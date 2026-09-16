"""Small regression checks for the desktop's ownership and identity contract."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from contextlib import ExitStack
import menu
import session
import subprocess
from aiohttp.test_utils import TestClient, TestServer


class Contract(unittest.TestCase):
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
            profiles = {p['directory']: p for p in session.chrome_profiles(root)}
            self.assertEqual(profiles['Profile 2']['google_account'], 'second@example.test')
            self.assertTrue(profiles['Profile 2']['last_used_by_chrome'])
            self.assertFalse(profiles['Default']['last_used_by_chrome'])
            self.assertFalse(profiles['Profile 9']['exists'])

    def test_sway_pid_proves_existing_chrome_display(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'SingletonLock').symlink_to('coordinator-12345')
            with patch.object(session, 'windows', return_value={4: {'pid': 12345}}):
                session.ensure_chrome_on_display(root, {'WAYLAND_DISPLAY': 'wayland-test'})


class ChromeMenu(unittest.IsolatedAsyncioTestCase):
    async def test_unavailable_keyring_does_not_offer_a_password_fix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Default').mkdir()
            (root / 'Local State').write_text(json.dumps({'profile': {'info_cache': {'Default': {'name': 'Test'}}}}))
            with patch.object(menu, 'RUNTIME', root), patch.object(menu, 'keyring_state', return_value='unavailable'), patch.object(menu, 'start_desktop') as start:
                with self.assertRaisesRegex(ValueError, 'session needs repair'):
                    menu.open_window(root, 'Default')
                start.assert_not_called()

    async def test_requests_validate_origin_identity_and_desktop_ownership(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'Default').mkdir()
            (root / 'Local State').write_text(json.dumps({'profile': {'info_cache': {
                'Default': {'name': 'Test', 'user_name': 'test@example.test'}}}}))
            with patch.object(menu, 'RUNTIME', root), patch.object(menu, 'keyring_state', return_value='unlocked'), patch.object(menu.subprocess, 'run') as launch:
                async with TestClient(TestServer(menu.make_app(root, 'https://browser.internal'))) as client:
                    headers = {'Origin': 'https://browser.internal', 'X-Desktop-Control': '1'}
                    listing = await (await client.get('/profiles')).json()
                    self.assertEqual(listing['profiles'][0]['google_account'], 'test@example.test')
                    for invalid_headers in ({}, {'Origin': 'http://other.test', 'X-Desktop-Control': '1'}, {'Origin': 'https://browser.internal'}):
                        response = await client.post('/open', json={'profile': 'Default'}, headers=invalid_headers)
                        self.assertEqual(response.status, 403)
                    for body in ({'profile': '../Default'}, {'profile': 'Missing'}, []):
                        response = await client.post('/open', json=body, headers=headers)
                        self.assertEqual(response.status, 409)
                    with menu.desktop_operation():
                        listing = await (await client.get('/profiles')).json()
                        self.assertTrue(listing['busy'])
                        for action in ('open', 'unlock', 'end'):
                            response = await client.post('/' + action, json={'profile': 'Default'}, headers=headers)
                            self.assertEqual(response.status, 409)
                    launch.assert_not_called()


class SessionCleanup(unittest.TestCase):
    def test_closed_window_waits_for_browser_exit_before_stopping_display(self):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            stack.enter_context(patch.object(session, 'RUNTIME', root))
            stack.enter_context(patch.object(session, 'MANUAL', root / 'manual'))
            stack.enter_context(patch.object(session, 'NO_VIEWERS', root / 'idle'))
            command = stack.enter_context(patch.object(session.subprocess, 'run',
                side_effect=[SimpleNamespace(stdout='active\n'), SimpleNamespace(stdout=''), None]))
            delay = stack.enter_context(patch.object(session.time, 'sleep'))
            session.stop_desktop(wait_for_chrome=True)
            self.assertEqual(command.call_count, 3)
            self.assertEqual(command.call_args_list[-1].args[0][2], 'stop')
            delay.assert_called_once_with(.1)

    def test_failed_start_does_not_leave_a_restart_loop(self):
        with tempfile.TemporaryDirectory() as root, patch.object(session, 'RUNTIME', Path(root)), patch.object(session.subprocess, 'run', side_effect=[subprocess.CalledProcessError(1, 'systemctl'), None]) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                session.start_desktop()
            self.assertEqual(command.call_args_list[-1].args[0],
                             ['systemctl','--user','stop','browser-desktop.service'])

    def test_grace_reconnect_busy_menu_and_unmanaged_desktop(self):
        with tempfile.TemporaryDirectory() as root, ExitStack() as stack:
            root = Path(root)
            stack.enter_context(patch.object(menu, 'RUNTIME', root))
            for name, filename in [('MANUAL','manual-session'), ('NO_VIEWERS','no-viewers-since')]:
                stack.enter_context(patch.object(menu, name, root/filename))
            stop = stack.enter_context(patch.object(menu, 'stop_desktop'))
            command = stack.enter_context(patch.object(menu.subprocess, 'run', return_value=SimpleNamespace(stdout='[]')))
            clock = stack.enter_context(patch.object(menu.time, 'monotonic', return_value=1000))
            (root/'environment').touch(); menu.MANUAL.touch()
            menu.expire_idle_session()
            clock.return_value=1299; menu.expire_idle_session(); stop.assert_not_called()
            command.return_value.stdout='[{"id":"viewer"}]'
            menu.expire_idle_session(); self.assertFalse(menu.NO_VIEWERS.exists())
            command.return_value.stdout='[]'
            clock.return_value=1400; menu.expire_idle_session()
            clock.return_value=1700
            with menu.desktop_operation():
                menu.expire_idle_session()
            stop.assert_not_called(); self.assertFalse(menu.NO_VIEWERS.exists())
            menu.expire_idle_session()
            clock.return_value=1999; menu.expire_idle_session(); stop.assert_not_called()
            clock.return_value=2000; menu.expire_idle_session(); stop.assert_called_once()
            stop.reset_mock(); menu.MANUAL.unlink()
            menu.expire_idle_session(); stop.assert_called_once()


if __name__ == '__main__':
    unittest.main()
