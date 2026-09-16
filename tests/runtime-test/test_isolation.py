"""Run on a host with unprivileged user namespaces, outside the Nix build sandbox."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[2] / 'home/dot_local/bin/runtime-test'


class RuntimeIsolation(unittest.TestCase):
    def test_cleanup_cannot_touch_host_runtime_or_its_processes(self):
        runtime = Path('/run/user') / str(os.getuid())
        # Only this uniquely named fixture is created/removed on the host.
        with tempfile.TemporaryDirectory(prefix='runtime-test-proof-', dir=runtime) as root:
            sentinel = Path(root) / 'keep'
            sentinel.write_text('host survives')
            probe = r'''
import os, pathlib, shutil, sys
runtime = pathlib.Path(os.environ['XDG_RUNTIME_DIR'])
assert not pathlib.Path(sys.argv[1]).exists(), 'host runtime is visible'
assert str(runtime) == '/run/user/' + str(os.getuid())
assert runtime.stat().st_mode & 0o777 == 0o700
assert 'NOTIFY_SOCKET' not in os.environ
assert 'DBUS_SESSION_BUS_ADDRESS' not in os.environ
# A private /dev supplies usable standard devices after user namespace setup.
with open('/dev/null', 'wb') as null:
    null.write(b'probe')
# Reproduce deleting the runtime contents; the mountpoint itself stays mounted.
(runtime / 'test-socket-directory').mkdir()
(runtime / 'test-socket-directory' / 'file').write_text('disposable')
for child in runtime.iterdir():
    shutil.rmtree(child) if child.is_dir() else child.unlink()
assert not pathlib.Path('/proc/' + sys.argv[2]).exists(), 'host PID is visible'
sys.exit(23)
'''
            p = subprocess.run([str(RUNNER), '--', os.sys.executable, '-c', probe, str(sentinel), str(os.getpid())],
                               env=dict(os.environ, XDG_RUNTIME_DIR=str(runtime), NOTIFY_SOCKET='live-notify', DBUS_SESSION_BUS_ADDRESS='live-bus'),
                               capture_output=True, text=True, timeout=15)
            self.assertEqual(p.returncode, 23, p.stderr)
            self.assertEqual(sentinel.read_text(), 'host survives')


if __name__ == '__main__':
    unittest.main()
