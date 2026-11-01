"""Run through the installed runtime-test, outside the Nix build sandbox.

Positive device tests mount /dev/null at the requested device paths inside a
second private /dev. They exercise character-device checks, permissions, argv
and mount scope without exposing a real GPU or issuing any GPU requests.

    ~/.local/bin/runtime-test -- python3 -m unittest discover \
        -s tests/runtime-test -p 'test_*.py' -v
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


RUNNER = str(Path(__file__).resolve().parents[2] / "home/dot_local/bin/runtime-test")
RENDER = "/dev/dri/renderD128"
UNSET = (
    "DBUS_SESSION_BUS_ADDRESS", "DBUS_SESSION_BUS_PID", "NOTIFY_SOCKET",
    "WATCHDOG_PID", "WATCHDOG_USEC", "WAYLAND_DISPLAY", "DISPLAY", "SWAYSOCK",
    "I3SOCK", "SSH_AUTH_SOCK", "PULSE_SERVER",
)


def run(*argv, env=None):
    return subprocess.run(
        [RUNNER, *argv], env=env, capture_output=True, text=True, timeout=15,
    )


def fixture(*argv, kfd="char", render="char", kvm=False, env=None):
    # The caller is already inside the installed runtime-test. This fixture
    # changes /dev only; PID/IPC separation must come from the candidate runner.
    with tempfile.TemporaryDirectory(prefix="runtime-gpu-devices-") as root:
        regular = Path(root) / "regular"
        regular.write_text("not a character device")
        command = [
            "bwrap", "--die-with-parent", "--unshare-user", "--bind", "/", "/",
            "--dev", "/dev", "--dir", "/dev/dri",
        ]
        for path, kind in (("/dev/kfd", kfd), (RENDER, render)):
            if kind == "char":
                command += ["--dev-bind", "/dev/null", path]
            elif kind == "regular":
                command += ["--bind", str(regular), path]
            elif kind == "symlink":
                command += ["--symlink", "/dev/null", path]
            elif kind is not None:
                raise ValueError(kind)
        # The candidate must not inherit another render node or a display node.
        command += [
            "--dev-bind", "/dev/null", "/dev/dri/renderD129",
            "--dev-bind", "/dev/null", "/dev/dri/card0",
        ]
        if kvm:
            command += ["--dev-bind", "/dev/null", "/dev/kvm"]
        command += ["--", RUNNER, *argv]
        return subprocess.run(
            command, env=env, capture_output=True, text=True, timeout=15,
        )


DEVICE_PROBE = r"""
import os, pathlib, stat, sys
for path in ['/dev/kfd', '/dev/dri/renderD128']:
    info = os.stat(path)
    assert stat.S_ISCHR(info.st_mode), path
    assert info.st_rdev == os.stat('/dev/null').st_rdev, 'fixture is not /dev/null'
    os.close(os.open(path, os.O_RDWR))
