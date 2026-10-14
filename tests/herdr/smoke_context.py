#!/usr/bin/env python3
"""Real Sway/Kitty/Chrome/Mako acceptance on an isolated disposable desktop.

No Herdr server, credentials or user profile is used. A read-only snapshot
fixture and local chat SPA stand in for Herdr. Runtime/PID/IPC, network, D-Bus,
HOME and every XDG directory are private. Logs remain in the printed temp dir.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'home/dot_local/bin'


def run(argv, **kwargs):
    kwargs.setdefault('timeout', 30)
    kwargs.setdefault('capture_output', True)
    value = subprocess.run([str(x) for x in argv], text=True, **kwargs)
    if value.returncode:
        raise AssertionError(f'{argv}: exit {value.returncode}\n{value.stdout}\n{value.stderr}')
    return value.stdout


def wait(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError('Timed out: ' + description)


def binary(name, pattern=None):
    if path := shutil.which(name):
        return str(Path(path).resolve())
    matches = sorted(Path('/nix/store').glob(pattern or f'*-*/bin/{name}'))
    if not matches:
        raise SystemExit(f'Required installed binary missing: {name}')
    return str(matches[0])


def prepare(directory):
    for name in ['home', 'config', 'data', 'state', 'cache', 'bin', 'logs', 'empty-apps']:
        (directory / name).mkdir()
    paths = {name: binary(name, pattern) for name, pattern in [
        ('sway', '*-sway-1.12/bin/sway'), ('swaymsg', '*-sway-unwrapped-1.12/bin/swaymsg'),
        ('kitty', None), ('google-chrome-stable', None), ('mako', '*-mako-*/bin/mako'),
        ('makoctl', '*-mako-*/bin/makoctl'), ('notify-send', '*-libnotify-*/bin/notify-send')]}
    (directory / 'paths.json').write_text(json.dumps(paths))
    (directory / 'sway.conf').write_text('''font monospace 10
output HEADLESS-1 mode 1600x1000
output HEADLESS-2 mode 1200x900 position 1600 0
seat seat0 fallback true
xwayland disable
focus_follows_mouse no
default_border pixel 1
default_floating_border pixel 1
workspace_layout default
''' + '\n'.join(line for line in (ROOT / 'home/dot_config/sway/rules.conf').read_text().splitlines()
                    if 'herdr-context' in line or 'HerdrSwayContext' in line) + '\n')
    (directory / 'mako.conf').write_text('default-timeout=0\nignore-timeout=1\nmax-visible=10\n')
    # No activation/service dirs: neither bus can start a user's service.
    (directory / 'dbus.conf').write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen><policy context="default"><allow send_destination="*"/><allow send_type="error" send_requested_reply="false"/><allow receive_sender="*"/><allow receive_type="error" receive_requested_reply="false"/><allow own="*"/></policy></busconfig>
''')
    for name in ['herdr-context', 'herdr-picker', 'herdr-attention']:
        (directory / 'bin' / name).symlink_to(SCRIPTS / name)
    for name in ['swaymsg', 'notify-send']:
        (directory / 'bin' / name).symlink_to(paths[name])
    mock = directory / 'bin/herdr'
    mock.write_text('#!' + sys.executable + '\n' + '''import os, sys
from pathlib import Path
root = Path(os.environ['CONTEXT_FIXTURE'])
with (root / 'herdr-calls.log').open('a') as stream: stream.write(repr(sys.argv[1:]) + '\\n')
if sys.argv[1:] != ['api', 'snapshot']: raise SystemExit('Read-only fixture forbids this call')
if (root / 'offline').exists(): raise SystemExit('Fixture Herdr is temporarily unavailable')
print((root / 'snapshot.json').read_text())
''')
    mock.chmod(0o755)
    deny = directory / 'bin/systemctl'
    deny.write_text('#!' + sys.executable + '\nraise SystemExit("Service lifecycle operations are forbidden in this test")\n')
    deny.chmod(0o755)
    browser = directory / 'bin/fixture-browser'
    browser.write_text('#!' + sys.executable + '\nimport os,sys\nos.execv(' + repr(paths['google-chrome-stable']) + ', [' + repr(paths['google-chrome-stable']) + ', "--disable-background-networking", "--disable-component-update", "--disable-sync", "--password-store=basic", *sys.argv[1:]])\n')
    browser.chmod(0o755)
    return paths


def exercise(directory):
    assert Path.home() == directory / 'home'
    assert os.environ['XDG_STATE_HOME'] == str(directory / 'state')
    assert not os.environ.get('SWAYSOCK') and not os.environ.get('WAYLAND_DISPLAY')
    assert not (Path(os.environ['XDG_RUNTIME_DIR']) / 'bus').exists(), 'Refusing live runtime'
    paths = json.loads((directory / 'paths.json').read_text())
    children, receipts = [], []
    server = None
    core = None

    def start(name, argv):
        with (directory / 'logs' / (name + '.log')).open('w') as log:
            child = subprocess.Popen([str(x) for x in argv], stdout=log, stderr=subprocess.STDOUT)
        children.append((name, child))
        return child

    def query(kind='get_tree'):
        return json.loads(run([paths['swaymsg'], '-r', '-t', kind]))

    def ipc(command):
        result = json.loads(run([paths['swaymsg'], '-r', '--', command]))
        assert result and all(x.get('success') for x in result), (command, result)

    def windows():
        def walk(node, workspace=None):
            if node.get('type') == 'workspace':
                workspace = node
            if node.get('app_id'):
                yield node, workspace
            for child in node.get('nodes', []) + node.get('floating_nodes', []):
                yield from walk(child, workspace)
        return list(walk(query()))

    def window(cid):
        return next((n, w) for n, w in windows() if n['id'] == cid)

    def visible(cid, number=None):
        node, workspace = window(cid)
        return workspace['name'] != '__i3_scratch' and (number is None or workspace['num'] == number)

    def status():
        return json.loads(run([SCRIPTS / 'herdr-context', 'status', '--json']))

    def context(wid='wA'):
        return next(row for row in status()['contexts'] if row['workspace_id'] == wid)

    def action(*args):
        return run([SCRIPTS / 'herdr-context', *args])

    def terminal(name, title, app='herdr-projector'):
        start(name, [paths['kitty'], '--config', 'NONE', '--class', app, '--title', title,
                     '-o', 'shell_integration=disabled', '-o', 'confirm_os_window_close=0',
                     sys.executable, '-u', '-c', 'import time; print("persistent terminal fixture"); time.sleep(300)'])
        return wait(lambda: next((n['id'] for n, _ in windows() if n.get('name') == title), None), name)

    snapshot = {'workspaces': [], 'agents': [], 'panes': []}
    for suffix, slot, label in [('A', 1, 'abcdef'), ('B', 2, 'fedcba')]:
        wid = 'w' + suffix
        snapshot['workspaces'].append({'workspace_id': wid, 'label': f'client-slot-{slot}-{label}'})
        snapshot['agents'].append({'workspace_id': wid, 'pane_id': wid + ':p1', 'terminal_id': 't' + suffix,
                                   'agent': 'codex', 'agent_status': 'working', 'state_change_seq': 1,
                                   'terminal_title_stripped': 'Fixture task ' + suffix})
        snapshot['panes'].append({'workspace_id': wid, 'pane_id': wid + ':p1'})

    def save_snapshot():
        temp = directory / 'snapshot.new'
        temp.write_text(json.dumps(snapshot))
        temp.replace(directory / 'snapshot.json')

    def evaluate(expression, wid='wA'):
        target = core['app_target'](wid)
        return core['cdp'](target, 'Runtime.evaluate', {'expression': expression, 'returnByValue': True})['result'].get('value')

    class Chat(BaseHTTPRequestHandler):
        def do_GET(self):
            payload = b'''<!doctype html><title>Fixture Herdr Chat</title><textarea id="draft"></textarea><div id="pane"></div><script>
window.pageIdentity=crypto.randomUUID(); window.popstates=0;
function route(){document.getElementById('pane').textContent=new URL(location).searchParams.get('pane')}
window.addEventListener('popstate',()=>{window.popstates++;route()});route();</script>'''
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def log_message(self, *args):
            pass

    try:
        save_snapshot()
        server = ThreadingHTTPServer(('127.0.0.1', 0), Chat)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        os.environ['HERDR_WEB_URL'] = f'http://127.0.0.1:{server.server_port}/'
        sway = start('sway', [paths['sway'], '-c', directory / 'sway.conf'])
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        os.environ['SWAYSOCK'] = str(wait(lambda: next(runtime.glob('sway-ipc.*.sock'), None), 'private Sway'))
        os.environ['WAYLAND_DISPLAY'] = wait(lambda: next((p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock')), None), 'private Wayland')
        ipc('workspace number 1')
        terminal_id = terminal('terminal-a', 'strix: client-slot-1-abcdef')
        neighbor = terminal('neighbor', 'Neighbor stays put', 'fixture-neighbor')
        ipc(f'[con_id={terminal_id}] focus')
        before = window(terminal_id)[0]['rect']
        neighbor_before = window(neighbor)[0]['rect']
        core = runpy.run_path(str(SCRIPTS / 'herdr-context'))
        action('show', 'chat')
        row = context()
        chat_id = row['chat_id']
        wait(lambda: window(chat_id)[0]['focused'], 'Chat receives keyboard focus')
        assert window(chat_id)[0]['rect'] == before, ('Chat changed tile geometry', before, window(chat_id)[0]['rect'])
        assert window(neighbor)[0]['rect'] == neighbor_before, 'Neighbor geometry changed'
        assert re.fullmatch(r'chrome-.*-HerdrSwayContext', window(chat_id)[0]['app_id']), window(chat_id)[0]
        assert window(chat_id)[0]['border'] in ('pixel', 'none'), 'Unexpected title bar'
        assert not visible(terminal_id), 'Inactive Kitty is not hidden'
        core = runpy.run_path(str(SCRIPTS / 'herdr-context'))
        page_identity = evaluate('window.pageIdentity')
        evaluate('document.getElementById("draft").value="Unsent draft survives"')
        for _ in range(3):
            action('toggle')
            assert visible(terminal_id, 1) and not visible(chat_id)
            assert window(terminal_id)[0]['rect'] == before
            action('toggle')
            assert visible(chat_id, 1) and not visible(terminal_id)
            assert evaluate('document.getElementById("draft").value') == 'Unsent draft survives'
            assert evaluate('window.pageIdentity') == page_identity
        assert len([n for n, _ in windows() if re.fullmatch(r'chrome-.*-HerdrSwayContext', n.get('app_id', ''))]) == 1
        receipts.append('Real Wayland Chrome app_id, exact tile/neighbor geometry, focus, pixel borders, hidden companion, one browser window and preserved draft across six swaps.')
        for mode, command in [(1, 'fullscreen enable'), (2, 'fullscreen enable global')]:
            action('show', 'terminal')
            ipc(f'[con_id={terminal_id}] {command}')
            action('toggle')
            assert window(chat_id)[0]['fullscreen_mode'] == mode, ('Chat lost fullscreen tile state', mode)
            assert window(terminal_id)[0]['fullscreen_mode'] == 0, 'Hidden terminal retained fullscreen'
            action('toggle')
            assert window(terminal_id)[0]['fullscreen_mode'] == mode, ('Terminal lost fullscreen tile state', mode)
            assert window(chat_id)[0]['fullscreen_mode'] == 0, 'Hidden Chat retained fullscreen'
            ipc(f'[con_id={terminal_id}] fullscreen disable')
        action('show', 'chat')
        assert window(chat_id)[0]['rect'] == before
        receipts.append('Per-output and global fullscreen follow the visible view through round trips and normal tile geometry restores afterwards.')

        snapshot['panes'].append({'workspace_id': 'wA', 'pane_id': 'wA:p2'})
        save_snapshot()
        action('activate', '--workspace', 'wA', '--pane', 'wA:p2')
        assert evaluate('document.getElementById("pane").textContent') == 'wA:p2'
        assert evaluate('window.pageIdentity') == page_identity
        assert evaluate('document.getElementById("draft").value') == 'Unsent draft survives'
        assert evaluate('window.popstates') == 1
        receipts.append('Explicit pane activation dispatched SPA navigation without reload or draft loss.')

        ipc('rename workspace "1" to "1: Writing"')
        ipc('move workspace to output HEADLESS-2')
        action('show', 'terminal')
        action('show', 'chat')
        assert context()['sway_workspace'] == '1: Writing'
        assert window(chat_id)[1]['name'] == '1: Writing'
        ipc('workspace number 2')
        terminal_b = terminal('terminal-b', 'strix: client-slot-2-fedcba')
        action('show', 'chat')
        row_b = context('wB')
        assert row_b['chat_id'] != chat_id
        targets = [target for target in core['http_json']('/json/list') if target.get('type') == 'page' and target.get('url', '').startswith(os.environ['HERDR_WEB_URL'])]
        assert len(targets) == 2, ('Expected exactly two dedicated Chat pages', targets)
        assert window(row_b['chat_id'])[0]['pid'] == window(chat_id)[0]['pid'], 'Companions use different browser processes'
        assert len([n for n, _ in windows() if re.fullmatch(r'chrome-.*-HerdrSwayContext', n.get('app_id', ''))]) == 2
        action('activate', '--workspace', 'wA')
        run([SCRIPTS / 'herdr-picker', '--workspace', 'close'])
        assert not visible(terminal_id) and not visible(chat_id)
        run([SCRIPTS / 'herdr-picker', '--workspace', 'restore'])
        assert visible(chat_id, 1) and not visible(terminal_id)
        assert evaluate('document.getElementById("draft").value') == 'Unsent draft survives'
        receipts.append('Two workspace pairs share one dedicated Chrome profile; rename/output moves and pair close/restore retain identity and last Chat view.')

        action('activate', '--workspace', 'wB')
        mako = start('mako', [paths['mako'], '--config', directory / 'mako.conf'])
        wait(lambda: subprocess.run([paths['makoctl'], 'list'], capture_output=True).returncode == 0, 'Mako private D-Bus owner')
        daemon = start('attention', [SCRIPTS / 'herdr-attention', '--interval', '1'])
        attention_file = directory / 'state/herdr-context/attention.json'
        wait(attention_file.exists, 'attention baseline')
        snapshot['agents'][0].update(agent_status='blocked', state_change_seq=2)
        save_snapshot()
        wait(lambda: window(chat_id)[0]['urgent'], 'Chat represents waiting urgency')
        notifications = wait(lambda: (text if 'Herdr' in (text := run([paths['makoctl'], 'list'])) and '1: Writing' in text else None), 'waiting notification')
        assert next(w for w in query('get_workspaces') if w['focused'])['num'] == 2, 'Notification stole focus'
        assert not window(terminal_id)[0]['urgent'], 'Hidden Kitty carries urgency'
        time.sleep(2.2)
        assert run([paths['makoctl'], 'list']) == notifications, 'Repeated poll duplicated notification'
        run([paths['makoctl'], 'invoke'])
        wait(lambda: window(chat_id)[0]['focused'], 'notification activation reveals exact workspace chat')
        wait(lambda: not window(chat_id)[0]['urgent'], 'visit acknowledges urgency')
        saved = wait(lambda: (record if (record := json.loads(attention_file.read_text())['records']['wA/wA:p1']).get('seen') else None), 'attention acknowledgement persisted')
        assert saved['waiting'] and saved['seen'], 'Visit must not answer the question'
        assert evaluate('document.getElementById("pane").textContent') == 'wA:p1'
        receipts.append('Real Mako notification and Sway urgency fire once, do not steal focus, target the visible companion, and activate the right workspace/pane; visiting acknowledges without answering.')

        (directory / 'offline').touch()
        wait(lambda: 'snapshot unavailable' in (directory / 'logs/attention.log').read_text(), 'daemon observes Herdr disconnect')
        action('show', 'terminal')
        assert visible(terminal_id, 1)
        (directory / 'offline').unlink()
        wait(lambda: 'connection restored' in (directory / 'logs/attention.log').read_text(), 'daemon reconnects')
        action('show', 'chat')
        assert evaluate('document.getElementById("draft").value') == 'Unsent draft survives'
        action('activate', '--workspace', 'wB')
        before_restart = run([paths['makoctl'], 'list'])
        daemon.terminate()
        assert daemon.wait(timeout=6) == 0
        daemon = start('attention-restarted', [SCRIPTS / 'herdr-attention', '--interval', '1'])
        time.sleep(2.2)
        assert not window(chat_id)[0]['urgent'], 'Seen waiting request became urgent after daemon restart'
        assert run([paths['makoctl'], 'list']) == before_restart, 'Daemon restart replayed a seen notification'
        action('activate', '--workspace', 'wA')
        ipc(f'[con_id={chat_id}] kill')
        wait(lambda: visible(terminal_id, 1), 'closing Chat automatically restores Kitty', timeout=20)
        action('show', 'chat')
        new_chat = context()['chat_id']
        assert new_chat != chat_id
        assert len([n for n, _ in windows() if re.fullmatch(r'chrome-.*-HerdrSwayContext', n.get('app_id', ''))]) == 2
        assert sway.poll() is None and mako.poll() is None and daemon.poll() is None
        receipts.append('Offline terminal return preserves sessions; reconnect preserves the browser draft; closing Chat restores Kitty and one replacement app opens on demand.')
        run([paths['makoctl'], 'dismiss', '--all'])
        old_browser_pid = window(new_chat)[0]['pid']
        core['cdp'](core['http_json']('/json/version'), 'Browser.close', {})
        wait(lambda: not any(re.fullmatch(r'chrome-.*-HerdrSwayContext', n.get('app_id', '')) for n, _ in windows()), 'dedicated browser closes completely')
        wait(lambda: visible(terminal_id, 1) and visible(terminal_b, 2), 'both terminals restore after browser exit', timeout=20)
        ipc(f'[con_id={terminal_id}] focus')
        snapshot['agents'][1].update(agent_status='blocked', state_change_seq=2)
        save_snapshot()
        wait(lambda: window(terminal_b)[0]['urgent'], 'terminal urgency with no browser')
        wait(lambda: 'Herdr' in run([paths['makoctl'], 'list']), 'notification with no browser')
        run([paths['makoctl'], 'invoke'])
        reopened = wait(lambda: next((n for n, _ in windows() if 'herdr-context-wB-chat' in n.get('marks', []) and n.get('focused')), None), 'notification launches first dedicated browser', timeout=25)
        assert reopened['pid'] != old_browser_pid
        assert evaluate('document.getElementById("pane").textContent', 'wB') == 'wB:p1'
        daemon.terminate()
        assert daemon.wait(timeout=6) == 0
        daemon = start('attention-after-action', [SCRIPTS / 'herdr-attention', '--interval', '1'])
        time.sleep(1.5)
        assert visible(reopened['id'], 2) and daemon.poll() is None
        receipts.append('With the entire dedicated browser stopped, a notification launches the correct first Chat via Sway; that browser survives an attention-daemon restart.')
        (directory / 'final-tree.json').write_text(json.dumps(query(), indent=2))
        (directory / 'results.json').write_text(json.dumps(receipts, indent=2))
        print('\n'.join(receipts), flush=True)
    finally:
        if os.environ.get('SWAYSOCK'):
            try:
                (directory / 'exit-tree.json').write_text(json.dumps(query(), indent=2))
                processes = {}
                for node, _ in windows():
                    pid = node.get('pid')
                    while pid and pid > 1 and pid not in processes:
                        proc = Path('/proc') / str(pid)
                        try:
                            environment = [entry.decode() for entry in (proc / 'environ').read_bytes().split(b'\0') if entry.startswith(b'HERDR_CONTEXT_BROWSER_PROFILE=')]
                        except OSError as error:
                            environment = str(error)
                        processes[pid] = {'args': (proc / 'cmdline').read_bytes().decode().split('\0'),
                                          'profile_environment': environment,
                                          'owns_browser': core['own_browser']({'pid': pid}) if core else None}
                        parent = next(line for line in (proc / 'status').read_text().splitlines() if line.startswith('PPid:'))
                        pid = int(parent.split()[1])
                (directory / 'exit-processes.json').write_text(json.dumps(processes, indent=2))
            except (OSError, AssertionError, StopIteration) as error:
                print(f'Desktop exit diagnostics: {error}', file=sys.stderr)
        # Stop the attention owner while its windows still exist, so normal
        # shutdown clears urgency before closing the dedicated browser.
        for name, child in children:
            if name.startswith('attention') and child.poll() is None:
                child.terminate()
                child.wait(timeout=6)
        if core:
            try:
                browser = core['http_json']('/json/version')
                (directory / 'browser-processes.json').write_text(json.dumps(core['cdp'](browser, 'SystemInfo.getProcessInfo', {}), indent=2))
            except (OSError, ValueError, core['Error']) as error:
                print(f'Chrome process diagnostics: {error}', file=sys.stderr)
            try:
                targets = core['http_json']('/json/list')
                (directory / 'browser-targets.json').write_text(json.dumps(targets, indent=2))
                if targets:
                    core['cdp'](targets[0], 'Browser.close', {})
            except (OSError, ValueError, core['Error']) as error:
                print(f'Chrome cleanup: {error}', file=sys.stderr)
        if server:
            server.shutdown()
            server.server_close()
        for name, child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                    print(f'{name}: shutdown required SIGKILL', file=sys.stderr)
            elif child.returncode:
                print(f'{name}: exited unexpectedly with {child.returncode}; inspect logs', file=sys.stderr)
        print(f'Artifacts retained: {directory}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inside', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        exercise(args.inside)
        return
    wrapper = Path.home() / '.local/bin/runtime-test'
    if not wrapper.is_file() or not shutil.which('bwrap'):
        raise SystemExit('runtime-test and bubblewrap are required; refusing live-runtime tests')
    directory = Path(tempfile.mkdtemp(prefix='herdr-context-smoke-'))
    prepare(directory)
    environment = {key: value for key, value in os.environ.items() if not key.startswith(('HERDR_', 'KITTY_', 'PROJECT_'))}
    environment.update(HOME=str(directory / 'home'), XDG_CONFIG_HOME=str(directory / 'config'),
                       XDG_STATE_HOME=str(directory / 'state'), XDG_DATA_HOME=str(directory / 'data'),
                       XDG_CACHE_HOME=str(directory / 'cache'), XDG_CONFIG_DIRS=str(directory / 'config'),
                       XDG_DATA_DIRS=str(directory / 'empty-apps'), CONTEXT_FIXTURE=str(directory),
                       HERDR_SWAY_LOCAL='1', HERDR_PICKER_HOSTNAME='strix',
                       HERDR_CONTEXT_BROWSER=str(directory / 'bin/fixture-browser'),
                       HERDR_CONTEXT_STATE_DIR=str(directory / 'state/herdr-context'),
                       PATH=f'{directory / "bin"}:{os.environ["PATH"]}', WLR_BACKENDS='headless',
                       WLR_HEADLESS_OUTPUTS='2', WLR_RENDERER='pixman', LIBGL_ALWAYS_SOFTWARE='1',
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-context-test-system-bus',
                       XDG_SESSION_TYPE='wayland', XDG_CURRENT_DESKTOP='sway-physical', NO_AT_BRIDGE='1')
    print(f'Isolated Herdr context desktop test: {directory}', flush=True)
    command = [wrapper, '--', 'bwrap', '--die-with-parent', '--unshare-net', '--bind', '/', '/', '--dev', '/dev',
               '--tmpfs', '/tmp/.X11-unix', '--chmod', '1777', '/tmp/.X11-unix', '--',
               'dbus-run-session', '--config-file', directory / 'dbus.conf', '--', sys.executable,
               Path(__file__).resolve(), '--inside', directory]
    # Stream progress/errors from this isolated child; every generated log remains.
    subprocess.run([str(x) for x in command], env=environment, check=True, timeout=240)


if __name__ == '__main__':
    main()
