"""Offline installer guards; never open a real disk, mount, or launch a service."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(os.environ.get("PS4_USB_SOURCE", Path(__file__).resolve().parents[2]
                             / "pkgs/ps4-installer/ps4_usb.py"))
SPEC = importlib.util.spec_from_file_location("ps4_usb", SOURCE)
USB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(USB)
MIB = 1024 * 1024


def node():
    return {"type": "disk", "tran": "usb", "serial": "USB-SERIAL-1",
            "size": 32 * 1024 * MIB, "ro": False, "mountpoints": [None],
            "maj:min": "8:16", "log-sec": 512, "path": "/dev/sdb", "model": "Fixture",
            "children": [{"type": "part", "ro": False, "mountpoints": [None],
                          "maj:min": "8:17", "path": "/dev/sdb1"}]}


class DiskGuards(unittest.TestCase):
    def validate(self, value, size=32 * 1024 * MIB, image_size=1024 * MIB):
        USB.validate_disk(value, "USB-SERIAL-1", size, image_size)

    def test_idle_whole_usb_accepted(self):
        self.validate(node())

    def test_internal_partition_and_other_transports_refused(self):
        for key, value in (("type", "part"), ("tran", "sata"),
                           ("tran", "nvme"), ("tran", None)):
            record = node()
            record[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.validate(record)

    def test_serial_and_capacity_must_match(self):
        for key, value in (("serial", "OTHER"), ("serial", ""), ("size", 1)):
            record = node()
            record[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.validate(record)
        with self.assertRaises(ValueError):
            self.validate(node(), image_size=64 * 1024 * MIB)

    def test_incompatible_logical_sector_size_refused(self):
        for size in (4096, None):
            record = node()
            record["log-sec"] = size
            with self.subTest(size=size), self.assertRaises(ValueError):
                self.validate(record)

    def test_mounted_root_child_swap_and_readonly_refused(self):
        for child in (False, True):
            for key, value in (("mountpoints", ["/"]), ("mountpoints", ["[SWAP]"]),
                               ("ro", True), ("maj:min", None)):
                record = node()
                selected = record["children"][0] if child else record
                selected[key] = value
                with self.subTest(child=child, key=key), self.assertRaises(ValueError):
                    self.validate(record)

    def test_unstable_names_refused_before_any_disk_query(self):
        for name in ("/dev/sdb", "/dev/disk/by-id/ata-internal",
                     "/dev/disk/by-id/usb-fixture-part1"):
            with self.subTest(name=name), patch.object(USB.subprocess, "check_output") as query:
                with self.assertRaises(ValueError):
                    USB.disk_record(Path(name), "USB-SERIAL-1", 100, 1)
                query.assert_not_called()


class ImageGuards(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ps4-usb-fixture-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "fixture.img"
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
        self.addCleanup(os.close, self.fd)
        self.boot_start, self.boot_size, self.root_size = 8 * MIB, 32 * MIB, 128 * MIB
        self.root_start = self.boot_start + self.boot_size
        os.ftruncate(self.fd, self.root_start + self.root_size)
        self.header = bytearray(512)
        self.header[510:512] = b"\x55\xaa"
        self.partition(0, 0x0B, self.boot_start, self.boot_size)
        self.partition(1, 0x83, self.root_start, self.root_size)
        self.fat = bytearray(512)
        self.fat[71:82] = b"PS4BOOT    "
        self.fat[82:90] = b"FAT32   "
        self.fat[510:512] = b"\x55\xaa"
        self.btrfs = bytearray(4096)
        self.btrfs[64:72] = b"_BHRfS_M"
        self.btrfs[299:308] = b"ps4-nixos"
        self.save()

    def partition(self, number, kind, start, size):
        position = 446 + number * 16
        self.header[position + 4] = kind
        struct.pack_into("<II", self.header, position + 8, start // 512, size // 512)

    def save(self):
        os.pwrite(self.fd, self.header, 0)
        os.pwrite(self.fd, self.fat, self.boot_start)
        os.pwrite(self.fd, self.btrfs, self.root_start + 65536)

    def inspect(self):
        # Structure tests use sparse files; digest semantics have separate tests.
        with patch.object(USB, "digest", return_value="fixture-sha256"):
            return USB.inspect_image(self.fd)

    def test_expected_layout(self):
        result = self.inspect()
        self.assertEqual(result["labels"], ["PS4BOOT", "ps4-nixos"])
        self.assertEqual(result["partitions"][1]["start"], self.root_start)

    def test_extra_partition_refused(self):
        self.partition(2, 0x83, 1, 1)
        self.save()
        with self.assertRaises(ValueError):
            self.inspect()

    def test_overlapping_partitions_refused(self):
        self.partition(1, 0x83, self.boot_start, self.root_size)
        self.save()
        with self.assertRaises(ValueError):
            self.inspect()

    def test_wrong_boot_label_and_wrong_root_label_refused(self):
        self.fat[71:82] = b"OTHER      "
        self.save()
        with self.assertRaises(ValueError):
            self.inspect()
        self.fat[71:82] = b"PS4BOOT    "
        self.btrfs[299:308] = b"orbis-root"
        self.save()
        with self.assertRaises(ValueError):
            self.inspect()

    def test_truncated_and_appended_images_refused(self):
        for offset in (-512, 512):
            os.ftruncate(self.fd, self.root_start + self.root_size + offset)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.inspect()

    def test_default_action_only_reads_image(self):
        with patch.object(USB, "inspect_image", return_value={"bytes": 5, "sha256": "abc"}), \
                patch.object(USB, "disk_record") as disk, \
                patch.object(USB, "write_image") as write, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(USB.main(["--image", str(self.path)]), 0)
            self.assertIn('"action": "plan"', output.getvalue())
            disk.assert_not_called()
            write.assert_not_called()

    def command(self, *extra):
        return ["--image", str(self.path), "--device", "/dev/disk/by-id/usb-fixture",
                "--expect-serial", "USB-SERIAL-1", "--expect-size-bytes",
                str(32 * 1024 * MIB), *extra]

    def test_target_plan_never_opens_target(self):
        real_open = os.open
        with patch.object(USB, "inspect_image", return_value={"bytes": 5, "sha256": "abc"}), \
                patch.object(USB, "disk_record", return_value=(Path("/dev/sdb"), node())), \
                patch.object(USB.os, "open", wraps=real_open) as opened, \
                patch.object(USB, "write_image") as write, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(USB.main(self.command()), 0)
            self.assertEqual(opened.call_count, 1)
            self.assertEqual(opened.call_args.args[0], self.path)
            write.assert_not_called()

    def test_changed_topology_refused_before_target_open(self):
        real_open = os.open
        with patch.object(USB, "inspect_image", return_value={"bytes": 5, "sha256": "abc"}), \
                patch.object(USB, "disk_record", side_effect=[(Path("/dev/sdb"), node()),
                                                              (Path("/dev/sdc"), node())]), \
                patch.object(USB.os, "geteuid", return_value=0), \
                patch.object(USB.os, "open", wraps=real_open) as opened, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as failure:
                USB.main(self.command("--write", "--confirm-erase", "USB-SERIAL-1"))
            self.assertEqual(failure.exception.code, 1)
            self.assertEqual(opened.call_count, 1)

    def test_regular_file_cannot_substitute_for_write_target(self):
        target = Path(self.directory.name) / "must-remain-unchanged"
        target.write_bytes(b"preserve-this-file")
        with patch.object(USB, "inspect_image", return_value={"bytes": 5, "sha256": "abc"}), \
                patch.object(USB, "disk_record", return_value=(target, node())), \
                patch.object(USB.os, "geteuid", return_value=0), \
                patch.object(USB, "write_image") as write, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as failure:
                USB.main(self.command("--write", "--confirm-erase", "USB-SERIAL-1"))
            self.assertEqual(failure.exception.code, 1)
            write.assert_not_called()
        self.assertEqual(target.read_bytes(), b"preserve-this-file")


class CopyAndCli(unittest.TestCase):
    def test_partial_write_handled_and_readback_matches(self):
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as destination:
            content = b"unchanged-model-file\x00" * 100
            source.write(content)
            source.flush()
            real_write = os.pwrite
            with patch.object(USB.os, "pwrite", side_effect=lambda fd, data, offset:
                              real_write(fd, data[:13], offset)):
                USB.write_image(source.fileno(), destination.fileno(), len(content))
            self.assertEqual(USB.digest(source.fileno(), len(content)),
                             USB.digest(destination.fileno(), len(content)))
            with self.assertRaises(ValueError):
                USB.digest(destination.fileno(), len(content) + 1)

    def test_write_refused_without_exact_explicit_confirmation(self):
        for args in (["--image", "absent", "--write"],
                     ["--image", "absent", "--device", "/dev/sdb", "--write",
                      "--expect-serial", "one", "--confirm-erase", "two"],
                     ["--image", "absent", "--confirm-erase", "one"]):
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as failure:
                    USB.main(args)
                self.assertEqual(failure.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
