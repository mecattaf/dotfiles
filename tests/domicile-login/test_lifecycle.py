#!/usr/bin/env python3
"""Run through runtime-test; all systemctl/dbus calls below are test doubles."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import unittest

ARGS = None
ROOT = Path(__file__).resolve().parents[2]


def isolated(directory):
    for name in ("home", "config", "state", "cache", "data"):
        (directory / name).mkdir(parents=True, exist_ok=True)
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(directory / "home"),
        "XDG_CONFIG_HOME": str(directory / "config"),
        "XDG_STATE_HOME": str(directory / "state"),
        "XDG_CACHE_HOME": str(directory / "cache"),
        "XDG_DATA_HOME": str(directory / "data"),
        "XDG_RUNTIME_DIR": os.environ["XDG_RUNTIME_DIR"],
        "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
        "SHELL": "/does-not-exist",
    }


class Launcher(unittest.TestCase):
    def setUp(self):
        self.directory = ARGS.receipts / self.id().split(".")[-1]
        self.directory.mkdir(parents=True)
        self.env = isolated(self.directory)
        self.env.update(XDG_VTNR="7", XDG_SESSION_ID="practice-only",
                        CALLS=str(self.directory / "calls.jsonl"))
        self.source = ARGS.session.read_text()
        self.tools = self.directory / "tools"
        self.tools.mkdir()
        stub = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
keys = ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "DOMICILE_SOCK",
        "OZONE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP",
        "XDG_VTNR", "XDG_SESSION_ID", "XDG_DATA_DIRS", "TEST_DECLARED")
with open(os.environ["CALLS"], "a") as out:
    out.write(json.dumps(dict(tool=name, argv=sys.argv[1:], pid=os.getpid(),
                             env={k: os.environ[k] for k in keys if k in os.environ})) + "\\n")
if name == "systemctl":
    if "show-environment" in sys.argv:
        sys.exit(int(os.environ.get("FAIL_BUS", "0")))
    if "is-active" in sys.argv:
        sys.exit(0 if sys.argv[-1] == os.environ.get("ACTIVE_UNIT") else 3)
    sys.exit(int(os.environ.get("FAIL_EXPORT", "0")))
if name == "domicile-recover":
    if os.environ.get("LIVE_DESKTOP"):
        print("A desktop is already listening at practice.sock")
        sys.exit(1)
    sys.exit(int(os.environ.get("FAIL_CONFIG", "0")))
if name == "dbus-update-activation-environment":
    sys.exit(int(os.environ.get("FAIL_DBUS", "0")))
if name == "systemd-cat":
    os.execv(sys.argv[2], sys.argv[2:])
"""
        for name in ("systemctl", "domicile-recover", "dbus-update-activation-environment",
                     "systemd-cat", "domicile"):
            path = self.tools / name
            path.write_text(stub)
            path.chmod(0o755)
            self.source, count = re.subn(
                r"/nix/store/[^/\s]+/bin/" + name + r"(?=[\s\\])",
                str(path), self.source)
            self.assertGreater(count, 0, name)
        self.source += "\n"
        self.script = self.directory / "session"
        self.script.write_text(self.source)
        self.script.chmod(0o755)

    def launch(self, expected=0, arguments=()):
        process = subprocess.Popen([str(self.script), *arguments], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        output, _ = process.communicate(timeout=20)
        (self.directory / "output.log").write_text(output)
        self.assertEqual(process.returncode, expected, output)
        path = self.directory / "calls.jsonl"
        calls = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return process.pid, calls, output

    def test_direct_exec_and_stale_environment(self):
        for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "DOMICILE_SOCK",
                     "OZONE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP"):
            self.env[name] = "stale"
        pid, calls, _ = self.launch()
        final = calls[-1]
        self.assertEqual(final["tool"], "domicile")
        self.assertEqual(final["pid"], pid)
        self.assertEqual(final["argv"], [])
        self.assertEqual(final["env"]["XDG_VTNR"], "7")
        for name in ("SWAYSOCK", "I3SOCK", "WAYLAND_DISPLAY", "DISPLAY", "DOMICILE_SOCK",
                     "OZONE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP"):
            self.assertNotIn(name, final["env"])
        self.assertTrue(final["env"]["XDG_DATA_DIRS"])
        self.assertLess(next(i for i, c in enumerate(calls) if c["tool"] == "domicile-recover"),
                        next(i for i, c in enumerate(calls) if "unset-environment" in c["argv"]))
        exports = next(c for c in calls if c["tool"] == "dbus-update-activation-environment")
        self.assertIn("XDG_VTNR", exports["argv"])
        self.assertNotIn("DOMICILE_SOCK", exports["argv"])

    def test_missing_vt_refused_before_bus(self):
        self.env.pop("XDG_VTNR")
        _, calls, output = self.launch(1)
        self.assertEqual(calls, [])
        self.assertIn("physical console login", output)
        self.assertIn("Ctrl+Alt+F2", output)

    def test_missing_session_refused(self):
        self.env.pop("XDG_SESSION_ID")
        _, calls, _ = self.launch(1)
        self.assertEqual(calls, [])

    def test_bus_failure_refused(self):
        self.env["FAIL_BUS"] = "1"
        _, calls, output = self.launch(1)
        self.assertEqual(len(calls), 1)
        self.assertIn("checking the physical login and user bus", output)

    def test_sway_refused(self):
        self.env["ACTIVE_UNIT"] = "sway-physical.service"
        _, calls, output = self.launch(1)
        self.assertNotIn("domicile-recover", [c["tool"] for c in calls])
        self.assertIn("sway-physical.service", output)

    def test_existing_domicile_refused(self):
        self.env["LIVE_DESKTOP"] = "1"
        _, calls, output = self.launch(1)
        self.assertFalse(any("unset-environment" in c["argv"] for c in calls))
        self.assertIn("practice.sock", output)

    def test_bad_config_does_not_mutate_manager(self):
        self.env["FAIL_CONFIG"] = "1"
        _, calls, output = self.launch(1)
        self.assertFalse(any("unset-environment" in c["argv"] for c in calls))
        self.assertIn("validating the startup config", output)

    def test_failed_export_does_not_start_launcher(self):
        self.env["FAIL_EXPORT"] = "1"
        _, calls, output = self.launch(1)
        self.assertNotIn("domicile", [c["tool"] for c in calls])
        self.assertIn("exporting the login environment", output)

    def test_failed_dbus_import_does_not_start_launcher(self):
        self.env["FAIL_DBUS"] = "1"
        _, calls, _ = self.launch(1)
        self.assertNotIn("domicile", [c["tool"] for c in calls])

    def test_login_shell_once_preserves_pid(self):
        shell = self.directory / "login-shell"
        shell.write_text("#!/usr/bin/env bash\nprintf 'login\\n' >> " +
                         shlex.quote(str(self.directory / "login-count")) +
                         '\nexec bash -c "$3"\n')
        shell.chmod(0o755)
        shells = self.directory / "shells"
        shells.write_text(str(shell) + "\n")
        self.script.write_text(self.source.replace("/etc/shells", shlex.quote(str(shells))))
        self.env["SHELL"] = str(shell)
        pid, calls, _ = self.launch()
        self.assertEqual((self.directory / "login-count").read_text(), "login\n")
        self.assertEqual(calls[-1]["pid"], pid)

    def test_arguments_refused(self):
        _, calls, _ = self.launch(2, ("--config", "surprise"))
        self.assertEqual(calls, [])


