"""Attach an existing DSH terminal from a local catalogue click; never allocate."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import fcntl
from catalogue_client import SSH
from catalogue_logs import diagnostic
from legacy_bootstrap import find_desktop, verify_current_cli
from native_terminal.control import route

REMOTE = '/home/tom/.local/lib/agency-chat-window'


def main():
    value = json.loads(sys.stdin.buffer.read(16385))
    expected = route(value['server'], value['epoch'], value['session'], value['terminal'])
    if value != {key: expected[key] for key in ('version', 'server', 'epoch', 'session', 'terminal', 'windowClass')} or value['server'] != 'agency-web':
        raise ValueError('Invalid terminal route')
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    path, module = find_desktop(runtime); verify_current_cli(path, module)
    checked = subprocess.run([*SSH, 'python3 ' + REMOTE + '/catalogue_nas.py --check-terminal'],
        input=json.dumps(value), capture_output=True, text=True, timeout=20)
    if checked.returncode or json.loads(checked.stdout) != value:
        raise ValueError('Terminal route unavailable')
    directory = runtime / 'agency-chat-terminals'; directory.mkdir(mode=0o700, exist_ok=True)
    with os.fdopen(os.open(directory / (value['windowClass'] + '.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # The catalogue focuses known windows. Check the current native list
        # again under a route lock to close the double-click race.
        receipt = directory / (value['windowClass'] + '.json')
        if receipt.exists():
            old = json.loads(receipt.read_text())
            try:
                if Path('/proc', str(old['pid']), 'stat').read_text().split(') ', 1)[1].split()[19] == old['start']:
                    print(json.dumps(value)); return
            except OSError:
                pass
        peer = [*SSH]; peer[peer.index('-T')] = '-tt'
        arguments = ['python3', REMOTE + '/native_terminal/view.py', '--socket', '/home/tom/.local/state/agency-web/native-terminal/pty.sock']
        for key in ('server', 'epoch', 'session', 'terminal'):
            arguments += ['--' + key, value[key]]
        command = [*peer, shlex.join(arguments)]
        with diagnostic('terminal-viewers') as log:
            child = subprocess.Popen(['/etc/profiles/per-user/tom/bin/kitty', '--class', value['windowClass'],
                '--title', 'DSH terminal', '-e', *command], stdin=subprocess.DEVNULL,
                stdout=log, stderr=log, start_new_session=True)
        start = Path('/proc', str(child.pid), 'stat').read_text().split(') ', 1)[1].split()[19]
        from nas_handoff import save
        save(receipt, {'pid': child.pid, 'start': start})
    print(json.dumps(value))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('DSH terminal unavailable; no replacement was allocated', file=sys.stderr)
        raise SystemExit(1)
