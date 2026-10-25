"""Hermetic checks: no hardware, desktop sockets, or audio playback."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MENU = os.environ.get("INZONE_MENU_SCRIPT", str(ROOT / "home/dot_local/bin/inzone-menu"))
VOLUME = os.environ.get("INZONE_VOLUME_SCRIPT", str(ROOT / "home/dot_local/bin/volume"))

STUB = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = pathlib.Path(os.environ["MOCK_STATE"])
state = json.loads(state_path.read_text())
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "wpctl":
    if args[0] == "inspect":
        print('node.name = "' + os.environ["MOCK_SINK"] + '"')
    elif args[0] == "get-volume":
        print("Volume: 0.35")
elif name == "zoneout":
    if "--get" in args:
        print(state[args[args.index("--get") + 1]])
    elif "--set" in args:
        index = args.index("--set")
        state[args[index + 1]] = int(args[index + 2])
elif name == "fzf":
    rows = sys.stdin.read().splitlines()
    if not state["choices"]:
        sys.exit(1)
    wanted = state["choices"].pop(0)
    state_path.write_text(json.dumps(state))
    matches = [row for row in rows if row.split("\t")[0] == wanted]
    if not matches:
        sys.exit(1)
    print(matches[0])
state_path.write_text(json.dumps(state))
'''

class InzoneAudioTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for name in ("wpctl", "zoneout", "fzf", "osd"):
            path = bin_dir / name
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        self.state = root / "state.json"
        self.log = root / "calls.jsonl"
        self.state.write_text(json.dumps({
            "volume": 20, "balance": 50, "nc_mode": 1, "choices": []
        }))
        self.env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / "xdg"),
                        PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                        MOCK_STATE=str(self.state), MOCK_LOG=str(self.log),
                        MOCK_SINK="alsa_output.usb-Sony_INZONE_Buds-00.iec958-stereo",
                        ZONEOUT=str(bin_dir / "zoneout"))

    def configure(self, **values):
        state = json.loads(self.state.read_text())
        state.update(values)
        self.state.write_text(json.dumps(state))

    def run_script(self, script, *args):
        return subprocess.run([shutil.which("bash"), script, *args], env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=8)

    def calls(self, name, verb):
        return [args for item, args in
                (json.loads(line) for line in self.log.read_text().splitlines())
                if item == name and verb in args]

    def test_inzone_volume_keys_stop_at_unity(self):
        result = self.run_script(VOLUME, "up")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("wpctl", "set-volume"),
                         [["set-volume", "--limit", "1.0", "@DEFAULT_AUDIO_SINK@", "3%+"]])

    def test_other_output_keeps_existing_volume_behavior(self):
        self.env["MOCK_SINK"] = "alsa_output.usb-Creative_GS3.analog-stereo"
        result = self.run_script(VOLUME, "up")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("wpctl", "set-volume"),
                         [["set-volume", "@DEFAULT_AUDIO_SINK@", "3%+"]])

    def test_native_volume_selection_changes_only_native_volume(self):
        self.configure(choices=["volume", "21"])
        result = self.run_script(MENU)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("zoneout", "--set"),
                         [["--device", "buds", "--set", "volume", "21"]])
        self.assertEqual(self.calls("wpctl", "set-volume"), [])
        gets = self.calls("zoneout", "--get")
        self.assertEqual(len(gets), 6, "all three displayed values must be read back")

    def test_game_chat_balance_selection(self):
        self.configure(balance=80, choices=["balance", "50"])
        result = self.run_script(MENU)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("zoneout", "--set"),
                         [["--device", "buds", "--set", "balance", "50"]])

    def test_noise_control_selection(self):
        self.configure(choices=["noise", "2"])
        result = self.run_script(MENU)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("zoneout", "--set"),
                         [["--device", "buds", "--set", "nc_mode", "2"]])

    def test_cancel_never_writes_hardware(self):
        result = self.run_script(MENU)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls("zoneout", "--set"), [])

    def test_bad_native_reading_never_writes_hardware(self):
        for value in (31, "not connected"):
            with self.subTest(value=value):
                self.configure(volume=value, choices=["volume", "30"])
                result = self.run_script(MENU)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(self.calls("zoneout", "--set"), [])

if __name__ == "__main__":
    unittest.main()