class Config(unittest.TestCase):
    def setUp(self):
        self.directory = ARGS.receipts / self.id().split(".")[-1]
        self.directory.mkdir(parents=True)
        self.env = isolated(self.directory)
        self.config = self.directory / "config/domicile"
        self.config.mkdir()

    def check(self, expected):
        result = subprocess.run([str(ARGS.recovery), "check"], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        (self.directory / "output.log").write_text(result.stdout)
        self.assertEqual(result.returncode, expected, result.stdout)
        logs = list((self.directory / "state/domicile-session").glob("*.log"))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)
        self.assertIn("PASS:" if expected == 0 else "FAIL:", logs[0].read_text())
        return result.stdout

    def candidate(self):
        return (ROOT / "home/dot_config/domicile/domicile.tsx").read_text()

    def test_current_config(self):
        (self.config / "domicile.tsx").write_text(self.candidate())
        self.check(0)

    def test_syntax_error(self):
        (self.config / "domicile.tsx").write_text("export const Shell = ( ;")
        self.assertIn("Unexpected", self.check(1))

    def test_semantic_chord_guard(self):
        text = self.candidate().replace("  ...kept,", '  ...kept,\n  "Shift+Meta+Return": exec("false"),')
        (self.config / "domicile.tsx").write_text(text)
        self.assertIn("this mode already binds", self.check(1))

    def test_unknown_section(self):
        (self.config / "domicile.tsx").write_text(
            self.candidate() + "\nexport const output = { nosuchkey: true };\n")
        self.assertIn("nosuchkey", self.check(1))

    def test_missing_import(self):
        (self.config / "domicile.tsx").write_text('import "does-not-exist-for-login-practice";')
        self.check(1)

    def test_json_config(self):
        (self.config / "domicile.json").write_text('{"shell":"@domicile-desktop/manganese"}')
        self.check(0)

    def test_json_missing_shell(self):
        (self.config / "domicile.json").write_text("{}")
        self.assertIn("must name its shell", self.check(1))

    def test_two_configs(self):
        (self.config / "domicile.tsx").write_text(self.candidate())
        (self.config / "domicile.json").write_text("{}")
        self.assertIn("found 2", self.check(1))

    def test_no_config(self):
        self.assertIn("found 0", self.check(1))

    def test_broken_symlink(self):
        (self.config / "domicile.tsx").symlink_to(self.config / "missing")
        self.assertIn("not a regular file", self.check(1))

    def test_login_check_refuses_live_socket(self):
        import socket
        path = Path(self.env["XDG_RUNTIME_DIR"]) / f"domicile-ipc.{os.getpid()}.sock"
        try:
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(str(path))
                listener.listen()
                result = subprocess.run([str(ARGS.recovery), "login-check"], env=self.env,
                                        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 1)
            self.assertIn("already listening", result.stdout)
        finally:
            path.unlink(missing_ok=True)

    def test_login_check_leaves_dead_socket(self):
        import socket
        path = Path(self.env["XDG_RUNTIME_DIR"]) / f"domicile-ipc.{os.getpid()}.sock"
        try:
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(str(path))
            (self.config / "domicile.tsx").write_text(self.candidate())
            result = subprocess.run([str(ARGS.recovery), "login-check"], env=self.env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertTrue(path.exists())
        finally:
            path.unlink(missing_ok=True)

    def test_exit_requires_explicit_desktop(self):
        result = subprocess.run([str(ARGS.recovery), "exit"], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("No desktop selected", result.stdout)

    def test_exit_refuses_non_domicile_peer(self):
        import socket
        listener = socket.socket(socket.AF_UNIX)
        path = self.directory / "unrelated.sock"
        with listener:
            listener.bind(str(path))
            listener.listen()
            result = subprocess.run([str(ARGS.recovery), "--socket", str(path), "exit"],
                                    env=self.env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("not this installation", result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--recovery", type=Path, required=True)
    parser.add_argument("--receipts", type=Path, required=True)
    ARGS, extra = parser.parse_known_args()
    if Path("/proc/1/comm").read_text().strip() != "bwrap":
        sys.exit("Use ~/.local/bin/runtime-test -- python3 tests/domicile-login/test_lifecycle.py ...")
    ARGS.receipts = ARGS.receipts.resolve()
    ARGS.receipts.mkdir(parents=True, exist_ok=True)
    unittest.main(argv=[sys.argv[0], *extra], verbosity=2)
