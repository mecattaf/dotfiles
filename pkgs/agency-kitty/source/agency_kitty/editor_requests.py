"""One blocking NAS vi request and an exclusive, typed UI lifecycle lease.

Only directory/files and completion status cross this socket. Editor RPC uses
its own native SSH Unix forward; no terminal bytes or remote-control commands
are accepted here. The retained NAS PTY and request PID remain the authority.
"""
from __future__ import annotations

import json
import os
from pathlib import Path, PurePosixPath
import selectors
import socket
import stat
import struct
import sys
import uuid
from urllib.parse import quote

from .capabilities import harness
from .sessions import SessionError, validate_cwd, validate_id

MAX_RECORD = 16384
MAX_MESSAGE = 1024


def _root() -> Path:
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
    if not runtime.is_absolute():
        raise SessionError('editor request runtime must be absolute')
    path = runtime / 'agency-editor-requests'
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SessionError('editor request runtime must be private and owned')
    return path


def _files(directory: str, files: list[str]) -> list[str]:
    if not isinstance(files, list) or len(files) > 64:
        raise SessionError('editor request accepts at most 64 files')
    result = []
    for value in files:
        if (not isinstance(value, str) or not value or len(os.fsencode(value)) > 4096
                or any(ord(c) < 32 or 127 <= ord(c) < 160 for c in value)):
            raise SessionError('invalid editor request file')
        result.append(os.path.normpath(os.path.join(directory, value)))
    return result


def _read(identity: str) -> dict | None:
    path = _root() / (validate_id(identity) + '.json')
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SessionError('editor request record must be private and owned')
        raw = stream.read(MAX_RECORD + 1)
    if len(raw) > MAX_RECORD:
        raise SessionError('editor request record exceeds its bound')
    value = json.loads(raw)
    validate_record(value, identity)
    return value


def validate_record(value: dict, identity: str | None = None) -> dict:
    if (not isinstance(value, dict) or value.get('version') != 1
            or type(value.get('pid')) is not int or value['pid'] <= 0
            or not isinstance(value.get('start'), str) or not value['start'].isdigit()
            or not isinstance(value.get('terminal_context'), str)):
        raise SessionError('invalid editor request record')
    validate_id(value.get('session'))
    validate_id(value.get('request'))
    if identity is not None and value['session'] != identity:
        raise SessionError('editor request belongs to a different terminal')
    directory = validate_cwd(value.get('directory'))
    if directory != value['directory'] or '..' in PurePosixPath(directory).parts:
        raise SessionError('editor request directory is not canonical')
    if _files(directory, value.get('files')) != value['files']:
        raise SessionError('editor request files must be absolute and normalized')
    return value


def _alive(value: dict) -> bool:
    try:
        process = Path(f'/proc/{value["pid"]}/stat').read_text()
        if process[process.rfind(')') + 1:].split()[0] in {'Z', 'X'}:
            return False
        if harness._process_start(value['pid']) != value['start']:
            return False
        if Path(f'/proc/{value["pid"]}').stat().st_uid != os.getuid():
            return False
        harness.validate_terminal_context(value['terminal_context'])
        info = (_root() / (value['session'] + '.sock')).lstat()
        return stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o077
    except (OSError, ValueError):
        return False


def event(value: dict) -> bytes:
    # The file list stays on NAS. A native callback claims this exact request
    # before any editor process or filesystem operation is allocated locally.
    payload = {key: value[key] for key in ('version', 'session', 'request', 'directory')}
    return harness.user_var('agency_editor_request', json.dumps(payload, ensure_ascii=False, separators=(',', ':')))


def read_rebind(identity: str) -> bytes:
    value = _read(identity)
    if value is None or not _alive(value):
        return b''
    # This is freshly encoded state owned by the still-live request/PTY, not a
    # replay of terminal bytes. It precedes the event so a new Kitty starts at
    # the actual pending directory before the holder restores its screen.
    cwd = b'\x1b]7;file://nas' + quote(value['directory'], safe='/').encode() + b'\x1b\\'
    return harness.user_var('agency_directory', value['directory']) + cwd + event(value)


def _send(connection: socket.socket, value: dict) -> None:
    raw = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode() + b'\n'
    if len(raw) > MAX_RECORD:
        raise SessionError('editor lifecycle message exceeds its bound')
    connection.sendall(raw)


def _line(connection: socket.socket, limit: int = MAX_MESSAGE) -> dict:
    raw = bytearray()
    while b'\n' not in raw:
        chunk = connection.recv(min(4096, limit + 1 - len(raw)))
        if not chunk:
            raise EOFError('editor lifecycle connection ended')
        raw.extend(chunk)
        if len(raw) > limit:
            raise SessionError('editor lifecycle message exceeds its bound')
    if raw.count(b'\n') != 1 or not raw.endswith(b'\n'):
        raise SessionError('editor lifecycle accepts one JSON line')
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise SessionError('editor lifecycle message must be an object')
    return value


