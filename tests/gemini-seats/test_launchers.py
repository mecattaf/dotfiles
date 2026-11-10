"""Test actual account launchers with an offline Gemini executable."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LAUNCHERS = Path(os.environ.get(
    "GEMINI_LAUNCHERS", Path(__file__).resolve().parents[2] / "home/dot_local/bin"
))
AUTH_VARS = (
    "GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_APPLICATION_CREDENTIALS",
    "GOOGLE_GENAI_USE_VERTEXAI", "GOOGLE_GENAI_USE_GCA", "GOOGLE_CLOUD_ACCESS_TOKEN",
    "GEMINI_CLI_TRUSTED_FOLDERS_PATH",
)
MOCK = r'''
import json, os, pathlib, sys
state = pathlib.Path(os.environ["GEMINI_CLI_HOME"]) / ".gemini"
token = state / "oauth_creds.json"
if not token.exists():
    token.write_text(os.environ["FAKE_ACCOUNT"])
print(json.dumps({
    "home": os.environ["HOME"], "state": str(state), "cwd": os.getcwd(),
    "args": sys.argv[1:], "account": token.read_text(),
    "mode": os.environ["GEMINI_CLI_AUTH_OVERRIDE"],
    "encrypted": os.environ["GEMINI_FORCE_ENCRYPTED_FILE_STORAGE"],
    "file_storage": os.environ["GEMINI_FORCE_FILE_STORAGE"],
    "auth": {k: os.environ.get(k) for k in json.loads(os.environ["AUTH_VARS"])},
}))
sys.exit(int(os.environ.get("MOCK_EXIT", "0")))
'''


class GeminiSeats(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.user_home = self.root / "home with spaces"
        self.user_home.mkdir()
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        executable = self.bin / "gemini"
        executable.write_text("#!" + sys.executable + "\n" + MOCK)
        executable.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.user_home),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        AUTH_VARS=json.dumps(AUTH_VARS),
                        GEMINI_CLI_HOME=str(self.root / "inherited-wrong-seat"),
                        GEMINI_FORCE_ENCRYPTED_FILE_STORAGE="true")
        self.env.update({key: "inherited-wrong-identity" for key in AUTH_VARS})

    def launch(self, command, *args, **env):
        result = subprocess.run(
            ["bash", str(LAUNCHERS / command), *args], cwd=self.project,
            env=self.env | env, capture_output=True, text=True, timeout=10,
        )
        return result, json.loads(result.stdout)

    def test_three_persistent_logins_are_separate_and_reset_inherited_seat(self):
        for index, command in enumerate(("gmni", "gmni2", "gmni3"), 1):
            with self.subTest(command=command):
                account_home = self.user_home if index == 1 else self.user_home / f".gemini-account-{index}"
                expected = account_home / ".gemini"
                result, actual = self.launch(command, FAKE_ACCOUNT=str(index))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(actual["state"], str(expected))
                self.assertEqual(actual["account"], str(index))
                self.assertEqual(actual["home"], str(self.user_home))
                self.assertEqual(actual["cwd"], str(self.project))
                self.assertEqual(expected.stat().st_mode & 0o777, 0o700)
                self.assertEqual((expected / "oauth_creds.json").stat().st_mode & 0o777, 0o600)
                settings = expected / "settings.json"
                settings.write_text('{"model":{"name":"user-choice"}}')
                _, repeated = self.launch(command, FAKE_ACCOUNT="must-not-replace")
                self.assertEqual(repeated["account"], str(index))
                self.assertEqual(settings.read_text(), '{"model":{"name":"user-choice"}}')
        self.assertFalse((self.root / "inherited-wrong-seat").exists())

    def test_browser_oauth_and_file_storage_replace_ambient_api_credentials(self):
        _, actual = self.launch("gmni2", FAKE_ACCOUNT="2")
        self.assertEqual(actual["mode"], "oauth-personal")
        self.assertEqual(actual["encrypted"], "false")
        self.assertEqual(actual["file_storage"], "true")
        self.assertEqual(actual["auth"], dict.fromkeys(AUTH_VARS, ""))

    def test_arguments_and_exit_status_pass_through_unchanged(self):
        args = ("--resume", "latest", "--prompt", "a 'quoted' prompt; $(false)", "")
        result, actual = self.launch("gmni3", *args, FAKE_ACCOUNT="3", MOCK_EXIT="17")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(actual["args"], list(args))


if __name__ == "__main__":
    unittest.main()
