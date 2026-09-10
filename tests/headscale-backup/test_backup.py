#!/usr/bin/env python3
"""Exercise live-WAL snapshots and failure-safe publication using private fixtures."""
import importlib.util
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import stat
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / "hosts/nas/headscale-backup.py"
SPEC = importlib.util.spec_from_file_location("headscale_backup", SOURCE)
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.mount = self.root / "disk"
        self.mount.mkdir()
        (self.mount / "services").mkdir(mode=0o711)
        self.destination = self.mount / "services/headscale-backups"
        self.source = self.root / "live"
        self.source.mkdir()
        self.writer = sqlite3.connect(self.source / "db.sqlite")
        self.writer.execute("PRAGMA journal_mode=WAL")
        self.writer.execute("PRAGMA wal_autocheckpoint=0")
        self.writer.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
        self.writer.execute("INSERT INTO nodes VALUES (1, 'xps-fleet')")
        self.writer.commit()
        (self.source / "noise_private.key").write_bytes(b"fixture-private-noise-key\n")
        self.config = self.root / "config.yaml"
        self.config.write_text("server_url: https://example.test:8443\n")
        self.policy = self.root / "policy.hujson"
        self.policy.write_text('{"acls": []}\n')

    def tearDown(self):
        self.writer.close()
        self.temporary.cleanup()

    def take(self):
        with patch.object(backup.os.path, "ismount", return_value=True):
            return backup.backup(self.mount, self.destination, self.source, self.config, self.policy)

    def test_backup_includes_committed_wal_and_restores_privately(self):
        self.assertGreater((self.source / "db.sqlite-wal").stat().st_size, 0)
        snapshot = self.take()
        with closing(sqlite3.connect(snapshot / "db.sqlite")) as restored:
            self.assertEqual(restored.execute("SELECT * FROM nodes").fetchall(), [(1, "xps-fleet")])
            self.assertEqual(restored.execute("PRAGMA journal_mode").fetchone(), ("delete",))
        self.assertEqual((snapshot / "noise_private.key").read_bytes(), (self.source / "noise_private.key").read_bytes())
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(snapshot.stat().st_mode), 0o700)
        for path in snapshot.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        manifest = backup.verify(snapshot)
        self.assertEqual(set(manifest["sha256"]), {"db.sqlite", "noise_private.key", "config.yaml", "policy.hujson"})

    def test_unmounted_disk_refuses_before_creating_any_destination(self):
        with patch.object(backup.os.path, "ismount", return_value=False):
            with self.assertRaisesRegex(ValueError, "not mounted"):
                backup.backup(self.mount, self.destination, self.source, self.config, self.policy)
        self.assertFalse(self.destination.exists())

    def test_destination_outside_mount_is_rejected(self):
        with patch.object(backup.os.path, "ismount", return_value=True):
            with self.assertRaisesRegex(ValueError, "below"):
                backup.backup(self.mount, self.root / "wrong-disk", self.source, self.config, self.policy)

    def test_missing_database_does_not_create_empty_live_database(self):
        self.writer.close()
        (self.source / "db.sqlite").unlink()
        with self.assertRaises(sqlite3.OperationalError):
            self.take()
        self.assertFalse((self.source / "db.sqlite").exists())
        self.assertFalse((self.destination / "current").exists())

    def test_failed_verification_preserves_previous_good_snapshot(self):
        first = self.take()
        with patch.object(backup, "verify", side_effect=ValueError("fixture restore failed")):
            with self.assertRaises(ValueError):
                self.take()
        self.assertEqual((self.destination / "current").resolve(), first)
        self.assertEqual(len(list((self.destination / "snapshots").iterdir())), 1)

    def test_checksum_and_permissions_changes_are_detected(self):
        snapshot = self.take()
        key = snapshot / "noise_private.key"
        key.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "not private"):
            backup.verify(snapshot)
        key.chmod(0o600)
        key.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum"):
            backup.verify(snapshot)

    def test_only_current_and_previous_are_retained(self):
        first = self.take()
        second = self.take()
        third = self.take()
        self.assertFalse(first.exists())
        self.assertEqual((self.destination / "previous").resolve(), second)
        self.assertEqual((self.destination / "current").resolve(), third)
        self.assertEqual(len(list((self.destination / "snapshots").iterdir())), 2)


if __name__ == "__main__":
    unittest.main()
