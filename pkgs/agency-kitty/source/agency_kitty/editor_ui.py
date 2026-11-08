"""Local native Neovim UI over one SSH-forwarded retained NAS Unix socket.

The SSH tunnel carries Neovim RPC. It never carries a remote terminal UI or
implements a terminal parser. The NAS directory server owns all editor state.
"""
from __future__ import annotations

from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time

from .sessions import SessionError, validate_cwd, validate_id
from .transport import NAS_HOST, SSH_OPTIONS, SSHTransport, ssh_command_argv


def validate_record(raw: bytes) -> dict:
    if len(raw) > 65536:
        raise SessionError('NAS editor receipt exceeds its bound')
    record = json.loads(raw)
    if not isinstance(record, dict):
        raise SessionError('NAS editor receipt must be an object')
    directory = validate_cwd(record.get('directory', ''))
    if '..' in PurePosixPath(directory).parts:
        raise SessionError('NAS editor directory must be canonical')
    identity = hashlib.sha256(directory.encode()).hexdigest()[:24]
    address = record.get('socket')
    if (record.get('identity') != identity or type(record.get('pid')) is not int or record['pid'] <= 0
            or record.get('ready') != 1 or not isinstance(address, str)
            or not PurePosixPath(address).is_absolute() or '..' in PurePosixPath(address).parts
            or PurePosixPath(address).parent.name != 'dsh-editor'
            or PurePosixPath(address).name != identity + '.sock'
            or len(address.encode()) > 103 or ':' in address
            or any(ord(char) < 32 or ord(char) == 127 for char in address)):
        raise SessionError('NAS editor receipt has an invalid identity, socket or process')
    return record


def ensure_argv(transport: SSHTransport, directory: str, files: list[str]) -> list[str]:
    directory = validate_cwd(directory)
    if not isinstance(files, list) or len(files) > 64 or any(not isinstance(path, str) or len(path.encode()) > 4096
                              or any(ord(char) < 32 or ord(char) == 127 for char in path) for path in files):
        raise SessionError('invalid editor file list')
    # This is an ordinary SSH control request. TERM describes the actual local
    # Kitty UI while the retained headless server has no initial terminal.
    return ssh_command_argv(['env', 'TERM=xterm-kitty', 'dsh-editor', '--socket-only', '--json',
                             '--directory', directory, '--', *files], ssh=transport.ssh)


def forward_argv(transport: SSHTransport, local_socket: Path, remote_socket: str) -> list[str]:
    local = str(local_socket)
    if not local_socket.is_absolute() or ':' in local or len(local.encode()) > 103:
        raise SessionError('local editor socket path is invalid or too long')
    if (not remote_socket.startswith('/') or ':' in remote_socket
            or any(ord(char) < 32 or ord(char) == 127 for char in remote_socket)):
        raise SessionError('remote editor socket path is invalid')
    # ClearAllForwardings=yes would also erase this deliberately requested Unix
    # forward. OpenSSH uses the first option, so only this command overrides it;
    # the NAS address/key, no-agent and no-ControlMaster policy is unchanged.
    return [transport.ssh, '-N', '-n', '-o', 'ClearAllForwardings=no',
            '-o', 'ExitOnForwardFailure=yes', '-o', 'StreamLocalBindUnlink=no',
            *SSH_OPTIONS, '-L', local + ':' + remote_socket, '--', NAS_HOST]


def _private_directory(path: Path) -> Path:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SessionError('local editor runtime directory must be private and owned')
    return path


def _die_with_parent(owner: int):
    # Linux/Domicile: an abruptly closed Kitty must not orphan its SSH tunnel.
    libc = ctypes.CDLL(None, use_errno=True)
    if os.getppid() != owner or libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0 or os.getppid() != owner:
        os._exit(125)


@contextmanager
def _termination_cleanup():
    previous = {}
    def terminate(number, frame):
        raise SystemExit(128 + number)
    try:
        for number in (signal.SIGHUP, signal.SIGTERM):
            previous[number] = signal.signal(number, terminate)
        yield
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


