#!/usr/bin/env python3
"""Inspect a PS4 USB image and plan, or explicitly perform, a verified USB write.

The image contains only external PS4BOOT + ps4-nixos partitions. This tool
never creates an internal-disk installation or edits an Orbis partition.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys


CHUNK = 4 * 1024 * 1024


def digest(fd, length):
    result = hashlib.sha256()
    offset = 0
    while offset < length:
        data = os.pread(fd, min(CHUNK, length - offset), offset)
        if not data:
            raise ValueError("Unexpected end of file during checksum verification")
        result.update(data)
        offset += len(data)
    return result.hexdigest()


def inspect_image(fd):
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        raise ValueError("Image must be an uncompressed regular .img file")
    header = os.pread(fd, 512, 0)
    if len(header) != 512 or header[510:512] != b"\x55\xaa":
        raise ValueError("Image has no DOS/MBR partition-table signature")
    parts = []
    for index in range(4):
        entry = header[446 + index * 16:462 + index * 16]
        kind, start, sectors = entry[4], *struct.unpack_from("<II", entry, 8)
        if kind:
            parts.append({"number": index + 1, "type": kind,
                          "start": start * 512, "bytes": sectors * 512})
        elif start or sectors:
            raise ValueError("Unused MBR entry has unexpected extents")
    if len(parts) != 2 or [p["number"] for p in parts] != [1, 2]:
        raise ValueError("Expected exactly two primary USB partitions")
    boot, root = parts
    if boot["type"] not in (0x0B, 0x0C) or root["type"] != 0x83:
        raise ValueError("Expected FAT32 boot partition followed by Linux root")
    if (boot["start"] < 1024 * 1024 or boot["bytes"] < 32 * 1024 * 1024
            or root["start"] < boot["start"] + boot["bytes"]
            or root["bytes"] < 128 * 1024 * 1024
            or root["start"] + root["bytes"] != info.st_size):
        raise ValueError("Invalid, overlapping, truncated or unexpected image extents")
    fat = os.pread(fd, 512, boot["start"])
    if (fat[71:82].rstrip(b" ") != b"PS4BOOT"
            or fat[82:90] != b"FAT32   " or fat[510:512] != b"\x55\xaa"):
        raise ValueError("Boot partition is not the expected PS4BOOT FAT32 volume")
    btrfs = os.pread(fd, 4096, root["start"] + 65536)
    if (btrfs[64:72] != b"_BHRfS_M"
            or btrfs[299:555].split(b"\0", 1)[0] != b"ps4-nixos"):
        raise ValueError("Root partition is not the expected ps4-nixos Btrfs volume")
    return {"bytes": info.st_size, "sha256": digest(fd, info.st_size),
            "partitions": parts, "labels": ["PS4BOOT", "ps4-nixos"]}


def descendants(node):
    yield node
    for child in node.get("children", []):
        yield from descendants(child)


def validate_disk(node, expected_serial, expected_bytes, image_bytes):
    if node.get("type") != "disk" or node.get("tran") != "usb":
        raise ValueError("Target must be one whole external USB disk")
    if node.get("log-sec") != 512:
        raise ValueError("The PS4 USB image requires a 512-byte logical-sector target")
    if not expected_serial or str(node.get("serial", "")).strip() != expected_serial:
        raise ValueError("USB serial does not match the explicitly expected serial")
    if node.get("size") is None or int(node["size"]) != expected_bytes:
        raise ValueError("USB capacity differs from the explicitly expected byte count")
    if expected_bytes < image_bytes:
        raise ValueError("USB drive is smaller than the complete image")
    for item in descendants(node):
        if item.get("ro"):
            raise ValueError("Target disk or child device is read-only")
        if any(item.get("mountpoints") or []):
            raise ValueError("Target disk or child is mounted or used as swap")
        if not re.fullmatch(r"\d+:\d+", item.get("maj:min") or ""):
            raise ValueError("Missing device identity in lsblk result")


def disk_record(device, expected_serial, expected_bytes, image_bytes):
    # A stable by-id name and a separate serial/size check avoid /dev/sdX guesses.
    if (device.parent != Path("/dev/disk/by-id")
            or not device.name.startswith("usb-") or "-part" in device.name):
        raise ValueError("Use the complete /dev/disk/by-id/usb-... whole-disk name")
    resolved = device.resolve(strict=True)
    if not stat.S_ISBLK(resolved.stat().st_mode):
        raise ValueError("Selected USB path is not a block device")
    record = json.loads(subprocess.check_output(
        ["lsblk", "--bytes", "--json", "--paths", "--output",
         "PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,RO,MOUNTPOINTS,MAJ:MIN,LOG-SEC", str(resolved)],
        text=True))
    if len(record.get("blockdevices", [])) != 1:
        raise ValueError("Expected one unambiguous USB disk")
    node = record["blockdevices"][0]
    validate_disk(node, expected_serial, expected_bytes, image_bytes)
    if node["path"] != str(resolved):
        raise ValueError("lsblk returned a different device path")
    for item in descendants(node):
        sys_device = Path("/sys/dev/block") / item["maj:min"]
        holders = sys_device / "holders"
        if not holders.is_dir() or any(holders.iterdir()):
            raise ValueError("USB disk or child has active holders or missing sysfs identity")
    return resolved, node


def write_image(image_fd, target_fd, length):
    """Bounded copy; descriptors and write authorization belong to the caller."""
    offset = 0
    while offset < length:
        data = os.pread(image_fd, min(CHUNK, length - offset), offset)
        if not data:
            raise ValueError("Image changed or ended during write")
        done = 0
        while done < len(data):
            count = os.pwrite(target_fd, data[done:], offset + done)
            if count <= 0:
                raise OSError("USB write made no progress")
            done += count
        offset += len(data)
    os.fsync(target_fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--device", type=Path)
    parser.add_argument("--expect-serial")
    parser.add_argument("--expect-size-bytes", type=int)
    parser.add_argument("--write", action="store_true",
                        help="Erase this external USB disk only, then verify every image byte")
    parser.add_argument("--confirm-erase", help="Repeat the exact expected USB serial")
    args = parser.parse_args(argv)
    if args.write and (not args.device or args.confirm_erase != args.expect_serial
                       or not args.expect_serial):
        parser.error("--write requires --device, --expect-serial and matching --confirm-erase")
    if args.device and (not args.expect_serial or not args.expect_size_bytes):
        parser.error("A USB target requires its explicit serial and exact size in bytes")
    if args.confirm_erase and not args.write:
        parser.error("--confirm-erase is valid only together with --write")
    try:
        image = args.image.resolve(strict=True)
        image_fd = os.open(image, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            manifest = {"action": "write" if args.write else "plan",
                        "image": str(image), **inspect_image(image_fd),
                        "internal_orbis": "untouched", "grow_on_boot": False}
            if not args.device:
                print(json.dumps(manifest, indent=2))
                return 0
            resolved, node = disk_record(args.device, args.expect_serial,
                                         args.expect_size_bytes, manifest["bytes"])
            manifest["usb"] = {key: node[key] for key in
                               ("path", "model", "serial", "size", "maj:min")}
            manifest["usb"]["by_id"] = str(args.device)
            if args.write:
                if os.geteuid() != 0:
                    raise ValueError("The explicit write requires root; planning does not")
                # Recheck identity immediately before exclusive block-device open.
                resolved2, node2 = disk_record(args.device, args.expect_serial,
                                               args.expect_size_bytes, manifest["bytes"])
                if resolved != resolved2 or node != node2:
                    raise ValueError("USB topology changed after the plan")
                target_fd = os.open(resolved, os.O_RDWR | os.O_EXCL | os.O_NOFOLLOW)
                try:
                    fcntl.flock(target_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    observed = os.fstat(target_fd)
                    if (not stat.S_ISBLK(observed.st_mode)
                            or f"{os.major(observed.st_rdev)}:{os.minor(observed.st_rdev)}" != node["maj:min"]):
                        raise ValueError("Opened target identity differs from the checked USB disk")
                    resolved3, node3 = disk_record(args.device, args.expect_serial,
                                                   args.expect_size_bytes, manifest["bytes"])
                    if resolved3 != resolved or node3 != node:
                        raise ValueError("USB identity changed before the exclusive write")
                    print("Writing the explicitly selected USB; keep it connected until verified.",
                          file=sys.stderr, flush=True)
                    write_image(image_fd, target_fd, manifest["bytes"])
                    readback = digest(target_fd, manifest["bytes"])
                    if readback != manifest["sha256"]:
                        raise ValueError("USB readback SHA256 differs from image; do not boot it")
                    manifest["readback_sha256"] = readback
                    manifest["verified"] = True
                finally:
                    os.close(target_fd)
            print(json.dumps(manifest, indent=2))
            return 0
        finally:
            os.close(image_fd)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"PS4 USB operation refused or incomplete: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
