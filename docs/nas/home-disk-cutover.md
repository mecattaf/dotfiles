# NAS primary pool and dedicated 256 GB memory disk

The final target is one 500 GB btrfs pool with `@home`, `@fast` and
`@snapshots`. These subvolumes share capacity instead of trapping spare space
in the earlier 176 GiB fast / 289 GiB home split. Measured whole home around
264 GiB plus current fast state around 90 GiB fits the approximately 466 GiB
raw pool with about 112 GiB before filesystem overhead and growth. Confirm
actual sizes and reserve before writing; the full independent backup remains
on LaCie, not in this pool.

The NAS's eMMC root and boot partition stay unchanged. `/mnt/fast/nix` remains
the source of the `/nix` bind mount; the entire previous `/mnt/fast` tree moves
to new `@fast`, preserving its paths and service data. The 256 GB SSD remains
intact and available for rollback until the new primary has booted and passed
acceptance. It then becomes the dedicated Screenpipe/CUA recording, memory
and log disk, **not** a backup or snapshot target. No recording application is
implemented or activated by this change.

## Physical checkpoint and initial NAS return

NAS-local Herdr/harness residence can first be proved on the current home
with its existing 256 GB fast tier. The worker is powered off and its Windows
contents are explicitly disposable. Thus the one physical SSD move need not
wait for a Windows network connection or pre-partitioning on the worker.

Before the physical checkpoint, independently back up and verify all retained
source data, stage recovery media and exact closures, preserve identities and
write the handoff. After the move, boot the NAS's **previous working
generation first**, with its current 256 GB `/mnt/fast` and eMMC home intact.
Verify its independent native agent access before preparing the new 500 GB.
The bare presence of a blank 500 GB SSD does not authorize a final generation
that expects its new pool to exist.

## Identity-bound manual preparation

Only incoming whole disk
`/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482` is formatted here.
Verify its physical serial, model and capacity after insertion. If it differs,
change `myNas.homeDisk.device` and `.serial` together before building/staging.
Never run NAS disko: it also describes eMMC and the old fast SSD.

The following writes were not executed by this change. They are the attended
recipe after the independent-backup and target-identity gates:

```sh
disk=/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "$disk"
findmnt / /nix /mnt/fast
# Confirm this disk is neither mounted nor the current root/fast device.
sgdisk --zap-all "$disk"
sgdisk -n1:0:0 -t1:8300 -c1:disk-primary "$disk"
udevadm settle
mkfs.btrfs -L nasprimary "$disk-part1"
install -d -m 0700 /mnt/nas-primary-prep /mnt/newhome /mnt/newfast
mount -t btrfs -o subvolid=5,compress=zstd:1,noatime "$disk-part1" /mnt/nas-primary-prep
btrfs subvolume create /mnt/nas-primary-prep/@home
btrfs subvolume create /mnt/nas-primary-prep/@fast
btrfs subvolume create /mnt/nas-primary-prep/@snapshots
chmod 0755 /mnt/nas-primary-prep/@home /mnt/nas-primary-prep/@fast
chmod 0700 /mnt/nas-primary-prep/@snapshots
umount /mnt/nas-primary-prep
mount -t btrfs -o subvol=@home,compress=zstd:1,noatime "$disk-part1" /mnt/newhome
mount -t btrfs -o subvol=@fast,compress=zstd:1,noatime "$disk-part1" /mnt/newfast
install -d -m 0700 -o 1000 -g 100 /mnt/newhome/tom
```

## Copies are separate from the full backup

Build/copy the reviewed `nas-home-migrate` helper. It never partitions,
formats, mounts, deletes files or controls services; its default is dry-run.
The new shared-pool helper verifies serial, p1 label `disk-primary`, filesystem
label `nasprimary`, actual mounted device and exact `@home` or `@fast`.
`legacy-split` remains an explicit compatibility option, not the final target.

```sh
# Dry-run against the assembled, reviewed NAS home source:
nas-home-migrate home --source /home/tom/ --target /mnt/newhome --final
# Dry-run against all current NAS fast state:
nas-home-migrate fast --source /mnt/fast/ --target /mnt/newfast --final
```

`home` copies into `@home/tom/` with the documented home curation exclusions.
`fast` copies into `@fast/` with **no home exclusions**: Nix store/database,
Attic state/signing material, PostgreSQL, Immich generated files, Navidrome,
remote journals and every other fast-tier file remain included. Parent-side
reviewed native history/DB exports and assembled credential state must remain
intact; do not overwrite those with a later raw coordinator corpus copy.
The curated helper is never a substitute for the full LaCie backup.

After reviewing each plan, add `--apply` for its initial copy. Before the final
fast delta, identify/quiesce **every writer to `/mnt/fast`**, including Nix
builds/daemon/socket, Attic, PostgreSQL, Navidrome, Immich services and remote
journal writing as applicable. A dump or a live rsync alone is not a
consistent filesystem database transfer. Keep the NAS router, SSH and native
agent connection available; do not restart Herdr or the user manager.

Stage the new NAS boot closure **before** the last quiescent fast copy, so
that the exact new `/nix/store` closure and Nix profiles/database are present
on the destination. Perform final `--final --apply` copies with writers
quiescent, then repeat both `--final` dry-runs and require no itemized changes.
Reconcile the NAS's active home/session state consistently at its agreed
handover point. Flush/unmount both destinations and deliberately reboot the
NAS into the reviewed final generation.

The final shared-pool generation needs the 500 GB to boot: `/mnt/fast` and
`/nix` are boot-critical. The old generation plus untouched 256 GB is the
rollback, so preserve both until acceptance. Do not describe the new
missing-primary case as a degraded but bootable router.

## Acceptance before releasing the old 256 GB

- `/home` is incoming p1 with `subvol=@home`; UID 1000 home/session access works.
- `/mnt/fast` is the **same** incoming p1 with `subvol=@fast`; `/nix` binds its
  `nix/` directory. All required system closures/profiles and store DB exist.
- NAS router/DHCP/DNS/tailnet/SSH work, and PostgreSQL, Attic cache/signing,
  Navidrome, Immich state and remote journal routes pass real service checks.
- Zenbook→NAS Herdr and native harness continuity are proved locally on NAS.
- Backup/restore receipts and the old boot generation remain available.

Superseded 2026-10-28: the old Fanxiang (serial `26040259615000015`) was not
kept as a recording/memory reservation. On Tom's word it was reformatted as ext4
with label `immich` and became Immich's fast tier at `/mnt/immich`
(`hosts/nas/immich-disk.nix`): the PostgreSQL cluster and Immich's generated
media. The mount checks both serial and label first.
