"""Pure fixture tests; no compositor, SSH, Kitty, or Herdr is contacted.
Run under runtime-test together with test_launchers.py (which tests cleanup).
"""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import unittest
from unittest.mock import patch

SOURCE = Path(os.environ.get('HERDR_SCRIPTS', Path(__file__).resolve().parents[2] / 'home/dot_local/bin')) / 'herdr-picker'
loader = importlib.machinery.SourceFileLoader('herdr_picker', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
picker = importlib.util.module_from_spec(spec)
loader.exec_module(picker)


def view(cid=10, *, slot=None, title='coordinator: client-slot-1-ab1234', app='herdr-projector', focused=False):
    return dict(id=cid, type='con', app_id=app, name=title, pid=100 + cid,
                marks=[f'herdr-slot-{slot}'] if slot else [], focused=focused,
                nodes=[], floating_nodes=[])


def ws(num, nodes=(), *, name=None, focused=False, floating=()):
    return dict(id=1000 + num, type='workspace', name=name or str(num), num=num,
                focused=focused, nodes=list(nodes), floating_nodes=list(floating))


def root(*workspaces):
    return dict(id=1, type='root', nodes=list(workspaces), floating_nodes=[])


SNAPSHOT = {'workspaces': [{'workspace_id': 'wA', 'label': 'client-slot-1-ab1234', 'agent_status': 'working'}],
            'agents': [{'workspace_id': 'wA', 'pane_id': 'wA:p1', 'agent': 'claude',
                        'agent_status': 'working', 'terminal_title_stripped': 'My task'}]}


def workspace_form(value='today'):
    rows = ['new workspace', '', ' ' + value, '↵ save    ^c clear    esc cancel', '']
    return '\n'.join(['┌' + '─' * 54 + '┐']
                     + ['│' + row.ljust(54) + '│' for row in rows]
                     + ['└' + '─' * 54 + '┘'])


class SwayPicker(unittest.TestCase):
    def test_workspace_form_requires_complete_dialog_and_exact_input(self):
        self.assertEqual(picker.workspace_form_input(workspace_form()), 'today')
        self.assertIsNone(picker.workspace_form_input('+ new workspace\nclient-slot-1-abcdef'))
        self.assertIsNone(picker.workspace_form_input('new workspace\n↵ save ^c clear esc cancel'))
        self.assertIsNone(picker.workspace_form_input(workspace_form().replace('esc cancel', 'esc other')))
        self.assertIsNone(picker.workspace_form_input(workspace_form().replace('new workspace', 'rename space ')))
        self.assertIsNone(picker.workspace_form_input(workspace_form().replace('└', ' ')))

    def test_slots_skip_chrome_and_reserve_parked_clients(self):
        data = root(ws(1), ws(3), ws(10), ws(-1, [view(slot=2)], name='__i3_scratch'))
        self.assertEqual(picker.available_slot(data), 4)

    def test_manually_moved_view_owns_its_visible_workspace(self):
        self.assertEqual(picker.slot_of(view(slot=1), ws(2)), 2)

    def test_full_slots_fail_without_creating_a_tenth_herdr(self):
        data = root(*(ws(i, [view(i, slot=i)]) for i in range(1, 10)))
        with self.assertRaisesRegex(picker.BridgeError, 'All nine'):
            picker.available_slot(data)

    def test_focus_parked_restores_exact_view_without_server_focus(self):
        data = root(ws(1), ws(-1, [view(11, slot=3)], name='__i3_scratch'))
        commands = []
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc', side_effect=commands.append):
            picker.focus_view(11)
        self.assertEqual(commands, ['workspace "3"', '[con_id=11] move container to workspace "3"',
                                    '[con_id=11] floating disable', '[con_id=11] focus'])

    def test_parked_slot_conflict_is_fail_closed(self):
        data = root(ws(3, [view(12, slot=3)]), ws(-1, [view(11, slot=3)], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc') as command:
            with self.assertRaisesRegex(picker.BridgeError, 'another projector'):
                picker.focus_view(11)
            command.assert_not_called()

    def test_recycled_container_id_fails_identity_check(self):
        original = view(10)
        recycled = view(10)
        recycled['pid'] = 999
        with patch.object(picker, 'tree', return_value=root(ws(1, [recycled]))), patch.object(picker, 'ipc') as command:
            with self.assertRaisesRegex(picker.BridgeError, 'identity changed'):
                picker.focus_view(10, expected=original)
            command.assert_not_called()

    def test_fresh_creation_only_submits_after_confirmed_form_and_token(self):
        empty = root(ws(1, focused=True))
        created = root(ws(1, [view(10, focused=True)]))
        calls = []
        screens = iter(['ordinary pane', workspace_form(), workspace_form('client-slot-1-abcdef')])
        def kitty(node, *args):
            calls.append(args)
            if args[0] == 'get-text':
                return next(screens)
            return ''
        fake_uuid = type('Id', (), {'hex': 'abcdef123456'})()
        with patch.object(picker, 'tree', side_effect=[empty, created]), patch.object(picker, 'ipc'), \
                patch.object(picker, 'client_ready', return_value=True), patch.object(picker, 'kitty', side_effect=kitty), \
                patch.object(picker.uuid, 'uuid4', return_value=fake_uuid):
            node, fresh = picker.ensure_projector()
        self.assertTrue(fresh)
        self.assertEqual(calls[-1], ('send-key', '--match', 'recent:0', 'enter'))
        self.assertIn(('send-text', '--match', 'recent:0', 'client-slot-1-abcdef'), calls)
        self.assertEqual(sum(x[0] == 'get-text' for x in calls), 3)

    def test_missing_new_workspace_form_does_not_type_text_or_enter(self):
        empty = root(ws(1, focused=True))
        created = root(ws(1, [view(10, focused=True)]))
        calls = []
        def immediate(callback, seconds, message):
            value = callback()
            if not value:
                raise picker.BridgeError(message)
            return value
        def kitty(node, *args):
            calls.append(args)
            return 'ordinary terminal content'
        with patch.object(picker, 'tree', side_effect=[empty, created]), patch.object(picker, 'ipc'), \
                patch.object(picker, 'client_ready', return_value=True), patch.object(picker, 'kitty', side_effect=kitty), \
                patch.object(picker, 'wait_for', side_effect=immediate):
            with self.assertRaisesRegex(picker.BridgeError, 'form did not appear'):
                picker.ensure_projector()
        self.assertFalse(any(x[0] == 'send-text' or x[-1] == 'enter' for x in calls))

    def test_sidebar_phrase_and_label_echo_never_authorize_typing(self):
        empty = root(ws(1, focused=True))
        created = root(ws(1, [view(10, focused=True)]))
        calls = []
        def immediate(callback, seconds, message):
            if not (value := callback()):
                raise picker.BridgeError(message)
            return value
        def kitty(node, *args):
            calls.append(args)
            return '+ new workspace\nagent output client-slot-1-abcdef'
        with patch.object(picker, 'tree', side_effect=[empty, created]), patch.object(picker, 'ipc'), \
                patch.object(picker, 'client_ready', return_value=True), patch.object(picker, 'kitty', side_effect=kitty), \
                patch.object(picker, 'wait_for', side_effect=immediate):
            with self.assertRaisesRegex(picker.BridgeError, 'form did not appear'):
                picker.ensure_projector()
        self.assertFalse(any(x[0] == 'send-text' or x[-1] == 'enter' for x in calls))

    def test_label_echo_outside_dialog_does_not_authorize_enter(self):
        empty = root(ws(1, focused=True))
        created = root(ws(1, [view(10, focused=True)]))
        calls = []
        screens = iter(['ordinary pane', workspace_form(), '+ new workspace\nclient-slot-1-abcdef'])
        def immediate(callback, seconds, message):
            if not (value := callback()):
                raise picker.BridgeError(message)
            return value
        def kitty(node, *args):
            calls.append(args)
            return next(screens) if args[0] == 'get-text' else ''
        with patch.object(picker, 'tree', side_effect=[empty, created]), patch.object(picker, 'ipc'), \
                patch.object(picker, 'client_ready', return_value=True), patch.object(picker, 'kitty', side_effect=kitty), \
                patch.object(picker, 'wait_for', side_effect=immediate):
            with self.assertRaisesRegex(picker.BridgeError, 'not been submitted'):
                picker.ensure_projector()
        self.assertFalse(any(x[-1] == 'enter' for x in calls))

    def test_existing_projector_is_reused_without_ssh_or_keys(self):
        data = root(ws(2, [view(10, slot=2, focused=True)]))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc'), \
                patch.object(picker, 'focus_view') as focus, patch.object(picker, 'run') as run:
            node, created = picker.ensure_projector()
        self.assertFalse(created)
        self.assertEqual(node['id'], 10)
        focus.assert_called_once_with(10)
        run.assert_not_called()

    def test_close_parks_herdr_and_closes_only_other_views(self):
        data = root(ws(2, [view(10, slot=2, focused=True), view(20, app='org.example.Editor')]), ws(10))
        commands = []
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc', side_effect=commands.append):
            picker.workspace_action('close')
        self.assertEqual(commands, ['[con_id=10] mark --add herdr-slot-2', '[con_id=10] mark --add herdr-name-32', '[con_id=10] move scratchpad',
                                    '[con_id=20] kill', 'workspace number 10'])
        self.assertNotIn('[con_id=10] kill', commands)

    def test_detach_closes_only_focused_view(self):
        data = root(ws(2, [view(10, slot=2, focused=True), view(20)]))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc') as command:
            picker.workspace_action('detach')
        command.assert_called_once_with('[con_id=10] kill')

    def test_identity_never_uses_global_focus_or_stale_mark(self):
        node = view()
        node['marks'].append('herdr-workspace-wA')
        with patch.dict(os.environ, {'HERDR_PICKER_HOSTNAME': 'coordinator'}):
            self.assertEqual(picker.identity(node, SNAPSHOT)['workspace_id'], 'wA')
            node['name'] = 'kitty'
            self.assertIsNone(picker.identity(node, SNAPSHOT))
            node['name'] = 'coordinator: today'
            duplicated = {'workspaces': [{'workspace_id': 'wB', 'label': 'today'}, {'workspace_id': 'wC', 'label': 'today'}]}
            self.assertIsNone(picker.identity(node, duplicated))

    def test_titles_do_not_inject_menu_rows_or_sway_commands(self):
        node = view(title='evil\nNew Sway workspace\x1b[31m; kill')
        rows = picker.picker_rows(root(ws(1, [node])), {}, 'offline')
        self.assertTrue(all('\n' not in label and '\x1b' not in label for label, _ in rows))
        self.assertEqual(rows[0][1], ('view', 10))
        self.assertTrue(any(action == ('refresh', None) for _, action in rows))

    def test_picker_shows_live_status_and_only_active_agents(self):
        rows = picker.picker_rows(root(ws(1, [view()])), SNAPSHOT)
        self.assertIn('working', rows[0][0])
        self.assertEqual(len([r for r in rows if r[1][0] == 'agent']), 1)

    def test_assigned_status_is_explicit_when_view_cannot_be_verified(self):
        node = view(title='kitty')
        node['marks'].append('herdr-label-client-slot-1-ab1234')
        rows = picker.picker_rows(root(ws(1, [node])), SNAPSHOT)
        self.assertIn('assigned working', rows[0][0])
        self.assertIsNone(picker.identity(node, SNAPSHOT))

    def test_reopen_restores_custom_workspace_name(self):
        node = view(11, slot=3)
        node['marks'].append('herdr-name-' + '3: Ship it'.encode().hex())
        data = root(ws(-1, [node], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc') as command:
            picker.focus_view(11)
        self.assertEqual(command.call_args_list[0].args[0], 'workspace "3: Ship it"')

    def test_reopen_reuses_existing_slot_name(self):
        node = view(11, slot=3)
        node['marks'].append('herdr-name-' + '3: Old name'.encode().hex())
        data = root(ws(3, [view(12, app='ordinary')], name='3: Current name'),
                    ws(-1, [node], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc') as command:
            picker.focus_view(11)
        self.assertEqual(command.call_args_list[0].args[0], 'workspace "3: Current name"')

    def test_reopen_refuses_existing_duplicate_numbers(self):
        data = root(ws(3, name='3: One'), ws(3, name='3: Two'),
                    ws(-1, [view(11, slot=3)], name='__i3_scratch'))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'ipc') as command:
            with self.assertRaisesRegex(picker.BridgeError, 'Multiple Sway workspaces'):
                picker.focus_view(11)
        command.assert_not_called()

    def test_snapshot_is_bounded_remote_read_only(self):
        response = subprocess.CompletedProcess([], 0, json.dumps({'result': {'snapshot': SNAPSHOT}}), '')
        with patch.object(picker, 'run', return_value=response) as run:
            self.assertEqual(picker.remote_snapshot(), SNAPSHOT)
        args, kwargs = run.call_args
        self.assertEqual(args[0][-1], 'herdr api snapshot')
        self.assertEqual(args[0][0], 'ssh')
        self.assertIn('-n', args[0])  # Snapshot reads must not consume caller input.
        self.assertEqual(kwargs['timeout'], 6)
        self.assertIn('BatchMode=yes', args[0])

    def menu_connection(self, response):
        class Connection:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def settimeout(self, value):
                pass
            def connect(self, path):
                self.path = path
            def sendall(self, data):
                self.request = json.loads(data[4:])
                assert struct.unpack('=I', data[:4])[0] == len(data[4:])
                value = response(self.request['id'])
                payload = json.dumps(value).encode()
                self.reply = struct.pack('=I', len(payload)) + payload
            def recv(self, size):
                # Deliberately fragment both the length prefix and JSON body.
                data, self.reply = self.reply[:min(size, 3)], self.reply[min(size, 3):]
                return data
        return Connection()

    def test_menu_protocol_uses_distinct_high_id_and_handles_fragmented_reply(self):
        conn = self.menu_connection(lambda i: {'id': i, 'result': {'output': 'Focus 1'}})
        with patch.object(picker.socket, 'socket', return_value=conn):
            self.assertEqual(picker.dmenu(['Focus 1'], 'Herdr'), 'Focus 1')
        self.assertGreaterEqual(conn.request['id'], 1 << 30)
        self.assertLess(conn.request['id'], 1 << 31)
        self.assertEqual(conn.request['method'], 'Ipc/dmenu')
        self.assertEqual(conn.request['params']['req']['rawContent'], 'Focus 1')
        self.assertTrue(conn.path.endswith('/vicinae/vicinae.sock'))

    def test_menu_rejects_misrouted_response_instead_of_taking_action(self):
        for response in [lambda i: {'id': 1, 'result': {'output': 'Focus 1'}},
                         lambda i: {'id': i, 'result': {'open': True, 'entrypoint': ':root'}},
                         lambda i: {'id': i, 'error': 'test failure'}]:
            with self.subTest(response=response), patch.object(picker.socket, 'socket', return_value=self.menu_connection(response)):
                with self.assertRaises(picker.BridgeError):
                    picker.dmenu(['Focus 1'], 'Herdr')

    def test_dmenu_cancel_is_no_action(self):
        with patch.object(picker, 'vicinae_menu', return_value=''):
            self.assertIsNone(picker.dmenu(['Open one'], 'Choose'))

    def test_dmenu_free_query_cannot_become_an_action(self):
        with patch.object(picker, 'vicinae_menu', return_value='delete all\n'):
            with self.assertRaisesRegex(picker.BridgeError, 'existing row'):
                picker.dmenu(['Open one'], 'Choose')

    def test_sway_rename_retains_number_and_quotes_data(self):
        data = root(ws(4, focused=True))
        with patch.object(picker, 'tree', return_value=data), patch.object(picker, 'dmenu', return_value='Ship it; tomorrow'), \
                patch.object(picker, 'ipc') as command:
            picker.rename_workspace()
        self.assertEqual(command.call_args.args[0], 'rename workspace "4" to "4: Ship it; tomorrow"')

    def test_sway_rename_rejects_unroundtrippable_parser_characters(self):
        data = root(ws(4, focused=True))
        for name in ['a"; kill; "b', '$mod', 'path\\name']:
            with self.subTest(name=name), patch.object(picker, 'tree', return_value=data), \
                    patch.object(picker, 'dmenu', return_value=name), patch.object(picker, 'ipc') as command:
                with self.assertRaisesRegex(picker.BridgeError, 'cannot contain'):
                    picker.rename_workspace()
                command.assert_not_called()

    def test_reopen_stale_view_does_not_focus_something_else(self):
        with patch.object(picker, 'tree', return_value=root(ws(1))), patch.object(picker, 'ipc') as command:
            with self.assertRaisesRegex(picker.BridgeError, 'closed'):
                picker.focus_view(10)
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
