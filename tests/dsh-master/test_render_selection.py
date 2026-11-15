"""Exercise render selection through the CLI without changing a live profile."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = os.environ["DSH_MASTER"]
FILES = ("cordis.patch.yml", "package.json", "pnpm-workspace.yaml")
PROFILES = ("master", "master-gufo", "master-opus")


def snapshot(root):
    return {str(path.relative_to(root)): (path.stat().st_ino, path.stat().st_mode,
            path.stat().st_mtime_ns, path.read_bytes() if path.is_file() else None)
            for path in [root, *sorted(root.rglob("*"))]}


class RenderSelection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source, self.home = self.root / "source", self.root / "dsh-home"
        self.home.mkdir()
        self.dshd = self.root / "dshd"
        self.dshd.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                            "if os.environ.get('INVENTORY_FAIL'): sys.exit(1)\n"
                            "if sys.argv[1]=='ls': print(json.dumps({'instances':[{'name':'floor','state':'running'}]}))\n"
                            "else: print(json.dumps({'activeState':'active','profile':{'name':os.environ.get('ACTIVE_PROFILE',''), 'dshHome':os.environ.get('ACTIVE_HOME',os.environ['DSH_HOME'])}}))\n")
        self.dshd.chmod(0o755)
        profiles = {}
        for name in PROFILES:
            folder = self.source / "profiles" / name
            folder.mkdir(parents=True)
            digests = {}
            for file in FILES:
                data = (name + ": new " + file + "\n").encode()
                (folder / file).write_bytes(data)
                digests[file] = hashlib.sha256(data).hexdigest()
            profiles[name] = {"files": digests}
        (self.source / "manifest.json").write_text(json.dumps({"profiles": profiles}))

    def run_render(self, *profiles, **env):
        return subprocess.run([sys.executable, CLI, "render", "--from", str(self.source), "--dshd", str(self.dshd), *profiles],
                              env={**os.environ, "DSH_HOME": str(self.home), **env},
                              text=True, capture_output=True)

    def test_gufo_only_preserves_unselected_claude_profiles_and_state_exactly(self):
        before = {}
        for name in ("master", "master-opus"):
            folder = self.home / "profiles" / name
            folder.mkdir(parents=True)
            for file in (*FILES, ".dsh-master.json", "pnpm-lock.yaml", "cordis.yml"):
                (folder / file).write_text("hand-edited " + name + "/" + file)
                (folder / file).chmod(0o640)
            before[name] = snapshot(folder)
        result = self.run_render("master-gufo")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, prior in before.items():
            self.assertEqual(snapshot(self.home / "profiles" / name), prior)
            self.assertNotIn(name + "/", result.stdout)
            self.assertNotIn("install needed: " + name + "\n", result.stdout)
        for file in FILES:
            self.assertEqual((self.home / "profiles/master-gufo" / file).read_bytes(),
                             (self.source / "profiles/master-gufo" / file).read_bytes())
        self.assertTrue((self.home / "profiles/master-gufo/.dsh-master.json").is_file())
        self.assertEqual(result.stderr, "")

    def test_no_selection_keeps_render_all_default(self):
        result = self.run_render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(path.name for path in (self.home / "profiles").iterdir()), list(PROFILES))
        for name in PROFILES:
            for file in FILES:
                self.assertEqual((self.home / "profiles" / name / file).read_bytes(),
                                 (self.source / "profiles" / name / file).read_bytes())

    def test_unknown_selection_fails_before_writing_any_profile(self):
        before = snapshot(self.home)
        result = self.run_render("master-gufo", "unknown")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a rendered Master profile: unknown", result.stderr)
        self.assertEqual(snapshot(self.home), before)

    def test_active_master_is_preserved_while_inactive_workers_render(self):
        folder = self.home / "profiles/master"
        folder.mkdir(parents=True)
        for file in (*FILES, ".dsh-master.json", "pnpm-lock.yaml", "cordis.yml"):
            (folder / file).write_text("live " + file)
        before = snapshot(folder)
        result = self.run_render(ACTIVE_PROFILE="master")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("render pending: master: dshd instance floor is running", result.stderr)
        self.assertEqual(snapshot(folder), before)
        self.assertTrue((self.home / "profiles/master-gufo/package.json").is_file())

    def test_inventory_failure_precedes_all_writes(self):
        before = snapshot(self.home)
        result = self.run_render(INVENTORY_FAIL="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("cannot tell which dshd instances", result.stderr)
        self.assertEqual(snapshot(self.home), before)

    def test_same_profile_in_another_dsh_home_does_not_block_render(self):
        result = self.run_render(ACTIVE_PROFILE="master", ACTIVE_HOME=str(self.root / "another-home"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("render pending", result.stderr)
        self.assertTrue((self.home / "profiles/master/package.json").is_file())


if __name__ == "__main__":
    unittest.main()
