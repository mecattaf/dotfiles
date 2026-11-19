"""domicile-apps and the NAS workflow path open persistent sessions, and can
let the caller choose the session id. Stand-ins only: a fake kitty, a fake
kitty-persist, a fake Domicile binary and a fake ssh."""
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import support  # noqa: E402

SID = "0f3b2a11-3b1c-4d2e-9f00-0123456789ab"
terminal_open = support.load(support.BIN / "domicile-terminal-open", "domicile_terminal_open")
open_terminal = support.load(support.BIN / "domicile-open-terminal", "domicile_open_terminal")


class Apps(unittest.TestCase):
    """domicile-apps as a process. It resolves domicile-persist next to
    itself, so both are copied into one directory with the fakes on PATH."""

    def setUp(self):
        self.fake = support.Fakes()
        self.addCleanup(self.fake.close)
        self.bin = self.fake.root / "bin"
        self.bin.mkdir()
        for name in ("domicile-apps", "domicile-persist", "domicile-terminal"):
            shutil.copy(support.BIN / name, self.bin / name)
        persist = self.bin / "domicile-persist"
        persist.write_text(f"#!{sys.executable}\n" + persist.read_text().split("\n", 1)[1])
        shutil.copy(self.fake.kitty, self.bin / "kitty")

    def run_apps(self, *args):
        env = self.fake.env(PATH=f"{self.bin}:{os.environ.get('PATH', '')}")
        return subprocess.run([shutil.which("bash") or "/bin/sh", str(self.bin / "domicile-apps"), *args],
                              env=env, capture_output=True, text=True, timeout=60)

    def test_terminal_opens_a_persistent_session(self):
        result = self.run_apps("terminal", "--cwd", "/srv/project")
        self.assertEqual(result.returncode, 0, result.stderr)
        [window] = self.fake.windows()
        argv = window["argv"]
        self.assertTrue(argv[1].startswith("kitty-persist-"))
        sid = argv[1].removeprefix("kitty-persist-")
        self.assertEqual(argv[argv.index("-e") + 1], str((self.bin / "domicile-persist").resolve()))
        self.assertEqual(argv[argv.index("-e") + 2:], ["new", "--id", sid, "--cwd", "/srv/project"])

    def test_bare_call_is_a_terminal(self):
        self.assertEqual(self.run_apps().returncode, 0)
        self.assertTrue(self.fake.windows()[0]["argv"][1].startswith("kitty-persist-"))

    def test_terminal_with_a_chosen_id_and_attach(self):
        self.assertEqual(self.run_apps("terminal", "--id", SID, "--cwd", "/srv").returncode, 0)
        self.assertEqual(self.run_apps("attach", SID).returncode, 0)
        first, second = self.fake.windows()
        self.assertEqual(first["argv"][1], "kitty-persist-" + SID)
        self.assertEqual(second["argv"][second["argv"].index("-e") + 2:], ["attach", SID])

    def test_restore_dry_run(self):
        self.fake.listing([support.record(SID, labels={"opener": "domicile"})])
        result = self.run_apps("restore", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["open"], [SID])

    def test_nas_shell_keeps_the_former_plain_terminal(self):
        self.assertEqual(self.run_apps("nas-shell", "--cwd", "/srv").returncode, 0)
        argv = self.fake.windows()[0]["argv"]
        self.assertEqual(argv[:4], ["--class", "domicile-terminal", "--title", "NAS terminal"])
        self.assertEqual(argv[-3:], [str(self.bin / "domicile-terminal"), "--cwd", "/srv"])

    def test_unknown_word_is_refused(self):
        self.assertEqual(self.run_apps("persist").returncode, 2)


