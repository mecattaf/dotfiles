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
  "context":os.environ.get("HERDR_PANE_ID"),"gdk":os.environ.get("GDK_BACKEND"),
  "home":os.environ.get("HOME"),"xdg_config_home":os.environ.get("XDG_CONFIG_HOME"),
  "attach_intent":os.environ.get("DOMICILE_HERDR_ATTACH"),"reconnect":os.environ.get("HERDR_PROJECTOR_RECONNECT")})+"\\n")
if name=="herdr":
 if os.environ.get("READ_HERDR_INPUT"):
  import select, termios, tty
  old=termios.tcgetattr(0)
  tty.setraw(0)
  data=os.read(0,4096) if select.select([0],[],[],0.3)[0] else b""
  termios.tcsetattr(0,termios.TCSANOW,old)
  Path(os.environ["CALLS"]+".input").write_bytes(data)
 print("MOCK REMOTE ATTACHED",flush=True)
 sys.exit(int(os.environ.get("MOCK_HERDR_EXIT","0")))
elif name=="ssh":
 import time
 time.sleep(float(os.environ.get("MOCK_SSH_DELAY","0")))
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
                        CALLS=str(self.calls), TMPDIR=str(self.work), HOME=str(self.work / "ordinary-home"),
                        XDG_CONFIG_HOME=str(self.work / "config"), TERM="xterm-256color",
                        HERDR_PANE_ID="foreign:pane", HERDR_ENV="1")
        self.env.pop("DOMICILE_DESKTOP_CLIENT_CONFIG", None)

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
        self.assertEqual(call["args"][call["args"].index("--title")+1], "Terminal control")
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

    def test_piped_remote_selection_is_refused(self):
        p = subprocess.run([str(self.bin / "domicile-terminal"), "--remote-attempt",
                            "--remote", "nas", "--remote-keybindings", "server"],
                            input="nas\n", text=True, env=self.env, capture_output=True)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(self.recorded(), [])

    def test_adapter_requires_menu_selection_and_rejects_other_targets(self):
        t = self.term("--remote-attempt", "--remote", "nas", "--remote-keybindings", "server")
        self.assertEqual(t.process.wait(timeout=3), 2)
        self.env["DOMICILE_HERDR_ATTACH"] = "1"
        u = self.term("--remote-attempt", "--remote", "other", "--remote-keybindings", "server")
        self.assertEqual(u.process.wait(timeout=3), 2)
        self.assertEqual(self.recorded(), [])

    def test_one_selection_keeps_transport_and_neutral_config(self):
        t = self.term()
        t.expect("EXISTING workspace/pane, which may be Claude.")
        t.expect("local / nas / quit >")
        self.assertEqual(self.recorded(), [])
        t.send("nas\n")
        t.expect("Remote view ended")
        self.assertNotIn(b"ATTACH nas", t.output)
        ssh, remote = self.recorded()
        self.assertIn("systemctl --user is-active", ssh["args"][-1])
        self.assertEqual(remote["args"], ["--remote", "nas", "--remote-keybindings", "server"])
        self.assertEqual(remote["config"], str(self.work / "config/herdr/desktop-client.toml"))
        self.assertIsNone(remote["context"])
        self.assertIsNone(remote["attach_intent"])
        self.assertEqual(remote["reconnect"], "0")
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_queued_lines_are_discarded_without_reattachment(self):
        self.env["READ_HERDR_INPUT"] = "1"
        t = self.term()
        t.expect("local / nas / quit >")
        t.send(b"nas\nSTRAY-ORDINARY-KEYS\nnas\n")
        t.expect("back at LOCAL control")
        self.assertEqual(Path(str(self.calls)+".input").read_bytes(), b"")
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 1)
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_keys_typed_during_preflight_do_not_reach_remote(self):
        self.env.update(READ_HERDR_INPUT="1", MOCK_SSH_DELAY="0.3")
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("Checking NAS.")
        t.send("TYPED-WHILE-CONNECTING\n")
        t.expect("back at LOCAL control")
        self.assertEqual(Path(str(self.calls)+".input").read_bytes(), b"")
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_unreachable_nas_returns_to_local_without_retries(self):
        self.env["MOCK_SSH_EXIT"] = "255"
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("back at LOCAL control")
        self.assertEqual([c["name"] for c in self.recorded()], ["ssh"])
        t.send("local\n")
        self.assertEqual(t.process.wait(timeout=4), 0)
        self.assertEqual(self.recorded()[-1]["name"], "fish")

    def test_missing_neutral_config_refuses_attachment(self):
        (self.work / "config/herdr/desktop-client.toml").unlink()
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("desktop client config must be a readable regular TOML file")
        t.expect("staying at LOCAL control.")
        self.assertEqual(self.recorded(), [])
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_explicit_config_preserves_xdg_home_and_browser_profile(self):
        explicit = self.work / "candidate ; $HOME [test].toml"
        content = 'onboarding = false\n[ui]\nprompt_new_workspace_name = true\n'
        explicit.write_text(content)
        default = self.work / "config/herdr/desktop-client.toml"
        default.unlink()  # the console-trial client has no installed neutral config
        self.env["DOMICILE_DESKTOP_CLIENT_CONFIG"] = str(explicit)
        t = self.term()
        t.expect("local / nas / quit >")
        self.assertEqual(self.recorded(), [])
        t.send("nas\n")
        t.expect("back at LOCAL control")
        ssh, remote = self.recorded()
        self.assertEqual(remote["config"], str(explicit))
        self.assertEqual(remote["home"], self.env["HOME"])
        self.assertEqual(remote["xdg_config_home"], self.env["XDG_CONFIG_HOME"])
        self.assertEqual(remote["args"], ["--remote", "nas", "--remote-keybindings", "server"])
        self.assertEqual(explicit.read_text(), content)
        self.assertFalse(default.exists())
        self.run_app("chrome", "https://example.invalid/fixture")
        chrome = self.recorded()[-1]
        self.assertEqual(chrome["args"], ["--ozone-platform=wayland", "https://example.invalid/fixture"])
        self.assertEqual(chrome["home"], self.env["HOME"])
        self.assertEqual(chrome["xdg_config_home"], self.env["XDG_CONFIG_HOME"])
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_invalid_explicit_configs_stay_local_without_fallback(self):
        malformed = self.work / "malformed.toml"
        malformed.write_text("[ui\n")
        invalid_utf8 = self.work / "invalid-utf8.toml"
        invalid_utf8.write_bytes(b"\xff")
        unreadable = self.work / "unreadable.toml"
        unreadable.write_text("onboarding = false\n")
        unreadable.chmod(0)
        cases = {
            "empty": "", "relative": "candidate.toml",
            "missing": str(self.work / "missing.toml"), "directory": str(self.work),
            "unreadable": str(unreadable), "malformed": str(malformed),
            "invalid_utf8": str(invalid_utf8),
        }
        for name, value in cases.items():
            with self.subTest(name=name):
                self.env["DOMICILE_DESKTOP_CLIENT_CONFIG"] = value
                t = self.term()
                t.expect("local / nas / quit >")
                t.send("nas\n")
                t.expect("staying at LOCAL control.")
                self.assertIsNone(t.process.poll())
                self.assertEqual(self.recorded(), [])
                t.send("quit\n")
                self.assertEqual(t.process.wait(timeout=3), 0)

    def test_lost_link_requires_a_new_local_selection(self):
        self.env["MOCK_HERDR_EXIT"] = "1"
        t = self.term()
        t.expect("local / nas / quit >")
        t.send("nas\n")
        t.expect("back at LOCAL control")
        self.assertNotIn(b"reconnecting in", t.output)
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 1)
        t.send("ordinary keys after a lost link\n")
        t.expect("No action.")
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 1)
        t.output = b""
        t.send("nas\n")
        t.expect("back at LOCAL control")
        self.assertEqual(sum(c["name"] == "herdr" for c in self.recorded()), 2)
        t.send("quit\n")
        self.assertEqual(t.process.wait(timeout=3), 0)

    def test_existing_projector_callers_still_reconnect_by_default(self):
        env = self.env | {"MOCK_HERDR_EXIT": "1", "HERDR_BIN": "herdr"}
        env.pop("HERDR_PROJECTOR_RECONNECT", None)
        t = Terminal([str(self.bin / "herdr-projector")], env)
        self.addCleanup(t.close)
        t.expect("reconnecting in")
        for _ in range(50):
            t.read()
            if sum(c["name"] == "herdr" for c in self.recorded()) >= 2:
                break
        self.assertGreaterEqual(sum(c["name"] == "herdr" for c in self.recorded()), 2)

    def test_invalid_reconnect_policy_is_rejected_before_ssh(self):
        p = subprocess.run(["bash", str(BIN / "herdr-projector")],
                           env=self.env | {"HERDR_PROJECTOR_RECONNECT": "bad"},
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(self.recorded(), [])


if __name__ == "__main__":
    unittest.main()