assert sorted(os.listdir('/dev/dri')) == ['renderD128']
assert pathlib.Path('/dev/kvm').exists() == (sys.argv[1] == 'kvm')
"""


@unittest.skipUnless(shutil.which("bwrap"), "bubblewrap is required")
class AllowGpu(unittest.TestCase):
    def test_default_keeps_gpu_devices_absent(self):
        p = fixture("--", sys.executable, "-c", (
            "from pathlib import Path; "
            "assert not Path('/dev/kfd').exists(); "
            "assert not Path('/dev/dri').exists()"
        ))
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_binds_only_kfd_and_selected_render_node(self):
        p = fixture("--allow-gpu", RENDER, "--", sys.executable,
                    "-c", DEVICE_PROBE, "no-kvm")
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_combined_flags_in_either_order_preserve_argv(self):
        arguments = ["two words", "", "--allow-gpu", "/dev/dri/renderD129", "--", "literal*"]
        probe = DEVICE_PROBE + "\nimport json; assert sys.argv[3:] == json.loads(sys.argv[2])\n"
        for flags in (
            ["--allow-kvm", "--allow-gpu", RENDER],
            ["--allow-gpu", RENDER, "--allow-kvm"],
        ):
            for separator in ([], ["--"]):
                with self.subTest(flags=flags, separator=separator):
                    p = fixture(*flags, *separator, sys.executable, "-c", probe,
                                "kvm", json.dumps(arguments), *arguments, kvm=True)
                    self.assertEqual(p.returncode, 0, p.stderr)

    def test_device_paths_must_be_exact_render_node_names(self):
        for path in (
            "/dev/dri", "/dev/dri/card0", "/dev/kfd", "renderD128",
            "/tmp/renderD128", "/dev/dri/renderD", "/dev/dri/renderD-1",
            "/dev/dri/renderD128/", "/dev/dri/renderD128/../renderD129",
            "/dev/dri/renderD128\n",
        ):
            with self.subTest(path=path):
                p = run("--allow-gpu", path, "--", "true")
                self.assertEqual(p.returncode, 2, p.stderr)
                self.assertIn("requires /dev/dri/renderD<number>", p.stderr)

    def test_missing_devices_refuse_to_run_the_command(self):
        for device, kwargs in (("/dev/kfd", {"kfd": None}), (RENDER, {"render": None})):
            with self.subTest(device=device):
                p = fixture("--allow-gpu", RENDER, "--", "echo", "MUST_NOT_RUN", **kwargs)
                self.assertEqual(p.returncode, 1, p.stderr)
                self.assertIn(device, p.stderr)
                self.assertNotIn("MUST_NOT_RUN", p.stdout)

    def test_regular_files_and_symlinks_are_rejected(self):
        for option, device in (("kfd", "/dev/kfd"), ("render", RENDER)):
            for kind in ("regular", "symlink"):
                with self.subTest(device=device, kind=kind):
                    p = fixture("--allow-gpu", RENDER, "--", "true", **{option: kind})
                    self.assertEqual(p.returncode, 1, p.stderr)
                    self.assertIn(device, p.stderr)
                    self.assertIn("read-write character device", p.stderr)

    def test_multiple_render_nodes_are_not_supported(self):
        for second in (RENDER, "/dev/dri/renderD129"):
            p = run("--allow-gpu", RENDER, "--allow-gpu", second, "--", "true")
            self.assertEqual(p.returncode, 2, p.stderr)
            self.assertIn("only one render node", p.stderr)

    def test_missing_argument_or_command_is_usage_error(self):
        for arguments in (
            ["--allow-gpu"], ["--allow-gpu", "--", "true"],
            ["--allow-gpu", "--allow-kvm", "true"],
            ["--allow-gpu", RENDER], ["--allow-gpu", RENDER, "--"],
            ["--allow-kvm", "--allow-gpu", RENDER, "--"],
        ):
            with self.subTest(arguments=arguments):
                self.assertEqual(run(*arguments).returncode, 2)

    def test_help_describes_both_narrow_flags(self):
        p = run("--help")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("--allow-kvm", p.stdout)
        self.assertIn("--allow-gpu", p.stdout)
        self.assertIn("/dev/kfd", p.stdout)

    def test_gpu_flag_preserves_private_runtime_pid_ipc_and_environment(self):
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        parent_namespaces = [os.readlink(f"/proc/self/ns/{kind}") for kind in ("pid", "ipc")]
        with tempfile.TemporaryDirectory(prefix="runtime-gpu-socket-", dir=runtime) as root:
            path = str(Path(root) / "socket")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                probe = r"""
import json, os, pathlib, shutil, socket, sys
runtime = pathlib.Path(os.environ['XDG_RUNTIME_DIR'])
assert runtime == pathlib.Path('/run/user') / str(os.getuid())
assert runtime.stat().st_mode & 0o777 == 0o700
assert list(runtime.iterdir()) == []
assert not pathlib.Path(sys.argv[1]).exists(), 'parent runtime socket is visible'
with socket.socket(socket.AF_UNIX) as connection:
    try:
        connection.connect(sys.argv[1])
    except FileNotFoundError:
        pass
    else:
        raise AssertionError('connected to parent runtime socket')
assert [os.readlink('/proc/self/ns/' + kind) for kind in ['pid', 'ipc']] != json.loads(sys.argv[2])
for kind, parent in zip(['pid', 'ipc'], json.loads(sys.argv[2])):
    assert os.readlink('/proc/self/ns/' + kind) != parent, kind + ' namespace is shared'
assert all(name not in os.environ for name in json.loads(sys.argv[3]))
(runtime / 'disposable').mkdir()
(runtime / 'disposable' / 'file').write_text('private')
for child in runtime.iterdir():
    shutil.rmtree(child) if child.is_dir() else child.unlink()
"""
                environment = dict(os.environ, **{name: "live-sentinel" for name in UNSET})
                p = fixture("--allow-gpu", RENDER, "--", sys.executable, "-c", probe,
                            path, json.dumps(parent_namespaces), json.dumps(UNSET), env=environment)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertTrue(Path(path).is_socket(), "parent socket was removed")
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.connect(path)
                    accepted, _ = listener.accept()
                    accepted.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
