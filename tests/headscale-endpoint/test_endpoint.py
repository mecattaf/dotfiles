"""Identity guard tests; execute evaluated shell with synthetic command fixtures only.

Run: python3 -m unittest discover -s tests/headscale-endpoint -v
For sandboxed checks set HEADSCALE_ENROLL_SCRIPT and HEADSCALE_CONNECT_SCRIPT
to files containing the corresponding evaluated NixOS service script strings.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
LAN_URL = "http://10.42.0.1:8090"
KEY = "synthetic-bootstrap-key-never-a-real-credential"

MOCK = r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with (root / "calls").open("a") as stream:
    stream.write(json.dumps([name] + args) + "\n")
status = json.loads((root / "status").read_text())
if name == "tailscale":
    if args == ["debug", "prefs"]:
        print((root / "prefs").read_text())
    elif args == ["status", "--json", "--peers=false"]:
        print(json.dumps(status))
    elif args and args[0] == "up":
        assert "--force-reauth" not in args
        status.update(BackendState="Running", HaveNodeKey=True)
        (root / "status").write_text(json.dumps(status))
        prefs = json.loads((root / "prefs").read_text())
        prefs["ControlURL"] = "http://10.42.0.1:8090"
        (root / "prefs").write_text(json.dumps(prefs))
    else:
        sys.exit("UNEXPECTED MUTATION: " + repr(args))
elif name == "headscale":
    if args[:2] == ["users", "list"]:
        print('[{"name":"tom","id":1}]')
    elif args[:2] == ["preauthkeys", "create"]:
        assert "--tags" in args and "tag:mesh" in args
        print(json.dumps({"key": "synthetic-bootstrap-key-never-a-real-credential"}))
    else:
        sys.exit("UNEXPECTED HEADSCALE COMMAND: " + repr(args))
else:
    sys.exit("unexpected executable")
'''


def evaluated_script(service, variable):
    if variable in os.environ:
        return Path(os.environ[variable]).read_text()
    return subprocess.check_output(
        ["nix", "eval", "--raw", f".#nixosConfigurations.nas.config.systemd.services.{service}.script"],
        cwd=ROOT, text=True,
    )


class EndpointIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enroll = evaluated_script("headscale-nas-enroll", "HEADSCALE_ENROLL_SCRIPT")
        cls.connect = evaluated_script("tailscaled-autoconnect", "HEADSCALE_CONNECT_SCRIPT")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("tailscale", "headscale"):
            target = self.bin / name
            target.write_text(f"#!{sys.executable}\n" + MOCK)
            target.chmod(0o755)
        self.prefs = {"ControlURL": LAN_URL, "LoggedOut": False,
                      "Config": {"PrivateNodeKey": "synthetic-retained-key"}}
        self.status = {"BackendState": "Running", "HaveNodeKey": True,
                       "Self": {"ID": "retained-nas-id"}}

    def run_script(self, script):
        (self.root / "prefs").write_text(json.dumps(self.prefs))
        (self.root / "status").write_text(json.dumps(self.status))
        script = script.replace("/run/headscale-nas-enroll/authkey", str(self.root / "authkey"))
        env = dict(os.environ, FIXTURE_ROOT=str(self.root), RUNTIME_DIRECTORY=str(self.root),
                   PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        result = subprocess.run([shutil.which("bash"), "-c", script], env=env,
                                capture_output=True, text=True, timeout=10)
        self.assertNotIn(KEY, result.stdout + result.stderr)
        self.assertNotIn("synthetic-retained-key", result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
        return result, calls

    def assert_read_only(self, calls):
        self.assertTrue(all(call in (["tailscale", "debug", "prefs"],
                                     ["tailscale", "status", "--json", "--peers=false"])
                            for call in calls), calls)
        self.assertFalse((self.root / "authkey").exists())

    def test_running_identity_never_mints(self):
        result, calls = self.run_script(self.enroll)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_read_only(calls)

    def test_running_connect_needs_no_keyfile(self):
        result, calls = self.run_script(self.connect)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_read_only(calls)

    def test_changed_or_foreign_url_fails_closed(self):
        for url in ("https://controlplane.tailscale.com", "https://nas.example.ts.net"):
            for script in (self.enroll, self.connect):
                with self.subTest(url=url, script=script[:20]):
                    self.prefs["ControlURL"] = url
                    result, calls = self.run_script(script)
                    self.assertNotEqual(result.returncode, 0)
                    self.assert_read_only(calls)

    def test_existing_stopped_identity_is_not_reenrolled(self):
        self.status["BackendState"] = "Stopped"
        result, calls = self.run_script(self.enroll)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_read_only(calls)
        result, calls = self.run_script(self.connect)
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = [call for call in calls if call[:2] == ["tailscale", "up"]]
        self.assertEqual(mutations, [["tailscale", "up"]])
        self.assertFalse((self.root / "authkey").exists())

    def test_existing_expired_or_unapproved_identity_requires_operator(self):
        for state in ("NeedsLogin", "NeedsMachineAuth"):
            self.status["BackendState"] = state
            result, calls = self.run_script(self.enroll)
            self.assertNotEqual(result.returncode, 0)
            self.assert_read_only(calls)

    def test_unknown_key_state_fails_closed(self):
        del self.status["HaveNodeKey"]
        result, calls = self.run_script(self.enroll)
        self.assertNotEqual(result.returncode, 0)
        self.assert_read_only(calls)

    def test_malformed_prefs_cannot_look_pristine(self):
        self.prefs = {"ControlURL": ""}
        self.status.update(BackendState="NeedsLogin", HaveNodeKey=False, Self=None)
        result, calls = self.run_script(self.enroll)
        self.assertNotEqual(result.returncode, 0)
        self.assert_read_only(calls)

    def test_pristine_bootstrap_mints_tagged_key_only(self):
        self.prefs.update(ControlURL="", Config=None)
        self.status.update(BackendState="NeedsLogin", HaveNodeKey=False, Self=None)
        self.assert_pristine_bootstrap()

    def test_authentic_fresh_status_omits_false_have_node_key(self):
        # Non-secret projection of the live 1.98.10 fresh-daemon shape:
        # HaveNodeKey's omitempty tag removes false instead of emitting it.
        self.prefs.update(ControlURL="", Config=None)
        self.status = json.loads((Path(__file__).parent / "fixtures/fresh-status.json").read_text())
        self.assertNotIn("HaveNodeKey", self.status)
        self.assert_pristine_bootstrap()

    def test_missing_key_with_retained_config_is_not_pristine(self):
        self.status.update(BackendState="NeedsLogin", Self=None)
        del self.status["HaveNodeKey"]
        result, calls = self.run_script(self.enroll)
        self.assertNotEqual(result.returncode, 0)
        self.assert_read_only(calls)

    def test_explicit_null_key_is_malformed_not_omitted(self):
        self.prefs.update(ControlURL="", Config=None)
        self.status.update(BackendState="NeedsLogin", HaveNodeKey=None, Self=None)
        result, calls = self.run_script(self.enroll)
        self.assertNotEqual(result.returncode, 0)
        self.assert_read_only(calls)

    def assert_pristine_bootstrap(self):
        result, calls = self.run_script(self.enroll)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(call[:3] == ["headscale", "preauthkeys", "create"] for call in calls), 1)
        self.assertEqual((self.root / "authkey").read_text().strip(), KEY)
        self.assertEqual((self.root / "authkey").stat().st_mode & 0o777, 0o400)
        result, calls = self.run_script(self.connect)
        self.assertEqual(result.returncode, 0, result.stderr)
        up = [call for call in calls if call[:2] == ["tailscale", "up"]]
        self.assertEqual(len(up), 1)
        self.assertIn("--auth-key=file:" + str(self.root / "authkey"), up[0])
        self.assertNotIn(KEY, " ".join(up[0]))

    def test_logged_out_profile_is_not_pristine(self):
        self.prefs.update(Config=None, LoggedOut=True)
        self.status.update(BackendState="NeedsLogin", HaveNodeKey=False, Self=None)
        result, calls = self.run_script(self.enroll)
        self.assertNotEqual(result.returncode, 0)
        self.assert_read_only(calls)

    def test_scripts_have_no_destructive_identity_operation(self):
        for script in (self.enroll, self.connect):
            self.assertNotIn("tailscale logout", script)
            self.assertNotIn("--force-reauth", script)
            self.assertNotIn("tailscale switch", script)


if __name__ == "__main__":
    unittest.main()
