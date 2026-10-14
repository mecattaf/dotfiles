"""Behavioral attention tests; no live Sway, notifications or Herdr calls.

Run with runtime-test alongside launcher tests. Fixtures distinguish seeing a
request from answering it and stale notification actions from current episodes.
"""
import copy
import importlib.machinery
import importlib.util
import json
import os
import shlex
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(os.environ.get('HERDR_SCRIPTS', Path(__file__).resolve().parents[2] / 'home/dot_local/bin')) / 'herdr-attention'
loader = importlib.machinery.SourceFileLoader('herdr_attention', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
attention = importlib.util.module_from_spec(spec)
loader.exec_module(attention)


def status(state='working', focused=False, representative=10, closed=False):
    return {'contexts': [{'workspace_id': 'wA', 'label': 'client-slot-1-abcdef',
                          'sway_workspace': '1: Writing', 'terminal_id': 10, 'chat_id': 20,
                          'representative_id': representative, 'focused': focused, 'closed': closed}],
            'agents': [{'workspace_id': 'wA', 'pane_id': 'wA:p1', 'agent_status': state,
                        'terminal_title_stripped': 'Review <change>'}]}


class AttentionTransitions(unittest.TestCase):
    def test_blocked_transition_notifies_once_and_idle_is_not_a_question(self):
        model = attention.Attention()
        for value in ['working', 'idle', 'done', 'working']:
            self.assertEqual(model.update(status(value)), [])
            self.assertFalse(model.pending('wA'))
        self.assertEqual(len(model.update(status('blocked'))), 1)
        self.assertTrue(model.pending('wA'))
        self.assertEqual(model.update(status('blocked')), [])
        self.assertEqual(model.update(status('working')), [])
        self.assertFalse(model.pending('wA'))
        self.assertEqual(len(model.update(status('blocked'))), 1)

    def test_startup_and_reconnect_do_not_replay_notifications(self):
        model = attention.Attention()
        self.assertEqual(model.update(status('blocked')), [])
        self.assertTrue(model.pending('wA'), 'Existing unseen questions still need workspace urgency')
        unavailable = status()
        unavailable['agents'] = None
        self.assertEqual(model.update(unavailable), [])
        self.assertTrue(model.pending('wA'), 'Disconnect does not erase an outstanding question')
        self.assertEqual(model.update(status('blocked')), [])
        model.update(status('working'))
        self.assertEqual(len(model.update(status('blocked'))), 1)

    def test_visiting_acknowledges_without_answering_and_survives_restart(self):
        model = attention.Attention()
        model.update(status())
        model.update(status('blocked'))
        model.update(status('blocked', focused=True))
        self.assertFalse(model.pending('wA'))
        record = model.records['wA/wA:p1']
        self.assertTrue(record['waiting'])
        self.assertTrue(record['seen'])
        restarted = attention.Attention(copy.deepcopy(model.records))
        self.assertEqual(restarted.update(status('blocked')), [])
        self.assertFalse(restarted.pending('wA'))
        restarted.update(status('working'))
        self.assertEqual(len(restarted.update(status('blocked'))), 1)
        self.assertTrue(restarted.pending('wA'))

    def test_focused_workspace_never_demands_attention(self):
        model = attention.Attention()
        model.update(status())
        self.assertEqual(model.update(status('blocked', focused=True)), [])
        self.assertFalse(model.pending('wA'))
        model.update(status('blocked'))
        self.assertFalse(model.pending('wA'), 'Leaving a seen question must not re-alert')

    def test_multiple_panes_coalesce_notification_but_retain_waiting_state(self):
        model = attention.Attention()
        model.update(status())
        value = status('blocked')
        value['agents'].append(dict(value['agents'][0], pane_id='wA:p2'))
        self.assertEqual(len(model.update(value)), 1)
        self.assertEqual(len(model.records), 2)
        model.acknowledge('wA')
        self.assertTrue(all(record['waiting'] and record['seen'] for record in model.records.values()))

    def test_workspace_id_reuse_does_not_inherit_seen_state(self):
        model = attention.Attention()
        model.update(status('blocked', focused=True))
        replacement = status('blocked')
        replacement['contexts'][0]['label'] = 'client-slot-1-fedcba'
        self.assertEqual(len(model.update(replacement)), 1)
        self.assertTrue(model.pending('wA'))

    def test_missed_working_transition_uses_sequence_and_reset_is_silent(self):
        model = attention.Attention()
        value = status('blocked', focused=True)
        value['agents'][0]['state_change_seq'] = 2
        model.update(value)
        value['contexts'][0]['focused'] = False
        self.assertEqual(model.update(value), [])
        value['agents'][0]['state_change_seq'] = 4
        self.assertEqual(len(model.update(value)), 1)
        self.assertTrue(model.pending('wA'))
        self.assertEqual(model.update(value), [])
        value['agents'][0]['state_change_seq'] = 1
        self.assertEqual(model.update(value), [], 'Sequence reset is a restart baseline')
        self.assertTrue(model.pending('wA'))

    def test_replaced_agent_session_cannot_inherit_seen_state(self):
        model = attention.Attention()
        value = status('blocked', focused=True)
        value['agents'][0]['agent_session'] = {'agent': 'codex', 'kind': 'session', 'value': 'old'}
        model.update(value)
        value['contexts'][0]['focused'] = False
        value['agents'][0]['agent_session']['value'] = 'new'
        self.assertEqual(len(model.update(value)), 1)
        self.assertTrue(model.pending('wA'))

    def test_closed_context_does_not_notify_and_unknown_agents_are_ignored(self):
        model = attention.Attention()
        model.update(status())
        value = status('blocked', closed=True)
        value['agents'].append({'workspace_id': 'wUnknown', 'pane_id': 'wUnknown:p1', 'agent_status': 'blocked'})
        self.assertEqual(model.update(value), [])
        self.assertEqual(set(model.records), {'wA/wA:p1'})


class DesktopEffects(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        env = patch.dict(os.environ, {'XDG_STATE_HOME': self.directory.name})
        env.start()
        self.addCleanup(env.stop)
        self.bridge = attention.Bridge(3)
        self.bridge.model.update(status())
        self.bridge.model.update(status('blocked'))

    def test_urgency_moves_to_visible_companion_and_clears_after_visit(self):
        tree = {'id': 1, 'nodes': [{'id': 2, 'type': 'workspace', 'name': '1: Writing',
                                  'nodes': [{'id': 10, 'urgent': True}, {'id': 20, 'urgent': False}]}]}
        self.bridge.owned_urgency = {10}
        self.bridge.model.contexts['wA']['representative_id'] = 20
        with patch.object(attention, 'run', return_value=json.dumps(tree)), patch.object(self.bridge, 'set_urgent') as urgent:
            self.bridge.reconcile_urgency()
        self.assertEqual([call.args for call in urgent.call_args_list], [(10, False), (20, True)])
        tree['nodes'][0]['nodes'][0]['urgent'] = False
        tree['nodes'][0]['nodes'][1]['urgent'] = True
        self.bridge.model.acknowledge('wA')
        with patch.object(attention, 'run', return_value=json.dumps(tree)), patch.object(self.bridge, 'set_urgent') as urgent:
            self.bridge.reconcile_urgency()
        urgent.assert_called_once_with(20, False)

    def test_closed_or_missing_representative_cannot_mark_other_windows(self):
        for closed, representative in [(True, 20), (False, 999)]:
            self.bridge.model.contexts['wA'].update(closed=closed, representative_id=representative)
            with patch.object(attention, 'run', return_value=json.dumps({'id': 1, 'nodes': [{'id': 30}]})), patch.object(self.bridge, 'set_urgent') as urgent:
                self.bridge.reconcile_urgency()
                urgent.assert_not_called()

    def test_notification_action_matches_owner_pane_and_episode(self):
        record = copy.deepcopy(self.bridge.model.records['wA/wA:p1'])
        with patch.object(attention, 'run', return_value='[{"success":true}]') as run:
            self.bridge.event('activate', record)
            expected = 'exec ' + shlex.join([str(SOURCE.resolve().with_name('herdr-context')), 'activate', '--workspace', 'wA', '--pane', 'wA:p1'])
            run.assert_called_once_with(['swaymsg', '-r', '--', expected], timeout=3)
        for altered in [dict(record, owner='different'), dict(record, episode=0), dict(record, pane_id='missing')]:
            with patch.object(attention, 'run') as run:
                self.bridge.event('activate', altered)
                run.assert_not_called()
        self.bridge.model.update(status('working'))
        self.bridge.model.update(status('blocked'))
        with patch.object(attention, 'run') as run:
            self.bridge.event('activate', record)
            run.assert_not_called()

    def test_focus_event_acknowledges_and_persists_waiting(self):
        with patch.object(self.bridge, 'reconcile_urgency'):
            self.bridge.event('sway', {'change': 'focus', 'current': {'name': '1: Writing'}})
        saved = json.loads(self.bridge.state_path.read_text())['records']['wA/wA:p1']
        self.assertTrue(saved['waiting'])
        self.assertTrue(saved['seen'])
        self.assertEqual(self.bridge.state_path.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
