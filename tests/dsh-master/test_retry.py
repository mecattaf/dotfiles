"""Exercise the real DSH retry executor against a local HTTP fixture.

Only the 60-second timer is accelerated. No model provider is contacted.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest

spec = importlib.util.spec_from_file_location("master", os.environ["DSH_MASTER"])
master = importlib.util.module_from_spec(spec)
spec.loader.exec_module(master)


class Retry(unittest.TestCase):
    def exercise(self, status, message, expected_calls, expected_code):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            home.mkdir()
            dsh_home = root / "dsh"
            dsh_home.mkdir()
            with (Path(os.environ["PROBES"]) / "profiles/master-groq/cordis.patch.yml").open() as stream:
                rows = master.yaml.load(stream, Loader=master.Loader)
            config = next(row["config"] for row in rows if row.get("id") == "llm-pi-ai")
            groq = config["providers"]["groq"]
            calls = []

            class Handler(BaseHTTPRequestHandler):
                def do_POST(self):
                    self.rfile.read(int(self.headers["content-length"]))
                    calls.append(self.path)
                    data = json.dumps({"error": {"message": message, "type": expected_code}}).encode()
                    self.send_response(status)
                    self.send_header("content-type", "application/json")
                    self.send_header("content-length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)

                def log_message(self, *_):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)
            groq["baseURL"] = f"http://127.0.0.1:{server.server_port}/v1"
            groq["api"] = "openai-completions"
            patch = root / "fixture.yml"
            patch.write_text(master.yaml.safe_dump([
                {"id": "llm-pi-ai", "config": {"providers": {"groq": groq}}},
                {"id": "agent-default-model", "config": {"provider": "groq", "model": "qwen/qwen3.8-27b", "reasoningEffort": "low"}},
                {"id": "session-title-llm", "disabled": True},
                {"id": "session-persistence-jsonl", "config": {"root": str(dsh_home / "sessions"), "compression": "none"}},
                {"id": "otel", "disabled": True},
                {"id": "session-telemetry-otel", "disabled": True},
            ]))
            clock = root / "clock.mjs"
            clock.write_text("const real = globalThis.setTimeout; globalThis.setTimeout = (fn, ms, ...args) => real(fn, ms === 60000 ? 1 : ms, ...args);\n")
            env = {k: v for k, v in os.environ.items() if k in ("PATH", "TMPDIR")}
            env.update(HOME=str(home), DSH_HOME=str(dsh_home), DSH_TELEMETRY_DISABLED="1",
                       GROQ_API_KEY="synthetic-local-fixture-only", NODE_OPTIONS=f"--import={clock}")
            result = subprocess.run([os.environ["DSH"], "headless", "--patch", str(patch), "--json", "Return one word."],
                                    cwd=root, env=env, capture_output=True, text=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(calls), expected_calls, result.stderr)
            retries = []
            for path in dsh_home.rglob("*.jsonl"):
                for line in path.read_text().splitlines():
                    event = json.loads(line)
                    if event.get("type") == "llm/retry":
                        retries.append(event.get("data", {}))
            self.assertEqual(len(retries), expected_calls - 1)
            for retry in retries:
                self.assertEqual(retry["delayMs"], 60000)
                self.assertEqual(retry["maxRetries"], 3)

    def test_rate_limit_retries_are_bounded_and_use_the_full_minute(self):
        self.exercise(429, "rate limit reached", 4, "rate_limit_exceeded")

    def test_authentication_is_terminal(self):
        self.exercise(401, "invalid api key", 1, "authentication_error")

    def test_exhausted_quota_is_terminal(self):
        self.exercise(429, "insufficient_quota: quota exceeded", 1, "insufficient_quota")


if __name__ == "__main__":
    unittest.main()
