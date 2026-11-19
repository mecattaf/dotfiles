#!/usr/bin/env python3
"""Explicit local operations on a DSH Host's terminal carrier. Opens no window."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys
import uuid


def request(path, payload):
    with socket.socket(socket.AF_UNIX) as channel:
        channel.settimeout(10)
        channel.connect(path)
        channel.sendall((json.dumps(payload) + '\n').encode())
        data = b''
        while b'\n' not in data:
            chunk = channel.recv(65536)
            if not chunk:
                raise RuntimeError('Host closed without a result')
            data += chunk
            if len(data) > 8 * 1024 * 1024:
                raise RuntimeError('oversized Host result')
        value = json.loads(data.split(b'\n', 1)[0])
        if value.get('type') == 'error':
            raise RuntimeError(value.get('code', 'terminal unavailable'))
        if value.get('type') != 'result':
            raise RuntimeError('unexpected Host result')
        return value


def route(server, epoch, session, terminal):
    identity = '\0'.join((server, epoch, session, terminal))
    return {
        'version': 1, 'server': server, 'epoch': epoch,
        'session': session, 'terminal': terminal,
        'windowClass': 'dsh-terminal-' + hashlib.sha256(identity.encode()).hexdigest()[:20],
        'sidebar': {'sessionId': session, 'kind': 'terminal', 'params': {'terminalId': terminal}},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('socket', 'server', 'session'):
        parser.add_argument('--' + field, required=True)
    commands = parser.add_subparsers(dest='operation', required=True)
    commands.add_parser('inventory')
    create = commands.add_parser('create')
    create.add_argument('--terminal', default='kitty-' + str(uuid.uuid4()))
    create.add_argument('--cols', type=int, default=90)
    create.add_argument('--rows', type=int, default=30)
    for operation in ('route', 'view', 'close'):
        command = commands.add_parser(operation)
        command.add_argument('--terminal', required=True)
        command.add_argument('--epoch', required=True)
    args = parser.parse_args()
    for value in (args.server, args.session, getattr(args, 'terminal', 'valid')):
        if re.fullmatch(r'[\w-]{1,128}', value, flags=re.ASCII) is None:
            parser.error('invalid Host, session or terminal identity')
    payload = {'version': 1, 'server': args.server, 'session': args.session}
    if args.operation == 'view':
        # No inventory-based fallback: stale routes must not attach to a new Host.
        argv = [sys.executable, str(Path(__file__).with_name('view.py'))]
        for field in ('socket', 'server', 'epoch', 'session', 'terminal'):
            argv += ['--' + field, getattr(args, field)]
        os.execv(sys.executable, argv)
    inventory = request(args.socket, dict(payload, operation='inventory'))
    if (inventory.get('server'), inventory.get('session')) != (args.server, args.session):
        raise RuntimeError('Host inventory identity mismatch')
    if args.operation == 'inventory':
        print(json.dumps(inventory, indent=2))
        return
    epoch = inventory['epoch']
    if args.operation != 'create':
        if args.epoch != epoch:
            raise RuntimeError('stale Host epoch; no attachment, allocation or close attempted')
        if not any(row['id'] == args.terminal for row in inventory['terminals']):
            raise RuntimeError('terminal unavailable; no replacement allocated')
    if args.operation in ('create', 'close'):
        mutation = dict(payload, operation=args.operation, epoch=epoch, terminal=args.terminal)
        if args.operation == 'create':
            mutation.update(cols=args.cols, rows=args.rows)
        result = request(args.socket, mutation)
        if args.operation == 'close':
            print(json.dumps(result, indent=2))
            return
    print(json.dumps(route(args.server, epoch, args.session, args.terminal), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
