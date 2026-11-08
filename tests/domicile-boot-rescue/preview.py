#!/usr/bin/env python3
"""Use real bootctl against a private Strix ESP fixture; never touches host ESP."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from rescue import build_plan, require
from install import verify_menu


def preview(plan):
    # No kernels are copied. Small placeholders satisfy path discovery only.
    with tempfile.TemporaryDirectory(prefix="domicile-rescue-preview-") as tmp:
        root = Path(tmp)
        boot = root/"boot"
        (boot/"loader/entries").mkdir(parents=True)
        (boot/"loader/loader.conf").write_text(plan["snapshot"]["loader_conf"])
        files = dict(plan["snapshot"]["entries"])
        files[plan["target"]["entry_id"]] = plan["entry_text"]
        for name, text in files.items():
            (boot/"loader/entries"/name).write_text(text)
            for line in text.splitlines():
                if line.startswith(("linux ", "initrd ")):
                    relative = line.split(maxsplit=1)[1]
                    require(relative.startswith("/") and ".." not in Path(relative).parts,
                            "unsafe fixture path")
                    dest = boot/relative.lstrip("/")
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(b"fixture-placeholder")
        argv = ["bootctl", "--root="+tmp, "--esp-path=/boot", "--boot-path=/boot",
                "--variables=no", "--no-pager", "list", "--json=short"]
        result = subprocess.run(argv, text=True, capture_output=True,
                                env=os.environ | {"SYSTEMD_RELAX_ESP_CHECKS":"1", "SYSTEMD_RELAX_XBOOTLDR_CHECKS":"1"}, timeout=30)
        receipt = dict(command=argv, returncode=result.returncode, stderr=result.stderr,
                       bootctl_version=subprocess.check_output(["bootctl","--version"],text=True).splitlines()[0],
                       proof="Parsing and ordering of supplied entry text on Strix; placeholder assets, no boot proof.")
        require(result.returncode == 0, json.dumps(receipt))
        entries = json.loads(result.stdout)
        # bootctl --root prefixes paths, normalize only that fixture prefix.
        for e in entries:
            if e.get("path", "").startswith(tmp):
                e["path"] = e["path"][len(tmp):]
        verify_menu(plan, entries)
        receipt["entries"] = entries
        receipt["status"] = "PASS_VISIBLE_NOT_DEFAULT_IN_STRIX_FIXTURE"
        return receipt


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    p = json.loads(Path(args.plan).read_text())
    require(p == build_plan(p["snapshot"]), "plan mismatch")
    receipt = preview(p)
    Path(args.out).write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps({k:v for k,v in receipt.items() if k != "entries"}, indent=2))