def _stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait(timeout=5)


def _wait_ui(ui, tunnel, lease=None):
    """Block on Linux child lifecycle events; no recurring idle/key timer."""
    descriptors = []
    try:
        with selectors.DefaultSelector() as ready:
            for process, kind in ((ui, 'ui'), (tunnel, 'tunnel'), (lease.process if lease else None, 'lease')):
                if process is None:
                    continue
                descriptor = os.pidfd_open(process.pid)
                descriptors.append(descriptor)
                ready.register(descriptor, selectors.EVENT_READ, kind)
            while True:
                ready.select()
                if tunnel.poll() is not None:
                    raise SessionError('Nvim RPC SSH disconnected; the NAS editor is retained')
                if lease and lease.process.poll() is not None:
                    raise SessionError('NAS vi was cancelled or its original terminal ended')
                if ui.poll() is not None:
                    return ui.wait()
    finally:
        for descriptor in descriptors:
            os.close(descriptor)


class RequestLease:
    """An SSH lifecycle connection, completely separate from Nvim RPC bytes."""
    def __init__(self, transport, session, request, directory, logfile):
        self.session, self.request = validate_id(session), validate_id(request)
        self.log = logfile.open('xb')
        logfile.chmod(0o600)
        owner = os.getpid()
        command = ssh_command_argv([transport.remote_program, 'editor-lease', '--session', session,
                                     '--request', request], ssh=transport.ssh)
        self.process = None
        try:
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.log, start_new_session=True,
                                            preexec_fn=lambda: _die_with_parent(owner))
            raw = bytearray()
            deadline = time.monotonic() + 15
            while b'\n' not in raw:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                    raise SessionError('NAS editor request lease timed out')
                chunk = os.read(self.process.stdout.fileno(), 4096)
                if not chunk:
                    raise SessionError('NAS editor request was refused: ' + logfile.read_bytes()[-1000:].decode('utf-8', 'replace'))
                raw.extend(chunk)
                if len(raw) > 16384:
                    raise SessionError('NAS editor request receipt exceeds its bound')
            value = json.loads(raw)
            if (not isinstance(value, dict) or set(value) != {'version', 'session', 'request', 'directory', 'files'}
                    or value['version'] != 1 or value['session'] != session or value['request'] != request
                    or value['directory'] != directory):
                raise SessionError('NAS editor request receipt did not match the exact source')
            ensure_argv(transport, value['directory'], value['files'])
            self.files = value['files']
        except BaseException:
            self.close()
            raise

    def finish(self, status):
        if self.process.poll() is not None:
            raise SessionError('NAS editor request disconnected before completion')
        self.process.stdin.write(json.dumps({'status': status}).encode() + b'\n')
        self.process.stdin.flush()
        self.process.stdin.close()
        if self.process.wait(timeout=5):
            raise SessionError('NAS editor request completion was not acknowledged')

    def close(self):
        _stop(self.process)
        if self.process:
            for stream in (self.process.stdin, self.process.stdout):
                if stream and not stream.closed:
                    stream.close()
        self.log.close()


