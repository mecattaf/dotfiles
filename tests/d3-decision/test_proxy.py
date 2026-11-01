"""Check real llama-swap demand routing for a native decision API."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.error import URLError
from urllib.request import Request, urlopen


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def backend(port, model):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.send_response(200 if self.path == "/health" else 404)
            self.end_headers()

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            decision = model == "d3-ultra"
            expected = "/v1/systemone" if decision else "/v1/chat/completions"
            if self.path != expected:
                self.send_error(404)
                return
            result = ({"model": model, "answers": {"q": {"type": "noul", "noul": 0.75}},
                       "state_echo": body["state"]} if decision
                      else {"model": model, "choices": [{"message": {"content": "text"}}]})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())

    ThreadingHTTPServer(("127.0.0.1", int(port)), Handler).serve_forever()


class Proxy(unittest.TestCase):
    def test_native_decision_api_swaps_with_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            port = free_port()
            config = {"healthCheckTimeout": 15, "startPort": free_port(), "models": {}}
            for model in ["text", "d3-ultra"]:
                config["models"][model] = {
                    "cmd": shlex.join([sys.executable, __file__, "--backend", "${PORT}", model]),
                    "checkEndpoint": "/health", "ttl": 1,
                }
            (root / "config.json").write_text(json.dumps(config))
            with (root / "proxy.log").open("w+") as log:
                process = subprocess.Popen(
                    [os.environ["LLAMA_SWAP"], "-config", str(root / "config.json"),
                     "-listen", f"127.0.0.1:{port}"], stdout=log, stderr=log)
                try:
                    endpoint = f"http://127.0.0.1:{port}"
                    deadline = time.monotonic() + 15
                    while True:
                        try:
                            with urlopen(endpoint + "/health", timeout=2):
                                break
                        except (URLError, TimeoutError):
                            if process.poll() is not None or time.monotonic() > deadline:
                                raise RuntimeError("proxy startup failed")
                            time.sleep(0.1)

                    def running():
                        with urlopen(endpoint + "/running", timeout=2) as response:
                            return json.load(response)["running"]

                    with urlopen(endpoint + "/v1/models", timeout=2):
                        pass
                    self.assertEqual(running(), [])
                    body = {"model": "d3-ultra", "state": {"ticket": "charged twice"},
                            "questions": {"q": {"type": "noul", "instructions": "Billing?"}}}
                    request = Request(endpoint + "/upstream/d3-ultra/v1/systemone",
                                      data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
                    with urlopen(request, timeout=15) as response:
                        decision = json.load(response)
                    self.assertEqual(decision["state_echo"], body["state"])
                    self.assertEqual(decision["answers"]["q"]["noul"], 0.75)
                    self.assertNotIn("choices", decision)
                    self.assertEqual([row["model"] for row in running()], ["d3-ultra"])
                    request = Request(endpoint + "/v1/chat/completions",
                                      data=json.dumps({"model": "text", "messages": []}).encode(),
                                      headers={"Content-Type": "application/json"})
                    with urlopen(request, timeout=15) as response:
                        self.assertEqual(json.load(response)["model"], "text")
                    self.assertEqual([row["model"] for row in running()], ["text"])
                    deadline = time.monotonic() + 10
                    while running() and time.monotonic() < deadline:
                        time.sleep(0.1)
                    self.assertEqual(running(), [])
                except BaseException:
                    log.flush()
                    log.seek(0)
                    print(log.read(), file=sys.stderr)
                    raise
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--backend":
        backend(*sys.argv[2:])
    else:
        unittest.main()
