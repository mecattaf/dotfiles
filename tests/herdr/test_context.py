"""Context identity and navigation behavior, using inert desktop fixtures."""
import copy
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

SOURCE = Path(os.environ.get('HERDR_SCRIPTS', Path(__file__).resolve().parents[2] / 'home/dot_local/bin')) / 'herdr-context'
loader = importlib.machinery.SourceFileLoader('herdr_context', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
context = importlib.util.module_from_spec(spec)
loader.exec_module(context)


def window(cid, kind='terminal', wid='wA', marked=True, focused=False):
    return {'id': cid, 'type': 'con', 'pid': 1000 + cid, 'focused': focused,
            'app_id': 'herdr-projector' if kind == 'terminal' else 'herdr-context',
            'name': 'strix: client-slot-1-abcdef' if kind == 'terminal' else 'Chat',
            'marks': [f'herdr-context-{wid}-{kind}', 'herdr-slot-1'] if marked else [],
            'nodes': [], 'floating_nodes': []}


def workspace(number, nodes, name=None):
    return {'id': 100 + number, 'type': 'workspace', 'num': number,
            'name': name or str(number), 'nodes': nodes, 'floating_nodes': []}


def root(*nodes):
    return {'id': 1, 'type': 'root', 'nodes': list(nodes), 'floating_nodes': []}


def snapshot():
    return {'workspaces': [{'workspace_id': 'wA', 'label': 'client-slot-1-abcdef'}],
            'panes': [{'workspace_id': 'wA', 'pane_id': 'wA:p1'}],
            'agents': [{'workspace_id': 'wA', 'pane_id': 'wA:p1', 'agent': 'codex', 'agent_status': 'working'}]}


class Identity(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {'HERDR_PICKER_HOSTNAME': 'strix'})
        env.start()
        self.addCleanup(env.stop)

    def test_first_terminal_discovery_uses_live_title(self):
        rows, errors = context.collect(root(workspace(1, [window(10, marked=False)])), snapshot(), {})
        self.assertEqual(errors, [])
        self.assertEqual([(r['workspace_id'], r['slot'], r['view']) for r in rows], [('wA', 1, 'terminal')])

    def test_hidden_companion_retains_slot_and_rename_follows_visible_view(self):
        tree = root(workspace(2, [window(20, 'chat')], '2: Renamed'), workspace(-1, [window(10)], '__i3_scratch'))
        rows, errors = context.collect(tree, snapshot(), {})
        self.assertEqual(errors, [])
        self.assertEqual(rows[0]['slot'], 2)
        self.assertEqual(rows[0]['sway_workspace'], '2: Renamed')
        self.assertEqual(rows[0]['representative_id'], 20)

    def test_same_workspace_cannot_have_two_terminal_windows(self):
        tree = root(workspace(1, [window(10)]), workspace(2, [window(11)]))
        rows, errors = context.collect(tree, snapshot(), {})
        self.assertEqual(rows, [])
        self.assertTrue(any('Multiple windows' in error for error in errors))

    def test_two_herdr_workspaces_cannot_share_one_sway_slot(self):
        second = window(11, wid='wB')
        second['name'] = 'strix: client-slot-2-fedcba'
        snap = snapshot()
        snap['workspaces'].append({'workspace_id': 'wB', 'label': 'client-slot-2-fedcba'})
        rows, errors = context.collect(root(workspace(1, [window(10), second])), snap, {})
        self.assertEqual(rows, [])
        self.assertTrue(errors)

    def test_stale_marks_cannot_override_changed_kitty_workspace(self):
        terminal = window(10)
        terminal['name'] = 'strix: another-workspace'
        rows, errors = context.collect(root(workspace(1, [terminal])), snapshot(), {})
        self.assertEqual(rows, [])
        self.assertTrue(any('assigned Herdr workspace' in error for error in errors))

    def test_browser_alone_never_claims_a_context(self):
        rows, errors = context.collect(root(workspace(1, [window(20, 'chat')])), snapshot(), {})
        self.assertEqual(rows, [])
        self.assertTrue(any('Terminal companion is closed' in error for error in errors))

    def test_two_visible_companions_are_rejected(self):
        rows, errors = context.collect(root(workspace(1, [window(10), window(20, 'chat')])), snapshot(), {})
        self.assertEqual(rows, [])
        self.assertTrue(any('Both companion views' in error for error in errors))

    def test_offline_marked_pair_remains_available_without_guessing_new_identity(self):
        tree = root(workspace(1, [window(10)]), workspace(-1, [window(20, 'chat')], '__i3_scratch'))
        rows, errors = context.collect(tree, None, {'wA': {'label': 'client-slot-1-abcdef'}})
        self.assertEqual(errors, [])
        self.assertEqual(rows[0]['label'], 'client-slot-1-abcdef')
        self.assertEqual(context.collect(root(workspace(2, [window(30, marked=False)])), None, {}), ([], []))

    def test_both_parked_preserve_closed_context_and_last_view(self):
        rows, errors = context.collect(root(workspace(-1, [window(10), window(20, 'chat')], '__i3_scratch')),
                                      snapshot(), {'wA': {'closed': True, 'last_view': 'chat', 'sway_workspace': '1: Task'}})
        self.assertEqual(errors, [])
        self.assertTrue(rows[0]['closed'])
        self.assertIsNone(rows[0]['representative_id'])
        self.assertEqual(rows[0]['last_view'], 'chat')
        self.assertEqual(rows[0]['sway_workspace'], '1: Task')


class Navigation(unittest.TestCase):
    def test_one_agent_is_unambiguous_even_with_utility_shell(self):
        snap = snapshot()
        snap['panes'].append({'workspace_id': 'wA', 'pane_id': 'wA:p2'})
        self.assertEqual(context.pane_for({'workspace_id': 'wA'}, snap), 'wA:p1')

    def test_multiple_agents_choose_within_context_not_global_focus(self):
        snap = snapshot()
        snap['agents'].append(dict(snap['agents'][0], pane_id='wA:p2', focused=True))
        snap['panes'].append({'workspace_id': 'wA', 'pane_id': 'wA:p2', 'focused': True})
        self.assertEqual(context.pane_for({'workspace_id': 'wA', 'pane_id': 'wA:p1'}, snap), 'wA:p1')
        with patch.object(context.picker, 'dmenu', side_effect=lambda choices, prompt: choices[0]) as menu:
            self.assertEqual(context.pane_for({'workspace_id': 'wA'}, snap), 'wA:p1')
            self.assertEqual(len(menu.call_args.args[0]), 2)
        self.assertEqual(context.pane_for({'workspace_id': 'wA'}, snap, 'wA:p2'), 'wA:p2')
        with self.assertRaises(context.Error):
            context.pane_for({'workspace_id': 'wA'}, snap, 'wB:p1')

    def test_chat_url_scopes_identity_and_clears_previous_navigation(self):
        with patch.dict(os.environ, {'HERDR_WEB_URL': 'https://herdr.example/app?machine=remote&file=old&settings=account&ws=old&view=terminal#anchor'}):
            url = urlsplit(context.chat_url({'workspace_id': 'wA'}, 'wA:p1'))
        self.assertEqual((url.scheme, url.netloc, url.path, url.fragment), ('https', 'herdr.example', '/app', 'anchor'))
        self.assertEqual(parse_qs(url.query), {'machine': ['remote'], 'ws': ['wA'], 'pane': ['wA:p1'],
                                            'view': ['chat'], 'sidebar': ['hidden'], 'context': ['wA']})

    def test_same_pane_toggle_does_not_reload_or_touch_browser_draft(self):
        row = {'workspace_id': 'wA', '_chat': window(20, 'chat')}
        target = {'url': 'https://herdr.example/?ws=wA&pane=wA%3Ap1&view=chat&sidebar=hidden&context=wA'}
        with patch.dict(os.environ, {'HERDR_WEB_URL': 'https://herdr.example/'}), \
             patch.object(context, 'own_browser', return_value=True), patch.object(context, 'app_target', return_value=target), \
             patch.object(context, 'cdp') as cdp:
            self.assertEqual(context.ensure_chat(row, 'wA:p1')['id'], 20)
            cdp.assert_not_called()

    def test_foreign_browser_fails_before_cdp_navigation(self):
        row = {'workspace_id': 'wA', '_chat': window(20, 'chat')}
        with patch.object(context, 'own_browser', return_value=False), patch.object(context, 'cdp') as cdp:
            with self.assertRaises(context.Error):
                context.ensure_chat(row, 'wA:p1')
            cdp.assert_not_called()

    def test_duplicate_cdp_targets_are_rejected(self):
        target = {'type': 'page', 'url': 'https://herdr.example/?context=wA'}
        with patch.dict(os.environ, {'HERDR_WEB_URL': 'https://herdr.example/'}), \
             patch.object(context, 'http_json', return_value=[target, copy.deepcopy(target)]):
            with self.assertRaises(context.Error):
                context.app_target('wA')


if __name__ == '__main__':
    unittest.main()
