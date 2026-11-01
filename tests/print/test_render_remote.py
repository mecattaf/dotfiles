from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(os.environ.get("PAPER_RENDER_BRIDGE", Path(__file__).resolve().parents[2] /
                             "pkgs/paper-daemon/render-remote.py"))
spec = importlib.util.spec_from_file_location("render_remote", SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

FAKE_AUTO = '''import argparse, json
from pathlib import Path
ap=argparse.ArgumentParser()
ap.add_argument("input", type=Path)
ap.add_argument("--output-dir", type=Path)
ap.add_argument("--target-pages", type=int)
args=ap.parse_args()
assert args.input.read_text() == "# Café\\nExact source.\\n"
(args.output_dir / "brief.pdf").write_bytes(b"%PDF-1.7\\nexample\\n")
(args.output_dir / "decision.json").write_text(json.dumps({
  "decision": {"filename":"brief.pdf", "sides":"duplex"},
  "pdf": str(args.output_dir / "brief.pdf"), "pages_rendered": 1,
  "target_pages": args.target_pages, "page_slack": 0, "length_check": "pass"}))
print("rendered")
'''


class RemoteRenderTests(unittest.TestCase):
    def test_dormant_worker_is_rejected_before_ssh(self):
        with tempfile.TemporaryDirectory() as raw, \
             mock.patch.dict(os.environ, {"PAPER_RENDER_HOST": "strix-worker"}), \
             mock.patch.object(bridge, "exchange") as exchange:
            with self.assertRaisesRegex(ValueError, "dormant"):
                self.client(Path(raw), self.response())
            exchange.assert_not_called()

    def response(self, **changes):
        pdf = b"%PDF-1.7\nexample\n"
        response = {"version": 1, "returncode": 0,
                    "decision": {"decision": {"filename": "brief.pdf", "sides": "duplex"},
                                 "pdf": "/temporary/compute/brief.pdf", "pages_rendered": 1},
                    "pdf_base64": base64.b64encode(pdf).decode(),
                    "pdf_sha256": hashlib.sha256(pdf).hexdigest(), "log": "rendered"}
        response.update(changes)
        return response

    def client(self, root, response):
        source = root / "source.md"
        source.write_text("# Brief\n")
        args = bridge.parser().parse_args([str(source), "--output-dir", str(root / "job"),
                                          "--target-pages", "1", "--page-slack", "0"])
        with mock.patch.object(bridge, "exchange", return_value=(0, json.dumps(response).encode(), b"")) as run:
            rc = bridge.client(args)
        return rc, run.call_args, root / "job"

    def test_worker_renders_source_and_options_with_no_queue_authority(self):
        with tempfile.TemporaryDirectory() as raw:
            program = Path(raw) / "auto.py"
            program.write_text(FAKE_AUTO)
            env = {**os.environ, "PAPER_PRINT_AUTO": str(program)}
            request = {"version": 1, "source": "# Café\nExact source.\n",
                       "flags": ["--target-pages", "1"]}
            result = subprocess.run([sys.executable, str(SCRIPT), "--worker"],
                                    input=json.dumps(request), capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            response = json.loads(result.stdout)
            self.assertEqual(response["decision"]["target_pages"], 1)
            self.assertTrue(base64.b64decode(response["pdf_base64"]).startswith(b"%PDF-"))
            # The worker's private directory was removed before returning.
            self.assertFalse(Path(response["decision"]["pdf"]).exists())
            self.assertNotIn("receipt", response)

    def test_client_uses_pinned_host_key_no_agent_and_rehomes_paths(self):
        with tempfile.TemporaryDirectory() as raw:
            rc, called, job = self.client(Path(raw), self.response())
            command, encoded = called.args
            self.assertEqual(rc, 0)
            self.assertIn("-oStrictHostKeyChecking=yes", command)
            self.assertIn("-oForwardAgent=no", command)
            self.assertEqual(json.loads(encoded)["flags"], ["--target-pages", "1", "--page-slack", "0"])
            result = json.loads((job / "decision.json").read_text())
            self.assertEqual(result["pdf"], str(job / "brief.pdf"))
            self.assertEqual(result["render_host"], "strix-coordinator")

    def test_invalid_responses_cannot_publish_decisions(self):
        hostile = self.response()
        hostile["decision"]["decision"]["filename"] = "../escape.pdf"
        for response in (self.response(version=2), self.response(returncode=1),
                         self.response(pdf_sha256="wrong"), self.response(pdf_base64="invalid"),
                         hostile):
            with self.subTest(response=response), tempfile.TemporaryDirectory() as raw:
                with self.assertRaises((ValueError, TypeError)):
                    self.client(Path(raw), response)
                self.assertFalse((Path(raw) / "job/decision.json").exists())

    def test_ssh_failure_does_not_fall_back_to_local_browser_or_cups(self):
        with tempfile.TemporaryDirectory() as raw:
            args = bridge.parser().parse_args([str(Path(raw) / "source.md"),
                                              "--output-dir", str(Path(raw) / "job")])
            args.input.write_text("# Brief\n")
            with (mock.patch.object(bridge, "exchange", return_value=(255, b"", b"unreachable")),
                  self.assertRaisesRegex(ValueError, "exited 255")):
                bridge.client(args)
            self.assertFalse(args.output_dir.exists())

    def test_dormant_worker_is_rejected_before_ssh(self):
        with tempfile.TemporaryDirectory() as raw:
            args = bridge.parser().parse_args([str(Path(raw) / "source.md"),
                                              "--output-dir", str(Path(raw) / "job")])
            args.input.write_text("# Brief\n")
            with (mock.patch.dict(os.environ, {"PAPER_RENDER_HOST": "strix-worker"}),
                  mock.patch.object(bridge, "exchange") as exchange,
                  self.assertRaisesRegex(ValueError, "dormant")):
                bridge.client(args)
            exchange.assert_not_called()
            self.assertFalse(args.output_dir.exists())

    def test_exchange_stops_unbounded_output(self):
        with self.assertRaisesRegex(ValueError, "response/log limit"):
            bridge.exchange([sys.executable, "-c", "import sys; sys.stdout.write('x'*200000)"],
                            b"", output_limit=1000)


if __name__ == "__main__":
    unittest.main()
