#!/usr/bin/env python3
"""A Kitty window's child for tests/kitty-persist-kitty/run.py.

--persist: it sets the user variables an attached kitty-persist client sets (persist_id,
persist_epoch, persist_state=attached), the way the product's attach client does, so Kitty's
mapping conditions and `kitty-persist paste-text --focused` see a persistent window. Without it,
it is an ordinary window.

It keeps the terminal raw and logs every byte Kitty sends it (hex, one JSON line per read) to
DIR/NAME.in.jsonl, writes DIR/NAME.ready.json once the variables are set, and exits when
DIR/stop exists. --status sends one program status report (OSC 7501), as the holder relays an
agent's state, so the tab title's program status has something to show.
"""
import argparse
import base64
import json
import os
import select
import sys
import termios
import time
import tty


def setvar(key: str, value: str) -> None:
    v = base64.b64encode(value.encode()).decode()
    sys.stdout.write(f'\x1b]1337;SetUserVar={key}={v}\x07')
    sys.stdout.flush()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--persist', metavar='SESSION_ID')
    ap.add_argument('--status', metavar='STATE', help='a program status report (OSC 7501), as the holder relays one')
    a = ap.parse_args()
    fd = sys.stdin.fileno()
    tty.setraw(fd, termios.TCSANOW)
    if a.persist:
        setvar('persist_id', a.persist)
        setvar('persist_epoch', '1')
        setvar('persist_state', 'attached')
    if a.status:
        sys.stdout.write(f'\x1b]7501;state={a.status}:app=test\x1b\\')
        sys.stdout.flush()
    time.sleep(0.3)
    with open(os.path.join(a.dir, f'{a.name}.ready.json'), 'w') as f:
        json.dump({'pid': os.getpid(), 'window_id': os.environ.get('KITTY_WINDOW_ID', '')}, f)
    log = open(os.path.join(a.dir, f'{a.name}.in.jsonl'), 'a')
    stop = os.path.join(a.dir, 'stop')
    while not os.path.exists(stop):
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            data = os.read(fd, 65536)
            if not data:
                break
            log.write(json.dumps({'t': time.time(), 'hex': data.hex()}) + '\n')
            log.flush()
    return 0


if __name__ == '__main__':
    sys.exit(main())
