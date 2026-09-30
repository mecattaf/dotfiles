#!/usr/bin/env python3
"""land — copy-then-verify landing tool for preservation packets (CNA-M07).

A "lane" is one pile of working files that has to reach the notes repository
intact: the nightly ``~/today`` sweep, the loose ``~/*.md``, a dated directory,
Downloads, a root relocation. `land copy` writes a *packet*: the copied tree
plus two artifacts at its root, ``preservation-<YYYY-MM-DD>.json`` and
``README.md``. `land verify` re-derives every claim the manifest makes, and
`land diff` proves the source and the copy are the same bytes before anybody
removes a source.

The manifest shape is the one built by hand for
notes/references/continuity/2026-09-16-orchestration-day — header with
file_count, total_bytes and exclusions carrying reasons, rows of
{source, preserved, bytes, sha256, mtime, source_session}. Older packets omit
mtime and source_session; verify warns about those rows, it does not fail them.

Rules the copy obeys, all of them because a packet is evidence and not a backup:
  * sources are never modified, moved or removed — land only reads them;
  * ``cp -p`` semantics (mtime and mode preserved), relative structure kept;
  * a regular file over the 95 MiB ceiling is left out, with its reason, and
    named in the README under "Left out on purpose";
  * a nested ``.git`` directory or gitfile is renamed to ``dot-git`` in the
    copy (notes never tracks a nested repository) and the row records the
    packet-relative path it would have had, as ``renamed_from``;
  * symlinks are never followed — each becomes a row with ``kind: symlink``
    and its ``target``, and the link is recreated verbatim in the copy;
  * the secret guard runs over the whole plan BEFORE the first byte is
    written, so an abort leaves no half-packet behind. It names the file it
    tripped on and never the value it matched.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path, PurePosixPath

TOOL = "land 1"
MANIFEST_GLOB = "preservation-*.json"
README_NAME = "README.md"

# GitHub refuses a blob over 100 MiB; the ceiling sits under it with room for
# the packet's own artifacts. Apparent size (st_size), so a sparse file is
# judged by what a copy would cost, not by the blocks it occupies today.
MAX_FILE_BYTES = 95 * 1024 * 1024

READ_CHUNK = 1 << 20

SECRET_NAME_GLOBS = (
    "*.env",
    "*token*",
    "*secret*",
    "*credential*",
    "id_ed25519*",
    "*.age",
)

SECRET_CONTENT_PATTERNS = (
    ("GitHub personal access token", re.compile(rb"ghp_[A-Za-z0-9]{20,}")),
    ("OpenAI-style API key", re.compile(rb"sk-[A-Za-z0-9]{20,}")),
    ("AWS access key id", re.compile(rb"AKIA[0-9A-Z]{16}")),
    ("PEM private key block", re.compile(rb"-----BEGIN .*PRIVATE KEY")),
)


class LandError(Exception):
    """Anything that must stop the run with a named cause and no partial packet."""


# --------------------------------------------------------------------------
# small helpers


def iso_mtime(timestamp: float) -> str:
    """Local time with offset, seconds resolution: 2026-09-16T11:45:53+02:00."""
    return datetime.fromtimestamp(timestamp).astimezone().isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(READ_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def human_bytes(count: int) -> str:
    return f"{count:,}"


CEILING_TEXT = f"95 MiB ({human_bytes(MAX_FILE_BYTES)} bytes)"


def looks_binary(path: Path) -> bool:
    with open(path, "rb") as handle:
        return b"\0" in handle.read(8192)


def scan_for_secrets(path: Path) -> str | None:
    """Return the NAME of the first pattern that matches, never the match."""
    if looks_binary(path):
        return None
    tail = b""
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(READ_CHUNK), b""):
            window = tail + chunk
            for name, pattern in SECRET_CONTENT_PATTERNS:
                if pattern.search(window):
                    return name
            tail = window[-256:]
    return None


def secret_name_hit(name: str) -> str | None:
    lowered = name.lower()
    for glob in SECRET_NAME_GLOBS:
        if fnmatch.fnmatch(lowered, glob):
            return glob
    return None


# --------------------------------------------------------------------------
# planning


class Item:
    """One planned row. `rel` is the packet-relative preserved path."""

    __slots__ = ("source", "rel", "kind", "renamed_from", "size", "mtime", "mode", "target")

    def __init__(self, source: Path, rel: PurePosixPath, kind: str) -> None:
        self.source = source
        self.rel = rel
        self.kind = kind
        self.renamed_from: str | None = None
        self.size = 0
        self.mtime = 0.0
        self.mode = 0o644
        self.target: str | None = None


def excluded_by(rel: PurePosixPath, globs: tuple[str, ...]) -> str | None:
    text = str(rel)
    for glob in globs:
        if fnmatch.fnmatch(text, glob) or fnmatch.fnmatch(rel.name, glob):
            return glob
    return None


def plan_lane(
    sources: list[Path], excludes: tuple[str, ...]
) -> tuple[list[Item], list[dict[str, str]]]:
    """Walk the sources without following a single symlink. Deterministic order."""
    items: list[Item] = []
    excluded: list[dict[str, str]] = []

    def note_exclusion(path: Path, reason: str) -> None:
        excluded.append({"path": str(path), "reason": reason})

    def take(source: Path, rel: PurePosixPath, renamed_from: str | None) -> None:
        stat_result = os.lstat(source)
        if os.path.islink(source):
            item = Item(source, rel, "symlink")
            item.target = os.readlink(source)
            item.size = stat_result.st_size
            item.mtime = stat_result.st_mtime
            item.renamed_from = renamed_from
            items.append(item)
            return
        if not os.path.isfile(source):
            note_exclusion(source, "not a regular file, directory or symlink")
            return
        if stat_result.st_size > MAX_FILE_BYTES:
            note_exclusion(
                source,
                f"{human_bytes(stat_result.st_size)} bytes, over the "
                f"{CEILING_TEXT} per-file ceiling",
            )
            return
        item = Item(source, rel, "file")
        item.size = stat_result.st_size
        item.mtime = stat_result.st_mtime
        item.mode = stat_result.st_mode
        item.renamed_from = renamed_from
        items.append(item)

    def walk(
        directory: Path,
        rel_dir: PurePosixPath,
        source_rel_dir: PurePosixPath,
        renamed_above: bool,
    ) -> None:
        """rel_dir is the path inside the packet, source_rel_dir the one at the source.

        The two diverge the moment a `.git` is renamed, and `renamed_from` has to
        name the SOURCE side — that is the whole point of recording it.
        """
        try:
            entries = sorted(os.scandir(directory), key=lambda e: e.name)
        except PermissionError as exc:
            note_exclusion(directory, f"unreadable: {exc.strerror}")
            return
        files = [e for e in entries if not e.is_dir(follow_symlinks=False)]
        directories = [e for e in entries if e.is_dir(follow_symlinks=False)]
        for entry in files + directories:
            name = entry.name
            renamed = name == ".git"
            rel = rel_dir / ("dot-git" if renamed else name)
            source_rel = source_rel_dir / name
            glob = excluded_by(rel, excludes) or excluded_by(source_rel, excludes)
            if glob:
                note_exclusion(Path(entry.path), f"matched --exclude {glob}")
                continue
            renamed_from = str(source_rel) if (renamed or renamed_above) else None
            if entry.is_dir(follow_symlinks=False):
                walk(Path(entry.path), rel, source_rel, renamed or renamed_above)
            else:
                take(Path(entry.path), rel, renamed_from)

    for source in sources:
        if not os.path.lexists(source):
            raise LandError(f"source does not exist: {source}")
        name = source.name
        renamed = name == ".git"
        rel = PurePosixPath("dot-git" if renamed else name)
        glob = excluded_by(rel, excludes)
        if glob:
            note_exclusion(source, f"matched --exclude {glob}")
            continue
        source_rel = PurePosixPath(name)
        if os.path.isdir(source) and not os.path.islink(source):
            walk(source, rel, source_rel, renamed)
        else:
            take(source, rel, str(source_rel) if renamed else None)

    return items, excluded


def guard_secrets(items: list[Item], allow_names: bool) -> None:
    """Abort the whole run on the first hit. Names only, never values."""
    offences: list[str] = []
    for item in items:
        if item.kind != "file":
            continue
        if not allow_names:
            glob = secret_name_hit(item.source.name)
            if glob:
                offences.append(f"{item.source}: name matches {glob}")
                continue
        try:
            hit = scan_for_secrets(item.source)
        except OSError as exc:
            raise LandError(f"cannot read {item.source}: {exc.strerror}") from exc
        if hit:
            offences.append(f"{item.source}: contains what looks like a {hit}")
    if not offences:
        return
    lines = ["land copy: refusing to write a packet, the secret guard tripped:"]
    lines += [f"  {offence}" for offence in offences]
    lines.append("Nothing was written. Move or redact the file, exclude it with")
    lines.append("--exclude, or pass --allow-secret-names for a name-only hit.")
    raise LandError("\n".join(lines))


# --------------------------------------------------------------------------
# copy


def copy_lane(
    items: list[Item], dest: Path, source_session: str | None
) -> list[dict[str, object]]:
    """cp -p, then hash BOTH sides. A copy that did not land is an error here."""
    rows: list[dict[str, object]] = []
    for item in items:
        target = dest / item.rel
        target.parent.mkdir(parents=True, exist_ok=True)
        row: dict[str, object] = {
            "source": str(item.source),
            "preserved": str(target),
        }
        if item.kind == "symlink":
            if target.is_symlink() or target.exists():
                target.unlink()
            os.symlink(item.target, target)
            row["kind"] = "symlink"
            row["target"] = item.target
            row["bytes"] = item.size
            row["sha256"] = sha256_bytes(os.fsencode(item.target))
        else:
            before = sha256_file(item.source)
            shutil.copy2(item.source, target, follow_symlinks=False)
            after = sha256_file(target)
            if before != after:
                raise LandError(
                    f"copy did not land intact: {item.source} -> {target} "
                    "(source changed under the copy, or the destination is faulty)"
                )
            row["bytes"] = item.size
            row["sha256"] = after
        row["mtime"] = iso_mtime(item.mtime)
        if source_session:
            row["source_session"] = source_session
        if item.renamed_from:
            row["renamed_from"] = item.renamed_from
        rows.append(row)
    return rows


def common_source_root(sources: list[Path]) -> str:
    parents = [str(source.parent) for source in sources]
    try:
        return os.path.commonpath(parents)
    except ValueError:
        return ""


# --------------------------------------------------------------------------
# packet reading


def find_manifest(packet: Path) -> Path:
    matches = sorted(packet.glob(MANIFEST_GLOB))
    if not matches:
        raise LandError(f"no {MANIFEST_GLOB} in {packet}")
    if len(matches) > 1:
        names = ", ".join(m.name for m in matches)
        raise LandError(f"{packet} holds more than one manifest: {names}")
    return matches[0]


def load_manifest(packet: Path) -> tuple[Path, dict]:
    path = find_manifest(packet)
    try:
        with open(path, "rb") as handle:
            return path, json.load(handle)
    except json.JSONDecodeError as exc:
        raise LandError(f"{path} is not valid JSON: {exc}") from exc


def resolve_preserved(packet: Path, manifest: dict, preserved: str) -> Path:
    """Absolute path if it is still there, else re-root it on this packet dir.

    A packet that was moved (or is being checked out of the repository at a
    different path) must still verify — the manifest's preserved_root is what
    makes the row relative again.
    """
    candidate = Path(preserved)
    if candidate.exists() or candidate.is_symlink():
        return candidate
    root = manifest.get("preserved_root")
    if root:
        try:
            return packet / Path(preserved).relative_to(root)
        except ValueError:
            pass
    return candidate


def packet_file_count(packet: Path, manifest_name: str) -> int:
    """`find <packet> -type f`, minus the packet's own two artifacts."""
    count = 0
    for root, directories, files in os.walk(packet, followlinks=False):
        directories[:] = [d for d in directories if not os.path.islink(os.path.join(root, d))]
        for name in files:
            full = os.path.join(root, name)
            if os.path.islink(full):
                continue
            if Path(root) == packet and name in {manifest_name, README_NAME}:
                continue
            count += 1
    return count


