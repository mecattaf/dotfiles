# Fresh Strix installs and the single SSD move

This supersedes the old preserving-worker install and coordinator rename-only
plan. Tom has now required both Strix hosts to start with fresh NixOS roots,
current kernels and Framework BIOS. The powered-off worker's Windows data is
disposable. Its 500 GB disk may be formatted at the attended preparation step.
The NAS's current 256 GB SSD stays active until all `/nix`/fast service state
has moved successfully to the shared 500 GB primary; it then becomes the
separately gated recording/memory disk.
Neither NAS eMMC nor its 256 GB is an install target in this procedure.

The authorization does not make preparation evidence: no disk write, BIOS
flash, service activation, reboot or shutdown was performed by this change.

The final NAS NFS configuration keeps its services, backups and historical
snapshot subvolumes unexported. Compute receives read-only, root-squashed
model/media views; the coordinator's existing document export keeps Tom's
writes for manual handwriting backups, with root squashed. Apply this final
NAS configuration after the accepted cold backup, before accepting fresh
compute access. Do not re-export or remount the running migration to stage it.
Verify the loaded exports and denied services/backups access at that point;
evaluated configuration alone does not prove the live NFS boundary.

## Order that actually works

1. Independently back up and verify all retained data on LaCie, including the
   entire old coordinator home and occupied secondary 1 TB. Preserve service
   databases, credentials, Git refs/worktrees and old identities for rollback.
   `nas-home-migrate` is a curated migration helper, **not** this full backup.
   The retired five-tree `lacie-mirror` plug trigger is disabled by default
   (`myNas.legacyLacieMirror.enable = false`): it would recreate the previous
   partial/history layout beside the new estate copy. Keep its runtime hold
   on the old NAS generation until LaCie is cleanly unmounted and unplugged.
2. Prove native NAS-local harness/Herdr residence from Zenbook using the
   existing NAS home/256 GB fast tier. Capture final source deltas and native
   histories consistently before retiring old Strix operator sessions.
3. Build/root/copy the final four closures, source, offline worker disko
   script and installer ISO. After its backup, fresh-install worker's future
   1 TB while still the inactive coordinator secondary, using the declared
   offline mount root. Install only its fresh host identity and selected
   verified model loans. Optional portable Tailscale pre-enrollment is
   supervised and must not copy the coordinator's identity.
4. Write the checkpoint, flush/unmount targets, shut down all three devices
   and unplug/open each once. Keep coordinator anchor `25140U804698`; move
   `26051Y809195` to worker; move verified Windows `260538801482` to NAS.
   Connect each Ethernet to BE550 plus the dual compute USB4/TB5 cables.
5. Boot NAS into its previous known working generation first. Its 256 GB
   fast tier/eMMC home still work while the new 500 GB is blank. Prove NAS
   control access, then follow `nas/home-disk-cutover.md` to prepare the
   shared primary pool, copy all fast state and reviewed home, stage/boot
   the final NAS generation, and validate. Keep the old 256 GB untouched until
   that succeeds, then release its dedicated memory-disk gate separately.
6. Boot worker's preinstalled fresh system; read its real BIOS/NIC identity.
   Complete the verified Framework 3.06 update and deliberate reboot if
   needed. Boot coordinator from the installer USB for its fresh install,
   or temporarily boot its old OS solely as SSH transport for a separately
   pinned/reviewed nixos-anywhere kexec installation from NAS. No operator
   agent sessions belong on that temporary compute OS.
7. Fresh-install coordinator's anchor from NAS/installer, installing its fresh host key and preserving only
   its own Tailscale identity. Reboot into the fresh 7.3
   system, finish BIOS/tailnet enrollment as required, then run fleet/model
   acceptance. Keep USB recovery for failed SSH/kexec/firmware paths.

The coordinator cannot be made fresh while executing its old root normally;
its old OS must first yield to an installer (USB or kexec). Multiple OS boots
are compatible with one physical opening and cable/SSD move per device.

## Stable identities and destructive boundary

| Host | Only permitted install disk | Target configuration |
|---|---|---|
| Coordinator | `/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_25140U804698` | `strix-coordinator` |
| Worker, while still a secondary disk | `/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195` | `strix-worker` |
| Incoming NAS home, worker installer bench only | `/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482` after physical verification | Manual NAS home recipe; **never NAS disko** |

Before every destructive command, compare `lsblk` serial/model/capacity,
`findmnt /`, and all target mountpoints with the manifest. Enumeration such as
`nvme0n1` is not an identity. Abort if the expected serial is absent, differs,
is mounted, or backs the running system. Record successful independent backup
and restore-sample receipts before releasing the destructive boundary.

The two Strix disko definitions name exactly their own serial and measured
GPT identities; running disko destroys old contents, even when GUIDs are
reused. Keeping the GUIDs does not preserve the old filesystem.

## Prepare actual installer and closures

Use the reviewed branch/revision, not a live-main assumption. The existing
`nas-installer-iso` package is a generic x86_64 UEFI minimal NixOS installer
with DHCP and the fleet operator public SSH keys. Its historical name does
not make NAS a target; it executes no disk installation automatically.

```sh
# On the build-capable coordinator, before it is retired:
nix build --out-link /safe/rooted/installer .#nas-installer-iso
nix build --out-link /safe/rooted/coordinator .#nixosConfigurations.strix-coordinator.config.system.build.toplevel
nix build --out-link /safe/rooted/worker .#nixosConfigurations.strix-worker.config.system.build.toplevel
nix build --out-link /safe/rooted/nas .#nixosConfigurations.nas.config.system.build.toplevel
```

Record the final paths and copy/root required closures on NAS or offline media
with `nix copy`. Write the ISO to a **separately identified USB stick**. Its
serial is unknown until Tom supplies the stick; never substitute a fleet SSD.
Booting the USB and proving LAN SSH/console is the media acceptance test.
Use a separate FAT32 stick with Framework's verified EFI BIOS update files.

## Fresh install from an installer, using the already-built closure

On the coordinator installer (or on the coordinator for its inactive worker
disk), use the final source and supplied `nixos-install`. Do not run an
unbounded shell fragment from another script. This is the actual write stage,
shown for review and **not executed by this change**:

```sh
# Build/root these scripts before the shutdown; build does not run them.
nix build --out-link /safe/rooted/worker-disko .#strix-worker-disko-offline
nix build --out-link /safe/rooted/coordinator-disko \
  .#nixosConfigurations.strix-coordinator.config.system.build.diskoScript
```

The worker script's root mountpoint is `/mnt/strix-worker-install`, supplied
by the declared offline package; the coordinator script's root is `/mnt`.
Copy both closures to the future executing host, and inspect the generated
scripts' exact target serial and mount root. On the live coordinator only the
**worker** script may run, after checking its backup and inactive disk. The
coordinator script may run only after booting the installer on that actual
machine. Neither script is a preserving operation.

```sh
# Actual write stage, after the serial/backup/foreground-root gates:
sudo "$recorded_disko_script"
# Set this consistently with the selected script:
target_root=/mnt/strix-worker-install  # worker prep; /mnt on coordinator USB
# target_system is the recorded final reviewed host closure, not the live OS.
```

After formatting/mounting, install each host's separately generated fresh
SSH key and only its own Tailscale node state. Keep old SSH keys in the secured
NAS/LaCie recovery archive, never on fresh compute. No operator harness/cloud
credentials, old general user home, old worker identity, caches or generations
are copied onto compute. Tom's latest reversal explicitly retains the existing
coordinator Chrome/browser.internal setup as a narrow exception; preserve and
restore its required browser profile/keyring state separately from the fresh
compute identity. This does not introduce a NAS browser architecture. At the installer:

```sh
sudo install -d -m 0700 "$target_root/etc/ssh"
# Copy the selected host's private/public host-key pair securely here.
sudo nixos-install --root "$target_root" --system "$target_system" \
  --no-channel-copy --no-root-passwd
```

