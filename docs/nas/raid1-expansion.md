# NAS second-drive expansion: Btrfs RAID 1 mirror

*Staged 2026-08-21 for the second 4TB HDD arriving ~September. What Tom wants
is a full live mirror of the data disk — that is **RAID 1** (RAID 3 is an
obsolete striping-with-parity scheme nobody uses; the "every byte on both
drives" one is RAID 1).*

## What it buys — and what it doesn't

RAID 1 protects against exactly one thing: **a drive dying**. The NAS keeps
serving through the failure and rebuilds onto a replacement with no restore.
It does NOT protect against deletion, ransomware, filesystem corruption, or
the NAS itself dying — a mirror faithfully replicates every mistake within
seconds. That cover comes from the other three layers, all live as of
2026-08-21: btrbk snapshots (oops recovery), the borg chain (ws2b, versioned
backup), and the monthly one-way LaCie dump (offline catastrophic copy).

With 2×4TB in RAID 1, usable capacity stays 4TB (currently 1.9T used).

## Shopping note

Match the existing drive class: WD Red Plus 4TB (WD40EFZZ), CMR. Any CMR NAS
drive works; avoid SMR drives — their rebuild behavior under Btrfs is awful.

## Runbook (live conversion, no reformat, data stays in place)

1. Power the NAS down, seat the new drive in the empty bay, boot. The data
   filesystem is untouched — it is UUID-mounted (hosts/nas/default.nix
   `filesystemUuid`), so device-name shuffling cannot bite.
2. Identify the new disk (empty, no partitions): `lsblk -o NAME,SIZE,SERIAL`.
   Note its serial for step 6.
3. Add it to the data filesystem, WHOLE DISK, no partitioning needed:
   `sudo btrfs device add /dev/sdX /mnt/nas`
4. Convert data + metadata to raid1 (this is the long step — it rebalances
   ~1.9T across both spindles; run it overnight, it is safe to serve media
   during, just slower):
   `sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/nas`
   Progress: `sudo btrfs balance status /mnt/nas`.
5. Verify — both lines of `sudo btrfs filesystem df /mnt/nas` must say RAID1,
   and `sudo btrfs filesystem show /mnt/nas` must list 2 devices with roughly
   equal used bytes.
6. Repo follow-ups (same commit):
   - hosts/nas/default.nix: extend the smartd/device-identity block with the
     second drive's /dev/disk/by-id path so SMART monitoring covers both.
   - hosts/nas/disko.nix: add a comment that the data volume is now 2-device
     raid1, converted imperatively on 2026-09-XX — disko only describes
     provision-time layout and must NOT be re-applied to this pool.
7. Failure drill, once, so the degraded path is known BEFORE it matters:
   `sudo btrfs device stats /mnt/nas` (all zeros = healthy). Know the
   degraded mount incantation: a raid1 pool with a dead device needs
   `mount -o degraded` — NixOS will NOT boot the mount unit unaided with a
   missing device. Replacement is `btrfs replace start <devid> /dev/sdNEW
   /mnt/nas`, not device-remove/add.

## Timing interaction with everything else

Do the conversion AFTER the router-cutover settles. The balance saturates the
disk for hours; don't overlap it with a LaCie dump or first borg seed.
