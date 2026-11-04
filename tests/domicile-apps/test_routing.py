"""Run under runtime-test. All endpoints here are fakes, never the user's desktop."""
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import fcntl
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "home/dot_local/bin"


class Terminal:
    def __init__(self, argv, env):
        self.fd, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 1000, 600))
        self.output = b""
        self.process = subprocess.Popen(argv, env=env, stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True, preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
        os.close(slave)

    def read(self, duration=0.1):
        until = time.monotonic() + duration
        while time.monotonic() < until:
            if select.select([self.fd], [], [], max(0, until-time.monotonic()))[0]:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                self.output += data
        return self.output

    def expect(self, text, timeout=8):
        until = time.monotonic() + timeout
        while text.encode() not in self.output and time.monotonic() < until:
            self.read()
        assert text.encode() in self.output, self.output[-4000:].decode(errors="replace")

    def send(self, data):
        os.write(self.fd, data if isinstance(data, bytes) else data.encode())

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()
        os.close(self.fd)


MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ["CALLS"], "a") as f:
 f.write(json.dumps({"name":name,"args":sys.argv[1:],"config":os.environ.get("HERDR_CONFIG_PATH"),
  "context":os.environ.get("HERDR_PANE_ID"),"gdk":os.environ.get("GDK_BACKEND")})+"\\n")
if name=="herdr":
 if os.environ.get("READ_HERDR_INPUT"):
  import select, tty
  tty.setraw(0)
  data=os.read(0,4096) if select.select([0],[],[],0.3)[0] else b""
  Path(os.environ["CALLS"]+".input").write_bytes(data)
 print("MOCK REMOTE ATTACHED",flush=True)
 sys.exit(int(os.environ.get("MOCK_HERDR_EXIT","0")))
elif name=="ssh":
 sys.exit(int(os.environ.get("MOCK_SSH_EXIT","0")))
