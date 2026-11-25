"""hc-station against a fake core socket, a fake herdr-core and fake shells.

Nothing here talks to a real core, a user manager or the live runtime dir:
XDG_RUNTIME_DIR, HOME and every program on PATH live in a temporary directory.
"""
import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest

BIN = Path(os.environ.get("DOTFILES_BIN", Path(__file__).resolve().parents[2] / "home/dot_local/bin"))
STATION = BIN / "hc-station"

# One recorder for every fake program: it writes what it was run with next to
# itself, so it works even under the clean environment hc-station gives attach.
FAKE = r'''
import json, os, sys
from pathlib import Path
here = Path(sys.argv[0]).resolve().parent
name = Path(sys.argv[0]).name
record = {"argv": sys.argv[1:], "cwd": os.getcwd(), "env": dict(os.environ)}
with open(here / (name + ".json"), "a") as out:
    out.write(json.dumps(record) + "\n")
if name == "infocmp":
    ok = (here / "terminfo-ok").exists() and os.environ.get("TERM") == "xterm-kitty"
    sys.exit(0 if ok else 1)
'''


class FakeCore:
    """A plain-mode JSON-RPC listener: records requests, answers per `mode`."""

    def __init__(self, path, mode="ok"):
        self.path, self.mode, self.requests, self.connections = str(path), mode, [], 0
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(8)
        self.server.settimeout(0.1)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.thread.start()

    def loop(self):
        while not self.stop.is_set():
            try:
                peer, _ = self.server.accept()
            except (socket.timeout, OSError):
                continue
            self.connections += 1
            threading.Thread(target=self.serve, args=(peer,), daemon=True).start()

    def serve(self, peer):
        with peer:
            peer.settimeout(5)
            buffer = b""
            try:
                while b"\n" not in buffer:
                    chunk = peer.recv(65536)
                    if not chunk:
                        return
                    buffer += chunk
            except OSError:
                return
            request = json.loads(buffer.split(b"\n", 1)[0])
            self.requests.append(request)
            if self.mode == "silent":
                self.stop.wait(10)
                return
            if self.mode == "error":
                reply = {"jsonrpc": "2.0", "id": request["id"], "error": {
                    "code": -32000, "message": 'cannot start "/bin/sh"',
                    "data": {"kind": "spawn_failed", "hint": ""}}}
            else:
                reply = {"jsonrpc": "2.0", "id": request["id"], "result": {
                    "address": "t7", "state": "live", "labels": request["params"].get("labels", {})}}
            # A notification line first: the client must match the reply by id.
            peer.sendall(b'{"jsonrpc":"2.0","method":"noise","params":{}}\n' + json.dumps(reply).encode() + b"\n")

    def close(self):
        self.stop.set()
        self.server.close()
        self.thread.join(2)


