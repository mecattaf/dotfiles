#!/usr/bin/env python3
"""Build and populate an index-preserving LaCie archive of R2 papers.

The archive has three deliberately separate layers:

* the untouched D1 SQL export and sidecar snapshot are evidence;
* papers.sqlite is the queryable local catalog keyed by the original db_id;
* originals/ and receipts/ are the verified local payloads and provenance.

This program never mutates D1 or R2.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import html.parser
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 2
SUCCESS_STATUSES = {
    "mirrored_r2_pdf",
    "recovered_from_landing",
    "recovered_from_archive_duplicate",
    "recovered_open_access_web",
    "existing_local_pdf",
}
RETRYABLE_STATUSES = {
    "pending",
    "r2_fetch_error",
    "unresolved_landing_no_link",
    "unresolved_landing_links_failed",
    "unexpected_r2_payload",
}
USER_AGENT = "mecattaf-paper-archive/1.0"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def atomic_copy(source: Path, destination: Path) -> None:
    """Copy a finished file into place without exposing a partial version."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with source.open("rb") as input_handle, os.fdopen(fd, "wb") as output_handle:
            shutil.copyfileobj(input_handle, output_handle, length=1 << 20)
            output_handle.flush()
            os.fsync(output_handle.fileno())
        os.replace(tmp_name, destination)
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def quote_url(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    path = urllib.parse.quote(parts.path, safe="/%:@")
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, path, parts.query, parts.fragment)
    )


def payload_kind(head: bytes) -> str:
    stripped = head.lstrip()
    lowered = stripped.lower()
    if head.startswith(b"%PDF-"):
        return "pdf"
    if lowered.startswith(b"<!doctype html") or lowered.startswith(b"<html"):
        return "html"
    return "other"


