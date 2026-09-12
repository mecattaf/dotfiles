"""Lifecycle helpers for the on-demand shared desktop; no browser content or credentials."""
import os
from pathlib import Path
import subprocess
import time
import uuid

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'browser-desktop'
MANUAL = RUNTIME / 'manual-session'
TASK_LEASE = RUNTIME / 'task-session.json'
TASK_MODEL = RUNTIME / 'task-model-started'
NO_VIEWERS = RUNTIME / 'no-viewers-since'


def start_desktop(manual=False):
    RUNTIME.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(['systemctl', '--user', 'start', 'browser-desktop.service'], check=True)
    except subprocess.CalledProcessError:
        # A failed readiness check must not leave Restart=always retrying after
        # the caller has already reported startup failure.
        subprocess.run(['systemctl', '--user', 'stop', 'browser-desktop.service'], check=False)
        raise
    if manual:
        MANUAL.touch(mode=0o600)


def stop_desktop():
    # Each Chrome launcher unit is PartOf this service, including when a task
    # dies before reaching its own finally block. systemd stops its whole cgroup.
    subprocess.run(['systemctl', '--user', 'stop', 'browser-chrome-*.service', 'browser-desktop.service'], check=True)
    MANUAL.unlink(missing_ok=True)
    NO_VIEWERS.unlink(missing_ok=True)
    (RUNTIME / 'environment').unlink(missing_ok=True)


def launch_chrome(data_dir, profile, env, unit=None):
    unit = unit or 'browser-chrome-' + uuid.uuid4().hex[:12] + '.service'
    args = ['systemd-run', '--user', '--collect', '--unit=' + unit,
            '--property=PartOf=browser-desktop.service',
            '--property=After=browser-desktop.service', '--property=TimeoutStopSec=15',
            '--setenv=DISPLAY=']
    for name in ('XCURSOR_THEME', 'XCURSOR_SIZE', 'XCURSOR_PATH', 'WAYLAND_DISPLAY',
                 'XDG_CURRENT_DESKTOP', '__EGL_VENDOR_LIBRARY_FILENAMES',
                 'LIBGL_DRIVERS_PATH', 'GBM_BACKENDS_PATH'):
        if name in env:
            args.append('--setenv=' + name + '=' + env[name])
    args += [os.environ['FARA_BROWSER_CHROME'], '--ozone-platform=wayland',
             '--user-data-dir=' + str(data_dir), '--profile-directory=' + profile,
             '--no-first-run', '--no-default-browser-check', '--disable-background-mode',
             '--new-window', 'about:blank']
    subprocess.run(args, check=True, capture_output=True, text=True)
    return unit


def desktop_status():
    remaining = None
    if NO_VIEWERS.exists():
        remaining = max(0, 300 - int(time.monotonic() - float(NO_VIEWERS.read_text())))
    return {'desktop_running': (RUNTIME / 'environment').exists(),
            'manual_session': MANUAL.exists(), 'idle_shutdown_seconds': remaining}
