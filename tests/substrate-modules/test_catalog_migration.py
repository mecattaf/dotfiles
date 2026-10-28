"""Catalog migration exercises real atomic files, backup and refusal paths."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

SCRIPT = Path(os.environ.get("CATALOG_SCRIPT", Path(__file__).parents[2] / "pkgs/substrate-apps/migrate-dsh-catalog.py"))
CATALOG = '''# Keep original comments in the backup.
[[models]]
id = "claude-custom"
harness = "claude"
aliases = ["opus"]
default = true
ceilings = {model_scoped = 89}

[[models]]
id = "qwen3.8-flash-next"
harness = "pi"
aliases = ["local", "halogen-qwen3.8-flash-next"]
default = true
[models.pi]
context_window = 102400

[[models]]
id = "old-cloud-model"
harness = "pi"
provider = "qwen-token-plan"
default = true
'''


class Migration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.catalog = Path(self.tmp.name) / "models.toml"
        self.catalog.write_text(CATALOG)

    def run_migration(self, *args, success=True):
        p = subprocess.run([sys.executable, str(SCRIPT), "--file", str(self.catalog), *args], capture_output=True, text=True)
        self.assertEqual(p.returncode == 0, success, p.stdout + p.stderr)
        return json.loads(p.stdout) if success else p.stderr

    def test_startup_refuses_pi_once_with_config_exit_code(self):
        p = subprocess.run([sys.executable, str(SCRIPT), "--file", str(self.catalog), "--check"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 78, p.stderr)
        self.assertIn("retired Pi catalog", p.stderr)
        self.assertEqual(list(self.catalog.parent.iterdir()), [self.catalog])
        self.run_migration("--apply")
        self.assertEqual(self.run_migration("--check")["status"], "ready")

    def test_plan_has_no_filesystem_side_effect(self):
        result = self.run_migration()
        self.assertEqual(result["retired_models"], ["old-cloud-model"])
        self.assertEqual(self.catalog.read_text(), CATALOG)
        self.assertEqual(list(self.catalog.parent.iterdir()), [self.catalog])

    def test_apply_backs_up_and_preserves_nonpi_choices(self):
        result = self.run_migration("--apply")
        backup = Path(result["backup"])
        self.assertEqual(backup.read_text(), CATALOG)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.catalog.stat().st_mode & 0o777, 0o600)
        data = tomllib.loads(self.catalog.read_text())
        self.assertEqual(len(data["models"]), 2)
        self.assertEqual(data["models"][0], tomllib.loads(CATALOG)["models"][0])
        local = data["models"][1]
        self.assertEqual(local["harness"], "dsh")
        self.assertEqual(local["provider"], "gufo")
        self.assertEqual(local["aliases"], ["local", "nightly"])
        self.assertNotIn("pi", local)

    def test_repeated_apply_is_idempotent(self):
        self.run_migration("--apply")
        before = self.catalog.read_bytes()
        self.assertEqual(self.run_migration("--apply")["status"], "unchanged")
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertEqual(len(list(self.catalog.parent.glob("models.toml.before-dsh-*"))), 1)

    def test_unknown_model_refuses_without_rewrite(self):
        self.catalog.write_text(CATALOG.replace("qwen3.8-flash-next", "custom-local"))
        before = self.catalog.read_bytes()
        self.assertIn("review it explicitly", self.run_migration("--apply", success=False))
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertFalse(list(self.catalog.parent.glob("models.toml.before-dsh-*")))

    def test_alias_collision_refuses_without_rewrite(self):
        self.catalog.write_text(CATALOG.replace('["opus"]', '["opus", "nightly"]'))
        before = self.catalog.read_bytes()
        self.assertIn("alias belongs", self.run_migration("--apply", success=False))
        self.assertEqual(self.catalog.read_bytes(), before)

    def test_symlink_refuses_without_replacing_target(self):
        target = self.catalog.with_name("target.toml")
        self.catalog.rename(target)
        self.catalog.symlink_to(target)
        self.assertIn("symlink", self.run_migration("--apply", success=False))
        self.assertTrue(self.catalog.is_symlink())
        self.assertEqual(target.read_text(), CATALOG)

    def test_existing_default_is_preserved_or_conflict_reported(self):
        self.run_migration("--apply")
        self.catalog.write_text(self.catalog.read_text() + '\n[[models]]\nid="custom"\nharness="dsh"\nprovider="gufo"\ndefault=true\n')
        before = self.catalog.read_bytes()
        self.assertIn("another Gufo default", self.run_migration("--apply", success=False))
        self.assertEqual(self.catalog.read_bytes(), before)

    def test_missing_local_model_does_not_invent_choice(self):
        self.catalog.write_text('[[models]]\nid="claude-custom"\nharness="claude"\n')
        self.assertIn("expected local", self.run_migration("--apply", success=False))


if __name__ == "__main__":
    unittest.main()