The final configuration grants key-based operator SSH access. Confirm the
installed hostname, key fingerprint, fstab identities, system-profile link,
kernel/initrd boot entries, and `EFI/BOOT/BOOTX64.EFI`. Worker explicitly uses
`canTouchEfiVariables=false`, so preparation cannot change coordinator NVRAM.
For coordinator fresh install, normal EFI registration occurs on its own box.
NAS Nix distributed-build settings are not an instruction to compile these
closures on its 24 GB: closures are built before teardown and copied in.

If `nixos-anywhere` is used instead, pin its source/version and verify its
installed help for `--no-reboot`, `--build-on`, `--extra-files` and
prebuilt-system flags first. Do not invent those options or let it repartition
NAS. The explicit generated disko script plus `nixos-install --system` path
above avoids reliance on an uninstalled remote installer frontend.

## Model preparation and first boot

Gufo stable 0.22 is the single-box engine; the current neuhaus RDMA fork is a
separate pinned package. Four Donnerkeule rails cannot share payload rings
with legacy USB4-IP. Ethernet carries management/build/TCP fallback traffic.
Independent single-box Q4 Gufo starts at boot on both compute hosts; TP2 and
DS4 are attended/manual targets until actual cables and matching model bytes
pass hardware acceptance. No NAS model service is enabled.

Canonical acquisition is exclusively NAS `library-fetch`. New catalog rows
do not download during evaluation/activation/startup. Inspect the complete
capacity plan after the independent backup before acquiring more weights.
Use scoped manifests to borrow only selected models from NAS:

- Boot models: `/etc/local-models/wanted.json`.
- Flash-Next Q8 TP2: `/etc/gufo/tp2-q8-wanted.json`, roughly 179 GiB per host.
- 27B Q8: `/etc/gufo/27b-q8-wanted.json`, roughly 31 GiB per host.
- DS4.1 1017 Q2+vision+DSpark: `/etc/ds4/wanted.json`, roughly 349 GiB per host.
  All three files are kyuz0's matched 1017 set
  (`kyuz0/deepseek-v4.1-flash-gguf` @20408f69, Tom 2026-10-25); ds4 refuses
  an original-release vision encoder beside a 1017 language model.
- Gufo ASR, TTS Base and Qwen-Image (`qwen3-asr-1.7b`,
  `qwen3-tts-12hz-1.7b-base`, `qwen-image-2.1`): in the boot wanted set,
  roughly 42 GB per host.

Set `LOCAL_MODELS_MANIFEST` to the desired scoped manifest and run
`local-models-borrow --dry-run`, review reserve and full target identity, then
`--yes`. Use the target closure's tools/manifests and alternate
`LOCAL_MODELS_ROOT` when staging an offline fresh root. Recheck pre-existing
files' SHA-256 too; the current borrow tool only size-skips existing files.
Do not promise every variant resident at once. MiniMax remains gated on Tom's
personal license acceptance; it is not silently fetched or enabled.

DS4 uses the official kyuz0 ROCm 10 container by immutable digest. Explicitly
pull the pinned image on each compute host during preparation, after capacity
is clear. Startup uses `--pull=never`, read-only local model mounts, no home
mount, no operator credentials and no automatic model acquisition. Its first
TP transport is wired Ethernet TCP. The image does not include Donnerkeule's
custom USB4 userspace provider, and no claim of DS4-over-USB4 RDMA is made.

API: coordinator port 8732, worker peer link 9911; initial unit presence is not
inference readiness. Check actual `/v1/models` and a bounded completion after
starting both attended ranks. Stop both ranks when switching engines. Validate
Gufo Q4/Q8 dual-host correctness, rail counters, and hold-descriptor lifetime
with the real hardware before changing the startup policy.

## Current upstream verification

