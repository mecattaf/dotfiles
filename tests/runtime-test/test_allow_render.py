"""Render-only DRM access without KFD; run under the installed runtime-test.

The shared fixture mounts /dev/null in a nested private /dev. No real GPU,
display node, compositor, DRM ioctl or inference workload is involved.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import sys
import tempfile
import unittest

from test_allow_gpu import RENDER, UNSET, fixture, run


PROBE = r"""
import os, pathlib, stat
path = pathlib.Path('/dev/dri/renderD128')
assert stat.S_ISCHR(path.stat().st_mode)
assert path.stat().st_rdev == os.stat('/dev/null').st_rdev
os.close(os.open(path, os.O_RDWR))
assert sorted(os.listdir('/dev/dri')) == ['renderD128']
assert not pathlib.Path('/dev/kfd').exists()
"""


@unittest.skipUnless(shutil.which("bwrap"), "bubblewrap is required")
class AllowRender(unittest.TestCase):
    def test_render_only_needs_no_kfd(self):
        result = fixture("--allow-render", RENDER, "--", sys.executable, "-c", PROBE, kfd=None)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ambient_kfd_is_never_inherited_or_required(self):
        for kind in ("char", "regular", "symlink"):
            with self.subTest(kfd=kind):
                result = fixture("--allow-render", RENDER, "--", sys.executable,
                                 "-c", PROBE, kfd=kind)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_gpu_and_render_modes_are_mutually_exclusive(self):
        for flags in (("--allow-gpu", RENDER, "--allow-render", RENDER),
                      ("--allow-render", RENDER, "--allow-gpu", RENDER),
                      ("--allow-render", RENDER, "--allow-render", "/dev/dri/renderD129")):
            with self.subTest(flags=flags):
                result = run(*flags, "--", "echo", "MUST_NOT_RUN")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("only one render node", result.stderr)
                self.assertNotIn("MUST_NOT_RUN", result.stdout)

    def test_kvm_combination_preserves_literal_arguments(self):
        arguments = ["two words", "", "--allow-render", "literal*", "--"]
        probe = PROBE + r"""
import json, sys
assert pathlib.Path('/dev/kvm').exists()
assert sys.argv[2:] == json.loads(sys.argv[1])
"""
        for flags in (("--allow-kvm", "--allow-render", RENDER),
                      ("--allow-render", RENDER, "--allow-kvm")):
            with self.subTest(flags=flags):
                result = fixture(*flags, "--", sys.executable, "-c", probe,
                                 json.dumps(arguments), *arguments, kvm=True, kfd=None)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_only_exact_render_paths_are_accepted(self):
        for path in ("/dev/dri/card0", "/dev/kfd", "/dev/dri", "renderD128",
                     "/dev/dri/renderD", "/dev/dri/renderD128/", "/dev/dri/renderD128\n"):
            with self.subTest(path=path):
                result = run("--allow-render", path, "--", "true")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("--allow-render requires /dev/dri/renderD<number>", result.stderr)

    def test_missing_or_invalid_render_never_runs_command(self):
        for kind in (None, "regular", "symlink"):
            with self.subTest(render=kind):
                result = fixture("--allow-render", RENDER, "--", "echo", "MUST_NOT_RUN",
                                 render=kind, kfd=None)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("read-write character device", result.stderr)
                self.assertNotIn("MUST_NOT_RUN", result.stdout)

    def test_missing_argument_or_command_is_usage_error(self):
        for flags in (("--allow-render",), ("--allow-render", "--", "true"),
                      ("--allow-render", RENDER), ("--allow-render", RENDER, "--")):
            with self.subTest(flags=flags):
                self.assertEqual(run(*flags).returncode, 2)

    def test_help_distinguishes_render_and_gpu_modes(self):
        result = run("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--allow-render", result.stdout)
        self.assertIn("--allow-gpu", result.stdout)
        self.assertIn("without /dev/kfd", result.stdout)

    def test_private_runtime_namespaces_and_environment_are_preserved(self):
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        parent_namespaces = [os.readlink(f"/proc/self/ns/{kind}") for kind in ("pid", "ipc")]
        with tempfile.TemporaryDirectory(prefix="render-parent-socket-", dir=runtime) as directory:
            path = str(Path(directory) / "socket")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                probe = PROBE + r"""
import json, socket, sys
runtime = pathlib.Path(os.environ['XDG_RUNTIME_DIR'])
assert runtime == pathlib.Path('/run/user') / str(os.getuid())
assert runtime.stat().st_mode & 0o777 == 0o700
assert list(runtime.iterdir()) == []
assert not pathlib.Path(sys.argv[1]).exists()
for kind, parent in zip(('pid', 'ipc'), json.loads(sys.argv[2])):
    assert os.readlink('/proc/self/ns/' + kind) != parent
assert all(name not in os.environ for name in json.loads(sys.argv[3]))
(runtime / 'child-private-file').write_text('namespace only')
"""
                environment = dict(os.environ, **{name: "parent-sentinel" for name in UNSET})
                result = fixture("--allow-render", RENDER, "--", sys.executable, "-c", probe,
                                 path, json.dumps(parent_namespaces), json.dumps(UNSET),
                                 env=environment, kfd=None)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(Path(path).is_socket())
                self.assertFalse((runtime / 'child-private-file').exists())
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.connect(path)
                    accepted, _ = listener.accept()
                    accepted.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