# --------------------------------------------------------------------------
# verify


def verify_packet(packet: Path, quiet: bool = False) -> tuple[bool, list[str], dict[str, int]]:
    manifest_path, manifest = load_manifest(packet)
    rows = manifest.get("files")
    if not isinstance(rows, list):
        raise LandError(f"{manifest_path} has no files[] array")

    failures: list[str] = []
    warnings: list[str] = []
    # Row failures and packet-shape failures are kept apart so the receipt can
    # say which one actually happened: a manifest that covers only part of its
    # directory (every hash right, the count wrong) is a different fault from a
    # tampered file, and reporting the first as "sha256 MISMATCH" is a lie.
    file_rows = 0
    symlink_rows = 0
    total_bytes = 0

    for index, row in enumerate(rows):
        preserved = row.get("preserved")
        if not preserved:
            failures.append(f"row {index} has no preserved path")
            continue
        path = resolve_preserved(packet, manifest, preserved)
        expected = row.get("sha256")
        kind = row.get("kind", "file")
        if "mtime" not in row:
            warnings.append(f"{preserved}: no mtime recorded (pre-land packet)")
        if "source_session" not in row:
            warnings.append(f"{preserved}: no source_session recorded (pre-land packet)")
        if kind == "symlink":
            symlink_rows += 1
            if not os.path.islink(path):
                failures.append(f"{preserved}: recorded as a symlink, is not one")
                continue
            target = os.readlink(path)
            if row.get("target") is not None and target != row["target"]:
                failures.append(f"{preserved}: symlink target changed")
                continue
            if expected and sha256_bytes(os.fsencode(target)) != expected:
                failures.append(f"{preserved}: symlink target does not match sha256")
            continue
        file_rows += 1
        if not path.is_file() or path.is_symlink():
            failures.append(f"{preserved}: missing from the packet")
            continue
        size = path.stat().st_size
        if row.get("bytes") is not None and size != row["bytes"]:
            failures.append(f"{preserved}: {size} bytes, manifest says {row['bytes']}")
            continue
        total_bytes += size
        if not expected:
            failures.append(f"{preserved}: no sha256 in the manifest")
            continue
        if sha256_file(path) != expected:
            failures.append(f"{preserved}: sha256 does not match")

    rows_before_shape_checks = len(failures)
    found = packet_file_count(packet, manifest_path.name)
    if found != file_rows:
        failures.append(
            f"count mismatch: {file_rows} manifest file rows, "
            f"{found} files under the packet (find -type f, minus the two artifacts)"
        )
    declared = manifest.get("file_count")
    if declared is not None and declared != file_rows:
        failures.append(f"header file_count {declared} != {file_rows} file rows")
    declared_bytes = manifest.get("total_bytes")
    if declared_bytes is not None and not failures and declared_bytes != total_bytes:
        failures.append(f"header total_bytes {declared_bytes} != {total_bytes} bytes on disk")

    counts = {
        "rows": len(rows),
        "files": file_rows,
        "symlinks": symlink_rows,
        "found": found,
        "bytes": total_bytes,
    }
    row_failures = rows_before_shape_checks
    if not quiet:
        for warning in warnings[:10]:
            print(f"land verify: warning: {warning}", file=sys.stderr)
        if len(warnings) > 10:
            print(
                f"land verify: warning: ... and {len(warnings) - 10} more rows "
                "without mtime/source_session",
                file=sys.stderr,
            )
        for failure in failures:
            print(f"land verify: FAIL: {failure}", file=sys.stderr)
        state = "OK" if not failures else "FAILED"
        symlink_note = f", {symlink_rows} symlinks" if symlink_rows else ""
        print(
            f"land verify {state}  {packet}  {file_rows} file rows == {found} files"
            f"{symlink_note}  {human_bytes(counts['bytes'])} bytes  "
            f"sha256 {'all match' if not row_failures else 'MISMATCH'}"
            f"{f'  {len(warnings)} warnings' if warnings else ''}"
        )
    return (not failures), warnings, counts


