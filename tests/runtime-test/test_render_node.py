"""The graphics test opt-in exposes rendering, never display/input ownership."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

RUNNER = str(Path(__file__).resolve().parents[2] / "home/dot_local/bin/runtime-test")
NODES = [p for p in Path("/dev/dri").glob("renderD*")
         if p.is_char_device() and os.access(p, os.R_OK | os.W_OK)]


class RenderIsolation(unittest.TestCase):
    def invoke(self, *args):
        return subprocess.run([RUNNER, *args], capture_output=True, text=True, timeout=15)

    def test_default_has_no_graphics_devices(self):
        result = self.invoke("--", sys.executable, "-c",
                             "from pathlib import Path; assert not Path('/dev/dri').exists()")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_card_input_and_arbitrary_paths_are_rejected(self):
        for path in ["/dev/dri/card1", "/dev/input/event0", "/dev/kvm", "/dev/dri/../null"]:
            with self.subTest(path=path):
                result = self.invoke("--render-node", path, "--", "true")
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_missing_render_device_fails(self):
        result = self.invoke("--render-node", "/dev/dri/renderD999999", "--", "true")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("accessible DRM render device", result.stderr)

    @unittest.skipUnless(NODES, "no usable render node")
    def test_only_selected_render_node_and_private_runtime(self):
        node = NODES[0]
        probe = """
import os, pathlib, sys
assert sorted(p.name for p in pathlib.Path('/dev/dri').iterdir()) == [sys.argv[1]]
assert not pathlib.Path('/dev/input').exists()
assert not pathlib.Path('/dev/kvm').exists()
assert not pathlib.Path(os.environ['XDG_RUNTIME_DIR'], 'bus').exists()
assert 'HYPRLAND_INSTANCE_SIGNATURE' not in os.environ
os.close(os.open('/dev/dri/' + sys.argv[1], os.O_RDWR))
"""
        result = self.invoke("--render-node", str(node), "--", sys.executable, "-c", probe, node.name)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
