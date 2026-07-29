#!/usr/bin/env python3
"""drain-worklist.py — build the OCR drain work-list from the NAS catalog.

Reads /mnt/nas/documents/academic-papers/catalog/papers.sqlite (paper_archive),
computes page counts with pdfinfo, excludes papers already carrying a canonical
receipt under $dataRoot/papers/<db_id>/, and writes worklist.jsonl sorted by
ascending page count. Papers over --max-pages land in deferred.jsonl instead of
the runnable list; unreadable PDFs land in broken.jsonl.

Idempotent: page counts are cached in pagecount-cache.json keyed by sha256.
"""
import json
import os
import sqlite3
import subprocess
import sys
import urllib.parse

NAS = "/mnt/nas/documents/academic-papers"
DATA_ROOT = os.environ.get("DATA_ROOT", os.path.expanduser("~/.local/state/academic-ocr"))
DRAIN = os.path.join(DATA_ROOT, "drain")
PDFINFO = None
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "env.sh")):
    if line.startswith("POPPLER="):
        PDFINFO = line.strip().split("=", 1)[1] + "/pdfinfo"
if not PDFINFO or not os.path.exists(PDFINFO):
    sys.exit("pdfinfo not found via env.sh POPPLER pin")

MAX_PAGES = int(sys.argv[sys.argv.index("--max-pages") + 1]) if "--max-pages" in sys.argv else 1500

os.makedirs(DRAIN, exist_ok=True)
cache_path = os.path.join(DRAIN, "pagecount-cache.json")
cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}

def page_count(path, sha):
    if sha in cache:
        return cache[sha]
    try:
        out = subprocess.run([PDFINFO, path], capture_output=True, text=True, timeout=60)
        pages = None
        for ln in out.stdout.splitlines():
            if ln.startswith("Pages:"):
                pages = int(ln.split()[1])
        cache[sha] = pages
        return pages
    except Exception:
        cache[sha] = None
        return None

db = sqlite3.connect(os.path.join(NAS, "catalog", "papers.sqlite"))
rows = db.execute(
    "SELECT db_id, local_pdf_path, local_pdf_sha256, sidecar_path, migration_status"
    " FROM paper_archive WHERE local_pdf_sha256 IS NOT NULL ORDER BY db_id"
).fetchall()

runnable, deferred, broken, done = [], [], [], []
for i, (db_id, rel, sha, sidecar, status) in enumerate(rows):
    abspath = os.path.join(NAS, rel)
    if not os.path.exists(abspath):
        broken.append({"db_id": db_id, "path": rel, "reason": "missing-file"})
        continue
    if os.path.exists(os.path.join(DATA_ROOT, "papers", db_id, "canonical", "receipt.json")):
        done.append(db_id)
        continue
    pages = page_count(abspath, sha)
    if i % 250 == 0:
        json.dump(cache, open(cache_path, "w"))
        print(f"  scanned {i}/{len(rows)}", file=sys.stderr)
    if not pages:
        broken.append({"db_id": db_id, "path": rel, "reason": "pdfinfo-failed"})
        continue
    title = os.path.splitext(os.path.basename(rel))[0]
    entry = {
        "db_id": db_id,
        "title": title,
        "pages": pages,
        "sha256": sha,
        "local_pdf_path": rel,
        "file_url": "file://" + urllib.parse.quote(abspath),
        "sidecar_path": sidecar,
        "migration_status": status,
    }
    (runnable if pages <= MAX_PAGES else deferred).append(entry)

json.dump(cache, open(cache_path, "w"))
# Ruled 2026-07-29: Bocconi papers drain first, shortest-first within each band.
def order(e):
    is_bocconi = e["local_pdf_path"].startswith("originals/knowledge/bocconi/")
    return (0 if is_bocconi else 1, e["pages"], e["db_id"])
runnable.sort(key=order)
deferred.sort(key=order)

for name, data in [("worklist.jsonl", runnable), ("deferred.jsonl", deferred), ("broken.jsonl", broken)]:
    with open(os.path.join(DRAIN, name), "w") as f:
        for e in data:
            f.write(json.dumps(e) + "\n")

total_pages = sum(e["pages"] for e in runnable)
print(json.dumps({
    "runnable": len(runnable), "runnable_pages": total_pages,
    "deferred_over_%d_pages" % MAX_PAGES: len(deferred),
    "broken": len(broken), "already_done": len(done),
}, indent=1))
