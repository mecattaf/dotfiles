"""Bounded metadata for an ordinary SSH shell, without retaining its PTY.

The original process, boot and owned terminal remain the liveness authority.
An expired UUID stays reserved until its metadata is explicitly archived.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import replace
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import stat
import uuid

from .capabilities import harness
from .sessions import MAX_CATALOGUE_METADATA_BYTES, Session, SessionError, SessionStore, validate_id

MAX_DIRECT_RECORDS = 4096
MAX_RECORD_BYTES = 32768


class DirectRegistry:
    def __init__(self, store: SessionStore | None = None):
        self.store = store or SessionStore()

    @contextmanager
    def _directory(self, create=False):
        root = os.open(self.store.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            _private(root, True)
            if create:
                try:
                    os.mkdir('direct', 0o700, dir_fd=root)
                except FileExistsError:
                    pass
            directory = os.open('direct', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
        finally:
            os.close(root)
        try:
            _private(directory, True)
            yield directory
        finally:
            os.close(directory)

    def known(self, identity: str) -> bool:
        """Reserve expired identities too; a read never allocates metadata."""
        validate_id(identity)
        try:
            with self._directory() as directory:
                return _read(directory, identity) is not None
        except FileNotFoundError:
            return False

    def context_matches(self, identity: str, context: str) -> bool:
        """Validate a hook against this direct terminal's original owner only."""
        validate_id(identity)
        try:
            with self._directory() as directory:
                record = _read(directory, identity)
        except FileNotFoundError:
            return False
        return (record is not None and _alive(record)
                and json.loads(record['terminal_context']) == json.loads(context))

    def get(self, identity: str) -> dict | None:
        validate_id(identity)
        try:
            with self._directory() as directory:
                record = _read(directory, identity)
        except FileNotFoundError:
            return None
        if record is None:
            return None
        if not _alive(record):
            raise SessionError('direct terminal ended or its original owner is unavailable')
        return _public(record)

    def list(self) -> list[dict]:
        try:
            with self._directory() as directory:
                records = _inventory(directory)
        except FileNotFoundError:
            return []
        return [_public(record) for record in records if _alive(record)]

    def register(self, session: Session, context: str, *, window_class: str | None = None,
                 kitty_window_id: int | None = None) -> dict:
        _frontend(window_class, kitty_window_id)
        try:
            harness.validate_terminal_context(context)
        except (OSError, ValueError) as error:
            raise SessionError('direct terminal original owner is unavailable') from error
        timestamp = datetime.now(timezone.utc).isoformat(timespec='seconds')
        session = replace(session, status='active', created_at=timestamp, updated_at=timestamp)
        record = {'version': 1, 'session': session.to_dict(), 'terminal_context': context,
                  'boot_id': _boot(), 'window_class': window_class, 'kitty_window_id': kitty_window_id}
        with self.store._lock():
            try:
                self.store.get(session.id)
            except SessionError as error:
                if not str(error).startswith('unknown session:'):
                    raise
            else:
                raise SessionError('a durable terminal already used this identity')
            with self._directory(create=True) as directory:
                if _read(directory, session.id) is not None:
                    raise SessionError('a direct terminal already used this identity')
                _capacity(_inventory(directory), record)
                _write(directory, session.id, record)
        return _public(record)

    def add_links(self, identity: str, *, chat_ids=(), workspace_id=None, title=None) -> dict:
        validate_id(identity)
        with self.store._lock(), self._directory() as directory:
            record = _read(directory, identity)
            if record is None or not _alive(record):
                raise SessionError('direct terminal ended or is unavailable')
            current = Session.from_dict(record['session'])
            changes = {'chat_ids': tuple(dict.fromkeys((*current.chat_ids, *chat_ids))),
                       'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds')}
            if workspace_id is not None:
                changes['workspace_id'] = workspace_id
            if title is not None:
                changes['title'] = title
            updated = {**record, 'session': replace(current, **changes).to_dict()}
            others = [value for value in _inventory(directory) if value['session']['id'] != identity]
            _capacity(others, updated)
            _write(directory, identity, updated)
            return _public(updated)


def _boot() -> str:
    return str(uuid.UUID(Path('/proc/sys/kernel/random/boot_id').read_text().strip()))


