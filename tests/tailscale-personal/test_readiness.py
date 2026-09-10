"""Run the evaluated readiness program against synthetic daemon responses."""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

FIXTURES = json.loads(pathlib.Path(sys.argv.pop(1)).read_text())
SCRIPT = pathlib.Path(FIXTURES["public"]["container"]["funnelUnit"]
                      ["serviceConfig"]["ExecCondition"]).read_text()


def status(caps=None, state="Running"):
    if caps is None:
        caps = ["https", "funnel", "https://tailscale.com/cap/funnel-ports?ports=443,8443,10000"]
    return {"BackendState": state, "Self": {"CapMap": {key: [] for key in caps}}}


class Readiness(unittest.TestCase):
    def run_ready(self, responses, timeout=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            mock = root / "tailscale"
            mock.write_text("#!/bin/sh\n"
                            "test \"$*\" = 'status --json --peers=false' || exit 99\n"
                            f"exec {sys.executable} {root / 'response.py'}\n")
            mock.chmod(0o700)
            (root / "responses.json").write_text(json.dumps(responses))
            (root / "response.py").write_text(
                "import json, pathlib\n"
                f"p = pathlib.Path({str(root / 'responses.json')!r})\n"
                "r = json.loads(p.read_text())\n"
                "print(r[0])\n"
                "p.write_text(json.dumps(r[1:] if len(r) > 1 else r))\n")
            text = re.sub(r"/nix/store/[^ /]+/bin/tailscale", str(mock), SCRIPT)
            text = re.sub(r"/nix/store/[^ /]+/bin/sleep 2", ":", text)
            if timeout:
                text = text.replace("SECONDS + 60", "SECONDS + 0")
            script = root / "ready"
            script.write_text(text)
            script.chmod(0o700)
            return subprocess.run([str(script)], capture_output=True, text=True, timeout=5)

    def test_running_authorized_node(self):
        self.assertEqual(self.run_ready([json.dumps(status())]).returncode, 0)

    def test_nostate_race_recovers_without_reconfiguring_daemon(self):
        self.assertEqual(self.run_ready([json.dumps(status(state="NoState")),
                                        json.dumps(status())]).returncode, 0)

    def test_missing_or_unknown_capabilities_skip_without_retry_or_secret_output(self):
        for caps in [[], ["https"], ["funnel"], ["https", "funnel"],
                     ["https", "funnel", "https://tailscale.com/cap/funnel-ports?ports=443"],
                     ["https", "funnel", "https://tailscale.com/cap/funnel-ports?ports=unknown"]]:
            with self.subTest(caps=caps):
                data = status(caps)
                data["secret_fixture"] = "must-not-be-logged"
                result = self.run_ready([json.dumps(data)])
                self.assertEqual(result.returncode, 1)
                self.assertNotIn("must-not-be-logged", result.stdout + result.stderr)

    def test_port_ranges_supported(self):
        data = status(["https", "funnel", "https://tailscale.com/cap/funnel-ports?ports=8400-8500"])
        self.assertEqual(self.run_ready([json.dumps(data)]).returncode, 0)

    def test_malformed_json_then_recovery(self):
        self.assertEqual(self.run_ready(["not-json", json.dumps(status())]).returncode, 0)

    def test_readiness_timeout_is_bounded_retryable_failure(self):
        result = self.run_ready([], timeout=True)
        self.assertEqual(result.returncode, 255)
        self.assertIn("readiness timed out", result.stderr)


if __name__ == "__main__":
    unittest.main()
