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
elif name == 'kitten' and args[-1] == 'ls':
    print(json.dumps([{'tabs': [{'windows': [{'foreground_processes': [{'cmdline': ['/bin/herdr', 'client'], 'pid': 300}]}]}]}]))
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
        for name in ('niri', 'kitten', 'ssh', 'sleep', 'herdr'):
            p = self.bin / name
            p.write_text('#!' + os.sys.executable + '\n' + MOCK)
            p.chmod(0o755)
        log = self.root / 'client.log'
        log.write_text('herdr starting version=fixture pid=300\nendpoint handshake succeeded\n')
        self.env = dict(os.environ, FIXTURE=str(self.root), PATH=f'{self.bin}:{os.environ["PATH"]}',
                        HERDR_CLIENT_LOG=str(log), TMPDIR=str(self.root), HERDR_CHORD_TIMEOUT='2')

    def run_script(self, name, *args, **env):
        return subprocess.run(['bash', str(ROOT / name), *args], env=self.env | env,
                              capture_output=True, text=True, timeout=5)

    def calls(self):
        return [json.loads(x) for x in (self.root / 'calls').read_text().splitlines()]

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

    def test_projector_diagnoses_failures_without_starting_unmanaged_server(self):
        cases = [
            ('1', 'Failed to connect to user scope bus via local transport: No such file or directory', 'Herdr may still be running'),
            ('255', 'ssh: connect to host coordinator: Connection refused', 'SSH connection to coordinator failed'),
            ('3', 'inactive', 'herdr.service check on coordinator failed: inactive'),
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
