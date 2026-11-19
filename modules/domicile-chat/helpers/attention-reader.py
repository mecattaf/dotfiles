#!/usr/bin/env python3
"""Read Host attention on NAS, or relay JSON events over SSH without copying credentials."""
import argparse
import http.client
from http.cookies import SimpleCookie
import json
import os
from pathlib import Path
import stat
import sys
import time
from urllib.parse import parse_qs, urlsplit

DEFAULT_ACTIVE = Path('/home/tom/wednesday/domicile-first-pass-20261105/agency-web-backend/state/active.json')


def connect(active):
    fd = os.open(active, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(fd) as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 65536:
            raise ValueError('invalid active file')
        url = urlsplit(json.load(file)['url'])
    query = parse_qs(url.query, strict_parsing=True)
    if (url.scheme != 'http' or url.hostname != '127.0.0.1' or not url.port
            or url.username or url.password or url.fragment or url.path != '/'
            or set(query) != {'token'} or len(query['token']) != 1):
        raise ValueError('invalid Host endpoint')
    connection = http.client.HTTPConnection('127.0.0.1', url.port, timeout=45)
    try:
        connection.request('GET', '/?' + url.query)
        response = connection.getresponse()
        if response.status != 303 or response.getheader('Location') != './':
            raise ValueError('Host authentication unavailable')
        cookie = SimpleCookie()
        cookie.load(response.getheader('Set-Cookie', ''))
        if len(cookie) != 1:
            raise ValueError('invalid Host cookie')
        response.read(65536)
        headers = {'Origin': 'http://' + url.netloc,
                   'Cookie': '; '.join(f'{item.key}={item.value}' for item in cookie.values())}
        return connection, headers
    except Exception:
        connection.close()
        raise


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':')), flush=True)


def read(active, watch):
    connection, headers = connect(active)
    try:
        path = '/api/chat-attention-events' if watch else '/api/chat-attention'
        connection.request('GET', path, headers=headers)
        response = connection.getresponse()
        if response.status != 200:
            raise ValueError('attention plugin unavailable')
        expected = 'text/event-stream' if watch else 'application/json'
        if not response.getheader('Content-Type', '').startswith(expected):
            raise ValueError('unexpected attention response')
        if not watch:
            body = response.read(8 * 1024 * 1024 + 1)
            if len(body) > 8 * 1024 * 1024:
                raise ValueError('attention snapshot too large')
            emit(json.loads(body))
            return
        kind = None
        for line in response:
            if len(line) > 8 * 1024 * 1024:
                raise ValueError('attention frame too large')
            line = line.decode('utf-8').rstrip('\r\n')
            if line.startswith('event: '):
                kind = line[7:]
            elif line.startswith('data: ') and kind in ('snapshot', 'upsert', 'remove'):
                emit({'type': kind, **json.loads(line[6:])})
                kind = None
        raise ConnectionError('attention stream closed')
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--active', type=Path, default=DEFAULT_ACTIVE)
    parser.add_argument('--watch', action='store_true')
    args = parser.parse_args()
    while True:
        try:
            read(args.active, args.watch)
            return 0
        except (KeyboardInterrupt, BrokenPipeError):
            return 0
        except Exception:
            # Exceptions can contain the launch URL or cookie. Emit a fixed
            # unavailable message and keep all authentication material on NAS.
            if not args.watch:
                print('Host attention unavailable', file=sys.stderr)
                return 1
            emit({'type': 'unavailable'})
            time.sleep(2)


if __name__ == '__main__':
    raise SystemExit(main())
