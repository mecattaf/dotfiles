"""Native Kitty editor/dock gestures, with no input or output interception."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import sys
import uuid


def main(args):
    return None


def _module_directory():
    filename = globals().get('__file__')
    return Path(filename).resolve().parent if filename else Path(sys.path[0]).resolve()


# Kitty temporarily prepends the custom kitten directory only while exec() runs,
# then restores sys.path before handle_result. Capture it during module loading.
_MODULE_DIRECTORY = _module_directory()


def _clean_path(value):
    if (not isinstance(value, str) or not PurePosixPath(value).is_absolute()
            or any(ord(c) < 32 or ord(c) == 127 for c in value)
            or len(value.encode('utf-8')) > 4096 or '..' in PurePosixPath(value).parts):
        raise ValueError('editor path must be an absolute path without control characters or parent components')
    return value


def _identity(window):
    variables = window.user_vars
    session = variables.get('agency_session', '')
    if variables.get('agency_host') != 'nas' or str(uuid.UUID(session)) != session:
        raise ValueError('editor gestures require an explicitly bound NAS session')
    return {'window_id': window.id, 'child_pid': window.child.pid,
            'session': session, 'directory': _clean_path(variables.get('agency_directory'))}


def _version():
    from kitty.constants import version
    return tuple(version)


def _socket(boss):
    value = os.environ.get('KITTY_LISTEN_ON') or getattr(boss, 'listening_on', '')
    if not isinstance(value, str) or not value:
        raise ValueError('Kitty control socket is unavailable')
    return value


def _ssh(program, directory, files=()):
    command = [f'/home/tom/.local/bin/{program}', '--directory', directory]
    if files:
        command += ['--', *files]
    return ['kitten', 'ssh', '-oBatchMode=yes', '-oStrictHostKeyChecking=yes',
            '-oForwardAgent=no', 'nas', shlex.join(command)]


def sidebar(boss, window, args=()):
    """Toggle this parent's left file tree; native Nvim retains Ctrl+B."""
    variables = window.user_vars
    if variables.get('agency_editor_picker') == '1':
        boss.mark_window_for_close(window)
        return
    if variables.get('nvim') == '1':
        # Kitty encodes the key for the application's negotiated keyboard mode.
        # Raw control bytes would collapse Ctrl+Shift+B and Ctrl+B.
        window.send_key('ctrl+shift+b' if 'shift' in args else 'ctrl+b')
        return
    target = _identity(window)
    for candidate in list(boss.all_windows):
        tags = candidate.user_vars
        if (tags.get('agency_editor_picker') == '1'
                and tags.get('agency_editor_parent') == str(window.id)
                and tags.get('agency_editor_parent_pid') == str(target['child_pid'])
                and tags.get('agency_editor_parent_session') == target['session']):
            # Clearing first prevents a close/toggle racing a completed pick
            # from opening a file the user just dismissed.
            candidate.set_user_var('agency_editor_pick', '')
            boss.mark_window_for_close(candidate)
            return
    tab = window.tabref()
    if tab is None:
        raise ValueError('source Kitty tab has closed')
    command = ['launch', '--match', f'id:{tab.id}', '--source-window', f'id:{window.id}',
               '--next-to', f'id:{window.id}', '--title', 'Files', '--watcher',
               str(_MODULE_DIRECTORY / 'agency_editor_watch.py')]
    if _version() >= (0, 50, 0):
        command += ['--type=window-dock', '--dock-edge=left', '--dock-size=28']
    else:
        layout = tab.current_layout
        if getattr(layout, 'name', '') != 'splits' or not getattr(layout, 'default_axis_is_horizontal', False):
            raise ValueError('Kitty before 0.50 requires the splits layout with split_axis=horizontal for the left file tree')
        columns = max(1, window.screen.columns)
        bias = max(5, min(80, round(28 / columns * 100)))
        command += ['--type=window', '--location=before', '--bias', str(bias)]
    tags = {
        'agency_editor_picker': '1', 'agency_editor_parent': str(window.id),
        'agency_editor_parent_pid': str(target['child_pid']),
        'agency_editor_parent_session': target['session'], 'agency_editor_root': target['directory'],
        'agency_editor_socket': _socket(boss),
    }
    for key, value in tags.items():
        command += ['--var', f'{key}={value}']
    boss.call_remote_control(window, tuple(command + ['--', *_ssh('dsh-editor-tree', target['directory'])]))


def open_editor(boss, window, payload):
    """Open a separate editor window, after revalidating the exact origin."""
    if not isinstance(payload, dict):
        raise ValueError('editor callback must be an object')
    target = _identity(window)
    if (payload.get('window_id') != target['window_id'] or payload.get('session') != target['session']
            or payload.get('directory') != target['directory']):
        return  # stale response, closed/reused window, or rebound directory
    files = payload.get('files', [])
    if not isinstance(files, list) or len(files) > 64:
        raise ValueError('editor callback files exceed the limit')
    files = [_clean_path(path) for path in files]
    directory = target['directory']
    identity = hashlib.sha256(directory.encode('utf-8')).hexdigest()[:24]
    command = ['launch', '--type=os-window', '--title', 'Editor: ' + PurePosixPath(directory).name,
               '--var', 'agency_host=nas', '--var', 'agency_session=' + target['session'],
               '--var', 'agency_directory=' + directory, '--var', 'agency_editor_window=1',
               '--var', 'agency_editor_identity=' + identity]
    boss.call_remote_control(window, tuple(command + ['--', *_ssh('dsh-editor', directory, files)]))


def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None or getattr(window, 'destroyed', False):
        return
    action = args[1] if len(args) > 1 else 'sidebar'
    if action in ('sidebar', 'editor-tree'):
        sidebar(boss, window, args[2:])
    elif action == 'open-editor':
        if len(args) != 3 or len(args[2]) > 65536:
            raise ValueError('editor callback exceeds its bound')
        raw = base64.b64decode(args[2], altchars=b'-_', validate=True)
        open_editor(boss, window, json.loads(raw))
    else:
        raise ValueError('unknown editor gesture')


handle_result.no_ui = True
