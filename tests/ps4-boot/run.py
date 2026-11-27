#!/usr/bin/env python3
"""Bounded, network-free generic-PC test of the PS4 USB root/stage-2 contract.

Run only on Strix through runtime-test --allow-kvm. All disks are regular
files; writes go to a new qcow2 overlay. This never emulates the PS4 GPU,
executes the Orbis payload, supplies Sony firmware, or proves PS4 hardware.
"""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import time


def entry(name, content=b"", mode=stat.S_IFREG | 0o644, inode=1):
    encoded = name.encode() + b"\0"
    fields = (inode, mode, 0, 0, 1, 0, len(content), 0, 0, 0, 0, len(encoded), 0)
    header = b"070701" + b"".join(f"{field:08x}".encode() for field in fields)
    result = header + encoded
    result += b"\0" * (-len(result) % 4)
    result += content
    return result + b"\0" * (-len(result) % 4)


def synthetic_overlay(proof):
    result = b""
    for index, name in enumerate(("lib", "lib/firmware", "lib/firmware/amdgpu"), 1):
        result += entry(name, mode=stat.S_IFDIR | 0o755, inode=index)
    result += entry("lib/firmware/amdgpu/ps4-vm-proof", proof,
                    mode=stat.S_IFREG | 0o755, inode=4)
    result += entry("TRAILER!!!", inode=0)
    return gzip.compress(result, mtime=0)


def regular_file(path):
    result = path.resolve(strict=True)
    if not stat.S_ISREG(result.stat().st_mode):
        raise ValueError(f"A regular file is required, never a real disk: {path}")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qemu", type=Path, required=True)
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--initramfs", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--expected-release", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args(argv)
    if not 10 <= args.timeout <= 180:
        parser.error("Timeout must be between 10 and 180 seconds")
    try:
        qemu = regular_file(args.qemu)
        qemu_img = regular_file(qemu.parent / "qemu-img")
        kernel, initramfs, image = map(regular_file, (args.kernel, args.initramfs, args.image))
        output = args.output_dir.absolute()
        if "," in str(output):
            raise ValueError("Output path must not contain QEMU drive-option separators")
        output.mkdir(mode=0o700, parents=False, exist_ok=False)
        base_identity = (image.stat().st_size, image.stat().st_mtime_ns)
        overlay = output / "usb-root.qcow2"
        subprocess.run([str(qemu_img), "create", "-f", "qcow2", "-F", "raw",
                        "-b", str(image), str(overlay)], check=True, capture_output=True)
        proof = (Path(__file__).parent / "proof.sh").read_bytes()
        appended = output / "SYNTHETIC-test-initramfs.cpio.gz"
        appended.write_bytes(initramfs.read_bytes() + synthetic_overlay(proof))
        command_line = " ".join([
            "root=LABEL=ps4-nixos rootfstype=btrfs rootwait rw",
            "console=ttyS0,115200n8 panic=1 libata.force=disable",
            "systemd.run=/run/ps4-firmware/amdgpu/ps4-vm-proof",
            # NixOS has an explicit /etc/default.target; select the generated
            # proof target rather than relying on its lower-priority symlink.
            "systemd.unit=kernel-command-line.target",
            "systemd.run_success_action=poweroff systemd.run_failure_action=poweroff",
            "systemd.show_status=1",
        ])
        command = [str(qemu), "-machine", "q35,accel=kvm", "-cpu", "host,-avx2,-avx512f",
                   "-m", "2048", "-smp", "2", "-nodefaults", "-nic", "none",
                   "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot",
                   "-kernel", str(kernel), "-initrd", str(appended), "-append", command_line,
                   "-device", "qemu-xhci,id=ps4test-usb",
                   "-drive", f"file={overlay},format=qcow2,if=none,id=usbroot",
                   "-device", "usb-storage,bus=ps4test-usb.0,drive=usbroot,removable=true"]
        print("SYNTHETIC generic-PC root-contract test; no PS4 GPU, firmware or payload.", flush=True)
        started = time.monotonic()
        timed_out = False
        log_limit_hit = False
        with (output / "serial.log").open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                       stdin=subprocess.DEVNULL, start_new_session=True)
            while process.poll() is None:
                timed_out = time.monotonic() - started >= args.timeout
                log_limit_hit = log.tell() >= 32 * 1024 * 1024
                if timed_out or log_limit_hit:
                    break
                time.sleep(0.1)
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        serial = (output / "serial.log").read_text(errors="replace")
        passed = (not timed_out and not log_limit_hit and process.returncode == 0
                  and "PS4_VM_ROOT_CONTRACT_PASS" in serial
                  and "PS4_VM_FLEET_STARTUP_PASS" in serial
                  and f"PS4_VM_RELEASE={args.expected_release}" in serial
                  and base_identity == (image.stat().st_size, image.stat().st_mtime_ns))
        receipt = {
            "scope": "SYNTHETIC generic-PC USB-root/stage-2/ownership/Nix-DB/fleet-startup only",
            "ps4_hardware_qualified": False, "passed": passed,
            "qemu": str(qemu), "kernel": str(kernel), "initramfs": str(initramfs),
            "image": str(image), "image_bytes": base_identity[0],
            "kernel_sha256": hashlib.sha256(kernel.read_bytes()).hexdigest(),
            "initramfs_sha256": hashlib.sha256(initramfs.read_bytes()).hexdigest(),
            "proof_sha256": hashlib.sha256(proof).hexdigest(),
            "command": command, "returncode": process.returncode, "timed_out": timed_out,
            "log_limit_hit": log_limit_hit,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "serial_log": str(output / "serial.log"), "overlay": str(overlay),
        }
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, indent=2))
        return 0 if passed else 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Disposable VM test stopped: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
