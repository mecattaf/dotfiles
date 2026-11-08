"""Project terminal identities into DSH/Imagine without owning their layout.

This projection is metadata only. A DSH chat id, durable NAS terminal id, and
native client window class are distinct identities; none grants input access.
"""
from __future__ import annotations

import dataclasses
import json
import re
import uuid
from pathlib import PurePosixPath
from typing import Any, Iterable, Mapping
from .sessions import MAX_CATALOGUE_METADATA_BYTES, SessionError

MAX_SESSIONS = 4096
ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z", re.ASCII)


def session_id(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("terminal id must be a UUID")
    parsed = uuid.UUID(value)
    if parsed.version != 4 or str(parsed) != value:
        raise ValueError("terminal id must be a canonical UUID4")
    return value


def chat_id(value: str) -> str:
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ValueError("invalid DSH chat id")
    return value


def clean_title(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("terminal title must be text")
    return "".join(c for c in value if ord(c) >= 32 and ord(c) != 127)[:256] or "NAS terminal"


def as_mapping(value: Any) -> Mapping[str, Any]:
    if isinstance(value, Mapping):
        return value
    if hasattr(value, "to_dict"):
        return value.to_dict()
    if dataclasses.is_dataclass(value):
        return dataclasses.asdict(value)
    raise ValueError("invalid terminal metadata")


def bound_inventory(values: Iterable[Any]) -> list[Any]:
    result, total = [], 0
    for value in values:
        if len(result) >= MAX_SESSIONS:
            raise SessionError('terminal catalogue exceeds its record bound')
        total += len(json.dumps(dict(as_mapping(value)), ensure_ascii=False).encode()) + 2
        if total > MAX_CATALOGUE_METADATA_BYTES:
            raise SessionError('terminal catalogue exceeds its metadata bound')
        result.append(value)
    return result


def local_inventory(store) -> list[Any]:
    """Read saved identities and live direct owners, without a holder call."""
    from .direct_registry import DirectRegistry
    from .capabilities.harness_state import status
    return bound_inventory([{**as_mapping(value),'agent_status':status(as_mapping(value)['id'],store=store)}
                            for value in [*store.list(), *DirectRegistry(store).list()]])


def project_session(value: Any) -> dict[str, Any]:
    row = as_mapping(value)
    identity = session_id(row["id"])
    if row.get("host", "nas") != "nas":
        raise ValueError("terminal belongs to another host")
    cwd = row.get("cwd")
    if not isinstance(cwd, str) or not PurePosixPath(cwd).is_absolute() or any(ord(c) < 32 or 127 <= ord(c) < 160 for c in cwd):
        raise ValueError("terminal directory must be an absolute NAS path")
    chats = row.get("chat_ids", [])
    if not isinstance(chats, (list, tuple)) or len(chats) > 128:
        raise ValueError("too many linked chats")
    chats = list(dict.fromkeys(chat_id(c) for c in chats))
    workspace = row.get("workspace_id")
    if workspace is not None and (not isinstance(workspace, str) or not workspace or len(workspace) > 128
                                  or any(ord(c) < 32 or ord(c) == 127 for c in workspace)):
        raise ValueError("invalid Imagine workspace reference")
    status = row.get("status", "unknown")
    if status not in ("created", "active", "detached", "closed", "unknown", "running", "exited"):
        status = "unknown"
    mode = row.get("mode", "persistent")
    if mode not in {"direct", "persistent"}:
        raise ValueError("invalid terminal mode")
    direct = mode == "direct"
    window_class = row.get("window_class") if direct else "agencykitty-" + uuid.UUID(identity).hex
    if window_class is not None and (not isinstance(window_class, str) or not re.fullmatch(r"agencykitty-[a-f0-9]{32}", window_class)):
        raise ValueError("invalid native OS-window class")
    window_id = row.get("kitty_window_id") if direct else None
    if window_id is not None and (type(window_id) is not int or not 0 < window_id < 2**31):
        raise ValueError("invalid native Kitty window id")
    return {
        "version": 1,
        "provider": "agency-kitty",
        "host": "nas",
        "terminalId": identity,
        "directory": cwd,
        "title": clean_title(row.get("title", "")),
        "chatIds": chats,
        "workspaceId": workspace,
        "status": status,
        "liveness": "running" if row.get("live") is True else "absent" if row.get("live") is False else "unverified",
        "mode": mode,
        "resumable": not direct,
        "windowClass": window_class,
        "kittyWindowId": window_id,
        "agentStatus": project_agent_status(row.get('agent_status')),
        "resume": None if direct else {"program": "agency-kitty", "args": ["resume", identity]},
        "editor": {"program": "dsh-editor", "args": ["--directory", cwd]},
        "capabilities": {"nativeRendering": True, "contentIncluded": False, "inputAuthority": False},
    }


def project_agent_status(value):
    if value is None:
        return None
    if (not isinstance(value,dict) or set(value)!={'version','harness','state','foreground','verified'}
            or value['version']!=1 or value['harness'] not in {'codex','claude'}
            or value['state'] not in {'idle','working','done','waiting','background','ended','unverified'}
            or value['foreground'] is not None and type(value['foreground']) is not bool
            or type(value['verified']) is not bool
            or value['state'] in {'idle','working','done','waiting'} and (value['foreground'] is not True or value['verified'] is not True)
            or value['state'] in {'background','ended'} and (value['foreground'] is not False or value['verified'] is not True)
            or value['state']=='unverified' and (value['foreground'] is not None or value['verified'] is not False)):
        raise ValueError('invalid native agent status projection')
    return dict(value)


def project_catalogue(values: Iterable[Any], *, linked_chat: str | None = None) -> dict[str, Any]:
    if linked_chat is not None:
        chat_id(linked_chat)
    items: list[dict[str, Any]] = []
    identities: set[str] = set()
    for value in values:
        if len(identities) >= MAX_SESSIONS:
            raise ValueError("terminal catalogue exceeds its bound")
        item = project_session(value)
        if item["terminalId"] in identities:
            raise ValueError("duplicate terminal identity")
        identities.add(item["terminalId"])
        if linked_chat is None or linked_chat in item["chatIds"]:
            items.append(item)
    items.sort(key=lambda item: item["terminalId"])
    return {"version": 1, "host": "nas", "provider": "agency-kitty", "sessions": items}
