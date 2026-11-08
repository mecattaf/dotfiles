"""Add exact lifecycle hooks to one managed TUI invocation, without config edits.

This module exits through exec before the harness starts. It never forwards
keyboard input, watches output or changes a user's credential/config directory.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import sys

from .capabilities import harness, harness_process
from .sessions import validate_id


EVENTS = ('SessionStart', 'UserPromptSubmit', 'Stop', 'SessionEnd')


def hook_command(command: str, name: str, event: str) -> str:
    if (not Path(command).is_absolute() or any(ord(c) < 32 or ord(c) == 127 for c in command)
            or name not in {'claude', 'codex'} or event not in {*EVENTS, 'Notification'}):
        raise ValueError('harness hooks require an absolute reviewed helper path')
    verb = 'bind-harness' if event in {'SessionStart', 'SessionEnd'} else 'harness-event'
    return shlex.join([command, 'capability', verb, '--harness', name])


def codex_hash(event: str, command: str) -> str:
    # Exact normalized declaration identity from Codex0.163/0.167 discovery.rs
    # and config/fingerprint.rs. Optional None fields disappear through TOML.
    labels = {'SessionStart': 'session_start', 'UserPromptSubmit': 'user_prompt_submit',
              'Stop': 'stop', 'SessionEnd': 'session_end'}
    value = {'event_name': labels[event], 'hooks': [
        {'type': 'command', 'command': command, 'timeout': 3, 'async': False}]}
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def settings(name: str, command: str) -> list[str]:
    if name == 'claude':
        hooks = {event: [{'hooks': [{'type': 'command',
                  'command': hook_command(command, name, event), 'timeout': 3}]}]
                 for event in (*EVENTS, 'Notification')}
        # Claude merges hook arrays with the selected seat/project settings.
        return ['--settings', json.dumps({'hooks': hooks}, ensure_ascii=False, separators=(',', ':'))]
    if name != 'codex':
        raise ValueError('supported harnesses are claude and codex')
    flags = ['--config', 'features.hooks=true']
    states = []
    for event in EVENTS:
        own_command = hook_command(command, name, event)
        handler = '{ type = "command", command = ' + json.dumps(own_command, ensure_ascii=False) + ', timeout = 3 }'
        flags += ['--config', f'hooks.{event}=[{{ hooks = [{handler}] }}]']
        # Hook discovery is additive across layers. Trust only this known
        # invocation-layer declaration, leaving all user/project trust intact.
        label = {'SessionStart': 'session_start', 'UserPromptSubmit': 'user_prompt_submit',
                 'Stop': 'stop', 'SessionEnd': 'session_end'}[event]
        key = '/<session-flags>/config.toml:' + label + ':0:0'
        states.append(json.dumps(key) + ' = { trusted_hash = ' + json.dumps(codex_hash(event, own_command)) + ' }')
    # CLI dotted-key splitting does not parse quoted components containing
    # dots. Put exact source keys inside a TOML value, not the CLI key path.
    return [*flags, '--config', 'hooks.state={ ' + ', '.join(states) + ' }']


def arguments(name: str, args: list[str], *, command: str | None = None) -> list[str]:
    if name not in {'claude', 'codex'}:
        raise ValueError('supported harnesses are claude and codex')
    binary = shutil.which(name)
    if binary is None:
        raise FileNotFoundError(name + ' is unavailable')
    managed = os.environ.get('AGENCY_KITTY_SESSION', '')
    if not managed:
        return [binary, *args]
    validate_id(managed)
    if os.environ.get('AGENCY_KITTY_HOST') != 'nas':
        raise ValueError('managed harness hooks require the NAS terminal identity')
    harness.validate_terminal_context()
    command = command or os.environ.get('AGENCY_KITTY_COMMAND') or shutil.which('agency-kitty')
    if not command:
        raise FileNotFoundError('reviewed agency-kitty helper is unavailable')
    return [binary, *settings(name, command), *args]


def main(argv: list[str] | None = None) -> int:
    words = list(sys.argv[1:] if argv is None else argv)
    if not words:
        print('usage: agency-kitty harness claude|codex -- [original arguments]', file=sys.stderr)
        return 2
    name, *args = words
    if args[:1] == ['--']:
        args = args[1:]
    try:
        command = arguments(name, args)
        environment = dict(os.environ)
        if environment.get('AGENCY_KITTY_SESSION'):
            environment[harness_process.ENVIRONMENT] = harness_process.capture(name)
        os.execvpe(command[0], command, environment)
    except (OSError, ValueError) as error:
        print('agency-kitty harness: ' + str(error), file=sys.stderr)
        return 1
    return 1
