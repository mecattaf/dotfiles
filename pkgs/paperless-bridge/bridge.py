#!/usr/bin/env python3
"""paperless-bridge — same-inode projection of canonical NAS PDFs into
Paperless-ngx v3 (dotfiles#136).

The canonical tree under /mnt/nas/documents is the storage authority; a
Paperless "original" is only ever a second directory entry for the same
inode. Stock Paperless copies consumed input into its media tree, so the
bridge stages a temporary hardlink in the consume spool, lets the supported
consumer create the document, verifies checksums, then has a narrow root
helper atomically replace Paperless's copy with a hardlink to the canonical
inode. Never forks Paperless, never touches its database.

Commands (all idempotent; a converged corpus makes every one a no-op):
  scan       inventory canonical PDFs into the ledger
  ingest     stage pending entries through the Paperless consumer
  relink     replace Paperless copies with canonical hardlinks (root helper)
  enrich     project academic-ocr canonical paper.md into Paperless content
  suggest    propose ai-candidate/* tags through the fleet utility model
  sync-tags  ensure the versioned taxonomy exists in Paperless; export accepted tags
  verify     prove the same-inode invariant for every projected entry
  audit      full state report; nonzero exit on any violation
  bulk       guarded, resumable admission loop (scan, then ingest/relink/verify
             rounds) that pauses itself before it can hurt the router box

State: sqlite ledger + append-only receipts.jsonl under the bridge state
dir. Reconciliation keys are source_id + sha256 + paperless document id;
st_dev:st_ino is checked live, never trusted as durable identity.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone

CANONICAL_ROOT = os.environ.get("BRIDGE_CANONICAL_ROOT", "/mnt/nas/documents")
STATE_DIR = os.environ.get("BRIDGE_STATE_DIR", "/mnt/nas/services/paperless/bridge")
SPOOL = os.environ.get("BRIDGE_SPOOL", "/mnt/nas/documents/.paperless-consume")
VIEW_ROOT = os.environ.get("BRIDGE_VIEW_ROOT", "/mnt/nas/documents/.paperless-view")
PAPERLESS_URL = os.environ.get("PAPERLESS_URL", "http://127.0.0.1:28981")
TOKEN_FILE = os.environ.get("PAPERLESS_TOKEN_FILE", "/mnt/nas/services/paperless/bridge/api-token")
RELINK_HELPER = os.environ.get("BRIDGE_RELINK_HELPER", "paperless-relink-helper")
# The academic corpus of record (documents/academic-papers/README.md). The
# 2026-08-04 staging pointed enrichment at academic-papers/canonical/<db_id>/,
# a layout that never existed on the box; the real one, re-probed 2026-09-13:
#   catalog/papers.sqlite       paper_archive + historical_archive map db_id ->
#                               local_pdf_path (relative to this root);
#                               ocr_derivatives maps db_id -> source_sha256 +
#                               canonical_markdown_path (absolute)
#   ocr-june/papers-canonical/<db_id>/canonical/paper.md   (184 papers)
#   receipts/historical/<db_id>.json                        (260 receipts)
ACADEMIC_ROOT = os.environ.get(
    "BRIDGE_ACADEMIC_ROOT", os.path.join(CANONICAL_ROOT, "academic-papers")
)
# Where the catalog's absolute paths were written; rebased onto ACADEMIC_ROOT
# so a fixture tree (or a future re-home) resolves the same rows.
ACADEMIC_RECORDED_ROOT = "/mnt/nas/documents/academic-papers"
# The fleet's utility seam (AGENTS.md): one chat-completions request on stdin,
# one response on stdout. Only the coordinator has `utility-model`, so
# `suggest` runs there against http://paperless.internal.
UTILITY_CMD = os.environ.get("BRIDGE_UTILITY_CMD", "utility-model")
SUGGEST_MODEL = os.environ.get("BRIDGE_SUGGEST_MODEL", "utility")
SUGGEST_NOTE_MARKER = "paperless-bridge suggest"
# Namespaces a model may propose into. status/ and personal/ are human-owned
# and source/ is provenance the bridge knows exactly; none of them are guessed.
SUGGEST_NAMESPACES = ("kind", "topic", "course")
TAXONOMY = os.environ.get("BRIDGE_TAXONOMY", os.path.join(os.path.dirname(__file__), "taxonomy.json"))
# Trees the bridge never inventories: its own machinery plus service state.
EXCLUDE_DIRS = {".paperless-view", ".paperless-consume", ".snapshots"}

MACHINE_TAG_PREFIXES = ("kind/", "topic/", "course/", "status/", "source/", "ai-candidate/")


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg):
    print(f"{now()} {msg}", file=sys.stderr)


def die(msg, code=1):
    log(f"FATAL: {msg}")
    sys.exit(code)


# ---------------------------------------------------------------- ledger

SCHEMA = """
CREATE TABLE IF NOT EXISTS entries (
  source_id TEXT PRIMARY KEY,
  rel_path TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  md5 TEXT NOT NULL,
  size INTEGER NOT NULL,
  academic_db_id TEXT,
  state TEXT NOT NULL DEFAULT 'inventoried',
  paperless_id INTEGER,
  media_path TEXT,
  ocr_state TEXT NOT NULL DEFAULT 'baseline',
  first_seen TEXT NOT NULL,
  updated TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS entries_sha ON entries (sha256);
CREATE UNIQUE INDEX IF NOT EXISTS entries_path ON entries (rel_path);
"""

STATES = ("inventoried", "ingested", "relinked", "canonical-synced")


def ledger():
    os.makedirs(STATE_DIR, exist_ok=True)
    db = sqlite3.connect(os.path.join(STATE_DIR, "ledger.sqlite"))
    db.row_factory = sqlite3.Row
    db.executescript(SCHEMA)
    return db


def receipt(event, **fields):
    rec = {"at": now(), "event": event, **fields}
    # bulk can record a guard pause before anything opened the ledger.
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, "receipts.jsonl"), "a") as f:
        f.write(json.dumps(rec, sort_keys=True) + "\n")
    return rec


# ---------------------------------------------------------------- hashing


def digests(path):
    sha, md5 = hashlib.sha256(), hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            sha.update(chunk)
            md5.update(chunk)
    return sha.hexdigest(), md5.hexdigest()


# ---------------------------------------------------------------- API


def token():
    # PAPERLESS_TOKEN lets the coordinator-side `suggest` carry the token for
    # one invocation without a copy of the NAS token file at rest.
    if os.environ.get("PAPERLESS_TOKEN"):
        return os.environ["PAPERLESS_TOKEN"].strip()
    with open(TOKEN_FILE) as f:
        return f.read().strip()


def api(method, path, body=None, params=None):
    url = PAPERLESS_URL.rstrip("/") + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Token {token()}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else None


def api_all(path, params=None):
    params = dict(params or {})
    params.setdefault("page_size", 250)
    out, page = [], 1
    while True:
        params["page"] = page
        got = api("GET", path, params=params)
        out.extend(got["results"])
        if not got.get("next"):
            return out
        page += 1


# ---------------------------------------------------------------- scan


def catalog_path():
    return os.path.join(ACADEMIC_ROOT, "catalog", "papers.sqlite")


def open_catalog():
    catalog = catalog_path()
    if not os.path.exists(catalog):
        return None
    return sqlite3.connect(f"file:{catalog}?mode=ro", uri=True)


def rebase_academic(path):
    """A catalog path (relative to the academic root, or absolute as recorded
    on the NAS) -> an absolute path under ACADEMIC_ROOT."""
    if not os.path.isabs(path):
        return os.path.join(ACADEMIC_ROOT, path)
    if path == ACADEMIC_RECORDED_ROOT or path.startswith(ACADEMIC_RECORDED_ROOT + "/"):
        return os.path.join(ACADEMIC_ROOT, os.path.relpath(path, ACADEMIC_RECORDED_ROOT))
    return path


def academic_db_ids():
    """rel_path (under the canonical root) -> academic db_id, from the catalog.

    The column is local_pdf_path, in BOTH paper_archive (3417 mirrored R2
    papers) and historical_archive (the 260 recovered historical set, which is
    where all 184 OCR derivatives live). The 2026-08-04 staging read a
    `file_path` column that neither table has, so every scan would have
    silently inventoried the whole corpus without a single db_id."""
    db = open_catalog()
    if db is None:
        return {}
    out = {}
    try:
        for table in ("paper_archive", "historical_archive"):
            try:
                rows = db.execute(
                    f"SELECT db_id, local_pdf_path FROM {table} WHERE local_pdf_path IS NOT NULL"
                ).fetchall()
            except sqlite3.OperationalError as e:
                log(f"academic catalog table {table} unreadable ({e}); skipping it")
                continue
            for db_id, fp in rows:
                rel = os.path.relpath(rebase_academic(fp), CANONICAL_ROOT)
                out.setdefault(rel, db_id)
        return out
    finally:
        db.close()


def cmd_scan(args):
    db = ledger()
    academic = academic_db_ids()
    seen, added, moved = set(), 0, 0
    for dirpath, dirnames, filenames in os.walk(CANONICAL_ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for name in filenames:
            if not name.lower().endswith(".pdf"):
                continue
            abs_path = os.path.join(dirpath, name)
            if os.path.islink(abs_path):
                continue
            rel = os.path.relpath(abs_path, CANONICAL_ROOT)
            seen.add(rel)
            row = db.execute("SELECT * FROM entries WHERE rel_path = ?", (rel,)).fetchone()
            if row:
                continue  # known occurrence; verify owns drift detection
            sha, md5 = digests(abs_path)
            # A known payload whose old path vanished is a move, not a new
            # occurrence; adopt it into the existing identity.
            prior = db.execute(
                "SELECT * FROM entries WHERE sha256 = ?", (sha,)
            ).fetchall()
            adopted = False
            for p in prior:
                if not os.path.exists(os.path.join(CANONICAL_ROOT, p["rel_path"])):
                    db.execute(
                        "UPDATE entries SET rel_path = ?, updated = ? WHERE source_id = ?",
                        (rel, now(), p["source_id"]),
                    )
                    receipt("moved", source_id=p["source_id"], from_path=p["rel_path"], to_path=rel)
                    moved += 1
                    adopted = True
                    break
            if adopted:
                continue
            sid = str(uuid.uuid4())
            db.execute(
                "INSERT INTO entries (source_id, rel_path, sha256, md5, size, academic_db_id,"
                " first_seen, updated) VALUES (?,?,?,?,?,?,?,?)",
                (sid, rel, sha, md5, os.path.getsize(abs_path), academic.get(rel), now(), now()),
            )
            receipt("inventoried", source_id=sid, rel_path=rel, sha256=sha)
            added += 1
    missing = [
        r["rel_path"]
        for r in db.execute("SELECT rel_path FROM entries").fetchall()
        if r["rel_path"] not in seen
    ]
    db.commit()
    print(json.dumps({"added": added, "moved": moved, "missing_canonical": missing}))
    if missing:
        log(f"ALARM: {len(missing)} ledger entries have no canonical file; run verify")
        return 1
    return 0


# ---------------------------------------------------------------- ingest


def wait_for_document(spool_name, timeout_sec):
    deadline = time.time() + timeout_sec
    stem = os.path.splitext(spool_name)[0]
    while time.time() < deadline:
        got = api("GET", "/api/documents/", params={"original_filename__istartswith": stem})
        if got["count"] == 1:
            return got["results"][0]
        if got["count"] > 1:
            die(f"multiple Paperless documents match spool name {spool_name}")
        time.sleep(5)
    return None


def paperless_metadata(doc_id):
    return api("GET", f"/api/documents/{doc_id}/metadata/")


def checksum_matches(stored, sha, md5):
    """Paperless 3.0 stored an MD5 original checksum; 3.1 moved to SHA-256
    (documents/utils.py compute_checksum, max_length 64). Compare against the
    digest of the stored checksum's own length, never a truncation."""
    stored = (stored or "").lower()
    if len(stored) == 64:
        return stored == sha
    if len(stored) == 32:
        return stored == md5
    return False


def cmd_ingest(args):
    db = ledger()
    rows = db.execute(
        "SELECT * FROM entries WHERE state = 'inventoried' ORDER BY rel_path LIMIT ?",
        (args.batch,),
    ).fetchall()
    os.makedirs(SPOOL, exist_ok=True)
    done = 0
    for row in rows:
        src = os.path.join(CANONICAL_ROOT, row["rel_path"])
        if not os.path.exists(src):
            log(f"skip {row['source_id']}: canonical file missing ({row['rel_path']})")
            continue
        sha, md5 = digests(src)
        if sha != row["sha256"]:
            log(f"ALARM: {row['rel_path']} content changed since inventory; refusing to ingest")
            receipt("hash-mismatch", source_id=row["source_id"], expected=row["sha256"], actual=sha)
            continue
        # Duplicate payloads: if another occurrence of this sha is already in
        # Paperless, its consumer would reject the stage as a duplicate.
        # Academic occurrences are deliberately distinct research objects
        # (dotfiles#136), so only they proceed; general duplicates alias.
        twin = db.execute(
            "SELECT * FROM entries WHERE sha256 = ? AND paperless_id IS NOT NULL", (row["sha256"],)
        ).fetchone()
        if twin and not row["academic_db_id"]:
            db.execute(
                "UPDATE entries SET state = 'relinked', paperless_id = ?, media_path = ?,"
                " updated = ? WHERE source_id = ?",
                (twin["paperless_id"], twin["media_path"], now(), row["source_id"]),
            )
            db.commit()
            receipt("aliased", source_id=row["source_id"], alias_of=twin["source_id"],
                    paperless_id=twin["paperless_id"])
            continue
        spool_name = f"{row['source_id']}.pdf"
        spool_path = os.path.join(SPOOL, spool_name)
        if not os.path.exists(spool_path):
            os.link(src, spool_path)  # same-subvolume hardlink, never a copy
        doc = wait_for_document(spool_name, args.timeout)
        if doc is None:
            log(f"timeout waiting for consumer on {spool_name}; will retry next run")
            continue
        meta = paperless_metadata(doc["id"])
        if not checksum_matches(meta["original_checksum"], sha, md5):
            die(
                f"checksum mismatch for {row['rel_path']}: canonical sha256 {sha},"
                f" Paperless stored {meta['original_checksum']}"
            )
        db.execute(
            "UPDATE entries SET state = 'ingested', paperless_id = ?, media_path = ?,"
            " updated = ? WHERE source_id = ?",
            (doc["id"], meta["media_filename"], now(), row["source_id"]),
        )
        db.commit()
        receipt(
            "ingested",
            source_id=row["source_id"],
            rel_path=row["rel_path"],
            sha256=row["sha256"],
            paperless_id=doc["id"],
            media_path=meta["media_filename"],
        )
        done += 1
        if os.path.exists(spool_path):
            os.unlink(spool_path)
    leftovers = os.listdir(SPOOL) if os.path.isdir(SPOOL) else []
    print(json.dumps({"ingested": done, "spool_leftovers": leftovers}))
    return 0


# ---------------------------------------------------------------- relink


def originals_dir():
    # Paperless media originals, bind-mounted from the hidden view subvolume.
    return os.path.join(VIEW_ROOT)


def media_abs(media_path):
    return os.path.join(originals_dir(), media_path)


def cmd_relink(args):
    db = ledger()
    rows = db.execute("SELECT * FROM entries WHERE state = 'ingested' ORDER BY rel_path").fetchall()
    done = 0
    for row in rows:
        src = os.path.join(CANONICAL_ROOT, row["rel_path"])
        dst = media_abs(row["media_path"])
        if os.path.exists(dst) and os.path.exists(src):
            s, d = os.stat(src), os.stat(dst)
            if (s.st_dev, s.st_ino) == (d.st_dev, d.st_ino):
                db.execute(
                    "UPDATE entries SET state = 'relinked', updated = ? WHERE source_id = ?",
                    (now(), row["source_id"]),
                )
                db.commit()
                continue
        # BRIDGE_RELINK_HELPER may carry a privilege prefix ("sudo …").
        cmd = [
            *RELINK_HELPER.split(),
            "--source-id", row["source_id"],
            "--paperless-id", str(row["paperless_id"]),
            "--source", src,
            "--target", dst,
            "--sha256", row["sha256"],
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            log(f"relink helper refused {row['source_id']}: {proc.stderr.strip()}")
            receipt("relink-refused", source_id=row["source_id"], error=proc.stderr.strip())
            continue
        s, d = os.stat(src), os.stat(dst)
        if (s.st_dev, s.st_ino) != (d.st_dev, d.st_ino):
            die(f"relink helper reported success but inodes differ for {row['source_id']}")
        db.execute(
            "UPDATE entries SET state = 'relinked', updated = ? WHERE source_id = ?",
            (now(), row["source_id"]),
        )
        db.commit()
        receipt(
            "relinked",
            source_id=row["source_id"],
            paperless_id=row["paperless_id"],
            st_dev=s.st_dev,
            st_ino=s.st_ino,
        )
        done += 1
    print(json.dumps({"relinked": done}))
    return 0


# ---------------------------------------------------------------- enrich


def ensure_custom_fields():
    want = {
        "academic-db-id": "string",
        "source-id": "string",
        "sha256": "string",
        "doi": "string",
        "ocr-state": "string",
    }
    have = {f["name"]: f for f in api_all("/api/custom_fields/")}
    out = {}
    for name, dtype in want.items():
        if name not in have:
            have[name] = api("POST", "/api/custom_fields/", {"name": name, "data_type": dtype})
        out[name] = have[name]["id"]
    return out


def page_marker_projection(paper_md):
    """Canonical paper.md -> Paperless content: drop frontmatter, keep the
    page markers as plain text so lexical search can cite a page. The real
    June corpus writes `<!-- page:001 -->`; later passes may add a source."""
    body = re.sub(r"\A---\n.*?\n---\n", "", paper_md, flags=re.S)
    body = re.sub(
        r"<!-- page:(\d+)(?: source:[a-z0-9-]+)? -->",
        lambda m: f"[page {int(m.group(1))}]",
        body,
    )
    return body.strip() + "\n"


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def resolve_canonical(db_id):
    """db_id -> the academic-ocr canonical artifact for it, or None while the
    paper has none yet. Returns {md_path, source_hashes, receipt_pdf_sha256,
    doi}: source_hashes are every recorded claim about which PDF bytes the
    OCR ran on (catalog ocr_derivatives.source_sha256, paper.md frontmatter,
    source.json), each keyed by where it came from."""
    md_path = None
    hashes = {}
    db = open_catalog()
    if db is not None:
        try:
            row = db.execute(
                "SELECT source_sha256, canonical_markdown_path FROM ocr_derivatives WHERE db_id = ?",
                (db_id,),
            ).fetchone()
        except sqlite3.OperationalError:
            row = None
        finally:
            db.close()
        if row:
            if row[0]:
                hashes["catalog"] = row[0].lower()
            if row[1]:
                md_path = rebase_academic(row[1])
    paper_dir = os.path.join(ACADEMIC_ROOT, "ocr-june", "papers-canonical", db_id)
    if not (md_path and os.path.isfile(md_path)):
        md_path = os.path.join(paper_dir, "canonical", "paper.md")
    if not os.path.isfile(md_path):
        return None
    with open(md_path) as f:
        head = f.read(2000)
    m = re.search(r"^sha256:\s*([0-9a-f]{64})\s*$", head, flags=re.M)
    if m:
        hashes["frontmatter"] = m.group(1)
    source = read_json(os.path.join(os.path.dirname(os.path.dirname(md_path)), "source.json"))
    if source and source.get("sha256"):
        hashes["source.json"] = source["sha256"].lower()
    rec = read_json(os.path.join(ACADEMIC_ROOT, "receipts", "historical", f"{db_id}.json"))
    meta = read_json(os.path.join(os.path.dirname(os.path.dirname(md_path)), "metadata.json"))
    doi = ((meta or {}).get("openalex") or {}).get("doi")
    return {
        "md_path": md_path,
        "source_hashes": hashes,
        "receipt_pdf_sha256": (rec or {}).get("local_pdf_sha256"),
        "doi": doi,
    }


def canonical_mismatch(art, ledger_sha):
    """None when the canonical artifact provably describes the ledger's bytes;
    otherwise a reason. At least one OCR source-hash claim must exist and ALL
    of them must equal the ledger sha256; a historical receipt, when present,
    must name the same local PDF. (55 of the 184 June papers were OCRed from a
    different payload than the facsimile now on disk: those stay unsynced.)"""
    claims = art["source_hashes"]
    if not claims:
        return "no source hash recorded for the canonical artifact"
    wrong = {k: v for k, v in claims.items() if v != ledger_sha}
    if wrong:
        return "source hash differs: " + ", ".join(f"{k}={v[:12]}" for k, v in sorted(wrong.items()))
    if art["receipt_pdf_sha256"] and art["receipt_pdf_sha256"] != ledger_sha:
        return f"historical receipt names local pdf {art['receipt_pdf_sha256'][:12]}"
    return None


def cmd_enrich(args):
    db = ledger()
    fields = ensure_custom_fields()
    rows = db.execute(
        "SELECT * FROM entries WHERE academic_db_id IS NOT NULL AND paperless_id IS NOT NULL"
        " AND state IN ('relinked', 'canonical-synced')"
    ).fetchall()
    done, pending = 0, 0
    mismatched = 0
    for row in rows:
        if row["ocr_state"] == "canonical" and row["state"] == "canonical-synced":
            continue
        art = resolve_canonical(row["academic_db_id"])
        if art is None:
            pending += 1
            continue
        why = canonical_mismatch(art, row["sha256"])
        if why:
            log(f"ALARM: canonical artifact for {row['academic_db_id']} not synced: {why}")
            receipt("enrich-source-mismatch", source_id=row["source_id"],
                    academic_db_id=row["academic_db_id"], reason=why)
            mismatched += 1
            continue
        with open(art["md_path"]) as f:
            paper_md = f.read()
        content_sha = hashlib.sha256(paper_md.encode()).hexdigest()
        custom = [
            {"field": fields["academic-db-id"], "value": row["academic_db_id"]},
            {"field": fields["source-id"], "value": row["source_id"]},
            {"field": fields["sha256"], "value": row["sha256"]},
            {"field": fields["ocr-state"], "value": "canonical"},
        ]
        if art["doi"]:
            custom.append({"field": fields["doi"], "value": art["doi"]})
        api(
            "PATCH",
            f"/api/documents/{row['paperless_id']}/",
            {"content": page_marker_projection(paper_md), "custom_fields": custom},
        )
        db.execute(
            "UPDATE entries SET state = 'canonical-synced', ocr_state = 'canonical',"
            " updated = ? WHERE source_id = ?",
            (now(), row["source_id"]),
        )
        db.commit()
        receipt(
            "canonical-synced",
            source_id=row["source_id"],
            paperless_id=row["paperless_id"],
            academic_db_id=row["academic_db_id"],
            content_sha256=content_sha,
        )
        done += 1
    print(json.dumps({"synced": done, "awaiting_receipt": pending, "source_mismatch": mismatched}))
    return 0


# ---------------------------------------------------------------- tags


def load_taxonomy():
    with open(TAXONOMY) as f:
        return json.load(f)


def suggestable_slugs(tax):
    return sorted(t["slug"] for t in tax["tags"] if t["slug"].split("/", 1)[0] in SUGGEST_NAMESPACES)


def valid_tag_names(tax):
    """Taxonomy slugs plus the ai-candidate/<slug> mirror `suggest` may create
    for each suggestable slug; anything else in a machine namespace is drift."""
    return {t["slug"] for t in tax["tags"]} | {f"ai-candidate/{s}" for s in suggestable_slugs(tax)}


def cmd_sync_tags(args):
    tax = load_taxonomy()
    valid = valid_tag_names(tax)
    have = {t["name"]: t for t in api_all("/api/tags/")}
    created = 0
    for t in tax["tags"]:
        if t["slug"] not in have:
            api("POST", "/api/tags/", {"name": t["slug"]})
            created += 1
    # Machine-namespace tags that exist in Paperless but not in the taxonomy
    # are drift: report, never delete (a human may be mid-review).
    drift = [
        name
        for name in have
        if name.startswith(MACHINE_TAG_PREFIXES) and name not in valid
    ]
    # Export accepted tags to durable sidecars, one file per document.
    sidecars = os.path.join(STATE_DIR, "accepted-tags")
    os.makedirs(sidecars, exist_ok=True)
    db = ledger()
    tag_by_id = {t["id"]: t["name"] for t in api_all("/api/tags/")}
    exported = 0
    for row in db.execute("SELECT * FROM entries WHERE paperless_id IS NOT NULL").fetchall():
        doc = api("GET", f"/api/documents/{row['paperless_id']}/")
        names = sorted(
            tag_by_id[t] for t in doc["tags"]
            if not tag_by_id[t].startswith("ai-candidate/")
        )
        side = os.path.join(sidecars, f"{row['source_id']}.json")
        payload = {
            "source_id": row["source_id"],
            "sha256": row["sha256"],
            "paperless_id": row["paperless_id"],
            "tags": names,
            "taxonomy_version": tax["version"],
        }
        prior = None
        if os.path.exists(side):
            with open(side) as f:
                prior = {k: v for k, v in json.load(f).items() if k != "exported_at"}
        if prior != payload:
            with open(side + ".tmp", "w") as f:
                json.dump({**payload, "exported_at": now()}, f, indent=2, sort_keys=True)
            os.replace(side + ".tmp", side)
            exported += 1
    print(json.dumps({"tags_created": created, "drift": drift, "sidecars_updated": exported}))
    return 1 if drift else 0


# ---------------------------------------------------------------- suggest


def suggest_request(doc, tax, max_chars):
    slugs = suggestable_slugs(tax)
    vocab = "\n".join(
        f"- {t['slug']}: {t['definition']}" for t in tax["tags"] if t["slug"] in slugs
    )
    system = (
        "You classify one PDF for a personal document catalog. Choose ONLY from the"
        " controlled vocabulary below; never invent a slug. Reply with a single JSON"
        ' object and nothing else: {"tags": [{"slug": "<slug>", "confidence": <0..1>}]}.'
        " An empty list is a valid answer.\n\nVocabulary:\n" + vocab
    )
    user = (
        f"Title: {doc.get('title') or ''}\n"
        f"Original filename: {doc.get('original_file_name') or ''}\n\n"
        f"Extracted text (truncated):\n{(doc.get('content') or '')[:max_chars]}"
    )
    return {
        "model": "utility",
        "temperature": 0,
        "max_tokens": 4096,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }


def parse_candidates(text, allowed, min_confidence):
    """Model reply -> [(slug, confidence)], allowed slugs only, best first.
    Reasoning blocks and prose around the JSON are tolerated; a reply with no
    parseable object yields nothing (never a guess)."""
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return []
    try:
        obj = json.loads(text[start : end + 1])
    except ValueError:
        return []
    best = {}
    for item in obj.get("tags", []) if isinstance(obj, dict) else []:
        if not isinstance(item, dict):
            continue
        slug, conf = item.get("slug"), item.get("confidence")
        if slug not in allowed or not isinstance(conf, (int, float)) or isinstance(conf, bool):
            continue
        conf = float(conf)
        if not 0.0 <= conf <= 1.0 or conf < min_confidence:
            continue
        best[slug] = max(conf, best.get(slug, 0.0))
    return sorted(best.items(), key=lambda kv: (-kv[1], kv[0]))


def call_utility(request, timeout):
    proc = subprocess.run(
        shlex.split(UTILITY_CMD),
        input=json.dumps(request),
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"utility command failed ({proc.returncode}): {proc.stderr.strip()[:500]}")
    resp = json.loads(proc.stdout)
    content = resp["choices"][0]["message"].get("content") or ""
    return resp.get("model"), content


def prior_suggestion(doc_id, tax_version, model):
    for note in api("GET", f"/api/documents/{doc_id}/notes/") or []:
        text = note.get("note") or ""
        if not text.startswith(SUGGEST_NOTE_MARKER):
            continue
        try:
            rec = json.loads(text.split("\n", 1)[1])
        except (IndexError, ValueError):
            continue
        if rec.get("taxonomy_version") == tax_version and rec.get("model") == model:
            return rec
    return None


def suggest_lock():
    import fcntl

    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    fh = open(os.path.join(base, "paperless-bridge-suggest.lock"), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        die("another paperless-bridge suggest is running (concurrency is 1)")
    return fh


def cmd_suggest(args):
    """Bounded AI tag-candidate batch. Concurrency 1 by construction (serial
    loop + a host lock), one utility-model request per document, never a new
    model: the request lands on the worker's resident Halogen server through
    the coordinator's utility-model seam. Writes only ai-candidate/<slug>
    tags plus one audit note carrying model, taxonomy version and confidence;
    a human accepts by retagging into the owning namespace."""
    lock = suggest_lock()
    tax = load_taxonomy()
    allowed = set(suggestable_slugs(tax))
    if args.document_id:
        docs = [api("GET", f"/api/documents/{i}/") for i in args.document_id]
    else:
        docs = api("GET", "/api/documents/", params={"ordering": "id", "page_size": args.limit})["results"]
    tags = {t["name"]: t for t in api_all("/api/tags/")}
    out = []
    for doc in docs[: args.limit]:
        if not args.force and prior_suggestion(doc["id"], tax["version"], SUGGEST_MODEL):
            out.append({"document": doc["id"], "skipped": "already-suggested"})
            continue
        served, reply = call_utility(suggest_request(doc, tax, args.max_chars), args.timeout)
        cands = parse_candidates(reply, allowed, args.min_confidence)
        new_ids = []
        for slug, _conf in cands:
            name = f"ai-candidate/{slug}"
            if name not in tags:
                # matching_algorithm 0 = none: a candidate tag must never
                # auto-assign itself to future documents.
                tags[name] = api("POST", "/api/tags/", {"name": name, "matching_algorithm": 0})
            new_ids.append(tags[name]["id"])
        merged = sorted(set(doc.get("tags") or []) | set(new_ids))
        if merged != sorted(doc.get("tags") or []):
            api("PATCH", f"/api/documents/{doc['id']}/", {"tags": merged})
        rec = {
            "model": SUGGEST_MODEL,
            "served_model": served,
            "taxonomy_version": tax["version"],
            "candidates": [{"slug": sl, "confidence": round(c, 3)} for sl, c in cands],
            "at": now(),
        }
        api("POST", f"/api/documents/{doc['id']}/notes/",
            {"note": SUGGEST_NOTE_MARKER + "\n" + json.dumps(rec, sort_keys=True)})
        out.append({"document": doc["id"], **rec})
    lock.close()
    print(json.dumps({"suggested": out}, indent=2))
    return 0


# ---------------------------------------------------------------- bulk


def guard_reason(args):
    """Why an unattended round must not start now, or None. The NAS is the
    house router (dnsmasq DHCP/DNS, NAT): admission yields to it, to the disk
    (94% full at the 2026-09-13 flip) and to load, and it stops rather than
    waits so the unit's exit says what happened."""
    free = shutil.disk_usage(CANONICAL_ROOT).free
    if free < args.min_free_gb * 1024**3:
        return f"low-space: {free // 1024**3} GiB free < {args.min_free_gb} GiB"
    load1 = os.getloadavg()[0]
    if load1 > args.max_load:
        return f"load: {load1:.2f} > {args.max_load}"
    for unit in args.require_unit:
        if subprocess.run(["systemctl", "is-active", "--quiet", unit]).returncode != 0:
            return f"unit-inactive: {unit}"
    return None


BULK_PAUSED = 75  # EX_TEMPFAIL: guard tripped or no progress; rerun resumes


def pending_count():
    return ledger().execute("SELECT COUNT(*) FROM entries WHERE state = 'inventoried'").fetchone()[0]


def cmd_bulk(args):
    """Resumable admission: every step is ledger-driven and idempotent, so a
    stop, a crash or the morning reboot loses at most the in-flight document
    (its spool hardlink is reused on the next run)."""
    reason = guard_reason(args)
    if reason:
        receipt("bulk-paused", reason=reason, phase="start")
        log(f"bulk paused before scan: {reason}")
        return BULK_PAUSED
    if cmd_scan(args) != 0:
        receipt("bulk-aborted", reason="scan reported missing canonical files")
        return 1
    stalled = 0
    for rnd in range(args.max_rounds):
        before = pending_count()
        if before == 0:
            receipt("bulk-converged", rounds=rnd)
            return 0
        reason = guard_reason(args)
        if reason:
            receipt("bulk-paused", reason=reason, round=rnd, pending=before)
            log(f"bulk paused: {reason}")
            return BULK_PAUSED
        cmd_ingest(argparse.Namespace(batch=args.batch, timeout=args.timeout))
        cmd_relink(args)
        if cmd_verify(argparse.Namespace(hash=False)) != 0:
            receipt("bulk-aborted", reason="verify found violations", round=rnd)
            return 1
        after = pending_count()
        receipt("bulk-round", round=rnd, pending_before=before, pending_after=after)
        stalled = stalled + 1 if after >= before else 0
        if stalled >= 2:
            receipt("bulk-paused", reason="no progress in two rounds", round=rnd, pending=after)
            return BULK_PAUSED
    receipt("bulk-round-limit", rounds=args.max_rounds, pending=pending_count())
    return BULK_PAUSED if pending_count() else 0


# ---------------------------------------------------------------- verify


def cmd_verify(args):
    db = ledger()
    violations = []
    for row in db.execute("SELECT * FROM entries").fetchall():
        src = os.path.join(CANONICAL_ROOT, row["rel_path"])
        src_ok = os.path.isfile(src)
        if not src_ok:
            violations.append({"source_id": row["source_id"], "kind": "missing-canonical",
                               "path": row["rel_path"]})
        if row["state"] in ("relinked", "canonical-synced"):
            dst = media_abs(row["media_path"])
            if not os.path.isfile(dst):
                violations.append({"source_id": row["source_id"], "kind": "missing-projection",
                                   "path": row["media_path"]})
                continue
            if src_ok:
                s, d = os.stat(src), os.stat(dst)
                if (s.st_dev, s.st_ino) != (d.st_dev, d.st_ino):
                    violations.append({"source_id": row["source_id"], "kind": "detached-projection",
                                       "path": row["media_path"]})
                if args.hash:
                    sha, _ = digests(src)
                    if sha != row["sha256"]:
                        violations.append({"source_id": row["source_id"], "kind": "hash-drift",
                                           "path": row["rel_path"], "actual": sha})
    for v in violations:
        receipt("violation", **v)
        log(f"ALARM: {v['kind']} {v['path']} ({v['source_id']})")
    print(json.dumps({"entries": db.execute("SELECT COUNT(*) FROM entries").fetchone()[0],
                      "violations": violations}))
    return 1 if violations else 0


# ---------------------------------------------------------------- audit


def cmd_audit(args):
    db = ledger()
    by_state = dict(
        db.execute("SELECT state, COUNT(*) FROM entries GROUP BY state").fetchall()
    )
    ledger_ids = {
        r["paperless_id"]
        for r in db.execute("SELECT paperless_id FROM entries WHERE paperless_id IS NOT NULL")
    }
    orphans = [d["id"] for d in api_all("/api/documents/") if d["id"] not in ledger_ids]
    spool = os.listdir(SPOOL) if os.path.isdir(SPOOL) else []
    report = {
        "by_state": by_state,
        "paperless_docs_outside_ledger": orphans,
        "spool_leftovers": spool,
    }
    print(json.dumps(report, indent=2))
    return 1 if orphans or spool else 0


# ---------------------------------------------------------------- main


def main():
    p = argparse.ArgumentParser(prog="paperless-bridge", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    ing = sub.add_parser("ingest")
    ing.add_argument("--batch", type=int, default=50, help="entries per run (bounded admission)")
    ing.add_argument("--timeout", type=int, default=300, help="per-document consumer wait seconds")
    sub.add_parser("relink")
    sub.add_parser("enrich")
    sug = sub.add_parser("suggest")
    sug.add_argument("--limit", type=int, default=4, help="documents per run (bounded batch)")
    sug.add_argument("--document-id", type=int, action="append", help="explicit document(s)")
    sug.add_argument("--min-confidence", type=float, default=0.5)
    sug.add_argument("--max-chars", type=int, default=12000, help="document text sent per request")
    sug.add_argument("--timeout", type=float, default=1200, help="per-request seconds")
    sug.add_argument("--force", action="store_true", help="re-suggest already-suggested documents")
    sub.add_parser("sync-tags")
    ver = sub.add_parser("verify")
    ver.add_argument("--hash", action="store_true", help="also re-hash canonical bytes")
    sub.add_parser("audit")
    blk = sub.add_parser("bulk")
    blk.add_argument("--batch", type=int, default=50)
    blk.add_argument("--timeout", type=int, default=1800, help="per-document consumer wait seconds")
    blk.add_argument("--max-rounds", type=int, default=1000)
    blk.add_argument("--min-free-gb", type=int, default=150)
    blk.add_argument("--max-load", type=float, default=6.0)
    blk.add_argument("--require-unit", action="append", default=[],
                     help="systemd unit that must be active before each round")
    args = p.parse_args()
    handler = {
        "scan": cmd_scan,
        "ingest": cmd_ingest,
        "relink": cmd_relink,
        "enrich": cmd_enrich,
        "suggest": cmd_suggest,
        "bulk": cmd_bulk,
        "sync-tags": cmd_sync_tags,
        "verify": cmd_verify,
        "audit": cmd_audit,
    }[args.cmd]
    sys.exit(handler(args))


if __name__ == "__main__":
    main()