def run_local_ui(directory: str, files: list[str], *, transport: SSHTransport | None = None,
                 nvim: str = 'nvim', session: str | None = None, request: str | None = None) -> int:
    """Ensure one NAS editor, forward its socket, run the local TUI, retain NAS WIP."""
    from .server import bounded_run
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SessionError('local editor UI requires an interactive Kitty terminal')
    transport = transport or SSHTransport()
    directory = validate_cwd(directory)
    if bool(session) != bool(request):
        raise SessionError('NAS editor callback requires both session and request identity')
    version = bounded_run([nvim, '--version'], timeout=5, max_bytes=16384)
    matched = re.match(rb'NVIM v(\d+)\.(\d+)\.(\d+)', version.stdout)
    if version.returncode or matched is None:
        raise SessionError('a local Neovim installation is required')
    local_version = tuple(int(value) for value in matched.groups())
    if local_version < (0, 12, 0):
        raise SessionError('local Neovim must be at least 0.12 for the native UI')
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
    if not runtime.is_absolute():
        raise SessionError('local runtime directory must be absolute')
    root = _private_directory(runtime / 'agency-editor-ui')
    tunnel = ui = lease = None
    owner = os.getpid()
    marked = bool(os.environ.get('KITTY_WINDOW_ID'))
    with tempfile.TemporaryDirectory(prefix='ui-', dir=root) as temporary, _termination_cleanup():
        temporary = Path(temporary)
        address = temporary / 'nvim.sock'
        logfile = temporary / 'ssh.log'
        fd = os.open(logfile, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, 'wb') as log:
            try:
                if request:
                    lease = RequestLease(transport, session, request, directory, temporary / 'lease.log')
                    files = lease.files
                created = bounded_run(ensure_argv(transport, directory, files), timeout=25, max_bytes=65536)
                if created.returncode:
                    raise SessionError('NAS editor request failed: ' + created.stderr.decode('utf-8', 'replace')[-1000:])
                record = validate_record(created.stdout)
                tunnel = subprocess.Popen(forward_argv(transport, address, record['socket']),
                                          stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                          start_new_session=True, preexec_fn=lambda: _die_with_parent(owner))
                deadline = time.monotonic() + 12
                probe_expression = "json_encode({'pid':getpid(),'ready':get(g:,'dsh_editor_ready',0),'version':api_info().version})"
                while True:
                    if tunnel.poll() is not None:
                        raise SessionError('editor SSH tunnel exited: ' + logfile.read_bytes()[-1000:].decode('utf-8', 'replace'))
                    if address.exists():
                        probe = bounded_run([nvim, '--headless', '-u', 'NONE', '--server', str(address),
                                             '--remote-expr', probe_expression], timeout=3, max_bytes=16384)
                        if probe.returncode == 0:
                            value = json.loads(probe.stdout)
                            if value.get('pid') != record['pid'] or value.get('ready') != 1:
                                raise SessionError('forwarded editor process did not match the NAS receipt')
                            remote_version = value.get('version', {})
                            if (remote_version.get('major'), remote_version.get('minor')) != local_version[:2]:
                                raise SessionError('local and NAS Neovim major/minor versions must match')
                            break
                    if time.monotonic() >= deadline:
                        raise SessionError('editor SSH socket did not become ready')
                    time.sleep(0.05)
                if marked:
                    os.write(1, b'\x1b]1337;SetUserVar=nvim=MQ==\x1b\\')
                ui = subprocess.Popen([nvim, '-u', 'NONE', '--server', str(address), '--remote-ui'],
                                      preexec_fn=lambda: _die_with_parent(owner))
                status = _wait_ui(ui, tunnel, lease)
                if tunnel.poll() is not None:
                    raise SessionError('Nvim RPC SSH disconnected; the NAS editor is retained')
                status = status if status >= 0 else min(255, 128 - status)
                if lease:
                    lease.finish(status)
                return status
            except (SystemExit, KeyboardInterrupt) as interrupted:
                # An explicit local window close is an editor exit, with shell
                # status129. An SSH lease/RPC failure instead leaves vi pending
                # for fresh attach; it never completes a following shell command.
                status = interrupted.code if isinstance(interrupted, SystemExit) and type(interrupted.code) is int else 130
                if lease and (tunnel is None or tunnel.poll() is None) and lease.process.poll() is None:
                    try:
                        lease.finish(max(0, min(255, status)))
                    except (OSError, ValueError, subprocess.SubprocessError):
                        pass  # expected teardown race: retain pending request
                raise
            finally:
                _stop(ui)
                _stop(tunnel)
                if lease:
                    lease.close()
                if marked:
                    try:
                        os.write(1, b'\x1b]1337;SetUserVar=nvim=\x1b\\')
                    except OSError:
                        pass  # the exact Kitty PTY may already have closed