# --------------------------------------------------------------------------
# diff


def rsync_available() -> bool:
    return shutil.which("rsync") is not None


def rsync_differences(source: Path, target: Path) -> list[str]:
    command = ["rsync", "-rn", "--checksum", "-i", f"{source}/", f"{target}/"]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise LandError(f"rsync failed: {result.stderr.strip()}")
    return [
        line
        for line in result.stdout.splitlines()
        if line.strip() and not line.startswith(".")
    ]


def diff_source(packet: Path, source: Path) -> tuple[bool, list[str], str]:
    """Equivalence between one source and its copy inside the packet.

    Hashing is authoritative because a packet legitimately differs from its
    source in two recorded ways — the dot-git rename and the exclusions. rsync
    runs as a second opinion only when neither applies to this source.
    """
    _, manifest = load_manifest(packet)
    rows = manifest.get("files", [])
    source = Path(os.path.abspath(source))
    prefix = str(source) + os.sep
    relevant = [
        row
        for row in rows
        if row.get("source") == str(source) or str(row.get("source", "")).startswith(prefix)
    ]
    if not relevant:
        raise LandError(f"{packet} has no rows under {source}")

    problems: list[str] = []
    renamed = any(row.get("renamed_from") for row in relevant)
    excluded_paths = [entry["path"] for entry in manifest.get("excluded", [])]
    excluded_here = [
        path
        for path in excluded_paths
        if path == str(source) or path.startswith(prefix) or path.rstrip("/").startswith(prefix)
    ]

    seen: set[str] = set()
    for row in relevant:
        origin = Path(row["source"])
        seen.add(str(origin))
        preserved = resolve_preserved(packet, manifest, row["preserved"])
        if row.get("kind") == "symlink":
            if not os.path.islink(origin):
                problems.append(f"{origin}: source is no longer a symlink")
            elif os.readlink(origin) != row.get("target"):
                problems.append(f"{origin}: symlink target differs from the packet")
            continue
        if not origin.is_file() or origin.is_symlink():
            problems.append(f"{origin}: source file is gone")
            continue
        if sha256_file(origin) != row.get("sha256"):
            problems.append(f"{origin}: source bytes differ from the packet copy")
            continue
        if not preserved.is_file():
            problems.append(f"{row['preserved']}: missing from the packet")

    if source.is_dir() and not source.is_symlink():
        for root, directories, files in os.walk(source, followlinks=False):
            directories[:] = [
                d for d in directories if not os.path.islink(os.path.join(root, d))
            ]
            for name in files:
                full = os.path.join(root, name)
                if full in seen:
                    continue
                if os.path.islink(full):
                    continue
                if any(full == p or full.startswith(p.rstrip("/") + os.sep) for p in excluded_paths):
                    continue
                problems.append(f"{full}: present in the source, absent from the packet")

    method = "sha256 over every manifest row"
    if not problems and not renamed and not excluded_here and rsync_available():
        target = packet / source.name
        if target.is_dir():
            lines = rsync_differences(source, target)
            method = f"sha256 + rsync -rn --checksum ({len(lines)} transfer lines)"
            problems += [f"rsync would transfer: {line}" for line in lines]
    elif renamed or excluded_here:
        method = "sha256 over every manifest row (rsync skipped: renames/exclusions recorded)"
    elif not rsync_available():
        method = "sha256 over every manifest row (rsync not on PATH)"
    return (not problems), problems, method


