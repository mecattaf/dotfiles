"""Lifecycle metadata from the harness's exact transcript path, never latest-file guessing."""
from __future__ import annotations

import base64
import json
from pathlib import Path
import re


def user_var(name: str, value: str) -> bytes:
    if not re.fullmatch(r"[a-zA-Z0-9_]+", name):
        raise ValueError("invalid Kitty user-variable name")
    return b"\x1b]1337;SetUserVar=" + name.encode() + b"=" + base64.b64encode(value.encode()) + b"\x07"


def binding(payload: dict, harness: str, managed_session: str, inherited_id: str = "", *, invocation: str = "") -> bytes:
    if harness not in {"claude", "codex"}:
        raise ValueError("unsupported harness")
    if not managed_session:
        return b""  # globally configured hooks stay inert outside managed terminals
    event = payload.get("hook_event_name")
    if event not in {"SessionStart", "SessionEnd"}:
        return b""
    identity = payload.get("session_id")
    if not isinstance(identity, str) or not identity or len(identity) > 256:
        raise ValueError("harness lifecycle event lacks an exact session_id")
    if harness == "codex" and inherited_id and identity != inherited_id:
        return b""  # a background/subagent session cannot rebind its parent's UI
    event_data = {"harness": harness, "session_id": identity, "managed_session": managed_session}
    if invocation:
        event_data['invocation'] = invocation
    if event == "SessionStart":
        path = payload.get("transcript_path")
        if path is not None and (not isinstance(path, str) or not Path(path).is_absolute() or len(path) > 4096 or any(ord(c) < 32 for c in path)):
            raise ValueError("SessionStart must provide an absolute transcript_path")
        # Codex explicitly reports null for a non-local/ephemeral thread.
        # Bind the occupant while clearing an older session's history path.
        event_data["path"] = path
    key = "agency_harness_bind" if event == "SessionStart" else "agency_harness_unbind"
    return user_var(key, json.dumps(event_data, ensure_ascii=False))


def attention(payload: dict, harness: str, managed_session: str, inherited_id: str = "", *, invocation: str = "") -> bytes:
    """Turn completion/attention are distinct from process or session exit."""
    if harness not in {"claude", "codex"}:
        raise ValueError("unsupported harness")
    if not managed_session:
        return b""
    identity = payload.get("session_id")
    if not isinstance(identity, str) or not identity or len(identity) > 256:
        raise ValueError("harness event lacks an exact session_id")
    if harness == "codex" and inherited_id and identity != inherited_id:
        return b""
    event = payload.get("hook_event_name")
    if event == 'UserPromptSubmit':
        state = 'working'
    elif event == "Stop":
        state = "done"
    elif event == "Notification" and payload.get("notification_type") in {"permission_prompt", "idle_prompt", "elicitation_dialog"}:
        state = "waiting"
    else:
        return b""  # SessionEnd is not a completed turn
    data = {"managed_session": managed_session, "harness": harness, "session_id": identity,
            "state": state, "event": event}
    if invocation:
        data['invocation'] = invocation
    turn = payload.get("turn_id")
    if isinstance(turn, str) and len(turn) <= 256:
        data["turn_id"] = turn
    return user_var("agency_harness_event", json.dumps(data, ensure_ascii=False))


def _process_start(pid: int) -> str:
    # comm can itself contain spaces and parentheses; starttime is field22.
    raw = Path(f"/proc/{pid}/stat").read_text()
    return raw[raw.rfind(")") + 1:].split()[19]


def capture_terminal_context(owner_pid: int | None = None) -> dict[str, str]:
    """Capture once inside the managed remote shell, before launching a harness.

    Codex starts command hooks in a new session, without a controlling TTY.
    This token points to the original owned PTY and a still-live process that
    retains it. It does not confer authority over any other terminal/window.
    """
    import os
    import stat
    pid = os.getpid() if owner_pid is None else owner_pid
    if not isinstance(pid, int) or pid <= 0:
        raise ValueError("terminal owner PID must be positive")
    reference = Path(f"/proc/{pid}/fd/1")
    tty = os.readlink(reference)
    info = reference.stat()
    if (not re.fullmatch(r"/dev/pts/[0-9]+", tty) or not stat.S_ISCHR(info.st_mode)
            or info.st_uid != os.getuid()):
        raise ValueError("managed terminal must be an owned Linux PTY")
    return {"AGENCY_KITTY_TERMINAL": json.dumps({"version": 1, "pid": pid, "start": _process_start(pid), "tty": tty,
                       "device": info.st_rdev, "inode": info.st_ino}, separators=(",", ":"))}


def _open_terminal(context: str) -> int:
    import os
    import stat
    if not context or len(context) > 2048:
        raise ValueError("managed terminal context is missing or exceeds its bound")
    value = json.loads(context)
    if (not isinstance(value, dict) or value.get("version") != 1
            or not isinstance(value.get("pid"), int) or value["pid"] <= 0
            or not isinstance(value.get("start"), str) or not value["start"].isdigit()
            or not isinstance(value.get("tty"), str) or not re.fullmatch(r"/dev/pts/[0-9]+", value["tty"])):
        raise ValueError("invalid managed terminal context")
    fd = os.open(value["tty"], os.O_WRONLY | os.O_NOCTTY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        reference = Path(f"/proc/{value['pid']}/fd/1")
        owner = reference.stat()
        expected = (value.get("device"), value.get("inode"))
        if (not stat.S_ISCHR(info.st_mode) or info.st_uid != os.getuid() or not os.isatty(fd)
                or (info.st_rdev, info.st_ino) != expected or (owner.st_rdev, owner.st_ino) != expected
                or os.readlink(reference) != value["tty"] or _process_start(value["pid"]) != value["start"]):
            raise ValueError("managed terminal owner changed; no event was written")
        return fd
    except BaseException:
        os.close(fd)
        raise


def validate_terminal_context(context: str | None = None) -> None:
    import os
    fd = _open_terminal(os.environ.get("AGENCY_KITTY_TERMINAL", "") if context is None else context)
    os.close(fd)


def write_terminal(wire: bytes, context: str | None = None) -> None:
    """Write one bounded OSC event to the exact original PTY, never hook stdout."""
    import os
    import select
    import time
    if context is None:
        context = os.environ.get("AGENCY_KITTY_TERMINAL", "")
    if len(wire) > 32768:
        raise ValueError("harness terminal event exceeds its bound")
    if not wire:
        return
    if not context:
        # Claude may retain its controlling terminal. Codex requires the exact
        # captured context; a missing one fails visibly rather than guessing.
        with open("/dev/tty", "wb", buffering=0) as terminal:
            terminal.write(wire)
        return
    fd = _open_terminal(context)
    try:
        # The descriptor refers to the original PTY even if its numeric path
        # is later reused. A wedged/detached reader cannot block a hook forever.
        offset = 0
        deadline = time.monotonic() + 1
        while offset < len(wire):
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([], [fd], [], remaining)[1]:
                raise TimeoutError("managed terminal event write timed out")
            try:
                offset += os.write(fd, wire[offset:])
            except BlockingIOError:
                continue
    finally:
        os.close(fd)
