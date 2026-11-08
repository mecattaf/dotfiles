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


MOCK = r"""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ["CALLS"], "a") as f:
 f.write(json.dumps({"name":name,"args":sys.argv[1:],"pid":os.getpid(),"cwd":os.getcwd(),
  "context":{k:v for k,v in os.environ.items() if k.startswith(("HERDR_","DOMICILE_HERDR_"))},
  "home":os.environ["HOME"],"xdg":os.environ["XDG_CONFIG_HOME"],"gdk":os.environ.get("GDK_BACKEND")})+"\n")
if name == "ssh":
 if os.environ.get("MOCK_SSH_EXIT"):
  sys.exit(int(os.environ["MOCK_SSH_EXIT"]))
 # Execute the exact shell text that OpenSSH sends, with a harmless fish double.
 os.execv("/bin/sh", ["sh", "-c", sys.argv[-1]])
if name == "fish":
 print("FRESH SHELL",os.getpid(),flush=True)
"""


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
        for name in ("domicile-apps", "domicile-terminal", "herdr-domicile-client"):
            (self.bin / name).symlink_to(BIN / name)
        self.calls = self.work / "calls"
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', CALLS=str(self.calls),
                        HOME=str(self.work / "home"), XDG_CONFIG_HOME=str(self.work / "config"),
                        HERDR_PANE_ID="foreign:pane", HERDR_ENV="1", HERDR_CONFIG_PATH="foreign.toml",
                        HERDR_UNKNOWN_CONTEXT="foreign", DOMICILE_HERDR_ATTACH="1", TERM="xterm-256color")

    def recorded(self):
        return [json.loads(s) for s in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def run_app(self, *args):
        return subprocess.run([str(self.bin / "domicile-apps"), *args],
                              env=self.env, capture_output=True, text=True)

    def term(self, *args):
        t = Terminal([str(self.bin / "domicile-terminal"), *args], self.env)
        self.addCleanup(t.close)
        return t

    def test_terminal_creates_a_new_kitty_without_remote_control(self):
        for args in ((), ("terminal",)):
            self.assertEqual(self.run_app(*args).returncode, 0)
        calls = self.recorded()
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call["name"], "kitty")
            self.assertEqual(call["args"], ["--class", "domicile-terminal", "--title", "NAS terminal",
                                            "--override", f"shell={self.bin / 'domicile-terminal'}",
                                            "-e", str(self.bin / "domicile-terminal")])

    def test_two_launches_start_independent_nas_shells_without_herdr(self):
        for _ in range(2):
            t = self.term()
            t.expect("FRESH SHELL")
            self.assertEqual(t.process.wait(timeout=3), 0)
        ssh1, fish1, ssh2, fish2 = self.recorded()
        self.assertEqual([r["name"] for r in (ssh1, fish1, ssh2, fish2)], ["ssh", "fish", "ssh", "fish"])
        self.assertNotEqual(fish1["pid"], fish2["pid"])
        for ssh in (ssh1, ssh2):
            argv = ssh["args"]
            for option in ("StrictHostKeyChecking=yes", "Hostname=100.65.85.114", "HostKeyAlias=nas",
                           "ForwardAgent=no", "ControlPath=none", "ClearAllForwardings=yes", "BatchMode=yes"):
                self.assertIn(option, argv)
            self.assertEqual(argv[-2], "nas")
            self.assertIn("-tt", argv)
        for call in self.recorded():
            self.assertEqual(call["context"], {})
            self.assertEqual(call["home"], self.env["HOME"])
            self.assertEqual(call["xdg"], self.env["XDG_CONFIG_HOME"])
        self.assertEqual(fish1["args"], ["--login", "--interactive"])

    def test_remote_cwd_is_literal_data_and_missing_directory_does_not_fallback(self):
        target = self.work / "project ' ; $(touch INJECTED) `touch INJECTED2`"
        target.mkdir()
        t = self.term("--cwd", str(target))
        t.expect("FRESH SHELL")
        self.assertEqual(t.process.wait(timeout=3), 0)
        self.assertEqual(self.recorded()[-1]["cwd"], str(target))
        self.assertFalse((ROOT / "INJECTED").exists())
        self.calls.unlink()
        missing = self.term("--cwd", str(self.work / "missing"))
        self.assertNotEqual(missing.process.wait(timeout=3), 0)
        self.assertEqual([r["name"] for r in self.recorded()], ["ssh"])

    def test_local_shell_needs_no_ssh_or_herdr_configuration(self):
        t = self.term("--local", "--cwd", str(self.work))
        t.expect("FRESH SHELL")
        self.assertEqual(t.process.wait(timeout=3), 0)
        call, = self.recorded()
        self.assertEqual((call["name"], call["args"], call["cwd"], call["context"]),
                         ("fish", ["--login", "--interactive"], str(self.work), {}))

    def test_transport_failure_remains_visible_and_never_reconnects(self):
        self.env["MOCK_SSH_EXIT"] = "255"
        t = self.term()
        t.expect("Press Enter to close")
        self.assertIsNone(t.process.poll())
        self.assertEqual([r["name"] for r in self.recorded()], ["ssh"])
        t.send("\n")
        self.assertEqual(t.process.wait(timeout=3), 255)

    def test_old_attach_arguments_and_invalid_paths_are_refused(self):
        for args in (("--remote-attempt", "--remote", "nas"), ("--cwd", "relative"),
                     ("--cwd", "/tmp/line\nbreak"), ("--cwd", "/tmp/escape\x1b")):
            t = self.term(*args)
            self.assertEqual(t.process.wait(timeout=3), 2)
        self.assertEqual(self.recorded(), [])

    def test_noninteractive_launch_is_refused(self):
        p = subprocess.run([str(self.bin / "domicile-terminal")], env=self.env, capture_output=True)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(self.recorded(), [])

    def test_project_and_rescue_launcher_preserve_argument_boundaries(self):
        path = "/home/tom/project with spaces"
        self.assertEqual(self.run_app("terminal", "--cwd", path).returncode, 0)
        self.assertEqual(self.run_app("rescue", "--cwd", path).returncode, 0)
        nas, local = self.recorded()
        self.assertEqual(nas["args"][-4:], ["-e", str(self.bin / "domicile-terminal"), "--cwd", path])
        self.assertEqual(local["args"][-5:], ["-e", str(self.bin / "domicile-terminal"), "--local", "--cwd", path])

    def test_regular_chrome_and_files_preserve_profiles_and_arguments(self):
        self.run_app("chrome", "https://example.invalid/a b", "--new-window")
        self.run_app("files", "/tmp/a b")
        a, b = self.recorded()
        self.assertEqual(a["args"], ["--ozone-platform=wayland", "https://example.invalid/a b", "--new-window"])
        self.assertEqual(b["args"], ["--new-window", "/tmp/a b"])
        self.assertEqual(b["gdk"], "wayland")
        self.assertEqual(a["xdg"], self.env["XDG_CONFIG_HOME"])

    def test_unknown_action_fails_closed(self):
        self.assertEqual(self.run_app("send-text").returncode, 2)
        self.assertEqual(self.recorded(), [])

    def test_existing_herdr_projectors_keep_their_reconnect_adapter(self):
        config = self.work / "config/herdr/desktop-client.toml"
        config.parent.mkdir(parents=True)
        config.write_text("onboarding = false\n")
        t = Terminal([str(self.bin / "herdr-domicile-client"), "--remote", "nas",
                      "--remote-keybindings", "server"], self.env)
        self.addCleanup(t.close)
        self.assertEqual(t.process.wait(timeout=3), 0)
        call, = self.recorded()
        self.assertEqual((call["name"], call["args"]),
                         ("herdr", ["--remote", "nas", "--remote-keybindings", "server"]))
        self.assertNotIn("HERDR_PANE_ID", call["context"])
        self.assertNotIn("DOMICILE_HERDR_ATTACH", call["context"])

    def test_legacy_adapter_still_refuses_unapproved_attachment(self):
        self.env.pop("DOMICILE_HERDR_ATTACH")
        t = Terminal([str(self.bin / "herdr-domicile-client"), "--remote", "nas",
                      "--remote-keybindings", "server"], self.env)
        self.addCleanup(t.close)
        self.assertEqual(t.process.wait(timeout=3), 2)
        self.assertEqual(self.recorded(), [])


if __name__ == "__main__":
    unittest.main()