# --------------------------------------------------------------------------
# README


def top_level_entries(dest: Path, manifest_name: str) -> list[tuple[str, bool]]:
    entries = []
    for entry in sorted(os.scandir(dest), key=lambda e: e.name):
        if entry.name in {manifest_name, README_NAME}:
            continue
        entries.append((entry.name, entry.is_dir(follow_symlinks=False)))
    return entries


def render_readme(
    title: str,
    sources: list[Path],
    manifest: dict,
    manifest_name: str,
    dest: Path,
    verification: list[tuple[str, str, str]],
    renames: list[dict[str, object]],
    symlinks: list[dict[str, object]],
) -> str:
    lines: list[str] = [f"# {title}", ""]
    lines.append(
        f"A packet landed by `{TOOL}` on {manifest['date']}: "
        f"{manifest['file_count']} files, {human_bytes(manifest['total_bytes'])} bytes, "
        "copied then verified. The sources were not modified, moved or removed."
    )
    lines += ["", "## Sources", ""]
    for source in sources:
        lines.append(f"- `{source}`")
    if manifest.get("source_session"):
        lines += ["", f"Source session: `{manifest['source_session']}`."]
    lines += ["", "## What is preserved", "", "| Entry | Kind |", "|---|---|"]
    for name, is_dir in top_level_entries(dest, manifest_name):
        lines.append(f"| `{name}` | {'directory' if is_dir else 'file'} |")
    lines += [
        "",
        f"{manifest['file_count']} files, {human_bytes(manifest['total_bytes'])} bytes.",
        f"Manifest: [{manifest_name}]({manifest_name}) — source path, preserved path,",
        "bytes, SHA-256 and mtime for every copied file, each row tagged with the source session.",
        "",
        "## Left out on purpose",
        "",
    ]
    if manifest["excluded"]:
        for entry in manifest["excluded"]:
            lines.append(f"- `{entry['path']}` — {entry['reason']}")
    else:
        lines.append(
            f"Nothing. No file exceeded the {CEILING_TEXT} per-file ceiling "
            "and no exclusion was given."
        )
    if renames:
        lines += [
            "",
            "## Nested repositories",
            "",
            f"{len(renames)} copied paths sat under a nested `.git`. Notes never tracks a nested",
            "repository, so each was renamed to `dot-git` in this copy; contents are unchanged and",
            "every affected manifest row carries `renamed_from` with the path it had at the source.",
            "The sources keep their original names.",
        ]
    if symlinks:
        lines += [
            "",
            "## Symlinks",
            "",
            f"{len(symlinks)} symlinks were recorded and recreated, never followed:",
            "",
        ]
        for row in symlinks[:20]:
            lines.append(f"- `{row['source']}` -> `{row['target']}`")
        if len(symlinks) > 20:
            lines.append(f"- ... and {len(symlinks) - 20} more, all in the manifest")
    lines += ["", "## Verification", "", "Run after the copy, against the preserved tree:", "", "```"]
    width = max(len(check) for check, _, _ in verification) + 2
    result_width = max(len(result) for _, result, _ in verification) + 2
    for check, result, status in verification:
        lines.append(f"{check.ljust(width)}{result.ljust(result_width)}{status}".rstrip())
    lines += ["```", ""]
    lines.append(
        "Reproduce with `land verify <this directory>` and "
        "`land diff <source> <this directory>`."
    )
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# commands


