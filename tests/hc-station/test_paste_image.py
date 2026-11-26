"""hc-paste-image against fake kitten, wl-paste and ssh on PATH.

No clipboard, Kitty or ssh is used: every program the script calls is a
recorder in a temporary directory.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BIN = Path(os.environ.get("DOTFILES_BIN", Path(__file__).resolve().parents[2] / "home/dot_local/bin"))
SCRIPT = BIN / "hc-paste-image"

PINNED = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
          "-o", "Hostname=100.65.85.114", "-o", "HostKeyAlias=nas",
          "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
          "-o", "ControlMaster=no", "-o", "ControlPath=none",
          "-o", "ConnectTimeout=10"]

FAKE = r'''
import json, os, shlex, sys
from pathlib import Path
here = Path(sys.argv[0]).resolve().parent
name = Path(sys.argv[0]).name
data = sys.stdin.buffer.read() if name == "ssh" else b""
with open(here / (name + ".jsonl"), "a") as out:
    out.write(json.dumps({"argv": sys.argv[1:], "stdin_len": len(data)}) + "\n")
if name == "kitten" and sys.argv[1:3] == ["@", "ls"]:
    print((here / "kitten-ls.json").read_text())
elif name == "wl-paste" and sys.argv[1:] == ["--list-types"]:
    print((here / "wl-types.txt").read_text())
elif name == "wl-paste":
    sys.stdout.buffer.write((here / "image.bin").read_bytes())
elif name == "ssh":
    if (here / "ssh-fail").exists():
        sys.exit(255)
    if (here / "change-station").exists():
        data = json.loads((here / "kitten-ls.json").read_text())
        data[0]["tabs"][0]["windows"][0]["user_vars"]["hc_addr"] = "t8"
        (here / "kitten-ls.json").write_text(json.dumps(data))
    print("/tmp/hc-paste-1000/" + shlex.split(sys.argv[-1])[-1])
'''


class PasteImage(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="paste")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("kitten", "wl-paste", "ssh"):
            path = self.bin / name
            path.write_text("#!" + sys.executable + "\n" + FAKE)
            path.chmod(0o755)
        self.window({"hc_addr": "t7"})
        (self.bin / "wl-types.txt").write_text("text/plain\nimage/png\n")
        (self.bin / "image.bin").write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(range(92)))

    def window(self, user_vars):
        listing = [{"id": 1, "tabs": [{"id": 1, "windows": [{"id": 7, "user_vars": user_vars}]}]}]
        (self.bin / "kitten-ls.json").write_text(json.dumps(listing))

    def run_paste(self, *args):
        env = {"PATH": f"{self.bin}:{os.environ.get('PATH', '')}", "HOME": str(self.root)}
        return subprocess.run([sys.executable, str(SCRIPT), *args], env=env, capture_output=True, text=True, timeout=30)

    def calls(self, name):
        path = self.bin / (name + ".jsonl")
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def sent(self, verb):
        return [call["argv"] for call in self.calls("kitten") if call["argv"][1:2] == [verb]]

    def test_a_station_and_a_png_upload_once_and_paste_the_nas_path(self):
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 0, result.stderr)
        ssh = self.calls("ssh")
        self.assertEqual(len(ssh), 1)
        self.assertEqual(["ssh"] + ssh[0]["argv"][:18], PINNED)
        self.assertEqual(ssh[0]["argv"][18], "nas")
        self.assertEqual(ssh[0]["stdin_len"], 100)
        texts = self.sent("send-text")
        self.assertEqual(len(texts), 1)
        self.assertEqual(texts[0][:7], ["@", "send-text", "--match", "id:7", "--bracketed-paste", "auto", "--"])
        self.assertRegex(texts[0][7], r"^/tmp/hc-paste-1000/clipboard-\d{8}-\d{6}-[0-9a-f]{16}\.png$")
        self.assertEqual(self.sent("send-key"), [])

    def test_not_a_station_passes_ctrl_v_through(self):
        self.window({})
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.sent("send-key"), [["@", "send-key", "--match", "id:7", "ctrl+v"]])
        self.assertEqual(self.calls("ssh"), [])

    def test_no_image_passes_ctrl_v_through(self):
        (self.bin / "wl-types.txt").write_text("text/plain\n")
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.sent("send-key")), 1)
        self.assertEqual(self.calls("ssh"), [])

    def test_an_address_with_shell_characters_is_not_a_station(self):
        self.window({"hc_addr": "t7; rm -rf /"})
        self.run_paste("7")
        self.assertEqual(len(self.sent("send-key")), 1)
        self.assertEqual(self.calls("ssh"), [])

    def test_a_failed_upload_pastes_nothing(self):
        (self.bin / "ssh-fail").write_text("")
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 1)
        self.assertIn("upload to the NAS failed", result.stderr)
        self.assertEqual(self.sent("send-text"), [])

    def test_a_changed_attachment_pastes_nothing(self):
        (self.bin / "change-station").write_text("")
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed", result.stderr)
        self.assertEqual(self.sent("send-text"), [])

    def test_a_mislabeled_image_is_not_uploaded(self):
        (self.bin / "image.bin").write_bytes(b"not an image")
        result = self.run_paste("7")
        self.assertEqual(result.returncode, 1)
        self.assertIn("image signature", result.stderr)
        self.assertEqual(self.calls("ssh"), [])

    def test_bad_arguments(self):
        for args in ((), ("abc",), ("7", "8")):
            result = self.run_paste(*args)
            self.assertEqual(result.returncode, 2, args)
        for name in ("kitten", "wl-paste", "ssh"):
            self.assertEqual(self.calls(name), [])


if __name__ == "__main__":
    unittest.main()
