"""Fixed-purpose Chrome app opener. Private Unix socket and CDP pipe, no TCP listener.

The browser-only profile is shared by every chat viewer. NAS owns all DSH and
provider state. This process can open only the declared loopback chat origin.
"""
import json
import os
from pathlib import Path
import re
import select
import socket
import stat
import subprocess
import sys
import time

from legacy_bootstrap import validate_url
from nas_handoff import private_dir, read_private, save

CHROME = '/etc/profiles/per-user/tom/bin/google-chrome-stable'


class Pipe:
    def __init__(self, chrome, profile, page, log, extra=()):
        incoming, self.write_fd = os.pipe()
        self.read_fd, outgoing = os.pipe()
        null = os.open(os.devnull, os.O_RDONLY)
        actions = [(os.POSIX_SPAWN_DUP2, null, 0), (os.POSIX_SPAWN_DUP2, log.fileno(), 1),
            (os.POSIX_SPAWN_DUP2, log.fileno(), 2), (os.POSIX_SPAWN_DUP2, incoming, 3),
            (os.POSIX_SPAWN_DUP2, outgoing, 4)]
        argv = [chrome, '--ozone-platform=wayland', '--no-first-run', '--remote-debugging-pipe',
            '--user-data-dir=' + str(profile), *extra, '--app=' + page.as_uri()]
        self.pid = os.posix_spawn(chrome, argv, dict(os.environ), file_actions=actions)
        os.close(null); os.close(incoming); os.close(outgoing)
        self.sequence = 0
        self.buffer = b''

    def call(self, method, params=None, session=None, timeout=20):
        self.sequence += 1
        request = {'id': self.sequence, 'method': method, 'params': params or {}}
        if session:
            request['sessionId'] = session
        payload = json.dumps(request).encode() + b'\0'
        while payload:
            count = os.write(self.write_fd, payload)
            payload = payload[count:]
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b'\0' in self.buffer:
                raw, self.buffer = self.buffer.split(b'\0', 1)
                message = json.loads(raw)
                if message.get('id') == self.sequence:
                    if 'error' in message:
                        raise RuntimeError('Chrome refused its chat navigation')
                    return message.get('result', {})
            if not select.select([self.read_fd], [], [], max(0, deadline - time.monotonic()))[0]:
                break
            chunk = os.read(self.read_fd, 65536)
            if not chunk:
                raise RuntimeError('Chrome pipe closed')
            self.buffer += chunk
            if len(self.buffer) > 2 * 1024 * 1024:
                raise RuntimeError('Chrome pipe exceeded its response limit')
        raise TimeoutError('Chrome navigation timed out')

    def alive(self):
        pid, _ = os.waitpid(self.pid, os.WNOHANG)
        return pid == 0

    def close(self):
        os.close(self.write_fd); os.close(self.read_fd)


