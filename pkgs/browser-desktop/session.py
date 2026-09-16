"""Lifecycle, profile and display helpers for the on-demand shared desktop.

No browser content or credentials pass through these helpers.
"""
import contextlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'browser-desktop'
MANUAL = RUNTIME / 'manual-session'
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


def stop_desktop(wait_for_chrome=False):
    if wait_for_chrome:
        # An empty Sway tree only means Chrome unmapped its last window.
        # Let the browser finish saving its profile before signalling it.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            states = subprocess.run(['systemctl', '--user', 'show',
                'browser-chrome-*.service', '--property=ActiveState', '--value'],
                check=True, capture_output=True, text=True).stdout.splitlines()
            if not any(state in ('active', 'activating', 'deactivating') for state in states):
                break
            time.sleep(.1)
    # Each Chrome launcher unit is PartOf this service; systemd stops its whole
    # cgroup, including children that outlived the launcher.
    subprocess.run(['systemctl', '--user', 'stop', 'browser-chrome-*.service', 'browser-desktop.service'], check=True)
    MANUAL.unlink(missing_ok=True)
    NO_VIEWERS.unlink(missing_ok=True)
    (RUNTIME / 'environment').unlink(missing_ok=True)


def launch_chrome(data_dir, profile, env):
    unit = 'browser-chrome-' + uuid.uuid4().hex[:12] + '.service'
    args = ['systemd-run', '--user', '--collect', '--unit=' + unit,
            '--property=PartOf=browser-desktop.service',
            '--property=After=browser-desktop.service', '--property=TimeoutStopSec=15',
            # Ask the browser to exit first; killing its renderer/utility
            # children simultaneously can crash the browser during shutdown.
            '--property=KillMode=mixed',
            '--setenv=DISPLAY=']
    for name in ('XCURSOR_THEME', 'XCURSOR_SIZE', 'XCURSOR_PATH', 'WAYLAND_DISPLAY',
                 'XDG_CURRENT_DESKTOP', '__EGL_VENDOR_LIBRARY_FILENAMES',
                 'LIBGL_DRIVERS_PATH', 'GBM_BACKENDS_PATH'):
        if name in env:
            args.append('--setenv=' + name + '=' + env[name])
    args += [os.environ['BROWSER_DESKTOP_CHROME'], '--ozone-platform=wayland',
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


def command(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check).stdout.strip()


def chrome_profiles(data_dir):
    """Chrome's recorded profile identities; never infer website logins."""
    state = json.loads((data_dir / 'Local State').read_text()).get('profile', {})
    return [{'directory': directory, 'name': item.get('name', directory),
             'google_account': item.get('user_name') or None,
             'google_account_name': item.get('gaia_name') or None,
             'exists': (data_dir / directory).is_dir(),
             'last_used_by_chrome': directory == state.get('last_used')}
            for directory, item in state.get('info_cache', {}).items()]


def keyring_state():
    try:
        value = command('busctl', '--user', 'get-property', 'org.freedesktop.secrets',
                        '/org/freedesktop/secrets/aliases/default',
                        'org.freedesktop.Secret.Collection', 'Locked')
        return {'b false': 'unlocked', 'b true': 'locked'}.get(value, 'unknown')
    except subprocess.CalledProcessError:
        return 'unavailable'


def request_unlock():
    import secretstorage
    # gcr-prompter exits after inactivity. Start it on the right display only
    # when actually needed, rather than changing global D-Bus activation state.
    subprocess.Popen([os.environ['BROWSER_DESKTOP_PROMPTER']], env=session_environment(),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(.2)
    # Prompt objects belong to one D-Bus connection. The established library
    # keeps it alive until the human completes or dismisses the native dialog.
    with contextlib.closing(secretstorage.dbus_init()) as connection:
        secretstorage.Collection(connection).unlock(timeout=600)


def session_environment():
    path = RUNTIME / 'environment'
    if not path.exists():
        raise RuntimeError('Start browser-desktop.service before using the browser.')
    # Read our own Bash-generated environment, without importing any credentials.
    data = command('bash', '-c', 'source "$1"; printf "%s\\n%s\\n" "$WAYLAND_DISPLAY" "$SWAYSOCK"',
                   'bash', str(path)).splitlines()
    env = dict(os.environ)
    env.pop('DISPLAY', None)
    env.update(WAYLAND_DISPLAY=data[0], SWAYSOCK=data[1], XDG_CURRENT_DESKTOP='sway')
    return env


def windows(env):
    tree = json.loads(subprocess.check_output(['swaymsg', '-t', 'get_tree', '-r'], env=env))
    found = {}
    def visit(node):
        chrome_process = False
        if node.get('pid'):
            with contextlib.suppress(OSError):
                chrome_process = Path(os.readlink(f"/proc/{node['pid']}/exe")).name == 'chrome'
        if chrome_process or node.get('app_id') == 'google-chrome' or node.get('window_properties', {}).get('class') == 'Google-chrome':
            found[node['id']] = node
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            visit(child)
    visit(tree)
    return found


def ensure_chrome_on_display(data_dir, env):
    lock = data_dir / 'SingletonLock'
    if not lock.is_symlink():
        return
    try:
        pid = int(os.readlink(lock).rsplit('-', 1)[1])
        # Chrome can sanitize its environment after starting. Sway's reported
        # client PID is authoritative for an existing window on this seat.
        if any(node.get('pid') == pid for node in windows(env).values()):
            return
        raw = Path(f'/proc/{pid}/environ').read_bytes().split(b'\0')
        process_env = dict(item.split(b'=', 1) for item in raw if b'=' in item)
    except (ValueError, FileNotFoundError, ProcessLookupError):
        return  # Chrome itself decides whether a stale singleton lock is usable.
    if process_env.get(b'WAYLAND_DISPLAY', b'').decode() != env['WAYLAND_DISPLAY']:
        raise RuntimeError('This Chrome installation is already running on another display. '
                           'Close its existing windows normally before opening its profiles in Sway; '
                           'the menu will not terminate that browser.')
