# Prepared PS4 images and validation

The production images below were built on `strix-coordinator` from pushed
commit `b5305c8d4dc7d979da45b126aa8945d9c29fbe85`. Later verification changes
fix only the VM CPU mask and record these results; the tested operating-system
artifacts remain bound to that production commit. Full paths, exact byte
lengths and complete hashes are in [the image manifest](ps4-dummy-images.json).

| Prepared image | Purpose | Uncompressed size | Media requirement | Corrected VM test |
| --- | --- | ---: | --- | ---: |
| `ps4-dummy-usb-image` | Headless Baikal-derived candidate | 9,920,577,536 bytes | Nominal 16 GB or larger | Pass, 19.485 s |
| `ps4-dummy-fleet-usb-image` | Same kernel with optional Kitty/Domicile and manual Herdr core | 16,488,857,600 bytes | Nominal 32 GB or larger | Pass, 19.829 s |
| `ps4-dummy-universal-usb-image` | Separate Aeolia/Belize/Baikal source candidate | 9,920,577,536 bytes | Nominal 16 GB or larger | Pass, 19.328 s |

The exact drive capacity must exceed its selected image. In particular, the
fleet image exceeds a retail 16 GB drive. Its applications are available on
disk; no compositor or model starts at boot. Each image has the same external
512 MiB FAT32 `PS4BOOT` plus Btrfs `ps4-nixos` structure. The internal PS4 disk
is not an installation target.

Use [the installation procedure](ps4-dummy-install.md) after identifying the
real console and selected USB in the final attended UI/hardware pass. The
names `Baikal` and `universal` select source bundles; they are not declarations
that untested physical consoles are supported. ELF/BIN payload selection and
a privileged, firmware-compatible entrance remain pre-Linux prerequisites.

## What actually passed

All three immutable images passed read-only structure/full-hash inspection
before and after the tests. Tests wrote only disposable qcow2 overlays, with
no NIC, display server or shared host filesystem. The candidate PS4 kernel
booted a generic PC guest through emulated USB XHCI/storage, the production
initramfs and its actual `/sbin/init` bridge. A separately labelled synthetic
cpio member supplied the proof script instead of Sony firmware. No production
image or payload contains that fixture.

The corrected tests hide AVX2 and all AVX-512 features. Each verified:

- Root and immutable imported system files are owned by UID 0.
- NixOS stage 2, PID 1 systemd, Nix database registration and closure queries.
- Running kernel release matches the selected generation's module directory.
- SSH, NetworkManager, nftables, Tailscale and Home Manager start successfully.
- Real `nixos-fw` rules exist; fresh SSH keys and distinct machine IDs are generated.
- Tailscale is unenrolled (`NeedsLogin`), with no transplanted state or credential.
- The shipped isolation wrapper works as unprivileged `tom`.
- No failed systemd units, CPU dependency warnings, missing descriptor links,
  Btrfs ACL errors or unsupported cgroup IP-filter warnings remain.

An earlier disposable run exposed the missing `/dev/fd` links and Btrfs ACL
support, and another exposed the kernel capabilities needed by existing
systemd IP filters/accounting. Those were fixed in the v3 candidate kernel
and initramfs. Both kernel profiles build, with all 41 requested settings
asserted; both boot-bundle checksum manifests, module identities and complete
ELF/BIN loader pairs were inspected.

The focused fleet checks build successfully: PS4 host/installer, fleet
connectivity, transport, roles, topology, Herdr core and deadnix. Full flake
output evaluation passes. The runtime isolation regression suite passes all
30 tests; the USB writer has 17 offline safety tests and host admission has
eight fixtures. Mesa compiles with its four pinned PS4 patches and passes all
43 CPU tests. The memory probe's nine no-device guards run as an install check.
Its approved Strix query and one-MiB touch/map/cleanup smoke also pass; see
[the separate capacity procedure](ps4-memory-qualification.md).

The exact VM runner and proof source hashes are recorded in the image
manifest. No physical USB was selected or written, no Orbis UI was operated,
and no running fleet generation or session was changed by preparation.

## What remains for the console

A generic-PC guest does not execute the Orbis loader or emulate Liverpool,
the PS4 southbridge, Ethernet, power, fans or GPU memory. The actual CUH,
southbridge, firmware, existing payload entrance and USB identity must be
recorded before choosing a boot set. Physical PS4 boot, SSH/Ethernet duration,
Orbis recovery and the seven-GiB user-buffer test remain separate evidence.
Bonsai and the model-plugin runtime have not been installed or benchmarked.

The configured 7424 MiB total backing ceiling leaves a 256 MiB accounting
margin above a 7168 MiB user-buffer qualification target. It reserves no RAM.
The probe requires actual free headroom and reports GPU VA mapping, CPU
touching and residency separately; it cannot qualify GPU reads, coherence,
bandwidth or inference.

The generic guests retain nonfatal diagnostics for absent wireless
regulatory data, optional BPF-LSM filesystem hooks, CEC debugfs, and busy
oldroot detachment followed by successful power-off. The universal guest also
has no PS4 LED/fan controller. These observations are retained in the logs;
no wireless, desktop-rendering or physical power/fan acceptance is implied.
The prepared hashes identify these exact stored artifacts. An independent
bit-for-bit rebuild of filesystem images has not been qualified.

## Unknowns and proposed defaults

- Hardware and USB facts remain deliberately unknown until the final pass.
  Default: select the matching prepared bundle after collecting them.
- The initial Linux root is external; internal Orbis is preserved. Default:
  qualify the external boot/recovery path before investigating internal images.
- The optional suite consumes storage until launched. Default: inference stays
  headless, with model bytes outside Nix and no further Bonsai/cache quantization.
