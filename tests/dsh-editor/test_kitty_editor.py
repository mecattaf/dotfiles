import base64
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'home/dot_config/kitty' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EDITOR = load('agency_editor')
WATCHER = load('agency_editor_watch')


class Window:
    def __init__(self, identity=1):
        self.id = identity
        self.child = SimpleNamespace(pid=4321 + identity)
        self.user_vars = {'agency_host': 'nas', 'agency_session': str(uuid.uuid4()),
                          'agency_directory': '/home/tom/a project'}
        self.screen = SimpleNamespace(columns=120)
        self.keys = []
        self.tab = SimpleNamespace(id=18, current_layout=SimpleNamespace(name='splits', default_axis_is_horizontal=True))

    def tabref(self):
        return self.tab

    def send_key(self, *args):
        self.keys.append(args)

    def set_user_var(self, key, value):
        self.user_vars[key] = value


class Boss:
    listening_on = 'unix:/private/kitty.sock'

    def __init__(self, window):
        self.window_id_map = {window.id: window}
        self.all_windows = [window]
        self.commands = []
        self.closed = []
        self.background = []

    def call_remote_control(self, window, args):
        self.commands.append((window.id, args))

    def mark_window_for_close(self, window):
        self.closed.append(window.id)

    def run_background_process(self, args):
        self.background.append(args)


class KittyEditorIdentityTests(unittest.TestCase):
    def setUp(self):
        self.window = Window()
        self.boss = Boss(self.window)
        self.old_version = EDITOR._version

    def tearDown(self):
        EDITOR._version = self.old_version

    def test_one_press_is_forwarded_to_remote_nvim_without_creating_sidebar(self):
        self.window.user_vars['nvim'] = '1'
        EDITOR.sidebar(self.boss, self.window)
        EDITOR.sidebar(self.boss, self.window, ['shift'])
        self.assertEqual(self.window.keys, [('ctrl+b',), ('ctrl+shift+b',)])
        self.assertEqual(self.boss.commands, [])

    def test_048_left_split_and_050_dock_are_feature_gated(self):
        EDITOR._version = lambda: (0, 48, 0)
        EDITOR.sidebar(self.boss, self.window)
        command = self.boss.commands[-1][1]
        self.assertIn('--location=before', command)
        self.assertNotIn('--type=window-dock', command)
        self.assertIn("'/home/tom/a project'", command[-1])
        EDITOR._version = lambda: (0, 50, 0)
        EDITOR.sidebar(self.boss, self.window)
        command = self.boss.commands[-1][1]
        self.assertIn('--type=window-dock', command)
        self.assertIn('--dock-edge=left', command)

    def test_toggling_one_parent_cannot_close_another_parents_tree(self):
        other = Window(2)
        other.user_vars = {'agency_editor_picker': '1', 'agency_editor_parent': '99',
                           'agency_editor_parent_pid': str(self.window.child.pid),
                           'agency_editor_parent_session': self.window.user_vars['agency_session']}
        self.boss.all_windows.append(other)
        EDITOR._version = lambda: (0, 50, 0)
        EDITOR.sidebar(self.boss, self.window)
        self.assertEqual(self.boss.closed, [])
        other.user_vars['agency_editor_parent'] = str(self.window.id)
        other.user_vars['agency_editor_pick'] = 'old result'
        EDITOR.sidebar(self.boss, self.window)
        self.assertEqual(self.boss.closed, [2])
        self.assertEqual(other.user_vars['agency_editor_pick'], '')

    def pick_window(self):
        picker = Window(5)
        picker.user_vars = {
            'agency_editor_pick': json.dumps({'directory': '/home/tom/a project', 'path': '/home/tom/a project/notes.md'}),
            'agency_editor_parent': str(self.window.id), 'agency_editor_parent_pid': str(self.window.child.pid),
            'agency_editor_parent_session': self.window.user_vars['agency_session'],
            'agency_editor_root': '/home/tom/a project', 'agency_editor_socket': self.boss.listening_on,
        }
        return picker

    def test_stale_picker_result_never_targets_an_active_replacement_window(self):
        picker = self.pick_window()
        self.window.child.pid += 1
        WATCHER.on_close(self.boss, picker, {})
        self.assertEqual(self.boss.background, [])
        self.window.child.pid -= 1
        WATCHER.on_close(self.boss, picker, {})
        self.assertEqual(self.boss.background[0][-1], '/home/tom/a project/notes.md')

    def test_changed_session_or_directory_blocks_editor_launch(self):
        payload = {'window_id': 1, 'session': self.window.user_vars['agency_session'],
                   'directory': '/home/tom/a project', 'files': ['/home/tom/a project/file.md']}
        for key, value in [('session', str(uuid.uuid4())), ('directory', '/home/tom/other')]:
            EDITOR.open_editor(self.boss, self.window, {**payload, key: value})
        self.assertEqual(self.boss.commands, [])
        EDITOR.open_editor(self.boss, self.window, payload)
        self.assertIn('--type=os-window', self.boss.commands[-1][1])

    def test_stale_async_sidebar_envelope_cannot_use_new_window_binding(self):
        EDITOR._version = lambda: (0, 50, 0)
        payload = {'window_id': 1, 'session': str(uuid.uuid4()),
                   'directory': '/home/tom/a project', 'files': []}
        encoded = base64.b64encode(json.dumps(payload).encode()).decode()
        EDITOR.handle_result(['editor.py', 'sidebar', encoded], None, 1, self.boss)
        self.assertEqual(self.boss.commands, [])
        payload['session'] = self.window.user_vars['agency_session']
        encoded = base64.b64encode(json.dumps(payload).encode()).decode()
        EDITOR.handle_result(['editor.py', 'sidebar', encoded], None, 1, self.boss)
        self.assertEqual(len(self.boss.commands), 1)
        self.assertIn('-tt', self.boss.commands[0][1])

    def test_control_character_or_oversized_callback_is_rejected(self):
        picker = self.pick_window()
        picker.user_vars['agency_editor_pick'] = json.dumps({'directory': '/home/tom/a project', 'path': '/home/tom/x\nattack'})
        with self.assertRaises(ValueError):
            WATCHER.on_close(self.boss, picker, {})
        with self.assertRaises(ValueError):
            EDITOR.handle_result(['editor.py', 'open-editor', 'A' * 65537], None, 1, self.boss)
        with self.assertRaises(ValueError):
            EDITOR._clean_path('/home/tom/../other')


if __name__ == '__main__':
    unittest.main(verbosity=2)
