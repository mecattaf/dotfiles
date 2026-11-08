"""Exact managed invocation identity and Linux foreground-job validation.

This is sampled only at launch, typed hooks and explicit catalogue reads. It
does not parse screens, watch processes, or participate in ordinary key input.
"""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import uuid

ENVIRONMENT = 'AGENCY_KITTY_HARNESS_PROCESS'


def process(pid: int) -> dict:
    if type(pid) is not int or pid <= 0:
        raise ValueError('managed harness PID must be positive')
    directory = Path(f'/proc/{pid}')
    if directory.stat().st_uid != os.getuid():
        raise ValueError('managed harness process belongs to another user')
    raw = (directory/'stat').read_text()
    parts = raw[raw.rfind(')')+1:].split()
    return {'pid':pid,'start':parts[19],'pgrp':int(parts[2]),'sid':int(parts[3]),
            'tty':int(parts[4]),'foreground':int(parts[5]),'state':parts[0]}


def boot() -> str:
    return str(uuid.UUID(Path('/proc/sys/kernel/random/boot_id').read_text().strip()))


def capture(name: str) -> str:
    if name not in {'claude','codex'}:
        raise ValueError('unsupported managed harness')
    value = process(os.getpid())
    return json.dumps({'version':1,'harness':name,'boot':boot(),
                       **{key:value[key] for key in ('pid','start','pgrp','sid')}},separators=(',',':'))


def parse(token: str, name: str) -> dict | None:
    if not token:
        return None
    if not isinstance(token,str) or len(token)>2048:
        raise ValueError('managed harness process token exceeds its bound')
    value = json.loads(token)
    fields = {'version','harness','boot','pid','start','pgrp','sid'}
    if (not isinstance(value,dict) or set(value)!=fields or value['version']!=1 or value['harness']!=name
            or any(type(value[key]) is not int or value[key]<=0 for key in ('pid','pgrp','sid'))
            or not isinstance(value['start'],str) or not value['start'].isdigit()
            or not isinstance(value['boot'],str)):
        raise ValueError('invalid managed harness process identity')
    uuid.UUID(value['boot'])
    return value


def attest(token: str, name: str) -> dict | None:
    """At SessionStart, freeze the executable after the launcher exec completed."""
    value = parse(token,name)
    if value is None:
        return None
    current = process(value['pid'])
    if value['boot']!=boot() or any(current[key]!=value[key] for key in ('pid','start','pgrp','sid')):
        raise ValueError('managed harness invocation ended or changed')
    executable = Path(f'/proc/{value["pid"]}/exe').stat()
    return {**value,'executable_device':executable.st_dev,'executable_inode':executable.st_ino}


def invocation(token: str, name: str) -> str:
    """Stable generation for one launcher exec, not its reusable conversation."""
    value = parse(token,name)
    if value is None:
        return ''
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def foreground(value: dict | None, context: str, name: str) -> str:
    if value is None:
        return 'unverified'
    if not isinstance(value,dict):
        raise ValueError('invalid managed harness process identity')
    base = {key:value.get(key) for key in ('version','harness','boot','pid','start','pgrp','sid')}
    parse(json.dumps(base),name)
    if any(type(value.get(key)) is not int or value[key]<0 for key in ('executable_device','executable_inode')):
        raise ValueError('invalid managed harness executable identity')
    if value['boot']!=boot():
        return 'ended'
    try:
        current = process(value['pid'])
        executable = Path(f'/proc/{value["pid"]}/exe').stat()
    except (FileNotFoundError,ProcessLookupError):
        return 'ended'
    if (any(current[key]!=value[key] for key in ('pid','start','pgrp','sid'))
            or executable.st_dev!=value['executable_device'] or executable.st_ino!=value['executable_inode']
            or current['state'] in {'Z','X'}):
        return 'ended'
    owner = process(json.loads(context)['pid'])
    if (current['state'] in {'T','t'} or owner['tty']==0 or current['tty']!=owner['tty']
            or current['sid']!=owner['sid'] or owner['foreground']!=current['pgrp']):
        return 'background'
    return 'foreground'
