"""Conditional publisher behavior against a real HTTP server; no provider calls."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest

SCRIPT = Path(os.environ.get("FLEET_STATUS_PUBLISHER_PY", Path(__file__).resolve().parents[2] / "pkgs/fleet-status/publisher.py"))
spec = importlib.util.spec_from_file_location("fleet_publisher", SCRIPT)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Endpoint(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, code):
        self.send_response(code)
        if self.server.value is not None:
            self.send_header("ETag", self.server.etag)
            self.send_header("x-sequence", str(self.server.value["publisher"]["sequence"]))
            self.send_header("x-snapshot-id", self.server.value["snapshotId"])
        self.end_headers()

    def do_HEAD(self):
        if self.headers.get("Authorization") != "Bearer " + self.server.token:
            return self.answer(401)
        if self.headers.get("User-Agent") != "fleet-status-observer/1":
            return self.answer(403)
        self.answer(200 if self.server.value is not None else 404)

    def do_PUT(self):
        if self.headers.get("Authorization") != "Bearer " + self.server.token:
            return self.answer(401)
        self.server.writes += 1
        if self.server.conflict:
            self.server.value = {"publisher": {"sequence": 99}, "snapshotId": "newer"}
            self.server.etag = '"newer"'
        if self.server.value is None:
            if self.headers.get("If-None-Match") != "*":
                return self.answer(428)
        elif self.headers.get("If-Match") != self.server.etag:
            return self.answer(412)
        self.server.value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.etag = '"committed-' + str(self.server.value["publisher"]["sequence"]) + '"'
        if self.server.lose_response:
            self.connection.close()
            self.close_connection = True
            return
        self.answer(200)


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="publisher-test-")
        self.root = Path(self.temp.name)
        self.token = self.root / "token"
        self.token.write_text("only-a-synthetic-unit-test-token-12345")
        self.token.chmod(0o600)
        self.file = self.root / "public.json"
        self.candidate(1)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Endpoint)
        self.server.token = self.token.read_text()
        self.server.value = None
        self.server.etag = None
        self.server.writes = 0
        self.server.conflict = False
        self.server.lose_response = False
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def candidate(self, sequence):
        self.file.write_text(json.dumps({"schemaVersion": "fleet-observations/1", "synthetic": False,
            "publisher": {"sequence": sequence}, "snapshotId": "snapshot-" + str(sequence)}))

    def publish(self):
        return publisher.publish_file(self.file, self.root / "state", self.url, self.token, allow_http=True)

    def test_initial_and_successor_use_atomic_conditions(self):
        self.assertEqual(self.publish()["status"], "published")
        self.candidate(2)
        self.assertEqual(self.publish()["committedSequence"], 2)
        self.assertEqual(self.server.writes, 2)
        self.assertEqual((self.root / "state/publisher.json").stat().st_mode & 0o777, 0o600)

    def test_same_snapshot_reconciles_without_duplicate_put(self):
        self.publish()
        result = self.publish()
        self.assertTrue(result["reconciled"])
        self.assertEqual(self.server.writes, 1)

    def test_stale_local_sequence_preserves_remote_and_records_floor(self):
        self.candidate(2)
        self.publish()
        self.candidate(1)
        self.assertEqual(self.publish()["errorCode"], "publisher-sequence-conflict")
        self.assertEqual(self.server.writes, 1)
        self.assertEqual(json.loads((self.root / "state/publisher.json").read_text())["remoteSequence"], 2)

    def test_put_response_loss_reconciles_the_committed_object(self):
        self.server.lose_response = True
        result = self.publish()
        self.assertEqual(result["status"], "published")
        self.assertTrue(result["reconciled"])
        self.assertEqual(self.server.writes, 1)

    def test_cas_race_never_overwrites_newer_publication(self):
        self.publish()
        self.candidate(2)
        self.server.conflict = True
        self.assertEqual(self.publish()["status"], "failed")
        self.assertEqual(self.server.value["publisher"]["sequence"], 99)
        self.assertEqual(json.loads((self.root / "state/publisher.json").read_text())["remoteSequence"], 99)

    def test_bad_auth_is_safe_and_does_not_write(self):
        self.server.token = "different-credential"
        result = self.publish()
        self.assertEqual(result["errorCode"], "publisher-auth-failed")
        self.assertNotIn(self.token.read_text(), json.dumps(result))
        self.assertEqual(self.server.writes, 0)

    def test_permissive_credential_mode_fails_before_network(self):
        self.token.chmod(0o644)
        self.assertEqual(self.publish()["errorCode"], "publisher-credential-permissions")
        self.assertEqual(self.server.writes, 0)

    def test_oversize_and_synthetic_objects_are_not_sent(self):
        self.file.write_bytes(b" " * (publisher.MAX_BYTES + 1))
        self.assertEqual(self.publish()["errorCode"], "publisher-snapshot-invalid")
        self.candidate(1)
        value = json.loads(self.file.read_text())
        value["synthetic"] = True
        self.file.write_text(json.dumps(value))
        self.assertEqual(self.publish()["errorCode"], "publisher-snapshot-invalid")
        self.assertEqual(self.server.writes, 0)

    def test_production_urls_cannot_be_http_or_redirect_credential_targets(self):
        for url in [self.url, "https://user:pass@example.com", "https://example.com/arbitrary", "https://example.com?next=target"]:
            with self.assertRaises(publisher.PublishError):
                publisher.Client(url, self.token.read_text())

    def test_corrupt_state_and_symlink_are_rejected(self):
        folder = self.root / "state"
        folder.mkdir()
        state = folder / "publisher.json"
        state.write_text('{"remoteSequence":"invalid"}')
        with self.assertRaises(publisher.PublishError):
            self.publish()
        state.unlink()
        state.symlink_to(self.token)
        with self.assertRaises(publisher.PublishError):
            self.publish()
        self.assertEqual(self.server.writes, 0)


if __name__ == "__main__":
    unittest.main()
