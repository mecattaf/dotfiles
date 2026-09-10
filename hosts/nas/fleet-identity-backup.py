#!/usr/bin/env python3
"""Manual encrypted NAS identity snapshot; never restore or stop live services."""

import argparse
from contextlib import closing
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import stat
import subprocess
import tarfile
import tempfile
import time


# Existing operator-only recipient: secrets.nix, editors/operator-vault.
# Host SSH recipients are deliberately not added to this recovery authority.
ADMIN_RECIPIENT = "age159pyyqqnrxwv3d7f758u5xtzv53fu2nwc85x3sur63g3p29jnegq9tf47w"
FIXED_FILES = (
    "etc/ssh/ssh_host_ed25519_key", "etc/ssh/ssh_host_ed25519_key.pub",
    "var/lib/headscale/noise_private.key", "var/lib/atticd-secrets/env",
)
DATABASES = ("var/lib/headscale/db.sqlite", "var/lib/atticd/server.db")


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def private_write(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("xb") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def stable_read(path):
    """Atomic replacements or concurrent writes fail instead of mixing bytes."""
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size == 0:
        raise ValueError("required identity source is not a nonempty regular file")
    with path.open("rb") as stream:
        opened = os.fstat(stream.fileno())
        raw = stream.read()
        finished = os.fstat(stream.fileno())
    after = path.stat()
    fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
    snapshots = [tuple(getattr(item, field) for field in fields)
                 for item in (before, opened, finished, after)]
    if len(set(snapshots)) != 1 or len(raw) != before.st_size:
        raise ValueError("identity source changed during capture; retry")
    return raw


def database_copy(source, target):
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    deadline = time.monotonic() + 300
    def progress(_status, _remaining, _total):
        if time.monotonic() > deadline:
            raise TimeoutError("SQLite online snapshot exceeded five minutes")
    with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True, timeout=30)) as origin:
        with closing(sqlite3.connect(target, timeout=30)) as copied:
            origin.backup(copied, pages=256, progress=progress, sleep=0.05)
            copied.execute("PRAGMA journal_mode=DELETE")
            if copied.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("SQLite snapshot integrity check failed")
            if not copied.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchone():
                raise ValueError("SQLite identity database is empty")
            if source.name == "server.db" and not copied.execute(
                    "SELECT 1 FROM cache WHERE name='fleet' AND length(keypair)>0 AND deleted_at IS NULL").fetchone():
                raise ValueError("Attic snapshot has no active fleet signing identity")
    target.chmod(0o600)


def tailscale_files(root):
    directory = root / "var/lib/tailscale"
    result = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError("unexpected symlink in Tailscale state; inspect before backup")
        if path.is_file() and not path.name.startswith("tailscaled.log"):
            result.append(path)
        elif not path.is_dir() and not path.is_file():
            raise ValueError("unexpected special file in Tailscale state")
    if directory / "tailscaled.state" not in result:
        raise ValueError("Tailscale identity state is missing")
    return result