class Station(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hcst")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.hcdir = self.root / "hc"
        self.home = self.root / "home"
        for directory in (self.bin, self.hcdir, self.home / "proj", self.root / "run"):
            directory.mkdir(parents=True)
        for path in (self.bin / "fish", self.bin / "infocmp", self.bin / "systemctl", self.hcdir / "herdr-core"):
            path.write_text("#!" + sys.executable + "\n" + FAKE)
            path.chmod(0o755)
        self.socket = self.root / "run" / "herdr-core" / "default.sock"
        self.env = {
            "PATH": str(self.bin), "HOME": str(self.home), "USER": "tester", "LANG": "C.UTF-8",
            "HC_BIN": str(self.hcdir / "herdr-core"), "XDG_RUNTIME_DIR": str(self.root / "run"),
            "XDG_CONFIG_HOME": str(self.root / "config"), "XDG_STATE_HOME": str(self.root / "state"),
            "HC_STATION_TIMEOUT": "0.5",
            # What an ssh login may carry; none of it may reach attach.
            "CLAUDECODE": "1", "SSH_CONNECTION": "1.2.3.4 5 6.7.8.9 22",
            "SECRET_TOKEN": "x", "HERDR_ENV": "1", "KITTY_WINDOW_ID": "3",
        }
        self.core = None

    def tearDown(self):
        if self.core:
            self.core.close()

    def start_core(self, mode="ok"):
        self.core = FakeCore(self.socket, mode)
        return self.core

    def run_station(self, *args, env=None, timeout=20):
        return subprocess.run([sys.executable, str(STATION), *args], env=env or self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)

    def records(self, path):
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines()]

    def attach_calls(self):
        return self.records(self.hcdir / "herdr-core.json")

    def fish_calls(self):
        return self.records(self.bin / "fish.json")

    def systemctl_calls(self):
        return [r["argv"] for r in self.records(self.bin / "systemctl.json")]

    def params(self):
        self.assertEqual(len(self.core.requests), 1, self.core.requests)
        request = self.core.requests[0]
        self.assertEqual(request["method"], "terminal.run")
        return request["params"]

    def assert_fallback(self, result, kind, cwd=None):
        self.assertIn(f"hc-station: hc unavailable ({kind}): plain fish, not persistent", result.stderr)
        calls = self.fish_calls()
        self.assertEqual(len(calls), 1, result.stderr)
        self.assertEqual(calls[0]["argv"], ["--login", "--interactive"])
        self.assertEqual(calls[0]["cwd"], str(cwd or self.home))
        self.assertNotIn("HERDR_ENV", calls[0]["env"])
        self.assertEqual(self.attach_calls(), [])

    # -- the station path ---------------------------------------------------

    def test_new_sends_the_station_params_and_execs_attach(self):
        self.start_core()
        (self.bin / "terminfo-ok").touch()
        result = self.run_station("new", "--label", "seat=zenbook", "--kitty-version", "0.50.0",
                                  "--cwd", str(self.home / "proj"))
        self.assertEqual(result.returncode, 0, result.stderr)
        params = self.params()
        self.assertEqual(params["cwd"], str(self.home / "proj"))
        self.assertIs(params["no_parent"], True)
        self.assertIs(params["no_notify"], True)
        self.assertEqual(params["labels"], {"owner": "tester", "ui": "kitty", "kind": "shell", "seat": "zenbook"})
        self.assertEqual(params["env"], {"TERM": "xterm-kitty", "TERM_PROGRAM": "kitty",
                                         "COLORTERM": "truecolor", "TERM_PROGRAM_VERSION": "0.50.0"})
        for absent in ("argv", "keep", "size", "line", "rm"):
            self.assertNotIn(absent, params)
        self.assertNotIn("KITTY", json.dumps(params))
        calls = self.attach_calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["argv"], ["attach", "--history", "2000", "t7"])
        attach_env = calls[0]["env"]
        for leaked in ("CLAUDECODE", "SSH_CONNECTION", "SECRET_TOKEN", "HERDR_ENV", "KITTY_WINDOW_ID",
                       "HC_STATION_TIMEOUT", "HC_BIN"):
            self.assertNotIn(leaked, attach_env)
        self.assertEqual(attach_env["XDG_RUNTIME_DIR"], str(self.root / "run"))
        self.assertEqual(attach_env["PATH"], "/run/current-system/sw/bin:/etc/profiles/per-user/tester/bin")
        self.assertEqual(self.systemctl_calls(), [])
        self.assertEqual(self.fish_calls(), [])

    def test_default_cwd_is_home(self):
        self.start_core()
        self.assertEqual(self.run_station("new").returncode, 0)
        self.assertEqual(self.params()["cwd"], str(self.home))

    def test_program_argv_makes_an_agent_station(self):
        self.start_core()
        result = self.run_station("new", "--", "claude", "--resume", "x", "--no-fallback")
        self.assertEqual(result.returncode, 0, result.stderr)
        params = self.params()
        self.assertEqual(params["argv"], ["claude", "--resume", "x", "--no-fallback"])
        self.assertEqual(params["labels"]["kind"], "agent")

    def test_no_identity_env_without_kitty_terminfo(self):
        self.start_core()
        self.assertEqual(self.run_station("new", "--kitty-version", "0.50.0").returncode, 0)
        self.assertNotIn("env", self.params())
        self.assertEqual(self.records(self.bin / "infocmp.json")[0]["env"]["TERM"], "xterm-kitty")

    def test_no_identity_env_without_infocmp(self):
        self.start_core()
        (self.bin / "infocmp").unlink()
        self.assertEqual(self.run_station("new").returncode, 0)
        self.assertNotIn("env", self.params())

    def test_a_bad_kitty_version_is_dropped(self):
        self.start_core()
        (self.bin / "terminfo-ok").touch()
        for bad in ("0.50; rm -rf ~", "v0.50", "0.50.", "0.50\n"):
            self.core.requests.clear()
            self.assertEqual(self.run_station("new", "--kitty-version", bad).returncode, 0)
            env = self.params()["env"]
            self.assertNotIn("TERM_PROGRAM_VERSION", env, bad)
            self.assertEqual(env["TERM"], "xterm-kitty")

    def test_a_missing_cwd_starts_in_home_with_a_note(self):
        self.start_core()
        result = self.run_station("new", "--cwd", str(self.home / "gone"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.params()["cwd"], str(self.home))
        self.assertIn("is not a directory here; starting in", result.stderr)

    def test_argument_forms(self):
        self.start_core()
        cases = [
            (["new", f"--cwd={self.home / 'proj'}", "--label=a=b", "sh", "-c", "x --cwd y"],
             {"cwd": str(self.home / "proj"), "argv": ["sh", "-c", "x --cwd y"], "a": "b"}),
            (["new", "--no-fallback", "--kitty-version=1.2", "--", "--weird", "-x"],
             {"cwd": str(self.home), "argv": ["--weird", "-x"]}),
        ]
        for argv, want in cases:
            self.core.requests.clear()
            result = self.run_station(*argv)
            self.assertEqual(result.returncode, 0, result.stderr)
            params = self.params()
            self.assertEqual(params["cwd"], want["cwd"], argv)
            self.assertEqual(params["argv"], want["argv"], argv)
            if "a" in want:
                self.assertEqual(params["labels"]["a"], "b")
        self.assertEqual(self.run_station("--help").returncode, 0)
        self.assertEqual(self.run_station().returncode, 2)
        self.assertEqual(self.run_station("attach").returncode, 2)
        self.assertEqual(self.run_station("attach", "t1", "--history", "lots").returncode, 2)
        self.assertEqual(self.fish_calls(), [])
        (self.hcdir / "herdr-core.json").unlink()
        self.assert_fallback(self.run_station("new", "--bogus", "--cwd", str(self.home / "proj")), "usage",
                             self.home / "proj")

    def test_a_bad_label_falls_back(self):
        self.start_core()
        self.assert_fallback(self.run_station("new", "--label", "noequals"), "usage")
        self.assertEqual(self.core.requests, [])

    def test_tty_size_and_the_kitty_user_var(self):
        self.start_core()
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 43, 132, 0, 0))
        child = subprocess.Popen([sys.executable, str(STATION), "new"], env=self.env,
                                 stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = b""
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
            elif child.poll() is not None:
                break
        child.wait(5)
        os.close(master)
        self.assertEqual(child.returncode, 0, output)
        self.assertEqual(self.params()["size"], {"cols": 132, "rows": 43})
        mark = base64.b64encode(b"t7").decode()
        self.assertIn(f"\033]1337;SetUserVar=hc_addr={mark}\033\\".encode(), output)

    # -- never autostart; systemd starts the declared core ------------------

    def test_no_socket_asks_systemd_once_then_falls_back(self):
        result = self.run_station("new", "--cwd", str(self.home / "proj"))
        self.assertEqual(self.systemctl_calls(), [["--user", "start", "--no-block", "hc-core.service"]])
        self.assert_fallback(result, "no core", self.home / "proj")

    def test_a_stale_socket_is_no_core(self):
        os.makedirs(self.socket.parent)
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(str(self.socket))
        stale.close()  # the file stays, nobody listens: connect is refused
        result = self.run_station("new")
        self.assertEqual(len(self.systemctl_calls()), 1)
        self.assert_fallback(result, "no core")

    def test_the_unit_brings_the_core_up(self):
        log = self.bin / "systemctl.json"

        def start_when_asked():
            deadline = time.monotonic() + 10
            while not log.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            time.sleep(0.2)
            self.start_core()

        helper = threading.Thread(target=start_when_asked)
        helper.start()
        result = self.run_station("new", env=dict(self.env, HC_STATION_TIMEOUT="5"))
        helper.join()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attach_calls()[0]["argv"][-1], "t7")
        self.assertEqual(self.fish_calls(), [])

    def test_another_session_never_starts_the_unit(self):
        result = self.run_station("new", env=dict(self.env, HC_SESSION="other"))
        self.assertEqual(self.systemctl_calls(), [])
        self.assert_fallback(result, "no core")

    def test_hc_socket_is_used_and_never_starts_the_unit(self):
        self.socket = self.root / "elsewhere.sock"
        self.start_core()
        result = self.run_station("new", env=dict(self.env, HC_SOCKET=str(self.socket)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attach_calls()[0]["env"]["HC_SOCKET"], str(self.socket))
        self.core.close()
        self.core = None
        result = self.run_station("new", env=dict(self.env, HC_SOCKET=str(self.socket)))
        self.assertEqual(self.systemctl_calls(), [])
        self.assertIn("(no core)", result.stderr)

    def test_config_socket_is_honoured(self):
        self.socket = self.root / "fromconfig.sock"
        (self.root / "config" / "herdr-core").mkdir(parents=True)
        (self.root / "config" / "herdr-core" / "config.toml").write_text(f'socket = "{self.socket}"\n')
        self.start_core()
        self.assertEqual(self.run_station("new").returncode, 0)
        self.assertEqual(len(self.core.requests), 1)

    # -- every other failure falls back -------------------------------------

    def test_an_error_reply_falls_back(self):
        self.start_core("error")
        self.assert_fallback(self.run_station("new"), "spawn_failed")

    def test_a_silent_core_times_out_and_falls_back(self):
        self.start_core("silent")
        began = time.monotonic()
        result = self.run_station("new")
        self.assertLess(time.monotonic() - began, 5)
        self.assert_fallback(result, "timeout")

    def test_a_missing_binary_falls_back_before_any_call(self):
        self.start_core()
        result = self.run_station("new", env=dict(self.env, HC_BIN=str(self.root / "nope")))
        self.assert_fallback(result, "missing binary")
        self.assertEqual(self.core.requests, [])

    def test_no_fallback_exits_69(self):
        result = self.run_station("new", "--no-fallback")
        self.assertEqual(result.returncode, 69)
        self.assertIn("hc-station: hc unavailable (no core)", result.stderr)
        self.assertEqual(self.fish_calls(), [])

    def test_the_fallback_reaches_a_shell_without_fish(self):
        (self.bin / "fish").unlink()
        sh = self.bin / "sh"
        sh.write_text("#!" + sys.executable + "\n" + FAKE)
        sh.chmod(0o755)
        result = self.run_station("new")
        self.assertIn("plain fish, not persistent", result.stderr)
        self.assertEqual(self.records(self.bin / "sh.json")[0]["argv"], ["-i"])

    # -- attach --------------------------------------------------------------

    def test_attach_execs_with_the_address(self):
        self.start_core()
        result = self.run_station("attach", "t3", "--history", "50")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attach_calls()[0]["argv"], ["attach", "--history", "50", "t3"])
        self.assertEqual(self.core.requests, [])

    def test_attach_without_a_core_fails_and_starts_nothing(self):
        result = self.run_station("attach", "t3")
        self.assertEqual(result.returncode, 69)
        self.assertEqual(self.systemctl_calls(), [])
        self.assertEqual(self.fish_calls(), [])


if __name__ == "__main__":
    unittest.main()