- [Gufo v0.22.0](https://github.com/gufo-org/gufo/releases/tag/v0.22.0),
  release commit `7b1bf049a0a3600345676fdf0a544152ac7ce6a1`.
- [kyuz0 ds4 ROCm clustering](https://github.com/kyuz0/ds4/blob/abf18415738337da0de0e2b463567711548ea5ec/docs/CLUSTERING_ROCM.md),
  TCP/RoCE V4.1 qualification uses E810 100 GbE, not this USB4 hardware.
- [Official toolbox](https://github.com/kyuz0/strix-halo-ds4-toolbox/blob/a027daab2e6a4bd7b34379ec0eccaa67a7f03248/README.md),
  verified Docker Hub `rocm-10.0` image digest ends `f5f7d1c`, dated Oct 23.
- [Framework Desktop BIOS 3.06](https://resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.06/)
  remains labelled latest stable; verify downloaded EFI SHA-256
  `68c251bf20b98c9d0928ddad51dd920a3b073aa4e1c8be55ff43454b8b38c013`.
- [kernel.org](https://www.kernel.org/) lists 7.3 as latest mainline release;
  the integrated fleet module ABI is 7.3.0. Hardware boot proof is outstanding.

## Pinned remote installer path from NAS

`nixos-anywhere` source `92b94751fc010eab62d07de40972cffa6937cafd`
was fetched and its actual `--help` executed during preparation. The prepared
CLI reports 1.13.0. Its supported `--store-paths` accepts the already-built
disko script and system closure; no NAS compilation is required. `--phases`
can stop after installation, before the final reboot. The exact prepared
invocation below is a future destructive operation, not a test:

```sh
# NAS only, after backup, NAS-local residence and identity/serial gates.
# Both paths must already exist/root in the NAS store and name coordinator.
nix run github:nix-community/nixos-anywhere/92b94751fc010eab62d07de40972cffa6937cafd -- \
  --store-paths "$coordinator_disko" "$coordinator_system" \
  --extra-files "$coordinator_identity_tree" \
  --phases kexec,disko,install \
  --target-host root@10.42.0.2
```

`coordinator_identity_tree` contains only that machine's new host
key and its own preserved Tailscale node state, with private modes. Never include the
old general home/operator harness credentials or another machine's identity.
Restore coordinator browser profile/keyring separately under Tom's explicit
keep-Chrome exception. Inspect resulting
boot/hostname/key/target serial before the deliberate final reboot. A failed
SSH/kexec must fall back to the verified USB installer; do not infer that a
failed connection means no mutation happened.

The inactive worker disk was inspected read-only with `ro,noload`. Its old
system/profile/kernel 7.2.2/initrd/init exist, and root SSH authorizes the
current fleet key and original flasher key. Its old host fingerprint is
`SHA256:TKMZIVdgrL/gEy7BV2co9g00bHJEz0OvUlJW10mFW7A`, distinct from the new
worker key. But its ESP has no detected filesystem: it cannot currently be
promised to boot as a temporary installer transport. Fresh offline worker
pre-install is therefore preferred. If that is not completed, USB boot is a
required fallback, or a separately reviewed bootloader repair is required;
merely moving this occupied SSD is not a boot-ready worker.

## Firmware preparation evidence

Read-only local fwupd discovery confirms coordinator System Firmware is
03.05 and supports the trusted LVFS UEFI-capsule update 3.06. Its firmware GUID
is `eb68dbae-3aef-5077-92ae-9016d1f0c856`; query the actual worker separately.
The advertised cabinet SHA-256 is
`2742d7595114df4276bb11e1ae042ee414a24ac5628a75c6333e75d3b01b1dee`.
Direct download of the cabinet returned HTTP 403 during this pass, so it is
not claimed staged. The official EFI ZIP **was** downloaded and independently
SHA-256 verified, at 21,466,600 bytes, against Framework's published checksum.
No firmware update, reboot or kexec was invoked.

The installed fwupdmgr supports `--no-reboot-check` (do not prompt/check after
update), `local-install FILE DEVICE`, and ordinary `install DEVICE VERSION`.
These perform real staging/flashing; they are not dry-run checks. Query
`get-devices`, `get-releases` and `check-reboot-needed` as read-only preparation.
Do not stage a capsule onto an ESP that will then be erased before its firmware
reboot. Flash/validate before the fresh disk install, or after first fresh boot,
with AC power maintained and a recovery console/EFI stick present.