def capture(root, server_config, policy, staging):
    sources = {name: root / name for name in FIXED_FILES}
    sources.update({str(path.relative_to(root)): path for path in tailscale_files(root)})
    sources.update({"reference/headscale-server.yaml": server_config,
                    "reference/headscale-policy.hujson": policy})
    originals = {}
    for name, source in sources.items():
        raw = stable_read(source)
        originals[name] = hashlib.sha256(raw).hexdigest()
        private_write(staging / name, raw)
    for name in DATABASES:
        database_copy(root / name, staging / name)
    private_key = staging / "etc/ssh/ssh_host_ed25519_key"
    derived = subprocess.run(["ssh-keygen", "-y", "-P", "", "-f", str(private_key)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout.split()
    recorded = (staging / "etc/ssh/ssh_host_ed25519_key.pub").read_bytes().split()
    if len(derived) < 2 or derived[:2] != recorded[:2]:
        raise ValueError("NAS SSH signing identity does not match its public key")
    if not any(line.startswith(b"ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=")
               and line.partition(b"=")[2].strip() for line in
               (staging / "var/lib/atticd-secrets/env").read_bytes().splitlines()):
        raise ValueError("Attic RS256 signing secret is absent")
    tailscale_state = json.loads((staging / "var/lib/tailscale/tailscaled.state").read_bytes())
    if not isinstance(tailscale_state, dict) or not tailscale_state:
        raise ValueError("Tailscale state is not a nonempty JSON object")
    # Private identity files must bracket the independent database snapshots.
    # This is not a cross-service transaction; concurrent rotations must retry.
    for name, source in sources.items():
        if hashlib.sha256(stable_read(source)).hexdigest() != originals[name]:
            raise ValueError("identity changed across database snapshots; retry")
    if {str(path.relative_to(root)) for path in tailscale_files(root)} != {
            name for name in sources if name.startswith("var/lib/tailscale/")}:
        raise ValueError("Tailscale state inventory changed during snapshot; retry")
    names = sorted(list(sources) + list(DATABASES))
    manifest = {
        "schemaVersion": 1, "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "method": "online-sqlite-backup-and-stable-identity-files",
        "excluded": ["Tailscale diagnostic logs", "Attic NAR/chunk storage", "laptop owner secrets"],
        "files": {name: {"sha256": checksum(staging / name), "size": (staging / name).stat().st_size,
                         "mode": "0600"} for name in names},
    }
    private_write(staging / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
    return manifest


def make_archive(staging, archive):
    with tarfile.open(archive, "x:gz") as output:
        for path in sorted(staging.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            name = path.relative_to(staging).as_posix()
            info = output.gettarinfo(str(path), arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mode = 0o600
            with path.open("rb") as source:
                output.addfile(info, source)
    archive.chmod(0o600)


def verify_archive(archive, verification_directory):
    """Inspect all metadata and hashes; restore only SQLite into private scratch."""
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        names = [item.name for item in members]
        if len(names) != len(set(names)):
            raise ValueError("duplicate archive members")
        for item in members:
            path = PurePosixPath(item.name)
            if (not item.isfile() or path.is_absolute() or ".." in path.parts
                    or item.mode != 0o600 or item.uid != 0 or item.gid != 0):
                raise ValueError("unsafe archive metadata")
        manifest = json.load(source.extractfile("manifest.json"))
        expected = set(manifest.get("files", {}))
        required = set(FIXED_FILES) | set(DATABASES) | {
            "var/lib/tailscale/tailscaled.state", "reference/headscale-server.yaml",
            "reference/headscale-policy.hujson",
        }
        if (manifest.get("schemaVersion") != 1 or not required <= expected
                or set(names) != expected | {"manifest.json"}):
            raise ValueError("incomplete identity archive")
        for name, metadata in manifest["files"].items():
            item = source.getmember(name)
            if metadata.get("mode") != "0600" or item.size != metadata.get("size"):
                raise ValueError("archive size/mode mismatch")
            with source.extractfile(item) as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != metadata.get("sha256"):
                    raise ValueError("archive checksum mismatch")
            if name in DATABASES:
                restored = verification_directory / ("headscale.sqlite" if "headscale" in name else "attic.sqlite")
                with source.extractfile(item) as stream, restored.open("xb") as output:
                    os.fchmod(output.fileno(), 0o600)
                    shutil.copyfileobj(stream, output, length=1024 * 1024)
                with closing(sqlite3.connect(restored.as_uri() + "?mode=ro", uri=True)) as database:
                    if database.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                        raise ValueError("archived SQLite restore check failed")
    return manifest


def encrypt(archive, destination, recipients, age, identity=None):
    # Output goes to a unique private temporary name; failed encryption never
    # publishes a plausible recovery artifact or overwrites a previous backup.
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    descriptor, temporary = tempfile.mkstemp(prefix=".encrypting-", dir=destination)
    os.close(descriptor)
    temporary = Path(temporary)
    try:
        command = [age]
        for recipient in recipients:
            command.extend(["--recipient", recipient])
        with temporary.open("wb") as encrypted:
            subprocess.run(command + [str(archive)], stdout=encrypted, stderr=subprocess.PIPE, check=True)
            encrypted.flush()
            os.fsync(encrypted.fileno())
        if identity:
            # No plaintext output to the terminal. Equality covers every byte
            # of the archive already checked above, including both databases.
            decrypted = archive.with_name("decryption-check.tar.gz")
            with decrypted.open("xb") as output:
                os.fchmod(output.fileno(), 0o600)
                subprocess.run([age, "--decrypt", "--identity", str(identity), str(temporary)],
                               stdout=output, stderr=subprocess.PIPE, check=True)
            if checksum(decrypted) != checksum(archive):
                raise ValueError("archive decryption round-trip mismatch")
        final = destination / f"fleet-identities-{stamp}-{temporary.name.removeprefix('.encrypting-')}.tar.gz.age"
        os.link(temporary, final)  # exclusive: never overwrite an existing snapshot
        temporary.unlink()
        directory = os.open(destination, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        return {"ciphertext": str(final), "sha256": checksum(final),
                "archiveVerified": True, "decryptionVerified": bool(identity)}
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headscale-config", type=Path, required=True,
                        help="actual server YAML from headscale.service, not the CLI stub")
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--destination", type=Path, default=Path("/mnt/nas/services/fleet-identity-backups"))
    parser.add_argument("--recipient", action="append", help="operator age recipient; defaults to secrets.nix admin")
    parser.add_argument("--verify-identity", type=Path, help="optional private age identity for silent round-trip")
    parser.add_argument("--age", default="age")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("identity backups require root")
    os.umask(0o077)
    destination = args.destination.resolve()
    base = Path("/mnt/nas/services")
    if not os.path.ismount("/mnt/nas") or not destination.is_relative_to(base) or destination == base:
        parser.error("ciphertext destination must be beneath mounted /mnt/nas/services")
    if any((ancestor / ".git").exists() for ancestor in [destination, *destination.parents]):
        parser.error("recovery archives must never enter a Git worktree")
    destination.mkdir(mode=0o700, exist_ok=True)
    if destination.stat().st_uid != 0 or stat.S_IMODE(destination.stat().st_mode) != 0o700:
        parser.error("ciphertext destination must already be root-owned mode 0700")
    with tempfile.TemporaryDirectory(prefix="fleet-identity-backup-", dir="/run") as temporary:
        scratch = Path(temporary)
        staging = scratch / "snapshot"
        staging.mkdir(mode=0o700)
        capture(Path("/"), args.headscale_config, args.policy, staging)
        archive = scratch / "identities.tar.gz"
        make_archive(staging, archive)
        verification = scratch / "verification"
        verification.mkdir(mode=0o700)
        verify_archive(archive, verification)
        result = encrypt(archive, destination, args.recipient or [ADMIN_RECIPIENT],
                         args.age, args.verify_identity)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, sqlite3.Error, tarfile.TarError, subprocess.SubprocessError) as error:
        # Subprocess stderr can contain secret-adjacent paths; report only its
        # class. Operators inspect local inputs, never paste key material.
        raise SystemExit(f"fleet-identity-backup failed ({type(error).__name__}); no new verified archive published")
