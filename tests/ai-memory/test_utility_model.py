from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
UTILITY_OWNER = Path(
    os.environ.get(
        "AI_MEMORY_UTILITY_OWNER",
        REPO_ROOT / "pkgs/utility-model/utility_model.py",
    )
)


# The served ID llama-swap exposes for the deployment behind the stable
# `utility` slot since the 2026-08-29 GPU migration (lib/local-models.nix:
# utility.deployment -> qwen36-35b-a3b-mtp-ud-q8-k-xl -> model).
CONCRETE_MODEL = "qwen3.6-35b-a3b"


class QuietServer(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # A client that timed out and walked away is the point of one of the
        # tests below; do not dump its broken pipe into the check's output.
        pass


class FakeLlamaSwap:
    """A loopback stand-in for the coordinator's llama-swap endpoint.

    The wrapper owns no child process since the GPU migration, so the fake
    upstream is started by the test rather than exec'd by the code under test.
    """

    def __init__(self, *, status: int = 200, delay: float = 0.0) -> None:
        self.requests: list[dict[str, object]] = []
        self.paths: list[str] = []
        recorder = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"

            def do_POST(self) -> None:
                recorder.paths.append(self.path)
                length = int(self.headers.get("Content-Length", "0"))
                try:
                    recorder.requests.append(json.loads(self.rfile.read(length)))
                except (ValueError, OSError):
                    recorder.requests.append({})
                if delay:
                    time.sleep(delay)
                if status == 200:
                    body = json.dumps(
                        {
                            "id": "synthetic-completion",
                            "model": CONCRETE_MODEL,
                            "choices": [
                                {
                                    "index": 0,
                                    "message": {
                                        "role": "assistant",
                                        "content": '{"title":"local result"}',
                                    },
                                    "finish_reason": "stop",
                                }
                            ],
                        }
                    ).encode()
                else:
                    body = json.dumps(
                        {"error": "model qwen3.6-35b-a3b failed to load"}
                    ).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, _format, *_args):
                pass

        self.server = QuietServer(("127.0.0.1", 0), Handler)
        self.endpoint = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def closed_endpoint() -> str:
    """A loopback address nothing is listening on."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = int(sock.getsockname()[1])
    return f"http://127.0.0.1:{port}"


FAKE_UTILITY = r"""#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

request = json.load(sys.stdin)
Path(os.environ["FAKE_UTILITY_REQUEST"]).write_text(json.dumps(request))
if os.environ.get("FAKE_UTILITY_FAIL") == "1":
    raise SystemExit(1)