def _frontend(window_class, kitty_window_id) -> None:
    if window_class is not None and (not isinstance(window_class, str)
            or not re.fullmatch(r'agencykitty-[a-f0-9]{32}', window_class)):
        raise SessionError('direct frontend class must identify an explicitly launched Kitty OS window')
    if kitty_window_id is not None and (type(kitty_window_id) is not int or not 0 < kitty_window_id < 2**31):
        raise SessionError('direct Kitty window id must be a bounded positive integer')


def _private(descriptor: int, directory=False) -> None:
    info = os.fstat(descriptor)
    expected = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if not expected or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SessionError('direct terminal metadata must be private and owned')


def _read(directory: int, identity: str) -> dict | None:
    validate_id(identity)
    try:
        descriptor = os.open(identity + '.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    except FileNotFoundError:
        return None
    with os.fdopen(descriptor, 'rb') as source:
        _private(source.fileno())
        raw = source.read(MAX_RECORD_BYTES + 1)
    if len(raw) > MAX_RECORD_BYTES:
        raise SessionError('direct terminal record exceeds its bound')
    record = json.loads(raw)
    if (not isinstance(record, dict) or set(record) != {'version', 'session', 'terminal_context', 'boot_id', 'window_class', 'kitty_window_id'}
            or record['version'] != 1 or not isinstance(record['terminal_context'], str)
            or len(record['terminal_context']) > 2048 or not isinstance(record['boot_id'], str)):
        raise SessionError('invalid direct terminal record')
    session = Session.from_dict(record['session'])
    if session.id != identity or session.status != 'active':
        raise SessionError('direct terminal record identity changed')
    try:
        uuid.UUID(record['boot_id'])
    except ValueError as error:
        raise SessionError('invalid direct terminal boot identity') from error
    _frontend(record['window_class'], record['kitty_window_id'])
    return record


def _alive(record: dict) -> bool:
    if record['boot_id'] != _boot():
        return False
    try:
        harness.validate_terminal_context(record['terminal_context'])
    except (OSError, ValueError):
        return False
    return True


def _public(record: dict) -> dict:
    session = dict(record['session'])
    session.pop('holder_version')
    return {**session, 'mode': 'direct', 'resumable': False, 'live': True,
            'provider': 'agency-kitty', 'transport': 'ssh',
            'window_class': record['window_class'], 'kitty_window_id': record['kitty_window_id']}


def _inventory(directory: int) -> list[dict]:
    names = []
    with os.scandir(directory) as entries:
        for index, entry in enumerate(entries):
            if index >= MAX_DIRECT_RECORDS:
                raise SessionError('direct terminal inventory exceeds its record limit; archive ended metadata explicitly')
            if entry.name.endswith('.json'):
                names.append(entry.name[:-5])
    records, total = [], 0
    for identity in sorted(names):
        record = _read(directory, identity)
        if record is None:
            raise SessionError('direct terminal metadata disappeared during inventory')
        total += len(_encoded(record))
        if total > MAX_CATALOGUE_METADATA_BYTES:
            raise SessionError('direct terminal inventory exceeds its metadata bound; archive ended metadata explicitly')
        records.append(record)
    return records


def _encoded(record: dict) -> bytes:
    data = json.dumps(record, ensure_ascii=False, separators=(',', ':')).encode() + b'\n'
    if len(data) > MAX_RECORD_BYTES:
        raise SessionError('direct terminal record exceeds its bound')
    return data


def _capacity(records: list[dict], addition: dict) -> None:
    if len(records) >= MAX_DIRECT_RECORDS:
        raise SessionError('direct terminal inventory exceeds its record limit; archive ended metadata explicitly')
    if sum(len(_encoded(value)) for value in [*records, addition]) > MAX_CATALOGUE_METADATA_BYTES:
        raise SessionError('direct terminal inventory exceeds its metadata bound; archive ended metadata explicitly')


def _write(directory: int, identity: str, record: dict) -> None:
    raw = _encoded(record)
    temporary = '.direct-' + uuid.uuid4().hex
    descriptor = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600, dir_fd=directory)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(raw); output.flush(); os.fsync(output.fileno())
        os.replace(temporary, identity + '.json', src_dir_fd=directory, dst_dir_fd=directory)
        os.fsync(directory)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass
