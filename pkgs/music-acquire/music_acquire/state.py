"""Durable batch state for :mod:`music_acquire`.

The archive is intentionally the resume gate.  The append-only ledger is the
audit trail; a retryable row is evidence about an attempt, never permission to
skip the item on the next run.
"""

from __future__ import annotations

import collections
import fcntl
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


TERMINAL_DISPOSITIONS = {
    "ok_soundcloud",
    "ok_youtube",
    "ok_capture",
    "ok_bandcamp",
    "skipped_duplicate",
    "gone",
    "fallthrough",
}


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except (json.JSONDecodeError, TypeError):
                continue
            if isinstance(row, dict):
                rows.append(row)
    return rows


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def _atomic_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


class BatchState:
    """One batch's worklist, append-only evidence ledger, and resume gate."""

    def __init__(self, root: Path, batch: str):
        self.root = root.expanduser().resolve()
        self.batch = batch
        self.path = self.root / batch
        self.worklist_path = self.path / "worklist.jsonl"
        self.ledger_path = self.path / "ledger.jsonl"
        self.archive_path = self.path / "archive.txt"
        self.request_path = self.path / "request.json"
        self.cookies_path = self.path / "cookies"
        self.lock_path = self.path / ".lock"

    def ensure(self) -> None:
        self.path.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.cookies_path.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.ledger_path.touch(exist_ok=True)
        self.archive_path.touch(exist_ok=True)
        os.chmod(self.path, 0o700)
        os.chmod(self.cookies_path, 0o700)

    def _lock(self):
        self.ensure()
        handle = self.lock_path.open("a+")
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return handle

    @staticmethod
    def _merge_appearances(
        old: list[dict[str, Any]], new: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        seen: set[str] = set()
        merged: list[dict[str, Any]] = []
        for appearance in old + new:
            key = json.dumps(appearance, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                seen.add(key)
                merged.append(appearance)
        return merged

    def merge_worklist(self, rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
        """Create or extend a worklist without changing existing identities."""
        incoming = [dict(row) for row in rows]
        for row in incoming:
            if not row.get("id"):
                raise ValueError("every worklist row needs a stable id")

        lock = self._lock()
        try:
            existing = _read_jsonl(self.worklist_path)
            by_id = {str(row["id"]): row for row in existing if row.get("id")}
            order = [str(row["id"]) for row in existing if row.get("id")]
            changed = not self.worklist_path.exists()
            for row in incoming:
                item_id = str(row["id"])
                if item_id not in by_id:
                    by_id[item_id] = row
                    order.append(item_id)
                    changed = True
                    continue
                current = by_id[item_id]
                merged_appearances = self._merge_appearances(
                    list(current.get("appearances") or []),
                    list(row.get("appearances") or []),
                )
                if merged_appearances != list(current.get("appearances") or []):
                    current = dict(current)
                    current["appearances"] = merged_appearances
                    by_id[item_id] = current
                    changed = True
            result = [by_id[item_id] for item_id in order]
            if changed or not self.worklist_path.exists():
                _atomic_jsonl(self.worklist_path, result)
            return result
        finally:
            lock.close()

    def worklist(self) -> list[dict[str, Any]]:
        return _read_jsonl(self.worklist_path)

    def save_request(self, request: dict[str, Any]) -> None:
        lock = self._lock()
        try:
            if self.request_path.exists():
                return
            _atomic_json(self.request_path, request)
        finally:
            lock.close()

    def request(self) -> dict[str, Any]:
        if not self.request_path.exists():
            raise FileNotFoundError(f"missing batch request: {self.request_path}")
        with self.request_path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            raise ValueError(f"invalid batch request: {self.request_path}")
        return value

    def append(self, row: dict[str, Any]) -> None:
        lock = self._lock()
        try:
            with self.ledger_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
        finally:
            lock.close()

    def append_header(self, **fields: Any) -> None:
        self.append({"record": "batch", "ts": now(), "batch": self.batch, **fields})

    def record(self, item: dict[str, Any], disposition: str, **fields: Any) -> dict[str, Any]:
        if disposition not in TERMINAL_DISPOSITIONS and disposition != "retryable":
            raise ValueError(f"unknown disposition: {disposition}")
        row = {
            "record": "item",
            "ts": now(),
            "id": str(item["id"]),
            "query": item.get("query") or item.get("title") or item.get("url") or "",
            "disposition": disposition,
            "source": item.get("source"),
            "appearances": list(item.get("appearances") or []),
            **fields,
        }
        lock = self._lock()
        try:
            with self.ledger_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            if disposition in TERMINAL_DISPOSITIONS:
                archived = self.archived()
                if row["id"] not in archived:
                    with self.archive_path.open("a", encoding="utf-8") as handle:
                        handle.write(row["id"] + "\n")
                        handle.flush()
                        os.fsync(handle.fileno())
        finally:
            lock.close()
        return row

    def ledger(self) -> list[dict[str, Any]]:
        return _read_jsonl(self.ledger_path)

    def final_rows(self) -> dict[str, dict[str, Any]]:
        final: dict[str, dict[str, Any]] = {}
        for row in self.ledger():
            if row.get("record") == "item" and row.get("id"):
                final[str(row["id"])] = row
        return final

    def archived(self) -> set[str]:
        if not self.archive_path.exists():
            return set()
        with self.archive_path.open(encoding="utf-8") as handle:
            return {line.strip() for line in handle if line.strip()}

    def reopen_capture_unavailable(self) -> list[str]:
        """Make no-capture holes runnable when a later resume has capture."""
        final = self.final_rows()
        reopen = {
            item_id
            for item_id, row in final.items()
            if row.get("disposition") == "fallthrough"
            and row.get("reason") == "capture_unavailable"
        }
        if not reopen:
            return []
        lock = self._lock()
        try:
            keep = sorted(self.archived() - reopen)
            text = "".join(f"{item_id}\n" for item_id in keep)
            fd, tmp_name = tempfile.mkstemp(prefix=".archive.", dir=self.path)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(text)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(tmp_name, self.archive_path)
            finally:
                try:
                    os.unlink(tmp_name)
                except FileNotFoundError:
                    pass
        finally:
            lock.close()
        return sorted(reopen)

    def status(self) -> dict[str, Any]:
        work = self.worklist()
        ids = {str(row["id"]) for row in work if row.get("id")}
        archived = self.archived() & ids
        final = self.final_rows()
        dispositions = collections.Counter(
            row.get("disposition", "unknown") for row in final.values()
        )
        total = len(ids)
        done = len(archived)
        retryable = sum(
            1 for row in final.values() if row.get("disposition") == "retryable"
        )

        headers = [row for row in self.ledger() if row.get("record") == "batch"]
        estimate_seconds = None
        if done and headers:
            try:
                started = datetime.fromisoformat(headers[0]["ts"])
                elapsed = max(0.0, (datetime.now(started.tzinfo) - started).total_seconds())
                estimate_seconds = round((total - done) * elapsed / done)
            except (KeyError, TypeError, ValueError):
                estimate_seconds = None

        return {
            "batch": self.batch,
            "total": total,
            "archived": done,
            "remaining": max(0, total - done),
            "completion": round(done / total, 6) if total else 1.0,
            "dispositions": dict(sorted(dispositions.items())),
            "retryable": retryable,
            "estimate_seconds": estimate_seconds,
            "last_header": headers[-1] if headers else None,
        }


def all_batch_statuses(root: Path) -> list[dict[str, Any]]:
    root = root.expanduser()
    if not root.exists():
        return []
    statuses = []
    for path in sorted(root.iterdir()):
        if path.is_dir() and (path / "worklist.jsonl").exists():
            statuses.append(BatchState(root, path.name).status())
    return statuses
