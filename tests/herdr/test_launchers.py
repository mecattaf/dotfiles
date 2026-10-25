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
if name == 'systemctl':
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
        for name in ('ssh', 'sleep', 'herdr', 'systemctl', 'herdr-picker'):
            p = self.bin / name
            p.write_text('#!' + os.sys.executable + '\n' + MOCK)
            p.chmod(0o755)
        self.env = dict(os.environ, FIXTURE=str(self.root), PATH=f'{self.bin}:{os.environ["PATH"]}',
                        TMPDIR=str(self.root))

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

    def test_local_hyprland_projector_uses_same_guard_and_existing_server(self):
        p = self.run_script('herdr-hyprland-projector', HERDR_SWAY_LOCAL='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.calls(), [['systemctl', '--user', '--quiet', 'is-active', 'herdr.service'], ['herdr', 'client']])

    def test_hyprland_projector_refuses_inactive_local_server(self):
        p = self.run_script('herdr-hyprland-projector', HERDR_SWAY_LOCAL='1', UNIT_STATUS='3')
        self.assertEqual(p.returncode, 1)
        self.assertEqual(len(self.calls()), 1)

    def run_chord(self, *args):
        # herdr-chord execs the herdr-picker beside it, so run a copy next to the mock.
        chord = self.bin / 'herdr-chord'
        chord.write_text((ROOT / 'herdr-chord').read_text())
        return subprocess.run(['bash', str(chord), *args], env=self.env,
                              capture_output=True, text=True, timeout=5)

    def test_chords_hand_off_to_herdr_picker(self):
        for verb in ('new', 'sidebar', 'rename'):
            with self.subTest(verb=verb):
                p = self.run_chord(verb)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertEqual(self.calls()[-1], ['herdr-picker', '--chord', verb])

    def test_unknown_chord_is_rejected(self):
        p = self.run_chord('bogus')
        self.assertEqual(p.returncode, 2)
        self.assertIn('usage', p.stderr)
        self.assertFalse((self.root / 'calls').exists())

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
