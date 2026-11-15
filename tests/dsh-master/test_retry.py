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
    def exercise(self, status, message, expected_calls, expected_code, missing_store=False, provider="groq"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            home.mkdir()
            dsh_home = root / "dsh"
            dsh_home.mkdir()
            with (Path(os.environ["PROBES"]) / f"profiles/master-{provider}/cordis.patch.yml").open() as stream:
                rows = master.yaml.load(stream, Loader=master.Loader)
            config = next(row["config"] for row in rows if row.get("id") == "llm-pi-ai")
            route = config["providers"][provider]
            calls = []

            class Handler(BaseHTTPRequestHandler):
                def do_POST(self):
                    body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                    calls.append(body)
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
            route["baseURL"] = f"http://127.0.0.1:{server.server_port}/v1"
            route["api"] = "openai-completions"
            model = next(row["config"] for row in rows if row.get("id") == "agent-default-model")
            patch = root / "fixture.yml"
            patch.write_text(master.yaml.safe_dump([
                {"id": "llm-pi-ai", "config": {"providers": {provider: route}}},
                {"id": "agent-default-model", "config": model},
                {"id": "session-title-llm", "disabled": True},
                {"id": "session-persistence-jsonl", "config": {"root": str(dsh_home / "sessions"), "compression": "none"}},
                {"id": "otel", "disabled": True},
                {"id": "session-telemetry-otel", "disabled": True},
            ]))
            if missing_store:
                credential = next(row for row in rows if row.get("id") == "credentials")
                expression = credential["config"]["path"]["__js"]
                with patch.open("a") as stream:
                    stream.write(f"- id: credentials\n  disabled: false\n  config:\n    path: !!js {expression}\n    watch: false\n")
                    stream.write("- id: llm-pi-ai\n  inject: [llm, credentials]\n")
                (root / ".env").write_text("GROQ_API_KEY=synthetic-unselected-project-key\n")
            clock = root / "clock.mjs"
            clock.write_text("const real = globalThis.setTimeout; globalThis.setTimeout = (fn, ms, ...args) => real(fn, ms === 60000 ? 1 : ms, ...args);\n")
            env = {k: v for k, v in os.environ.items() if k in ("PATH", "TMPDIR")}
            env.update(HOME=str(home), DSH_HOME=str(dsh_home), DSH_TELEMETRY_DISABLED="1",
                       GROQ_API_KEY="synthetic-local-fixture-only", NODE_OPTIONS=f"--import={clock}")
            env[route["apiKeyEnv"]] = "synthetic-local-fixture-only"
            result = subprocess.run([os.environ["DSH"], "headless", "--patch", str(patch), "--json", "Return one word."],
                                    cwd=root, env=env, capture_output=True, text=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(calls), expected_calls, result.stderr)
            if provider == "nvidia":
                self.assertEqual(calls[0]["model"], "nvidia/nemotron-3.5-lightning-30b-a3b")
                self.assertEqual(calls[0]["chat_template_kwargs"], {"enable_thinking": False})
                self.assertNotIn("reasoning_effort", calls[0])
            retries = []
            for path in dsh_home.rglob("*.jsonl"):
                for line in path.read_text().splitlines():
                    event = json.loads(line)
                    if event.get("type") == "llm/retry":
                        retries.append(event.get("data", {}))
            self.assertEqual(len(retries), max(expected_calls - 1, 0))
            for retry in retries:
                self.assertEqual(retry["delayMs"], 60000)
                self.assertEqual(retry["maxRetries"], 3)
            if missing_store:
                self.assertIn("master-credentials", result.stderr)

    def test_rate_limit_retries_are_bounded_and_use_the_full_minute(self):
        self.exercise(429, "rate limit reached", 4, "rate_limit_exceeded")

    def test_authentication_is_terminal(self):
        self.exercise(401, "invalid api key", 1, "authentication_error")

    def test_exhausted_quota_is_terminal(self):
        self.exercise(429, "insufficient_quota: quota exceeded", 1, "insufficient_quota")

    def test_missing_native_store_refuses_ambient_and_project_credentials(self):
        self.exercise(401, "must not be reached", 0, "authentication_error", missing_store=True)

    def test_nvidia_native_config_sends_documented_thinking_off_body(self):
        self.exercise(401, "local fixture only", 1, "authentication_error", provider="nvidia")


if __name__ == "__main__":
    unittest.main()
