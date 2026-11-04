import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import runpy
from unittest import mock
import io
from contextlib import redirect_stdout
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("practice_worker", Path(__file__).with_name("worker.py"))
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class SafetyTests(unittest.TestCase):
    def test_nas_receipt_survives_corrupt_archive_after_failed_transport(self):
        with tempfile.TemporaryDirectory() as scratch:
            calls = []
            def remote(argv, **kwargs):
                self.assertEqual(argv[:2], ["fleet-exec", "strix-coordinator"])
                calls.append(argv)
                return subprocess.CompletedProcess(argv, 1 if "worker.py" in " ".join(argv) else 0)
            script = str(Path(__file__).with_name("run-nas.py"))
            with mock.patch("sys.argv", [script, "--out", scratch]), \
                 mock.patch("socket.gethostname", return_value="nas"), \
                 mock.patch("subprocess.run", side_effect=remote), redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as exited:
                    runpy.run_path(script, run_name="__main__")
            self.assertEqual(exited.exception.code, 1)
            self.assertEqual(len(calls), 2)
            receipt_path = next(Path(scratch).glob("*/nas-receipt.json"))
            receipt = json.loads(receipt_path.read_text())
            self.assertEqual(receipt["transport_exit"], 1)
            self.assertEqual(receipt["archive_exit"], 0)
            self.assertIn("copy-or-validation-failed", receipt["artifact_status"])
            self.assertIn("artifact_error", receipt)

    def test_host_namespace_rejected_before_creating_home_or_starting_bus(self):
        with tempfile.TemporaryDirectory() as scratch:
            output = Path(scratch)
            runtime = Path(os.environ["XDG_RUNTIME_DIR"])
            st = runtime.stat()
            worker.atomic(output / "isolation-expectations.json", {
                "pid": os.readlink("/proc/self/ns/pid"),
                "ipc": os.readlink("/proc/self/ns/ipc"),
                "runtime_devino": [st.st_dev, st.st_ino]})
            h = worker.Harness(SimpleNamespace(output=output))
            with self.assertRaisesRegex(AssertionError, "refusing live PID namespace"):
                h.setup()
            self.assertFalse((output / "home").exists())
            self.assertEqual(h.children, [])

    def test_ancestry_excludes_unrelated_session(self):
        table = {n: {"pid": n, "ppid": parent} for n, parent in
                 [(1, 0), (2, 1), (3, 2), (4, 3), (5, 1), (6, 5)]}
        self.assertEqual(set(worker.descendants(table, [2])), {2, 3, 4})

    def test_reused_identity_cannot_signal_even_our_own_child(self):
        child = subprocess.Popen(["sleep", "30"])
        try:
            actual = worker.processes()[child.pid]
            stale = dict(actual, start=actual["start"] - 1)
            worker.send_owned(stale, signal.SIGKILL)
            self.assertIsNone(child.poll())
            self.assertFalse(worker.living(stale))
            self.assertTrue(worker.living(actual))
            worker.send_owned(actual, signal.SIGTERM)
            self.assertEqual(child.wait(3), -signal.SIGTERM)
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(3)

    def test_failed_check_keeps_failure_and_traceback_in_receipt(self):
        with tempfile.TemporaryDirectory() as scratch:
            h = worker.Harness(SimpleNamespace(output=Path(scratch)))
            with h.check("deliberate-test-failure"):
                raise ValueError("evidence must survive")
            receipt = json.loads((Path(scratch) / "receipt.json").read_text())
            row = receipt["checks"][0]
            self.assertEqual(row["status"], "fail")
            self.assertEqual(row["reason"], "evidence must survive")
            self.assertIn("ValueError", row["traceback"])

    def test_crash_gate_refuses_active_capture_or_recorder(self):
        h = worker.Harness(SimpleNamespace(output=Path("/tmp/practice-test-no-write")))
        h.capture_active = True
        with self.assertRaisesRegex(AssertionError, "screenshot still active"):
            h.require_quiet_capture()
        h.capture_active = False
        recorder = subprocess.Popen(["sleep", "30"])
        try:
            h.recorders.append(recorder)
            with self.assertRaisesRegex(AssertionError, "recorder still active"):
                h.require_quiet_capture()
            recorder.terminate()
            recorder.wait(3)
            h.require_quiet_capture()
        finally:
            if recorder.poll() is None:
                recorder.terminate()
                recorder.wait(3)

    def test_custom_expectations_cannot_match_unrelated_process(self):
        h = worker.Harness(SimpleNamespace(output=Path("/tmp/practice-test-no-write")))
        h.expectations = {"rescue": ["kitty", "practice-rescue"]}
        h.observe = lambda: {4: {"pid": 4, "state": "S", "argv": ["kitty", "practice-terminal"]}}
        self.assertEqual(h.app_rows("rescue"), [])
        h.observe = lambda: {4: {"pid": 4, "state": "S", "argv": ["kitty", "practice-rescue"]}}
        self.assertEqual([r["pid"] for r in h.app_rows("rescue")], [4])


if __name__ == "__main__":
    unittest.main()
