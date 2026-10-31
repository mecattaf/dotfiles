"""Data-only XDG parsing and real rsync transfers through a private SSH fixture."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


SCRIPT = Path(os.environ.get("DOWNLOADS_MIRROR_SCRIPT", Path(__file__).resolve().parents[2] / "pkgs/downloads-mirror/downloads-mirror.py"))
BINARY = os.environ.get("DOWNLOADS_MIRROR_BINARY")
FIXTURE_BINARY = os.environ.get("DOWNLOADS_MIRROR_FIXTURE_BINARY")
loader = importlib.machinery.SourceFileLoader("downloads_mirror", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
mirror = importlib.util.module_from_spec(spec)
loader.exec_module(mirror)


class XDG(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / "config"
        self.config.mkdir()

    def resolve(self, value):
        (self.config / "user-dirs.dirs").write_text(value)
        return mirror.download_directory(self.home, self.config)

    def test_home_expansion_and_spaces(self):
        self.assertEqual(self.resolve('XDG_DOWNLOAD_DIR="$HOME/Browser files"'), self.home / "Browser files")
        self.assertEqual(self.resolve('XDG_DOWNLOAD_DIR="${HOME}/Browser files" # location'), self.home / "Browser files")

    def test_executable_text_is_literal_data(self):
        marker = self.home / "executed"
        path = self.resolve('XDG_DOWNLOAD_DIR="$HOME/$(touch ' + str(marker) + ')"')
        self.assertIn("$(touch ", str(path))
        self.assertFalse(marker.exists())

    def test_quotes_and_backslashes(self):
        self.assertEqual(self.resolve(r'XDG_DOWNLOAD_DIR="$HOME/a\"quote \\ dollar\$"'), self.home / 'a"quote \\ dollar$')

    def test_refuse_missing_disabled_root_relative_and_control_paths(self):
        for value in ('# absent', 'XDG_DOWNLOAD_DIR="$HOME"', 'XDG_DOWNLOAD_DIR="/"',
                      'XDG_DOWNLOAD_DIR="relative"', 'XDG_DOWNLOAD_DIR="$HOME/a/.."',
                      'XDG_DOWNLOAD_DIR="/some\tpath"'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.resolve(value)


@unittest.skipUnless(shutil.which("rsync"), "real rsync is required")
class Transfers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "receiver"
        self.source = self.root / "source with spaces ' [x]"
        self.destination = self.home / "configured location"
        self.config = self.home / ".config"
        self.bin = self.root / "bin"
        for path in (self.home, self.source, self.destination, self.config, self.bin):
            path.mkdir(parents=True, exist_ok=True)
        (self.config / "user-dirs.dirs").write_text(f'XDG_DOWNLOAD_DIR="{self.destination}"\n')
        self.rsync = shutil.which("rsync")
        ssh = self.bin / "ssh"
        ssh.write_text(f"#!{sys.executable}\n" + r'''
import json,os,sys
args=sys.argv[1:]
if os.environ.get("FIXTURE_OFFLINE"): sys.exit(255)
assert "StrictHostKeyChecking=yes" in args
assert "ForwardAgent=no" in args
if "nas" in args:
 assert args[-1]=='"/etc/profiles/per-user/$USER/bin/downloads-mirror" --background',args
 print(json.dumps({"status":"launched","pid":123})); sys.exit(0)
tail=args[args.index("client")+1:]
if len(tail)==1 and tail[0].endswith("/bin/downloads-mirror\" --print-directory"):
 print(json.dumps({"directory":os.environ["FIXTURE_SOURCE"]})); sys.exit(0)
assert tail[0].endswith("/bin/rsync"),tail
tail[0]="rsync"
if os.environ.get("FIXTURE_SLOW"): tail.insert(1,"--bwlimit=512")
os.execv(os.environ["FIXTURE_RSYNC"],tail)
''')
        ssh.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
                    "XDG_STATE_HOME": str(self.home / "state"), "FIXTURE_SOURCE": str(self.source),
                    "FIXTURE_RSYNC": self.rsync, "PATH": str(self.bin) + ":" + os.environ["PATH"]}

    def run_mirror(self, *args, **env):
        proc = subprocess.run(["python3", str(SCRIPT), *args], env={**self.env, **env}, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        return json.loads(proc.stdout)

    def test_copy_is_additive_and_replaced_files_are_saved(self):
        name = "a 'quote [x] $(never-run) café.pdf"
        (self.source / name).write_bytes(b"new completed download")
        (self.destination / name).write_bytes(b"older NAS material")
        (self.destination / "NAS-only.txt").write_text("keep")
        (self.source / "unfinished.crdownload").write_bytes(b"in progress")
        (self.source / "unsafe-link").symlink_to("/etc/passwd")
        report = self.run_mirror()
        self.assertEqual(report["status"], "completed")
        self.assertEqual((self.destination / name).read_bytes(), b"new completed download")
        self.assertEqual((self.destination / "NAS-only.txt").read_text(), "keep")
        self.assertFalse((self.destination / "unfinished.crdownload").exists())
        self.assertFalse((self.destination / "unsafe-link").exists())
        backup = self.home / "state/downloads-mirror/overwritten" / report["id"] / name
        self.assertEqual(backup.read_bytes(), b"older NAS material")
        self.assertEqual(self.run_mirror("--status")["id"], report["id"])
        self.assertEqual((self.home / "state/downloads-mirror/status.json").stat().st_mode & 0o777, 0o600)

    def test_preview_and_offline_keep_downloads_unchanged(self):
        (self.source / "completed.txt").write_text("ready")
        self.assertEqual(self.run_mirror("--dry-run")["status"], "preview")
        self.assertFalse((self.destination / "completed.txt").exists())
        offline = self.run_mirror(FIXTURE_OFFLINE="yes")
        self.assertEqual((offline["status"], offline["reason"]), ("deferred", "client-unreachable"))
        self.assertFalse((self.destination / "completed.txt").exists())

    def test_transfer_preserves_partials_and_protects_arguments(self):
        command = mirror.copy_command("client", self.source, self.destination, self.home / "state", "run")
        self.assertIn("--protect-args", command)
        self.assertIn("--partial", command)
        self.assertTrue(any(arg.startswith("--partial-dir=") for arg in command))
        self.assertNotIn("--inplace", command)
        self.assertFalse(any(arg.startswith("--delete") for arg in command))
        self.assertIn("StrictHostKeyChecking=yes", next(arg for arg in command if arg.startswith("--rsh=")))

    def test_background_request_finishes_with_a_receipt(self):
        (self.source / "event.txt").write_text("ready")
        launch = self.run_mirror("--background")
        self.assertEqual(launch["status"], "launched")
        deadline = time.monotonic() + 10
        status = None
        while time.monotonic() < deadline:
            path = Path(launch["receipt"])
            if path.exists():
                status = json.loads(path.read_text())
                if status["status"] != "running":
                    break
            time.sleep(0.02)
        self.assertEqual(status["status"], "completed")
        self.assertEqual((self.destination / "event.txt").read_text(), "ready")

    def test_xdg_watcher_preparation(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--prepare-watch"], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        dropin = self.config / "systemd/user/downloads-mirror-watch.path.d/xdg-directory.conf"
        self.assertEqual(dropin.read_text(), '[Path]\nPathChanged=\nPathChanged=' + str(self.destination) + '\n')

    def test_interrupted_copy_retains_partial_and_a_later_copy_finishes(self):
        payload = os.urandom(4 * 1024 * 1024)
        (self.source / "large.bin").write_bytes(payload)
        process = subprocess.Popen([sys.executable, str(SCRIPT)], env={**self.env, "FIXTURE_SLOW": "yes"},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                temporary = list(self.destination.glob(".large.bin.*"))
                if temporary and temporary[0].stat().st_size > 0:
                    break
                time.sleep(0.02)
            else:
                self.fail("transfer did not start")
            self.assertFalse((self.destination / "large.bin").exists())
            process.send_signal(signal.SIGTERM)
            output, error = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 1, error + output)
            self.assertEqual(json.loads(output)["status"], "interrupted")
            partial = self.home / "state/downloads-mirror/partials/large.bin"
            self.assertTrue(partial.exists())
            self.assertGreater(partial.stat().st_size, 0)
            self.assertEqual(self.run_mirror()["status"], "completed")
            self.assertEqual((self.destination / "large.bin").read_bytes(), payload)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


@unittest.skipUnless(BINARY and FIXTURE_BINARY, "Nix-built production and transport-fixture wrappers are required")
class MinimalPath(unittest.TestCase):
    setUp = Transfers.setUp

    def invoke(self, binary, *args):
        environment = {**self.env, "PATH": "/nonexistent-path", "DOWNLOADS_MIRROR_FIXTURE_SSH": str(self.bin / "ssh")}
        result = subprocess.run([binary, *args], env=environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout) if result.stdout else None

    def test_production_activation_with_no_python_on_path(self):
        self.invoke(BINARY, "--prepare-watch")
        dropin = self.config / "systemd/user/downloads-mirror-watch.path.d/xdg-directory.conf"
        self.assertIn(str(self.destination), dropin.read_text())
        self.assertEqual(self.invoke(BINARY, "--print-directory")["directory"], str(self.destination))
        self.assertEqual(self.invoke(BINARY, "--status")["status"], "never-run")

    @unittest.skipUnless(os.environ.get("DOWNLOADS_SYSTEMD_ANALYZE"), "real systemd parser required")
    def test_real_systemd_accepts_generated_units_and_private_dropin(self):
        special = self.home / 'configured "quoted" %named location'
        (self.config / "user-dirs.dirs").write_text('XDG_DOWNLOAD_DIR="' + str(special).replace('"', '\\"') + '"\n')
        self.invoke(BINARY, "--prepare-watch")
        units = self.config / "systemd/user"
        watcher = units / "downloads-mirror-watch.path"
        shutil.copyfile(os.environ["DOWNLOADS_MIRROR_PATH_UNIT"], watcher)
        service = units / "downloads-mirror-notify.service"
        shutil.copyfile(os.environ["DOWNLOADS_MIRROR_SERVICE_UNIT"], service)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        environment = {**self.env, "PATH": "/nonexistent-path", "XDG_RUNTIME_DIR": str(runtime),
                       "SYSTEMD_UNIT_PATH": str(units) + ":" + os.environ["DOWNLOADS_SYSTEMD_USER_UNITS"]}
        result = subprocess.run([os.environ["DOWNLOADS_SYSTEMD_ANALYZE"], "--user", "verify", "--man=no",
                                 "--generators=no", str(watcher), str(service)],
                                capture_output=True, text=True, env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Prove the real parser reads this drop-in and catches the original
        # failure, rather than silently checking only the packaged unit.
        dropin = units / "downloads-mirror-watch.path.d/xdg-directory.conf"
        dropin.write_text('[Path]\nPathChanged=\nPathChanged="' + str(special) + '"\n')
        rejected = subprocess.run([os.environ["DOWNLOADS_SYSTEMD_ANALYZE"], "--user", "verify", "--man=no",
                                   "--generators=no", str(watcher), str(service)],
                                  capture_output=True, text=True, env=environment)
        self.assertNotEqual(rejected.returncode, 0)

    def test_pinned_ssh_and_rsync_with_empty_path(self):
        (self.source / "quoted ' [x] café.txt").write_text("complete")
        (self.destination / "NAS-only.txt").write_text("keep")
        report = self.invoke(FIXTURE_BINARY)
        self.assertEqual(report["status"], "completed")
        self.assertEqual((self.destination / "quoted ' [x] café.txt").read_text(), "complete")
        self.assertEqual((self.destination / "NAS-only.txt").read_text(), "keep")

    def test_notify_and_detached_child_with_empty_path(self):
        self.assertEqual(self.invoke(FIXTURE_BINARY, "--notify")["status"], "launched")
        (self.source / "event.txt").write_text("ready")
        launch = self.invoke(FIXTURE_BINARY, "--background")
        self.assertEqual(launch["status"], "launched")
        deadline = time.monotonic() + 10
        status = None
        while time.monotonic() < deadline:
            path = Path(launch["receipt"])
            if path.exists():
                status = json.loads(path.read_text())
                if status["status"] != "running":
                    break
            time.sleep(0.02)
        self.assertEqual(status["status"], "completed")
        self.assertEqual((self.destination / "event.txt").read_text(), "ready")


if __name__ == "__main__":
    unittest.main()
