#!/usr/bin/env python3
"""paperless-relink-helper — the only privileged step of the projection
bridge (dotfiles#136). Replaces one Paperless-owned original with a hardlink
to its canonical inode, after refusing everything that is not exactly the
requested, ledger-known, hash-identical pair. Runs as root because Linux
protected-hardlink rules stay enabled; everything else about the bridge is
unprivileged.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import stat
import sys
from datetime import datetime, timezone

CANONICAL_ROOT = os.environ.get("BRIDGE_CANONICAL_ROOT", "/mnt/nas/documents")
VIEW_ROOT = os.environ.get("BRIDGE_VIEW_ROOT", "/mnt/nas/documents/.paperless-view")
STATE_DIR = os.environ.get("BRIDGE_STATE_DIR", "/mnt/nas/services/paperless/bridge")
RECEIPTS = os.path.join(STATE_DIR, "relink-receipts.jsonl")


def refuse(msg):
    print(f"refused: {msg}", file=sys.stderr)
    sys.exit(2)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def under(root, path):
    return os.path.commonpath([root, path]) == root


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source-id", required=True)
    p.add_argument("--paperless-id", required=True, type=int)
    p.add_argument("--source", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--sha256", required=True)
    a = p.parse_args()

    # The pair must be one the unprivileged bridge already recorded: this
    # helper takes no orders that the ledger has not seen.
    db = sqlite3.connect(f"file:{os.path.join(STATE_DIR, 'ledger.sqlite')}?mode=ro", uri=True)
    row = db.execute(
        "SELECT rel_path, sha256, paperless_id FROM entries WHERE source_id = ?",
        (a.source_id,),
    ).fetchone()
    if row is None:
        refuse(f"source id {a.source_id} not in ledger")
    rel_path, ledger_sha, ledger_pid = row
    if ledger_pid != a.paperless_id:
        refuse(f"paperless id {a.paperless_id} does not match ledger ({ledger_pid})")
    if ledger_sha != a.sha256:
        refuse("sha256 argument does not match ledger")

    src = os.path.realpath(a.source)
    dst = os.path.realpath(a.target)
    if src != os.path.realpath(os.path.join(CANONICAL_ROOT, rel_path)):
        refuse("source path does not match the ledger entry's canonical path")
    if not under(os.path.realpath(CANONICAL_ROOT), src):
        refuse("source escapes the canonical root")
    if not under(os.path.realpath(VIEW_ROOT), dst):
        refuse("target escapes the projection root")
    for path, name in ((a.source, "source"), (a.target, "target")):
        if os.path.islink(path):
            refuse(f"{name} is a symlink")
    st_src, st_dst = os.lstat(src), os.lstat(dst)
    for st_, name in ((st_src, "source"), (st_dst, "target")):
        if not stat.S_ISREG(st_.st_mode):
            refuse(f"{name} is not a regular file")
    if st_src.st_dev != st_dst.st_dev:
        refuse("source and target are on different filesystems; hardlink impossible")
    if sha256(src) != a.sha256:
        refuse("source bytes do not match the requested sha256")
    if sha256(dst) != a.sha256:
        refuse("target bytes do not match the requested sha256; not the same document")

    tmp = dst + ".relink-tmp"
    if os.path.exists(tmp):
        os.unlink(tmp)
    os.link(src, tmp)
    os.replace(tmp, dst)

    st = os.stat(dst)
    rec = {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_id": a.source_id,
        "paperless_id": a.paperless_id,
        "rel_path": rel_path,
        "sha256": a.sha256,
        "st_dev": st.st_dev,
        "st_ino": st.st_ino,
    }
    with open(RECEIPTS, "a") as f:
        f.write(json.dumps(rec, sort_keys=True) + "\n")
    print(json.dumps(rec))


if __name__ == "__main__":
    main()