class Browser:
    def __init__(self, runtime, profile, chrome=CHROME, extra=()):
        self.runtime, self.profile, self.chrome, self.extra = runtime, profile, chrome, extra
        self.origin = 'http://127.0.0.1:17318'
        self.pipe = None
        self.log = None
        self.targets = {}
        self.main_tag = None

    def open_main(self, record, tag):
        if self.main_tag is not None and self.pipe is not None:
            target = self.targets.get(self.main_tag)
            live = self.pipe.call('Target.getTargets')['targetInfos']
            if any(row['targetId'] == target for row in live):
                return read_private(self.runtime / self.main_tag / 'opened.json')
        receipt = self.open(record, tag)
        self.main_tag = tag
        return receipt

    def open_viewer(self, record, tag):
        # Reuse only a live target of this broker, keyed by DSH identity. The
        # shell resolves the returned tag to its current SDK appId and focus.
        if self.pipe is not None:
            live = {row['targetId'] for row in self.pipe.call('Target.getTargets')['targetInfos']}
            for previous, target in self.targets.items():
                if target in live:
                    receipt = read_private(self.runtime / previous / 'opened.json')
                    if receipt.get('sessionId') == record['sessionId']:
                        return receipt
        return self.open(record, tag)

    def open(self, record, tag):
        url = validate_url(record['url'])
        if not re.fullmatch('agencychat[0-9a-f]{32}', tag):
            raise ValueError('Unexpected Chrome app identity')
        session_id = record.get('sessionId')
        if session_id is not None and not re.fullmatch(r'session-[a-zA-Z0-9-]{1,100}', session_id):
            raise ValueError('Unexpected DSH identity')
        directory = self.runtime / tag
        private_dir(directory)
        receipt_path = directory / 'opened.json'
        if receipt_path.exists():
            receipt = read_private(receipt_path)
            if any(receipt.get(key) != record.get(key) for key in ('sessionId', 'requestId')) or receipt.get('tag') != tag:
                raise ValueError('Chat launch identity was already used')
            return receipt
        page = directory / 'start.html'
        # Native app identity derives from this harmless URL path. Credentials
        # travel only inside the pipe and are never written into this file.
        fd = os.open(page, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write('<!doctype html><meta charset="utf-8"><title>Opening chat</title>Opening chat…')
        private_dir(self.profile)
        if self.pipe is None:
            log_path = self.profile / 'chrome.log'
            self.log = log_path.open('a'); log_path.chmod(0o600)
            self.pipe = Pipe(self.chrome, self.profile, page, self.log, self.extra)
        else:
            subprocess.run([self.chrome, '--ozone-platform=wayland', '--user-data-dir=' + str(self.profile),
                *self.extra, '--app=' + page.as_uri()], stdin=subprocess.DEVNULL,
                stdout=self.log, stderr=self.log, timeout=15, check=True)
        target = None
        deadline = time.monotonic() + 20
        while target is None and time.monotonic() < deadline:
            targets = self.pipe.call('Target.getTargets')['targetInfos']
            target = next((row['targetId'] for row in targets if row['type'] == 'page' and row['url'] == page.as_uri()), None)
            if target is None:
                time.sleep(.05)
        if target is None:
            raise RuntimeError('Chrome app window did not appear')
        self.targets[tag] = target
        attached = self.pipe.call('Target.attachToTarget', {'targetId': target, 'flatten': True})['sessionId']
        try:
            clean = url.split('?', 1)[0].split('#', 1)[0]
            if record.get('freeform') is True:
                clean += '?agency-view=freeform'
            if session_id:
                clean += '#agency-chat=' + session_id
            self.pipe.call('Page.navigate', {'url': url}, session=attached)
            # The first cross-site redirect may receive 401 even though its
            # Set-Cookie succeeded. Wait for its clean top-level document, then
            # navigate within the origin so Chrome sends the strict cookie.
            end = time.monotonic() + 15
            while time.monotonic() < end:
                state = self.pipe.call('Runtime.evaluate', {'expression':
                    '({origin:location.origin,search:location.search,ready:document.readyState})', 'returnByValue': True}, session=attached)
                value = state.get('result', {}).get('value', {})
                if value.get('origin') == self.origin and not value.get('search') and value.get('ready') == 'complete':
                    break
                time.sleep(.05)
            else:
                raise RuntimeError('Chrome bootstrap did not finish')
            self.pipe.call('Page.navigate', {'url': clean}, session=attached)
        finally:
            self.pipe.call('Target.detachFromTarget', {'sessionId': attached})
        receipt = {'tag': tag, **{key: record[key] for key in ('sessionId', 'requestId') if key in record}}
        save(receipt_path, receipt)
        return receipt


def main():
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
    path = runtime / 'agency-chat-chrome-v2.sock'
    profile = Path.home() / '.local/share/agency-chat-chrome-v2'
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    browser = Browser(runtime, profile)
    identity = None
    try:
        # An existing socket is never removed on guesswork, including one
        # left after a crash. A caller reports that state instead of replacing it.
        server.bind(str(path)); path.chmod(0o600)
        info = path.lstat(); identity = (info.st_dev, info.st_ino)
        server.listen(4); server.settimeout(1)
        while browser.pipe is None or browser.pipe.alive():
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(3)
                try:
                    raw = bytearray()
                    while b'\n' not in raw:
                        chunk = connection.recv(4096)
                        if not chunk or len(raw) + len(chunk) > 16384:
                            raise ValueError('Invalid chat request')
                        raw.extend(chunk)
                    request = json.loads(raw)
                    if set(request) not in ({'record', 'tag'}, {'record', 'tag', 'main'}, {'record', 'tag', 'main', 'viewer'}):
                        raise ValueError('Invalid chat request')
                    method = browser.open_main if request.get('main') is True else browser.open_viewer if request.get('viewer') is True else browser.open
                    receipt = method(request['record'], request['tag'])
                    connection.sendall(json.dumps({'ok': True, 'receipt': receipt}).encode() + b'\n')
                except Exception as error:
                    print('Chrome chat operation failed (' + type(error).__name__ + ')', file=sys.stderr, flush=True)
                    connection.sendall(b'{"ok":false}\n')
    finally:
        server.close()
        if identity is not None:
            current = path.lstat()
            if identity == (current.st_dev, current.st_ino):
                path.unlink()
        if browser.pipe is not None:
            browser.pipe.close()
        if browser.log is not None:
            browser.log.close()


if __name__ == '__main__':
    main()
