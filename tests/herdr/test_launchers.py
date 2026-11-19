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
        for name in ('ssh', 'sleep', 'herdr', 'systemctl'):
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









    def test_projector_diagnoses_failures_without_starting_unmanaged_server(self):
        cases = [
            ('1', 'Failed to connect to user scope bus via local transport: No such file or directory', 'Herdr may still be running'),
            ('255', 'ssh: connect to host nas: Connection refused', 'SSH connection to nas failed'),
            ('3', 'inactive', 'herdr.service check on nas failed: inactive'),
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
