"""Close-time picker result delivery; all identity checks precede launch."""
import json
import os
from pathlib import PurePosixPath
import uuid


def _path(value):
    if (not isinstance(value, str) or not PurePosixPath(value).is_absolute()
            or any(ord(c) < 32 or ord(c) == 127 for c in value)
            or len(value.encode('utf-8')) > 4096 or '..' in PurePosixPath(value).parts):
        raise ValueError('invalid editor pick path')
    return value


def on_close(boss, window, data):
    tags = window.user_vars
    result = tags.get('agency_editor_pick', '')
    if not result:
        return
    if len(result) > 16384:
        raise ValueError('editor picker result exceeds its bound')
    pick = json.loads(result)
    if not isinstance(pick, dict):
        raise ValueError('editor picker result must be an object')
    directory, path = _path(pick.get('directory')), _path(pick.get('path'))
    if directory != tags.get('agency_editor_root'):
        raise ValueError('editor picker changed its directory identity')
    parent_id = int(tags['agency_editor_parent'])
    parent = boss.window_id_map.get(parent_id)
    session = tags['agency_editor_parent_session']
    if str(uuid.UUID(session)) != session:
        raise ValueError('invalid editor parent session')
    if (parent is None or getattr(parent, 'destroyed', False)
            or parent.child.pid != int(tags['agency_editor_parent_pid'])
            or parent.user_vars.get('agency_host') != 'nas'
            or parent.user_vars.get('agency_session') != session
            or parent.user_vars.get('agency_directory') != directory):
        return
    argv = [os.environ.get('AGENCY_KITTY_COMMAND', 'agency-kitty'), 'edit', '--kitty-socket', tags['agency_editor_socket'],
            '--window-id', str(parent_id), '--child-pid', str(parent.child.pid), '--session', session,
            '--directory', directory, '--', path]
    # No SSH, subprocess wait or output parsing occurs in Kitty's render loop.
    boss.run_background_process(argv)