def cmd_copy(args: argparse.Namespace) -> int:
    sources = [Path(os.path.abspath(source)) for source in args.sources]
    dest = Path(os.path.abspath(args.dest))
    excludes = tuple(args.exclude or ())

    if dest.exists():
        existing = [
            entry.name
            for entry in os.scandir(dest)
            if entry.is_file(follow_symlinks=False) or entry.is_dir(follow_symlinks=False)
        ]
        if existing and not args.force:
            raise LandError(
                f"{dest} is not empty ({len(existing)} entries). A packet owns its "
                "directory: verify counts manifest rows against every file under it. "
                "Pick a fresh directory, or pass --force if you meant to add to this one."
            )
    for source in sources:
        if dest == source or str(dest).startswith(str(source) + os.sep):
            raise LandError(f"destination {dest} sits inside source {source}")

    items, excluded = plan_lane(sources, excludes)
    if not items:
        raise LandError("nothing to copy: the plan is empty")
    guard_secrets(items, args.allow_secret_names)

    dest.mkdir(parents=True, exist_ok=True)
    rows = copy_lane(items, dest, args.source_session)

    file_rows = [row for row in rows if row.get("kind") != "symlink"]
    symlink_rows = [row for row in rows if row.get("kind") == "symlink"]
    manifest_name = f"preservation-{date.today().isoformat()}.json"
    manifest: dict[str, object] = {
        "date": date.today().isoformat(),
        "packet": dest.name,
        "source_root": common_source_root(sources),
        "preserved_root": str(dest),
        "source_session": args.source_session,
        "file_count": len(file_rows),
        "total_bytes": sum(int(row["bytes"]) for row in file_rows),
        "symlink_count": len(symlink_rows),
        "max_file_bytes": MAX_FILE_BYTES,
        "tool": TOOL,
        "excluded": excluded,
        "files": rows,
    }
    manifest_path = dest / manifest_name
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1)
        handle.write("\n")

    ok, _, counts = verify_packet(dest, quiet=True)
    verification = [
        (
            "manifest rows == find -type f count",
            f"{counts['files']} == {counts['found']}",
            "exit 0" if counts["files"] == counts["found"] else "MISMATCH",
        ),
        (
            "sha256 recomputed over all manifest rows",
            f"{counts['files']} files {'OK' if ok else 'FAILED'}",
            "exit 0" if ok else "exit 1",
        ),
    ]
    diff_ok = True
    for source in sources:
        source_ok, problems, method = diff_source(dest, source)
        diff_ok = diff_ok and source_ok
        verification.append(
            (
                f"equivalence, {source.name}",
                "no differences" if source_ok else f"{len(problems)} differences",
                "exit 0" if source_ok else "exit 1",
            )
        )
        if not source_ok:
            for problem in problems[:20]:
                print(f"land copy: diff: {problem}", file=sys.stderr)
    if verification:
        method_line = method if sources else ""
        if method_line:
            verification.append(("equivalence method", method_line, ""))

    renames = [row for row in rows if row.get("renamed_from")]
    readme = render_readme(
        args.readme_title or dest.name,
        sources,
        manifest,
        manifest_name,
        dest,
        verification,
        renames,
        symlink_rows,
    )
    readme_path = dest / README_NAME
    if readme_path.exists() and not args.force:
        raise LandError(
            f"{readme_path} already exists; land wrote the copy and the manifest but "
            "will not overwrite a README. Move it aside and rerun, or pass --force."
        )
    readme_path.write_text(readme, encoding="utf-8")

    print(
        f"land copy {'OK' if ok and diff_ok else 'FAILED'}  {dest}  "
        f"{len(file_rows)} files"
        f"{f', {len(symlink_rows)} symlinks' if symlink_rows else ''}"
        f"{f', {len(renames)} dot-git renames' if renames else ''}  "
        f"{human_bytes(int(manifest['total_bytes']))} bytes  "
        f"{len(excluded)} left out  -> {manifest_name}"
    )
    return 0 if (ok and diff_ok) else 1


