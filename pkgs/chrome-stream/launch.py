"""Own one Chrome process and its localhost screencast bridge."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import time
import urllib.request


def attach_existing(args):
    """Attach after Chrome's own UI enables and authorizes remote debugging."""
    os.umask(0o077)
    state = args.state or Path.home()/'.local/share/chrome-stream/live'
    state.mkdir(parents=True, exist_ok=True)
    with (state/'launcher.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        deadline = time.monotonic() + 600
        active_port = args.attach/'DevToolsActivePort'
        print('Waiting for remote debugging to be enabled in chrome://inspect/#remote-debugging', flush=True)
        while not active_port.exists():
            if time.monotonic() > deadline:
                raise RuntimeError('Remote debugging was not enabled within 10 minutes')
            time.sleep(.5)
        lines = active_port.read_text().splitlines()
        port = int(lines[0])
        if not 0 < port < 65536 or not lines[1].startswith('/devtools/browser'):
            raise RuntimeError('Invalid Chrome debugging endpoint')
        env = dict(os.environ)
        env['CHROME_STREAM_CDP'] = f'ws://127.0.0.1:{port}{lines[1]}'
        env['CHROME_STREAM_TOKEN'] = secrets.token_urlsafe(32)
        env['CHROME_STREAM_PORT'] = str(args.port)
        print('Connecting to existing Chrome. Accept its Allow debugging dialog.', flush=True)
        bridge = subprocess.Popen(['bun', str(args.assets/'server.js')], env=env)

        def stop(*_):
            raise KeyboardInterrupt

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            while time.monotonic() < deadline:
                if bridge.poll() is not None:
                    raise RuntimeError('Connection was not accepted, or the bridge failed')
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/health', timeout=1) as r:
                        if r.read() == b'ok':
                            break
                except OSError:
                    time.sleep(.5)
            else:
                raise RuntimeError('Timed out waiting for Chrome authorization')
            (state/'viewer-url').write_text(f"http://127.0.0.1:{args.port}/#" + env['CHROME_STREAM_TOKEN'] + '\n')
            print(f'Ready. Existing Chrome viewer link: {state}/viewer-url', flush=True)
            bridge.wait()
        except KeyboardInterrupt:
            pass
        finally:
            if bridge.poll() is None:
                bridge.terminate()
                try:
                    bridge.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    bridge.kill()
                    bridge.wait()
            (state/'viewer-url').unlink(missing_ok=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--assets', type=Path, default=Path(__file__).parent)
    p.add_argument('--profile', default='Default')
    p.add_argument('--source', type=Path, default=Path.home()/'.config/google-chrome')
    p.add_argument('--state', type=Path)
    p.add_argument('--port', type=int, default=4780)
    p.add_argument('--url', default='about:blank')
    p.add_argument('--attach', type=Path, nargs='?', const=Path.home()/'.config/google-chrome',
                   help='attach to an existing browser after enabling remote debugging in Chrome; does not launch or stop Chrome')
    a = p.parse_args()
    if a.attach:
        return attach_existing(a)
    if Path(a.profile).name != a.profile or a.profile in ('.', '..'):
        p.error('--profile must be a single directory name')
    state = a.state or Path.home()/'.local/share/chrome-stream'/a.profile.replace(' ', '-')
    os.umask(0o077)
    state.mkdir(parents=True, exist_ok=True)
    lock = (state/'launcher.lock').open('w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        p.error(f'a chrome-stream process already owns {state}')
    udd = state/'chrome'
    if not udd.exists():
        # A live source would make a torn SQLite/LevelDB snapshot.
        singleton = a.source/'SingletonLock'
        if singleton.is_symlink():
            owner = os.readlink(singleton)
            host, _, pid = owner.rpartition('-')
            if host != os.uname().nodename or Path('/proc', pid).exists():
                p.error('source Chrome profile is in use; close that browser before the first copy')
        staging = state/'chrome.partial'
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        shutil.copy2(a.source/'Local State', staging/'Local State')
        shutil.copytree(a.source/a.profile, staging/a.profile,
                        ignore=shutil.ignore_patterns('Cache', 'Code Cache', 'GPUCache'))
        staging.rename(udd)
    # Also refuse a browser started manually against our private copy.
    singleton = udd/'SingletonLock'
    if singleton.is_symlink():
        host, _, pid = os.readlink(singleton).rpartition('-')
        if host != os.uname().nodename or Path('/proc', pid).exists():
            p.error('the remote profile is already open in another Chrome process')
    # Only our private copy, protected by the launcher lock, is cleaned.
    for name in ('SingletonLock', 'SingletonSocket', 'SingletonCookie', 'DevToolsActivePort'):
        (udd/name).unlink(missing_ok=True)
    env = dict(os.environ)
    env.setdefault('DBUS_SESSION_BUS_ADDRESS', f"unix:path=/run/user/{os.getuid()}/bus")
    env['CHROME_STREAM_TOKEN'] = secrets.token_urlsafe(32)
    children = []

    def stop(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        with (state/'chrome.log').open('w') as log:
            chrome = subprocess.Popen([
                'google-chrome-stable', '--headless=new', '--remote-debugging-port=0',
                f'--user-data-dir={udd}', f'--profile-directory={a.profile}',
                '--password-store=gnome-libsecret', '--no-first-run', '--no-default-browser-check',
                '--window-size=1440,900', a.url,
            ], env=env, stdout=log, stderr=log)
            children.append(chrome)
            deadline = time.monotonic() + 30
            while not (udd/'DevToolsActivePort').exists():
                if chrome.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f'Chrome failed to start; see {state}/chrome.log')
                time.sleep(.1)
            port = int((udd/'DevToolsActivePort').read_text().splitlines()[0])
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/json/version') as r:
                env['CHROME_STREAM_CDP'] = json.load(r)['webSocketDebuggerUrl']
            env['CHROME_STREAM_PORT'] = str(a.port)
            bridge = subprocess.Popen(['bun', str(a.assets/'server.js')], env=env)
            children.append(bridge)
            for _ in range(100):
                if bridge.poll() is not None:
                    raise RuntimeError('viewer failed to start')
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{a.port}/health') as r:
                        if r.read() == b'ok':
                            break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError('viewer did not become ready')
            link = f"http://127.0.0.1:{a.port}/#" + env['CHROME_STREAM_TOKEN']
            (state/'viewer-url').write_text(link + '\n')
            print(f'Ready. Viewer link: {state}/viewer-url', flush=True)
            print(f'On the client: ssh -N -L {a.port}:127.0.0.1:{a.port} coordinator', flush=True)
            while all(c.poll() is None for c in children):
                time.sleep(.5)
    except KeyboardInterrupt:
        pass
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        (state/'viewer-url').unlink(missing_ok=True)


if __name__ == '__main__':
    main()
