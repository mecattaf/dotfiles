"""Chrome --app viewer. Auth travels over SSH stdout, a private Unix socket and CDP pipe."""
import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import time
import subprocess
import sys
import uuid

from legacy_bootstrap import LaunchError, find_desktop, owned_socket, validate_url, verify_current_cli, request

NAS_HELPER = '/home/tom/.local/lib/agency-chat-window/nas_handoff.py'
CHROME = '/etc/profiles/per-user/tom/bin/google-chrome-stable'


def fetch(value):
    command = ['/run/current-system/sw/bin/ssh', '-T', '-S', 'none', '-o', 'ControlMaster=no',
        '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ForwardAgent=no',
        '-o', 'ConnectTimeout=8', '-o', 'Hostname=100.65.85.114', '-o', 'HostKeyAlias=nas',
        'nas', 'python3 ' + shlex.quote(NAS_HELPER)]
    try:
        result = subprocess.run(command, input=json.dumps(value), capture_output=True, text=True, timeout=45)
        if result.returncode or len(result.stdout) > 16384:
            raise LaunchError('NAS chat handoff failed; retry retains the same request identity')
        record = json.loads(result.stdout)
        validate_url(record['url'])
        if 'prompt' in value:
            expected = 'session-' + value['requestId']
            if record.get('requestId') != value['requestId'] or record.get('sessionId') != expected:
                raise LaunchError('NAS returned a different chat identity')
        return record
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError):
        raise LaunchError('Cannot complete the NAS chat handoff') from None


def open_chrome(record, runtime, tag, main=False, viewer=False):
    legacy = runtime / 'agency-chat-chrome.sock'
    path = legacy if main and legacy.exists() else runtime / 'agency-chat-chrome-v2.sock'
    if not path.exists():
        log_path = runtime / 'agency-chat-chrome-broker.log'
        fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'a') as log:
            subprocess.Popen([sys.executable, str(Path(__file__).with_name('chrome_broker.py'))],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(.05)
    identity = owned_socket(path)
    if identity is None:
        raise LaunchError('Chrome chat socket is not owned by this user')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(50)
        connection.connect(str(path))
        if owned_socket(path) != identity:
            raise LaunchError('Chrome chat socket changed during connection')
        payload = {'record': record, 'tag': tag, 'main': main}
        if path != legacy:
            payload['viewer'] = viewer
        connection.sendall(json.dumps(payload).encode() + b'\n')
        raw = bytearray()
        while b'\n' not in raw:
            chunk = connection.recv(4096)
            if not chunk or len(raw) + len(chunk) > 16384:
                raise LaunchError('Chrome chat response was incomplete')
            raw.extend(chunk)
        result = json.loads(raw)
        if result.get('ok') is not True:
            raise LaunchError('Chrome chat could not authenticate its viewer')
        return result['receipt']


def preflight():
    # Test the SAME client loopback route Chrome will use before a prompt can
    # create work on the NAS. A healthy remote Host alone is insufficient.
    from nas_handoff import Host
    record = fetch({'bootstrap': True})
    Host(record['url']).call('session/list', {})
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--new', action='store_true', help='read one native composer request from stdin')
    modes.add_argument('--main', action='store_true', help='read a main-viewer identity; the shell owns placement')
    modes.add_argument('--session', action='store_true', help='open an existing DSH session; no prompt or creation')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
        path, module = find_desktop(runtime)
        verify_current_cli(path, module)
        if not os.access(CHROME, os.X_OK):
            raise LaunchError('Google Chrome is unavailable')
        value = {'bootstrap': True}
        if args.new:
            raw = sys.stdin.buffer.read(65537)
            if len(raw) > 65536:
                raise LaunchError('Composer request is too large')
            value = json.loads(raw)
            from nas_handoff import validate_request
            validate_request(value)
        elif args.session:
            value = json.loads(sys.stdin.buffer.read(16385))
            if set(value) != {'sessionId', 'viewerId'} or str(uuid.UUID(value['viewerId'])) != value['viewerId']:
                raise LaunchError('Invalid chat viewer request')
        elif args.main:
            value = json.loads(sys.stdin.buffer.read(16385))
            if set(value) != {'viewerId'} or str(uuid.UUID(value['viewerId'])) != value['viewerId']:
                raise LaunchError('Invalid main viewer request')
        record = preflight()
        if (args.new or args.session) and not args.check:
            if record.get('chatLinks') is not True:
                raise LaunchError('Per-chat links await the staged DSH release')
            record = fetch({'sessionId': value['sessionId']} if args.session else value)
            if args.session and record.get('sessionId') != value['sessionId']:
                raise LaunchError('Chat viewer identity mismatch')
        if args.check:
            print('Chrome chat: Domicile, Chrome and NAS bootstrap reachable; no viewer opened')
        else:
            tag = 'agencychat' + (value['requestId'].replace('-', '') if args.new else value['viewerId'].replace('-', '') if (args.session or args.main) else uuid.uuid4().hex)
            receipt = open_chrome(record, runtime, tag, main=not (args.new or args.session), viewer=args.session)
            if not (args.new or args.session or args.main):
                # The shell resolves the native desktop identity to its current
                # SDK appId. No stale app-N is persisted across desktop mounts.
                request(path, {'type': 'send_shell', 'command': ['imagine', 'native-app', 'focus-tag', receipt['tag']]})
            print(json.dumps(receipt))
    except Exception:
        print('Chrome chat could not open; the composer draft is retained', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
