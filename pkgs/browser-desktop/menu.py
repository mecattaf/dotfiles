"""Local noVNC Chrome menu: profile metadata, native unlock and window launch."""
import argparse
import asyncio
import contextlib
import fcntl
import os
from pathlib import Path
import subprocess
import time
import uuid
from aiohttp import web
from harness import (RUNTIME, chrome_profiles, keyring_state, request_unlock,
                     session_environment, ensure_chrome_on_display, windows)


@contextlib.contextmanager
def desktop_operation():
    with (RUNTIME / 'task.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Finish or cancel the current FARA task before opening a window.') from None
        yield


def busy():
    try:
        with desktop_operation():
            return False
    except ValueError:
        return True


def open_window(data_dir, profile):
    with desktop_operation():
        known = {p['directory']: p for p in chrome_profiles(data_dir) if p['exists']}
        if profile not in known or Path(profile).name != profile:
            raise ValueError('Choose an existing Chrome profile from the list.')
        if keyring_state() != 'unlocked':
            raise ValueError('Unlock the desktop keyring before opening Chrome.')
        env = session_environment()
        ensure_chrome_on_display(data_dir, env)
        before = set(windows(env))
        unit = 'browser-chrome-' + uuid.uuid4().hex[:12]
        args = ['systemd-run', '--user', '--collect', '--unit=' + unit,
                '--setenv=DISPLAY=']
        for name in ('WAYLAND_DISPLAY', 'XDG_CURRENT_DESKTOP', '__EGL_VENDOR_LIBRARY_FILENAMES',
                     'LIBGL_DRIVERS_PATH', 'GBM_BACKENDS_PATH'):
            if name in env:
                args.append('--setenv=' + name + '=' + env[name])
        args += [os.environ['FARA_BROWSER_CHROME'], '--ozone-platform=wayland',
                 '--user-data-dir=' + str(data_dir), '--profile-directory=' + profile,
                 '--no-first-run', '--no-default-browser-check', '--new-window', 'about:blank']
        subprocess.run(args, check=True, capture_output=True, text=True)
        for _ in range(100):
            opened = set(windows(env)) - before
            if opened:
                for window_id in opened:
                    subprocess.run(['swaymsg', '-s', env['SWAYSOCK'], f'[con_id={window_id}] focus'],
                                   check=True, capture_output=True)
                return {'profile': known[profile], 'window_ids': sorted(opened)}
            time.sleep(.1)
        raise RuntimeError('Chrome did not create a window. Check the desktop for a dialog, then retry.')


def unlock():
    with desktop_operation():
        if keyring_state() == 'locked':
            request_unlock()


def make_app(data_dir, origin):
    app = web.Application(client_max_size=4096)
    work = set()

    async def profiles(_request):
        return web.json_response({'profiles': chrome_profiles(data_dir), 'keyring': keyring_state(),
                                  'busy': busy(), 'unlocking': any(not t.done() for t in work)})

    def finished(task):
        work.discard(task)
        try:
            task.result()
        except Exception as error:
            # No password or browser content is passed through this service.
            app.logger.warning('Keyring unlock did not complete: %s', error)

    async def change(request):
        if request.headers.get('Origin') != origin or request.headers.get('X-Fara-Control') != '1':
            raise web.HTTPForbidden()
        try:
            if busy():
                raise ValueError('Finish or cancel the current FARA task before using the Chrome menu.')
            if request.path == '/unlock':
                if not work:
                    task = asyncio.create_task(asyncio.to_thread(unlock))
                    work.add(task)
                    task.add_done_callback(finished)
                return web.json_response({'status': 'unlock_requested'})
            body = await request.json()
            profile = body.get('profile') if isinstance(body, dict) else None
            if not isinstance(profile, str):
                raise ValueError('Choose a Chrome profile.')
            result = await asyncio.to_thread(open_window, data_dir, profile)
            return web.json_response(result)
        except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
            return web.json_response({'error': str(error)}, status=409)

    app.router.add_get('/profiles', profiles)
    app.router.add_post('/open', change)
    app.router.add_post('/unlock', change)
    return app


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=4784)
    parser.add_argument('--origin', default='http://browser.internal')
    parser.add_argument('--chrome-data-dir', type=Path, default=Path.home()/'.config/google-chrome')
    args = parser.parse_args()
    web.run_app(make_app(args.chrome_data_dir, args.origin), host='127.0.0.1', port=args.port, access_log=None)