def request(directory: str, files: list[str], *, identity: str | None = None) -> int:
    identity = identity or os.environ.get('AGENCY_KITTY_SESSION')
    if os.environ.get('AGENCY_KITTY_HOST') != 'nas' or not identity:
        raise SessionError('NAS vi requires a managed Kitty NAS terminal; open agency-kitty desktop terminal on the seat, or use nvim explicitly')
    identity = validate_id(identity)
    context = os.environ.get('AGENCY_KITTY_TERMINAL', '')
    try:
        harness.validate_terminal_context(context)
    except (OSError, ValueError) as error:
        raise SessionError('NAS vi terminal binding is unavailable; reopen the managed Kitty NAS terminal, or use nvim explicitly') from error
    directory = str(Path(validate_cwd(directory)).resolve(strict=True))
    if not Path(directory).is_dir():
        raise SessionError('NAS editor directory is unavailable')
    root = _root()
    pending = _read(identity)
    if pending is not None and _alive(pending):
        raise SessionError('this terminal already has a pending editor request')
    value = {'version': 1, 'session': identity, 'request': str(uuid.uuid4()), 'directory': directory,
             'files': _files(directory, files), 'pid': os.getpid(), 'start': harness._process_start(os.getpid()),
             'terminal_context': context}
    raw = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
    if len(raw) > MAX_RECORD:
        raise SessionError('editor request exceeds its bound')
    address = root / (identity + '.sock')
    record = root / (identity + '.json')
    if len(os.fsencode(address)) > 103:
        raise SessionError('editor request socket path is too long')
    # Serialize creation, including a background vi racing the foreground one.
    import fcntl
    lock = os.open(root / (identity + '.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    listener = active = None
    with os.fdopen(lock, 'wb') as locked:
        try:
            fcntl.flock(locked, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise SessionError('this terminal already has a pending editor request') from error
        try:
            if address.exists():
                info = address.lstat()
                if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
                    raise SessionError('refusing to replace an unowned editor socket')
                address.unlink()
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(str(address)); address.chmod(0o600); listener.listen(4)
            temporary = root / ('.request-' + value['request'])
            descriptor = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, 'wb') as output:
                output.write(raw); output.flush(); os.fsync(output.fileno())
            os.replace(temporary, record)
            harness.write_terminal(event(value), context)
            with selectors.DefaultSelector() as ready:
                ready.register(listener, selectors.EVENT_READ, 'new')
                while True:
                    for key, _ in ready.select():
                        if key.data == 'new':
                            connection, _ = listener.accept()
                            connection.settimeout(2)
                            try:
                                credentials = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i'))
                                _, uid, _ = struct.unpack('3i', credentials)
                                claim = _line(connection)
                                if (uid != os.getuid() or claim != {'version': 1, 'session': identity, 'request': value['request']}
                                        or not _alive(value)):
                                    raise SessionError('stale editor request or terminal owner')
                                if active is not None:
                                    _send(connection, {'error': 'editor request already has a local UI'})
                                    connection.close(); continue
                                _send(connection, {k: value[k] for k in ('version', 'session', 'request', 'directory', 'files')})
                                active = connection
                                ready.register(active, selectors.EVENT_READ, 'completion')
                            except (OSError, ValueError, EOFError):
                                connection.close()
                        else:
                            try:
                                completion = _line(active)
                                status = completion.get('status')
                                if (set(completion) != {'version', 'session', 'request', 'status'}
                                        or completion['version'] != 1 or completion['session'] != identity
                                        or completion['request'] != value['request'] or type(status) is not int or not 0 <= status <= 255):
                                    raise SessionError('invalid editor completion')
                                _send(active, {'complete': status})
                                return status
                            except (OSError, ValueError, EOFError):
                                # A disconnected view releases only its lease.
                                # The original vi still waits and NAS WIP lives.
                                ready.unregister(active); active.close(); active = None
        finally:
            if active is not None: active.close()
            if listener is not None: listener.close()
            current = _read(identity)
            if current and current['request'] == value['request']:
                record.unlink(missing_ok=True)
                address.unlink(missing_ok=True)
            try:
                harness.write_terminal(harness.user_var('agency_editor_request', ''), context)
            except (OSError, ValueError, TimeoutError):
                pass  # original direct SSH PTY may have disappeared


def lease(identity: str, request_id: str) -> int:
    """SSH lifecycle endpoint: one claim/receipt and one bounded completion."""
    identity, request_id = validate_id(identity), validate_id(request_id)
    value = _read(identity)
    if value is None or value['request'] != request_id or not _alive(value):
        raise SessionError('editor request is unavailable or its original terminal ended')
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(3)
        connection.connect(str(_root() / (identity + '.sock')))
        _send(connection, {'version': 1, 'session': identity, 'request': request_id})
        receipt = _line(connection, MAX_RECORD)
        if 'error' in receipt:
            raise SessionError(receipt['error'])
        print(json.dumps(receipt, ensure_ascii=False, separators=(',', ':')), flush=True)
        connection.settimeout(None)
        with selectors.DefaultSelector() as ready:
            ready.register(sys.stdin, selectors.EVENT_READ, 'client')
            ready.register(connection, selectors.EVENT_READ, 'request')
            for key, _ in ready.select():
                if key.data == 'request':
                    return 130  # NAS user cancelled vi / original owner ended
                raw = sys.stdin.buffer.readline(MAX_MESSAGE + 1)
                if not raw:
                    return 0  # SSH loss releases lease, leaves request pending
                if len(raw) > MAX_MESSAGE or not raw.endswith(b'\n'):
                    raise SessionError('editor completion exceeds its bound')
                completion = json.loads(raw)
                if (not isinstance(completion, dict) or set(completion) != {'status'}
                        or type(completion['status']) is not int or not 0 <= completion['status'] <= 255):
                    raise SessionError('invalid local editor exit status')
                _send(connection, {'version': 1, 'session': identity, 'request': request_id, **completion})
                acknowledgement = _line(connection)
                return 0 if acknowledgement == {'complete': completion['status']} else 1
    return 1
