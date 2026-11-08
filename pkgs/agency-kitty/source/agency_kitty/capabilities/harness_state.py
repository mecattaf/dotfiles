"""Persist only typed lifecycle metadata so a fresh native client can rebind.

No terminal output, arbitrary escape sequences, transcript contents or prompt
text are stored. The original live PTY owner remains the authority.
"""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import json
import os
import stat
import time
import uuid

from ..sessions import SessionError, SessionStore, validate_id
from . import harness, harness_process

MAX_STATE_BYTES = 16384


def _private(fd: int, directory: bool = False) -> None:
    info = os.fstat(fd)
    expected = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if not expected or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("harness binding state must be private and owned by this user")


@contextmanager
def _directory(store: SessionStore, create: bool):
    root = os.open(store.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        _private(root, True)
        if create:
            try:
                os.mkdir("harness", mode=0o700, dir_fd=root)
            except FileExistsError:
                pass
        fd = os.open("harness", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
    finally:
        os.close(root)
    try:
        _private(fd, True)
        yield fd
    finally:
        os.close(fd)


def _read(fd: int, identity: str) -> dict | None:
    try:
        source = os.open(identity + ".json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except FileNotFoundError:
        return None
    with os.fdopen(source, "rb") as stream:
        _private(stream.fileno())
        raw = stream.read(MAX_STATE_BYTES + 1)
    if len(raw) > MAX_STATE_BYTES:
        raise ValueError("harness binding state exceeds its bound")
    value = json.loads(raw)
    if (not isinstance(value, dict) or value.get("version") != 1 or value.get("terminal_id") != identity
            or not isinstance(value.get("ended"), bool) or not isinstance(value.get("terminal_context"), str)):
        raise ValueError("invalid harness binding state identity")
    return value


def _write(fd: int, identity: str, value: dict) -> None:
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
    if len(data) > MAX_STATE_BYTES:
        raise ValueError("harness binding state exceeds its bound")
    temporary = ".binding-" + uuid.uuid4().hex
    output = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    try:
        with os.fdopen(output, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # Both names are relative to the already verified directory descriptor.
        os.replace(temporary, identity + ".json", src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=fd)
        except FileNotFoundError:
            pass


def _known(store: SessionStore, identity: str, context: str | None = None, *, ended=False) -> bool:
    from ..direct_registry import DirectRegistry
    try:
        session = store.get(identity)
    except SessionError as error:
        if str(error).startswith("unknown session:"):
            registry = DirectRegistry(store)
            if ended:
                return registry.known(identity)
            return registry.context_matches(identity,context) if context is not None else registry.get(identity) is not None
        raise
    return ended or session.status != 'closed'


def record_event(payload: dict, name: str, identity: str, *, store: SessionStore | None = None,
                 context: str | None = None, inherited_id: str = "", process_token: str | None = None) -> bool:
    """Write an explicit typed hook for a known durable or live direct identity."""
    validate_id(identity)
    store = store or SessionStore()
    event = payload.get("hook_event_name")
    binding = harness.binding(payload, name, identity, inherited_id)
    attention = harness.attention(payload, name, identity, inherited_id)
    if not binding and not attention:
        return False
    context = os.environ.get("AGENCY_KITTY_TERMINAL", "") if context is None else context
    if not _known(store,identity,context,ended=event=='SessionEnd'):
        return False
    if event!='SessionEnd':
        harness.validate_terminal_context(context)
    token = os.environ.get(harness_process.ENVIRONMENT,'') if process_token is None else process_token
    generation = harness_process.invocation(token,name)
    with _directory(store, True) as directory:
        lock = os.open(identity + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
        try:
            _private(lock)
            deadline = time.monotonic() + 1
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("harness binding state lock timed out")
                    time.sleep(0.01)
            current = _read(directory, identity)
            exact = (current is not None and current.get("harness") == name
                     and current.get("session_id") == payload["session_id"] and current.get("terminal_context") == context
                     and current.get('invocation','') == generation)
            if exact and current.get('process') is not None:
                parsed = harness_process.parse(token,name)
                exact = parsed is not None and all(current['process'].get(key)==value for key,value in parsed.items())
            if event == "SessionStart":
                value = {"version": 1, "terminal_id": identity, "harness": name,
                         "session_id": payload["session_id"], "path": payload.get("transcript_path"),
                         "terminal_context": context, "ended": False, "attention": None,
                         "invocation":generation,
                         "process":harness_process.attest(token,name)}
            elif event == "SessionEnd":
                if not exact:
                    return False  # an old exit cannot erase a newer harness
                value = {**current, "ended": True, "path": None, "attention": None}
            elif attention:
                if not exact or current.get("ended"):
                    return False
                value = {**current, "attention": {"hook_event_name": event,
                         "notification_type": payload.get("notification_type"),
                         "turn_id": payload.get("turn_id")}}
            else:
                return False
            _write(directory, identity, value)
            return True
        finally:
            os.close(lock)


def _saved(identity: str, store: SessionStore) -> dict | None:
    try:
        if not _known(store,identity):
            return None
        with _directory(store,False) as directory:
            value = _read(directory,identity)
        if value is not None:
            if not _known(store,identity,value['terminal_context']):
                return None
            harness.validate_terminal_context(value['terminal_context'])
        return value
    except FileNotFoundError:
        return None
    except (OSError,ValueError):
        return None


def status(identity: str, *, store: SessionStore | None = None) -> dict | None:
    """Metadata only; a saved working hook alone never proves a live agent."""
    validate_id(identity)
    value = _saved(identity,store or SessionStore())
    if value is None:
        return None
    name = value.get('harness')
    if name not in {'claude','codex'}:
        raise ValueError('invalid saved harness name')
    foreground = harness_process.foreground(value.get('process'),value['terminal_context'],name)
    if value['ended'] or foreground=='ended':
        state, active, verified = 'ended',False,True
    elif foreground=='foreground':
        attention = value.get('attention') or {}
        event = attention.get('hook_event_name')
        state = {'UserPromptSubmit':'working','Stop':'done','Notification':'waiting'}.get(event,'idle')
        active, verified = True,True
    else:
        state, active, verified = foreground,False if foreground=='background' else None,foreground!='unverified'
    return {'version':1,'harness':name,'state':state,'foreground':active,'verified':verified}


def can_target(identity: str, harness_session: str, *, invocation: str = "", store: SessionStore | None = None) -> bool:
    """Explicit gesture validation, independent of possibly stale local tags."""
    validate_id(identity)
    value = _saved(identity,store or SessionStore())
    return (isinstance(invocation,str) and len(invocation)==64
            and value is not None and not value['ended'] and value.get('session_id')==harness_session
            and value.get('invocation')==invocation
            and harness_process.foreground(value.get('process'),value['terminal_context'],value.get('harness'))=='foreground')


def read_rebind(identity: str, *, store: SessionStore | None = None) -> bytes:
    """Return freshly encoded typed OSC; never replay recorded terminal bytes."""
    validate_id(identity)
    store = store or SessionStore()
    try:
        session = store.get(identity)
        if session.status == "closed":
            return b""
        with _directory(store, False) as directory:
            value = _read(directory, identity)
    except FileNotFoundError:
        return b""
    except SessionError as error:
        if str(error).startswith("unknown session:"):
            return b""
        raise
    if value is None or value.get("ended"):
        return b""
    try:
        harness.validate_terminal_context(value.get("terminal_context", ""))
    except (OSError, ValueError):
        return b""  # original shell/PTY ended; do not bind a recycled pathname
    if value.get('process') is not None and harness_process.foreground(value['process'],value['terminal_context'],value.get('harness'))!='foreground':
        return b''
    payload = {"session_id": value.get("session_id"), "transcript_path": value.get("path"),
               "hook_event_name": "SessionStart"}
    generation = value.get('invocation','')
    wire = harness.binding(payload, value.get("harness"), identity, invocation=generation)
    attention = value.get("attention")
    if attention is not None:
        if not isinstance(attention, dict):
            raise ValueError("invalid saved harness attention state")
        wire += harness.attention({**attention, "session_id": value["session_id"]}, value["harness"], identity, invocation=generation)
    return wire
