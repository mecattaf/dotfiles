#!/usr/bin/env python3
"""Prove real Herdr client titles follow each Kitty's selected workspace.

This starts only disposable Herdr/Sway/Kitty instances through runtime-test,
with private home/config/runtime/D-Bus/network. No user server is contacted.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

from smoke_context import ROOT, binary, prepare, run, wait


def exercise(directory):
    assert Path.home() == directory / 'home'
    assert not os.environ.get('SWAYSOCK')
    assert not (Path(os.environ['XDG_RUNTIME_DIR']) / 'bus').exists()
    paths = json.loads((directory / 'paths.json').read_text())
    herdr = paths['herdr']
    children = []

    def start(name, argv):
        with (directory / 'logs' / (name + '.log')).open('w') as stream:
            child = subprocess.Popen([str(arg) for arg in argv], stdout=stream, stderr=subprocess.STDOUT, cwd=directory / 'home')
        children.append((name, child))
        return child

    def tree():
        return json.loads(run([paths['swaymsg'], '-r', '-t', 'get_tree']))

    def views():
        def walk(node):
            if node.get('app_id'):
                yield node
            for child in node.get('nodes', []) + node.get('floating_nodes', []):
                yield from walk(child)
        return list(walk(tree()))

    def ipc(command):
        result = json.loads(run([paths['swaymsg'], '-r', '--', command]))
        assert all(item.get('success') for item in result), result

    def kitty(name):
        before = {n['id'] for n in views()}
        sock = directory / (name + '.sock')
        start(name, [paths['kitty'], '--config', 'NONE', '--class', 'herdr-projector',
                     '--listen-on', 'unix:' + str(sock), '-o', 'allow_remote_control=yes',
                     '-o', 'shell_integration=disabled', '-o', 'confirm_os_window_close=0', herdr, 'client'])
        node = wait(lambda: next((n for n in views() if n['id'] not in before), None), name)
        wait(sock.exists, name + ' remote control')
        return node['id'], sock

    def remote(sock, *args):
        return run([paths['kitten'], '@', '--to', 'unix:' + str(sock), *args])

    def title(cid):
        return next(n['name'] for n in views() if n['id'] == cid)

    try:
        start('sway', [paths['sway'], '-c', directory / 'sway.conf'])
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        os.environ['SWAYSOCK'] = str(wait(lambda: next(runtime.glob('sway-ipc.*.sock'), None), 'Sway'))
        os.environ['WAYLAND_DISPLAY'] = wait(lambda: next((p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock')), None), 'Wayland')
        os.environ['HERDR_SOCKET_PATH'] = str(runtime / 'title-proof-herdr.sock')
        start('herdr-server', [herdr, 'server'])
        wait(lambda: Path(os.environ['HERDR_SOCKET_PATH']).exists(), 'private Herdr API socket')
        run([herdr, 'workspace', 'create', '--label', 'title-proof-a', '--cwd', directory / 'home', '--focus'])
        first, sock_a = kitty('kitty-a')
        hostname = socket.gethostname()
        wait(lambda: title(first) == hostname + ': title-proof-a', 'first actual Herdr workspace title')
        second, sock_b = kitty('kitty-b')
        wait(lambda: title(second) == hostname + ': title-proof-a', 'second client initial title')
        remote(sock_b, 'send-key', 'ctrl+b')
        remote(sock_b, 'send-key', 'shift+n')
        wait(lambda: 'new workspace' in remote(sock_b, 'get-text', '--extent', 'screen'), 'client-local workspace form')
        remote(sock_b, 'send-text', 'title-proof-b')
        remote(sock_b, 'send-key', 'enter')
        wait(lambda: title(second) == hostname + ': title-proof-b', 'second client local workspace title')
        assert title(first) == hostname + ': title-proof-a', 'Other client title changed with foreign selection'
        for cid, expected in [(first, 'title-proof-a'), (second, 'title-proof-b'), (first, 'title-proof-a')]:
            ipc(f'[con_id={cid}] focus')
            wait(lambda: title(cid) == hostname + ': ' + expected, 'focused client local title')
        # Global read-only roster and both independently selected titles agree.
        snapshot = json.loads(run([herdr, 'api', 'snapshot']))
        (directory / 'snapshot.json').write_text(json.dumps(snapshot, indent=2))
        (directory / 'tree.json').write_text(json.dumps(tree(), indent=2))
        assert title(first) == hostname + ': title-proof-a'
        assert title(second) == hostname + ': title-proof-b'
        # Apply the same supported configuration reload to only this fixture.
        run([herdr, 'server', 'reload-config'])
        assert all(child.poll() is None for _, child in children), 'A fixture unexpectedly exited'
        print('PASS: actual Herdr server, two Kitty clients, independent workspace titles, supported live config reload', flush=True)
    finally:
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
                print(f'{name}: unexpected exit {child.returncode}; inspect logs', file=sys.stderr)
        print('Title proof artifacts: ' + str(directory), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inside', type=Path)
    args = parser.parse_args()
    if args.inside:
        exercise(args.inside)
        return
    wrapper = Path.home() / '.local/bin/runtime-test'
    if not wrapper.is_file() or not shutil.which('bwrap'):
        raise SystemExit('runtime-test and bubblewrap required; refusing live runtime')
    directory = Path(tempfile.mkdtemp(prefix='herdr-title-smoke-'))
    paths = prepare(directory)
    paths.update(herdr=binary('herdr'), kitten=binary('kitten'))
    (directory / 'paths.json').write_text(json.dumps(paths))
    source = (ROOT / 'home/dot_config/herdr/config.toml').read_text()
    # Same UI override delivered by home/herdr.nix for Sway clients. Neither
    # the test nor Herdr may write to the tracked source config.
    (directory / 'herdr.toml').write_text(source.replace('[ui]\n', '[ui]\nprompt_new_workspace_name = true\n'))
    environment = {key: value for key, value in os.environ.items() if not key.startswith(('HERDR_', 'KITTY_', 'PROJECT_'))}
    environment.update(HOME=str(directory / 'home'), XDG_CONFIG_HOME=str(directory / 'config'),
                       XDG_STATE_HOME=str(directory / 'state'), XDG_DATA_HOME=str(directory / 'data'),
                       XDG_CACHE_HOME=str(directory / 'cache'), XDG_CONFIG_DIRS=str(directory / 'config'),
                       XDG_DATA_DIRS=str(directory / 'empty-apps'), HERDR_CONFIG_PATH=str(directory / 'herdr.toml'),
                       WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='pixman',
                       LIBGL_ALWAYS_SOFTWARE='1', DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-title-test-bus',
                       XDG_SESSION_TYPE='wayland', XDG_CURRENT_DESKTOP='sway-physical', NO_AT_BRIDGE='1')
    command = [wrapper, '--', 'bwrap', '--die-with-parent', '--unshare-net', '--bind', '/', '/', '--dev', '/dev',
               '--tmpfs', '/tmp/.X11-unix', '--chmod', '1777', '/tmp/.X11-unix', '--',
               'dbus-run-session', '--config-file', directory / 'dbus.conf', '--', sys.executable,
               Path(__file__).resolve(), '--inside', directory]
    print('Isolated real Herdr title test: ' + str(directory), flush=True)
    subprocess.run([str(x) for x in command], env=environment, check=True, timeout=120)


if __name__ == '__main__':
    main()
