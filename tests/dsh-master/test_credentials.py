"""Native runtime credential delivery: isolation, rotation and loud failures."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("master", os.environ["DSH_MASTER"])
master = importlib.util.module_from_spec(spec)
spec.loader.exec_module(master)


class Credentials(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.previous = os.environ.get("DSH_HOME")
        os.environ["DSH_HOME"] = str(self.home)
        self.addCleanup(self.restore_env)
        self.sources = {}
        for name in ("groq", "google"):
            source = self.root / (name + ".key")
            source.write_text("synthetic-private-" + name + "\n")
            source.chmod(0o600)
            self.sources[name] = source
        self.profiles = {
            "master-groq": {"credentialFiles": {"GROQ_API_KEY": str(self.sources["groq"])}},
            "master-gemini-lite": {"credentialFiles": {"GEMINI_API_KEY": str(self.sources["google"])}},
            "master": {},
        }
        self.manifest()

    def restore_env(self):
        if self.previous is None:
            os.environ.pop("DSH_HOME", None)
        else:
            os.environ["DSH_HOME"] = self.previous

    def manifest(self):
        (self.root / "manifest.json").write_text(json.dumps({"profiles": self.profiles}))

    def sync(self, *profiles):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = master.credentials_sync(SimpleNamespace(source=str(self.root), profiles=list(profiles)))
        self.assertNotIn("synthetic-private", output.getvalue())
        self.assertEqual(result, 0)
        return output.getvalue()

    def store(self, profile="master-groq"):
        return self.home / "master-credentials" / (profile + ".yaml")

    def test_native_document_is_private_and_isolated_per_pair(self):
        self.sync()
        self.assertEqual(json.loads(self.store().read_text()), {"version": 1, "refs": {"GROQ_API_KEY": "synthetic-private-groq"}})
        self.assertEqual(self.store().stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.store().parent.stat().st_mode & 0o777, 0o700)
        self.assertFalse(self.store("master").exists())
        self.assertNotIn("GROQ", self.store("master-gemini-lite").read_text())

    def test_selected_rotation_is_atomic_and_does_not_rewrite_other_pair(self):
        self.sync()
        other = self.store("master-gemini-lite").stat().st_mtime_ns
        old_inode = self.store().stat().st_ino
        self.sources["groq"].write_text("rotated-synthetic-key")
        self.sync("master-groq")
        self.assertNotEqual(self.store().stat().st_ino, old_inode)
        self.assertEqual(self.store("master-gemini-lite").stat().st_mtime_ns, other)
        unchanged = self.store().stat().st_mtime_ns
        self.assertIn("unchanged", self.sync("master-groq"))
        self.assertEqual(self.store().stat().st_mtime_ns, unchanged)

    def test_missing_source_fails_before_any_publication(self):
        self.sources["google"].unlink()
        with self.assertRaisesRegex(master.Failure, "cannot read credential source"):
            self.sync()
        self.assertFalse(self.store().exists())

    def test_failed_rotation_reports_failure_and_preserves_previous_file(self):
        self.sync()
        old = self.store().read_bytes()
        self.sources["groq"].write_text("")
        with self.assertRaisesRegex(master.Failure, "empty or not one bounded line"):
            self.sync("master-groq")
        self.assertEqual(self.store().read_bytes(), old)

    def test_symlink_destination_is_refused_without_touching_target(self):
        self.store().parent.mkdir(mode=0o700)
        target = self.root / "unrelated"
        target.write_text("untouched")
        self.store().symlink_to(target)
        with self.assertRaisesRegex(master.Failure, "real owner-only file"):
            self.sync()
        self.assertEqual(target.read_text(), "untouched")
        self.assertFalse(self.store("master-gemini-lite").exists())

    def test_readable_directory_and_file_are_refused(self):
        self.store().parent.mkdir(mode=0o755)
        with self.assertRaisesRegex(master.Failure, "owner-only directory"):
            self.sync()
        self.store().parent.chmod(0o700)
        self.store().write_text("unrelated")
        self.store().chmod(0o644)
        with self.assertRaisesRegex(master.Failure, "owner-only file"):
            self.sync()


if __name__ == "__main__":
    unittest.main()
