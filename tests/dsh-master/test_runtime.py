"""Runtime generations retain bytes and reject incomplete/mutable graphs."""
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest

SOURCE = Path(os.environ.get("DSH_MASTER_RUNTIME", Path(__file__).resolve().parents[2] / "pkgs/dsh-master/runtime.py"))
spec = importlib.util.spec_from_file_location("master_runtime", SOURCE)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "dsh"
        self.home.mkdir()
        self.source = self.root / "build"
        self.source.mkdir()
        self.profile = self.root / "installed/master-groq"
        self.modules = self.profile / "node_modules"
        (self.modules / "dsh-superagent/lib").mkdir(parents=True)
        (self.modules / "proof-dep").mkdir()
        (self.modules / ".pnpm").mkdir()
        package = {"name": "master-groq", "dependencies": {"dsh-superagent": "github:example/superagent#v7"}}
        self.write(self.profile / "package.json", package)
        self.write(self.modules / "dsh-superagent/package.json", {"name": "dsh-superagent", "dependencies": {"proof-dep": "1.0.0"}})
        self.write(self.modules / "proof-dep/package.json", {"name": "proof-dep", "version": "1.0.0"})
        (self.modules / "proof-dep/index.js").write_text("export const version = 1;\n")
        for file in runtime.BACKENDS.values():
            (self.modules / "dsh-superagent/lib" / file).write_text("export const version = 7;\n")
        (self.modules / "dsh-superagent/lib/lazy.js").write_text("export const lazy = 7;\n")
        (self.modules / "proof-dep/relative.js").symlink_to("index.js")
        (self.modules / "dsh-superagent/.git").mkdir()
        (self.modules / "dsh-superagent/.git/not-runtime").write_text("omit")
        lock = {"importers": {".": {"dependencies": {"dsh-superagent": {"specifier": package["dependencies"]["dsh-superagent"]}}}}}
        self.write(self.profile / "pnpm-lock.yaml", lock)
        self.write(self.modules / ".pnpm/lock.yaml", lock)
        self.manifest = {"dsh": "/not-needed-without-native-peers", "profiles": {
            "master-groq": {"files": {"package.json": hashlib.sha256((self.profile / "package.json").read_bytes()).hexdigest()}},
            "master": {"expect": [
                {"id": name, "disabled": False, "config": {"stateDir": "/persistent/master", "dshd": {"pairs": {"groq": {"profile": "master-groq"}}}} if name == "dsh-superagent" else None}
                for name in runtime.BACKENDS
            ]},
        }}
        self.write(self.source / "manifest.json", self.manifest)

    def write(self, path, value):
        path.write_text(json.dumps(value))

    def snapshot(self):
        # A toy graph has no Nix peers; any accidental process call fails.
        return runtime.snapshot(self.source, self.profile, self.home, "/must-not-run")

    def test_copy_is_readonly_independent_and_retries_reuse(self):
        result = self.snapshot()
        generation = Path(result["generation"])
        self.assertFalse(result["reused"])
        self.assertTrue(self.snapshot()["reused"])
        old = self.modules / "proof-dep/index.js"
        copy = generation / "node_modules/proof-dep/index.js"
        self.assertNotEqual(old.stat().st_ino, copy.stat().st_ino)
        old.write_text("changed after publishing")
        self.assertIn("version = 1", copy.read_text())
        self.assertTrue((generation / "node_modules/dsh-superagent/lib/lazy.js").is_file())
        self.assertFalse((generation / "node_modules/dsh-superagent/.git").exists())
        self.assertEqual((generation / "node_modules/proof-dep/relative.js").read_text(), copy.read_text())
        for folder, _, files in os.walk(generation):
            self.assertFalse(Path(folder).stat().st_mode & 0o222)
            for file in files:
                path = Path(folder) / file
                if not path.is_symlink():
                    self.assertFalse(path.stat().st_mode & 0o222)

    def test_overlay_disables_three_old_rows_and_preserves_new_configs(self):
        result = self.snapshot()
        overlay = json.loads(Path(result["overlay"]).read_text())
        self.assertEqual(overlay[:3], [{"id": name, "disabled": True} for name in runtime.BACKENDS])
        self.assertEqual(overlay[3]["insert"][0]["config"], self.manifest["profiles"]["master"]["expect"][0]["config"])
        self.assertEqual([row["id"] for row in overlay[3]["insert"]], [name + "-runtime" for name in runtime.BACKENDS])
        self.assertTrue(all(row["name"].startswith(result["generation"] + "/node_modules/dsh-superagent/lib/") for row in overlay[3]["insert"]))

    def assert_no_generation(self):
        parent = self.home / "master-runtimes"
        self.assertFalse(parent.exists() and any(path.name[0] != "." for path in parent.iterdir()))

    def test_missing_dependency_fails_before_publish(self):
        self.write(self.modules / "dsh-superagent/package.json", {"name": "dsh-superagent", "dependencies": {"missing": "1"}})
        # A dependency outside the graph must not accidentally satisfy it.
        outside = self.home / "node_modules/missing"
        outside.mkdir(parents=True)
        self.write(outside / "package.json", {"name": "missing"})
        with self.assertRaisesRegex(runtime.SnapshotError, "missing installed dependency"):
            self.snapshot()
        self.assert_no_generation()

    def test_mutable_external_symlink_fails_before_publish(self):
        external = self.root / "mutable.js"
        external.write_text("mutable")
        (self.modules / "proof-dep/external.js").symlink_to(external)
        with self.assertRaisesRegex(runtime.SnapshotError, "external link is mutable"):
            self.snapshot()
        self.assert_no_generation()

    def test_missing_backend_or_mismatched_lock_fails_before_publish(self):
        (self.modules / "dsh-superagent/lib/workflow.js").unlink()
        with self.assertRaisesRegex(runtime.SnapshotError, "no backend"):
            self.snapshot()
        self.assert_no_generation()
        (self.modules / "dsh-superagent/lib/workflow.js").write_text("runtime")
        self.write(self.profile / "pnpm-lock.yaml", {"importers": {".": {"dependencies": {}}}})
        with self.assertRaisesRegex(runtime.SnapshotError, "lockfile does not match"):
            self.snapshot()
        self.assert_no_generation()

    def test_concurrent_retries_share_exactly_one_generation(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.snapshot(), range(2)))
        self.assertEqual(results[0]["generation"], results[1]["generation"])
        self.assertEqual(sum(not result["reused"] for result in results), 1)
        self.assertEqual(len([path for path in (self.home / "master-runtimes").iterdir() if not path.name.startswith(".")]), 1)

    def test_reuse_detects_payload_tampering(self):
        result = self.snapshot()
        path = Path(result["generation"]) / "node_modules/proof-dep/index.js"
        path.chmod(0o644)
        path.write_text("tampered")
        path.chmod(0o444)
        with self.assertRaisesRegex(runtime.SnapshotError, "payload has changed"):
            self.snapshot()

    def test_reuse_refuses_writable_generation(self):
        result = self.snapshot()
        Path(result["generation"]).chmod(0o755)
        with self.assertRaisesRegex(runtime.SnapshotError, "read-only"):
            self.snapshot()


if __name__ == "__main__":
    unittest.main()
