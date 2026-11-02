"""Exercise the installed HTTP controller and real Quickshell processes.

Run on compute via runtime-test, with TACIT_TRIAL_PACKAGE set to the output.
Uses Qt's offscreen platform; no live compositor or user sockets are accessed.
"""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class Walkthrough(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = Path(os.environ["TACIT_TRIAL_PACKAGE"])
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            cls.port = listener.getsockname()[1]
        cls.url = f"http://127.0.0.1:{cls.port}"
        cls.log = tempfile.TemporaryFile(mode="w+")
        cls.server = subprocess.Popen([str(cls.package / "bin/tacit-kit-trial"), "--port", str(cls.port)],
                                      stdout=cls.log, stderr=subprocess.STDOUT,
                                      env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software"))
        try:
            for _ in range(80):
                if cls.server.poll() is not None:
                    raise RuntimeError("Controller exited")
                try:
                    with urlopen(cls.url, timeout=1) as response:
                        html = response.read().decode()
                    cls.token = re.search(r"const token='([a-f0-9]+)'", html)[1]
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("Controller did not start")
        except Exception:
            cls.server.terminate()
            cls.server.wait(timeout=5)
            cls.log.seek(0)
            print(cls.log.read())
            raise

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(timeout=10)
        cls.log.seek(0)
        output = cls.log.read()
        cls.log.close()
        print(output)
        assert cls.server.returncode == 0

    def request(self, path, body=None, token=None, headers=None):
        request_headers = headers or {}
        if body is not None:
            request_headers.update({"Content-Type": "application/json", "X-Trial-Token": token or self.token})
        request = Request(self.url + path, data=None if body is None else json.dumps(body).encode(), headers=request_headers)
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read())

    def test_end_to_end(self):
        self.assertFalse(any(w["running"] for w in self.request("/api/status")["windows"]))
        for kind in ("controls", "lists", "actions", "navigation"):
            data = self.request("/api/spawn", {"id": kind})
            row = next(w for w in data["windows"] if w["id"] == kind)
            self.assertTrue(row["running"], row)
            self.assertIsInstance(row["native"]["details"], dict)
        data = self.request("/api/spawn", {"id": "controls"})
        self.assertEqual(sum(w["running"] for w in data["windows"]), 4)
        accents = [w["native"]["accent"] for w in data["windows"]]
        data = self.request("/api/settings", {"palette": "moss", "reducedMotion": True})
        self.assertEqual(data["palette"], "moss")
        self.assertTrue(all(w["native"]["reducedMotion"] for w in data["windows"]))
        for _ in range(20):
            data = self.request("/api/status")
            if all(w["native"]["accent"] != old for w, old in zip(data["windows"], accents)):
                break
            time.sleep(0.1)
        self.assertTrue(all(w["native"]["accent"] != old for w, old in zip(data["windows"], accents)))
        data = self.request("/api/close", {"id": "lists"})
        self.assertEqual(sum(w["running"] for w in data["windows"]), 3)
        data = self.request("/api/spawn", {"id": "lists"})
        self.assertTrue(next(w for w in data["windows"] if w["id"] == "lists")["native"]["reducedMotion"])
        data = self.request("/api/close-all", {})
        self.assertFalse(any(w["running"] for w in data["windows"]))
        # Repeated cleanup and respawning must work without a controller restart.
        self.request("/api/close-all", {})
        self.request("/api/spawn", {"id": "controls"})
        self.request("/api/close-all", {})

    def test_rejects_external_and_unknown_requests(self):
        for path, body, headers, token in [
            ("/api/spawn", {"id": "controls"}, {}, "incorrect"),
            ("/api/spawn", {"id": "controls"}, {"Origin": "https://example.com"}, None),
            ("/api/spawn", {"id": "../../shell"}, {}, None),
            ("/api/settings", {"palette": "../../etc", "reducedMotion": False}, {}, None),
            ("/api/status", None, {"Host": "example.com"}, None),
        ]:
            with self.subTest(path=path, body=body, headers=headers):
                with self.assertRaises(HTTPError) as error:
                    self.request(path, body, token, headers)
                self.assertIn(error.exception.code, (400, 403))
                error.exception.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
