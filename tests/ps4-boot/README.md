# Disposable USB root-contract VM

This is a bounded **generic-PC test**, not a PS4 emulator. It can exercise the
actual candidate kernel, unchanged external initramfs logic, labelled USB
root, real `/sbin/init`, NixOS stage 2, root ownership and Nix DB registration.
The CPU hides AVX2/AVX512F. It proves no Liverpool dispatch, GPU allocation,
Ethernet southbridge support, Orbis payload execution or physical recovery.

The PS4 config has built-in generic XHCI, USB storage, Btrfs and 8250 serial.
Its PS4 early-platform setup is selected by the PS4 boot subarchitecture;
building `CONFIG_X86_PS4` alone does not require that path on a PC guest.
Virtio is absent, so this test uses `qemu-xhci` and `usb-storage`.

The real initramfs requires firmware that the Orbis loader normally appends.
The test appends a **synthetic** `lib/firmware/amdgpu/ps4-vm-proof` script in
a separate cpio member. There are no Sony firmware bytes or console keys.
The unchanged initramfs copies this directory into `/run/ps4-firmware`, and
systemd's `systemd.run=` facility executes the proof after normal stage 2.
It powers off the disposable guest after success or failure.

Run on Strix, only after the actual image exists:

```sh
fleet-exec strix-coordinator --cwd /tmp/ps4-dummy-build -- \
  /home/tom/.local/bin/runtime-test --allow-kvm -- \
  python3 tests/ps4-boot/run.py \
  --qemu /nix/store/QEMU/bin/qemu-system-x86_64 \
  --kernel /nix/store/KERNEL/bzImage \
  --initramfs /nix/store/INITRAMFS/initramfs.cpio.gz \
  --image /nix/store/USBIMAGE/sd-image/ps4-dummy-nixos.img \
  --expected-release EXACT_KERNEL_RELEASE \
  --output-dir /tmp/ps4-dummy-vm-unique --timeout 120
```

All paths must be regular files. Writes go only to a newly created qcow2
overlay in a fresh private output directory. There is no networking, host
filesystem sharing, display server or persistent service. The pristine image
is the read-only backing file. The runner retains a bounded serial log and
receipt; a timeout or 32 MiB serial-log limit terminates only its own disposable
process group.

The script-format check, `python3 tests/ps4-boot/test_overlay.py`, starts no VM.
An existing suitable QEMU binary on Strix can be used directly; QEMU is not a
production PS4 package dependency.

[QEMU USB emulation](https://www.qemu.org/docs/master/system/devices/usb.html),
[systemd-run-generator](https://www.freedesktop.org/software/systemd/man/latest/systemd-run-generator.html),
[psX platform policy source](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/platforms/ps4/patches/7.2-ps4-baikal/0100-x86-platform/0001-ps4-default-platform-boot-policy.patch).

## Unknowns and proposed defaults

- A source-compatible VM path is not a completed boot. Default: inspect the
  actual receipt and pass marker, and retain boot failures without masking them.
- Synthetic firmware presence only permits the generic-PC root test to reach
  stage 2. Default: never deploy the appended test initramfs to a PS4.
