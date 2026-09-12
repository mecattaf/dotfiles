"""Small regression checks for the adapter's ownership and identity contract."""
import asyncio
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
from contextlib import ExitStack
import harness
import menu
import session
import subprocess
from aiohttp.test_utils import TestClient, TestServer


class Contract(unittest.TestCase):
    def test_all_three_model_sizes_are_explicit_in_status(self):
        for model in ('Fara1.5-4B', 'Fara1.5-9B', 'Fara1.5-27B'):
            with self.subTest(model=model), tempfile.TemporaryDirectory() as root:
                args = SimpleNamespace(model=model, endpoint='http://127.0.0.1:8733/v1',
                    chrome_data_dir=Path(root), profile='Default', id='selection-test')
                with patch.object(harness, 'session_environment', return_value={}):
                    state = harness.Runner(args).state()
                self.assertEqual(state['model'], model)
                self.assertEqual(state['endpoint'], args.endpoint)

    def test_profiles_are_directory_identities_not_labels(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'Default').mkdir()
            (root / 'Profile 2').mkdir()
            (root / 'Local State').write_text(json.dumps({'profile': {
                'last_used': 'Profile 2', 'info_cache': {
                    'Default': {'name': 'Work', 'user_name': 'first@example.test'},
                    'Profile 2': {'name': 'Work', 'user_name': 'second@example.test'},
                    'Profile 9': {'name': 'Old'},
                }}}))
            chosen = harness.selected_profile(root, 'Profile 2')
            self.assertEqual(chosen['google_account'], 'second@example.test')
            self.assertTrue(chosen['last_used_by_chrome'])
            self.assertFalse(harness.chrome_profiles(root)[2]['exists'])
            self.assertIsNone(harness.selected_profile(root, 'Missing')['google_account'])

    def test_takeover_prevents_further_input(self):
        async def exercise():
            env = harness.NoVNCEnvironment(SimpleNamespace(owner='human'))
            env.page = AsyncMock()
            with self.assertRaises(asyncio.CancelledError):
                await env.left_click(100, 100)
            with self.assertRaises(asyncio.CancelledError):
                await env.type('must not reach desktop')
            env.page.mouse.click.assert_not_called()
            env.page.evaluate.assert_not_called()
        asyncio.run(exercise())

    def test_sway_pid_proves_existing_chrome_display(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'SingletonLock').symlink_to('coordinator-12345')
            with patch.object(harness, 'windows', return_value={4: {'pid': 12345}}):
                harness.ensure_chrome_on_display(root, {'WAYLAND_DISPLAY': 'wayland-test'})

    def test_replay_orders_native_and_lifecycle_events(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'solver_log').mkdir()
            (root / 'solver_log/events.jsonl').write_text(json.dumps({
                'timestamp': '2026-09-12T12:00:00+00:00', 'type': 'observation',
                'screenshot_path': 'screen.png', 'content': '</script>'}) + '\n')
            (root / 'lifecycle.jsonl').write_text(json.dumps({'time': 1, 'event': 'started'}) + '\n')
            harness.make_replay(root)
            replay = (root / 'replay.html').read_text()
            self.assertLess(replay.index('"started"'), replay.index('"observation"'))
            self.assertIn('"image": "screen.png"', replay)
            self.assertIn('\\u003c/script>', replay)


class ChromeMenu(unittest.IsolatedAsyncioTestCase):
    async def test_requests_validate_origin_identity_and_desktop_ownership(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'Default').mkdir()
            (root / 'Local State').write_text(json.dumps({'profile': {'info_cache': {
                'Default': {'name': 'Test', 'user_name': 'test@example.test'}}}}))
            with patch.object(menu, 'RUNTIME', root), patch.object(menu, 'keyring_state', return_value='unlocked'), patch.object(menu.subprocess, 'run') as launch:
                async with TestClient(TestServer(menu.make_app(root, 'https://browser.internal'))) as client:
                    headers = {'Origin': 'https://browser.internal', 'X-Fara-Control': '1'}
                    listing = await (await client.get('/profiles')).json()
                    self.assertEqual(listing['profiles'][0]['google_account'], 'test@example.test')
                    for invalid_headers in ({}, {'Origin': 'http://other.test', 'X-Fara-Control': '1'}, {'Origin': 'https://browser.internal'}):
                        response = await client.post('/open', json={'profile': 'Default'}, headers=invalid_headers)
                        self.assertEqual(response.status, 403)
                    for body in ({'profile': '../Default'}, {'profile': 'Missing'}, []):
                        response = await client.post('/open', json=body, headers=headers)
                        self.assertEqual(response.status, 409)
                    with menu.desktop_operation():
                        listing = await (await client.get('/profiles')).json()
                        self.assertTrue(listing['busy'])
                        for action in ('open', 'unlock'):
                            response = await client.post('/' + action, json={'profile': 'Default'}, headers=headers)
                            self.assertEqual(response.status, 409)
                    launch.assert_not_called()


