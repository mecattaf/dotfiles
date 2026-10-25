"""Run complete desktop helpers against fake commands, never a live compositor.

Use runtime-test -- python3 tests/desktop-control/test_helpers.py.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(os.environ.get('DESKTOP_SCRIPTS', Path(__file__).resolve().parents[2] / 'home/dot_local/bin'))
MOCK = r'''
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name == os.environ.get('FAIL_COMMAND'):
    print('fixture command failed', file=sys.stderr)
    sys.exit(3)
if name == 'hyprctl':
    if args[0] == '-j':
        print(os.environ.get('HYPR_' + args[1].upper(), '{}'))
    else:
        print(os.environ.get('DISPATCH_REPLY', 'ok'))
elif name == 'swaymsg':
    if 'get_outputs' in args:
        print(os.environ.get('SWAY_OUTPUTS', '[]'))
    elif 'get_tree' in args:
        print(os.environ.get('SWAY_TREE', '{}'))
    else:
        print(os.environ.get('DISPATCH_REPLY', '[{"success": true}]'))
elif name == 'slurp':
    print(os.environ.get('GEOMETRY', '1,2 30x40'))
elif name == 'hostname':
    print('strix')
elif name == 'grim':
    Path(args[-1]).write_bytes(b'fixture image')
elif name == 'wl-copy':
    sys.stdin.buffer.read()
'''


class DesktopHelpers(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('hyprctl', 'swaymsg', 'slurp', 'hostname', 'grim', 'wl-copy', 'satty',
                     'wf-recorder', 'notify-send', 'brightnessctl', 'swayidle'):
            script = self.bin / name
            script.write_text(f'#!{sys.executable}\n' + MOCK)
            script.chmod(0o755)
        # Nix checks supply the whole scripts directory; run the adapter with
        # this check's Python instead of depending on a patched shebang.
        control = self.bin / 'desktop-control'
        control.write_text(f'#!{sys.executable}\n' + (SCRIPTS / 'desktop-control').read_text().split('\n', 1)[1])
        control.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root / 'home'), CALLS=str(self.root / 'calls'),
                        PATH=f'{self.bin}:{os.environ["PATH"]}', SWAYSOCK='',
                        HYPRLAND_INSTANCE_SIGNATURE='fixture', XDG_CURRENT_DESKTOP='Hyprland',
                        HYPR_MONITORS='[{"name":"eDP-2","focused":true}]')

    def run_helper(self, name, *args, **environment):
        argv = [sys.executable, str(SCRIPTS / name)] if name == 'desktop-control' else ['bash', str(SCRIPTS / name)]
        return subprocess.run([*argv, *args], env=self.env | environment, text=True,
                              capture_output=True, timeout=5)

    def calls(self):
        path = self.root / 'calls'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_hyprland_focused_output_and_geometry(self):
        result = self.run_helper('desktop-control', 'focused-output')
        self.assertEqual((result.returncode, result.stdout), (0, 'eDP-2\n'))
        result = self.run_helper('desktop-control', 'focused-geometry',
                                 HYPR_ACTIVEWINDOW='{"at":[-100,20],"size":[400,300]}')
        self.assertEqual((result.returncode, result.stdout), (0, '-100,20 400x300\n'))

    def test_sway_geometry_keeps_content_offset_and_fallback_detection(self):
        tree = {'nodes': [{'focused': True, 'rect': {'x': 10, 'y': 20},
                           'window_rect': {'x': 2, 'y': 18, 'width': 500, 'height': 300}}]}
        result = self.run_helper('desktop-control', 'focused-geometry', SWAYSOCK='fixture',
                                 XDG_CURRENT_DESKTOP='sway-physical', SWAY_TREE=json.dumps(tree))
        self.assertEqual((result.returncode, result.stdout), (0, '12,38 500x300\n'))
        self.assertTrue(all(call[0] != 'hyprctl' for call in self.calls()))

    def test_no_focus_or_invalid_geometry_never_prints_capture_region(self):
        for data in ('{}', '{"at":[0,0],"size":[0,30]}', '{"at":[";bad",0],"size":[40,30]}'):
            with self.subTest(data=data):
                result = self.run_helper('desktop-control', 'focused-geometry', HYPR_ACTIVEWINDOW=data)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')

    def test_no_output_match_and_ambiguous_focus_fail_closed(self):
        for data in ('[]', '[{"name":"a","focused":true},{"name":"b","focused":true}]'):
            with self.subTest(data=data):
                result = self.run_helper('desktop-control', 'focused-output', HYPR_MONITORS=data)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')

    def test_headless_does_not_guess_or_call_a_compositor(self):
        result = self.run_helper('desktop-control', 'focused-output', HYPRLAND_INSTANCE_SIGNATURE='')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), [])

    def test_compositor_failure_propagates_before_capture(self):
        result = self.run_helper('screenshot', 'screen', FAIL_COMMAND='hyprctl')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fixture command failed', result.stderr)
        self.assertFalse(any(call[0] in ('grim', 'wl-copy') for call in self.calls()))

    def test_output_name_is_one_literal_recorder_argument(self):
        name = 'Display with spaces; $(never-execute)'
        result = self.run_helper('record', 'start', HYPR_MONITORS=json.dumps([{'name': name, 'focused': True}]))
        self.assertEqual(result.returncode, 0, result.stderr)
        recorder = next(call for call in self.calls() if call[0] == 'wf-recorder')
        self.assertEqual(recorder[recorder.index('-o') + 1], name)

    def test_cancelled_area_does_not_record_or_announce_start(self):
        result = self.run_helper('record', 'select', FAIL_COMMAND='slurp')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[0] in ('wf-recorder', 'notify-send') for call in self.calls()))

    def test_recorder_failure_is_visible(self):
        result = self.run_helper('record', 'start', FAIL_COMMAND='wf-recorder')
        self.assertEqual(result.returncode, 3)
        self.assertIn('fixture command failed', result.stderr)

    def test_hyprland_window_screenshot_uses_exact_rectangle(self):
        result = self.run_helper('screenshot', 'window', HYPR_ACTIVEWINDOW='{"at":[10,20],"size":[300,400]}')
        self.assertEqual(result.returncode, 0, result.stderr)
        capture = next(call for call in self.calls() if call[0] == 'grim')
        self.assertEqual(capture[1:3], ['-g', '10,20 300x400'])
        self.assertTrue(any(call[0] == 'wl-copy' for call in self.calls()))

    def test_hyprland_power_refusal_is_not_success(self):
        result = self.run_helper('desktop-control', 'power-off', DISPATCH_REPLY='invalid dispatcher')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), [['hyprctl', 'dispatch', 'dpms', 'off']])

    def test_sway_power_refusal_is_not_success(self):
        result = self.run_helper('desktop-control', 'power-on', HYPRLAND_INSTANCE_SIGNATURE='', SWAYSOCK='fixture',
                                 DISPATCH_REPLY='[{"success":false}]')
        self.assertEqual(result.returncode, 1)

    def test_monitors_off_arms_a_single_input_resume(self):
        result = self.run_helper('monitors-off')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [['swayidle', '-w', 'timeout', '1', 'desktop-control power-off',
                                         'resume', 'desktop-control power-on; kill $PPID']])


if __name__ == '__main__':
    unittest.main()
