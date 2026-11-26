"""hc-reap against a fake herdr-core and a fake core socket.

Nothing here talks to a real core or the live runtime dir: HC_BIN, HC_SOCKET
and XDG_RUNTIME_DIR point into a temporary directory. Idle time is real: each
station's pid is a sleeping child whose stdin is a file with set atime/mtime,
which is what /proc/<pid>/fd/0 reports for a pts.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

BIN = Path(os.environ.get("DOTFILES_BIN", Path(__file__).resolve().parents[2] / "home/dot_local/bin"))
REAP = BIN / "hc-reap"

FAKE = r'''
import json, os, sys
from pathlib import Path
here = Path(sys.argv[0]).resolve().parent
with open(here / "calls.jsonl", "a") as out:
    out.write(json.dumps({"argv": sys.argv[1:], "env": dict(os.environ)}) + "\n")
fixture = json.loads((here / "fixture.json").read_text())
verb, rest = sys.argv[1], [a for a in sys.argv[2:] if a != "--json"]
if verb == "ls":
    print(json.dumps(fixture["ls"]))
elif verb == "get":
    record = fixture["get"].get(rest[0])
    if record is None:
        print(json.dumps({"error": {"kind": "not_found"}}))
        sys.exit(3)
    print(json.dumps(record))
elif verb == "kill":
    print(json.dumps(dict(fixture["get"][rest[0]], state="finished", reason="killed")))
elif verb == "rm":
    print(json.dumps({"removed": rest[0]}))
'''


class Reap(unittest.TestCase):
    def setUp(self):
        # AF_UNIX paths are limited to 108 bytes: keep the root short.
        self.temp = tempfile.TemporaryDirectory(prefix="reap", dir="/tmp" if os.access("/tmp", os.W_OK) else None)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.hc = self.root / "herdr-core"
        self.hc.write_text("#!" + sys.executable + "\n" + FAKE)
        self.hc.chmod(0o755)
        self.sock = self.root / "default.sock"
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(self.sock))
        self.server.listen(8)
        self.addCleanup(self.server.close)
        self.ls, self.records, self.children = [], {}, []
        self.addCleanup(self.stop_children)

    def stop_children(self):
        for child in self.children:
            child.kill()
            child.wait()

    def sleeper(self, hours):
        """A live pid whose fd 0 was last read/written `hours` ago."""
        tty = self.root / f"pts-{len(self.children)}"
        tty.write_text("")
        stamp = time.time() - hours * 3600
        os.utime(tty, (stamp, stamp))
        with open(tty) as stdin:
            child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"], stdin=stdin)
        self.children.append(child)
        return child.pid

    def station(self, address, hours=30.0, labels=None, argv=("fish", "--login"), foreground="fish", pid=None, **extra):
        record = {"address": address, "name": "st-" + address, "argv": list(argv), "state": "live", "keep": False,
                  "parent": None, "labels": {"ui": "kitty", "owner": "tom", "kind": "shell"} if labels is None else labels,
                  "foreground": None if foreground is None else {"name": foreground, "pid": 1}, "status": None,
                  "pid": self.sleeper(hours) if pid is None else pid}
        record.update(extra)
        self.records[address] = record
        self.ls.append({"address": address, "name": record["name"], "state": "live", "turn": 0})
        return record

    def run_reap(self, *args, extra_env=None):
        (self.root / "fixture.json").write_text(json.dumps({"ls": {"hidden_finished": 0, "terminals": self.ls},
                                                            "get": self.records}))
        env = {"PATH": os.environ.get("PATH", "/run/current-system/sw/bin:/usr/bin:/bin"), "HOME": str(self.root),
               "HC_BIN": str(self.hc), "HC_SOCKET": str(self.sock), "XDG_RUNTIME_DIR": str(self.root)}
        env.update(extra_env or {})
        return subprocess.run([sys.executable, str(REAP), *args], env=env, capture_output=True, text=True, timeout=30)

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def verbs(self, *verbs):
        return [call["argv"][:2] for call in self.calls() if call["argv"][0] in verbs]

    def line(self, output, address):
        return next((line for line in output.splitlines() if line.split()[:1] == [address]), None)

    def test_lists_an_idle_station_and_ends_nothing(self):
        self.station("t1")
        result = self.run_reap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.line(result.stdout, "t1").endswith("REAP"), result.stdout)
        self.assertIn("1 to reap; run with --kill to end them", result.stdout)
        self.assertEqual(self.verbs("kill", "rm"), [])

    def test_kill_ends_only_the_idle_station(self):
        self.station("t1")
        self.station("t2", hours=1)
        result = self.run_reap("--kill")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.verbs("kill", "rm"), [["kill", "t1"], ["rm", "t1"]])
        self.assertIn("removed t1", result.stdout)
        self.assertTrue(self.line(result.stdout, "t2").endswith("recent"))

    def test_a_terminal_without_ui_kitty_is_never_touched(self):
        self.station("t1", labels={"owner": "floor"})
        result = self.run_reap("--kill")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.line(result.stdout, "t1"))
        self.assertEqual(self.verbs("kill", "rm"), [])

    def test_the_verdicts_that_spare_a_station(self):
        kitty = {"ui": "kitty", "owner": "tom"}
        self.station("t1", keep=True)
        self.station("t2", labels=dict(kitty, reap="never"))
        self.station("t3")
        self.station("t4", labels={"owner": "floor"}, parent="t3")
        self.station("t5", argv=("claude",), foreground="claude", status={"state": "working", "title": "x"})
        self.station("t6", argv=("claude",), foreground="claude", status="blocked")
        self.station("t7", foreground="sleep")
        self.station("t8", hours=1)
        self.station("t9", pid=2 ** 22 + 12345)
        result = self.run_reap("--kill")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {"t1": "kept", "t2": "reap=never", "t3": "has children", "t5": "working", "t6": "blocked",
                    "t7": "job running (sleep)", "t8": "recent", "t9": "no pts"}
        for address, why in expected.items():
            self.assertTrue(self.line(result.stdout, address).endswith(why), (address, result.stdout))
        self.assertEqual(self.verbs("kill", "rm"), [])

    def test_another_machines_terminal_is_skipped(self):
        self.station("t1", hours=1)
        self.ls.append({"address": "nas/t9", "name": "remote", "state": "live", "turn": 0})
        self.records["nas/t9"] = dict(self.records["t1"], address="nas/t9")
        result = self.run_reap("--kill")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("nas/t9", result.stdout)
        self.assertNotIn(["get", "nas/t9"], self.verbs("get"))

    def test_no_core_means_no_call(self):
        self.station("t1")
        missing = self.run_reap(extra_env={"HC_SOCKET": str(self.root / "missing.sock")})
        self.server.close()  # the socket file stays; connect is refused
        stale = self.run_reap()
        for result in (missing, stale):
            self.assertEqual(result.returncode, 3, result.stdout)
            self.assertIn("no hc core answers on", result.stderr)
        self.assertFalse((self.root / "calls.jsonl").exists())

    def test_calls_run_with_a_clean_environment(self):
        self.station("t1")
        self.run_reap("--kill", extra_env={"SECRET_TOKEN": "x", "CLAUDECODE": "1", "SSH_CONNECTION": "a b"})
        self.assertTrue(self.calls())
        for call in self.calls():
            self.assertFalse({"SECRET_TOKEN", "CLAUDECODE", "SSH_CONNECTION"} & set(call["env"]))
            self.assertTrue(call["env"]["PATH"].startswith("/run/wrappers/bin:/etc/profiles/per-user/"))
            self.assertEqual(call["argv"][-1], "--json")

    def test_label_filter(self):
        self.station("t1", labels={"ui": "kitty", "seat": "zenbook"})
        self.station("t2", labels={"ui": "kitty", "seat": "rehearsal-1"})
        result = self.run_reap("--label", "seat=zenbook")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(self.line(result.stdout, "t1"))
        self.assertIsNone(self.line(result.stdout, "t2"))

    def test_bad_arguments(self):
        for args in (["--hours", "0"], ["--hours", "-1"], ["--label", "novalue"]):
            result = self.run_reap(*args)
            self.assertEqual(result.returncode, 2, args)
        self.assertFalse((self.root / "calls.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
