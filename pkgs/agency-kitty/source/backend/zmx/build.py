#!/usr/bin/env python3
"""Build the pinned, restricted PTY holder on compute. Never installs it.

Example from NAS (after staging this repository without credentials):
  fleet-exec strix-coordinator --cwd /absolute/checkout -- \
    python3 backend/zmx/build.py --workdir /absolute/build-directory
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import tarfile
import urllib.request


ZIG_URL = "https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz"
ZIG_SHA256 = "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026"
UPSTREAM = "a35f00a2118b15a5e9d522a43035c8d7487df9b7"


def run(*argv, cwd=None, env=None):
    subprocess.run(argv, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--patch", type=Path, default=Path(__file__).resolve().with_name("agency.patch"),
                        help="explicit reviewed patch; default preserves the qualifiedv3 build")
    args = parser.parse_args()
    if socket.gethostname().split(".")[0] == "nas":
        raise SystemExit("build on strix-coordinator through fleet-exec; NAS compilation is disabled")
    if platform.machine() != "x86_64" or platform.system() != "Linux":
        raise SystemExit("this qualified toolchain is Linux x86_64 only")
    root = args.workdir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    archive = root / "zig-0.17.0.tar.xz"
    if not archive.exists():
        urllib.request.urlretrieve(ZIG_URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ZIG_SHA256:
        raise SystemExit("official Zig archive checksum mismatch")
    compiler = root / "zig-x86_64-linux-0.17.0" / "zig"
    if not compiler.exists():
        with tarfile.open(archive) as source:
            source.extractall(root, filter="data")
    source = root / "zmx-agency"
    if source.exists():
        raise SystemExit("use a fresh workdir: an existing patched tree is never overwritten")
    run("git", "clone", "--depth=1", "--branch=v1.0.1", "https://github.com/neurosnap/zmx.git", str(source))
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if commit != UPSTREAM:
        raise SystemExit("upstream release tag does not match the reviewed commit")
    patch = args.patch.resolve()
    run("git", "apply", "--check", str(patch), cwd=source)
    run("git", "apply", str(patch), cwd=source)
    env = {**os.environ, "ZIG_GLOBAL_CACHE_DIR": str(root / "zig-cache")}
    run(str(compiler), "build", "-Doptimize=ReleaseSafe", "-Dtarget=x86_64-linux-musl", cwd=source, env=env)
    binary = source / "zig-out/bin/zmx"
    receipt = {"upstream": UPSTREAM, "patch_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
               "zig_url": ZIG_URL, "zig_sha256": ZIG_SHA256, "target": "x86_64-linux-musl",
               "optimization": "ReleaseSafe", "binary": str(binary),
               "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    (root / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