class DesktopHelper(unittest.TestCase):
    """domicile-terminal-open, run on the desktop by the NAS workflow."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        root = Path(self.dir.name)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        runtime.chmod(0o700)
        self.listener = socket.socket(socket.AF_UNIX)
        self.addCleanup(self.listener.close)
        path = runtime / "domicile-ipc.test.sock"
        self.listener.bind(str(path))
        path.chmod(0o600)
        self.listener.listen(4)
        self.log = root / "domicile.jsonl"
        domicile = support.executable(root / "domicile", (
            "import json, sys\n"
            f"open({str(self.log)!r}, 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"))
        self.config = root / "client.json"
        self.config.write_text(json.dumps({"desktopId": "zenbook", "domicileBinary": str(domicile),
                                           "runtimeDirectory": str(runtime)}))
        self.config.chmod(0o600)

    def sent(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_without_a_session_the_call_is_unchanged(self):
        reply = terminal_open.launch("zenbook", "/srv/project", self.config)
        self.assertEqual(reply, {"ok": True, "desktop": "zenbook", "status": "launch-queued",
                                 "dshOwnedPty": False, "observedWindow": None})
        self.assertEqual(self.sent(), [["send-shell", "exec", "domicile-apps", "terminal", "--cwd", "/srv/project"]])

    def test_a_chosen_session_is_passed_and_named(self):
        reply = terminal_open.launch("zenbook", "/srv/project", self.config, SID)
        self.assertEqual(reply["session"], SID)
        self.assertEqual(self.sent(), [["send-shell", "exec", "domicile-apps", "terminal", "--id", SID,
                                        "--cwd", "/srv/project"]])

    def test_a_malformed_session_is_refused(self):
        result = subprocess.run([sys.executable, str(support.BIN / "domicile-terminal-open"), "zenbook",
                                 "--cwd", "/srv", "--session", SID.upper(), "--config", str(self.config)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())


class NasSide(unittest.TestCase):
    """domicile-open-terminal on NAS, with a fake ssh on PATH."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.root = Path(self.dir.name)
        self.registry = self.root / "desktops.json"
        self.registry.write_text(json.dumps({"desktops": {"zenbook": {
            "tailnetIp": "100.64.0.9", "sshAlias": "zenbook", "hostKeyAlias": "zenbook",
            "terminalLauncher": "/home/u/.local/bin/domicile-terminal-open"}}}))

    def fake_ssh(self, reply):
        support.executable(self.root / "ssh", (
            "import json, sys\n"
            f"open({str(self.root / 'ssh.jsonl')!r}, 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"
            f"print({json.dumps(json.dumps(reply))})\n"))

    def run_nas(self, *extra):
        env = dict(os.environ, PATH=f"{self.root}:{os.environ.get('PATH', '')}")
        return subprocess.run([sys.executable, str(support.BIN / "domicile-open-terminal"), "--registry",
                               str(self.registry), "--desktop", "zenbook", "--cwd", "/srv/project", *extra],
                              env=env, capture_output=True, text=True, timeout=30)

    def test_command_carries_the_session(self):
        argv = open_terminal.command(json.loads(self.registry.read_text()), "zenbook", "/srv/project", SID)
        self.assertEqual(shlex.split(argv[-1]), ["/home/u/.local/bin/domicile-terminal-open", "zenbook",
                                                 "--cwd", "/srv/project", "--session", SID])
        plain = open_terminal.command(json.loads(self.registry.read_text()), "zenbook", "/srv/project")
        self.assertNotIn("--session", plain[-1])

    def test_reply_must_name_the_chosen_session(self):
        base = {"ok": True, "desktop": "zenbook", "status": "launch-queued", "dshOwnedPty": False,
                "observedWindow": None}
        self.fake_ssh(dict(base, session=SID))
        result = self.run_nas("--session", SID)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["session"], SID)
        self.fake_ssh(base)
        self.assertEqual(self.run_nas("--session", SID).returncode, 2)
        self.assertEqual(self.run_nas().returncode, 0)

    def test_malformed_session_never_reaches_ssh(self):
        self.fake_ssh({})
        self.assertEqual(self.run_nas("--session", "not-a-uuid").returncode, 2)
        self.assertFalse((self.root / "ssh.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
