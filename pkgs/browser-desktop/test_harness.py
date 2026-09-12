"""Small regression checks for the adapter's ownership and identity contract."""
import asyncio
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
import harness
import menu
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
                async with TestClient(TestServer(menu.make_app(root, 'http://browser.internal'))) as client:
                    headers = {'Origin': 'http://browser.internal', 'X-Fara-Control': '1'}
                    listing = await (await client.get('/profiles')).json()
                    self.assertEqual(listing['profiles'][0]['google_account'], 'test@example.test')
                    for invalid_headers in ({}, {'Origin': 'http://other.test', 'X-Fara-Control': '1'}, {'Origin': 'http://browser.internal'}):
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


if __name__ == '__main__':
    unittest.main()