def cmd_verify(args: argparse.Namespace) -> int:
    packet = Path(os.path.abspath(args.packet))
    if not packet.is_dir():
        raise LandError(f"not a directory: {packet}")
    ok, _, _ = verify_packet(packet)
    return 0 if ok else 1


def cmd_diff(args: argparse.Namespace) -> int:
    packet = Path(os.path.abspath(args.packet))
    source = Path(os.path.abspath(args.source))
    ok, problems, method = diff_source(packet, source)
    for problem in problems[:50]:
        print(f"land diff: {problem}", file=sys.stderr)
    if len(problems) > 50:
        print(f"land diff: ... and {len(problems) - 50} more", file=sys.stderr)
    print(
        f"land diff {'OK' if ok else 'FAILED'}  {source} == {packet}  "
        f"{'no differences' if ok else str(len(problems)) + ' differences'}  ({method})"
    )
    return 0 if ok else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="land",
        description="Copy a lane into a preservation packet, then prove the copy.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    copy = sub.add_parser("copy", help="copy sources into a packet and write its manifest")
    copy.add_argument("sources", nargs="+", help="files or directories to preserve")
    copy.add_argument("--dest", required=True, help="the packet directory to write")
    copy.add_argument(
        "--exclude",
        action="append",
        metavar="GLOB",
        help="skip paths matching this glob (packet-relative path or basename); repeatable",
    )
    copy.add_argument("--source-session", help="session id stamped on every row")
    copy.add_argument("--readme-title", help="title line for the packet README")
    copy.add_argument(
        "--allow-secret-names",
        action="store_true",
        help="copy files whose NAME looks like a secret; content hits still abort",
    )
    copy.add_argument(
        "--force",
        action="store_true",
        help="write into a non-empty destination and overwrite an existing README",
    )
    copy.set_defaults(func=cmd_copy)

    verify = sub.add_parser("verify", help="recompute every hash and count in a packet")
    verify.add_argument("packet", help="the packet directory")
    verify.set_defaults(func=cmd_verify)

    diff = sub.add_parser("diff", help="prove a source and its copy are the same bytes")
    diff.add_argument("source", help="the original source path")
    diff.add_argument("packet", help="the packet directory")
    diff.set_defaults(func=cmd_diff)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except LandError as exc:
        print(f"land: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
