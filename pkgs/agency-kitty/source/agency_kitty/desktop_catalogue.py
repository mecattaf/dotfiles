"""Metadata bridge and explicit human resume for the existing Imagine catalogue.

This module never consumes live application output. DSH's own PTY provider stays
separate; its chat id is a link, not authority to create or type into a terminal.
"""
from __future__ import annotations

import json
import subprocess
import sys

from .catalogue import chat_id, local_inventory, project_catalogue, session_id
from .sessions import SessionError, SessionStore

SERVER = "agency-web"
MAX_REQUEST = 16384


def frame(catalogue: dict, server: str = SERVER) -> dict:
    chat_id(server)
    if (not isinstance(catalogue, dict) or catalogue.get('version') != 1
            or catalogue.get('provider') != 'agency-kitty' or catalogue.get('host') != 'nas'
            or not isinstance(catalogue.get('sessions'), list) or len(catalogue['sessions']) > 4096):
        raise SessionError('invalid native terminal catalogue')
    terminals = []
    identities = set()
    for item in catalogue['sessions']:
        identity = session_id(item['terminalId'])
        if identity in identities:
            raise SessionError('duplicate native terminal identity')
        identities.add(identity)
        # Only this process constructs routes; command-looking catalogue fields
        # are never copied. Exited direct owners have no surviving process.
        if item['mode'] == 'direct' and item['liveness'] == 'absent':
            continue
        for chat in item['chatIds']:
            terminals.append({'title': item['title'], 'route': {
                'version': 1, 'provider': 'agency-kitty', 'server': server, 'host': 'nas',
                'session': chat_id(chat), 'terminal': identity, 'windowClass': item['windowClass'],
                'mode': item['mode'], 'resumable': item['resumable'],
            }})
            if len(terminals) > 4096:
                raise SessionError('native terminal chat links exceed their bound')
    return {'type': 'native-terminals', 'available': True, 'terminals': terminals}


def resume_request(value: dict, store: SessionStore) -> dict:
    from .cli import open_window, refresh
    fields = {'version', 'provider', 'server', 'host', 'session', 'terminal',
              'windowClass', 'mode', 'resumable'}
    if (not isinstance(value, dict) or set(value) != fields or value.get('version') != 1
            or value.get('provider') != 'agency-kitty' or value.get('host') != 'nas'
            or value.get('server') != SERVER or value.get('mode') != 'persistent'
            or value.get('resumable') is not True):
        raise SessionError('invalid native terminal resume request')
    identity, chat = session_id(value['terminal']), chat_id(value['session'])
    window_class = 'agencykitty-' + identity.replace('-', '')
    if value['windowClass'] != window_class:
        raise SessionError('native terminal window identity mismatch')
    # Canonical describe checks exact liveness/mode before the local mirror.
    # No new-session action or fallback exists on this endpoint.
    session = refresh(identity, store)
    if chat not in session.chat_ids:
        raise SessionError('terminal is no longer linked to this DSH chat')
    receipt = open_window(session)
    return {**receipt, 'provider': 'agency-kitty', 'host': 'nas', 'session': chat}


def main(argv=None) -> int:
    words = list(sys.argv[1:] if argv is None else argv)
    try:
        if words == ['frame']:
            output = frame(project_catalogue(local_inventory(SessionStore())))
        elif words == ['resume']:
            raw = sys.stdin.buffer.read(MAX_REQUEST + 1)
            if len(raw) > MAX_REQUEST:
                raise SessionError('native terminal request exceeds its bound')
            output = resume_request(json.loads(raw), SessionStore())
        else:
            raise SessionError('unsupported desktop catalogue action')
        print(json.dumps(output, ensure_ascii=False, separators=(',', ':')))
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print('agency-kitty desktop: ' + str(error), file=sys.stderr)
        return 1
