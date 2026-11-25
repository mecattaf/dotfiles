"""home-prune keeps exactly the declared paths of a home and removes the rest.

Run: python3 -m unittest tests/strix-home-prune/test_home_prune.py
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'hosts/strix-coordinator/home-prune.sh'
KEEP = ['.ssh', '.local/share/keyrings', '.local/state/home-manager', '.local/state/nix',
        '.nix-profile', '.bash_history', '.local/share/fish', '.local/share/atuin', '.terminfo']


def run(root, *keep, dry=False):
    env = dict(os.environ, HOME_PRUNE_DRY_RUN='1' if dry else '0')
    return subprocess.run(['bash', str(SCRIPT), str(root), *keep], env=env,
                          capture_output=True, text=True)


class HomePrune(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'tom'
        files = [
            '.ssh/id_ed25519', '.ssh/known_hosts', '.ssh/authorized_keys',
            '.local/share/keyrings/Default_Keyring.keyring',
            '.local/share/fish/fish_history', '.local/share/atuin/history.db',
            '.local/share/hf/extensions/x', '.local/share/tacit-fonts/a.ttf',
            '.local/state/home-manager/gcroots/keep', '.local/state/nix/profiles/x',
            '.local/state/call-diarize/venv/bin/python', '.local/state/herdr/x',
            '.bash_history', '.terminfo/x/xterm-kitty',
            'compute/domicile/src/main.rs', '.wt/rawa/README.md', '.cache/nix/eval-cache',
            '.config/.wrangler/logs/a.log', '.config/gh/hosts.yml', 'Pictures/s.png',
            '.hidden-file', 'plain-file',
        ]
        for f in files:
            p = self.home / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(f)
        (self.home / '.nix-profile').symlink_to(self.home / '.local/state/nix/profiles/x')
        # A link named like a kept parent must not be followed into its target.
        outside = Path(self.temp.name) / 'outside'
        (outside / 'share').mkdir(parents=True)
        (outside / 'share/precious').write_text('outside')
        (self.home / '.local/share-link').symlink_to(outside / 'share')

    def tree(self):
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*')
                      if p.is_file() or p.is_symlink())

    def test_keeps_exactly_the_declared_paths(self):
        result = run(self.home, *KEEP)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tree(), sorted([
            '.bash_history', '.local/share/atuin/history.db',
            '.local/share/fish/fish_history', '.local/share/keyrings/Default_Keyring.keyring',
            '.local/state/home-manager/gcroots/keep', '.local/state/nix/profiles/x',
            '.nix-profile', '.ssh/authorized_keys', '.ssh/id_ed25519', '.ssh/known_hosts',
            '.terminfo/x/xterm-kitty',
        ]))
        self.assertEqual((Path(self.temp.name) / 'outside/share/precious').read_text(), 'outside')

    def test_dry_run_changes_nothing(self):
        before = self.tree()
        result = run(self.home, *KEEP, dry=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('would remove compute', result.stdout)
        self.assertIn('would remove .local/state/call-diarize', result.stdout)
        self.assertNotIn('would remove .ssh', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_refuses_an_empty_keep_list_and_bad_paths(self):
        self.assertEqual(run(self.home).returncode, 2)
        self.assertEqual(run(self.home, '/etc').returncode, 2)
        self.assertEqual(run(self.home, '.ssh/../compute').returncode, 2)
        self.assertEqual(run(self.home, '.ssh/').returncode, 2)
        self.assertTrue((self.home / 'compute').exists())

    def test_missing_root_is_a_no_op(self):
        result = run(Path(self.temp.name) / 'absent', *KEEP)
        self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
