"""CLI contract checks against actual observer snapshots; no live sources."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(os.environ.get("FLEET_STATUS_PY", Path(__file__).resolve().parents[2] / "pkgs/fleet-status/fleet_status.py"))
sys.path.insert(0, str(SCRIPT.parent))
from observer import Observer, public_observation


class ObservationsCLI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fleet-cli-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        value = Observer({"intervals": {"metrics": 60}}, self.state)
        self.addCleanup(value.pool.shutdown, wait=True)
        self.addCleanup(value.publisher_pool.shutdown, wait=True)
        value.accept("metrics", {"error": None, "rows": [
            public_observation("host-nas", "host.pressure", "host.load1", 2.0,
                               at="2000-01-01T00:00:00Z", ttl=60),
        ]})
        self.snapshot = value.publish()
        self.file = self.state / "public/status.json"
        self.before = self.file.read_bytes()
        # Any accidental fall-through into the health collector leaves evidence.
        fake_ssh = self.root / "ssh"
        fake_ssh.write_text(f"#!{sys.executable}\nfrom pathlib import Path\nPath({str(self.root / 'collected')!r}).touch()\nraise SystemExit(1)\n")
        fake_ssh.chmod(0o755)
        self.env = dict(os.environ, FLEET_STATUS_SSH=str(fake_ssh),
                        FLEET_STATUS_HOSTS="nas", HOME=str(self.root))

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), "observations", *args],
                              env=self.env, text=True, capture_output=True, timeout=5)

    def test_json_exposes_the_whole_contract_without_collection_or_state_writes(self):
        result = self.run_cli("--state-dir", str(self.state), "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(set(data), set(self.snapshot))
        for key in ("subjects", "events", "coverage", "publisher", "catalogRevision", "generatedAt"):
            self.assertEqual(data[key], self.snapshot[key])
        self.assertEqual(len(data["observations"]), len(self.snapshot["observations"]))
        self.assertEqual(self.file.read_bytes(), self.before)
        self.assertFalse((self.root / "collected").exists())

    def test_expired_values_keep_provenance_and_last_good_without_becoming_zero(self):
        result = self.run_cli("--snapshot", str(self.file), "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        row = next(row for row in data["observations"] if row["key"] == "host.load1")
        self.assertIsNone(row["value"])
        self.assertEqual(row["grade"], "unknown")
        self.assertEqual(row["errorCode"], "stale")
        self.assertEqual(row["observedAt"], "2000-01-01T00:00:00Z")
        self.assertEqual(row["lastGood"], {"value": 2.0, "observedAt": "2000-01-01T00:00:00Z"})

    def test_text_includes_all_collections_and_missing_source_coverage(self):
        result = self.run_cli("--state-dir", str(self.state))
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ("Subjects", "Observations", "Events", "Source coverage", "not-instrumented", "lastGood"):
            self.assertIn(text, result.stdout)

    def test_missing_snapshot_is_a_structured_failure_and_does_not_start_collection(self):
        result = self.run_cli("--json")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(json.loads(result.stderr)["error"]["code"], "snapshot-missing")
        self.assertFalse((self.root / "collected").exists())
        self.assertFalse((self.root / ".local/state/fleet-status").exists())

    def test_private_state_and_unreviewed_fields_are_not_printed(self):
        for content in (self.state / "state.json", self.file):
            data = json.loads(content.read_text())
            data["privateSecret"] = "do-not-print-this"
            target = self.root / "invalid.json"
            target.write_text(json.dumps(data))
            result = self.run_cli("--snapshot", str(target), "--json")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stderr)["error"]["code"], "snapshot-invalid")
            self.assertNotIn("do-not-print-this", result.stdout + result.stderr)

    def test_malformed_or_oversized_snapshot_fails_without_traceback(self):
        target = self.root / "bad.json"
        for raw in (b"{", b"[]", b" " * (1024 * 1024 + 1)):
            target.write_bytes(raw)
            result = self.run_cli("--snapshot", str(target), "--json")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stderr)["error"]["code"], "snapshot-invalid")


if __name__ == "__main__":
    unittest.main()
