"""Read-only NAS metadata multiplexer. Parent stdin owns its lifetime."""
import argparse
import json
import os
from pathlib import Path
import select
import signal
import stat
import subprocess
import sys
import time
import threading
import queue

from native_terminal.control import request as terminal_request, route
from catalogue_logs import diagnostic

HERE = Path(__file__).resolve().parent
SOCKET = Path('/home/tom/.local/state/agency-web/native-terminal/pty.sock')
MAX_FRAME = 8 * 1024 * 1024


def inventory(session_ids, path=SOCKET, server='agency-web'):
    info = path.lstat()
    parent = path.parent.lstat()
    if (info.st_uid != os.getuid() or not stat.S_ISSOCK(info.st_mode) or info.st_mode & 0o077
            or parent.st_uid != os.getuid() or not stat.S_ISDIR(parent.st_mode) or parent.st_mode & 0o077):
        raise ValueError('Untrusted terminal carrier')
    terminals = []
    epoch = None
    for session in session_ids:
        value = terminal_request(str(path), {'version': 1, 'server': server, 'session': session, 'operation': 'inventory'})
        if value.get('server') != server or value.get('session') != session:
            raise ValueError('Terminal inventory identity mismatch')
        if epoch is not None and value['epoch'] != epoch:
            raise ValueError('Terminal Host changed during inventory')
        epoch = value['epoch']
        for terminal in value['terminals']:
            terminals.append({'route': route(server, epoch, session, terminal['id']), 'title': terminal.get('title') or 'Terminal'})
            if len(terminals) > 4096:
                raise ValueError('Terminal inventory exceeds its limit')
    return {'type': 'terminals', 'available': True, 'terminals': terminals}


def check_terminal(value, path=SOCKET, server='agency-web'):
    expected = route(value['server'], value['epoch'], value['session'], value['terminal'])
    if value != {key: expected[key] for key in ('version', 'server', 'epoch', 'session', 'terminal', 'windowClass')} or value['server'] != server:
        raise ValueError('Terminal route mismatch')
    items = inventory([value['session']], path, server)['terminals']
    if not any(item['route']['epoch'] == value['epoch'] and item['route']['terminal'] == value['terminal'] for item in items):
        raise ValueError('Terminal route is stale or unavailable')
    return value


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':')), flush=True)


def watch(active=None, path=SOCKET, server='agency-web'):
    command = [sys.executable, str(HERE / 'attention-reader.py'), '--watch']
    if active is not None:
        command += ['--active', str(active)]
    log = diagnostic('catalogue-nas')
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=log, start_new_session=True)
    buffer = b''
    sessions = set()
    last_terminals = None
    poll_at = 0
    running = True
    results = queue.Queue(maxsize=1)
    polling = False
    def poll(identities):
        try:
            value = inventory(identities, path, server)
        except Exception:
            value = {'type': 'terminals', 'available': False}
        results.put((set(identities), value))
    def stop(*_):
        nonlocal running
        running = False
    previous = signal.signal(signal.SIGTERM, stop)
    try:
        while running and child.poll() is None:
            readable, _, _ = select.select([sys.stdin.buffer, child.stdout], [], [], .5)
            if sys.stdin.buffer in readable:
                if not os.read(sys.stdin.fileno(), 1):
                    return 0
                raise ValueError('Unexpected control input')
            if child.stdout in readable:
                data = os.read(child.stdout.fileno(), 65536)
                if not data:
                    break
                buffer += data
                if len(buffer) > MAX_FRAME:
                    raise ValueError('Metadata frame exceeds its limit')
                while b'\n' in buffer:
                    raw, buffer = buffer.split(b'\n', 1)
                    value = json.loads(raw)
                    if value.get('type') == 'snapshot':
                        sessions = set(value['sessions'])
                        poll_at = 0
                    elif value.get('type') == 'upsert':
                        if value['session']['sessionId'] not in sessions:
                            sessions.add(value['session']['sessionId']); poll_at = 0
                    elif value.get('type') == 'remove':
                        sessions.discard(value['sessionId']); poll_at = 0
                    elif value.get('type') == 'unavailable':
                        sessions.clear(); poll_at = 0
                    if len(sessions) > 4096:
                        raise ValueError('Catalogue exceeds its limit')
                    emit(value)
            if not results.empty():
                polled, value = results.get_nowait(); polling = False
                if polled == sessions and value != last_terminals:
                    emit(value); last_terminals = value
            if time.monotonic() >= poll_at and not polling:
                # A missing/slow terminal carrier must not block attention or
                # stdin EOF cleanup. This worker owns no subprocess or PTY.
                threading.Thread(target=poll, args=(sorted(sessions),), daemon=True).start()
                polling = True; poll_at = time.monotonic() + 10
        emit({'type': 'unavailable'})
        return 1
    finally:
        signal.signal(signal.SIGTERM, previous)
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(3)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait(3)
        log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-terminal', action='store_true')
    # Explicit fixture arguments; the installed client supplies none.
    parser.add_argument('--active', type=Path)
    parser.add_argument('--socket', type=Path, default=SOCKET)
    parser.add_argument('--server', default='agency-web')
    args = parser.parse_args()
    try:
        if args.check_terminal:
            value = json.loads(sys.stdin.buffer.read(16385))
            emit(check_terminal(value, args.socket, args.server))
            return 0
        return watch(args.active, args.socket, args.server)
    except Exception:
        print('Chat metadata unavailable', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