class SessionCleanup(unittest.TestCase):
    def test_failed_start_does_not_leave_a_restart_loop(self):
        with tempfile.TemporaryDirectory() as root, patch.object(session, 'RUNTIME', Path(root)), patch.object(session.subprocess, 'run', side_effect=[subprocess.CalledProcessError(1, 'systemctl'), None]) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                session.start_desktop()
            self.assertEqual(command.call_args_list[-1].args[0],
                             ['systemctl','--user','stop','browser-desktop.service'])

    def test_grace_reconnect_active_task_and_abandoned_task(self):
        with tempfile.TemporaryDirectory() as root, ExitStack() as stack:
            root = Path(root)
            stack.enter_context(patch.object(menu, 'RUNTIME', root))
            for name, filename in [('MANUAL','manual-session'), ('NO_VIEWERS','no-viewers-since'),
                                   ('TASK_LEASE','task-session.json'), ('TASK_MODEL','task-model-started')]:
                stack.enter_context(patch.object(menu, name, root/filename))
            stop = stack.enter_context(patch.object(menu, 'stop_desktop'))
            command = stack.enter_context(patch.object(menu.subprocess, 'run', return_value=SimpleNamespace(stdout='[]')))
            clock = stack.enter_context(patch.object(menu.time, 'monotonic', return_value=1000))
            (root/'environment').touch(); menu.MANUAL.touch()
            menu.reap_abandoned_task()
            clock.return_value=1299; menu.reap_abandoned_task(); stop.assert_not_called()
            command.return_value.stdout='[{"id":"viewer"}]'
            menu.reap_abandoned_task(); self.assertFalse(menu.NO_VIEWERS.exists())
            command.return_value.stdout='[]'
            clock.return_value=1400; menu.reap_abandoned_task()
            clock.return_value=1700
            with menu.desktop_operation():
                menu.reap_abandoned_task()
            stop.assert_not_called(); self.assertFalse(menu.NO_VIEWERS.exists())
            menu.reap_abandoned_task()
            clock.return_value=2000; menu.reap_abandoned_task(); stop.assert_called_once()
            stop.reset_mock(); menu.MANUAL.unlink()
            menu.reap_abandoned_task(); stop.assert_called_once()

    def test_abandoned_task_preserves_baseline_windows(self):
        with tempfile.TemporaryDirectory() as root, ExitStack() as stack:
            root = Path(root)
            for name, value in [('RUNTIME',root), ('MANUAL',root/'manual'),
                                ('NO_VIEWERS',root/'idle'), ('TASK_LEASE',root/'task'), ('TASK_MODEL',root/'model')]:
                stack.enter_context(patch.object(menu, name, value))
            (root/'environment').touch(); menu.MANUAL.touch()
            menu.TASK_LEASE.write_text(json.dumps({'baseline':[1], 'unit':'browser-chrome-task-test.service'}))
            stack.enter_context(patch.object(menu, 'session_environment', return_value={'SWAYSOCK':'test'}))
            stack.enter_context(patch.object(menu, 'windows', side_effect=[{1:{},2:{}}, {1:{}}]))
            command=stack.enter_context(patch.object(menu.subprocess, 'run', return_value=SimpleNamespace(stdout='[{"id":"viewer"}]')))
            stop=stack.enter_context(patch.object(menu, 'stop_desktop'))
            menu.reap_abandoned_task()
            calls=[call.args[0] for call in command.call_args_list]
            self.assertIn(['swaymsg','-s','test','[con_id=2] kill'],calls)
            self.assertNotIn(['swaymsg','-s','test','[con_id=1] kill'],calls)
            self.assertFalse(menu.TASK_LEASE.exists()); stop.assert_not_called()


if __name__ == '__main__':
    unittest.main()
