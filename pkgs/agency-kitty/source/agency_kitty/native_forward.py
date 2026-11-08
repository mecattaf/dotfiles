"""Experimental native local client through a stock SSH Unix-socket forward.

Attachment never creates a replacement. Explicit fresh provisioning uses a
bounded NAS control endpoint and declared NAS Kitty assets. Python owns startup
and child lifetime only; native code and OpenSSH carry every terminal byte.

A forwarding-only SSH connection has no interactive TTY channel, so OpenSSH
10.4 does not apply its interactive keystroke timing obfuscation to this path.
This is an explicit prototype, not a policy-equivalent replacement default.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import time

from .cli import clean_environment, emit_metadata, source_session, transport as configured_transport
from .editor_ui import _die_with_parent, _private_directory, _stop, _termination_cleanup, _wait_ui, forward_argv
from .server import HOLDER_NAMESPACES, bounded_run
from .sessions import Session, SessionError, validate_cwd, validate_id
from .transport import ssh_command_argv


def existing_holder(transport, identity: str):
    identity = validate_id(identity)
    value = transport.run_json('describe', identity)
    if (not isinstance(value, dict) or value.get('id') != identity or value.get('host') != 'nas'
            or value.get('transport') != 'zmx' or value.get('mode') == 'direct' or value.get('resumable') is False
            or value.get('live') is not True or value.get('status') == 'closed'):
        raise SessionError('exact NAS holder is unavailable; this prototype never creates a replacement')
    session = source_session(value)
    health = transport.run_json('health')
    if (not isinstance(health, dict) or health.get('host') != 'nas' or health.get('holder') != 'zmx'
            or health.get('version') != session.holder_version):
        raise SessionError('NAS holder version did not match its canonical session')
    namespace = HOLDER_NAMESPACES.get(session.holder_version)
    directory = health.get('socket_dir')
    if (not namespace or not isinstance(directory, str) or not directory.startswith('/')
            or '..' in PurePosixPath(directory).parts or ':' in directory
            or any(ord(c) < 32 or ord(c) == 127 for c in directory)
            or PurePosixPath(directory).name != namespace
            or PurePosixPath(directory).parent.name != 'agency-kitty'):
        raise SessionError('NAS holder socket namespace did not match its version')
    address = str(PurePosixPath(directory) / identity)
    if len(os.fsencode(address)) > 107:
        raise SessionError('NAS holder Unix socket path exceeds its bound')
    return session, address


def client_environment(directory: Path) -> dict:
    env = clean_environment()
    env.update(ZMX_DIR=str(directory), ZMX_DIR_MODE='700', ZMX_LOG_MODE='600',
               ZMX_NO_DETACH_KEY='1', ZMX_ATTACH_ONLY='1', ZMX_SESSION='',
               ZMX_SESSION_PREFIX='', ZMX_TRACK_ENV='')
    return env


def control_request(transport, program: str, action: str, identity: str) -> dict:
    """One bounded noninteractive request; it never opens or reads local stdin."""
    if not program or any(ord(c) < 32 or ord(c) == 127 for c in program):
        raise SessionError('native forward control program is invalid')
    remote = [program, action, '--session', validate_id(identity), '--fleet-assets']
    result = bounded_run(ssh_command_argv(remote, ssh=transport.ssh), timeout=25, max_bytes=131072)
    if result.returncode:
        raise SessionError('NAS forward control failed: ' + result.stderr[-1000:].decode('utf-8', 'replace'))
    value = json.loads(result.stdout)
    if not isinstance(value, dict) or value.get('version') != 1:
        raise SessionError('NAS forward control receipt is invalid')
    return value


def typed_rebind(value: dict, identity: str, address: str) -> bytes:
    allowed = {'version', 'session', 'socket', 'rebind', 'requiresSshPty'}
    if (set(value) != allowed or value.get('version') != 1 or value.get('socket') != address
            or value.get('requiresSshPty') is not False or not isinstance(value.get('session'), dict)
            or value['session'].get('id') != identity or value['session'].get('live') is not True
            or not isinstance(value.get('rebind'), str) or len(value['rebind']) > 65536):
        raise SessionError('typed native rebind does not match the exact holder')
    wire = base64.b64decode(value['rebind'], validate=True)
    if len(wire) > 49152:
        raise SessionError('typed native rebind exceeds its bound')
    return wire


def run_forward(identity: str, *, client: str, transport=None, control_program: str | None = None,
                provision_directory: str | None = None) -> int:
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SessionError('native local attachment requires an interactive Kitty terminal')
    identity = validate_id(identity)
    transport = transport or configured_transport()
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
    if not runtime.is_absolute():
        raise SessionError('local runtime directory must be absolute')
    root = _private_directory(runtime / 'agency-native-forward')
    executable = shutil.which(client)
    if executable is None:
        raise SessionError('the matching compiled local holder client is unavailable')
    version = bounded_run([executable, 'version'], env=client_environment(_private_directory(root / 'version-probe')),
                          max_bytes=16384)
    first = version.stdout.decode('utf-8', 'replace').splitlines()[:1]
    words = first[0].split() if first else []
    if version.returncode or len(words) != 2 or words[0] != 'zmx' or words[1] not in HOLDER_NAMESPACES:
        raise SessionError('a qualified local native holder client is required')
    if provision_directory is not None:
        if control_program is None:
            raise SessionError('fresh provisioning requires the explicit typed control program')
        health = transport.run_json('health')
        if not isinstance(health, dict) or health.get('version') != words[1]:
            raise SessionError('local native client must match NAS before provisioning a new holder')
        session = Session(id=identity, cwd=validate_cwd(provision_directory))
        result = bounded_run(transport.create_argv(session), timeout=15, max_bytes=65536)
        if result.returncode:
            raise SessionError('NAS creation refused: ' + result.stderr[-1000:].decode('utf-8', 'replace'))
        provisioned = control_request(transport, control_program, 'provision', identity)
        if (set(provisioned) != {'version', 'session', 'provisionedWithoutSshPty', 'controlStdinIsTty', 'controlStdoutIsTty'}
                or provisioned.get('provisionedWithoutSshPty') is not True
                or provisioned.get('controlStdinIsTty') is not False or provisioned.get('controlStdoutIsTty') is not False
                or not isinstance(provisioned.get('session'), dict) or provisioned['session'].get('id') != identity
                or provisioned['session'].get('live') is not True):
            raise SessionError('headless provisioning receipt did not match the exact requested holder')
    session, remote_address = existing_holder(transport, identity)
    rebind_receipt = transport.run_json('rebind', identity)
    rebind = typed_rebind(rebind_receipt, identity, remote_address)
    if words != ['zmx', session.holder_version]:
        raise SessionError('local native client must match the exact NAS holder version')
    native = tunnel = None
    owner = os.getpid()
    with tempfile.TemporaryDirectory(prefix='f-', dir=root) as temporary, _termination_cleanup():
        directory = Path(temporary)
        address = directory / identity
        command = forward_argv(transport, address, remote_address)
        logpath = directory / 'ssh.log'
        with logpath.open('xb') as log:
            logpath.chmod(0o600)
            try:
                tunnel = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                          stderr=log, start_new_session=True,
                                          preexec_fn=lambda: _die_with_parent(owner))
                deadline = time.monotonic() + 10
                while not address.exists():
                    if tunnel.poll() is not None:
                        raise SessionError('SSH Unix forward failed: ' + logpath.read_bytes()[-1000:].decode('utf-8', 'replace'))
                    if time.monotonic() >= deadline:
                        raise SessionError('SSH Unix forward did not become ready')
                    time.sleep(0.01)
                info = address.lstat()
                if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise SessionError('local forwarded holder socket is not private and owned')
                emit_metadata(session)
                if rebind:
                    os.write(1, rebind)
                native = subprocess.Popen([executable, 'attach', identity], env=client_environment(directory),
                                          preexec_fn=lambda: _die_with_parent(owner))
                return _wait_ui(native, tunnel)
            finally:
                _stop(native)
                _stop(tunnel)


def main(argv=None) -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--session', required=True, type=validate_id)
    cli.add_argument('--client', default=os.environ.get('AGENCY_KITTY_ZMX_BINARY', 'zmx'))
    cli.add_argument('--control-program', default=os.environ.get('AGENCY_NATIVE_FORWARD_CONTROL'),
                     help='explicit bounded NAS control endpoint for provisioning and typed lifecycle rebind')
    cli.add_argument('--provision-directory', help='explicitly create this new NAS identity without a resident SSH PTY')
    args = cli.parse_args(argv)
    try:
        return run_forward(args.session, client=args.client, control_program=args.control_program,
                           provision_directory=args.provision_directory)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('agency-kitty native-forward prototype: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
