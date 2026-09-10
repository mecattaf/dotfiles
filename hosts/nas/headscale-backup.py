#!/usr/bin/env python3
"""Consistent Headscale snapshots and isolated restore verification; no live restore."""
import argparse
from contextlib import closing
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_private(path, data):
    with path.open("xb") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def database_copy(source, target):
    # SQLite's backup API includes committed WAL frames while the server runs.
    # mode=ro avoids creating an empty source if its configured path is wrong.
    with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True, timeout=30)) as origin:
        with closing(sqlite3.connect(target, timeout=30)) as copy:
            origin.backup(copy, pages=256, sleep=0.1)
            copy.execute("PRAGMA journal_mode=DELETE")
            result = copy.execute("PRAGMA integrity_check").fetchall()
            if result != [("ok",)]:
                raise ValueError("SQLite backup integrity check failed")
    target.chmod(0o600)
    with target.open("rb") as stream:
        os.fsync(stream.fileno())


def verify(snapshot):
    snapshot = snapshot.resolve()
    manifest = json.loads((snapshot / "manifest.json").read_text())
    expected = {"db.sqlite", "noise_private.key", "config.yaml", "policy.hujson"}
    if manifest.get("schemaVersion") != 1 or set(manifest.get("sha256", {})) != expected:
        raise ValueError("unknown or incomplete Headscale backup manifest")
    for name, checksum in manifest["sha256"].items():
        path = snapshot / name
        if path.is_symlink() or not path.is_file() or digest(path) != checksum:
            raise ValueError(f"backup checksum mismatch: {name}")
        if path.stat().st_mode & 0o077:
            raise ValueError(f"backup file is not private: {name}")
    if not (snapshot / "noise_private.key").stat().st_size:
        raise ValueError("backup has an empty Noise key")
    # Exercise restoration to a disposable DB, never the live Headscale path.
    with tempfile.TemporaryDirectory(prefix="headscale-restore-check-") as temporary:
        database_copy(snapshot / "db.sqlite", Path(temporary) / "restored.sqlite")
    return manifest


def switch_link(link, target):
    temporary = link.with_name("." + link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, link)
    sync_dir(link.parent)


def retained(destination):
    names = set()
    for label in ("current", "previous"):
        link = destination / label
        if link.is_symlink():
            target = link.resolve()
            if target.parent != (destination / "snapshots").resolve():
                raise ValueError("unexpected snapshot symlink target")
            names.add(target.name)
    return names


def prune(destination):
    keep = retained(destination)
    for snapshot in (destination / "snapshots").iterdir():
        if snapshot.name not in keep and snapshot.is_dir() and not snapshot.is_symlink():
            shutil.rmtree(snapshot)


def backup(mount, destination, source, config, policy):
    mount = mount.resolve()
    destination = destination.resolve()
    if not os.path.ismount(mount):
        raise ValueError(f"backup disk is not mounted: {mount}")
    if not destination.is_relative_to(mount) or destination == mount:
        raise ValueError("backup destination must be below the mounted backup disk")
    # /mnt/nas/services is already root:root 0711; do not alter the shared parent.
    if not destination.parent.is_dir():
        raise ValueError("backup services parent is missing; restore the data-disk layout first")
    destination.mkdir(mode=0o700, exist_ok=True)
    destination.chmod(0o700)
    with (destination / "backup.lock").open("w") as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        snapshots = destination / "snapshots"
        snapshots.mkdir(mode=0o700, exist_ok=True)
        prune(destination)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
        snapshot = Path(tempfile.mkdtemp(prefix=stamp + "-", dir=snapshots))
        try:
            key = (source / "noise_private.key").read_bytes()
            if not key:
                raise ValueError("Headscale Noise key is empty")
            database_copy(source / "db.sqlite", snapshot / "db.sqlite")
            if (source / "noise_private.key").read_bytes() != key:
                raise ValueError("Headscale Noise key changed during the database snapshot; retry")
            write_private(snapshot / "noise_private.key", key)
            write_private(snapshot / "config.yaml", config.read_bytes())
            write_private(snapshot / "policy.hujson", policy.read_bytes())
            manifest = {
                "schemaVersion": 1,
                "createdAt": stamp,
                "method": "sqlite-online-backup-with-isolated-restore-check",
                "sha256": {path.name: digest(path) for path in sorted(snapshot.iterdir())},
            }
            write_private(snapshot / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
            verify(snapshot)
            sync_dir(snapshot)
            sync_dir(snapshots)
            current = destination / "current"
            if current.is_symlink():
                switch_link(destination / "previous", os.readlink(current))
            switch_link(current, "snapshots/" + snapshot.name)
            prune(destination)
            return snapshot
        finally:
            current = destination / "current"
            if not current.is_symlink() or current.resolve() != snapshot.resolve():
                shutil.rmtree(snapshot)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mount", type=Path, default=Path("/mnt/nas"))
    parser.add_argument("--destination", type=Path, default=Path("/mnt/nas/services/headscale-backups"))
    parser.add_argument("--source", type=Path, default=Path("/var/lib/headscale"))
    parser.add_argument("--config", type=Path, help="actual server YAML, not /etc/headscale/config.yaml's CLI-only stub")
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--verify", type=Path, help="verify a snapshot and restore it only into a temporary database")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Headscale identity backups require root")
    os.umask(0o077)
    if args.verify:
        verify(args.verify)
        print("Backup checksums, privacy, SQLite integrity, and isolated restore verified.")
    else:
        if not args.policy or not args.config:
            parser.error("backup requires --policy and --config (the server's actual YAML)")
        result = backup(args.mount, args.destination, args.source, args.config, args.policy)
        print(f"Verified Headscale snapshot published: {result}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"headscale-backup: {error}", file=sys.stderr)
        sys.exit(1)
