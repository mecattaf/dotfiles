"""Argument/status boundary only; no SSH, Kitty or live editor input."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("native_nvim", str(ROOT / "home/dot_local/bin/nvim-remote"))
spec = importlib.util.spec_from_loader("native_nvim", loader)
launcher = importlib.util.module_from_spec(spec)
loader.exec_module(launcher)


class Launcher(unittest.TestCase):
    def test_paths_remain_arguments(self):
        directory = "/tmp/it's a $(touch NEVER) `touch NEVER` directory"
        files = ["a b.md", "quote'file", "semi;colon", "[literal].md", "--", "-file"]
        data = launcher.request(directory, files)
        self.assertEqual(data["files"], files[:4] + ["-file"])
        argv = launcher.kitty_argv(directory, files)
        self.assertEqual(argv[-len(files):], files)
        self.assertEqual(argv[argv.index("--directory") + 1], directory)
        self.assertIn("--wait-for-child-to-exit", argv)
        self.assertIn("--source-window=state:self", argv)
        self.assertIn("--next-to=state:self", argv)

    def test_commands_and_unsupported_options(self):
        self.assertEqual(launcher.request("/tmp", ["+42", "-c", "set number", "a.md"]),
                         {"directory": "/tmp", "files": ["a.md"], "commands": ["42", "set number"]})
        for args in (["-c"], ["-u", "evil.lua"], ["-d", "a", "b"]):
            with self.assertRaises(ValueError):
                launcher.request("/tmp", args)

    def test_old_core_role_does_not_need_restart(self):
        for hostname, role in (("nas", "brain"), ("client", "seat"), ("strix-coordinator", "local")):
            with patch.object(launcher.socket, "gethostname", return_value=hostname):
                self.assertEqual(launcher.role({}), role)
        self.assertEqual(launcher.role({"NVIM_REMOTE_ROLE": "local"}), "local")


if __name__ == "__main__":
    unittest.main()
