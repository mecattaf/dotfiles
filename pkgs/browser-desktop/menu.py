"""Local noVNC Chrome menu: profile metadata, native unlock and window launch."""
import argparse
import asyncio
import contextlib
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time
from aiohttp import web
from session import MANUAL, TASK_LEASE, TASK_MODEL, NO_VIEWERS, start_desktop, stop_desktop, launch_chrome, desktop_status
from harness import (RUNTIME, chrome_profiles, keyring_state, request_unlock,
                     session_environment, ensure_chrome_on_display, windows)


@contextlib.contextmanager
def desktop_operation():
    RUNTIME.mkdir(parents=True, exist_ok=True)
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
        start_desktop(manual=True)
        env = session_environment()
        ensure_chrome_on_display(data_dir, env)
        before = set(windows(env))
        launch_chrome(data_dir, profile, env)
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
            start_desktop(manual=True)
        else:
            return
    # Waiting for a human password is not an active FARA task. Release the
    # operation lock so disconnect expiry and End session can still stop it.
    request_unlock()


def start_manual():
    with desktop_operation():
        start_desktop(manual=True)


def end_manual():
    with desktop_operation():
        if (RUNTIME / 'environment').exists():
            env = session_environment()
            for window_id in windows(env):
                subprocess.run(['swaymsg', '-s', env['SWAYSOCK'], f'[con_id={window_id}] kill'],
                               check=True, capture_output=True)
            for _ in range(30):
                if not windows(env):
                    break
                time.sleep(.1)
            else:
                raise ValueError('Chrome is waiting for confirmation. Resolve its dialog, then End session again.')
        stop_desktop()


def reap_abandoned_task():
    try:
        with desktop_operation():
            if TASK_MODEL.exists():
                subprocess.run(['systemctl', '--user', 'stop', 'fara-browser-model.service'], check=True)
                TASK_MODEL.unlink()
            running = (RUNTIME / 'environment').exists()
            if TASK_LEASE.exists():
                lease = json.loads(TASK_LEASE.read_text())
                if running:
                    env = session_environment()
                    for window_id in set(windows(env)) - set(lease['baseline']):
                        subprocess.run(['swaymsg', '-s', env['SWAYSOCK'], f'[con_id={window_id}] kill'],
                                       check=True, capture_output=True)
                subprocess.run(['systemctl', '--user', 'stop', lease['unit']], check=False, capture_output=True)
                if not running or not (set(windows(env)) - set(lease['baseline'])):
                    TASK_LEASE.unlink()
            if not running:
                NO_VIEWERS.unlink(missing_ok=True)
                return
            if not MANUAL.exists():
                stop_desktop()
                return
            result = subprocess.run(['wayvncctl', '--socket', str(RUNTIME / 'wayvncctl'),
                                     '--json', 'client-list'], check=True, capture_output=True, text=True)
            if json.loads(result.stdout):
                NO_VIEWERS.unlink(missing_ok=True)
            elif not NO_VIEWERS.exists():
                NO_VIEWERS.write_text(str(time.monotonic()))
            elif time.monotonic() - float(NO_VIEWERS.read_text()) >= 300:
                stop_desktop()
    except ValueError:
        # An active FARA CLI holds the task lock. No spectator is required, and
        # a manual session gets a fresh grace period after the task finishes.
        NO_VIEWERS.unlink(missing_ok=True)


async def reaper(_app):
    async def monitor():
        while True:
            await asyncio.sleep(5)
            try:
                await asyncio.to_thread(reap_abandoned_task)
            except Exception as error:
                _app.logger.warning('Desktop cleanup failed: %s', error)
    task = asyncio.create_task(monitor())
    yield
    task.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await task


def make_app(data_dir, origin):
    app = web.Application(client_max_size=4096)
    work = set()

    async def profiles(_request):
        return web.json_response({'profiles': chrome_profiles(data_dir), 'keyring': keyring_state(),
                                  **desktop_status(), 'busy': busy(), 'unlocking': any(not t.done() for t in work)})

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
            if request.path == '/start':
                await asyncio.to_thread(start_manual)
                return web.json_response({'status': 'started'})
            if request.path == '/end':
                await asyncio.to_thread(end_manual)
                return web.json_response({'status': 'stopped'})
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
    app.router.add_post('/start', change)
    app.router.add_post('/end', change)
    app.cleanup_ctx.append(reaper)
    return app


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=4784)
    parser.add_argument('--origin', default='https://browser.internal')
    parser.add_argument('--chrome-data-dir', type=Path, default=Path.home()/'.config/google-chrome')
    args = parser.parse_args()
    web.run_app(make_app(args.chrome_data_dir, args.origin), host='127.0.0.1', port=args.port, access_log=None)
