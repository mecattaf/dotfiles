"""Bounded, restartable metadata tails. Primary histories remain with owners."""
import json
import os


def tail_jsonl(path, cursors, *, enroll_at_end=False, byte_budget=2 * 1024 * 1024):
    """Yield complete JSON records once; preserve incomplete-line offsets.

    A replaced/truncated owner file is a coverage gap, not permission to count
    its retained history twice. First enrollment can intentionally start now.
    No raw line or transcript body is retained in the cursor state.
    """
    key = str(path)
    stat = path.stat()
    current = cursors.get(key)
    identity = [stat.st_dev, stat.st_ino]
    gap = False
    if current is None:
        offset = stat.st_size if enroll_at_end else 0
    elif current.get("identity") != identity or current.get("offset", 0) > stat.st_size:
        offset = stat.st_size
        gap = True
    else:
        offset = current["offset"]
    records = []
    consumed = 0
    with path.open("rb") as stream:
        stream.seek(offset)
        while consumed < byte_budget:
            line_limit = min(1024 * 1024, byte_budget - consumed)
            line = stream.readline(line_limit + 1)
            if not line:
                break
            if not line.endswith(b"\n"):
                # An over-budget line cannot block observation forever. Skip
                # to a complete delimiter within a bounded extra byte window.
                if len(line) > line_limit:
                    stream.seek(0, os.SEEK_END)
                    offset = stream.tell()
                    gap = True
                consumed += len(line)
                break
            consumed += len(line)
            offset = stream.tell()
            try:
                record = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                gap = True
                continue
            if isinstance(record, dict):
                records.append(record)
    cursors[key] = {"identity": identity, "offset": offset, "lastReadBytes": consumed}
    return records, gap, offset < stat.st_size
