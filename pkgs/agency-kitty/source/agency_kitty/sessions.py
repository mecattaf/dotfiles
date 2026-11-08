"""Stable identities and bounded metadata; this module never owns a terminal."""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import tempfile
from typing import Iterator
import uuid

MAX_SESSION_RECORDS = 4096
# Leave room below the 1 MiB SSH response cap for JSON framing/default spaces
# and the catalogue's metadata projection. No terminal content belongs here.
MAX_CATALOGUE_METADATA_BYTES = 512 * 1024


class SessionError(ValueError):
    """Invalid identity, metadata, or stored session state."""


def validate_id(value: str) -> str:
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError, TypeError) as exc:
        raise SessionError("session id must be a canonical UUID") from exc
    if str(parsed) != value or parsed.version != 4:
        raise SessionError("session id must be a canonical UUID4")
    return value


def _text(value: str, field: str, limit: int, *, empty: bool = True) -> str:
    if not isinstance(value, str) or len(value) > limit or (not empty and not value):
        raise SessionError(f"invalid {field}")
    if any(ord(c) < 32 or 127 <= ord(c) < 160 for c in value):
        raise SessionError(f"{field} contains control characters")
    return value


def validate_cwd(value: str) -> str:
    _text(value, "cwd", 4096, empty=False)
    if not value.startswith("/"):
        raise SessionError("cwd must be an absolute NAS path")
    return os.path.normpath(value)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass(frozen=True)
class Session:
    id: str
    host: str = "nas"
    cwd: str = "/home/tom/today"
    title: str = ""
    workspace_id: str | None = None
    chat_ids: tuple[str, ...] = ()
    status: str = "created"
    created_at: str = ""
    updated_at: str = ""
    schema_version: int = 1
    holder_version: str = "1.0.1-agency.3"

    def __post_init__(self) -> None:
        validate_id(self.id)
        if self.host != "nas":
            raise SessionError("only the NAS identity is supported")
        if self.schema_version != 1:
            raise SessionError("unsupported session schema")
        if not isinstance(self.holder_version, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+-]{0,63}", self.holder_version):
            raise SessionError("invalid holder version")
        if self.status not in {"created", "active", "detached", "closed"}:
            raise SessionError("invalid session status")
        object.__setattr__(self, "cwd", validate_cwd(self.cwd))
        _text(self.title, "title", 256)
        if self.workspace_id is not None:
            _text(self.workspace_id, "workspace id", 128, empty=False)
        if not isinstance(self.chat_ids, (list, tuple)) or len(self.chat_ids) > 64:
            raise SessionError("chat_ids must contain at most 64 ids")
        for chat_id in self.chat_ids:
            if not isinstance(chat_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", chat_id):
                raise SessionError("invalid DSH chat id")
        object.__setattr__(self, "chat_ids", tuple(self.chat_ids))
        for timestamp in (self.created_at, self.updated_at):
            _text(timestamp, "timestamp", 64)

    def to_dict(self) -> dict:
        result = asdict(self)
        result["chat_ids"] = list(self.chat_ids)
        return result

    @classmethod
    def from_dict(cls, value: dict) -> "Session":
        if not isinstance(value, dict):
            raise SessionError("session record must be an object")
        try:
            return cls(**value)
        except (TypeError, KeyError) as exc:
            raise SessionError("invalid session record") from exc


class SessionStore:
    """Small private JSON records, serialized updates, and atomic replacement.

    Metadata is not proof that a PTY is still running. The remote holder is the
    authority for liveness, and callers must not treat a cached `active` value
    as an attachment receipt.
    """

    def __init__(self, root: str | Path | None = None):
        if root is None:
            state = os.environ.get("AGENCY_KITTY_STATE_DIR")
            root = Path(state) if state else Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "agency-kitty"
        self.root = Path(root)
        self.records = self.root / "sessions"

    def _prepare(self) -> None:
        for path in (self.root, self.records):
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
            fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                info = os.fstat(fd)
                if info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise SessionError("session directories must be private and owned by this user")
            finally:
                os.close(fd)

    @contextmanager
    def _lock(self) -> Iterator[None]:
        self._prepare()
        fd = os.open(self.root / ".sessions.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def _path(self, session_id: str) -> Path:
        return self.records / f"{validate_id(session_id)}.json"

    def _read(self, session_id: str) -> Session:
        path = self._path(session_id)
        try:
            # Verify both directories without following a leaf symlink. Read
            # through the verified records fd, so replacement of its pathname
            # cannot redirect a record read into another directory.
            root_fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                root_info = os.fstat(root_fd)
                if root_info.st_uid != os.getuid() or root_info.st_mode & 0o077:
                    raise SessionError("session state directory is not private")
                directory_fd = os.open("sessions", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root_fd)
            finally:
                os.close(root_fd)
            try:
                directory_info = os.fstat(directory_fd)
                if directory_info.st_uid != os.getuid() or directory_info.st_mode & 0o077:
                    raise SessionError("session records directory is not private")
                fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
            finally:
                os.close(directory_fd)
            with os.fdopen(fd, "rb") as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise SessionError("session record must be a private regular file owned by this user")
                raw = source.read(32769)
            if len(raw) > 32768:
                raise SessionError("session record exceeds size limit")
            value = json.loads(raw)
        except FileNotFoundError as exc:
            raise SessionError(f"unknown session: {session_id}") from exc
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise SessionError(f"corrupt session record: {session_id}") from exc
        session = Session.from_dict(value)
        if session.id != session_id:
            raise SessionError("session record identity does not match its filename")
        return session

    def _write(self, session: Session) -> None:
        fd, name = tempfile.mkstemp(prefix=".session-", suffix=".json", dir=self.records)
        try:
            with os.fdopen(fd, "w") as output:
                json.dump(session.to_dict(), output, ensure_ascii=False, sort_keys=True)
                output.write("\n")
                output.flush()
                os.fsync(output.fileno())
            os.replace(name, self._path(session.id))
            directory_fd = os.open(self.records, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    def create(self, *, cwd: str = "/home/tom/today", title: str = "", workspace_id: str | None = None,
               chat_ids: tuple[str, ...] | list[str] = (), session_id: str | None = None,
               holder_version: str = "1.0.1-agency.3") -> Session:
        timestamp = _now()
        session = Session(id=session_id or str(uuid.uuid4()), cwd=cwd, title=title,
                          workspace_id=workspace_id, chat_ids=tuple(chat_ids), created_at=timestamp,
                          updated_at=timestamp, holder_version=holder_version)
        with self._lock():
            if self._path(session.id).exists():
                raise SessionError(f"session already exists: {session.id}")
            from .direct_registry import DirectRegistry
            if DirectRegistry(self).known(session.id):
                raise SessionError(f"a direct terminal already used this identity: {session.id}")
            self._write(session)
        return session

    def get(self, session_id: str) -> Session:
        return self._read(session_id)

    def list(self, *, include_closed: bool = False) -> list[Session]:
        try:
            root_info = self.root.lstat()
        except FileNotFoundError:
            return []
        if not stat.S_ISDIR(root_info.st_mode) or root_info.st_uid != os.getuid() or root_info.st_mode & 0o077:
            raise SessionError("session state directory is not private")
        try:
            self.records.lstat()
        except FileNotFoundError:
            return []
        sessions = []
        total = 0
        # The record and aggregate byte bounds apply before constructing a
        # response, including closed records that may later be filtered out.
        # scandir yields entries incrementally; glob+sorted could allocate an
        # unbounded directory listing before the catalogue checked its limit.
        with self._lock():
            fd = os.open(self.records, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                names = []
                with os.scandir(fd) as entries:
                    for index, entry in enumerate(entries):
                        if index >= MAX_SESSION_RECORDS:
                            raise SessionError("session inventory exceeds its record limit; archive metadata explicitly")
                        if entry.name.endswith(".json"):
                            names.append(entry.name[:-5])
                for identity in sorted(names):
                    session = self._read(identity)
                    total += len(json.dumps(session.to_dict(), ensure_ascii=False).encode("utf-8")) + 2
                    if total > MAX_CATALOGUE_METADATA_BYTES:
                        raise SessionError("session inventory exceeds its metadata byte limit; archive metadata explicitly")
                    sessions.append(session)
            finally:
                os.close(fd)
        return sorted((s for s in sessions if include_closed or s.status != "closed"),
                      key=lambda s: (s.created_at, s.id), reverse=True)

    def update(self, session_id: str, **changes) -> Session:
        allowed = {"title", "workspace_id", "chat_ids", "status"}
        if changes.keys() - allowed:
            raise SessionError("only title, workspace_id, chat_ids and status may be updated")
        with self._lock():
            current = self._read(session_id)
            if current.status == "closed" and changes.get("status", "closed") != "closed":
                raise SessionError("closed identities cannot be reused")
            session = replace(current, **changes, updated_at=_now())
            self._write(session)
            return session

    def mark_closed(self, session_id: str) -> Session:
        return self.update(session_id, status="closed")

    def add_links(self, session_id: str, *, chat_ids: tuple[str, ...] | list[str] = (),
                  workspace_id: str | None = None, title: str | None = None) -> Session:
        """Merge incoming links under the same lock as the read and replacement."""
        with self._lock():
            current = self._read(session_id)
            if current.status == "closed":
                raise SessionError("cannot link a closed session")
            changes = {"chat_ids": tuple(dict.fromkeys((*current.chat_ids, *chat_ids))), "updated_at": _now()}
            if workspace_id is not None:
                changes["workspace_id"] = workspace_id
            if title is not None:
                changes["title"] = title
            session = replace(current, **changes)
            self._write(session)
            return session
