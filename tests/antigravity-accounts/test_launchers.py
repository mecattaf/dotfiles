"""Execute the actual NAS launcher body against an offline vendor stand-in."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(os.environ.get('AGY_ACCOUNTS_SCRIPT', Path(__file__).resolve().parents[2] / 'home/antigravity-accounts.sh'))
REMOVED = ('GEMINI_CLI_HOME', 'GEMINI_CLI_AUTH_OVERRIDE', 'GEMINI_CLI_SYSTEM_SETTINGS_PATH',
           'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
           'GOOGLE_CLOUD_ACCESS_TOKEN', 'AGY_ADC_AUTH', 'AGY_ACCOUNT',
           'ANTIGRAVITY_CONFIG_REL_DIR', 'ANTIGRAVITY_CREDENTIAL_SCOPE')
MOCK = r'''
import json, os, pathlib, sys
root = pathlib.Path(sys.argv[2])
token = root / 'antigravity-cli/antigravity-oauth-token'
token.parent.mkdir(exist_ok=True)
if not token.exists(): token.write_text(os.environ['FAKE_ACCOUNT'])
print(json.dumps({'args':sys.argv[1:], 'home':os.environ['HOME'], 'cwd':os.getcwd(),
    'root':str(root), 'account':token.read_text(),
    'bus':os.environ.get('DBUS_SESSION_BUS_ADDRESS'),
    'cpu':os.environ.get('OPENSSL_ia32cap'), 'update':os.environ.get('AGY_CLI_DISABLE_AUTO_UPDATE'),
    'leaks':{key:os.environ[key] for key in json.loads(os.environ['REMOVED']) if key in os.environ}}))
sys.exit(int(os.environ.get('FAKE_EXIT', '0')))
'''


class Accounts(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.user_home = self.root / 'home with spaces'
        self.project = self.root / 'project with spaces'
        self.user_home.mkdir()
        self.project.mkdir()
        vendor = self.root / 'vendor'
        vendor.write_text('#!' + sys.executable + '\n' + MOCK)
        vendor.chmod(0o755)
        self.launcher = self.root / 'agy'
        self.launcher.write_text('#!/usr/bin/env bash\nset -euo pipefail\nAGY_EXECUTABLE=' + shlex.quote(str(vendor)) + '\n' + SOURCE.read_text())
        self.launcher.chmod(0o755)
        for command in ('agy2', 'agy3'):
            (self.root / command).symlink_to('agy')
        self.env = dict(os.environ, HOME=str(self.user_home), REMOVED=json.dumps(REMOVED))
        self.env.pop('XDG_DATA_HOME', None)
        self.env.update({key:'foreign-account-or-key' for key in REMOVED})

    def run_account(self, command, *args, **env):
        result = subprocess.run(['bash', str(self.root / command), *args], env=self.env | env,
                                cwd=self.project, capture_output=True, text=True, timeout=10)
        return result, json.loads(result.stdout)

    def test_three_persistent_accounts_preserve_real_home_cwd_and_reset_inherited_auth(self):
        for slot, name in enumerate(('agy', 'agy2', 'agy3'), 1):
            with self.subTest(name=name):
                result, actual = self.run_account(name, 'acp', '--login', FAKE_ACCOUNT=str(slot))
                self.assertEqual(result.returncode, 0, result.stderr)
                root = self.user_home / f'.local/share/antigravity-cli/accounts/{slot}'
                self.assertEqual(actual['root'], str(root))
                self.assertEqual(actual['home'], str(self.user_home))
                self.assertEqual(actual['cwd'], str(self.project))
                self.assertEqual(actual['account'], str(slot))
                self.assertEqual(actual['args'], ['--gemini_dir',str(root),'--app_data_dir','antigravity-cli','acp','--login'])
                self.assertEqual(actual['leaks'], {})
                self.assertEqual(root.stat().st_mode & 0o777, 0o700)
                self.assertEqual((root/'antigravity-cli/antigravity-oauth-token').stat().st_mode & 0o777, 0o600)
                _, repeated = self.run_account(name, FAKE_ACCOUNT='must-not-replace')
                self.assertEqual(repeated['account'], str(slot))

    def test_nas_crypto_mask_private_keyring_and_nix_update_policy(self):
        _, actual = self.run_account('agy2', FAKE_ACCOUNT='2')
        self.assertEqual(actual['cpu'], '~0x4000000000000000')
        self.assertEqual(actual['bus'], 'disabled:')
        self.assertEqual(actual['update'], 'true')

    def test_arguments_exit_status_and_xdg_data_root(self):
        args = ('--print', "quoted 'text'; $(false)", '')
        result, actual = self.run_account('agy3', *args, FAKE_ACCOUNT='3', FAKE_EXIT='17', XDG_DATA_HOME=str(self.root/'custom data'))
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(actual['args'][4:], list(args))
        self.assertEqual(actual['root'], str(self.root/'custom data/antigravity-cli/accounts/3'))


if __name__ == '__main__':
    unittest.main()
