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
  sync-tags  ensure the versioned taxonomy exists in Paperless; export accepted tags
  verify     prove the same-inode invariant for every projected entry
  audit      full state report; nonzero exit on any violation

State: sqlite ledger + append-only receipts.jsonl under the bridge state
dir. Reconciliation keys are source_id + sha256 + paperless document id;
st_dev:st_ino is checked live, never trusted as durable identity.
"""

import argparse
import hashlib
import json
import os
import re
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
ACADEMIC_CANONICAL = os.environ.get(
    "BRIDGE_ACADEMIC_CANONICAL", "/mnt/nas/documents/academic-papers/canonical"
)
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


def academic_db_ids():
    """rel_path (under the canonical root) -> academic db_id, from the catalog."""
    catalog = os.path.join(CANONICAL_ROOT, "academic-papers/catalog/papers.sqlite")
    if not os.path.exists(catalog):
        return {}
    db = sqlite3.connect(f"file:{catalog}?mode=ro", uri=True)
    try:
        rows = db.execute("SELECT db_id, file_path FROM paper_archive WHERE file_path IS NOT NULL")
        out = {}
        for db_id, fp in rows:
            rel = os.path.join("academic-papers", fp) if not fp.startswith("academic-papers") else fp
            out[rel.lstrip("/")] = db_id
        return out
    except sqlite3.OperationalError as e:
        log(f"academic catalog unreadable ({e}); scanning without db_id mapping")
        return {}
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
        if meta["original_checksum"] != md5:
            die(
                f"checksum mismatch for {row['rel_path']}: canonical md5 {md5},"
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
    page markers as plain text so lexical search can cite a page."""
    body = re.sub(r"\A---\n.*?\n---\n", "", paper_md, flags=re.S)
    body = re.sub(r"<!-- page:(\d+) source:[a-z0-9-]+ -->", r"[page \1]", body)
    return body.strip() + "\n"


def cmd_enrich(args):
    db = ledger()
    fields = ensure_custom_fields()
    rows = db.execute(
        "SELECT * FROM entries WHERE academic_db_id IS NOT NULL AND paperless_id IS NOT NULL"
        " AND state IN ('relinked', 'canonical-synced')"
    ).fetchall()
    done, pending = 0, 0
    for row in rows:
        can_dir = os.path.join(ACADEMIC_CANONICAL, row["academic_db_id"])
        receipt_path = os.path.join(can_dir, "receipt.json")
        md_path = os.path.join(can_dir, "paper.md")
        if not (os.path.isfile(receipt_path) and os.path.isfile(md_path)):
            pending += 1
            continue
        with open(md_path) as f:
            paper_md = f.read()
        content_sha = hashlib.sha256(paper_md.encode()).hexdigest()
        if row["ocr_state"] == "canonical" and row["state"] == "canonical-synced":
            continue
        m = re.search(r"^sha256:\s*([0-9a-f]{64})\s*$", paper_md[:1000], flags=re.M)
        if m and m.group(1) != row["sha256"]:
            log(
                f"ALARM: canonical receipt for {row['academic_db_id']} is for source"
                f" {m.group(1)[:12]}…, ledger has {row['sha256'][:12]}…; not syncing"
            )
            receipt("enrich-source-mismatch", source_id=row["source_id"],
                    academic_db_id=row["academic_db_id"])
            continue
        api(
            "PATCH",
            f"/api/documents/{row['paperless_id']}/",
            {
                "content": page_marker_projection(paper_md),
                "custom_fields": [
                    {"field": fields["academic-db-id"], "value": row["academic_db_id"]},
                    {"field": fields["source-id"], "value": row["source_id"]},
                    {"field": fields["sha256"], "value": row["sha256"]},
                    {"field": fields["ocr-state"], "value": "canonical"},
                ],
            },
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
    print(json.dumps({"synced": done, "awaiting_receipt": pending}))
    return 0


# ---------------------------------------------------------------- tags


def cmd_sync_tags(args):
    with open(TAXONOMY) as f:
        tax = json.load(f)
    valid = {t["slug"] for t in tax["tags"]}
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
    sub.add_parser("sync-tags")
    ver = sub.add_parser("verify")
    ver.add_argument("--hash", action="store_true", help="also re-hash canonical bytes")
    sub.add_parser("audit")
    args = p.parse_args()
    handler = {
        "scan": cmd_scan,
        "ingest": cmd_ingest,
        "relink": cmd_relink,
        "enrich": cmd_enrich,
        "sync-tags": cmd_sync_tags,
        "verify": cmd_verify,
        "audit": cmd_audit,
    }[args.cmd]
    sys.exit(handler(args))


if __name__ == "__main__":
    main()
