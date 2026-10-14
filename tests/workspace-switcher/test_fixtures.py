"""The switcher against the Zenbook's live seat as captured, and against the configured layout.

fixtures/zenbook-0221-*.json are `swaymsg -t get_workspaces|get_tree|get_outputs`
read from the Zenbook at 02:21 Paris on 2026-10-14 (MEASURED): eDP-1 (top) holds
1, 2, 3, 6, 8, 9 and 10; eDP-2 (bottom) holds 4 and 5. Projectors sit on 1, 2, 3,
10 and 4 with marks herdr-slot-{1,2,3,5,4} and the five live labels. Their
window titles are the constant "herdr-sway-projector", so identity() resolves
nothing and every status comes from assigned_identity(): rows read "assigned ...".
fixtures/config-layout-get_workspaces.json is binds.conf's assignment (1 to 9 on
eDP-1, 10 on eDP-2), which the live seat does not match: both must hold at once.
No compositor, Herdr or SSH is contacted. Run under runtime-test.
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SCRIPTS = Path(os.environ.get('HERDR_SCRIPTS', HERE.parents[1] / 'home/dot_local/bin'))
loader = importlib.machinery.SourceFileLoader('switcher_fixtures', str(SCRIPTS / 'sway-workspace-switcher'))
spec = importlib.util.spec_from_loader(loader.name, loader)
s = importlib.util.module_from_spec(spec)
loader.exec_module(s)
b = s.bridge()


def fixture(name):
    return json.loads((HERE / 'fixtures' / name).read_text())


LIVE_WORKSPACES = fixture('zenbook-0221-get_workspaces.json')
LIVE_TREE = fixture('zenbook-0221-get_tree.json')
LIVE_OUTPUTS = fixture('zenbook-0221-get_outputs.json')
CONFIG_WORKSPACES = fixture('config-layout-get_workspaces.json')

# The five live labels (SOAK.md section 3.5) with the agent status each pane
# showed at 01:10: the label's number is the slot the projector was created in,
# not where it sits now (two of five match).
LIVE_LABELS = {
    'client-slot-4-9690f0': ('wG4', 'working'),   # on workspace 1, mark herdr-slot-1
    'client-slot-2-d6929b': ('wG9', 'idle'),      # on workspace 2, mark herdr-slot-2
    'client-slot-3-02c703': ('wG7', 'done'),      # on workspace 3, mark herdr-slot-3
    'client-slot-5-fc4d18': ('wG8', 'working'),   # on workspace 10, mark herdr-slot-5
    'client-slot-4-6a3fb5': ('wG6', 'working'),   # on workspace 4 (eDP-2), mark herdr-slot-4
}
SNAPSHOT = {'workspaces': [{'workspace_id': wid, 'label': label, 'agent_status': status}
                           for label, (wid, status) in LIVE_LABELS.items()],
            'agents': []}
EXPECTED_LIVE_ROWS = [1, 2, 3, 6, 7, 8, 9, 10]


def label_of(rows, slot):
    return next(r['label'] for r in rows if r['slot'] == slot)


class LiveSeat(unittest.TestCase):
    def test_capture_is_the_seat_the_spec_describes(self):
        by_output = {}
        for w in LIVE_WORKSPACES:
            by_output.setdefault(w['output'], []).append(w['num'])
        self.assertEqual(sorted(by_output['eDP-1']), [1, 2, 3, 6, 8, 9, 10])
        self.assertEqual(sorted(by_output['eDP-2']), [4, 5])
        marks = {m for n, _ in b.projectors(LIVE_TREE) for m in n.get('marks', [])}
        self.assertEqual({m for m in marks if m.startswith('herdr-label-')},
                         {'herdr-label-' + label for label in LIVE_LABELS})
        self.assertEqual({m for m in marks if m.startswith('herdr-slot-')},
                         {'herdr-slot-1', 'herdr-slot-2', 'herdr-slot-3', 'herdr-slot-4', 'herdr-slot-5'})

    def test_rows_follow_live_membership_not_the_assignment(self):
        rows = s.make_rows(b, LIVE_TREE, LIVE_WORKSPACES, SNAPSHOT, 'eDP-1')
        self.assertEqual([r['slot'] for r in rows], EXPECTED_LIVE_ROWS)
        self.assertEqual(next(r for r in rows if r['slot'] == 10)['name'], '10')
        self.assertIsNone(next(r for r in rows if r['slot'] == 7)['name'])
        self.assertTrue(all(r['output'] == 'eDP-1' for r in rows))

    def test_live_statuses_read_assigned_from_the_five_labels(self):
        rows = s.make_rows(b, LIVE_TREE, LIVE_WORKSPACES, SNAPSHOT, 'eDP-1')
        self.assertIn('assigned working', label_of(rows, 1))
        self.assertIn('assigned idle', label_of(rows, 2))
        self.assertIn('assigned done', label_of(rows, 3))
        self.assertIn('assigned working', label_of(rows, 10))
        for slot in (6, 8, 9):
            self.assertIn('no Herdr projector', label_of(rows, slot))
        self.assertIn('7 · Empty workspace', label_of(rows, 7))
        # Nothing on the list claims a live title identity or a global focus.
        self.assertFalse(any(' working' in r['label'] and 'assigned' not in r['label'] for r in rows))

    def test_live_statuses_without_herdr_are_unavailable_not_idle(self):
        rows = s.make_rows(b, LIVE_TREE, LIVE_WORKSPACES, {}, 'eDP-1', unavailable=True)
        for slot in (1, 2, 3, 10):
            self.assertIn('unavailable', label_of(rows, slot))
            self.assertNotIn('idle', label_of(rows, slot))

    def test_live_outputs_both_active_and_top_required(self):
        s.require_output('eDP-1', LIVE_OUTPUTS)
        with self.assertRaisesRegex(RuntimeError, 'eDP-1 is unavailable'):
            s.require_output('eDP-1', [o for o in LIVE_OUTPUTS if o['name'] != 'eDP-1'])

    def test_existing_workspace_is_selected_by_name(self):
        row = {'slot': 10, 'name': '10', 'output': 'eDP-1'}
        with patch.object(s, 'sway_query', side_effect=[LIVE_OUTPUTS, LIVE_WORKSPACES]), patch.object(b, 'ipc') as ipc:
            s.activate(b, row)
        self.assertEqual([c.args[0] for c in ipc.call_args_list], ['focus output "eDP-1"', 'workspace "10"'])

    def test_empty_slot_is_selected_by_number(self):
        row = {'slot': 7, 'name': None, 'output': 'eDP-1'}
        with patch.object(s, 'sway_query', side_effect=[LIVE_OUTPUTS, LIVE_WORKSPACES]), patch.object(b, 'ipc') as ipc:
            s.activate(b, row)
        self.assertEqual([c.args[0] for c in ipc.call_args_list], ['focus output "eDP-1"', 'workspace number 7'])

    def test_select_workspace_pins_both_forms(self):
        with patch.object(b, 'ipc') as ipc:
            b.select_workspace(10, '10')
            b.select_workspace(6)
            b.select_workspace('6')
        self.assertEqual([c.args[0] for c in ipc.call_args_list],
                         ['workspace "10"', 'workspace number 6', 'workspace number 6'])
        with self.assertRaises(b.BridgeError):
            b.select_workspace(1, '1"; exec evil')

    def test_json_run_over_the_capture(self):
        def query(kind):
            return {'get_outputs': LIVE_OUTPUTS, 'get_workspaces': LIVE_WORKSPACES}[kind]
        out = io.StringIO()
        # main() loads its bridge afresh; hand it this test's patched one.
        with patch.object(s, 'bridge', return_value=b), patch.object(s, 'sway_query', side_effect=query), \
             patch.object(b, 'tree', return_value=LIVE_TREE), \
             patch.object(b, 'remote_snapshot', return_value=SNAPSHOT), patch.object(b, 'ipc') as ipc, \
             patch.dict(os.environ, {'SWAYSOCK': 'fixture'}), patch.object(sys, 'argv', ['switcher', '--json', '--output', 'eDP-1']), \
             contextlib.redirect_stdout(out):
            s.main()
        ipc.assert_not_called()
        result = json.loads(out.getvalue())
        self.assertEqual(result['output'], 'eDP-1')
        self.assertFalse(result['herdr_unavailable'])
        self.assertEqual([r['slot'] for r in result['workspaces']], EXPECTED_LIVE_ROWS)
        self.assertFalse(b.hyprland())


class ConfiguredLayout(unittest.TestCase):
    def test_config_layout_rows_are_one_to_nine(self):
        rows = s.make_rows(b, {'type': 'root', 'nodes': []}, CONFIG_WORKSPACES, {}, 'eDP-1')
        self.assertEqual([r['slot'] for r in rows], list(range(1, 10)))
        self.assertNotIn(10, [r['slot'] for r in rows])
        self.assertIn('● 1', label_of(rows, 1))

    def test_the_two_layouts_disagree_so_neither_test_passes_alone(self):
        live = [r['slot'] for r in s.make_rows(b, LIVE_TREE, LIVE_WORKSPACES, SNAPSHOT, 'eDP-1')]
        configured = [r['slot'] for r in s.make_rows(b, {'type': 'root', 'nodes': []}, CONFIG_WORKSPACES, {}, 'eDP-1')]
        self.assertNotEqual(live, configured)
        self.assertEqual(set(configured) - set(live), {4, 5})
        self.assertEqual(set(live) - set(configured), {10})


if __name__ == '__main__':
    unittest.main()
