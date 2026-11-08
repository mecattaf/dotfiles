import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import json
import shutil
import subprocess
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

SOURCE = Path(__file__).resolve().parents[2] / 'home/dot_local/bin/journal-day'
loader = importlib.machinery.SourceFileLoader('journal_day', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class JournalDay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.journal = self.root / 'journal'
        self.journal.mkdir()
        self.alias = self.root / 'today'
        self.config = dict(journal_root=str(self.journal), today_link=str(self.alias),
                           state_dir=str(self.root / 'state'), timezone='Europe/Paris')

    def choose(self, day, seat=None, resume=False):
        return module.select(self.config, seat, resume, datetime.fromisoformat(day))

    def test_paris_midnight_and_physical_path(self):
        result = self.choose('2026-11-08T23:30:00+00:00', 'cc')
        self.assertEqual(result, self.journal / '2026/11/09')
        self.assertEqual(self.alias.resolve(), result)

    def test_rollover_keeps_content_cwd_and_separate_resume_seats(self):
        before = self.choose('2026-11-08T12:00:00+00:00', 'cc')
        (before / 'draft.md').write_text('original')
        saved_inode = before.stat().st_ino
        after = self.choose('2026-11-09T12:00:00+00:00', 'cc2')
        self.assertEqual(self.choose('2026-11-10T12:00:00+00:00', 'cc', True), before)
        self.assertEqual(self.choose('2026-11-10T12:00:00+00:00', 'cc2', True), after)
        self.assertEqual(self.alias.resolve(), after)
        self.assertEqual(before.stat().st_ino, saved_inode)
        self.assertEqual((before / 'draft.md').read_text(), 'original')

    def test_resume_falls_back_to_legacy_alias_without_rotation(self):
        old = self.journal / '2026/11/03'
        old.mkdir(parents=True)
        self.alias.symlink_to(old)
        self.choose('2026-11-08T12:00:00+00:00')
        self.assertEqual(self.choose('2026-11-09T12:00:00+00:00', 'cc2', True), old)
        self.assertEqual(self.alias.resolve(), self.journal / '2026/11/08')

    def test_idempotent_and_no_generated_brief(self):
        first = self.choose('2026-11-08T12:00:00+00:00')
        link_inode = self.alias.lstat().st_ino
        self.assertEqual(self.choose('2026-11-08T13:00:00+00:00'), first)
        self.assertEqual(self.alias.lstat().st_ino, link_inode)
        self.assertEqual(list(first.iterdir()), [])

    def test_existing_directory_and_foreign_alias_are_preserved(self):
        self.alias.mkdir()
        marker = self.alias / 'important.md'
        marker.write_text('keep')
        with self.assertRaises(ValueError):
            self.choose('2026-11-08T12:00:00+00:00')
        self.assertEqual(marker.read_text(), 'keep')
        marker.unlink()
        self.alias.rmdir()
        self.alias.symlink_to(self.root)
        with self.assertRaises(ValueError):
            self.choose('2026-11-08T12:00:00+00:00')
        self.assertEqual(self.alias.resolve(), self.root)

    def test_configured_timezone(self):
        self.config['timezone'] = 'America/New_York'
        self.assertEqual(self.choose('2026-11-09T01:00:00+00:00'), self.journal / '2026/11/08')

    def test_concurrent_fresh_launches_share_day_without_lost_seats(self):
        config_path = self.root / 'journal-day.json'
        config_path.write_text(json.dumps(self.config))
        processes = [subprocess.Popen([str(SOURCE), '--config', str(config_path),
                                      '--seat', 'seat' + str(i)], stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True) for i in range(8)]
        results = []
        for process in processes:
            out, err = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, err)
            results.append(out.strip())
        self.assertEqual(len(set(results)), 1)
        self.assertEqual(self.alias.resolve(), Path(results[0]))
        state = json.loads((self.root / 'state/state.json').read_text())
        self.assertEqual(len(state['seats']), 8)

    def test_real_fish_launchers_preserve_projects_overrides_seats_and_resume(self):
        fish = shutil.which('fish')
        self.assertIsNotNone(fish, 'fish is required for actual launcher integration')
        source = SOURCE.parents[2] / 'dot_config/fish/config.fish'
        text = source.read_text()
        # Extract exactly the named function, stopping at the next declaration.
        # Do not source the surrounding interactive config or a trailing range.
        function = text.split('function __claude_seat ', 1)[1].split('function cc;', 1)[0]
        function = 'function __claude_seat ' + function
        self.assertTrue(function.rstrip().endswith('end'))
        self.assertNotIn('atuin', function)
        self.assertEqual(function.count('function '), 1)
        fixture = self.root / 'seat.fish'
        fixture.write_text(function)
        tools = self.root / 'bin'
        tools.mkdir()
        (tools / 'journal-day').symlink_to(SOURCE)
        runner = tools / 'claude'
        runner.write_text('#!/usr/bin/env python3\nimport os,json,sys\n'
                          'open(os.environ["SEAT_RESULT"],"w").write(json.dumps('
                          '{"cwd":os.getcwd(),"config":os.environ.get("CLAUDE_CONFIG_DIR"),'
                          '"args":sys.argv[1:]}))\n')
        runner.chmod(0o700)
        config_path = self.root / 'journal-day.json'
        config_path.write_text(json.dumps(self.config))
        result_path = self.root / 'result.json'
        env = dict(os.environ, HOME=str(self.root), JOURNAL_DAY_CONFIG=str(config_path),
                   SEAT_RESULT=str(result_path), PATH=str(tools) + ':' + os.environ['PATH'],
                   CLAUDE_CONFIG_DIR='inherited-seat')
        env.pop('AGENCY_KITTY_SESSION', None)
        env.pop('AGENCY_KITTY_COMMAND', None)

        def launch(cwd, seat='cc', args='', envelope=None):
            command = f'set -gx CLAUDE_ENVELOPE "{envelope or self.alias}"; '
            command += f'source "{fixture}"; __claude_seat {seat} '
            command += ('""' if seat == 'cc' else '"' + str(self.root / '.claude-work') + '"')
            subprocess.run([fish, '--no-config', '-c', command + ' ' + args],
                           cwd=cwd, env=env, check=True, capture_output=True, text=True)
            return json.loads(result_path.read_text())

        old = self.journal / '2026/11/03'
        old.mkdir(parents=True)
        self.alias.symlink_to(old)
        fresh = launch(self.root)
        expected = self.journal / datetime.now(ZoneInfo('Europe/Paris')).strftime('%Y/%m/%d')
        self.assertEqual(fresh['cwd'], str(expected))
        self.assertIsNone(fresh['config'])
        self.assertEqual(launch(self.root, args='--continue')['cwd'], str(expected))
        self.assertEqual(launch(self.root, 'cc2', '--resume example')['cwd'], str(old))
        self.assertEqual(launch(self.root, 'cc2')['config'], str(self.root / '.claude-work'))
        custom = self.root / 'custom'
        custom.mkdir()
        self.assertEqual(launch(self.root, envelope=custom)['cwd'], str(custom))
        project = self.root / 'project'
        project.mkdir()
        self.assertEqual(launch(project, args='--resume project-id')['cwd'], str(project))


if __name__ == '__main__':
    unittest.main()
