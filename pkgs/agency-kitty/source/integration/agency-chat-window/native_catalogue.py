"""One bounded metadata read inside catalogue_nas's existing inventory poll.

Installed beside catalogue_nas.py; package construction replaces COMMAND.
It owns no PTY, agent process, connection loop, provider or desktop command.
"""
import json
import os
import select
import subprocess
import time

COMMAND = '@AGENCY_KITTY_COMMAND@'
MAX_BYTES = 4 * 1024 * 1024


def inventory(session_ids, command=COMMAND):
    child = None
    try:
        if not os.path.isabs(command) or any(ord(c) < 32 for c in command):
            raise ValueError('native metadata helper must be installed')
        child = subprocess.Popen([command, 'desktop-catalogue'], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        chunks, total, deadline = [], 0, time.monotonic() + 5
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('native metadata deadline')
            ready, _, _ = select.select([child.stdout], [], [], remaining)
            if not ready:
                raise TimeoutError('native metadata deadline')
            chunk = os.read(child.stdout.fileno(), 65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_BYTES:
                raise ValueError('native metadata exceeds its bound')
            chunks.append(chunk)
        if child.wait(timeout=max(.001, deadline-time.monotonic())) != 0:
            raise ValueError('native metadata unavailable')
        value = json.loads(b''.join(chunks))
        if (not isinstance(value, dict) or value.get('type') != 'native-terminals'
                or value.get('available') is not True or not isinstance(value.get('terminals'), list)
                or len(value['terminals']) > 4096):
            raise ValueError('native metadata frame mismatch')
        value['terminals'] = [item for item in value['terminals'] if item['route']['session'] in session_ids]
        return value
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, TimeoutError):
        return {'type': 'native-terminals', 'available': False}
    finally:
        if child is not None:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(.3)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait(1)
            child.stdout.close()
