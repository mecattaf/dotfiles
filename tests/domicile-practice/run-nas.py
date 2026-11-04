#!/usr/bin/env python3
"""NAS orchestrator: execute only on Strix, copy every outcome back to NAS."""
import argparse
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import sys
import tarfile
import uuid
from datetime import datetime, timezone

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--worktree", default="/home/tom/compute/dotfiles-domicile-practice")
p.add_argument("--out", type=Path, required=True, help="durable NAS receipts root")
p.add_argument("--remote-root", default="/home/tom/compute/domicile-practice-runs")
p.add_argument("worker_args", nargs=argparse.REMAINDER,
               help="after --, arguments for worker.py (see its --help)")
a = p.parse_args()
if socket.gethostname() != "nas":
    p.error("run this orchestrator on nas; compute has no credentials or agents")
args = a.worker_args[1:] if a.worker_args[:1] == ["--"] else a.worker_args
if any(x in ("--enter", "--inside", "--output") or x.startswith("--output=") for x in args):
    p.error("the orchestrator owns output paths and isolation entry")
run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
a.out = a.out.expanduser().resolve() / run_id
a.out.mkdir(parents=True, exist_ok=False)
remote = a.remote_root.rstrip("/") + "/" + run_id
base = ["fleet-exec", "strix-coordinator", "--cwd", a.worktree, "--"]
cmd = base + ["python3", "tests/domicile-practice/worker.py", "--enter", "--output", remote] + args
receipt = {"schema": 1, "run_id": run_id, "nas_host": socket.gethostname(),
           "remote_path": remote, "command": cmd, "transport_exit": None,
           "archive_exit": None, "artifact_status": "pending"}
def save():
    tmp = a.out / ".nas-receipt.json.tmp"
    tmp.write_text(json.dumps(receipt, indent=2) + "\n")
    tmp.replace(a.out / "nas-receipt.json")
save()
print("NAS receipts: " + str(a.out), flush=True)
print("Strix scratch: " + remote, flush=True)
try:
    with (a.out / "transport.log").open("wb") as log:
        # A file sink survives a failed/partial remote run and never truncates
        # output. Do not impose a watchdog that kills the SSH transport early.
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        receipt["transport_exit"] = result.returncode
finally:
    save()
    try:
        archive = a.out / "remote.tar.gz"
        with archive.open("wb") as out, (a.out / "archive.log").open("wb") as err:
            copied = subprocess.run(base + ["tar", "-C", remote, "--exclude=./cache", "--exclude=./home",
                             "--exclude=./chrome", "--exclude=./data", "--exclude=./state",
                             "--exclude=./config", "-czf", "-", "."],
                                    stdout=out, stderr=err)
        receipt["archive_exit"] = copied.returncode
        if copied.returncode == 0:
            receipt["archive_sha256"] = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
            dest = a.out / "artifacts"
            dest.mkdir()
            with tarfile.open(archive) as tf:
                # A fake HOME can contain links: data filter rejects escaping links
                # and device files rather than following them into the NAS home.
                tf.extractall(dest, filter="data")
            manifest = dest / "manifest.json"
            verified = 0
            if manifest.exists():
                for relative, expected in json.loads(manifest.read_text()).items():
                    path = (dest / relative).resolve()
                    if not path.is_relative_to(dest.resolve()):
                        raise ValueError("manifest path escapes artifact directory")
                    with path.open("rb") as f:
                        actual = hashlib.file_digest(f, "sha256").hexdigest()
                    if actual != expected["sha256"] or path.stat().st_size != expected["size"]:
                        raise ValueError("artifact integrity failed: " + relative)
                    verified += 1
            receipt["verified_files"] = verified
            receipt["artifact_status"] = "copied" if verified else "incomplete-no-manifest"
            outcome = dest / "receipt.json"
            if outcome.exists():
                receipt["result"] = json.loads(outcome.read_text())["result"]
        else:
            receipt["artifact_status"] = "copy-failed; remote data retained"
        save()
    except Exception as error:
        receipt["artifact_status"] = "copy-or-validation-failed; evidence retained"
        receipt["artifact_error"] = repr(error)
    finally:
        save()

print(json.dumps(receipt, indent=2))
raise SystemExit(0 if receipt.get("result") == "pass" and receipt["transport_exit"] == 0
                 and receipt["artifact_status"] == "copied" else 1)