json.dump(
    {
        "model": "utility",
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": "<think>SECRET\nreasoning</think>\n✨ Memory / Drain!",
                }
            }
        ],
    },
    sys.stdout,
)
"""


def utility_request(model: str = "utility") -> dict[str, object]:
    return {
        "model": model,
        "stream": False,
        "messages": [{"role": "user", "content": "synthetic request"}],
    }


class UtilityOwnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.upstream: FakeLlamaSwap | None = None

    def tearDown(self) -> None:
        if self.upstream is not None:
            self.upstream.close()

    def start_upstream(self, **kwargs: object) -> FakeLlamaSwap:
        self.upstream = FakeLlamaSwap(**kwargs)  # type: ignore[arg-type]
        return self.upstream

    def run_owner(
        self,
        request: dict[str, object],
        *,
        endpoint: str,
        timeout: str = "10",
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(UTILITY_OWNER),
                "--endpoint",
                endpoint,
                "--concrete-model",
                CONCRETE_MODEL,
                "--context-tokens",
                "32768",
                "--timeout",
                timeout,
            ],
            input=json.dumps(request),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )

    def test_stable_id_is_rewritten_across_the_llama_swap_forward(self) -> None:
        upstream = self.start_upstream()
        completed = self.run_owner(utility_request(), endpoint=upstream.endpoint)
        self.assertEqual(completed.returncode, 0, completed.stderr)

        # Outbound: the caller's stable id becomes the concrete served id, on
        # the OpenAI chat-completions path, never streamed.
        self.assertEqual(upstream.paths, ["/v1/chat/completions"])
        self.assertEqual(len(upstream.requests), 1)
        self.assertEqual(upstream.requests[0]["model"], CONCRETE_MODEL)
        self.assertFalse(upstream.requests[0]["stream"])

        # Inbound: the concrete deployment stays behind the stable boundary.
        response = json.loads(completed.stdout)
        self.assertEqual(response["model"], "utility")
        self.assertEqual(
            response["choices"][0]["message"]["content"],
            '{"title":"local result"}',
        )

    def test_the_think_flag_is_translated_into_the_chat_template_kwarg(self) -> None:
        # Consumers name FastFlowLM's `think` flag. llama.cpp ignores it and
        # reasons anyway, spending the whole token budget before emitting any
        # answer — so the seam must translate it into the template kwarg the
        # backend actually honours, and must not leave the dead flag upstream.
        upstream = self.start_upstream()
        request = utility_request()
        request["think"] = False
        completed = self.run_owner(request, endpoint=upstream.endpoint)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        forwarded = upstream.requests[0]
        self.assertEqual(
            forwarded["chat_template_kwargs"],
            {"enable_thinking": False},
        )
        self.assertNotIn("think", forwarded)

    def test_a_request_that_wants_reasoning_is_forwarded_untouched(self) -> None:
        upstream = self.start_upstream()
        request = utility_request()
        request["think"] = True
        completed = self.run_owner(request, endpoint=upstream.endpoint)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        forwarded = upstream.requests[0]
        self.assertNotIn("chat_template_kwargs", forwarded)
        self.assertNotIn("think", forwarded)

    def test_a_trailing_slash_on_the_endpoint_does_not_double_the_path(self) -> None:
        upstream = self.start_upstream()
        completed = self.run_owner(
            utility_request(),
            endpoint=upstream.endpoint + "/",
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(upstream.paths, ["/v1/chat/completions"])

    def test_non_utility_requests_are_rejected_before_any_forward(self) -> None:
        upstream = self.start_upstream()
        completed = self.run_owner(
            utility_request(CONCRETE_MODEL),
            endpoint=upstream.endpoint,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('must use model "utility"', completed.stderr)
        self.assertEqual(upstream.requests, [])

    def test_unreachable_llama_swap_fails_with_one_bounded_line(self) -> None:
        endpoint = closed_endpoint()
        completed = self.run_owner(utility_request(), endpoint=endpoint)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("llama-swap", completed.stderr)
        self.assertIn(endpoint, completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)
        self.assertEqual(len(completed.stderr.splitlines()), 1)
        self.assertEqual(completed.stdout, "")

    def test_an_upstream_http_error_is_reported_without_a_traceback(self) -> None:
        upstream = self.start_upstream(status=503)
        completed = self.run_owner(utility_request(), endpoint=upstream.endpoint)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("HTTP 503", completed.stderr)
        self.assertIn(CONCRETE_MODEL, completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)
        self.assertEqual(completed.stdout, "")

    def test_a_slow_cold_load_times_out_cleanly_and_says_why(self) -> None:
        # llama-swap can legitimately spend minutes cold-loading; when the
        # caller's budget runs out first the failure must still name the cause
        # rather than surfacing a socket traceback.
        upstream = self.start_upstream(delay=5.0)
        completed = self.run_owner(
            utility_request(),
            endpoint=upstream.endpoint,
            timeout="0.6",
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("did not answer within", completed.stderr)
        self.assertIn("cold load", completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)

    def test_the_endpoint_must_be_an_http_url(self) -> None:
        completed = self.run_owner(utility_request(), endpoint="/var/run/flm.sock")
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("must be an http(s) URL", completed.stderr)


class UtilityOwnerProvenanceTests(unittest.TestCase):
    def test_owner_records_where_the_seam_runs_and_why_it_is_in_tree(self) -> None:
        # The 2026-08-29 migration moved this seam off the decommissioned NPU
        # onto llama-swap rather than retiring it. Pin both halves: where it is
        # installed (so nobody re-reads the FLM lifecycle back into it), and
        # that the flake check imports it by path regardless of installation.
        source = UTILITY_OWNER.read_text(encoding="utf-8")
        self.assertIn("2026-08-29", source)
        self.assertIn("llama-swap", source)
        self.assertIn("coordinator", source)
        self.assertIn("flake check", source)
        self.assertIn("by path", source)
        # The FLM child lifecycle is gone, not merely unused.
        self.assertNotIn("subprocess", source)
        self.assertNotIn("fcntl", source)


if __name__ == "__main__":
    unittest.main()
