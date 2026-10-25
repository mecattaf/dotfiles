"""Fixture-only Hyprland backend checks; run through runtime-test with launchers."""
import json
import contextlib
import io
import os
import shlex
import subprocess
import unittest
from unittest.mock import patch

from test_sway_picker import picker, view, ws, root, SNAPSHOT, workspace_form


class HyprlandPicker(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {
            'HYPRLAND_INSTANCE_SIGNATURE': 'isolated-fixture', 'SWAYSOCK': '',
            'XDG_CURRENT_DESKTOP': 'Hyprland', 'HERDR_SWAY_LOCAL': '0',
            'HERDR_SWAY_SEAT': 'client',
        })
        environment.start()
        self.addCleanup(environment.stop)

    def test_sway_fallback_wins_when_current_session_is_sway(self):
        with patch.dict(os.environ, {'SWAYSOCK': '/fake', 'XDG_CURRENT_DESKTOP': 'sway-physical'}):
            self.assertFalse(picker.hyprland())

    def test_normalized_tree_preserves_ids_focus_and_dynamic_tags(self):
        responses = {
            'workspaces': [{'id': 2, 'name': '2: Work'}, {'id': -99, 'name': 'special:herdr-parked'}],
            'clients': [
                {'address': '0xab', 'class': 'herdr-projector', 'title': 'strix: Work', 'pid': 123,
                 'workspace': {'id': 2}, 'tags': ['herdr-slot-2*']},
                {'address': '0xac', 'class': 'herdr-projector', 'pid': 124,
                 'workspace': {'id': -99}, 'tags': ['herdr-slot-3*', 'herdr-closed-25*']},
            ],
            'activeworkspace': {'id': 2, 'name': '2: Work'},
            'activewindow': {'address': '0xab'},
        }
        def run(argv):
            return subprocess.CompletedProcess(argv, 0, json.dumps(responses[argv[-1]]), '')
        with patch.object(picker, 'run', side_effect=run):
            data = picker.tree()
        projectors = picker.projectors(data)
        self.assertEqual(len(projectors), 2)
        self.assertEqual(projectors[0][0]['id'], 171)
        self.assertTrue(projectors[0][0]['focused'])
        self.assertEqual(picker.slot_of(*projectors[1]), 3)
        self.assertEqual(projectors[1][1]['name'], '__i3_scratch')

    def test_dispatch_is_argv_not_shell_or_batch(self):
        name = '3 3: a; exec bad $(bad) "literal"'
        answer = subprocess.CompletedProcess([], 0, 'ok\n', '')
        with patch.object(picker, 'run', return_value=answer) as run:
            picker.hypr_dispatch('renameworkspace', name)
        run.assert_called_once_with(['hyprctl', 'dispatch', 'renameworkspace', name])

    def test_dispatch_protocol_error_is_not_success(self):
        answer = subprocess.CompletedProcess([], 0, 'Invalid dispatcher', '')
        with patch.object(picker, 'run', return_value=answer):
            with self.assertRaisesRegex(picker.BridgeError, 'refused'):
                picker.hypr_dispatch('workspace', '2')

    def test_tag_selector_uses_space_and_refuses_missing_window(self):
        for clients, succeeds in [([], False), ([{'address': '0xab'}], True)]:
            with self.subTest(clients=clients):
                replies = [subprocess.CompletedProcess([], 0, json.dumps(clients), ''),
                           subprocess.CompletedProcess([], 0, 'ok', '')]
                with patch.object(picker, 'run', side_effect=replies) as run:
                    if succeeds:
                        picker.mark_view(171, 'herdr-slot-2')
                        self.assertEqual(run.call_args.args[0],
                                         ['hyprctl', 'dispatch', 'tagwindow', '+herdr-slot-2 address:0xab'])
                    else:
                        with self.assertRaisesRegex(picker.BridgeError, 'closed'):
                            picker.mark_view(171, 'herdr-slot-2')
                        run.assert_called_once_with(['hyprctl', '-j', 'clients'])

    def test_focus_cli_checks_expected_pid_without_remote_api(self):
        node = view(171, slot=2)
        for expected_pid in [node['pid'], 999]:
            with self.subTest(expected_pid=expected_pid), \
                    patch.object(picker.sys, 'argv', ['herdr-picker', '--focus-view', '171',
                                                     '--expect-pid', str(expected_pid)]), \
                    patch.object(picker, 'desktop_lock', return_value=contextlib.nullcontext()), \
                    patch.object(picker, 'tree', return_value=root(ws(2, [node]))), \
                    patch.object(picker, 'focus_view') as focus, \
                    patch.object(picker, 'remote_snapshot') as remote:
                if expected_pid == node['pid']:
                    picker.main()
                    focus.assert_called_once_with(171, expected=node)
                else:
                    with self.assertRaisesRegex(picker.BridgeError, 'identity changed'):
                        picker.main()
                    focus.assert_not_called()
                remote.assert_not_called()

    def test_json_rows_include_identity_for_native_picker(self):
        node = view(171, slot=2)
        output = io.StringIO()
        with patch.object(picker.sys, 'argv', ['herdr-picker', '--json']), \
                patch.object(picker, 'tree', return_value=root(ws(2, [node]))), \
                patch.object(picker, 'remote_snapshot', return_value=SNAPSHOT), \
                contextlib.redirect_stdout(output):
            picker.main()
        row = next(row for row in json.loads(output.getvalue()) if row['action'] == ['view', 171])
        self.assertEqual(row['view'], {'pid': node['pid'], 'app_id': node['app_id']})

    def test_command_failure_is_not_swallowed(self):
        answer = subprocess.CompletedProcess([], 1, '', 'connection refused')
        with patch.object(picker.subprocess, 'run', return_value=answer):
            with self.assertRaisesRegex(picker.BridgeError, 'connection refused'):
                picker.hypr_dispatch('workspace', '2')

    def test_stale_or_reused_address_does_not_focus_anything(self):
        for data, expected in [(root(ws(1)), None),
                               (root(ws(1, [view(10)])), {'pid': 999, 'app_id': 'herdr-projector'})]:
            with self.subTest(expected=expected), patch.object(picker, 'tree', return_value=data), \
                    patch.object(picker, 'hypr_dispatch') as dispatch:
                with self.assertRaises(picker.BridgeError):
                    picker.focus_view(10, expected)
                dispatch.assert_not_called()

    def test_focus_targets_exact_address_without_herdr_api(self):
        node = view(171, slot=2)
        with patch.object(picker, 'tree', return_value=root(ws(2, [node]))), \
                patch.object(picker, 'hypr_dispatch') as dispatch, patch.object(picker, 'remote_snapshot') as remote:
            picker.focus_view(171, node)
        dispatch.assert_called_once_with('focuswindow', 'address:0xab')
        remote.assert_not_called()

    def test_close_parks_projector_and_never_closes_its_window(self):
        data = root(ws(2, [view(171, slot=2, focused=True), view(172, app='google-chrome')]), ws(10))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker.time, 'time_ns', return_value=42), \
                patch.object(picker, 'hypr_dispatch') as dispatch:
            picker.workspace_action('close')
        calls = [c.args for c in dispatch.call_args_list]
        self.assertIn(('movetoworkspacesilent', 'special:herdr-parked,address:0xab'), calls)
        self.assertIn(('closewindow', 'address:0xac'), calls)
        self.assertNotIn(('closewindow', 'address:0xab'), calls)
        self.assertEqual(calls[-1], ('workspace', '10'))

    def test_failed_parking_stops_before_closing_other_views(self):
        data = root(ws(2, [view(172, app='google-chrome'), view(171, slot=2, focused=True)]))
        calls = []
        def dispatch(action, argument):
            calls.append((action, argument))
            if action == 'movetoworkspacesilent':
                raise picker.BridgeError('cannot park')
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'hypr_dispatch', side_effect=dispatch):
            with self.assertRaisesRegex(picker.BridgeError, 'cannot park'):
                picker.workspace_action('close')
        self.assertFalse(any(action in ('closewindow', 'workspace') for action, _ in calls))

    def test_invalid_parking_slot_refuses_before_any_mutation(self):
        data = root(ws(10, [view(172, app='google-chrome'), view(171, focused=True)]))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'hypr_dispatch') as dispatch:
            with self.assertRaisesRegex(picker.BridgeError, 'dedicated workspace'):
                picker.workspace_action('close')
        dispatch.assert_not_called()

    def test_restore_uses_tags_and_keeps_custom_name(self):
        node = view(171, slot=3)
        node['marks'] += ['herdr-name-' + '3: Work'.encode().hex(), 'herdr-closed-42']
        data = root(ws(-1, [node], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'hypr_dispatch') as dispatch:
            picker.focus_view(171)
        self.assertEqual([call.args for call in dispatch.call_args_list], [
            ('workspace', '3'), ('movetoworkspacesilent', '3,address:0xab'),
            ('settiled', 'address:0xab'), ('renameworkspace', '3 3: Work'),
            ('focuswindow', 'address:0xab'), ('tagwindow', '-herdr-closed-42 address:0xab'),
        ])

    def test_duplicate_parked_slot_refuses_to_merge(self):
        data = root(ws(3, [view(170, slot=3)]), ws(-1, [view(171, slot=3)], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'hypr_dispatch') as dispatch:
            with self.assertRaisesRegex(picker.BridgeError, 'already owns'):
                picker.focus_view(171)
        dispatch.assert_not_called()

    def test_existing_projector_never_creates_new_session_or_sends_keys(self):
        node = view(171, slot=2, focused=True)
        with patch.object(picker, 'tree', return_value=root(ws(2, [node]))), \
                patch.object(picker, 'hypr_dispatch') as dispatch, patch.object(picker, 'kitty') as kitty:
            result, created = picker.ensure_projector()
        self.assertFalse(created)
        self.assertEqual(result['id'], 171)
        kitty.assert_not_called()
        self.assertFalse(any(call.args[0] == 'exec' for call in dispatch.call_args_list))

    def test_new_projector_quotes_launcher_and_never_types_without_verified_form(self):
        data = root(ws(1, focused=True))
        created = root(ws(1, [view(171, focused=True)]))
        def immediate(callback, seconds, message):
            result = callback()
            if not result:
                raise picker.BridgeError(message)
            return result
        launcher = '/test path/a; printf bad'
        with patch.dict(os.environ, {'HERDR_PROJECTOR': launcher}), \
                patch.object(picker, 'tree', side_effect=[data, created]), \
                patch.object(picker, 'client_ready', return_value=True), \
                patch.object(picker, 'wait_for', side_effect=immediate), \
                patch.object(picker, 'hypr_dispatch') as dispatch, \
                patch.object(picker, 'kitty', return_value='ordinary pane') as kitty:
            with self.assertRaisesRegex(picker.BridgeError, 'form did not appear'):
                picker.ensure_projector()
        launched = next(call.args[1] for call in dispatch.call_args_list if call.args[0] == 'exec')
        self.assertEqual(shlex.split(launched), ['kitty', '--class', 'herdr-projector', '-e', launcher])
        self.assertFalse(any(call.args[1] == 'send-text' or call.args[-1] == 'enter' for call in kitty.call_args_list))

    def test_remote_snapshot_remains_read_only_and_bounded(self):
        answer = subprocess.CompletedProcess([], 0, json.dumps(SNAPSHOT), '')
        with patch.object(picker, 'run', return_value=answer) as run:
            picker.remote_snapshot()
        argv = run.call_args.args[0]
        self.assertEqual(argv[0], 'ssh')
        self.assertEqual(argv[-1], 'herdr api snapshot')
        self.assertIn('-n', argv)
        self.assertEqual(run.call_args.kwargs['timeout'], 6)

    def test_invalid_remote_target_never_invokes_ssh(self):
        with patch.dict(os.environ, {'HERDR_PROJECTOR_TARGET': '-oProxyCommand=bad'}), \
                patch.object(picker, 'run') as run:
            with self.assertRaisesRegex(picker.BridgeError, 'Invalid HERDR'):
                picker.remote_snapshot()
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
