from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
UTILITY_OWNER = Path(
    os.environ.get(
        "AI_MEMORY_UTILITY_OWNER",
        REPO_ROOT / "pkgs/utility-model/utility_model.py",
    )
)
ZMX_TITLE = Path(
    os.environ.get(
        "AI_MEMORY_ZMX_TITLE",
        REPO_ROOT / "home/dot_local/bin/zmx-title",
    )
)


FAKE_FLM = r"""#!/usr/bin/env python3
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

record_dir = Path(os.environ["FAKE_FLM_RECORD_DIR"])
record_dir.mkdir(parents=True, exist_ok=True)
(record_dir / "argv.json").write_text(json.dumps(sys.argv[1:]))


def stop(_signum, _frame):
    (record_dir / "stopped").write_text(str(os.getpid()))
    raise SystemExit(0)


signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)

if os.environ.get("FAKE_FLM_MODE") == "hang":
    while True:
        time.sleep(0.1)

if len(sys.argv) < 3 or sys.argv[1] != "serve":
    raise SystemExit(2)

model = sys.argv[2]
port = int(sys.argv[sys.argv.index("--port") + 1])
host = sys.argv[sys.argv.index("--host") + 1]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/v1/models":
            self.send_error(404)
            return
        body = json.dumps({"data": [{"id": model}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        (record_dir / "request.json").write_text(json.dumps(request))
        body = json.dumps(
            {
                "id": "synthetic-completion",
                "model": model,
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
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        pass


server = HTTPServer((host, port), Handler)
try:
    server.serve_forever()
finally:
    server.server_close()
"""


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
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fake_flm = self.root / "flm"
        self.fake_flm.write_text(
            FAKE_FLM.replace(
                "#!/usr/bin/env python3",
                f"#!{sys.executable}",
                1,
            ),
            encoding="utf-8",
        )
        self.fake_flm.chmod(
            self.fake_flm.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
        )
        self.records = self.root / "records"
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_owner(
        self,
        request: dict[str, object],
        *,
        timeout: str = "10",
        mode: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "FAKE_FLM_RECORD_DIR": str(self.records),
                "XDG_RUNTIME_DIR": str(self.runtime),
            }
        )
        if mode is not None:
            environment["FAKE_FLM_MODE"] = mode
        return subprocess.run(
            [
                sys.executable,
                str(UTILITY_OWNER),
                "--flm",
                str(self.fake_flm),
                "--concrete-model",
                "qwen3:4b",
                "--context-tokens",
                "32768",
                "--timeout",
                timeout,
            ],
            input=json.dumps(request),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            timeout=15,
            check=False,
        )

    def test_stable_id_is_rewritten_for_one_start_request_stop_cycle(self) -> None:
        completed = self.run_owner(utility_request())
        self.assertEqual(completed.returncode, 0, completed.stderr)
        response = json.loads(completed.stdout)
        self.assertEqual(response["model"], "utility")

        invocation = json.loads((self.records / "argv.json").read_text())
        self.assertEqual(invocation[0:2], ["serve", "qwen3:4b"])
        self.assertEqual(invocation[invocation.index("--host") + 1], "127.0.0.1")
        self.assertEqual(invocation[invocation.index("--ctx-len") + 1], "32768")
        upstream = json.loads((self.records / "request.json").read_text())
        self.assertEqual(upstream["model"], "qwen3:4b")
        self.assertFalse(upstream["stream"])
        self.assertTrue((self.records / "stopped").is_file())

    def test_non_utility_requests_are_rejected_before_fastflowlm_starts(self) -> None:
        completed = self.run_owner(utility_request("qwen3:4b"))
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('must use model "utility"', completed.stderr)
        self.assertFalse((self.records / "argv.json").exists())

    def test_startup_timeout_still_stops_the_owned_child(self) -> None:
        completed = self.run_owner(utility_request(), timeout="0.6", mode="hang")
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("timed out", completed.stderr)
        self.assertTrue((self.records / "stopped").is_file())


class ZmxTitleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.fake_utility = self.bin_dir / "utility-model"
        self.fake_utility.write_text(
            FAKE_UTILITY.replace(
                "#!/usr/bin/env python3",
                f"#!{sys.executable}",
                1,
            ),
            encoding="utf-8",
        )
        self.fake_utility.chmod(
            self.fake_utility.stat().st_mode
            | stat.S_IXUSR
            | stat.S_IXGRP
            | stat.S_IXOTH
        )
        self.request_path = self.root / "request.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_title(
        self,
        fallback: str,
        *,
        enabled: bool,
        fail: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin_dir}:{environment['PATH']}",
                "ZMX_TITLE": "1" if enabled else "0",
                "FAKE_UTILITY_REQUEST": str(self.request_path),
                "FAKE_UTILITY_FAIL": "1" if fail else "0",
            }
        )
        return subprocess.run(
            [
                shutil.which("bash") or "/bin/bash",
                str(ZMX_TITLE),
                fallback,
                "synthetic terminal context",
            ],
            input="",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            timeout=10,
            check=False,
        )

    def test_disabled_and_failed_titling_preserve_exact_fallback(self) -> None:
        disabled = self.run_title("stable-fallback", enabled=False)
        self.assertEqual(disabled.stdout, "stable-fallback\n")
        failed = self.run_title("stable-fallback", enabled=True, fail=True)
        self.assertEqual(failed.stdout, "stable-fallback\n")

    def test_enabled_titling_names_only_the_stable_utility_id(self) -> None:
        completed = self.run_title("stable-fallback", enabled=True)
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout, "✨ Memory Drain\n")
        request = json.loads(self.request_path.read_text())
        self.assertEqual(request["model"], "utility")
        self.assertFalse(request["think"])
        source = ZMX_TITLE.read_text()
        self.assertNotIn("FLM_TITLE_", source)
        self.assertNotIn("qwen3:4b", source)
        self.assertNotIn("http://", source)


if __name__ == "__main__":
    unittest.main()
