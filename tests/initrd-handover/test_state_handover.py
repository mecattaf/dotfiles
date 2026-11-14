"""Run on compute with runtime-test; every cleanup target is a fake /tmp tree.

Only the evaluated ExecStopPost argv is executed. Never source or execute the
lan-handover script, which flushes real NIC routes/addresses.
"""
import json
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / 'hosts/nas/initrd-ssh.nix'


def evaluated(nm=True, networkd=False):
    # Evaluate the real module without a nixpkgs/NixOS build. The service values
    # are lazy: unrelated initrd SSH keys and the registry are never forced.
    coreutils = str(Path(shutil.which('rm')).resolve().parent.parent)
    expr = '''let m = import %s {
      config = { networking.networkmanager.enable = %s; systemd.network.enable = %s; };
      pkgs = { iproute2 = "iproute2"; coreutils = %s; };
      lib = { optional = c: v: if c then [v] else []; mkAfter = v: v; };
    }; in { commands = m.boot.initrd.systemd.services.systemd-networkd.serviceConfig.ExecStopPost;
            bins = m.boot.initrd.systemd.initrdBin; }
    ''' % (MODULE, str(nm).lower(), str(networkd).lower(), json.dumps(coreutils))
    return json.loads(subprocess.check_output(
        ['nix-instantiate', '--eval', '--strict', '--json', '--expr', expr], text=True))


class Handover(unittest.TestCase):
    def run_cleanup(self, state):
        self.assertTrue(str(state.resolve(strict=False)).startswith('/tmp/'))
        command = evaluated()['commands']
        self.assertEqual(len(command), 1)
        argv = shlex.split(command[0])
        self.assertEqual(argv[1:], ['-f', '--', '/run/systemd/netif/state'])
        # Substitute only the one production operand. No runtime/system path
        # from the generated command is ever used as a cleanup target.
        argv[-1] = str(state)
        return subprocess.run(argv, capture_output=True, text=True)

    def test_networkmanager_handoff_only(self):
        for nm, networkd in [(True, True), (False, True), (False, False)]:
            with self.subTest(nm=nm, networkd=networkd):
                result = evaluated(nm, networkd)
                self.assertEqual(result['commands'], [])
                self.assertEqual(result['bins'], ['iproute2'])
        self.assertEqual(len(evaluated()['commands']), 1)
        self.assertEqual(len(evaluated()['bins']), 2)

    def test_exact_state_only_preserves_siblings_and_socket(self):
        with tempfile.TemporaryDirectory(prefix='initrd-netif-', dir='/tmp') as t:
            root = Path(t); state = root/'state'; state.write_text('ONLINE_STATE=offline\n')
            sibling = root/'links'; sibling.mkdir(); (sibling/'2').write_text('keep')
            with socket.socket(socket.AF_UNIX) as sock:
                endpoint = root/'io.systemd.Network'; sock.bind(str(endpoint))
                self.assertEqual(self.run_cleanup(state).returncode, 0)
                self.assertFalse(state.exists())
                self.assertEqual((sibling/'2').read_text(), 'keep')
                self.assertTrue(endpoint.is_socket())

    def test_missing_state_is_idempotent(self):
        with tempfile.TemporaryDirectory(prefix='initrd-netif-', dir='/tmp') as t:
            state = Path(t)/'state'
            self.assertEqual(self.run_cleanup(state).returncode, 0)
            self.assertEqual(self.run_cleanup(state).returncode, 0)
            self.assertTrue(state.parent.is_dir())

    def test_symlink_target_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix='initrd-netif-', dir='/tmp') as t:
            root = Path(t); target = root/'real-state'; target.write_text('keep')
            state = root/'state'; state.symlink_to(target)
            self.assertEqual(self.run_cleanup(state).returncode, 0)
            self.assertFalse(state.is_symlink()); self.assertEqual(target.read_text(), 'keep')

    def test_directory_is_not_recursively_removed(self):
        with tempfile.TemporaryDirectory(prefix='initrd-netif-', dir='/tmp') as t:
            state = Path(t)/'state'; state.mkdir(); (state/'sentinel').write_text('keep')
            self.assertNotEqual(self.run_cleanup(state).returncode, 0)
            self.assertEqual((state/'sentinel').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
