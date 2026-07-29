#!/usr/bin/env python3
"""absorb.py — production absorption of drained papers into the notes repo.

Generalizes the June migrate-june-corpus.sh semantics for the nightly drain:
for every paper under $DATA_ROOT/papers/<db_id>/ that has a canonical receipt
and is not yet absorbed, place canonical/paper.md at the notes path derived
from the catalog sidecar (sidecar_path minus 'catalog/sidecars/' prefix,
minus '.pdf.meta.json', plus '.md', rooted at notes/references/) and remove
the sidecar — sidecar presence means pending, .md presence means converted
(July 4 drain semantics). Text-only per the standing option-A figures ruling.

One git commit per invocation, staging only the files this run touched.
Ledger: $DATA_ROOT/drain/absorbed.jsonl. Idempotent and safe to re-run.
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import date

DATA_ROOT = os.environ.get("DATA_ROOT", os.path.expanduser("~/.local/state/academic-ocr"))
NOTES = os.environ.get("NOTES_REPO", os.path.expanduser("~/mecattaf/notes"))
CATALOG = "/mnt/nas/documents/academic-papers/catalog/papers.sqlite"
LEDGER = os.path.join(DATA_ROOT, "drain", "absorbed.jsonl")

absorbed = set()
if os.path.exists(LEDGER):
    for line in open(LEDGER):
        absorbed.add(json.loads(line)["db_id"])

db = sqlite3.connect(f"file:{CATALOG}?mode=ro", uri=True)
sidecar_of = dict(db.execute(
    "SELECT db_id, sidecar_path FROM paper_archive WHERE sidecar_path IS NOT NULL"))

papers_dir = os.path.join(DATA_ROOT, "papers")
actions, skips = [], []
for db_id in sorted(os.listdir(papers_dir)):
    if db_id in absorbed:
        continue
    receipt = os.path.join(papers_dir, db_id, "canonical", "receipt.json")
    paper_md = os.path.join(papers_dir, db_id, "canonical", "paper.md")
    if not (os.path.exists(receipt) and os.path.exists(paper_md)):
        continue
    sc = sidecar_of.get(db_id)
    if not sc:
        skips.append({"db_id": db_id, "reason": "no-catalog-row"})
        continue
    rel = sc[len("catalog/sidecars/"):] if sc.startswith("catalog/sidecars/") else None
    if not rel or not re.search(r"\.pdf\.meta\.json$", rel, re.IGNORECASE):
        skips.append({"db_id": db_id, "reason": f"unexpected-sidecar-path:{sc}"})
        continue
    sidecar_abs = os.path.join(NOTES, "references", rel)
    target_abs = os.path.join(NOTES, "references",
                              re.sub(r"\.pdf\.meta\.json$", ".md", rel, flags=re.IGNORECASE))
    if not os.path.exists(sidecar_abs):
        skips.append({"db_id": db_id, "reason": "sidecar-missing-in-notes"})
        continue
    if os.path.exists(target_abs):
        skips.append({"db_id": db_id, "reason": "target-md-already-exists"})
        continue
    actions.append({"db_id": db_id, "paper_md": paper_md,
                    "sidecar": sidecar_abs, "target": target_abs})

if not actions:
    print(json.dumps({"absorbed": 0, "skipped": skips}))
    sys.exit(0)

def git(*argv):
    return subprocess.run(["git", "-C", NOTES, *argv], capture_output=True, text=True)

done = []
for a in actions:
    os.makedirs(os.path.dirname(a["target"]), exist_ok=True)
    with open(a["paper_md"], "rb") as src, open(a["target"], "wb") as dst:
        dst.write(src.read())
    add = git("add", "--", os.path.relpath(a["target"], NOTES))
    rm = git("rm", "-q", "--", os.path.relpath(a["sidecar"], NOTES))
    if add.returncode or rm.returncode:
        print(f"git stage failed for {a['db_id']}: {add.stderr}{rm.stderr}", file=sys.stderr)
        continue
    done.append(a)

if done:
    msg = (f"absorb {len(done)} OCR papers from nightly drain ({date.today().isoformat()})\n\n"
           "canonical paper.md placed at the sidecar-derived path; sidecar removed\n"
           "(pending->converted). Source: tally paper-e2e flow, academic-ocr state root.\n\n"
           "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>")
    c = git("commit", "-m", msg)
    if c.returncode:
        print("git commit failed:", c.stderr, file=sys.stderr)
        sys.exit(1)
    with open(LEDGER, "a") as f:
        for a in done:
            f.write(json.dumps({"db_id": a["db_id"], "target": a["target"],
                                "absorbed_at": date.today().isoformat()}) + "\n")

head = git("rev-parse", "--short", "HEAD").stdout.strip()
print(json.dumps({"absorbed": len(done), "commit": head, "skipped": skips}))