def is_pdf(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(5) == b"%PDF-"
    except OSError:
        return False


@dataclass(frozen=True)
class FetchResult:
    path: Path
    bytes: int
    sha256: str
    kind: str
    content_type: str | None
    final_url: str
    pdf_has_eof: bool | None


def fetch_to_temp(url: str, temp_dir: Path, timeout: int, retries: int) -> FetchResult:
    temp_dir.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        fd, tmp_name = tempfile.mkstemp(prefix=".download-", dir=temp_dir)
        os.close(fd)
        tmp_path = Path(tmp_name)
        digest = hashlib.sha256()
        head = b""
        tail = b""
        size = 0
        try:
            request = urllib.request.Request(
                quote_url(url),
                headers={
                    "User-Agent": USER_AGENT,
                    "Accept": "application/pdf,text/html;q=0.9,*/*;q=0.5",
                    "Accept-Encoding": "identity",
                },
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                content_type = response.headers.get_content_type()
                final_url = response.geturl()
                with tmp_path.open("wb") as output:
                    while True:
                        chunk = response.read(1 << 20)
                        if not chunk:
                            break
                        if len(head) < 64:
                            head += chunk[: 64 - len(head)]
                        tail = (tail + chunk)[-4096:]
                        output.write(chunk)
                        digest.update(chunk)
                        size += len(chunk)
                    output.flush()
                    os.fsync(output.fileno())
            kind = payload_kind(head)
            return FetchResult(
                path=tmp_path,
                bytes=size,
                sha256=digest.hexdigest(),
                kind=kind,
                content_type=content_type,
                final_url=final_url,
                pdf_has_eof=(b"%%EOF" in tail) if kind == "pdf" else None,
            )
        except Exception as error:  # network boundary: retain the final exception
            last_error = error
            tmp_path.unlink(missing_ok=True)
            if attempt < retries:
                time.sleep(min(8.0, 1.5 * attempt))
    assert last_error is not None
    raise last_error


class PdfLinkParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._href: str | None = None
        self._text: list[str] = []
        self.download_links: list[str] = []
        self.pdf_links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        self._href = dict(attrs).get("href")
        self._text = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a" or self._href is None:
            return
        href = self._href.strip()
        text = " ".join(self._text).strip().lower()
        if href:
            if "pdf download" in text or text == "download pdf":
                self.download_links.append(href)
            if ".pdf" in urllib.parse.urlsplit(href).path.lower():
                self.pdf_links.append(href)
        self._href = None
        self._text = []


def pdf_links_from_html(path: Path, base_url: str) -> list[str]:
    parser = PdfLinkParser()
    parser.feed(path.read_text(encoding="utf-8", errors="replace"))
    ordered: list[str] = []
    for href in parser.download_links + parser.pdf_links:
        candidate = urllib.parse.urljoin(base_url, href)
        if candidate not in ordered:
            ordered.append(candidate)
    return ordered


def ensure_archive_layout(archive: Path) -> None:
    for relative in (
        "catalog/sidecars",
        "catalog/source-records/ocr",
        "originals",
        "historical-originals/by-db-id",
        "historical-facsimiles/by-db-id",
        "r2-landing-pages",
        "r2-other-payloads",
        "receipts",
        "manifests",
    ):
        (archive / relative).mkdir(parents=True, exist_ok=True)


def iter_pdf_sidecars(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name.lower().endswith(".pdf.meta.json"):
            yield path


def import_d1_sql(connection: sqlite3.Connection, sql_path: Path) -> None:
    # Wrangler's D1 export is a sequence of bare statements.  Without an
    # explicit transaction SQLite durably commits every INSERT separately,
    # which is especially punishing on an external Btrfs disk.
    script = sql_path.read_text(encoding="utf-8")
    connection.executescript(f"BEGIN IMMEDIATE;\n{script}\nCOMMIT;\n")


LOCAL_SCHEMA = """
CREATE UNIQUE INDEX idx_files_id_archive ON files(id);

CREATE TABLE archive_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE paper_archive (
  db_id TEXT PRIMARY KEY,
  sidecar_path TEXT NOT NULL UNIQUE,
  r2_url TEXT NOT NULL UNIQUE,
  local_pdf_path TEXT NOT NULL UNIQUE,
  landing_page_path TEXT,
  other_payload_path TEXT,
  migration_status TEXT NOT NULL DEFAULT 'pending',
  r2_payload_kind TEXT,
  r2_payload_bytes INTEGER,
  r2_payload_sha256 TEXT,
  local_pdf_bytes INTEGER,
  local_pdf_sha256 TEXT,
  pdf_has_eof INTEGER,
  recovery_url TEXT,
  error TEXT,
  first_attempted_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (db_id) REFERENCES files(id)
);

CREATE INDEX idx_paper_archive_status ON paper_archive(migration_status);
CREATE INDEX idx_paper_archive_local_sha ON paper_archive(local_pdf_sha256);

CREATE TABLE historical_purges (
  db_id TEXT,
  meta_path TEXT PRIMARY KEY,
  r2_url TEXT,
  r2_key TEXT,
  target_md_path TEXT,
  purge_action TEXT NOT NULL,
  ocr_db_id TEXT,
  notes TEXT
);

CREATE INDEX idx_historical_purges_db_id ON historical_purges(db_id);

CREATE TABLE ocr_derivatives (
  db_id TEXT PRIMARY KEY,
  source_json_path TEXT NOT NULL,
  r2_url TEXT,
  sidecar_path TEXT,
  source_sha256 TEXT,
  source_bytes INTEGER,
  page_count INTEGER,
  text_chars INTEGER,
  triage_tier TEXT,
  content_kind TEXT,
  canonical_markdown_path TEXT,
  prior_r2_purged INTEGER NOT NULL DEFAULT 0
);

CREATE VIEW current_papers AS
SELECT
  f.id AS db_id,
  f.filename,
  f.original_path,
  f.mime_type,
  f.size_bytes AS d1_size_bytes,
  f.r2_path,
  f.date_added,
  p.*
FROM files AS f
JOIN paper_archive AS p ON p.db_id = f.id;

CREATE VIEW purge_recovery AS
SELECT
  h.*,
  COALESCE(h.db_id, h.ocr_db_id) AS stable_db_id,
  o.source_json_path,
  o.source_sha256,
  o.page_count,
  o.canonical_markdown_path
FROM historical_purges AS h
LEFT JOIN ocr_derivatives AS o
  ON o.db_id = COALESCE(h.db_id, h.ocr_db_id);
"""


RECOVERY_SCHEMA = """
CREATE TABLE IF NOT EXISTS local_candidates (
  source_path TEXT PRIMARY KEY,
  source_root TEXT NOT NULL,
  filename TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  payload_kind TEXT NOT NULL,
  sha256 TEXT,
  last_seen_scan TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_local_candidates_name
  ON local_candidates(filename);
CREATE INDEX IF NOT EXISTS idx_local_candidates_size
  ON local_candidates(size_bytes);

CREATE TABLE IF NOT EXISTS historical_archive (
  db_id TEXT PRIMARY KEY,
  provenance_group TEXT NOT NULL,
  original_sidecar_path TEXT NOT NULL,
  original_r2_url TEXT,
  original_r2_key TEXT,
  desired_filename TEXT NOT NULL,
  migration_status TEXT NOT NULL DEFAULT 'pending_history',
  recovery_method TEXT,
  source_path TEXT,
  local_pdf_path TEXT UNIQUE,
  local_pdf_bytes INTEGER,
  local_pdf_sha256 TEXT,
  expected_source_bytes INTEGER,
  expected_source_sha256 TEXT,
  exact_source_hash_match INTEGER,
  candidate_count INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  updated_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_historical_archive_status
  ON historical_archive(migration_status);

CREATE TABLE IF NOT EXISTS web_recovery (
  db_id TEXT PRIMARY KEY,
  page_title TEXT,
  page_year INTEGER,
  page_authors TEXT,
  doi TEXT,
  matched_title TEXT,
  title_score REAL,
  discovery_source TEXT,
  open_access INTEGER,
  candidate_urls_json TEXT,
  selected_url TEXT,
  recovery_status TEXT NOT NULL,
  error TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (db_id) REFERENCES paper_archive(db_id)
);

CREATE INDEX IF NOT EXISTS idx_web_recovery_status
  ON web_recovery(recovery_status);
"""


def normalized_meta_path(path: str) -> str:
    marker = "/notes/"
    if marker in path:
        path = path.split(marker, 1)[1]
    path = path.removeprefix("references/")
    path = path.removeprefix("knowledge/")
    return path


def load_post_manifest(path: Path) -> dict[str, dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("entries", data) if isinstance(data, dict) else data
    return {entry["meta_path"]: entry for entry in entries if entry.get("meta_path")}


def find_canonical_markdown(source_json: Path) -> Path | None:
    paper_root = source_json.parent
    candidates = (
        paper_root / "canonical" / "paper.md",
        paper_root / "canonical" / "canonical.md",
        paper_root / "canonical.md",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    markdown = sorted((paper_root / "canonical").glob("*.md")) if (paper_root / "canonical").is_dir() else []
    return markdown[0] if markdown else None


def command_init(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    ensure_archive_layout(archive)
    database = archive / "catalog" / "papers.sqlite"
    if database.exists() and not args.refresh:
        raise SystemExit(f"catalog already exists: {database} (use --refresh to rebuild)")

    # Build the database on the local system disk.  The completed database is
    # copied atomically to LaCie once, avoiding thousands of external-drive
    # journal writes during import and index construction.
    fd, tmp_name = tempfile.mkstemp(prefix="papers-", suffix=".sqlite")
    os.close(fd)
    tmp_db = Path(tmp_name)
    tmp_db.unlink()
    warnings: list[str] = []
    try:
        connection = sqlite3.connect(tmp_db)
        connection.execute("PRAGMA foreign_keys = ON")
        print(json.dumps({"phase": "import_d1", "source": str(args.d1_sql)}), flush=True)
        import_d1_sql(connection, args.d1_sql)
        print(json.dumps({"phase": "join_sidecars"}), flush=True)
        connection.executescript(LOCAL_SCHEMA)
        connection.executescript(RECOVERY_SCHEMA)
        metadata = {
            "schema_version": str(SCHEMA_VERSION),
            "created_at": now_iso(),
            "d1_export_path": str(args.d1_sql.resolve()),
            "d1_export_sha256": sha256_file(args.d1_sql),
            "sidecar_snapshot": str(args.sidecars.resolve()),
        }
        connection.executemany(
            "INSERT INTO archive_meta(key, value) VALUES(?, ?)", metadata.items()
        )

        sidecar_count = 0
        for sidecar in iter_pdf_sidecars(args.sidecars):
            data = json.loads(sidecar.read_text(encoding="utf-8"))
            db_id = data.get("db_id") or data.get("id")
            r2_url = data.get("r2_url")
            if not db_id or not r2_url:
                warnings.append(f"sidecar missing db_id/r2_url: {sidecar}")
                continue
            relative = sidecar.relative_to(args.sidecars)
            pdf_relative = Path(str(relative)[: -len(".meta.json")])
            d1_row = connection.execute(
                "SELECT id, r2_url FROM files WHERE id = ?", (db_id,)
            ).fetchone()
            if d1_row is None:
                warnings.append(f"sidecar db_id absent from D1: {relative} ({db_id})")
                continue
            if d1_row[1] != r2_url:
                warnings.append(f"sidecar/D1 URL mismatch: {relative} ({db_id})")
            connection.execute(
                """
                INSERT INTO paper_archive(
                  db_id, sidecar_path, r2_url, local_pdf_path, migration_status
                ) VALUES (?, ?, ?, ?, 'pending')
                """,
                (
                    db_id,
                    str(Path("catalog/sidecars") / relative),
                    r2_url,
                    str(Path("originals") / pdf_relative),
                ),
            )
            sidecar_count += 1

        print(json.dumps({"phase": "join_ocr_and_purges"}), flush=True)
        post_manifest = load_post_manifest(args.post_manifest)
        ocr_by_normalized_path: dict[str, str] = {}
        ocr_count = 0
        for source_json in sorted(args.ocr_root.glob("*/source.json")):
            source = json.loads(source_json.read_text(encoding="utf-8"))
            db_id = source.get("db_id") or source.get("uuid")
            if not db_id:
                warnings.append(f"OCR source missing db_id: {source_json}")
                continue
            copied_source = archive / "catalog/source-records/ocr" / f"{db_id}.json"
            shutil.copy2(source_json, copied_source)
            canonical = find_canonical_markdown(source_json)
            normalized = normalized_meta_path(source.get("sidecar_path", ""))
            if normalized:
                ocr_by_normalized_path[normalized] = db_id
            connection.execute(
                """
                INSERT OR REPLACE INTO ocr_derivatives(
                  db_id, source_json_path, r2_url, sidecar_path, source_sha256,
                  source_bytes, page_count, text_chars, triage_tier, content_kind,
                  canonical_markdown_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    db_id,
                    str(copied_source.relative_to(archive)),
                    source.get("r2_url"),
                    source.get("sidecar_path"),
                    source.get("sha256"),
                    source.get("bytes"),
                    source.get("page_count"),
                    source.get("text_chars"),
                    source.get("triage_tier"),
                    source.get("content_kind"),
                    str(canonical) if canonical else None,
                ),
            )
            ocr_count += 1

        purged_count = 0
        with args.purge_log.open(encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
                record = json.loads(line)
                if record.get("action") != "PURGED":
                    continue
                meta_path = record["meta_path"]
                manifest_record = post_manifest.get(meta_path, {})
                normalized = normalized_meta_path(meta_path)
                connection.execute(
                    """
                    INSERT OR REPLACE INTO historical_purges(
                      db_id, meta_path, r2_url, r2_key, target_md_path,
                      purge_action, ocr_db_id, notes
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        manifest_record.get("db_id"),
                        meta_path,
                        manifest_record.get("url"),
                        record.get("cloud", "").removeprefix("r2:") or None,
                        manifest_record.get("target_md_path") or record.get("md"),
                        record["action"],
                        ocr_by_normalized_path.get(normalized),
                        None,
                    ),
                )
                purged_count += 1

        connection.execute(
            """
            UPDATE ocr_derivatives
            SET prior_r2_purged = 1
            WHERE db_id IN (
              SELECT COALESCE(db_id, ocr_db_id) FROM historical_purges
            )
            """
        )
        try:
            connection.execute(
                "CREATE VIRTUAL TABLE paper_search USING fts5(db_id UNINDEXED, filename, original_path, sidecar_path)"
            )
            connection.execute(
                """
                INSERT INTO paper_search(db_id, filename, original_path, sidecar_path)
                SELECT f.id, f.filename, f.original_path, p.sidecar_path
                FROM files f JOIN paper_archive p ON p.db_id = f.id
                """
            )
        except sqlite3.OperationalError as error:
            warnings.append(f"FTS5 unavailable: {error}")

        d1_pdf_count = connection.execute(
            "SELECT COUNT(*) FROM files WHERE lower(filename) LIKE '%.pdf'"
        ).fetchone()[0]
        if sidecar_count != d1_pdf_count:
            warnings.append(
                f"current sidecars ({sidecar_count}) != D1 PDF rows ({d1_pdf_count})"
            )
        purge_stable_count, purge_unique_stable_count, purge_id_mismatches = connection.execute(
            """
            SELECT
              COUNT(COALESCE(db_id, ocr_db_id)),
              COUNT(DISTINCT COALESCE(db_id, ocr_db_id)),
              SUM(CASE WHEN db_id IS NOT NULL AND ocr_db_id IS NOT NULL
                            AND db_id != ocr_db_id THEN 1 ELSE 0 END)
            FROM historical_purges
            """
        ).fetchone()
        if purge_stable_count != purged_count:
            warnings.append(
                f"historical purges with a stable ID ({purge_stable_count}) != purge rows ({purged_count})"
            )
        if purge_unique_stable_count != purged_count:
            warnings.append(
                f"unique historical purge IDs ({purge_unique_stable_count}) != purge rows ({purged_count})"
            )
        if purge_id_mismatches:
            warnings.append(
                f"historical purge manifest/OCR ID mismatches: {purge_id_mismatches}"
            )
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"SQLite integrity check failed: {integrity}")
        print(json.dumps({"phase": "verify_and_commit"}), flush=True)
        connection.commit()
        connection.close()
        atomic_copy(tmp_db, database)
        tmp_db.unlink()
    except BaseException:
        tmp_db.unlink(missing_ok=True)
        raise

    summary = {
        "created_at": now_iso(),
        "database": str(database),
        "d1_pdf_rows": d1_pdf_count,
        "current_pdf_sidecars": sidecar_count,
        "historical_purges": purged_count,
        "historical_purge_stable_ids": purge_stable_count,
        "ocr_derivatives": ocr_count,
        "warnings": warnings,
    }
    atomic_json(archive / "manifests/catalog-init.json", summary)
    print(json.dumps(summary, indent=2))
    return 0 if not warnings else 2


def clean_error(error: BaseException) -> str:
    if isinstance(error, urllib.error.HTTPError):
        return f"HTTP {error.code}: {error.reason}"
    if isinstance(error, urllib.error.URLError):
        return f"URL error: {error.reason}"
    return f"{type(error).__name__}: {error}"


def place_download(download: FetchResult, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    os.replace(download.path, destination)


def existing_receipt(archive: Path, db_id: str) -> dict[str, Any] | None:
    path = archive / "receipts" / f"{db_id}.json"
    if not path.is_file():
        return None
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
        local = receipt.get("local_pdf_path")
        if receipt.get("migration_status") in SUCCESS_STATUSES and local:
            local_path = archive / local
            if is_pdf(local_path) and local_path.stat().st_size == receipt.get("local_pdf_bytes"):
                receipt["resumed_from_receipt"] = True
                receipt["updated_at"] = now_iso()
                return receipt
    except (OSError, json.JSONDecodeError):
        return None
    return None


def mirror_one(
    archive: Path,
    row: sqlite3.Row,
    timeout: int,
    retries: int,
) -> dict[str, Any]:
    db_id = row["db_id"]
    prior = existing_receipt(archive, db_id)
    if prior is not None:
        return prior

    target = archive / row["local_pdf_path"]
    landing = archive / "r2-landing-pages" / f"{row['sidecar_path'].removeprefix('catalog/sidecars/')[:-len('.meta.json')]}.html"
    other = archive / "r2-other-payloads" / f"{row['sidecar_path'].removeprefix('catalog/sidecars/')[:-len('.meta.json')]}.bin"
    receipt: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "db_id": db_id,
        "filename": row["filename"],
        "original_path": row["original_path"],
        "sidecar_path": row["sidecar_path"],
        "r2_url": row["r2_url"],
        "r2_path": row["r2_path"],
        "d1_size_bytes": row["d1_size_bytes"],
        "local_pdf_path": row["local_pdf_path"],
        "first_attempted_at": row["first_attempted_at"] or now_iso(),
        "updated_at": now_iso(),
    }
    try:
        if target.is_file() and is_pdf(target):
            receipt.update(
                migration_status="existing_local_pdf",
                local_pdf_bytes=target.stat().st_size,
                local_pdf_sha256=sha256_file(target),
                pdf_has_eof=None,
            )
            return receipt

        r2_download = fetch_to_temp(row["r2_url"], archive / ".tmp", timeout, retries)
        receipt.update(
            r2_payload_kind=r2_download.kind,
            r2_payload_bytes=r2_download.bytes,
            r2_payload_sha256=r2_download.sha256,
            r2_content_type=r2_download.content_type,
            r2_final_url=r2_download.final_url,
            r2_size_matches_d1=(r2_download.bytes == row["d1_size_bytes"]),
        )
        if r2_download.kind == "pdf":
            place_download(r2_download, target)
            receipt.update(
                migration_status="mirrored_r2_pdf",
                local_pdf_bytes=r2_download.bytes,
                local_pdf_sha256=r2_download.sha256,
                pdf_has_eof=r2_download.pdf_has_eof,
            )
            return receipt

        if r2_download.kind == "html":
            place_download(r2_download, landing)
            receipt["landing_page_path"] = str(landing.relative_to(archive))
            candidates = pdf_links_from_html(landing, r2_download.final_url)
            receipt["recovery_candidates"] = candidates
            if not candidates:
                receipt["migration_status"] = "unresolved_landing_no_link"
                return receipt
            failures: list[dict[str, str]] = []
            for candidate in candidates:
                try:
                    recovered = fetch_to_temp(candidate, archive / ".tmp", timeout, retries)
                    if recovered.kind != "pdf":
                        failures.append(
                            {"url": candidate, "error": f"payload kind {recovered.kind}"}
                        )
                        recovered.path.unlink(missing_ok=True)
                        continue
                    place_download(recovered, target)
                    receipt.update(
                        migration_status="recovered_from_landing",
                        recovery_url=candidate,
                        local_pdf_bytes=recovered.bytes,
                        local_pdf_sha256=recovered.sha256,
                        pdf_has_eof=recovered.pdf_has_eof,
                    )
                    if failures:
                        receipt["recovery_failures_before_success"] = failures
                    return receipt
                except Exception as error:  # try the next archived candidate
                    failures.append({"url": candidate, "error": clean_error(error)})
            receipt.update(
                migration_status="unresolved_landing_links_failed",
                recovery_failures=failures,
            )
            return receipt

        place_download(r2_download, other)
        receipt.update(
            migration_status="unexpected_r2_payload",
            other_payload_path=str(other.relative_to(archive)),
        )
        return receipt
    except Exception as error:
        receipt.update(migration_status="r2_fetch_error", error=clean_error(error))
        return receipt


UPDATE_SQL = """
UPDATE paper_archive SET
  landing_page_path = :landing_page_path,
  other_payload_path = :other_payload_path,
  migration_status = :migration_status,
  r2_payload_kind = :r2_payload_kind,
  r2_payload_bytes = :r2_payload_bytes,
  r2_payload_sha256 = :r2_payload_sha256,
  local_pdf_bytes = :local_pdf_bytes,
  local_pdf_sha256 = :local_pdf_sha256,
  pdf_has_eof = :pdf_has_eof,
  recovery_url = :recovery_url,
  error = :error,
  first_attempted_at = :first_attempted_at,
  updated_at = :updated_at
WHERE db_id = :db_id
"""


def update_catalog(connection: sqlite3.Connection, receipt: dict[str, Any]) -> None:
    values = {
        "db_id": receipt["db_id"],
        "landing_page_path": receipt.get("landing_page_path"),
        "other_payload_path": receipt.get("other_payload_path"),
        "migration_status": receipt["migration_status"],
        "r2_payload_kind": receipt.get("r2_payload_kind"),
        "r2_payload_bytes": receipt.get("r2_payload_bytes"),
        "r2_payload_sha256": receipt.get("r2_payload_sha256"),
        "local_pdf_bytes": receipt.get("local_pdf_bytes"),
        "local_pdf_sha256": receipt.get("local_pdf_sha256"),
        "pdf_has_eof": receipt.get("pdf_has_eof"),
        "recovery_url": receipt.get("recovery_url"),
        "error": receipt.get("error"),
        "first_attempted_at": receipt.get("first_attempted_at"),
        "updated_at": receipt.get("updated_at", now_iso()),
    }
    connection.execute(UPDATE_SQL, values)


def write_manifests(archive: Path, connection: sqlite3.Connection) -> dict[str, Any]:
    connection.row_factory = sqlite3.Row
    rows = connection.execute(
        """
        SELECT db_id, filename, original_path, d1_size_bytes, sidecar_path,
               r2_url, r2_path, local_pdf_path, landing_page_path,
               migration_status, r2_payload_kind, r2_payload_bytes,
               r2_payload_sha256, local_pdf_bytes, local_pdf_sha256,
               pdf_has_eof, recovery_url, error, updated_at
        FROM current_papers ORDER BY original_path, db_id
        """
    ).fetchall()
    jsonl = "".join(
        json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    )
    atomic_text(archive / "manifests/papers.jsonl", jsonl)
    purge_rows = connection.execute(
        "SELECT * FROM purge_recovery ORDER BY meta_path"
    ).fetchall()
    atomic_text(
        archive / "manifests/historical-purges.jsonl",
        "".join(
            json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n"
            for row in purge_rows
        ),
    )
    ocr_rows = connection.execute(
        "SELECT * FROM ocr_derivatives ORDER BY db_id"
    ).fetchall()
    atomic_text(
        archive / "manifests/ocr-derivatives.jsonl",
        "".join(
            json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n"
            for row in ocr_rows
        ),
    )
    checksums = "".join(
        f"{row['local_pdf_sha256']}  {row['local_pdf_path']}\n"
        for row in rows
        if row["local_pdf_sha256"]
    )
    atomic_text(archive / "manifests/SHA256SUMS", checksums)
    status_rows = connection.execute(
        "SELECT migration_status, COUNT(*) AS n FROM paper_archive GROUP BY migration_status ORDER BY migration_status"
    ).fetchall()
    summary = {
        "generated_at": now_iso(),
        "total": len(rows),
        "status": {row["migration_status"]: row["n"] for row in status_rows},
        "local_pdf_count": sum(1 for row in rows if row["local_pdf_sha256"]),
        "local_pdf_bytes": sum(row["local_pdf_bytes"] or 0 for row in rows),
        "r2_payload_bytes_processed": sum(row["r2_payload_bytes"] or 0 for row in rows),
        "historical_purges": len(purge_rows),
        "ocr_derivatives": len(ocr_rows),
    }
    atomic_json(archive / "manifests/summary.json", summary)
    return summary


def command_mirror(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    database = archive / "catalog/papers.sqlite"
    if not database.is_file():
        raise SystemExit(f"catalog does not exist: {database}; run init first")
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    statuses = ["pending", "r2_fetch_error"]
    if args.retry_unresolved:
        statuses.extend(sorted(RETRYABLE_STATUSES - set(statuses)))
    placeholders = ",".join("?" for _ in statuses)
    sql = f"""
      SELECT f.id AS db_id, f.filename, f.original_path,
             f.mime_type, f.size_bytes AS d1_size_bytes, f.r2_path,
             p.sidecar_path, p.r2_url, p.local_pdf_path,
             p.first_attempted_at, p.migration_status
      FROM files f JOIN paper_archive p ON p.db_id = f.id
      WHERE p.migration_status IN ({placeholders})
      ORDER BY f.original_path, f.id
    """
    rows = connection.execute(sql, statuses).fetchall()
    if args.match:
        pattern = re.compile(args.match, re.IGNORECASE)
        rows = [
            row
            for row in rows
            if pattern.search(row["original_path"] or "")
            or pattern.search(row["filename"] or "")
            or pattern.search(row["db_id"])
        ]
    if args.limit:
        rows = rows[: args.limit]
    expected = sum(row["d1_size_bytes"] or 0 for row in rows)
    free = shutil.disk_usage(archive).free
    if expected > free:
        raise SystemExit(f"insufficient free space: need {expected}, have {free}")
    print(
        json.dumps(
            {
                "selected": len(rows),
                "expected_r2_bytes": expected,
                "free_bytes": free,
                "workers": args.workers,
            }
        ),
        flush=True,
    )

    counts: dict[str, int] = {}
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(mirror_one, archive, row, args.timeout, args.retries): row
            for row in rows
        }
        for index, future in enumerate(as_completed(futures), 1):
            receipt = future.result()
            receipt_path = archive / "receipts" / f"{receipt['db_id']}.json"
            atomic_json(receipt_path, receipt)
            update_catalog(connection, receipt)
            if index % 25 == 0 or index == len(rows):
                connection.commit()
            status = receipt["migration_status"]
            counts[status] = counts.get(status, 0) + 1
            if status not in SUCCESS_STATUSES or index % 25 == 0 or index == len(rows):
                with lock:
                    print(
                        json.dumps(
                            {
                                "progress": f"{index}/{len(rows)}",
                                "status": status,
                                "db_id": receipt["db_id"],
                                "original_path": receipt.get("original_path"),
                                "counts": counts,
                            },
                            ensure_ascii=False,
                        ),
                        flush=True,
                    )
    summary = write_manifests(archive, connection)
    connection.close()
    print(json.dumps(summary, indent=2))
    return 0


HISTORY_SUCCESS_STATUSES = {
    "recovered_exact_ocr_hash",
    "recovered_historical_path",
    "recovered_historical_basename",
    "recovered_from_orphan_r2",
}
HISTORY_LOCAL_PDF_STATUSES = HISTORY_SUCCESS_STATUSES | {
    "reconstructed_from_ocr_renders"
}


def normalized_name(value: str) -> str:
    name = Path(value).name
    if name.lower().endswith(".pdf"):
        name = name[:-4]
    decomposed = unicodedata.normalize("NFKD", name).casefold()
    return "".join(character for character in decomposed if character.isalnum())


def normalized_title(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value).casefold()
    return "".join(character for character in decomposed if character.isalnum())


def title_from_filename(filename: str) -> str:
    title = Path(filename).name
    if title.casefold().endswith(".pdf"):
        title = title[:-4]
    return " ".join(title.replace("_", " ").rstrip(". ").split())


def normalized_component(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value).casefold()
    return "".join(character for character in decomposed if character.isalnum())


def history_logical_path(sidecar_path: str) -> Path:
    path = sidecar_path
    if "/notes/" in path:
        path = path.split("/notes/", 1)[1]
    path = path.removeprefix("references/")
    path = path.removeprefix("knowledge/")
    return Path(path.removesuffix(".meta.json"))


def matching_tail_components(candidate: Path, logical: Path) -> int:
    candidate_parts = [normalized_component(part) for part in candidate.parts]
    logical_parts = [normalized_component(part) for part in logical.parts]
    matched = 0
    for candidate_part, logical_part in zip(
        reversed(candidate_parts), reversed(logical_parts)
    ):
        if candidate_part != logical_part:
            break
        matched += 1
    return matched


def seed_historical_archive(connection: sqlite3.Connection) -> None:
    connection.executescript(RECOVERY_SCHEMA)
    purge_rows = connection.execute(
        """
        SELECT
          COALESCE(h.db_id, h.ocr_db_id) AS db_id,
          h.meta_path,
          COALESCE(h.r2_url, o.r2_url) AS r2_url,
          h.r2_key,
          o.source_bytes,
          o.source_sha256
        FROM historical_purges h
        LEFT JOIN ocr_derivatives o
          ON o.db_id = COALESCE(h.db_id, h.ocr_db_id)
        ORDER BY h.meta_path
        """
    ).fetchall()
    for row in purge_rows:
        logical = history_logical_path(row["meta_path"])
        connection.execute(
            """
            INSERT INTO historical_archive(
              db_id, provenance_group, original_sidecar_path, original_r2_url,
              original_r2_key, desired_filename, expected_source_bytes,
              expected_source_sha256
            ) VALUES (?, 'prior_r2_purge', ?, ?, ?, ?, ?, ?)
            ON CONFLICT(db_id) DO UPDATE SET
              provenance_group = excluded.provenance_group,
              original_sidecar_path = excluded.original_sidecar_path,
              original_r2_url = excluded.original_r2_url,
              original_r2_key = excluded.original_r2_key,
              desired_filename = excluded.desired_filename,
              expected_source_bytes = excluded.expected_source_bytes,
              expected_source_sha256 = excluded.expected_source_sha256
            """,
            (
                row["db_id"],
                row["meta_path"],
                row["r2_url"],
                row["r2_key"],
                logical.name,
                row["source_bytes"],
                row["source_sha256"],
            ),
        )

    orphan_rows = connection.execute(
        """
        SELECT db_id, sidecar_path, r2_url, source_bytes, source_sha256
        FROM ocr_derivatives
        WHERE prior_r2_purged = 0
        ORDER BY db_id
        """
    ).fetchall()
    for row in orphan_rows:
        logical = history_logical_path(row["sidecar_path"])
        connection.execute(
            """
            INSERT INTO historical_archive(
              db_id, provenance_group, original_sidecar_path, original_r2_url,
              desired_filename, expected_source_bytes, expected_source_sha256
            ) VALUES (?, 'ocr_without_purge_log', ?, ?, ?, ?, ?)
            ON CONFLICT(db_id) DO UPDATE SET
              provenance_group = excluded.provenance_group,
              original_sidecar_path = excluded.original_sidecar_path,
              original_r2_url = excluded.original_r2_url,
              desired_filename = excluded.desired_filename,
              expected_source_bytes = excluded.expected_source_bytes,
              expected_source_sha256 = excluded.expected_source_sha256
            """,
            (
                row["db_id"],
                row["sidecar_path"],
                row["r2_url"],
                logical.name,
                row["source_bytes"],
                row["source_sha256"],
            ),
        )
    connection.commit()


def scan_local_candidates(
    connection: sqlite3.Connection,
    archive: Path,
    label: str,
    root: Path,
) -> int:
    root = root.resolve()
    if not root.is_dir():
        raise SystemExit(f"candidate root is not a directory: {root}")
    scan_id = now_iso()
    count = 0
    batch: list[tuple[Any, ...]] = []
    sql = """
      INSERT INTO local_candidates(
        source_path, source_root, filename, size_bytes, payload_kind,
        last_seen_scan
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_path) DO UPDATE SET
        source_root = excluded.source_root,
        filename = excluded.filename,
        sha256 = CASE
          WHEN local_candidates.size_bytes = excluded.size_bytes
           AND local_candidates.payload_kind = excluded.payload_kind
          THEN local_candidates.sha256 ELSE NULL END,
        size_bytes = excluded.size_bytes,
        payload_kind = excluded.payload_kind,
        last_seen_scan = excluded.last_seen_scan
    """
    for directory, directories, filenames in os.walk(root):
        directory_path = Path(directory)
        directories[:] = [
            name
            for name in directories
            if (directory_path / name).resolve() != archive
        ]
        if directory_path.resolve() == archive:
            directories[:] = []
            continue
        for filename in filenames:
            if not filename.lower().endswith(".pdf"):
                continue
            candidate = directory_path / filename
            try:
                size = candidate.stat().st_size
                with candidate.open("rb") as handle:
                    kind = payload_kind(handle.read(64))
            except OSError:
                continue
            batch.append((str(candidate), label, filename, size, kind, scan_id))
            count += 1
            if len(batch) >= 500:
                connection.executemany(sql, batch)
                connection.commit()
                batch.clear()
    if batch:
        connection.executemany(sql, batch)
    connection.execute(
        "DELETE FROM local_candidates WHERE source_root = ? AND last_seen_scan != ?",
        (label, scan_id),
    )
    connection.commit()
    return count


def local_candidate_hash(
    connection: sqlite3.Connection, candidate: sqlite3.Row
) -> str:
    if candidate["sha256"]:
        return candidate["sha256"]
    cached = connection.execute(
        "SELECT sha256 FROM local_candidates WHERE source_path = ?",
        (candidate["source_path"],),
    ).fetchone()
    if cached and cached[0]:
        return cached[0]
    path = Path(candidate["source_path"])
    digest = sha256_file(path)
    connection.execute(
        "UPDATE local_candidates SET sha256 = ? WHERE source_path = ?",
        (digest, candidate["source_path"]),
    )
    return digest


def set_history_status(
    connection: sqlite3.Connection,
    db_id: str,
    status: str,
    *,
    candidate_count: int,
    error: str | None = None,
) -> None:
    connection.execute(
        """
        UPDATE historical_archive SET
          migration_status = ?, candidate_count = ?, error = ?, updated_at = ?
        WHERE db_id = ?
        """,
        (status, candidate_count, error, now_iso(), db_id),
    )


def archive_history_source(
    archive: Path,
    connection: sqlite3.Connection,
    history: sqlite3.Row,
    source: Path,
    source_sha256: str,
    status: str,
    method: str,
    candidate_count: int,
) -> None:
    destination = (
        archive
        / "historical-originals/by-db-id"
        / history["db_id"]
        / history["desired_filename"]
    )
    if not destination.is_file() or sha256_file(destination) != source_sha256:
        atomic_copy(source, destination)
    destination_sha256 = sha256_file(destination)
    if not is_pdf(destination) or destination_sha256 != source_sha256:
        raise RuntimeError(f"historical recovery verification failed: {destination}")
    size = destination.stat().st_size
    exact_match = (
        1
        if history["expected_source_sha256"]
        and destination_sha256 == history["expected_source_sha256"]
        and size == history["expected_source_bytes"]
        else 0
    )
    connection.execute(
        """
        UPDATE historical_archive SET
          migration_status = ?, recovery_method = ?, source_path = ?,
          local_pdf_path = ?, local_pdf_bytes = ?, local_pdf_sha256 = ?,
          exact_source_hash_match = ?, candidate_count = ?, error = NULL,
          updated_at = ?
        WHERE db_id = ?
        """,
        (
            status,
            method,
            str(source),
            str(destination.relative_to(archive)),
            size,
            destination_sha256,
            exact_match,
            candidate_count,
            now_iso(),
            history["db_id"],
        ),
    )
    receipt = {
        "schema_version": SCHEMA_VERSION,
        "db_id": history["db_id"],
        "provenance_group": history["provenance_group"],
        "original_sidecar_path": history["original_sidecar_path"],
        "original_r2_url": history["original_r2_url"],
        "original_r2_key": history["original_r2_key"],
        "migration_status": status,
        "recovery_method": method,
        "source_path": str(source),
        "local_pdf_path": str(destination.relative_to(archive)),
        "local_pdf_bytes": size,
        "local_pdf_sha256": destination_sha256,
        "expected_source_bytes": history["expected_source_bytes"],
        "expected_source_sha256": history["expected_source_sha256"],
        "exact_source_hash_match": bool(exact_match),
        "candidate_count": candidate_count,
        "updated_at": now_iso(),
    }
    atomic_json(archive / "receipts/historical" / f"{history['db_id']}.json", receipt)


def write_history_manifests(
    archive: Path, connection: sqlite3.Connection
) -> dict[str, Any]:
    connection.row_factory = sqlite3.Row
    candidates = connection.execute(
        "SELECT * FROM local_candidates ORDER BY source_path"
    ).fetchall()
    atomic_text(
        archive / "manifests/local-candidates.jsonl",
        "".join(
            json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n"
            for row in candidates
        ),
    )
    history = connection.execute(
        "SELECT * FROM historical_archive ORDER BY provenance_group, original_sidecar_path"
    ).fetchall()
    atomic_text(
        archive / "manifests/historical-archive.jsonl",
        "".join(
            json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n"
            for row in history
        ),
    )
    statuses = connection.execute(
        "SELECT migration_status, COUNT(*) FROM historical_archive GROUP BY migration_status ORDER BY migration_status"
    ).fetchall()
    summary = {
        "generated_at": now_iso(),
        "local_candidates": len(candidates),
        "local_candidate_payloads": {
            row[0]: row[1]
            for row in connection.execute(
                "SELECT payload_kind, COUNT(*) FROM local_candidates GROUP BY payload_kind"
            )
        },
        "historical_records": len(history),
        "status": {row[0]: row[1] for row in statuses},
        "recovered_pdfs": sum(
            1 for row in history if row["migration_status"] in HISTORY_SUCCESS_STATUSES
        ),
        "reconstructed_facsimiles": sum(
            1
            for row in history
            if row["migration_status"] == "reconstructed_from_ocr_renders"
        ),
        "local_historical_pdfs": sum(
            1 for row in history if row["migration_status"] in HISTORY_LOCAL_PDF_STATUSES
        ),
        "recovered_bytes": sum(row["local_pdf_bytes"] or 0 for row in history),
    }
    atomic_json(archive / "manifests/historical-summary.json", summary)
    return summary


def command_recover_history(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    database = archive / "catalog/papers.sqlite"
    if not database.is_file():
        raise SystemExit(f"catalog does not exist: {database}; run init first")
    ensure_archive_layout(archive)
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    seed_historical_archive(connection)

    for label, root in args.candidate_root:
        print(
            json.dumps({"phase": "scan_local_candidates", "label": label, "root": str(root)}),
            flush=True,
        )
        count = scan_local_candidates(connection, archive, label, root)
        print(json.dumps({"phase": "scan_complete", "candidates": count}), flush=True)

    candidates = connection.execute(
        "SELECT * FROM local_candidates WHERE payload_kind = 'pdf' ORDER BY source_path"
    ).fetchall()
    by_size: dict[int, list[sqlite3.Row]] = {}
    by_name: dict[str, list[sqlite3.Row]] = {}
    for candidate in candidates:
        by_size.setdefault(candidate["size_bytes"], []).append(candidate)
        by_name.setdefault(normalized_name(candidate["filename"]), []).append(candidate)

    history_rows = connection.execute(
        "SELECT * FROM historical_archive ORDER BY provenance_group, original_sidecar_path"
    ).fetchall()
    expected_sizes = {
        row["expected_source_bytes"]
        for row in history_rows
        if row["expected_source_bytes"] is not None
    }
    hash_candidates = [
        candidate
        for size in expected_sizes
        for candidate in by_size.get(size, [])
    ]
    print(
        json.dumps(
            {
                "phase": "hash_expected_size_candidates",
                "candidate_files": len(hash_candidates),
            }
        ),
        flush=True,
    )
    for candidate in hash_candidates:
        local_candidate_hash(connection, candidate)
    connection.commit()

    for index, history in enumerate(history_rows, 1):
        db_id = history["db_id"]
        if not history["desired_filename"].lower().endswith(".pdf"):
            set_history_status(
                connection,
                db_id,
                "non_pdf_source_record",
                candidate_count=0,
            )
            continue

        logical = history_logical_path(history["original_sidecar_path"])
        name_candidates = by_name.get(normalized_name(history["desired_filename"]), [])
        chosen: sqlite3.Row | None = None
        chosen_hash: str | None = None
        status: str | None = None
        method: str | None = None

        if history["expected_source_sha256"]:
            exact: list[tuple[sqlite3.Row, str]] = []
            for candidate in by_size.get(history["expected_source_bytes"], []):
                digest = local_candidate_hash(connection, candidate)
                if digest == history["expected_source_sha256"]:
                    exact.append((candidate, digest))
            if exact:
                chosen, chosen_hash = min(
                    exact,
                    key=lambda item: (len(Path(item[0]["source_path"]).parts), item[0]["source_path"]),
                )
                status = "recovered_exact_ocr_hash"
                method = "exact_size_and_sha256"
            else:
                set_history_status(
                    connection,
                    db_id,
                    "unresolved_no_exact_hash",
                    candidate_count=len(name_candidates),
                    error="no local PDF matched the OCR source size and SHA-256",
                )
        else:
            scored = [
                (
                    matching_tail_components(Path(candidate["source_path"]), logical),
                    candidate,
                )
                for candidate in name_candidates
            ]
            best_score = max((score for score, _ in scored), default=0)
            eligible = [
                candidate for score, candidate in scored if score == best_score and score >= 2
            ]
            if eligible:
                digests = {
                    local_candidate_hash(connection, candidate) for candidate in eligible
                }
                if len(digests) == 1:
                    chosen = min(
                        eligible,
                        key=lambda candidate: (
                            len(Path(candidate["source_path"]).parts),
                            candidate["source_path"],
                        ),
                    )
                    chosen_hash = next(iter(digests))
                    status = "recovered_historical_path"
                    method = f"matching_path_tail_{best_score}_components"
            elif name_candidates:
                digests = {
                    local_candidate_hash(connection, candidate)
                    for candidate in name_candidates
                }
                if len(digests) == 1:
                    chosen = min(
                        name_candidates,
                        key=lambda candidate: (
                            len(Path(candidate["source_path"]).parts),
                            candidate["source_path"],
                        ),
                    )
                    chosen_hash = next(iter(digests))
                    status = "recovered_historical_basename"
                    method = "normalized_basename_single_unique_content"
            if chosen is None:
                set_history_status(
                    connection,
                    db_id,
                    "unresolved_ambiguous_or_missing_local_candidate",
                    candidate_count=len(name_candidates),
                    error="no unambiguous historical PDF path/content match",
                )

        if chosen is not None and chosen_hash and status and method:
            archive_history_source(
                archive,
                connection,
                history,
                Path(chosen["source_path"]),
                chosen_hash,
                status,
                method,
                len(name_candidates),
            )
        if index % 25 == 0:
            connection.commit()
            print(json.dumps({"phase": "recover_local", "progress": f"{index}/{len(history_rows)}"}), flush=True)
    connection.commit()

    r2_rows = connection.execute(
        """
        SELECT * FROM historical_archive
        WHERE provenance_group = 'ocr_without_purge_log'
          AND migration_status NOT IN (
            'recovered_exact_ocr_hash', 'recovered_historical_path',
            'recovered_historical_basename', 'recovered_from_orphan_r2'
          )
        ORDER BY db_id
        """
    ).fetchall()
    print(json.dumps({"phase": "probe_orphan_r2", "records": len(r2_rows)}), flush=True)
    for history in r2_rows:
        try:
            downloaded = fetch_to_temp(
                history["original_r2_url"], archive / ".tmp", args.timeout, args.retries
            )
            if (
                downloaded.kind != "pdf"
                or downloaded.bytes != history["expected_source_bytes"]
                or downloaded.sha256 != history["expected_source_sha256"]
            ):
                downloaded.path.unlink(missing_ok=True)
                raise RuntimeError(
                    f"R2 payload did not match OCR source: kind={downloaded.kind}, bytes={downloaded.bytes}, sha256={downloaded.sha256}"
                )
            archive_history_source(
                archive,
                connection,
                history,
                downloaded.path,
                downloaded.sha256,
                "recovered_from_orphan_r2",
                "exact_ocr_hash_from_unlogged_r2_url",
                history["candidate_count"],
            )
            downloaded.path.unlink(missing_ok=True)
        except Exception as error:
            set_history_status(
                connection,
                history["db_id"],
                "unresolved_r2_missing_and_no_local_hash_match",
                candidate_count=history["candidate_count"],
                error=clean_error(error),
            )
        connection.commit()

    connection.execute(
        "INSERT OR REPLACE INTO archive_meta(key, value) VALUES('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    connection.commit()
    summary = write_history_manifests(archive, connection)
    connection.close()
    print(json.dumps(summary, indent=2))
    return 0


def pdfinfo_page_count(pdfinfo: str, path: Path) -> int:
    result = subprocess.run(
        [pdfinfo, str(path)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    match = re.search(r"^Pages:\s+(\d+)\s*$", result.stdout, re.MULTILINE)
    if not match:
        raise RuntimeError(f"could not read PDF page count: {path}")
    return int(match.group(1))


def build_facsimile(
    magick: str,
    pdfinfo: str,
    images: list[Path],
    destination: Path,
) -> tuple[int, str]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".pdf", dir=destination.parent
    )
    os.close(fd)
    tmp_path = Path(tmp_name)
    tmp_path.unlink()
    try:
        subprocess.run(
            [
                magick,
                "-density",
                "200",
                *(str(image) for image in images),
                "-units",
                "PixelsPerInch",
                str(tmp_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if not is_pdf(tmp_path):
            raise RuntimeError(f"facsimile output is not a PDF: {tmp_path}")
        page_count = pdfinfo_page_count(pdfinfo, tmp_path)
        if page_count != len(images):
            raise RuntimeError(
                f"facsimile page mismatch: expected {len(images)}, found {page_count}"
            )
        digest = sha256_file(tmp_path)
        os.replace(tmp_path, destination)
        return page_count, digest
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def command_reconstruct_facsimiles(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    database = archive / "catalog/papers.sqlite"
    magick = shutil.which("magick")
    pdfinfo = shutil.which("pdfinfo")
    if not magick or not pdfinfo:
        raise SystemExit("reconstruct-facsimiles requires magick and pdfinfo")
    ensure_archive_layout(archive)
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    rows = connection.execute(
        """
        SELECT h.*, o.page_count, o.canonical_markdown_path
        FROM historical_archive h
        JOIN ocr_derivatives o ON o.db_id = h.db_id
        WHERE h.migration_status IN (
          'unresolved_no_exact_hash',
          'unresolved_r2_missing_and_no_local_hash_match',
          'reconstructed_from_ocr_renders'
        )
        ORDER BY h.db_id
        """
    ).fetchall()
    counts: dict[str, int] = {}
    for index, history in enumerate(rows, 1):
        render_dir = args.ocr_root.resolve() / history["db_id"] / "renders"
        images = sorted(render_dir.glob("*.png")) if render_dir.is_dir() else []
        stems = [image.stem for image in images]
        expected_stems = [f"{page:03d}" for page in range(1, history["page_count"] + 1)]
        if len(images) != history["page_count"] or stems != expected_stems:
            status = "content_preserved_as_ocr_no_complete_renders"
            set_history_status(
                connection,
                history["db_id"],
                status,
                candidate_count=history["candidate_count"],
                error=(
                    f"canonical OCR exists at {history['canonical_markdown_path']}; "
                    f"expected {history['page_count']} renders, found {len(images)}"
                ),
            )
            counts[status] = counts.get(status, 0) + 1
            continue

        destination = (
            archive
            / "historical-facsimiles/by-db-id"
            / history["db_id"]
            / history["desired_filename"]
        )
        try:
            if (
                history["migration_status"] == "reconstructed_from_ocr_renders"
                and destination.is_file()
                and is_pdf(destination)
                and pdfinfo_page_count(pdfinfo, destination) == len(images)
            ):
                page_count = len(images)
                digest = sha256_file(destination)
            else:
                page_count, digest = build_facsimile(
                    magick, pdfinfo, images, destination
                )
            size = destination.stat().st_size
            status = "reconstructed_from_ocr_renders"
            connection.execute(
                """
                UPDATE historical_archive SET
                  migration_status = ?, recovery_method = ?, source_path = ?,
                  local_pdf_path = ?, local_pdf_bytes = ?, local_pdf_sha256 = ?,
                  exact_source_hash_match = 0, error = NULL, updated_at = ?
                WHERE db_id = ?
                """,
                (
                    status,
                    "full_page_png_renders_to_image_pdf_200dpi",
                    str(render_dir),
                    str(destination.relative_to(archive)),
                    size,
                    digest,
                    now_iso(),
                    history["db_id"],
                ),
            )
            receipt = {
                "schema_version": SCHEMA_VERSION,
                "db_id": history["db_id"],
                "provenance_group": history["provenance_group"],
                "original_sidecar_path": history["original_sidecar_path"],
                "original_r2_url": history["original_r2_url"],
                "migration_status": status,
                "recovery_method": "full_page_png_renders_to_image_pdf_200dpi",
                "source_path": str(render_dir),
                "canonical_markdown_path": history["canonical_markdown_path"],
                "local_pdf_path": str(destination.relative_to(archive)),
                "local_pdf_bytes": size,
                "local_pdf_sha256": digest,
                "page_count": page_count,
                "is_original_pdf": False,
                "facsimile": True,
                "updated_at": now_iso(),
            }
            atomic_json(
                archive / "receipts/historical" / f"{history['db_id']}.json",
                receipt,
            )
            counts[status] = counts.get(status, 0) + 1
        except Exception as error:
            status = "facsimile_reconstruction_error"
            set_history_status(
                connection,
                history["db_id"],
                status,
                candidate_count=history["candidate_count"],
                error=clean_error(error),
            )
            counts[status] = counts.get(status, 0) + 1
        connection.commit()
        print(
            json.dumps(
                {
                    "progress": f"{index}/{len(rows)}",
                    "db_id": history["db_id"],
                    "status": status,
                    "counts": counts,
                }
            ),
            flush=True,
        )
    connection.commit()
    summary = write_history_manifests(archive, connection)
    connection.close()
    print(json.dumps(summary, indent=2))
    return 0


DOI_PATTERN = re.compile(r"10\.\d{4,9}/[^\s\"'<>?#&]+", re.IGNORECASE)


def plain_html(fragment: str) -> str:
    return " ".join(
        html.unescape(re.sub(r"<[^>]+>", " ", fragment)).split()
    )


def publication_page_metadata(
    path: Path, expected_filename: str | None = None
) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8", errors="replace").replace("\\/", "/")
    title_matches = [
        *re.finditer(
            r"<title[^>]*>(.*?)</title>", source, re.IGNORECASE | re.DOTALL
        ),
        *re.finditer(r"<h1[^>]*>(.*?)</h1>", source, re.IGNORECASE | re.DOTALL),
    ]
    expected_title = None
    if expected_filename:
        expected_title = title_from_filename(expected_filename)
    if title_matches and expected_title:
        title_match = max(
            title_matches,
            key=lambda match: difflib.SequenceMatcher(
                None,
                normalized_title(expected_title),
                normalized_title(plain_html(match.group(1))),
            ).ratio(),
        )
    else:
        title_match = title_matches[0] if title_matches else None
    title = (
        plain_html(title_match.group(1))
        if title_match
        else expected_title or path.stem
    )
    if expected_title:
        title_score = difflib.SequenceMatcher(
            None, normalized_title(expected_title), normalized_title(title)
        ).ratio()
        if title_score < 0.90:
            title = expected_title
    body_after_title = source[title_match.end() :] if title_match else source
    year_match = re.search(r"<p[^>]*>\s*((?:19|20)\d{2})\s*</p>", body_after_title, re.IGNORECASE)
    author_match = re.search(r"<h3[^>]*>(.*?)</h3>", body_after_title, re.IGNORECASE | re.DOTALL)
    authors = plain_html(author_match.group(1)) if author_match else None
    dois: list[str] = []
    for raw_doi in DOI_PATTERN.findall(source):
        doi = urllib.parse.unquote(raw_doi).rstrip(".,;:)\\]")
        if doi.casefold() not in {existing.casefold() for existing in dois}:
            dois.append(doi)
    return {
        "title": title,
        "year": int(year_match.group(1)) if year_match else None,
        "authors": authors,
        "dois": dois,
    }


def api_json(url: str, timeout: int, retries: int) -> Any:
    last_error: BaseException | None = None
    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.load(response)
        except Exception as error:
            last_error = error
            if attempt < retries:
                retry_after = 0.0
                if isinstance(error, urllib.error.HTTPError):
                    try:
                        retry_after = float(error.headers.get("Retry-After", "0"))
                    except (TypeError, ValueError):
                        retry_after = 0.0
                time.sleep(min(10.0, max(retry_after, 1.5 * attempt)))
    assert last_error is not None
    raise last_error


def crossref_years(item: dict[str, Any]) -> list[int]:
    years: list[int] = []
    for key in ("published", "published-print", "published-online", "issued", "created"):
        value = item.get(key) or {}
        for parts in value.get("date-parts", []):
            if parts and isinstance(parts[0], int) and parts[0] not in years:
                years.append(parts[0])
    return years


def crossref_lookup(
    title: str,
    page_year: int | None,
    page_authors: str | None,
    email: str,
    timeout: int,
    retries: int,
) -> dict[str, Any] | None:
    url = "https://api.crossref.org/works?" + urllib.parse.urlencode(
        {
            "query.bibliographic": title,
            "rows": 5,
            "mailto": email,
        }
    )
    items = api_json(url, timeout, retries)["message"]["items"]
    page_author_tokens = {
        normalized_component(token)
        for token in re.split(r"[;,]", page_authors or "")
        if normalized_component(token)
    }
    ranked: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    for item in items:
        candidate_title = (item.get("title") or [""])[0]
        score = difflib.SequenceMatcher(
            None, normalized_title(title), normalized_title(candidate_title)
        ).ratio()
        if score < 0.92 or not item.get("DOI"):
            continue
        years = crossref_years(item)
        year_distance = (
            min(abs(page_year - year) for year in years)
            if page_year is not None and years
            else 999
        )
        candidate_author_tokens = {
            normalized_component(author.get("family", ""))
            for author in item.get("author", [])
            if normalized_component(author.get("family", ""))
        }
        author_overlap = sum(
            1
            for page_token in page_author_tokens
            if any(
                candidate_token and candidate_token in page_token
                for candidate_token in candidate_author_tokens
            )
        )
        exact = normalized_title(title) == normalized_title(candidate_title)
        rank = (
            1 if exact else 0,
            round(score, 6),
            -year_distance,
            author_overlap,
            float(item.get("score") or 0),
        )
        ranked.append((rank, item))
    if not ranked:
        return None
    _, best = max(ranked, key=lambda pair: pair[0])
    candidate_title = (best.get("title") or [""])[0]
    return {
        "doi": best["DOI"],
        "title": candidate_title,
        "title_score": difflib.SequenceMatcher(
            None, normalized_title(title), normalized_title(candidate_title)
        ).ratio(),
        "links": [
            link["URL"]
            for link in best.get("link", [])
            if link.get("URL")
            and (
                link.get("content-type") == "application/pdf"
                or ".pdf" in urllib.parse.urlsplit(link["URL"]).path.lower()
            )
        ],
    }


def unpaywall_lookup(
    doi: str,
    email: str,
    timeout: int,
    retries: int,
) -> dict[str, Any]:
    url = (
        "https://api.unpaywall.org/v2/"
        + urllib.parse.quote(doi, safe="")
        + "?"
        + urllib.parse.urlencode({"email": email})
    )
    response = api_json(url, timeout, retries)
    pdf_urls: list[str] = []
    landing_urls: list[str] = []
    for location in [
        response.get("best_oa_location"),
        *(response.get("oa_locations") or []),
    ]:
        if not location:
            continue
        pdf_url = location.get("url_for_pdf")
        landing_url = location.get("url_for_landing_page") or location.get("url")
        if pdf_url and pdf_url not in pdf_urls:
            pdf_urls.append(pdf_url)
        if landing_url and landing_url not in landing_urls and landing_url not in pdf_urls:
            landing_urls.append(landing_url)
    return {
        "title": response.get("title"),
        "is_oa": bool(response.get("is_oa")),
        "pdf_urls": pdf_urls,
        "landing_urls": landing_urls,
    }


def download_web_pdf(
    candidates: list[str],
    archive: Path,
    timeout: int,
    retries: int,
) -> tuple[FetchResult | None, str | None, list[dict[str, str]]]:
    failures: list[dict[str, str]] = []
    attempted: set[str] = set()
    queue = list(candidates)
    while queue:
        candidate = queue.pop(0)
        if candidate in attempted:
            continue
        attempted.add(candidate)
        parsed_candidate = urllib.parse.urlsplit(candidate)
        figshare_match = re.search(
            r"/(?:articles/[^/]+/)?(\d+)(?:/versions/\d+)?/?$",
            parsed_candidate.path,
        )
        if parsed_candidate.hostname == "figshare.com" and figshare_match:
            try:
                article = api_json(
                    "https://api.figshare.com/v2/articles/"
                    + figshare_match.group(1),
                    timeout,
                    retries,
                )
                figshare_downloads = [
                    item["download_url"]
                    for item in article.get("files", [])
                    if item.get("download_url")
                    and (
                        item.get("mimetype") == "application/pdf"
                        or str(item.get("name", "")).lower().endswith(".pdf")
                    )
                ]
                if figshare_downloads:
                    queue[0:0] = figshare_downloads
                    continue
            except Exception as error:
                failures.append(
                    {"url": candidate, "error": "Figshare API: " + clean_error(error)}
                )
        try:
            downloaded = fetch_to_temp(candidate, archive / ".tmp", timeout, retries)
            if downloaded.kind == "pdf":
                return downloaded, candidate, failures
            if downloaded.kind == "html":
                nested = pdf_links_from_html(downloaded.path, downloaded.final_url)
                queue.extend(url for url in nested if url not in attempted)
            failures.append({"url": candidate, "error": f"payload kind {downloaded.kind}"})
            downloaded.path.unlink(missing_ok=True)
        except Exception as error:
            failures.append({"url": candidate, "error": clean_error(error)})
    return None, None, failures


def upsert_web_recovery(
    connection: sqlite3.Connection,
    values: dict[str, Any],
) -> None:
    connection.execute(
        """
        INSERT INTO web_recovery(
          db_id, page_title, page_year, page_authors, doi, matched_title,
          title_score, discovery_source, open_access, candidate_urls_json,
          selected_url, recovery_status, error, updated_at
        ) VALUES (
          :db_id, :page_title, :page_year, :page_authors, :doi, :matched_title,
          :title_score, :discovery_source, :open_access, :candidate_urls_json,
          :selected_url, :recovery_status, :error, :updated_at
        )
        ON CONFLICT(db_id) DO UPDATE SET
          page_title = excluded.page_title,
          page_year = excluded.page_year,
          page_authors = excluded.page_authors,
          doi = excluded.doi,
          matched_title = excluded.matched_title,
          title_score = excluded.title_score,
          discovery_source = excluded.discovery_source,
          open_access = excluded.open_access,
          candidate_urls_json = excluded.candidate_urls_json,
          selected_url = excluded.selected_url,
          recovery_status = excluded.recovery_status,
          error = excluded.error,
          updated_at = excluded.updated_at
        """,
        values,
    )


def write_web_recovery_manifest(
    archive: Path, connection: sqlite3.Connection
) -> dict[str, int]:
    rows = connection.execute(
        "SELECT * FROM web_recovery ORDER BY page_title, db_id"
    ).fetchall()
    atomic_text(
        archive / "manifests/web-recovery.jsonl",
        "".join(
            json.dumps(dict(row), ensure_ascii=False, sort_keys=True) + "\n"
            for row in rows
        ),
    )
    return {
        row[0]: row[1]
        for row in connection.execute(
            "SELECT recovery_status, COUNT(*) FROM web_recovery GROUP BY recovery_status"
        )
    }


def command_recover_web(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    database = archive / "catalog/papers.sqlite"
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    connection.executescript(RECOVERY_SCHEMA)
    rows = connection.execute(
        """
        SELECT f.id AS db_id, f.filename, f.original_path, f.r2_path,
               f.size_bytes AS d1_size_bytes, p.*
        FROM files f JOIN paper_archive p ON p.db_id = f.id
        WHERE p.migration_status LIKE 'unresolved_landing_%'
        ORDER BY f.original_path, f.id
        """
    ).fetchall()
    if args.match:
        pattern = re.compile(args.match, re.IGNORECASE)
        rows = [
            row
            for row in rows
            if pattern.search(row["db_id"])
            or pattern.search(row["filename"] or "")
            or pattern.search(row["original_path"] or "")
        ]
    if args.limit:
        rows = rows[: args.limit]
    counts: dict[str, int] = {}
    for index, row in enumerate(rows, 1):
        landing_path = archive / row["landing_page_path"]
        metadata = publication_page_metadata(landing_path, row["filename"])
        doi: str | None = metadata["dois"][0] if len(metadata["dois"]) == 1 else None
        discovery_source = "landing_page_doi" if doi else "crossref_title"
        matched_title: str | None = None
        title_score: float | None = None
        crossref_links: list[str] = []
        error: str | None = None
        open_access: bool | None = None
        candidate_urls: list[str] = []
        selected_url: str | None = None
        status = "web_discovery_pending"
        try:
            if doi is None:
                crossref = crossref_lookup(
                    metadata["title"],
                    metadata["year"],
                    metadata["authors"],
                    args.email,
                    args.timeout,
                    args.retries,
                )
                if crossref is None:
                    raise RuntimeError("no Crossref title match above threshold")
                doi = crossref["doi"]
                matched_title = crossref["title"]
                title_score = crossref["title_score"]
                crossref_links = crossref["links"]

            unpaywall = unpaywall_lookup(
                doi, args.email, args.timeout, args.retries
            )
            matched_title = matched_title or unpaywall["title"]
            title_score = title_score or difflib.SequenceMatcher(
                None,
                normalized_title(metadata["title"]),
                normalized_title(matched_title or ""),
            ).ratio()
            if title_score < 0.90:
                raise RuntimeError(
                    f"DOI title mismatch: score={title_score:.3f}, title={matched_title}"
                )
            open_access = unpaywall["is_oa"]
            for url in (
                unpaywall["pdf_urls"]
                + unpaywall["landing_urls"]
                + crossref_links
            ):
                if url not in candidate_urls:
                    candidate_urls.append(url)
            if not candidate_urls:
                status = "web_no_open_pdf_candidate"
            else:
                downloaded, selected_url, failures = download_web_pdf(
                    candidate_urls, archive, args.timeout, args.retries
                )
                if downloaded is None:
                    status = "web_pdf_candidates_failed"
                    error = json.dumps(failures, ensure_ascii=False)
                else:
                    target = archive / row["local_pdf_path"]
                    place_download(downloaded, target)
                    status = "recovered_open_access_web"
                    receipt_path = archive / "receipts" / f"{row['db_id']}.json"
                    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                    receipt.update(
                        schema_version=SCHEMA_VERSION,
                        migration_status=status,
                        recovery_url=selected_url,
                        local_pdf_bytes=downloaded.bytes,
                        local_pdf_sha256=downloaded.sha256,
                        pdf_has_eof=downloaded.pdf_has_eof,
                        web_discovery_source=discovery_source,
                        web_doi=doi,
                        web_matched_title=matched_title,
                        web_title_score=title_score,
                        web_candidate_urls=candidate_urls,
                        web_open_access=open_access,
                        updated_at=now_iso(),
                    )
                    atomic_json(receipt_path, receipt)
                    update_catalog(connection, receipt)
        except Exception as exception:
            status = "web_discovery_error"
            error = clean_error(exception)

        upsert_web_recovery(
            connection,
            {
                "db_id": row["db_id"],
                "page_title": metadata["title"],
                "page_year": metadata["year"],
                "page_authors": metadata["authors"],
                "doi": doi,
                "matched_title": matched_title,
                "title_score": title_score,
                "discovery_source": discovery_source,
                "open_access": None if open_access is None else int(open_access),
                "candidate_urls_json": json.dumps(candidate_urls, ensure_ascii=False),
                "selected_url": selected_url,
                "recovery_status": status,
                "error": error,
                "updated_at": now_iso(),
            },
        )
        connection.commit()
        counts[status] = counts.get(status, 0) + 1
        print(
            json.dumps(
                {
                    "progress": f"{index}/{len(rows)}",
                    "db_id": row["db_id"],
                    "status": status,
                    "doi": doi,
                    "counts": counts,
                },
                ensure_ascii=False,
            ),
            flush=True,
        )

    web_status = write_web_recovery_manifest(archive, connection)
    summary = write_manifests(archive, connection)
    summary["web_recovery"] = web_status
    atomic_json(archive / "manifests/summary.json", summary)
    connection.close()
    print(json.dumps(summary, indent=2))
    return 0


def title_evidence_from_text(
    extracted: str, expected_title: str, method: str
) -> dict[str, Any]:
    expected_tokens = {
        token
        for token in re.findall(
            r"[a-z0-9]+", unicodedata.normalize("NFKD", expected_title).casefold()
        )
        if len(token) >= 4
    }
    extracted_tokens = set(
        re.findall(
            r"[a-z0-9]+", unicodedata.normalize("NFKD", extracted).casefold()
        )
    )
    coverage = (
        len(expected_tokens & extracted_tokens) / len(expected_tokens)
        if expected_tokens
        else 0.0
    )
    exact = normalized_title(expected_title) in normalized_title(extracted)
    return {
        "expected_title": expected_title,
        "first_three_pages_exact_title": exact,
        "first_three_pages_title_token_coverage": round(coverage, 6),
        "first_three_pages_text_chars": len(extracted),
        "validation_method": method,
        "verified": exact or coverage >= 0.95,
    }


def pdf_title_evidence(path: Path, expected_title: str) -> dict[str, Any]:
    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        raise RuntimeError("pdftotext is required to validate a discovered PDF")
    result = subprocess.run(
        [pdftotext, "-f", "1", "-l", "3", str(path), "-"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    embedded_text = result.stdout[:100_000]
    evidence = title_evidence_from_text(
        embedded_text, expected_title, "embedded_pdf_text"
    )
    if evidence["verified"]:
        return evidence

    pdftoppm = shutil.which("pdftoppm")
    tesseract = shutil.which("tesseract")
    if not pdftoppm or not tesseract:
        evidence["ocr_fallback"] = "unavailable"
        return evidence

    with tempfile.TemporaryDirectory(prefix="paper-title-ocr-") as directory:
        prefix = Path(directory) / "page"
        subprocess.run(
            [
                pdftoppm,
                "-f",
                "1",
                "-l",
                "3",
                "-r",
                "180",
                "-png",
                str(path),
                str(prefix),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        ocr_parts: list[str] = []
        for image in sorted(Path(directory).glob("page-*.png")):
            ocr = subprocess.run(
                [tesseract, str(image), "stdout", "-l", "eng"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
            ocr_parts.append(ocr.stdout)
    ocr_evidence = title_evidence_from_text(
        "\n".join(ocr_parts)[:100_000], expected_title, "first_three_pages_ocr"
    )
    ocr_evidence["embedded_text_title_token_coverage"] = evidence[
        "first_three_pages_title_token_coverage"
    ]
    ocr_evidence["embedded_text_chars"] = evidence["first_three_pages_text_chars"]
    return ocr_evidence


def command_recover_url(args: argparse.Namespace) -> int:
    """Attach a manually discovered public-repository PDF with content validation."""
    archive = args.archive.resolve()
    connection = sqlite3.connect(archive / "catalog/papers.sqlite")
    connection.row_factory = sqlite3.Row
    row = connection.execute(
        """
        SELECT f.id AS db_id, f.filename, p.*
        FROM files f JOIN paper_archive p ON p.db_id = f.id
        WHERE f.id = ?
        """,
        (args.db_id,),
    ).fetchone()
    if row is None:
        raise SystemExit(f"unknown D1 paper ID: {args.db_id}")
    if row["migration_status"] in SUCCESS_STATUSES:
        raise SystemExit(
            f"paper is already recovered: {args.db_id} ({row['migration_status']})"
        )
    downloaded, selected_url, failures = download_web_pdf(
        [args.url], archive, args.timeout, args.retries
    )
    if downloaded is None:
        raise SystemExit(
            "public-repository candidate did not yield a PDF: "
            + json.dumps(failures, ensure_ascii=False)
        )
    evidence = pdf_title_evidence(
        downloaded.path, title_from_filename(row["filename"])
    )
    if not evidence["verified"]:
        downloaded.path.unlink(missing_ok=True)
        raise SystemExit(
            "downloaded PDF failed title validation: "
            + json.dumps(evidence, ensure_ascii=False)
        )

    target = archive / row["local_pdf_path"]
    place_download(downloaded, target)
    receipt_path = archive / "receipts" / f"{args.db_id}.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    web_row = connection.execute(
        "SELECT * FROM web_recovery WHERE db_id = ?", (args.db_id,)
    ).fetchone()
    receipt.update(
        schema_version=SCHEMA_VERSION,
        migration_status="recovered_open_access_web",
        recovery_url=selected_url,
        local_pdf_bytes=downloaded.bytes,
        local_pdf_sha256=downloaded.sha256,
        pdf_has_eof=downloaded.pdf_has_eof,
        web_discovery_source="manual_public_repository_search",
        web_doi=(web_row["doi"] if web_row else None),
        web_candidate_urls=[args.url],
        web_content_validation=evidence,
        error=None,
        updated_at=now_iso(),
    )
    atomic_json(receipt_path, receipt)
    update_catalog(connection, receipt)
    if web_row:
        connection.execute(
            """
            UPDATE web_recovery SET
              discovery_source = ?, selected_url = ?, recovery_status = ?,
              error = NULL, updated_at = ?
            WHERE db_id = ?
            """,
            (
                "manual_public_repository_search",
                selected_url,
                "recovered_open_access_web",
                now_iso(),
                args.db_id,
            ),
        )
    connection.commit()
    web_status = write_web_recovery_manifest(archive, connection)
    summary = write_manifests(archive, connection)
    summary["web_recovery"] = web_status
    atomic_json(archive / "manifests/summary.json", summary)
    connection.close()
    print(
        json.dumps(
            {
                "db_id": args.db_id,
                "status": "recovered_open_access_web",
                "selected_url": selected_url,
                "bytes": downloaded.bytes,
                "sha256": downloaded.sha256,
                "content_validation": evidence,
                "archive_summary": summary,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def effectuation_library_rows(
    archive: Path, timeout: int, retries: int
) -> dict[str, list[dict[str, str | None]]]:
    url = "https://effectuation.org/publications-library"
    fetched = fetch_to_temp(url, archive / ".tmp", timeout, retries)
    try:
        if fetched.kind != "html":
            raise RuntimeError(
                f"Effectuation library returned {fetched.kind}, expected HTML"
            )
        source = fetched.path.read_text(encoding="utf-8", errors="replace")
    finally:
        fetched.path.unlink(missing_ok=True)
    catalog: dict[str, list[dict[str, str | None]]] = {}
    for table_row in re.findall(
        r"<tr\b[^>]*>(.*?)</tr>", source, re.IGNORECASE | re.DOTALL
    ):
        cells = re.findall(
            r"<td\b[^>]*>(.*?)</td>", table_row, re.IGNORECASE | re.DOTALL
        )
        if len(cells) < 6:
            continue
        title = plain_html(cells[0])
        href_match = re.search(
            r'href=["\']([^"\']+)["\']', cells[5], re.IGNORECASE
        )
        catalog.setdefault(normalized_title(title), []).append(
            {
                "title": title,
                "url": html.unescape(href_match.group(1)) if href_match else None,
                "link_text": plain_html(cells[5]),
            }
        )
    return catalog


def is_direct_paper_link(entry: dict[str, str | None]) -> bool:
    url = entry.get("url") or ""
    path = urllib.parse.urlsplit(url).path.lower()
    return (
        "pdf" in (entry.get("link_text") or "").casefold()
        or ".pdf" in path
        or "/epdf/" in path
    )


def command_recover_live_library(args: argparse.Namespace) -> int:
    """Recover exact-title PDFs exposed by the live Effectuation catalog."""
    archive = args.archive.resolve()
    connection = sqlite3.connect(archive / "catalog/papers.sqlite")
    connection.row_factory = sqlite3.Row
    catalog = effectuation_library_rows(archive, args.timeout, args.retries)
    rows = connection.execute(
        """
        SELECT f.id AS db_id, f.filename, p.*, w.page_title, w.doi,
               w.candidate_urls_json
        FROM files f
        JOIN paper_archive p ON p.db_id = f.id
        LEFT JOIN web_recovery w ON w.db_id = f.id
        WHERE p.migration_status LIKE 'unresolved_landing_%'
        ORDER BY f.original_path, f.id
        """
    ).fetchall()
    results: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    for index, row in enumerate(rows, 1):
        expected_title = title_from_filename(row["filename"])
        entries = catalog.get(normalized_title(row["page_title"] or expected_title), [])
        candidates = [
            entry["url"]
            for entry in entries
            if entry.get("url") and is_direct_paper_link(entry)
        ]
        status = "live_library_no_direct_pdf"
        selected_url: str | None = None
        error: str | None = None
        evidence: dict[str, Any] | None = None
        if candidates:
            downloaded, selected_url, failures = download_web_pdf(
                candidates, archive, args.timeout, args.retries
            )
            if downloaded is None:
                status = "live_library_pdf_failed"
                error = json.dumps(failures, ensure_ascii=False)
            else:
                try:
                    evidence = pdf_title_evidence(downloaded.path, expected_title)
                    if not evidence["verified"]:
                        status = "live_library_title_mismatch"
                        error = json.dumps(evidence, ensure_ascii=False)
                        downloaded.path.unlink(missing_ok=True)
                    else:
                        target = archive / row["local_pdf_path"]
                        place_download(downloaded, target)
                        status = "recovered_open_access_web"
                        receipt_path = archive / "receipts" / f"{row['db_id']}.json"
                        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                        receipt.update(
                            schema_version=SCHEMA_VERSION,
                            migration_status=status,
                            recovery_url=selected_url,
                            local_pdf_bytes=downloaded.bytes,
                            local_pdf_sha256=downloaded.sha256,
                            pdf_has_eof=downloaded.pdf_has_eof,
                            web_discovery_source="live_effectuation_library",
                            web_doi=row["doi"],
                            web_candidate_urls=candidates,
                            web_content_validation=evidence,
                            error=None,
                            updated_at=now_iso(),
                        )
                        atomic_json(receipt_path, receipt)
                        update_catalog(connection, receipt)
                        prior_candidates = json.loads(
                            row["candidate_urls_json"] or "[]"
                        )
                        merged_candidates = list(prior_candidates)
                        for candidate in candidates:
                            if candidate not in merged_candidates:
                                merged_candidates.append(candidate)
                        connection.execute(
                            """
                            UPDATE web_recovery SET
                              discovery_source = ?, open_access = 1,
                              candidate_urls_json = ?, selected_url = ?,
                              recovery_status = ?, error = NULL, updated_at = ?
                            WHERE db_id = ?
                            """,
                            (
                                "live_effectuation_library",
                                json.dumps(merged_candidates, ensure_ascii=False),
                                selected_url,
                                status,
                                now_iso(),
                                row["db_id"],
                            ),
                        )
                except Exception as exception:
                    downloaded.path.unlink(missing_ok=True)
                    status = "live_library_validation_error"
                    error = clean_error(exception)
        result = {
            "db_id": row["db_id"],
            "expected_title": expected_title,
            "catalog_entries": entries,
            "candidate_urls": candidates,
            "selected_url": selected_url,
            "status": status,
            "content_validation": evidence,
            "error": error,
            "updated_at": now_iso(),
        }
        results.append(result)
        counts[status] = counts.get(status, 0) + 1
        connection.commit()
        if candidates or index == len(rows):
            print(
                json.dumps(
                    {
                        "progress": f"{index}/{len(rows)}",
                        "db_id": row["db_id"],
                        "status": status,
                        "counts": counts,
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )

    atomic_text(
        archive / "manifests/live-effectuation-library-recovery.jsonl",
        "".join(
            json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n"
            for result in results
        ),
    )
    web_status = write_web_recovery_manifest(archive, connection)
    summary = write_manifests(archive, connection)
    summary["web_recovery"] = web_status
    summary["live_effectuation_library"] = counts
    atomic_json(archive / "manifests/summary.json", summary)
    connection.close()
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def command_verify(args: argparse.Namespace) -> int:
    archive = args.archive.resolve()
    database = archive / "catalog/papers.sqlite"
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    d1_pdf_rows = connection.execute(
        "SELECT COUNT(*) FROM files WHERE lower(filename) LIKE '%.pdf'"
    ).fetchone()[0]
    archive_rows = connection.execute("SELECT COUNT(*) FROM paper_archive").fetchone()[0]
    rows = connection.execute(
        """
        SELECT db_id, sidecar_path, r2_url, local_pdf_path, local_pdf_bytes,
               local_pdf_sha256, migration_status
        FROM paper_archive
        """
    ).fetchall()
    missing_sidecars: list[str] = []
    bad_sidecar_links: list[str] = []
    missing_files: list[str] = []
    bad_files: list[str] = []
    hash_mismatches: list[str] = []
    verified_files = 0
    for row in rows:
        sidecar = archive / row["sidecar_path"]
        if not sidecar.is_file():
            missing_sidecars.append(row["db_id"])
        else:
            try:
                sidecar_data = json.loads(sidecar.read_text(encoding="utf-8"))
                if (
                    (sidecar_data.get("db_id") or sidecar_data.get("id")) != row["db_id"]
                    or sidecar_data.get("r2_url") != row["r2_url"]
                ):
                    bad_sidecar_links.append(row["db_id"])
            except (OSError, json.JSONDecodeError):
                bad_sidecar_links.append(row["db_id"])
        if not row["local_pdf_sha256"]:
            continue
        path = archive / row["local_pdf_path"]
        if not path.is_file():
            missing_files.append(row["db_id"])
            continue
        if not is_pdf(path) or path.stat().st_size != row["local_pdf_bytes"]:
            bad_files.append(row["db_id"])
            continue
        if args.rehash and sha256_file(path) != row["local_pdf_sha256"]:
            hash_mismatches.append(row["db_id"])
            continue
        verified_files += 1
    status_rows = connection.execute(
        "SELECT migration_status, COUNT(*) AS n FROM paper_archive GROUP BY migration_status"
    ).fetchall()
    historical_expected = connection.execute(
        """
        SELECT
          (SELECT COUNT(*) FROM historical_purges)
          + (SELECT COUNT(*) FROM ocr_derivatives WHERE prior_r2_purged = 0)
        """
    ).fetchone()[0]
    has_historical_archive = connection.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'historical_archive'"
    ).fetchone()[0]
    historical_rows: list[sqlite3.Row] = []
    historical_status: dict[str, int] = {}
    missing_historical_files: list[str] = []
    bad_historical_files: list[str] = []
    historical_hash_mismatches: list[str] = []
    missing_historical_receipts: list[str] = []
    verified_historical_files = 0
    if has_historical_archive:
        historical_rows = connection.execute(
            """
            SELECT db_id, migration_status, local_pdf_path, local_pdf_bytes,
                   local_pdf_sha256
            FROM historical_archive
            """
        ).fetchall()
        historical_status = {
            row[0]: row[1]
            for row in connection.execute(
                "SELECT migration_status, COUNT(*) FROM historical_archive GROUP BY migration_status"
            )
        }
        for row in historical_rows:
            if row["migration_status"] not in HISTORY_LOCAL_PDF_STATUSES:
                continue
            path = archive / row["local_pdf_path"]
            receipt = archive / "receipts/historical" / f"{row['db_id']}.json"
            if not receipt.is_file():
                missing_historical_receipts.append(row["db_id"])
            if not path.is_file():
                missing_historical_files.append(row["db_id"])
                continue
            if not is_pdf(path) or path.stat().st_size != row["local_pdf_bytes"]:
                bad_historical_files.append(row["db_id"])
                continue
            if args.rehash and sha256_file(path) != row["local_pdf_sha256"]:
                historical_hash_mismatches.append(row["db_id"])
                continue
            verified_historical_files += 1
    result = {
        "verified_at": now_iso(),
        "sqlite_integrity": integrity,
        "d1_pdf_rows": d1_pdf_rows,
        "archive_rows": archive_rows,
        "row_count_matches": d1_pdf_rows == archive_rows,
        "indexed_sidecars": archive_rows - len(missing_sidecars) - len(bad_sidecar_links),
        "missing_sidecars": missing_sidecars,
        "bad_sidecar_links": bad_sidecar_links,
        "status": {row["migration_status"]: row["n"] for row in status_rows},
        "all_rows_attempted": all(row["migration_status"] != "pending" for row in rows),
        "all_current_pdfs_local": verified_files == archive_rows,
        "verified_local_files": verified_files,
        "missing_local_files": missing_files,
        "bad_local_files": bad_files,
        "hash_mismatches": hash_mismatches,
        "historical_expected_records": historical_expected,
        "historical_archive_rows": len(historical_rows),
        "historical_row_count_matches": len(historical_rows) == historical_expected,
        "historical_status": historical_status,
        "verified_historical_files": verified_historical_files,
        "missing_historical_files": missing_historical_files,
        "bad_historical_files": bad_historical_files,
        "historical_hash_mismatches": historical_hash_mismatches,
        "missing_historical_receipts": missing_historical_receipts,
        "rehash": args.rehash,
    }
    atomic_json(archive / "manifests/verification.json", result)
    print(json.dumps(result, indent=2))
    connection.close()
    failures = (
        missing_sidecars
        or bad_sidecar_links
        or missing_files
        or bad_files
        or hash_mismatches
        or missing_historical_files
        or bad_historical_files
        or historical_hash_mismatches
        or missing_historical_receipts
    )
    counts_match = d1_pdf_rows == archive_rows and (
        not has_historical_archive or len(historical_rows) == historical_expected
    )
    return 0 if integrity == "ok" and counts_match and not failures else 1


def path_argument(value: str) -> Path:
    return Path(value).expanduser()


def candidate_root_argument(value: str) -> tuple[str, Path]:
    label, separator, raw_path = value.partition("=")
    if not separator or not label or not raw_path:
        raise argparse.ArgumentTypeError("expected LABEL=PATH")
    return label, Path(raw_path).expanduser()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    init = subparsers.add_parser("init", help="build the local SQLite catalog")
    init.add_argument("--archive", type=path_argument, required=True)
    init.add_argument("--d1-sql", type=path_argument, required=True)
    init.add_argument("--sidecars", type=path_argument, required=True)
    init.add_argument("--purge-log", type=path_argument, required=True)
    init.add_argument("--post-manifest", type=path_argument, required=True)
    init.add_argument("--ocr-root", type=path_argument, required=True)
    init.add_argument("--refresh", action="store_true")
    init.set_defaults(function=command_init)

    mirror = subparsers.add_parser("mirror", help="mirror and recover current PDFs")
    mirror.add_argument("--archive", type=path_argument, required=True)
    mirror.add_argument("--workers", type=int, default=8)
    mirror.add_argument("--timeout", type=int, default=90)
    mirror.add_argument("--retries", type=int, default=3)
    mirror.add_argument("--match", help="case-insensitive regex over ID/path/name")
    mirror.add_argument("--limit", type=int, default=0)
    mirror.add_argument("--retry-unresolved", action="store_true")
    mirror.set_defaults(function=command_mirror)

    recover_history = subparsers.add_parser(
        "recover-history",
        help="index local candidates and recover previously purged/OCR originals",
    )
    recover_history.add_argument("--archive", type=path_argument, required=True)
    recover_history.add_argument(
        "--candidate-root",
        type=candidate_root_argument,
        action="append",
        required=True,
        metavar="LABEL=PATH",
    )
    recover_history.add_argument("--timeout", type=int, default=30)
    recover_history.add_argument("--retries", type=int, default=1)
    recover_history.set_defaults(function=command_recover_history)

    facsimiles = subparsers.add_parser(
        "reconstruct-facsimiles",
        help="rebuild explicitly labeled image PDFs from complete OCR page renders",
    )
    facsimiles.add_argument("--archive", type=path_argument, required=True)
    facsimiles.add_argument("--ocr-root", type=path_argument, required=True)
    facsimiles.set_defaults(function=command_reconstruct_facsimiles)

    recover_web = subparsers.add_parser(
        "recover-web",
        help="recover unresolved landing pages through DOI/OA metadata",
    )
    recover_web.add_argument("--archive", type=path_argument, required=True)
    recover_web.add_argument("--email", required=True)
    recover_web.add_argument("--timeout", type=int, default=60)
    recover_web.add_argument("--retries", type=int, default=2)
    recover_web.add_argument("--match", help="case-insensitive regex over ID/path/name")
    recover_web.add_argument("--limit", type=int, default=0)
    recover_web.set_defaults(function=command_recover_web)

    recover_url = subparsers.add_parser(
        "recover-url",
        help="attach and content-validate a PDF found in a public repository",
    )
    recover_url.add_argument("--archive", type=path_argument, required=True)
    recover_url.add_argument("--db-id", required=True)
    recover_url.add_argument("--url", required=True)
    recover_url.add_argument("--timeout", type=int, default=60)
    recover_url.add_argument("--retries", type=int, default=2)
    recover_url.set_defaults(function=command_recover_url)

    recover_live = subparsers.add_parser(
        "recover-live-library",
        help="recover exact-title PDFs from the live Effectuation library",
    )
    recover_live.add_argument("--archive", type=path_argument, required=True)
    recover_live.add_argument("--timeout", type=int, default=60)
    recover_live.add_argument("--retries", type=int, default=2)
    recover_live.set_defaults(function=command_recover_live_library)

    verify = subparsers.add_parser("verify", help="verify catalog and local payloads")
    verify.add_argument("--archive", type=path_argument, required=True)
    verify.add_argument("--rehash", action="store_true")
    verify.set_defaults(function=command_verify)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "workers", 1) < 1:
        parser.error("--workers must be positive")
    return args.function(args)


if __name__ == "__main__":
    raise SystemExit(main())
