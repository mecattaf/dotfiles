"""Reconnect against a fake SSH/Kitty protocol; never touch a user's window."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_remote_command import load


FAKE = r'''
import json, os, sys
from pathlib import Path
root = Path(os.environ["FIXTURE"])
state = json.loads((root / "state.json").read_text())
if sys.argv[1] == "@":
    if state.get("broken_query"):
        print(state["broken_query"])
    else:
        print(json.dumps([{"tabs": [{"windows": [
            {"id": 7, "user_vars": {"hc_addr": state.get("marker", "")}},
            {"id": 8, "user_vars": {"hc_addr": "wrong-window"}}
        ]}]}]))
    sys.exit(0)
assert sys.argv[1] == "ssh", sys.argv
with open(root / "calls.jsonl", "a") as out:
    out.write(json.dumps(sys.argv[2:]) + "\n")
result = state["results"].pop(0)
if "marker" in result:
    state["marker"] = result["marker"]
(root / "state.json").write_text(json.dumps(state))
sys.exit(result["status"])
'''


class Reconnect(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dt = load()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dterm-reconnect-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        kitten = self.root / "kitten"
        kitten.write_text("#!" + sys.executable + "\n" + FAKE)
        kitten.chmod(0o755)
        self.env = {"PATH": str(self.root), "FIXTURE": str(self.root),
                    "KITTY_PID": "123", "KITTY_WINDOW_ID": "7", "KITTY_LISTEN_ON": "unix:@fixture"}

    def run_connection(self, options, state):
        (self.root / "state.json").write_text(json.dumps(state))
        self.stderr = io.StringIO()
        with contextlib.redirect_stderr(self.stderr), patch.object(self.dt.time, "sleep") as sleep:
            status = self.dt.connect(self.dt.parse_args(options), self.env, "0.50.0")
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        return status, [call[-1] for call in calls], sleep.call_args_list

    def test_new_then_retries_only_confirmed_address(self):
        status, commands, delays = self.run_connection([], {"results": [
            {"status": 255, "marker": "t39"}, {"status": 255}, {"status": 0}]})
        self.assertEqual(status, 0)
        self.assertIn("new --label", commands[0])
        self.assertEqual(commands[1:], [self.dt.station_command(None, address="t39")] * 2)
        self.assertEqual([call.args[0] for call in delays], [1, 2])

    def test_explicit_attach_retries_without_metadata_and_stops_on_remote_failure(self):
        self.env.pop("KITTY_LISTEN_ON")
        status, commands, delays = self.run_connection(["--attach", "t7"], {"results": [
            {"status": 255}, {"status": 255}, {"status": 42}]})
        self.assertEqual(status, 42)
        self.assertEqual(commands, [self.dt.station_command(None, address="t7")] * 3)
        self.assertEqual([call.args[0] for call in delays], [1, 2])

    def test_uncertain_new_never_creates_again(self):
        for state in ({"results": [{"status": 255}]},
                      {"marker": "old", "results": [{"status": 255}]},
                      {"broken_query": "invalid json", "results": [{"status": 255, "marker": "t7"}]},
                      {"results": [{"status": 255, "marker": "t7; touch PWNED"}]}):
            with self.subTest(state=state):
                path = self.root / "calls.jsonl"
                path.unlink(missing_ok=True)
                status, commands, delays = self.run_connection([], state)
                self.assertEqual(status, 255)
                self.assertEqual(len(commands), 1)
                self.assertEqual(delays, [])
                self.assertIn("before a new station address was confirmed", self.stderr.getvalue())

    def test_detach_or_exit_does_not_reconnect(self):
        status, commands, delays = self.run_connection(["--attach", "t7"], {"results": [{"status": 0}]})
        self.assertEqual(status, 0)
        self.assertEqual(len(commands), 1)
        self.assertEqual(delays, [])

    def test_plain_shell_never_reconnects(self):
        status, commands, delays = self.run_connection(["--plain"], {"results": [{"status": 255}]})
        self.assertEqual(status, 255)
        self.assertEqual(commands, [self.dt.plain_command(None)])
        self.assertEqual(delays, [])

    def test_only_this_window_can_supply_a_marker(self):
        (self.root / "state.json").write_text('{"marker": "t39"}')
        self.assertEqual(self.dt.kitty_address(self.env), "t39")
        self.env["KITTY_WINDOW_ID"] = "9"
        self.assertIsNone(self.dt.kitty_address(self.env))


if __name__ == "__main__":
    unittest.main()
