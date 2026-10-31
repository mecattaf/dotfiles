import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import shutil
import subprocess

import utility_storage as s
class StorageTests(unittest.TestCase):
    def test_local_config_and_override(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);config=root/'paths.json';config.write_text(json.dumps({'paper':str(root/'private queue')}))
            with patch.dict(os.environ,{'UTILITY_STORAGE_CONFIG':str(config)},clear=True):
                self.assertEqual(s.storage_root('paper'),root/'private queue')
                with patch.dict(os.environ,{'PAPER_ROOT':str(root/'override')}):self.assertEqual(s.storage_root('paper'),root/'override')
    def test_reject_unsafe_config(self):
        for value in ['relative','/','/tmp/bad\n[Unit]', '/tmp/space at end ']:
            with self.subTest(value=value),patch.dict(os.environ,{'PAPER_ROOT':value},clear=True):
                with self.assertRaises(ValueError):s.storage_root('paper')
    def test_watcher_replaces_default_and_escapes_specifiers(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);config=root/'config';private=root/'queue %name\\quoted"'
            with patch.dict(os.environ,{'XDG_CONFIG_HOME':str(config),'PAPER_ROOT':str(private)},clear=True):
                s.prepare(['paper'])
            watcher=config/'systemd/user/paper-daemon.path.d/storage.conf'
            escaped = str(private).replace('%', '%%')
            self.assertEqual(watcher.read_text(),'[Path]\nPathChanged=\nPathChanged='+escaped+'/intake\n')
            self.assertTrue((private/'intake').is_dir());self.assertEqual(watcher.stat().st_mode&0o777,0o600)
    def test_default_is_xdg_data(self):
        with patch.dict(os.environ,{'XDG_DATA_HOME':'/tmp/data','UTILITY_STORAGE_CONFIG':'/nonexistent/settings'},clear=True):
            self.assertEqual(s.storage_root('speech'),Path('/tmp/data/utility-data/speech'))
    def test_invalid_config_never_creates_intake_or_overwrites_watcher(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = root / 'paths.json'
            watcher = root / 'systemd/user/paper-daemon.path.d/storage.conf'
            watcher.parent.mkdir(parents=True)
            watcher.write_text('existing setting\n')
            with patch.dict(os.environ, {'UTILITY_STORAGE_CONFIG': str(config),
                                        'XDG_CONFIG_HOME': str(root)}, clear=True):
                for value in ([], {'paper': 'relative'}, {'paper': 42}):
                    config.write_text(json.dumps(value))
                    with self.subTest(value=value), self.assertRaises(ValueError):
                        s.prepare(['paper'])
                    self.assertEqual(watcher.read_text(), 'existing setting\n')
    @unittest.skipUnless(shutil.which('systemd-analyze'), 'systemd unit parser unavailable')
    def test_generated_path_is_accepted_by_systemd(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(root),
                                        'PAPER_ROOT': str(root / 'queue %named')}, clear=True):
                s.prepare(['paper'])
            unit = root / 'paper-daemon.path'
            unit.write_text('[Unit]\nDescription=Storage watcher parser test\n' +
                            (root / 'systemd/user/paper-daemon.path.d/storage.conf').read_text())
            (root / 'paper-daemon.service').write_text(
                '[Service]\nType=oneshot\nExecStart=' + shutil.which('true') + '\n')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            result = subprocess.run(['systemd-analyze', '--user', 'verify', '--man=no',
                                     '--generators=no', str(unit)], capture_output=True, text=True,
                                    env={**os.environ, 'XDG_RUNTIME_DIR': str(runtime)})
            self.assertEqual(result.returncode, 0, result.stderr)
if __name__=='__main__':unittest.main()
