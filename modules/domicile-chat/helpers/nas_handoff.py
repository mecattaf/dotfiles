"""NAS-only DSH handoff. JSON stdin/stdout; never log prompts or bootstrap URLs."""
import fcntl
import hashlib
import http.cookiejar
import json
import os
import re
from pathlib import Path
import stat
import subprocess
import sys
import urllib.request
from urllib.parse import urlsplit
import uuid

BASE = Path('/home/tom/wednesday/domicile-first-pass-20261105/agency-web-backend')
WORKSPACE = '/home/tom/wednesday'
MAX_INPUT = 65536


class HandoffError(Exception):
    pass


class HandoffRefused(HandoffError):
    """A complete negative RPC reply, distinct from an unknown transport outcome."""


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise HandoffError('Handoff directory ownership is invalid')


def read_private(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise HandoffError('Handoff record ownership is invalid')
        raw = os.read(fd, MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise HandoffError('Handoff record is too large')
        return json.loads(raw)
    finally:
        os.close(fd)


def save(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def bootstrap(base=BASE):
    url = read_private(base / 'state/active.json')['url']
    parts = urlsplit(url)
    if (parts.scheme != 'http' or parts.hostname != '127.0.0.1' or parts.port != 17318
            or parts.username or parts.password or not parts.query):
        raise HandoffError('Unexpected DSH origin')
    return url


class Host:
    def __init__(self, url):
        self.origin = url.split('?', 1)[0].rstrip('/')
        self.browser = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        with self.browser.open(url, timeout=10) as response:
            response.read(MAX_INPUT)

    def call(self, method, request):
        body = {'type': 'client-request', 'rpcId': str(uuid.uuid4()), 'method': method,
                'payload': {'args': {'request' if method != 'session/list' else '_request': request}}}
        message = urllib.request.Request(self.origin + '/api/' + method,
            data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'Origin': self.origin})
        with self.browser.open(message, timeout=15) as response:
            raw = response.read(1024 * 1024)
        result = json.loads(raw)['result']
        if result.get('ok') is False:
            raise HandoffRefused('DSH refused ' + method)
        if result.get('ok') is not True:
            raise HandoffError('Malformed DSH reply')
        return result['value']


def validate_request(value):
    if not isinstance(value, dict) or set(value) != {'requestId', 'prompt'}:
        raise HandoffError('Expected a composer request')
    request_id, prompt = value['requestId'], value['prompt']
    if not isinstance(request_id, str) or str(uuid.UUID(request_id)) != request_id:
        raise HandoffError('Invalid composer request identity')
    if not isinstance(prompt, str) or not prompt.strip() or len(prompt.encode()) > 48000 or '\0' in prompt:
        raise HandoffError('Enter a prompt of at most 48000 bytes')
    return request_id, prompt


def active_release():
    # Read the RUNNING launcher, not ExecStart (which may already name the
    # permission worker's staged next release). Never restart or edit it.
    pid = subprocess.check_output(['systemctl', '--user', 'show', 'agency-web.service',
        '--property=MainPID', '--value'], text=True, timeout=5).strip()
    if not pid.isdigit() or pid == '0':
        return None
    argv = Path('/proc', pid, 'cmdline').read_bytes().split(b'\0')
    if len(argv) < 2:
        return None
    launcher = Path(os.fsdecode(argv[1])).resolve()
    releases = Path.home() / '.local/share/agency-web/releases'
    if not launcher.is_relative_to(releases) or launcher.name != 'launch.py':
        return None
    return launcher.parent.parent


def active_plugin(directory):
    release = active_release()
    return release is not None and (release / 'plugins' / directory / 'package/client/client.js').is_file()


def active_chat_links():
    return active_plugin('agency-web-chat-links-0.1.0')


def start(value, base=BASE, host=None):
    request_id, prompt = validate_request(value)
    url = bootstrap(base)
    host = host or Host(url)
    directory = base / 'state/chat-window-requests'
    private_dir(directory)
    record_path = directory / (request_id + '.json')
    lock_fd = os.open(directory / (request_id + '.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        digest = hashlib.sha256(prompt.encode()).hexdigest()
        if record_path.exists():
            record = read_private(record_path)
            if record['digest'] != digest:
                raise HandoffError('Request identity was already used for another prompt')
        else:
            record = {'digest': digest, 'sessionId': 'session-' + request_id, 'stage': 'new'}
            save(record_path, record)
        if record['stage'] in ('creating', 'refused'):
            items = host.call('session/list', {})['items']
            if any(row['sessionId'] == record['sessionId'] for row in items):
                record['stage'] = 'created'
                save(record_path, record)
            elif record['stage'] == 'creating':
                raise HandoffError('Session creation outcome is unknown; no second chat was created')
        if record['stage'] in ('new', 'refused'):
            # Save intent before mutation. Only a complete negative RPC reply
            # permits another create attempt, still with the exact same ID.
            record['stage'] = 'creating'
            save(record_path, record)
            try:
                created = host.call('session/create', {'sessionId': record['sessionId'], 'cwd': WORKSPACE})
            except HandoffRefused:
                record['stage'] = 'refused'
                save(record_path, record)
                raise
            if created.get('sessionId') != record['sessionId']:
                raise HandoffError('DSH returned a different session identity')
            record['stage'] = 'created'
            save(record_path, record)
        if record['stage'] != 'accepted':
            # Host rc.2 deduplicates this client requestId on the exact user
            # message. Retries after a lost HTTP response keep both identities.
            accepted = host.call('session/prompt', {'requestId': request_id, 'sessionId': record['sessionId'],
                'mode': 'queue', 'content': [{'type': 'text', 'text': prompt}]})
            if accepted.get('accepted') is not True:
                raise HandoffError('DSH did not acknowledge the prompt')
            record['stage'] = 'accepted'
            save(record_path, record)
        return {'url': url, 'requestId': request_id, 'sessionId': record['sessionId']}
    finally:
        os.close(lock_fd)


def existing(value, base=BASE, host=None):
    session_id = value['sessionId']
    if not isinstance(session_id, str) or not re.fullmatch(r'session-[a-zA-Z0-9-]{1,100}', session_id):
        raise HandoffError('Invalid chat identity')
    url = bootstrap(base)
    items = (host or Host(url)).call('session/list', {})['items']
    if not any(item.get('sessionId') == session_id for item in items):
        raise HandoffError('Chat no longer exists')
    return {'url': url, 'sessionId': session_id}


def main():
    try:
        peer = os.environ.get('SSH_CONNECTION', '').split()
        if len(peer) != 4 or peer[0] != '100.121.160.100' or peer[2] != '100.65.85.114':
            raise HandoffError('Chat handoff requires the declared client to NAS Tailscale route')
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise HandoffError('Composer request is too large')
        value = json.loads(raw)
        for service in ('agency-web.service', 'agency-web-client-tunnel.service'):
            result = subprocess.run(['systemctl', '--user', 'is-active', '--quiet', service],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            if result.returncode:
                raise HandoffError('The chat Host or its client tunnel is unavailable')
        if value == {'bootstrap': True}:
            url = bootstrap()
            Host(url)  # Verify the running Host, not just yesterday's file.
            result = {'url': url, 'chatLinks': active_chat_links()}
        else:
            if not active_chat_links():
                raise HandoffError('Per-chat links are not active in the running release')
            if set(value) == {'sessionId'}:
                result = existing(value)
            else:
                result = start(value)
            result['freeform'] = active_plugin('agency-web-chat-view-0.1.1') or active_plugin('agency-web-chat-view-0.1.0')
        print(json.dumps(result))
        return 0
    except Exception:
        # urllib exceptions may include bootstrap credentials; keep bodies private.
        print('DSH chat handoff failed; the same request identity can be retried', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