'''


class Routing(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        for name in ("kitty", "fish", "google-chrome-stable", "nautilus", "herdr", "ssh"):
            p = self.bin / name
            p.write_text(MOCK)
            p.chmod(0o755)
        # Simulate Home Manager's one-file store links.
        for name in ("domicile-apps", "domicile-terminal", "herdr-domicile-client", "herdr-projector"):
            (self.bin / name).symlink_to(BIN / name)
        (self.work / "config/herdr").mkdir(parents=True)
        (self.work / "config/herdr/desktop-client.toml").write_text("onboarding = false\n")
        self.calls = self.work / "calls"
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        CALLS=str(self.calls), TMPDIR=str(self.work),
                        XDG_CONFIG_HOME=str(self.work / "config"), TERM="xterm-256color",
                        HERDR_PANE_ID="foreign:pane", HERDR_ENV="1")

    def recorded(self):
        return [json.loads(s) for s in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def run_app(self, *args):
        return subprocess.run([str(self.bin / "domicile-apps"), *args],
                              env=self.env, capture_output=True, text=True)

    def term(self, *args):
        t = Terminal([str(self.bin / "domicile-terminal"), *args], self.env)
        self.addCleanup(t.close)
        return t

    def test_new_terminal_is_local_control_in_new_kitty(self):
        self.assertEqual(self.run_app().returncode, 0)
        call, = self.recorded()
        self.assertEqual(call["name"], "kitty")
        self.assertIn("--class", call["args"])
        self.assertEqual(call["args"][-2:], ["-e", str(self.bin / "domicile-terminal")])
        self.assertNotIn("--single-instance", call["args"])

    def test_regular_chrome_and_nautilus_preserve_argv(self):
        self.run_app("chrome", "https://example.invalid/a b", "--new-window")
        self.run_app("files", "/tmp/a b")
        a, b = self.recorded()
        self.assertEqual(a["args"], ["--ozone-platform=wayland", "https://example.invalid/a b", "--new-window"])
        self.assertEqual(b["args"], ["--new-window", "/tmp/a b"])
        self.assertEqual(b["gdk"], "wayland")

    def test_unknown_action_fails_closed(self):
        self.assertEqual(self.run_app("send-text").returncode, 2)
        self.assertEqual(self.recorded(), [])

    def test_first_ordinary_keys_never_contact_remote(self):
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("please continue the old claude task\n")
        t.expect("No action.")
        self.assertEqual(self.recorded(), [])
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_local_shell_has_no_nas_dependency_or_inherited_pane(self):
        t = self.term("--local")
        self.assertEqual(t.process.wait(timeout=3), 0)
        call, = self.recorded()
        self.assertEqual((call["name"], call["args"], call["context"]), ("fish", ["--no-config"], None))

    def test_piped_remote_consent_is_refused(self):
        p = subprocess.run([str(self.bin / "domicile-terminal"), "--remote-attempt",
                            "--remote", "nas", "--remote-keybindings", "server"],
                            input="ATTACH nas\n", text=True, env=self.env, capture_output=True)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(self.recorded(), [])

    def test_gate_rejects_other_targets_and_cancel(self):
        t = self.term("--remote-attempt", "--remote", "other", "--remote-keybindings", "server")
        self.assertEqual(t.process.wait(timeout=3), 2)
        u = self.term("--remote-attempt", "--remote", "nas", "--remote-keybindings", "server")
        u.expect("Type ATTACH nas")
        u.send("no\n")
        self.assertEqual(u.process.wait(timeout=3), 0)
        self.assertEqual(self.recorded(), [])

    def test_explicit_attachment_keeps_transport_and_neutral_config(self):
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("Type ATTACH nas")
        self.assertEqual([x["name"] for x in self.recorded()], ["ssh"])
        t.send("ATTACH nas\n")
        t.expect("Remote view ended")
        ssh, remote = self.recorded()
        self.assertIn("systemctl --user is-active", ssh["args"][-1])
        self.assertEqual(remote["args"], ["--remote", "nas", "--remote-keybindings", "server"])
        self.assertTrue(remote["config"].endswith("/herdr/desktop-client.toml"))
        self.assertIsNone(remote["context"])
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_typeahead_is_discarded_at_remote_boundary(self):
        self.env["READ_HERDR_INPUT"] = "1"
        t = self.term("--remote-attempt", "--remote", "nas", "--remote-keybindings", "server")
        t.expect("Type ATTACH nas")
        t.send(b"ATTACH nas\nSTRAY-ORDINARY-KEYS\n")
        self.assertEqual(t.process.wait(timeout=3), 0)
        self.assertEqual(Path(str(self.calls)+".input").read_bytes(), b"")

    def test_unreachable_nas_can_return_to_local_control(self):
        self.env["MOCK_SSH_EXIT"] = "255"
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("reconnecting in")
        self.assertFalse(any(c["name"] == "herdr" for c in self.recorded()))
        t.send(b"\x03")
        t.expect("back at LOCAL control")
        t.send("local\n")
        self.assertEqual(t.process.wait(timeout=4), 0)
        self.assertEqual(self.recorded()[-1]["name"], "fish")

    def test_missing_neutral_config_refuses_attachment(self):
        (self.work / "config/herdr/desktop-client.toml").unlink()
        t = self.term("--remote-attempt", "--remote", "nas", "--remote-keybindings", "server")
        t.expect("Type ATTACH nas")
        t.send("ATTACH nas\n")
        self.assertEqual(t.process.wait(timeout=3), 2)
        self.assertFalse(any(c["name"] == "herdr" for c in self.recorded()))

    def test_reconnect_asks_again_before_exposing_any_pane(self):
        self.env["MOCK_HERDR_EXIT"] = "1"
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("Type ATTACH nas")
        t.send("ATTACH nas\n")
        t.expect("MOCK REMOTE ATTACHED")
        t.output = b""
        t.expect("Type ATTACH nas")
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 1)
        t.send("cancel\n")
        t.expect("Remote view ended")
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 1)


if __name__ == "__main__":
    unittest.main()
