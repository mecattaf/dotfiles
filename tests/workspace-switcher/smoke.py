#!/usr/bin/env python3
"""Run ONLY through runtime-test: an isolated two-output Sway, the real Fuzzel, a stub Herdr.

The seat mirrors the Zenbook as captured at 02:21 on 2026-10-14 (test_fixtures.py):
HEADLESS-1 is the top display with 1, 2, 3, 8, 9 and 10; HEADLESS-2 the bottom
with 4 and 5. Kitty windows stand in for the projectors (app_id herdr-projector,
title herdr-sway-projector, the live slot and label marks) and for the Chrome
windows on 5, 8 and 9. The stub `herdr api snapshot` carries the five live
labels, so rows read "assigned <status>". Codex's checks stay: a real Mod+i
opens and toggles the menu on the top output while the bottom is focused, the
bottom output's pixels do not change, 10 is selected by name without moving 4,
Escape cancels. Added: 5 is excluded with 4, 8 and 9 are listed, an empty slot
(7) is opened by number on the top output.

    runtime-test -- python3 tests/workspace-switcher/smoke.py [--evidence DIR]
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
SWAY = '/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/sway'
FUZZEL = '/nix/store/32iwmf6ipnxnnzcvmlrnxdbk1x1cq3qc-fuzzel-1.14.1/bin'
WTYPE = '/nix/store/bx230ccz3klvqr2fxgjz10w1r3m45grq-wtype-0.4/bin/wtype'
GRIM = '/nix/store/7scglgqhmxl5gj585y0h2nq699rspg4g-grim-1.5.0/bin/grim'
HELPER = ROOT / 'home/dot_local/bin/sway-workspace-switcher'
TOP, BOTTOM = 'HEADLESS-1', 'HEADLESS-2'

# (workspace, slot mark, label, status) for the five live projectors.
PROJECTORS = [(1, 1, 'client-slot-4-9690f0', 'working'),
              (2, 2, 'client-slot-2-d6929b', 'idle'),
              (3, 3, 'client-slot-3-02c703', 'done'),
              (10, 5, 'client-slot-5-fc4d18', 'working'),
              (4, 4, 'client-slot-4-6a3fb5', 'working')]
STAND_INS = [5, 8, 9]  # the live seat's Chrome windows; any window keeps a workspace alive
EXPECTED_ROWS = [1, 2, 3, 6, 7, 8, 9, 10]
SNAPSHOT = {'workspaces': [{'workspace_id': f'w{i}', 'label': label, 'agent_status': status}
                           for i, (_, _, label, status) in enumerate(PROJECTORS)],
            'agents': []}


def run(*args, timeout=10):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, check=True, timeout=timeout)


def wait(fn, label, seconds=10):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError(label)


def walk(node, workspace=None):
    if node.get('type') == 'workspace':
        workspace = node
    yield node, workspace
    for child in node.get('nodes', []) + node.get('floating_nodes', []):
        yield from walk(child, workspace)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, help='directory for logs, rows and screenshots (default: a new temp dir)')
    args = parser.parse_args()
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    assert not (runtime / 'bus').exists(), 'Refusing a live user runtime'
    assert not Path('/dev/input').exists(), 'Refusing a seat with real input devices'
    evidence = args.evidence or Path(tempfile.mkdtemp(prefix='sway-switcher-smoke-'))
    (evidence / 'bin').mkdir(parents=True, exist_ok=True)
    (evidence / 'config/theme').mkdir(parents=True, exist_ok=True)
    print(f'Evidence: {evidence}', flush=True)
    stub = evidence / 'bin/herdr'
    stub.write_text("#!/bin/sh\ncat <<'EOF'\n" + json.dumps(SNAPSHOT) + "\nEOF\n")
    stub.chmod(0o755)
    (evidence / 'bin/notify-send').write_text('#!/bin/sh\necho "notify-send: $*" >&2\n')
    (evidence / 'bin/notify-send').chmod(0o755)
    # The generation ships theme/kitty.conf and no desktop-shell.json: the parse-as-data branch.
    (evidence / 'config/theme/kitty.conf').write_text(
        'background #000000\nforeground #EAECF0\nselection_background #264F78\nselection_foreground #EAECF0\n'
        'url_color #70B8FF\ncolor8 #818898\n')
    config = evidence / 'sway.conf'
    config.write_text(f'''output {TOP} mode 1280x720 position 0 0 bg #D2D1C7 solid_color
output {BOTTOM} mode 1280x720 position 0 720 bg #52514E solid_color
workspace 1 output {TOP}
workspace 2 output {TOP}
workspace 3 output {TOP}
workspace 8 output {TOP}
workspace 9 output {TOP}
workspace 10 output {TOP}
workspace 4 output {BOTTOM}
workspace 5 output {BOTTOM}
xwayland disable
seat seat0 fallback true
bindsym Mod4+i exec {sys.executable} {HELPER} --output {TOP}
''')
    os.environ.update(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2', WLR_RENDERER='pixman',
                      WLR_LIBINPUT_NO_DEVICES='1', SWAY_DISABLE_SD_NOTIFY='1', LIBGL_ALWAYS_SOFTWARE='1',
                      DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent-test-bus',
                      DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-system-bus',
                      HERDR_SWAY_LOCAL='1', XDG_CURRENT_DESKTOP='sway', XDG_CONFIG_HOME=str(evidence / 'config'),
                      PATH=str(evidence / 'bin') + ':' + FUZZEL + ':' + str(Path(SWAY).parent) + ':' + os.environ['PATH'])
    log = (evidence / 'sway.log').open('w')
    sway = subprocess.Popen([SWAY, '--unsupported-gpu', '-c', str(config)], stdout=log, stderr=subprocess.STDOUT)

    def query(name):
        return json.loads(run('swaymsg', '-r', '-t', name).stdout)

    def command(value):
        run('swaymsg', '-r', '--', value)

    def toggles():
        return list((runtime / 'sway-workspace-switcher').glob('*.sock'))

    def chord():
        run(WTYPE, '-M', 'logo', '-k', 'i', '-m', 'logo')

    def shot(output, name):
        run(GRIM, '-o', output, evidence / name)

    def views_on(number, app_id):
        return [n for n, w in walk(query('get_tree')) if w and w.get('num') == number and n.get('app_id') == app_id]

    def window(number, app_id, title):
        command(f'workspace number {number}')
        child = subprocess.Popen(['kitty', '--config', 'NONE', '--class', app_id, '--title', title,
                                  '-o', 'shell_integration=disabled', '-o', 'allow_remote_control=no',
                                  '-o', 'cursor_blink_interval=0',
                                  # The cursor is hidden: a blinking or focus-shaped cursor on the bottom
                                  # window would differ between the before and during screenshots.
                                  sys.executable, '-c', 'import sys, time; sys.stdout.write("\\x1b[?25l"); sys.stdout.flush(); time.sleep(900)'],
                                 stdout=log, stderr=subprocess.STDOUT)
        children.append(child)
        return wait(lambda: next(iter(views_on(number, app_id)), None), f'window {title} on {number}', 30)

    children = []
    keyboard = None
    checks = []
    try:
        sock = wait(lambda: next(iter(runtime.glob('sway-ipc*.sock')), None), 'Sway IPC')
        os.environ['SWAYSOCK'] = str(sock)
        wayland = wait(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None), 'Wayland')
        os.environ['WAYLAND_DISPLAY'] = wayland.name
        keyboard = subprocess.Popen([WTYPE, '-s', '120000'], stdout=log, stderr=subprocess.STDOUT)
        time.sleep(.2)
        for number, slot, label, _ in PROJECTORS:
            view = window(number, 'herdr-projector', 'herdr-sway-projector')
            command(f'[con_id={view["id"]}] mark --add herdr-slot-{slot}')
            command(f'[con_id={view["id"]}] mark --add herdr-label-{label}')
        for number in STAND_INS:
            window(number, 'chrome-stand-in', 'design studies')
        command('workspace number 10')
        command('workspace number 5')  # the bottom display is focused, as on the live seat
        before = query('get_workspaces')
        (evidence / 'before.json').write_text(json.dumps(before, indent=2))
        placed = {w['num']: w['output'] for w in before}
        assert all(placed[n] == TOP for n in (1, 2, 3, 8, 9, 10)), placed
        assert all(placed[n] == BOTTOM for n in (4, 5)), placed
        assert next(w for w in before if w['focused'])['num'] == 5
        checks.append('seat laid out as captured: 1 2 3 8 9 10 on top, 4 5 on bottom, 5 focused')

        rows = json.loads(run(sys.executable, HELPER, '--output', TOP, '--json').stdout)
        (evidence / 'rows.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False))
        assert rows['herdr_unavailable'] is False, rows
        slots = [r['slot'] for r in rows['workspaces']]
        assert slots == EXPECTED_ROWS, slots
        labels = {r['slot']: r['label'] for r in rows['workspaces']}
        assert 'assigned working' in labels[1] and 'assigned idle' in labels[2] and 'assigned done' in labels[3], labels
        assert 'assigned working' in labels[10], labels
        assert all('no Herdr projector' in labels[n] for n in (8, 9)), labels
        assert all('Empty workspace' in labels[n] for n in (6, 7)), labels
        checks.append('rows 1 2 3 6 7 8 9 10 (4 and 5 excluded); 1 2 3 10 read assigned <status> from the stub snapshot')

        shot(BOTTOM, 'bottom-before.png')
        shot(TOP, 'top-before.png')
        chord()
        wait(toggles, 'Mod+i launches own socket')
        time.sleep(.6)
        shot(TOP, 'top-menu.png')
        shot(BOTTOM, 'bottom-during.png')
        assert ImageChops.difference(Image.open(evidence / 'bottom-before.png'), Image.open(evidence / 'bottom-during.png')).getbbox() is None, 'Lower output changed'
        assert ImageChops.difference(Image.open(evidence / 'top-before.png'), Image.open(evidence / 'top-menu.png')).getbbox() is not None, 'No menu drawn on the top output'
        checks.append('real Mod+i opens the menu on the top output while the bottom is focused; bottom pixels unchanged')
        chord()
        wait(lambda: not toggles(), 'Second Mod+i closes menu')
        checks.append('second Mod+i closes only its own menu')

        chord()
        wait(toggles, 'Menu reopens')
        time.sleep(.4)
        run(WTYPE, '10')
        run(WTYPE, '-k', 'Return')
        wait(lambda: not toggles(), 'Selection closes')
        after = query('get_workspaces')
        (evidence / 'after-10.json').write_text(json.dumps(after, indent=2))
        ten = next(w for w in after if w['num'] == 10)
        assert ten['focused'] and ten['name'] == '10' and ten['output'] == TOP, ten
        assert {w['num']: w['output'] for w in after} == placed, 'a workspace moved or appeared'
        checks.append('typing 10 + Return selects the existing workspace by name; 4 and 5 stay on the bottom')

        chord()
        wait(toggles, 'Menu reopens for an empty slot')
        time.sleep(.4)
        run(WTYPE, '7')
        run(WTYPE, '-k', 'Return')
        wait(lambda: not toggles(), 'Empty-slot selection closes')
        after = query('get_workspaces')
        (evidence / 'after-7.json').write_text(json.dumps(after, indent=2))
        seven = next(w for w in after if w['num'] == 7)
        assert seven['focused'] and seven['output'] == TOP and seven['name'] == '7', seven
        assert {w['num']: w['output'] for w in after if w['num'] != 7} == placed
        shot(TOP, 'top-after-7.png')
        checks.append('typing 7 + Return opens the empty slot by number on the top output; nothing else moved')

        chord()
        wait(toggles, 'Menu reopens for Escape')
        time.sleep(.4)
        run(WTYPE, '-k', 'Escape')
        wait(lambda: not toggles(), 'Escape closes')
        checks.append('Escape cancels')
        result = {'ok': True, 'checks': checks, 'rows': slots,
                  'scope': 'Private headless Sway (pixman) and the real Fuzzel under runtime-test; '
                           'kitty windows stand in for projectors and Chrome; the Herdr snapshot is a read-only stub.'}
        (evidence / 'results.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result), flush=True)
    except BaseException:
        (evidence / 'results.json').write_text(json.dumps({'ok': False, 'checks': checks}, indent=2))
        raise
    finally:
        for child in children:
            child.terminate()
        for child in children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if keyboard:
            keyboard.terminate()
            keyboard.wait(timeout=3)
        sway.terminate()
        try:
            sway.wait(timeout=5)
        except subprocess.TimeoutExpired:
            sway.kill()
            sway.wait()
            print('Sway needed SIGKILL', file=sys.stderr)
        log.close()


if __name__ == '__main__':
    main()
