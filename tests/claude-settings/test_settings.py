import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

module = Path(os.environ.get('CLAUDE_SETTINGS_MODULE', Path(__file__).resolve().parents[2] / 'home/claude-settings.py'))
spec = importlib.util.spec_from_file_location('settings', module)
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)

class SettingsTest(unittest.TestCase):
    def test_migrate_preserve_and_reactivate(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            template = home / 'template.json'
            template.write_text('{"voiceEnabled":true}')
            source = home / 'checkout-settings.json'
            source.write_text('{"model":"opus[1m]","effortLevel":"xhigh"}')
            for name in ('.claude', '.claude-work'):
                (home / name).mkdir()
                (home / name / 'settings.json').symlink_to(source)
            settings.initialize(home, template)
            target = home / '.local/state/claude/settings.json'
            self.assertEqual(json.loads(target.read_text())['model'], 'opus[1m]')
            # Simulate Claude's rename through its one-hop writable symlink.
            replacement = target.with_suffix('.tmp')
            replacement.write_text('{"model":"fable","effortLevel":"low"}')
            replacement.replace(target)
            settings.initialize(home, template)
            self.assertEqual(json.loads((home / '.claude-work/settings.json').read_text()),
                             {'model':'fable', 'effortLevel':'low'})
            self.assertEqual(json.loads(source.read_text())['model'], 'opus[1m]')

    def test_new_home_has_no_model_or_effort_default(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            template = home / 'template.json'
            template.write_text('{"voiceEnabled":true}')
            settings.initialize(home, template)
            self.assertEqual(json.loads((home / '.claude/settings.json').read_text()), {'voiceEnabled':True})

    def test_invalid_source_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            template = home / 'template.json'; template.write_text('{}')
            seat = home / '.claude/settings.json'; seat.parent.mkdir(); seat.write_text('{broken')
            with self.assertRaises(json.JSONDecodeError): settings.initialize(home, template)
            self.assertFalse(seat.is_symlink())
            self.assertEqual(seat.read_text(), '{broken')

if __name__ == '__main__': unittest.main()
