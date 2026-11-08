"""Bounded experimental NAS control endpoint; never a terminal-byte relay.

The authenticated SSH caller supplies one already-created canonical session
UUID. Provisioning launches only its declared fish bootstrap and disconnects
the temporary native client once the daemon exists. The daemon owns the sole
application PTY; this endpoint requires and allocates no SSH session PTY.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import selectors
import stat
import subprocess
import sys
import time

from .editor_ui import _stop
from .server import HolderBackend
from .sessions import SessionError, SessionStore, validate_id


def fleet_environment(env: dict) -> dict:
    """Require NAS-declared Kitty assets; never accept a client-supplied path."""
    from .server import fish_integration_env
    integration, terminfo = env.get('AGENCY_KITTY_FISH_INTEGRATION_DIR'), env.get('TERMINFO')
    if not integration or not terminfo or not Path(terminfo).is_absolute():
        raise SessionError('fleet bootstrap requires declared NAS Kitty fish integration and terminfo')
    info = (Path(terminfo) / 'x/xterm-kitty').lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid not in {0, os.getuid()} or info.st_mode & 0o022:
        raise SessionError('Kitty terminfo must be an owned, non-writable regular file')
    result = dict(env)
    # No remote SSH PTY exists, so OpenSSH does not supply a terminal type.
    result.update(TERM='xterm-kitty', COLORTERM='truecolor')
    return fish_integration_env(result)


def provision(identity: str, *, backend=None, store=None, fleet_assets=False) -> dict:
    identity = validate_id(identity)
    backend, store = backend or HolderBackend(), store or SessionStore()
    if fleet_assets:
        backend.env = fleet_environment(backend.env)
    backend.check_version()
    # Version checking creates/verifies the native namespace, but never a PTY.
    directory = backend.socket_dir
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SessionError('holder control directory must be private and owned')
    fd = os.open(directory / (identity + '.provision.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        session = store.get(identity)
        command, env = backend.prepare_attach(session, store)
        if env['ZMX_ATTACH_ONLY'] != '1':
            # The stock native attach CLI can bootstrap without a terminal.
            # Keep its stdin pipe open just until its exact socket is live;
            # then EOF detaches that short-lived client, leaving its sole app
            # PTY/daemon. Neither Python nor a resident extra PTY carries data.
            child = subprocess.Popen(command, cwd=session.cwd, env=env,
                                     stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.PIPE, start_new_session=True)
            try:
                deadline, detached, errors = time.monotonic() + 10, False, bytearray()
                os.set_blocking(child.stderr.fileno(), False)
                with selectors.DefaultSelector() as ready:
                    ready.register(child.stderr, selectors.EVENT_READ)
                    while True:
                        if not detached and identity in backend.names():
                            child.stdin.close(); child.stdin = None
                            detached, deadline = True, time.monotonic() + 5
                        for key, _ in ready.select(0.01):
                            chunk = os.read(key.fileobj.fileno(), 16385 - len(errors))
                            if not chunk:
                                ready.unregister(key.fileobj)
                            errors.extend(chunk)
                            if len(errors) > 16384:
                                raise SessionError('headless bootstrap stderr exceeds its bound')
                        if child.poll() is not None and not ready.get_map():
                            if not detached or child.returncode != 0:
                                raise SessionError('headless native bootstrap exited: ' + errors[-1000:].decode('utf-8', 'replace'))
                            break
                        if time.monotonic() >= deadline:
                            raise SessionError('headless native bootstrap timed out; its exact identity is retained')
            finally:
                _stop(child)
                for stream in (child.stdin, child.stderr):
                    if stream and not stream.closed:
                        stream.close()
        store.update(identity, status='active')
        return {'version': 1, 'session': backend.describe(store.get(identity)),
                'provisionedWithoutSshPty': True, 'controlStdinIsTty': os.isatty(0),
                'controlStdoutIsTty': os.isatty(1)}


def main(argv=None) -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('action', choices=('provision',))
    cli.add_argument('--session', required=True, type=validate_id)
    cli.add_argument('--fleet-assets', action='store_true', help='require NAS-declared immutable Kitty assets for an input-preserving plain SSH bootstrap')
    args = cli.parse_args(argv)
    try:
        value = provision(args.session, fleet_assets=args.fleet_assets)
        raw = json.dumps(value, separators=(',', ':')).encode()
        if len(raw) > 131072:
            raise SessionError('native forward control receipt exceeds its bound')
        sys.stdout.buffer.write(raw + b'\n')
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('agency-kitty native-forward control: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
