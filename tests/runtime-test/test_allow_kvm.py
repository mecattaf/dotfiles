"""runtime-test --allow-kvm (#453). Run on a host with unprivileged user
namespaces, outside the Nix build sandbox:

    python3 tests/runtime-test/test_allow_kvm.py

Unlike test_isolation.py this file creates nothing under the host's
/run/user: every probe runs inside the wrapper's own private tree.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

RUNNER = str(Path(__file__).resolve().parents[2] / 'home/dot_local/bin/runtime-test')
HOST_KVM = Path('/dev/kvm')
HOST_KVM_USABLE = HOST_KVM.is_char_device() and os.access(HOST_KVM, os.R_OK | os.W_OK)
OPEN_KVM = "import os; os.close(os.open('/dev/kvm', os.O_RDWR))"


def run(*argv, timeout=15):
    return subprocess.run([RUNNER, *argv], capture_output=True, text=True, timeout=timeout)


@unittest.skipUnless(shutil.which('bwrap'), 'bubblewrap is required')
class AllowKvm(unittest.TestCase):
    def test_default_is_unchanged_kvm_absent(self):
        p = run('--', 'test', '-e', '/dev/kvm')
        self.assertEqual(p.returncode, 1, p.stderr)

    def test_default_still_passes_exit_code(self):
        p = run('--', sys.executable, '-c', 'raise SystemExit(23)')
        self.assertEqual(p.returncode, 23, p.stderr)

    def test_bare_command_without_separator_still_works(self):
        p = run(sys.executable, '-c', 'raise SystemExit(7)')
        self.assertEqual(p.returncode, 7, p.stderr)

    @unittest.skipUnless(HOST_KVM_USABLE, 'host has no usable /dev/kvm')
    def test_flag_binds_kvm_and_it_opens(self):
        p = run('--allow-kvm', '--', sys.executable, '-c', OPEN_KVM)
        self.assertEqual(p.returncode, 0, p.stderr)

    @unittest.skipUnless(HOST_KVM_USABLE, 'host has no usable /dev/kvm')
    def test_flag_widens_only_kvm(self):
        # The rest of /dev is still bubblewrap's minimal devtmpfs.
        probe = "import os; print(' '.join(sorted(os.listdir('/dev'))))"
        base = run('--', sys.executable, '-c', probe)
        kvm = run('--allow-kvm', '--', sys.executable, '-c', probe)
        self.assertEqual(base.returncode, 0, base.stderr)
        self.assertEqual(kvm.returncode, 0, kvm.stderr)
        self.assertEqual(set(kvm.stdout.split()) - set(base.stdout.split()), {'kvm'})

    @unittest.skipUnless(HOST_KVM_USABLE, 'host has no usable /dev/kvm')
    def test_flag_keeps_runtime_isolation(self):
        probe = (
            "import os, pathlib; r = pathlib.Path(os.environ['XDG_RUNTIME_DIR']);"
            "assert r == pathlib.Path('/run/user') / str(os.getuid());"
            "assert list(r.iterdir()) == [], 'private runtime dir is not empty';"
            "assert 'DBUS_SESSION_BUS_ADDRESS' not in os.environ"
        )
        p = run('--allow-kvm', '--', sys.executable, '-c', probe)
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_flag_fails_loudly_when_kvm_missing(self):
        # The outer wrapper has no /dev/kvm, so the inner --allow-kvm must refuse
        # before starting anything rather than run the command without the device.
        p = run('--', RUNNER, '--allow-kvm', '--', 'true')
        self.assertEqual(p.returncode, 1, p.stderr)
        self.assertIn('runtime-test: --allow-kvm', p.stderr)
        self.assertIn('/dev/kvm', p.stderr)

    def test_flag_without_command_is_usage_error(self):
        self.assertEqual(run('--allow-kvm').returncode, 2)
        self.assertEqual(run('--allow-kvm', '--').returncode, 2)

    def test_no_general_device_passthrough(self):
        # Only the one named flag is parsed; anything else is the command.
        p = run('--dev-bind', '/dev/null', '/dev/kvm', '--', 'true')
        self.assertNotEqual(p.returncode, 0)

    def test_help_documents_the_flag(self):
        p = run('--help')
        self.assertEqual(p.returncode, 0)
        self.assertIn('--allow-kvm', p.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
