"""Client metadata relay. No provider state, browser bootstrap or desktop commands."""
import json
import os
import re
from pathlib import Path
import select
import signal
import subprocess
import sys
import time

from nas_handoff import read_private, HandoffError
from catalogue_logs import diagnostic

REMOTE = '/home/tom/.local/lib/agency-chat-window/catalogue_nas.py'
SSH = ['/run/current-system/sw/bin/ssh', '-T', '-S', 'none', '-o', 'ControlMaster=no',
    '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ForwardAgent=no',
    '-o', 'ConnectTimeout=8', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
    '-o', 'Hostname=100.65.85.114', '-o', 'HostKeyAlias=nas', 'nas']
MAX_FRAME = 8 * 1024 * 1024


def viewers(runtime):
    result, main = [], []
    for path in sorted(runtime.glob('agencychat*/opened.json'))[:4096]:
        try:
            value = read_private(path)
            tag = value.get('tag')
            if tag != path.parent.name or not re.fullmatch(r'agencychat[a-f0-9]{32}', tag):
                continue
            if value.get('sessionId'):
                result.append({'sessionId': value['sessionId'], 'tag': tag})
            else:
                main.append(tag)
        except (OSError, ValueError, HandoffError):
            continue
    return {'type': 'viewers', 'viewers': result, 'mainViewers': main}


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':')), flush=True)


def main():
    if sys.argv[1:] != ['--watch']:
        return 2
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    last_viewers = None
    log = diagnostic('catalogue-client')
    while running:
        child = subprocess.Popen([*SSH, 'python3 ' + REMOTE], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=log)
        buffer = b''
        try:
            while running and child.poll() is None:
                readable, _, _ = select.select([sys.stdin.buffer, child.stdout], [], [], .5)
                if sys.stdin.buffer in readable and not os.read(sys.stdin.fileno(), 1):
                    running = False; break
                if child.stdout in readable:
                    data = os.read(child.stdout.fileno(), 65536)
                    if not data:
                        break
                    buffer += data
                    if len(buffer) > MAX_FRAME:
                        raise ValueError('Metadata frame exceeds its limit')
                    while b'\n' in buffer:
                        raw, buffer = buffer.split(b'\n', 1)
                        emit(json.loads(raw))
                current = viewers(runtime)
                if current != last_viewers:
                    emit(current); last_viewers = current
        except (OSError, ValueError):
            pass
        finally:
            # EOF reaches the remote multiplexer, which ends its owned reader.
            child.stdin.close()
            try:
                child.wait(3)
            except subprocess.TimeoutExpired:
                child.terminate()
                try:
                    child.wait(3)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait(3)
        if running:
            emit({'type': 'unavailable'}); emit({'type': 'terminals', 'available': False})
            # Remain cancellable while SSH reconnects; no background service.
            ready, _, _ = select.select([sys.stdin.buffer], [], [], 2)
            if ready and not os.read(sys.stdin.fileno(), 1):
                break
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        pass
