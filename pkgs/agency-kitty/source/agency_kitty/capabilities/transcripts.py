"""Read saved harness history without scrolling or injecting keys into a TUI.

This exports semantic messages, not terminal pixels or an alternate-screen
backlog. It cannot recover output which the harness never persisted.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Iterator

MAX_RECORD_BYTES = 16 * 1024 * 1024
MAX_TRANSCRIPT_BYTES = 512 * 1024 * 1024


@dataclass
class ExportStats:
    records: int = 0
    messages: int = 0
    skipped_partial: int = 0
    skipped_metadata: int = 0


def _records(path: Path, stats: ExportStats) -> Iterator[dict]:
    with path.open("rb") as stream:
        size = stream.seek(0, 2)
        if size > MAX_TRANSCRIPT_BYTES:
            raise ValueError("transcript exceeds 512 MiB; choose a smaller session file")
        stream.seek(0)
        remaining = size  # a stable prefix even while the agent appends
        while remaining:
            line = stream.readline(min(remaining, MAX_RECORD_BYTES + 1))
            remaining -= len(line)
            if len(line) > MAX_RECORD_BYTES:
                raise ValueError("transcript record exceeds 16 MiB")
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                if remaining == 0 and not line.endswith(b"\n"):
                    stats.skipped_partial += 1
                    break
                raise ValueError(f"invalid JSON in transcript record {stats.records + 1}") from None
            stats.records += 1
            if isinstance(record, dict):
                yield record


def _content(blocks, include_tools: bool) -> str:
    if isinstance(blocks, str):
        return blocks
    if not isinstance(blocks, list):
        return ""
    result = []
    for block in blocks:
        if not isinstance(block, dict):
            continue
        kind = block.get("type", "")
        if kind in {"text", "input_text", "output_text"}:
            value = block.get("text")
            if isinstance(value, str):
                result.append(value)
        elif kind in {"image", "input_image"}:
            result.append("[image attachment]")
        elif kind == "tool_use" and include_tools:
            result.append("Tool " + str(block.get("name", "unknown")) + "\n\n```json\n" + json.dumps(block.get("input"), ensure_ascii=False, indent=2) + "\n```")
        elif kind == "tool_result" and include_tools:
            result.append("Tool result\n\n" + _content(block.get("content", ""), include_tools))
    return "\n\n".join(result)


def markdown(path: str | Path, harness: str, include_tools: bool = False) -> tuple[str, ExportStats]:
    if harness not in {"claude", "codex"}:
        raise ValueError("harness must be claude or codex")
    stats = ExportStats()
    path = Path(path).expanduser()
    sections = [f"# {harness.title()} session history\n\nSource: `{path}`\n\nSaved semantic messages; terminal-only output and unsaved drafts are outside this export."]
    seen: set[tuple[str, str]] = set()
    for record in _records(path, stats):
        if harness == "claude":
            if record.get("type") not in {"user", "assistant"} or record.get("isSidechain"):
                stats.skipped_metadata += 1
                continue
            msg = record.get("message")
            if not isinstance(msg, dict):
                continue
            role = msg.get("role", record["type"])
            content = _content(msg.get("content"), include_tools)
            identity = str(record.get("uuid", ""))
        else:
            if record.get("type") != "response_item":
                stats.skipped_metadata += 1
                continue
            msg = record.get("payload", {})
            if not isinstance(msg, dict):
                continue
            if msg.get("type") == "message":
                role = msg.get("role")
                blocks = msg.get("content")
                metadata = msg.get("internal_chat_message_metadata_passthrough")
                kinds = metadata.get("content_item_kinds") if isinstance(metadata, dict) else None
                if (role == "user" and isinstance(blocks, list) and isinstance(kinds, list)
                        and len(blocks) == len(kinds) and "unknown" not in kinds):
                    # Current Codex labels generated environment/context blocks
                    # separately even when their API role is user. Preserve
                    # actual user.text/image parts; do not export model setup.
                    blocks = [block for block, kind in zip(blocks, kinds)
                              if isinstance(kind, str) and kind.startswith("user.")]
                content = _content(blocks, include_tools)
            elif include_tools and msg.get("type") in {"function_call", "custom_tool_call", "function_call_output", "custom_tool_call_output"}:
                role = "tool"
                raw = msg.get("output", msg.get("arguments", msg.get("input", "")))
                content = str(msg.get("name", "Tool result")) + "\n\n" + (raw if isinstance(raw, str) else json.dumps(raw, ensure_ascii=False))
            else:
                continue
            identity = str(msg.get("id", ""))
        if role not in {"user", "assistant", "tool"} or not content:
            continue
        # Re-delivery can repeat a complete record. Never deduplicate solely by
        # message id: streaming Claude blocks share an id but contain new text.
        if identity:
            key = (identity, content)
            if key in seen:
                continue
            seen.add(key)
        stats.messages += 1
        timestamp = str(record.get("timestamp", ""))
        sections.append(f"## {str(role).title()}" + (f" · {timestamp}" if timestamp else "") + "\n\n" + content)
    footer = f"Exported {stats.messages} messages from {stats.records} saved records."
    if stats.skipped_partial:
        footer += " The final incomplete record was skipped while the agent was writing."
    sections.append(footer)
    return "\n\n".join(sections) + "\n", stats
