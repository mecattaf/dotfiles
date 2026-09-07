#!/usr/bin/env python3
"""Shape validator for one tally enqueue event (MEM-3).

    python3 tools/enqueue-row-check.py <file> [<file> ...]

Exit 0 when every file carries the live daemon's enqueue-event shape, 1 with
one reason per line on stderr otherwise. The module is also importable: the
harvest verb loads it by path and calls `validate_document` on every row it
builds *before* the row reaches the disk, so a malformed row is never written.

Where the required keys come from
--------------------------------
A 400-row random sample of the live daemon's own rows
(`~/.local/state/tally/events/*.enqueue.json`, 10,144 rows, read 2026-09-07)
carries exactly `REQUIRED_EVENT_KEYS` and `REQUIRED_ROW_KEYS` in *every* row.
`payloadHash` (379/400) and `briefHash` (300/400) are required here as well
because MEM-3's mechanism names them on a harvest row. Keys that only some
real rows carry — `jobTokenHash` (598/600), `ingressId`, `orchestration`,
`workspace`, `adapterOptions`, `ghOrigin`, `modelProvenance` — are optional and
type-checked when present;
unknown keys are allowed, because the daemon's shape grows by addition.

This validator reads rows. It never writes one, and it never touches
`~/.local/state/tally/`: crossing into the live events dir is a separate act
(DECISIONS D-E07).
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Callable, Mapping, Sequence

# Test seam: a comma-separated list of keys this validator drops from the
# document before it checks it, so a test can drive the refusal path with a row
# the writer built correctly rather than by hand-forging a broken file. A key
# may name a row field with a `row.` prefix. Unset in every real run.
TEST_SEAM_ENV = "ENQUEUE_ROW_CHECK_DROP_KEYS"

UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}"
    r"-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
KNOWN_PRIORITIES = ("low", "medium", "high")
MAX_ROW_BYTES = 256_000


def is_bool(value: object) -> bool:
    return isinstance(value, bool)


def is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_str(value: object) -> bool:
    return isinstance(value, str)


def is_dict(value: object) -> bool:
    return isinstance(value, dict)


def is_uuid(value: object) -> bool:
    return isinstance(value, str) and UUID_RE.match(value) is not None


def is_hash(value: object) -> bool:
    return isinstance(value, str) and HASH_RE.match(value) is not None


def is_str_list(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def is_list(value: object) -> bool:
    return isinstance(value, list)


def optional(predicate: Callable[[object], bool]) -> Callable[[object], bool]:
    return lambda value: value is None or predicate(value)


# The required-keys lists. Dropping a name from either one is the mutation the
# unit's card names: a document missing that key would then be kept.
REQUIRED_EVENT_KEYS: dict[str, tuple[str, Callable[[object], bool]]] = {
    "schemaVersion": ("an integer", is_int),
    "eventId": ("a uuid string", is_uuid),
    "acknowledged": ("a boolean", is_bool),
    "guardrailDepth": ("an integer", is_int),
    "row": ("an object", is_dict),
}

REQUIRED_ROW_KEYS: dict[str, tuple[str, Callable[[object], bool]]] = {
    "rowVersion": ("an integer", is_int),
    "uuid": ("a uuid string", is_uuid),
    "description": ("a string", is_str),
    "priority": (f"one of {', '.join(KNOWN_PRIORITIES)}", lambda v: v in KNOWN_PRIORITIES),
    "source": ("a string", is_str),
    "adapter": ("a string", is_str),
    "pool": ("a list of strings", is_str_list),
    "model": ("a string or null", optional(is_str)),
    "cwd": ("a string or null", optional(is_str)),
    "dedupKey": ("a string or null", optional(is_str)),
    "payloadHash": ("a sha256:<hex> string or null", optional(is_hash)),
    "briefHash": ("a sha256:<hex> string or null", optional(is_hash)),
    "sessionRef": ("a string or null", optional(is_str)),
    "leaseEpoch": ("an integer", is_int),
    "attempt": ("an integer", is_int),
    "argv": ("a list of strings", is_str_list),
    "evidence": ("a list of strings", is_str_list),
    "parentUuid": ("a uuid string or null", optional(is_uuid)),
    "consumptionEstimate": ("a number or null", optional(is_number)),
    "runtimeMaxSec": ("an integer or null", optional(is_int)),
    "noEnqueue": ("a boolean", is_bool),
    "credentials": ("an object", is_dict),
    "origin": ("an object", is_dict),
    "relatedTrigger": ("an object or null", optional(is_dict)),
    "evidenceClass": ("an object or null", optional(is_dict)),
    "manifestHash": ("a sha256:<hex> string or null", optional(is_hash)),
}

OPTIONAL_EVENT_KEYS: dict[str, tuple[str, Callable[[object], bool]]] = {
    "ingressId": ("a string", is_str),
}

OPTIONAL_ROW_KEYS: dict[str, tuple[str, Callable[[object], bool]]] = {
    "jobTokenHash": ("a sha256:<hex> string or null", optional(is_hash)),
    "orchestration": ("an object or null", optional(is_dict)),
    "workspace": ("an object or null", optional(is_dict)),
    "adapterOptions": ("an object or null", optional(is_dict)),
    "ghOrigin": ("an object or null", optional(is_dict)),
    "modelProvenance": ("a string or null", optional(is_str)),
}

REQUIRED_ORIGIN_KEYS: dict[str, tuple[str, Callable[[object], bool]]] = {
    "schemaVersion": ("an integer", is_int),
    "source": ("a string", is_str),
}


def apply_test_seam(
    document: Mapping[str, object],
    environ: Mapping[str, str] | None = None,
) -> dict[str, object]:
    """Drop the keys named by the test seam from a copy of `document`.

    A no-op unless `ENQUEUE_ROW_CHECK_DROP_KEYS` is set, which no real run
    does. The copy is shallow apart from `row`, which is copied when a `row.`
    key is dropped, so the caller's document is never mutated.
    """
    environ = os.environ if environ is None else environ
    raw = environ.get(TEST_SEAM_ENV, "")
    names = [name.strip() for name in raw.split(",") if name.strip()]
    copy = dict(document)
    if not names:
        return copy
    for name in names:
        if name.startswith("row."):
            row = copy.get("row")
            if isinstance(row, Mapping):
                trimmed = dict(row)
                trimmed.pop(name[len("row.") :], None)
                copy["row"] = trimmed
        else:
            copy.pop(name, None)
    return copy


def check_keys(
    value: Mapping[str, object],
    required: Mapping[str, tuple[str, Callable[[object], bool]]],
    optional_keys: Mapping[str, tuple[str, Callable[[object], bool]]],
    prefix: str,
) -> list[str]:
    reasons: list[str] = []
    for key, (description, predicate) in required.items():
        if key not in value:
            reasons.append(f"{prefix}{key} is missing")
        elif not predicate(value[key]):
            reasons.append(f"{prefix}{key} must be {description}")
    for key, (description, predicate) in optional_keys.items():
        if key in value and not predicate(value[key]):
            reasons.append(f"{prefix}{key} must be {description}")
    return reasons


def validate_document(
    document: object,
    environ: Mapping[str, str] | None = None,
) -> list[str]:
    """Every reason this document is not an enqueue event; empty means valid."""
    if not isinstance(document, Mapping):
        return ["the document is not a JSON object"]
    checked = apply_test_seam(document, environ)

    reasons = check_keys(checked, REQUIRED_EVENT_KEYS, OPTIONAL_EVENT_KEYS, "")
    if checked.get("schemaVersion") not in (None, 1) and is_int(
        checked.get("schemaVersion")
    ):
        reasons.append("schemaVersion must be 1")

    row = checked.get("row")
    if not isinstance(row, Mapping):
        return reasons
    reasons += check_keys(row, REQUIRED_ROW_KEYS, OPTIONAL_ROW_KEYS, "row.")

    origin = row.get("origin")
    if isinstance(origin, Mapping):
        reasons += check_keys(origin, REQUIRED_ORIGIN_KEYS, {}, "row.origin.")
    return reasons


def check_file(path: Path, environ: Mapping[str, str] | None = None) -> list[str]:
    """`validate_document` plus the two things only a file can be asked."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return [f"{path}: unreadable ({exc})"]
    if len(raw) > MAX_ROW_BYTES:
        return [f"{path}: {len(raw)} bytes exceeds the {MAX_ROW_BYTES}-byte bound"]
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return [f"{path}: not JSON ({exc})"]

    reasons = [f"{path}: {reason}" for reason in validate_document(document, environ)]
    if isinstance(document, Mapping):
        event_id = document.get("eventId")
        expected = f"{event_id}.enqueue.json"
        if isinstance(event_id, str) and path.name != expected:
            reasons.append(f"{path}: file name must be {expected}")
    return reasons


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments or arguments[0] in ("-h", "--help"):
        sys.stderr.write(
            "usage: enqueue-row-check.py <file> [<file> ...]\n"
            "  exit 0 when every file carries the daemon's enqueue-row shape\n"
        )
        return 0 if arguments else 2
    reasons: list[str] = []
    for argument in arguments:
        reasons += check_file(Path(argument))
    for reason in reasons:
        sys.stderr.write(f"enqueue-row-check: {reason}\n")
    return 1 if reasons else 0


if __name__ == "__main__":
    raise SystemExit(main())
