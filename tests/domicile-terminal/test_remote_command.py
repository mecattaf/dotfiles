"""domicile-terminal's ssh command, run locally against fake NAS programs.

No ssh is started: the remote command string is handed to a local bash, the
way sshd hands it to the NAS login shell (bash), with HOME and PATH pointing
at fakes in a temporary directory.
"""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

BIN = Path(os.environ.get("DOTFILES_BIN", Path(__file__).resolve().parents[2] / "home/dot_local/bin"))

# The pinned transport on main (5c84d256), byte for byte.
PINNED = ["ssh", "-tt", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
          "-o", "Hostname=100.65.85.114", "-o", "HostKeyAlias=nas",
          "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
          "-o", "ControlMaster=no", "-o", "ControlPath=none",
          "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
          "-o", "ServerAliveCountMax=3", "nas"]


def main_remote(cwd):
    # main's remote command (5c84d256 ssh_argv), reproduced here independently.
    shell = shlex.join(["env", "-u", "HERDR_ENV", "-u", "HERDR_SESSION",
                        "-u", "HERDR_WORKSPACE_ID", "-u", "HERDR_PANE_ID",
                        "-u", "HERDR_SOCKET_PATH", "fish", "--login", "--interactive"])
    return (f"cd -- {shlex.quote(cwd)} && " if cwd is not None else "") + "exec " + shell


def load():
    loader = importlib.machinery.SourceFileLoader("domicile_terminal", str(BIN / "domicile-terminal"))
    spec = importlib.util.spec_from_loader("domicile_terminal", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


RECORD = r'''
import json, os, sys
from pathlib import Path
out = Path(os.environ["FIXTURE"]) / (Path(sys.argv[0]).name + ".json")
with open(out, "a") as handle:
    handle.write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
                             "env": sorted(os.environ)}) + "\n")
'''

AWKWARD = "/tmp/x/it's a $(touch PWNED) `touch PWNED` dir; \"q\" & *"


class RemoteCommand(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dt = load()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dterm")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        for directory in (self.home / ".local/bin", self.bin):
            directory.mkdir(parents=True)
        self.awkward = str(self.root) + AWKWARD
        os.makedirs(self.awkward)

    def fake(self, path):
        path.write_text("#!" + sys.executable + "\n" + RECORD)
        path.chmod(0o755)

    def run_remote(self, remote):
        # sshd runs the command with the login shell: `bash -c <remote>`.
        env = {"HOME": str(self.home), "FIXTURE": str(self.root),
               "PATH": f"{self.bin}:{os.environ.get('PATH', '/run/current-system/sw/bin:/usr/bin:/bin')}",
               "HERDR_ENV": "1"}
        return subprocess.run(["bash", "-c", remote], env=env, cwd=self.root, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=20)

    def records(self, name):
        path = self.root / (name + ".json")
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_the_ssh_options_are_the_pinned_list(self):
        for kwargs in ({}, {"plain": True}, {"version": "0.50.0"}, {"seat": "rehearsal"}):
            argv = self.dt.ssh_argv("/home/tom", **kwargs)
            self.assertEqual(argv[:-1], PINNED, kwargs)
        self.assertEqual(self.dt.ssh_argv(None)[:-1], PINNED)

    def test_plain_is_mains_command(self):
        for cwd in (None, "/home/tom", self.awkward):
            self.assertEqual(self.dt.ssh_argv(cwd, plain=True)[-1], main_remote(cwd))

    def test_the_remote_script_parses(self):
        for cwd in (None, "/home/tom", self.awkward):
            remote = self.dt.ssh_argv(cwd, version="0.50.0")[-1]
            words = shlex.split(remote)
            self.assertEqual(words[:3], ["exec", "sh", "-c"])
            self.assertEqual(len(words), 4)
            script = self.root / "script.sh"
            script.write_text(words[3])
            for shell in ("sh", "bash"):
                checked = subprocess.run([shell, "-n", str(script)], capture_output=True, text=True)
                self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_the_station_gets_the_cwd_as_data(self):
        self.fake(self.home / ".local/bin/hc-station")
        result = self.run_remote(self.dt.ssh_argv(self.awkward, version="0.50.0")[-1])
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.records("hc-station")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["argv"], ["new", "--label", "seat=zenbook", "--kitty-version", "0.50.0",
                                            "--cwd", self.awkward])
        self.assertFalse((self.root / "PWNED").exists())
        self.assertFalse(Path(self.awkward, "PWNED").exists())

    def test_no_cwd_no_version(self):
        self.fake(self.home / ".local/bin/hc-station")
        self.assertEqual(self.run_remote(self.dt.ssh_argv(None)[-1]).returncode, 0)
        self.assertEqual(self.records("hc-station")[0]["argv"], ["new", "--label", "seat=zenbook"])

    def test_the_seat_label(self):
        self.fake(self.home / ".local/bin/hc-station")
        self.run_remote(self.dt.ssh_argv(None, seat="rehearsal")[-1])
        self.assertEqual(self.records("hc-station")[0]["argv"], ["new", "--label", "seat=rehearsal"])

    def test_a_bad_version_is_not_sent(self):
        self.fake(self.home / ".local/bin/hc-station")
        self.run_remote(self.dt.ssh_argv(None, version="1; reboot")[-1])
        self.assertEqual(self.records("hc-station")[0]["argv"], ["new", "--label", "seat=zenbook"])

    def test_missing_station_runs_todays_fish_with_a_banner(self):
        self.fake(self.bin / "fish")
        result = self.run_remote(self.dt.ssh_argv(self.awkward)[-1])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("domicile-terminal: hc-station is missing on the NAS: plain fish, not persistent",
                      result.stderr)
        calls = self.records("fish")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["argv"], ["--login", "--interactive"])
        self.assertEqual(calls[0]["cwd"], self.awkward)
        self.assertNotIn("HERDR_ENV", calls[0]["env"])
        self.assertFalse((self.root / "PWNED").exists())

    def test_a_station_that_is_not_executable_counts_as_missing(self):
        self.fake(self.home / ".local/bin/hc-station")
        (self.home / ".local/bin/hc-station").chmod(0o644)
        self.fake(self.bin / "fish")
        result = self.run_remote(self.dt.ssh_argv(None)[-1])
        self.assertIn("hc-station is missing", result.stderr)
        self.assertEqual(len(self.records("fish")), 1)

    def test_attach_does_not_create_or_fall_back_to_a_shell(self):
        self.fake(self.home / ".local/bin/hc-station")
        for address in ("t7", "writing", "nas/t7"):
            result = self.run_remote(self.dt.ssh_argv(None, address=address)[-1])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.records("hc-station")[-1]["argv"], ["attach", address])
        (self.home / ".local/bin/hc-station").unlink()
        self.fake(self.bin / "fish")
        result = self.run_remote(self.dt.ssh_argv(None, address="t7")[-1])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.records("fish"), [])

    def test_attach_remote_failures_are_returned_without_new(self):
        station = self.home / ".local/bin/hc-station"
        station.write_text("#!/bin/sh\nexit 42\n")
        station.chmod(0o755)
        self.fake(self.bin / "fish")
        result = self.run_remote(self.dt.ssh_argv(None, address="t7")[-1])
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.records("fish"), [])

    def test_kitty_owns_multiplexing_but_host_checks_are_unchanged(self):
        argv = self.dt.ssh_argv(None, kitty=True)
        self.assertEqual(argv[:3], ["kitten", "ssh", "-tt"])
        self.assertEqual(argv[2:-1], PINNED[1:14] + PINNED[18:])
        self.assertIn("StrictHostKeyChecking=yes", argv)
        self.assertIn("Hostname=100.65.85.114", argv)
        self.assertIn("HostKeyAlias=nas", argv)
        self.assertNotIn("ControlMaster=no", argv)
        self.assertNotIn("ControlPath=none", argv)

    def test_kitty_version(self):
        kitty = self.bin / "kitty"
        path = os.environ.get("PATH", "")
        try:
            os.environ["PATH"] = f"{self.bin}"
            self.assertIsNone(self.dt.kitty_version())
            for printed, expected in (("kitty 0.50.0 created by Kovid Goyal", "0.50.0"),
                                      ("kitty 0.50.0-dev created by", None), ("garbage", None), ("", None)):
                kitty.write_text(f"#!/bin/sh\nprintf '%s\\n' {shlex.quote(printed)}\n")
                kitty.chmod(0o755)
                self.assertEqual(self.dt.kitty_version(), expected, printed)
        finally:
            os.environ["PATH"] = path

    def test_arguments(self):
        self.assertEqual(self.dt.parse_args([]).seat, "zenbook")
        self.assertTrue(self.dt.parse_args(["--plain", "--cwd", "/x"]).plain)
        self.assertEqual(self.dt.parse_args(["--attach", "t7"]).attach, "t7")
        for bad in (["--cwd", "relative"], ["--seat", "Bad Seat"], ["--local", "--plain"],
                    ["--attach", "t7", "--cwd", "/tmp"], ["--plain", "--attach", "t7"],
                    ["--local", "--attach", "t7"], ["--attach", "t7; touch PWNED"],
                    ["--attach", "$(touch PWNED)"], ["--attach", "t7\nnew"],
                    ["--attach", "a/b/c"], ["--attach=-t7"]):
            with self.assertRaises(SystemExit):
                with open(os.devnull, "w") as quiet:
                    stderr, sys.stderr = sys.stderr, quiet
                    try:
                        self.dt.parse_args(bad)
                    finally:
                        sys.stderr = stderr


if __name__ == "__main__":
    unittest.main()
