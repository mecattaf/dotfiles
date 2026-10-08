"""Exercise launcher behavior without touching a desktop, SSH, or Herdr server."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('HERDR_SCRIPTS', Path(__file__).resolve().parents[2] / 'home/dot_local/bin'))
MOCK = r'''
import json, os, signal, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ['FIXTURE'])
with (root / 'calls').open('a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'niri':
    if args == ['msg', '-j', 'focused-window']:
        print(json.dumps({'app_id': os.environ.get('FOCUSED_APP', 'herdr-projector'), 'pid': 100}))
    elif args == ['msg', '-j', 'workspaces']:
        print(json.dumps([{'output': 'eDP-1', 'is_focused': True, 'idx': 1}, {'output': 'eDP-1', 'is_focused': False, 'idx': 4}]))
    elif args[:3] == ['msg', 'action', 'spawn']:
        (root / 'spawned').touch()
    elif args == ['msg', '-j', 'windows']:
        rows = [{'app_id': 'herdr-projector', 'id': 1, 'pid': 100}]
        if (root / 'spawned').exists():
            rows.append({'app_id': 'herdr-projector', 'id': 2, 'pid': 200})
        print(json.dumps(rows))
elif name == 'scrollmsg':
    def tree():
        views = [{'type': 'con', 'id': 11, 'app_id': 'herdr-projector', 'pid': 100,
                  'focused': os.environ.get('FOCUSED_APP', 'herdr-projector') == 'herdr-projector',
                  'nodes': [], 'floating_nodes': []},
                 {'type': 'con', 'id': 12, 'app_id': 'other', 'pid': 150,
                  'focused': os.environ.get('FOCUSED_APP') == 'other', 'nodes': [], 'floating_nodes': []}]
        if (root / 'spawned').exists():
            views.append({'type': 'con', 'id': 13, 'app_id': 'herdr-projector', 'pid': 200,
                          'focused': False, 'nodes': [], 'floating_nodes': []})
        if os.environ.get('FOCUSED_EMPTY'):
            for v in views:
                v['focused'] = False
            busy = {'type': 'workspace', 'name': '1', 'num': 1, 'nodes': views, 'floating_nodes': []}
            empty = {'type': 'workspace', 'name': '3', 'num': 3, 'focused': True, 'nodes': [], 'floating_nodes': []}
            wss = [busy, empty]
        else:
            wss = [{'type': 'workspace', 'name': '1', 'num': 1, 'nodes': views, 'floating_nodes': []},
                   {'type': 'workspace', 'name': '4', 'num': 4, 'nodes': [], 'floating_nodes': []}]
        scratch = {'type': 'workspace', 'name': '__i3_scratch', 'num': -1, 'nodes': [], 'floating_nodes': []}
        out = {'type': 'output', 'name': 'eDP-1', 'nodes': wss}
        return {'type': 'root', 'nodes': [{'type': 'output', 'name': '__i3', 'nodes': [scratch]}, out]}
    if args[-2:] == ['-t', 'get_tree']:
        print(json.dumps(tree()))
    elif len(args) >= 2 and args[-1].startswith('exec '):
        (root / 'spawned').touch()
        print('[{"success": true}]')
    else:
        print('[{"success": true}]')
elif name == 'kitten' and args[-1] == 'ls':
    print(json.dumps([{'tabs': [{'windows': [{'foreground_processes': [{'cmdline': ['/bin/herdr', 'client'], 'pid': 300}]}]}]}]))
elif name == 'systemctl':
    sys.exit(int(os.environ.get('UNIT_STATUS', '0')))
elif name == 'ssh':
    print(os.environ.get('SSH_OUTPUT', ''), file=sys.stderr)
    sys.exit(int(os.environ.get('SSH_STATUS', '1')))
elif name == 'sleep' and os.environ.get('STOP_BACKOFF'):
    os.kill(os.getppid(), signal.SIGTERM)
'''


class Launchers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('niri', 'scrollmsg', 'kitten', 'ssh', 'sleep', 'herdr', 'systemctl'):
            p = self.bin / name
            p.write_text('#!' + os.sys.executable + '\n' + MOCK)
            p.chmod(0o755)
        log = self.root / 'client.log'
        log.write_text('herdr starting version=fixture pid=300\nendpoint handshake succeeded\n')
        self.env = dict(os.environ, FIXTURE=str(self.root), PATH=f'{self.bin}:{os.environ["PATH"]}',
                        HERDR_CLIENT_LOG=str(log), TMPDIR=str(self.root), HERDR_CHORD_TIMEOUT='2',
                        HERDR_CHORD_WM='niri')

    def run_script(self, name, *args, **env):
        return subprocess.run(['bash', str(ROOT / name), *args], env=self.env | env,
                              capture_output=True, text=True, timeout=5)

    def calls(self):
        return [json.loads(x) for x in (self.root / 'calls').read_text().splitlines()]

    def test_local_sway_projector_attaches_without_ssh_or_auto_start(self):
        p = self.run_script('herdr-sway-projector', HERDR_SWAY_LOCAL='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.calls(), [['systemctl', '--user', '--quiet', 'is-active', 'herdr.service'], ['herdr', 'client']])

    def test_local_sway_projector_refuses_inactive_server(self):
        p = self.run_script('herdr-sway-projector', HERDR_SWAY_LOCAL='1', UNIT_STATUS='3')
        self.assertEqual(p.returncode, 1)
        self.assertIn('refusing to start', p.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_new_preserves_focused_projector(self):
        p = self.run_script('herdr-chord', 'new')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.root / 'spawned').exists())
        calls = self.calls()
        self.assertIn(['niri', 'msg', 'action', 'focus-workspace', '4'], calls)
        keys = [x for x in calls if 'send-key' in x]
        self.assertEqual(len(keys), 2)
        self.assertTrue(all('unix:@kitty-200' in x for x in keys))
        self.assertEqual(keys[-1][-1], 'shift+n')

    def test_sidebar_opens_another_window(self):
        p = self.run_script('herdr-chord', 'sidebar')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.root / 'spawned').exists())
        self.assertEqual([x for x in self.calls() if 'send-key' in x][-1][-1], 'b')

    def test_rename_targets_existing_window(self):
        p = self.run_script('herdr-chord', 'rename')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((self.root / 'spawned').exists())
        keys = [x for x in self.calls() if 'send-key' in x]
        self.assertTrue(all('unix:@kitty-100' in x for x in keys))
        self.assertEqual(keys[-1][-1], 'shift+w')

    def test_rename_outside_projector_is_noop(self):
        p = self.run_script('herdr-chord', 'rename', FOCUSED_APP='other')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse(any('send-key' in x for x in self.calls()))

    # scroll (scroll/transition): the same chords over scrollmsg.
    def test_scroll_new_opens_fresh_workspace_and_spawns(self):
        p = self.run_script('herdr-chord', 'new', HERDR_CHORD_WM='scroll')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.root / 'spawned').exists())
        calls = self.calls()
        self.assertFalse(any(x[0] == 'niri' for x in calls))
        self.assertIn(['scrollmsg', '-r', '--', 'workspace number 5'], calls)
        spawn = [x for x in calls if x[0] == 'scrollmsg' and x[-1].startswith('exec ')]
        self.assertEqual(len(spawn), 1)
        self.assertIn('kitty --class herdr-projector -e ', spawn[0][-1])
        keys = [x for x in calls if 'send-key' in x]
        self.assertTrue(all('unix:@kitty-200' in x for x in keys))
        self.assertEqual(keys[-1][-1], 'shift+n')

    def test_scroll_new_stays_on_empty_workspace(self):
        p = self.run_script('herdr-chord', 'new', HERDR_CHORD_WM='scroll', FOCUSED_EMPTY='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse(any(x[0] == 'scrollmsg' and x[-1].startswith('workspace') for x in self.calls()))
        self.assertTrue((self.root / 'spawned').exists())

    def test_scroll_rename_targets_focused_projector(self):
        p = self.run_script('herdr-chord', 'rename', HERDR_CHORD_WM='scroll')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((self.root / 'spawned').exists())
        keys = [x for x in self.calls() if 'send-key' in x]
        self.assertTrue(all('unix:@kitty-100' in x for x in keys))
        self.assertEqual(keys[-1][-1], 'shift+w')

    def test_scroll_is_the_default_when_scrollsock_is_set(self):
        env = {k: v for k, v in self.env.items() if k not in ('HERDR_CHORD_WM', 'NIRI_SOCKET')}
        p = subprocess.run(['bash', str(ROOT / 'herdr-chord'), 'rename'], env=env | {'SCROLLSOCK': '/nonexistent'},
                           capture_output=True, text=True, timeout=5)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(any(x[0] == 'scrollmsg' for x in self.calls()))
        self.assertFalse(any(x[0] == 'niri' for x in self.calls()))

    def test_projector_diagnoses_failures_without_starting_unmanaged_server(self):
        cases = [
            ('1', 'Failed to connect to user scope bus via local transport: No such file or directory', 'Herdr may still be running'),
            ('255', 'ssh: connect to host strix: Connection refused', 'SSH connection to strix failed'),
            ('3', 'inactive', 'herdr.service check on strix failed: inactive'),
        ]
        for status, output, expected in cases:
            with self.subTest(status=status):
                p = self.run_script('herdr-projector', SSH_STATUS=status, SSH_OUTPUT=output, STOP_BACKOFF='1')
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertIn(expected, p.stdout)
                self.assertFalse(any(x[0] == 'herdr' for x in self.calls()))

    def test_invalid_unit_is_rejected_before_ssh(self):
        p = self.run_script('herdr-projector', HERDR_PROJECTOR_UNIT="bad';exit 0;")
        self.assertEqual(p.returncode, 2)
        self.assertFalse((self.root / 'calls').exists())


if __name__ == '__main__':
    unittest.main()
