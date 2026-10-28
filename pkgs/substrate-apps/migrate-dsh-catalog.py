#!/usr/bin/env python3
"""Plan/apply Pi-to-DSH catalog migration during exclusive catalog maintenance.

Stop catalog edits while applying, or have writers take models.toml.migration.lock.
This tool serializes migrations; it cannot serialize an editor that ignores locks.
Never run automatically at Nix activation.
"""
import argparse
import copy
import contextlib
import datetime
import fcntl
import json
import os
import sys
from pathlib import Path
import tempfile
import tomllib

MODEL = "qwen3.8-flash-next"


def migrate(data):
    result = copy.deepcopy(data)
    rows = result.get("models")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise ValueError("catalog needs a [[models]] list")
    kept, retired = [], []
    local = None
    for row in rows:
        harness = row.get("harness")
        if harness == "pi":
            if row.get("provider", "gufo") not in {"gufo", "halogen"}:
                retired.append(row)
                continue
            if row.get("id") != MODEL:
                raise ValueError("unrecognized local Pi model; review it explicitly: " + str(row.get("id")))
            row["harness"] = "dsh"
            row["provider"] = "gufo"
            row.pop("pi", None)
            row["aliases"] = [a for a in row.get("aliases", []) if not a.startswith("halogen")]
        elif harness not in {"claude", "codex", "dsh"}:
            raise ValueError("unrecognized harness; leaving catalog untouched: " + str(harness))
        if row.get("harness") == "dsh" and row.get("provider", "gufo") == "gufo":
            if row.get("id") != MODEL and row.get("default"):
                raise ValueError("another Gufo default is configured; review it explicitly")
            if row.get("id") == MODEL:
                if local is not None:
                    raise ValueError("duplicate local Gufo model")
                local = row
        kept.append(row)
    if local is None:
        raise ValueError("expected local Flash-Next entry is absent; leaving catalog untouched")
    for alias in ["local", "nightly"]:
        if any(alias == row.get("id") or alias in row.get("aliases", []) for row in kept if row is not local):
            raise ValueError("alias belongs to another model: " + alias)
    local["provider"] = "gufo"
    local["default"] = True
    local["aliases"] = list(dict.fromkeys(local.get("aliases", []) + ["local", "nightly"]))
    result["models"] = kept
    return result, retired


def scalar(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(scalar(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(json.dumps(k) + " = " + scalar(v) for k, v in value.items()) + " }"
    raise ValueError("unsupported TOML value; leaving catalog untouched: " + type(value).__name__)


def serialize(data):
    lines = ["# Migrated explicitly by substrate-dsh-catalog; original retained beside this file."]
    for key, value in data.items():
        if key != "models":
            lines.append(json.dumps(key) + " = " + scalar(value))
    for row in data["models"]:
        lines.extend(["", "[[models]]"])
        lines.extend(json.dumps(key) + " = " + scalar(value) for key, value in row.items())
    text = "\n".join(lines) + "\n"
    if tomllib.loads(text) != data:
        raise ValueError("TOML round-trip failed; leaving catalog untouched")
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file", type=Path, default=Path.home() / ".config/substrate/models.toml")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="write after private backup; default is read-only plan")
    mode.add_argument("--check", action="store_true", help="read-only executor readiness check; bad config exits 78")
    args = ap.parse_args()
    path = args.file.expanduser()
    if args.check:
        with path.open("rb") as source:
            models = tomllib.load(source).get("models", [])
        if any(model.get("harness") == "pi" for model in models):
            print("substrate-puller: retired Pi catalog; review substrate-dsh-catalog, then apply explicitly", file=sys.stderr)
            raise SystemExit(78)
        if not any(model.get("harness") == "dsh" and model.get("provider") == "gufo" for model in models):
            print("substrate-puller: no DSH Gufo model configured", file=sys.stderr)
            raise SystemExit(78)
        print(json.dumps({"status": "ready", "catalog": str(path)}))
        return
    if path.is_symlink():
        raise ValueError("catalog is a symlink; migrate its explicit target instead")
    # Read-only plans create no lock or backup. Apply locks survive replacement.
    guard = (open(path.with_suffix(path.suffix + ".migration.lock"),
        "a", opener=lambda p, f: os.open(p, f, 0o600)) if args.apply else contextlib.nullcontext())
    with guard as lock:
        if lock is not None:
            fcntl.flock(lock, fcntl.LOCK_EX)
        original = path.read_bytes()
        data = tomllib.loads(original.decode())
        updated, retired = migrate(data)
        rendered = serialize(updated)
        report = {"status": "planned", "catalog": str(path), "changed": updated != data,
                  "local_model": MODEL, "retired_models": [row["id"] for row in retired]}
        if args.apply and updated != data:
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup = path.with_name(path.name + ".before-dsh-" + stamp)
            fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as out:
                out.write(original)
                out.flush()
                os.fsync(out.fileno())
            fd, staged = tempfile.mkstemp(prefix="." + path.name, dir=path.parent)
            try:
                with os.fdopen(fd, "w") as out:
                    out.write(rendered)
                    out.flush()
                    os.fsync(out.fileno())
                # Detect edits before publication. Manual writers must share the
                # migration lock or stop editing during this explicit maintenance.
                if path.read_bytes() != original:
                    raise ValueError("catalog changed during migration; original left in place")
                os.replace(staged, path)
                directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
            finally:
                if os.path.exists(staged):
                    os.unlink(staged)
            report.update(status="applied", backup=str(backup))
        elif args.apply:
            report["status"] = "unchanged"
        print(json.dumps(report))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
        raise SystemExit("substrate-dsh-catalog: " + str(exc))
