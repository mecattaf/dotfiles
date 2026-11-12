import contextlib
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import json
import shutil
import signal
import subprocess
import sys
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
        runner.write_text('#!' + sys.executable + '\nimport os,json,sys\n'
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


class Rollover(unittest.TestCase):
    """The unattended (scheduled) rotation: dry run and the open-session refusal."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.journal = self.root / 'journal'
        self.old = self.journal / '2026/11/08'
        self.old.mkdir(parents=True)
        self.alias = self.root / 'today'
        self.alias.symlink_to(self.old)
        self.state = self.root / 'state'
        self.config = dict(journal_root=str(self.journal), today_link=str(self.alias),
                           state_dir=str(self.state), timezone='Europe/Paris')
        self.proc = self.root / 'proc'
        self.proc.mkdir()
        self.process(1, '/', 'systemd', 0)
        self.process(100, '/', 'python3', 1)
        (self.proc / 'self').symlink_to('100')
        self.next_day = datetime.fromisoformat('2026-11-09T12:00:00+00:00')

    def process(self, pid, cwd, argv0, ppid, comm=None):
        entry = self.proc / str(pid)
        entry.mkdir()
        (entry / 'cwd').symlink_to(cwd)
        (entry / 'cmdline').write_bytes(argv0.encode() + b'\0--flag\0')
        (entry / 'comm').write_text((comm or Path(argv0).name)[:15] + '\n')
        (entry / 'status').write_text(f'Name:\t{comm or argv0}\nPPid:\t{ppid}\n')

    def rotate(self, seat=None, dry_run=False, now=None):
        return module.select(self.config, seat, False, now or self.next_day,
                             dry_run=dry_run, proc_root=self.proc)

    def test_dry_run_reports_the_plan_and_writes_nothing(self):
        result = self.rotate(dry_run=True)
        self.assertEqual(result, self.journal / '2026/11/09')
        self.assertFalse(result.exists())
        self.assertEqual(self.alias.resolve(), self.old)
        self.assertFalse(self.state.exists())

    def test_open_session_in_current_day_refuses_unattended_rotation(self):
        # Claude Code runs as a wrapper whose comm is not its name; argv[0] is.
        self.process(4242, str(self.old / 'sub'), 'claude', 1, comm='.claude-wrapped')
        (self.old / 'sub').mkdir()
        for dry_run in (True, False):
            with self.assertRaises(module.Busy) as caught:
                self.rotate(dry_run=dry_run)
            self.assertIn('4242', str(caught.exception))
        self.assertEqual(self.alias.resolve(), self.old)
        self.assertFalse((self.journal / '2026/11/09').exists())

    def test_seat_launch_still_rotates_past_an_open_session(self):
        self.process(4242, str(self.old), '/nix/store/x/bin/dsh', 1, comm='MainThread')
        self.assertEqual(self.rotate('cc'), self.journal / '2026/11/09')
        self.assertEqual(self.alias.resolve(), self.journal / '2026/11/09')

    def test_shells_callers_and_other_folders_do_not_block(self):
        elsewhere = self.root / 'project'
        elsewhere.mkdir()
        self.process(200, str(self.old), 'fish', 1)
        self.process(300, str(elsewhere), 'codex', 1)
        # The worker that runs the rollover may itself sit in the day folder.
        self.process(400, str(self.old), 'claude', 1)
        (self.proc / '100' / 'status').write_text('Name:\tpython3\nPPid:\t400\n')
        self.assertEqual(self.rotate(), self.journal / '2026/11/09')
        self.assertEqual(self.alias.resolve(), self.journal / '2026/11/09')

    def test_already_rotated_is_a_no_op_even_while_busy(self):
        self.rotate()
        link_inode = self.alias.lstat().st_ino
        self.process(4242, str(self.journal / '2026/11/09'), 'claude', 1)
        self.assertEqual(self.rotate(), self.journal / '2026/11/09')
        self.assertEqual(self.alias.lstat().st_ino, link_inode)

    def test_configured_session_commands(self):
        self.config['session_commands'] = ['aider']
        self.process(4242, str(self.old), 'claude', 1)
        self.assertEqual(self.rotate(dry_run=True), self.journal / '2026/11/09')
        self.process(4343, str(self.old), '/usr/bin/aider', 1)
        with self.assertRaises(module.Busy):
            self.rotate(dry_run=True)

    def test_cli_against_a_real_open_process(self):
        config_path = self.root / 'journal-day.json'
        self.config['session_commands'] = ['journal-day-test-session']
        config_path.write_text(json.dumps(self.config))
        today = self.journal / datetime.now(ZoneInfo('Europe/Paris')).strftime('%Y/%m/%d')
        self.assertNotEqual(today, self.old)
        # A shell under an assumed argv[0], in its own group so no child outlives it.
        session = subprocess.Popen(['journal-day-test-session', '-c', 'sleep 60; :'],
                                   executable=shutil.which('sh'), cwd=self.old,
                                   start_new_session=True)

        def stop():
            with contextlib.suppress(ProcessLookupError):
                os.killpg(session.pid, signal.SIGKILL)
            session.wait()
        self.addCleanup(stop)

        def run(*args):
            return subprocess.run([str(SOURCE), '--config', str(config_path), *args],
                                  capture_output=True, text=True, timeout=15)

        for args in ((), ('--dry-run',)):
            busy = run(*args)
            self.assertEqual(busy.returncode, 75, busy.stderr)
            self.assertIn('journal-day-test-session', busy.stderr)
        self.assertEqual(self.alias.resolve(), self.old)
        self.assertFalse(today.exists())
        stop()
        planned = run('--dry-run')
        self.assertEqual((planned.returncode, planned.stdout.strip()), (0, str(today)))
        self.assertFalse(today.exists())
        # Refused runs and the dry run record nothing; only the lock file exists.
        self.assertFalse((self.state / 'state.json').exists())
        done = run()
        self.assertEqual((done.returncode, done.stdout.strip()), (0, str(today)))
        self.assertEqual(self.alias.resolve(), today)


if __name__ == '__main__':
    unittest.main()
