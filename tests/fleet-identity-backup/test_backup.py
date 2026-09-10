import importlib.util
import io
import json
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


script = Path(__file__).resolve().parents[2] / "hosts/nas/fleet-identity-backup.py"
spec = importlib.util.spec_from_file_location("fleet_identity_backup", script)
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class IdentityBackupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source"
        self.root.mkdir()
        for name in backup.FIXED_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture-identity")
        private = self.root / "etc/ssh/ssh_host_ed25519_key"
        private.unlink()
        private.with_name(private.name + ".pub").unlink()
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(private)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (self.root / "var/lib/atticd-secrets/env").write_bytes(b"ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=synthetic-only\n")
        state = self.root / "var/lib/tailscale"
        state.mkdir(parents=True)
        (state / "tailscaled.state").write_text('{"synthetic":"fixture"}')
        (state / "supplementary-state").write_bytes(b"fixture-supplement")
        (state / "tailscaled.log1.txt").write_bytes(b"excluded diagnostic log")
        self.connections = []
        for name in backup.DATABASES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            database = sqlite3.connect(path)
            database.execute("PRAGMA journal_mode=WAL")
            database.execute("CREATE TABLE cache (name TEXT, keypair TEXT, deleted_at TEXT)")
            database.execute("INSERT INTO cache VALUES ('fleet','synthetic-keypair',NULL)")
            database.commit()
            self.connections.append(database)
            self.addCleanup(database.close)
        self.config = self.root / "server.yaml"
        self.config.write_text("server_url: https://synthetic.invalid\n")
        self.policy = self.root / "policy.hujson"
        self.policy.write_text('{"acls": []}')
        self.staging = Path(self.temporary.name) / "snapshot"
        self.staging.mkdir(mode=0o700)

    def capture(self):
        return backup.capture(self.root, self.config, self.policy, self.staging)

    def archive(self):
        self.capture()
        path = Path(self.temporary.name) / "identity.tar.gz"
        backup.make_archive(self.staging, path)
        return path

    def test_live_wal_capture_and_archive_integrity(self):
        archive = self.archive()
        verification = Path(self.temporary.name) / "verify"
        verification.mkdir(mode=0o700)
        manifest = backup.verify_archive(archive, verification)
        self.assertIn("var/lib/tailscale/supplementary-state", manifest["files"])
        self.assertNotIn("var/lib/tailscale/tailscaled.log1.txt", manifest["files"])
        for name in backup.DATABASES:
            with sqlite3.connect(self.staging / name) as database:
                self.assertEqual(database.execute("SELECT name FROM cache").fetchall(), [("fleet",)])
                self.assertEqual(database.execute("PRAGMA journal_mode").fetchone(), ("delete",))
        for path in self.staging.rglob("*"):
            if path.is_file():
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_missing_required_identity_fails(self):
        (self.root / "var/lib/tailscale/tailscaled.state").unlink()
        with self.assertRaises(ValueError):
            self.capture()

    def test_empty_attic_fleet_key_fails(self):
        self.connections[1].execute("UPDATE cache SET keypair=''")
        self.connections[1].commit()
        with self.assertRaisesRegex(ValueError, "signing identity"):
            self.capture()

    def test_rotation_during_database_snapshot_fails(self):
        original = backup.database_copy
        def rotating(source, target):
            original(source, target)
            (self.root / "var/lib/headscale/noise_private.key").write_bytes(b"rotated-during-copy")
        with patch.object(backup, "database_copy", side_effect=rotating):
            with self.assertRaisesRegex(ValueError, "identity changed"):
                self.capture()

    def test_archive_tampering_is_rejected(self):
        self.capture()
        (self.staging / "var/lib/headscale/noise_private.key").write_bytes(b"tampered")
        archive = Path(self.temporary.name) / "tampered.tar.gz"
        backup.make_archive(self.staging, archive)
        verification = Path(self.temporary.name) / "verify"
        verification.mkdir()
        with self.assertRaisesRegex(ValueError, "mismatch"):
            backup.verify_archive(archive, verification)

    def test_unsafe_archive_member_is_rejected_without_extracting(self):
        archive = Path(self.temporary.name) / "unsafe.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            info = tarfile.TarInfo("../escape")
            info.mode = 0o600
            info.size = 1
            output.addfile(info, io.BytesIO(b"x"))
        with self.assertRaisesRegex(ValueError, "unsafe"):
            backup.verify_archive(archive, Path(self.temporary.name))
        self.assertFalse((Path(self.temporary.name).parent / "escape").exists())

    @unittest.skipUnless(shutil.which("age") and shutil.which("age-keygen"), "age tools required")
    def test_real_age_encrypt_decrypt_roundtrip_and_private_ciphertext(self):
        archive = self.archive()
        identity = Path(self.temporary.name) / "fixture.agekey"
        subprocess.run(["age-keygen", "-o", str(identity)], check=True, capture_output=True)
        recipient = subprocess.run(["age-keygen", "-y", str(identity)], check=True,
                                   capture_output=True, text=True).stdout.strip()
        destination = Path(self.temporary.name) / "ciphertext"
        destination.mkdir(mode=0o700)
        result = backup.encrypt(archive, destination, [recipient], "age", identity)
        self.assertTrue(result["decryptionVerified"])
        encrypted = Path(result["ciphertext"])
        self.assertEqual(stat.S_IMODE(encrypted.stat().st_mode), 0o600)
        self.assertEqual(backup.checksum(encrypted), result["sha256"])
        self.assertEqual(list(destination.iterdir()), [encrypted])

    def test_failed_encryption_does_not_publish(self):
        archive = self.archive()
        destination = Path(self.temporary.name) / "ciphertext"
        destination.mkdir(mode=0o700)
        with patch.object(backup.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "age")):
            with self.assertRaises(subprocess.CalledProcessError):
                backup.encrypt(archive, destination, [backup.ADMIN_RECIPIENT], "age")
        self.assertEqual(list(destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
