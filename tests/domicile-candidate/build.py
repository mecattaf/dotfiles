#!/usr/bin/env python3
"""Build the reviewed client candidate on Strix, with exact local source inputs."""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import socket
import tempfile
import subprocess
import sys


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def engine_identity(checkout, revision):
    # Execute the complete reviewed identity helper from an immutable Git archive,
    # rather than trusting a mutable checkout or duplicating its hash algorithm.
    paths = [".github/scripts/engine-series-stamp.sh", "packages/domicile-engine/CHROMIUM_PIN",
             "packages/domicile-engine/patches", "packages/domicile-engine/src"]
    with tempfile.TemporaryDirectory(prefix="domicile-source-identity-") as scratch:
        archive = subprocess.run(["git", "-C", str(checkout), "archive", revision, *paths],
                                 stdout=subprocess.PIPE, check=True).stdout
        subprocess.run(["tar", "-x", "-C", scratch], input=archive, check=True)
        return subprocess.run(["bash", scratch + "/.github/scripts/engine-series-stamp.sh", "identity"],
                              text=True, capture_output=True, check=True).stdout.strip()


def provenance(tarball):
    names = subprocess.run(["tar", "--zstd", "-tf", str(tarball)],
                           text=True, capture_output=True, check=True).stdout.splitlines()
    entries = [n for n in names if re.fullmatch(r"[^/]+/PROVENANCE", n)]
    if len(entries) != 1:
        raise RuntimeError("engine must contain exactly one top-level PROVENANCE file")
    text = subprocess.run(["tar", "--zstd", "-xOf", str(tarball), entries[0]],
                          text=True, capture_output=True, check=True).stdout
    if len(text) > 65536:
        raise RuntimeError("oversized engine PROVENANCE")
    fields = {}
    for line in text.splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            if key in fields:
                raise RuntimeError("duplicate engine PROVENANCE key: " + key)
            fields[key] = value.strip()
    return fields, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotfiles-checkout", required=True, type=pathlib.Path)
    parser.add_argument("--dotfiles-revision", required=True)
    parser.add_argument("--domicile-checkout", required=True, type=pathlib.Path)
    parser.add_argument("--domicile-revision", required=True)
    parser.add_argument("--engine-tarball", required=True, type=pathlib.Path)
    parser.add_argument("--engine-sha256", required=True)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--evaluate-only", action="store_true")
    args = parser.parse_args()
    if socket.gethostname().split(".")[0] != "strix-coordinator":
        parser.error("run this build worker only on strix-coordinator through fleet-exec")
    for checkout, revision in [(args.dotfiles_checkout, args.dotfiles_revision),
                               (args.domicile_checkout, args.domicile_revision)]:
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            parser.error("source revisions must be full lowercase Git commit hashes")
        subprocess.run(["git", "-C", str(checkout), "cat-file", "-e", revision + "^{commit}"], check=True)
    if not re.fullmatch(r"[0-9a-f]{64}", args.engine_sha256):
        parser.error("engine SHA256 must be a lowercase 64-character hex digest")
    if sha256(args.engine_tarball) != args.engine_sha256:
        parser.error("engine tarball SHA256 mismatch")
    expected_series = engine_identity(args.domicile_checkout, args.domicile_revision)
    fields, provenance_text = provenance(args.engine_tarball)
    if fields.get("series identity") != expected_series:
        parser.error("engine PROVENANCE series differs from the exact Domicile source")
    engine_commit = fields.get("domicile commit", "")
    if not re.fullmatch(r"[0-9a-f]{40}", engine_commit):
        parser.error("engine PROVENANCE lacks a full Domicile commit")
    if engine_identity(args.domicile_checkout, engine_commit) != expected_series:
        parser.error("engine packaging commit does not describe the candidate engine series")
    if not fields.get("build", "").startswith("checked "):
        parser.error("candidate requires the checked engine flavor")
    recipe = pathlib.Path(__file__).resolve().with_name("build.nix")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    inputs = {
        "dotfilesCheckout": str(args.dotfiles_checkout.resolve()),
        "dotfilesRevision": args.dotfiles_revision,
        "domicileCheckout": str(args.domicile_checkout.resolve()),
        "domicileRevision": args.domicile_revision,
        "engineTarball": str(args.engine_tarball.resolve()),
    }
    identity = {"inputs": inputs, "engineSha256": args.engine_sha256,
                "recipeSha256": sha256(recipe), "engineSeries": expected_series,
                "enginePackagingCommit": engine_commit}
    identity_path = out / "inputs.json"
    if identity_path.exists() and json.loads(identity_path.read_text()) != identity:
        parser.error("output directory belongs to a different candidate")
    identity_path.write_text(json.dumps(identity, indent=2) + "\n")
    (out / "engine-PROVENANCE.txt").write_text(provenance_text)
    nix_args = ["--impure", "--file", str(recipe)]
    for key, value in inputs.items():
        nix_args += ["--argstr", key, value]
    evaluation = ["nix", "eval", *nix_args, "metadata", "--json"]
    with (out / "evaluation.stderr").open("wb") as log:
        result = subprocess.run(evaluation, stdout=subprocess.PIPE, stderr=log, check=True)
    metadata = json.loads(result.stdout)
    if metadata["failedAssertions"]:
        raise RuntimeError("candidate has failed NixOS assertions")
    (out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    receipt = {**identity, "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "evaluationCommand": evaluation, "evaluated": True, "built": False}
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if args.evaluate_only:
        print(json.dumps(metadata, indent=2))
        return
    # This is the build host's filesystem. Never run a fallback build elsewhere.
    disk = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, check=True)
    (out / "df-before-build.txt").write_text(disk.stdout)
    print(disk.stdout, end="", flush=True)
    free = shutil.disk_usage("/").free
    if free < 25 * 1024 ** 3:
        raise RuntimeError("stop: less than 25 GiB free on the build host")
    command = ["nix", "build", *nix_args, "system", "--out-link", str(out / "system"), "--print-out-paths"]
    receipt.update(buildCommand=command, freeBytesBeforeBuild=free)
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    with (out / "build.log").open("ab") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    receipt.update(buildExit=result.returncode, built=result.returncode == 0,
                   finishedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
    if result.returncode == 0:
        receipt["system"] = str((out / "system").resolve(strict=True))
        if receipt["system"] != metadata["system"]:
            raise RuntimeError("built system differs from evaluated metadata")
        receipt["gcRoot"] = str(out / "system")
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    if result.returncode:
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
