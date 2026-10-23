# NAS home: prepare on the worker bench, then move once

This is the storage part of #597 / #599. Tom's latest order is a simultaneous
fleet power-off, SSD transfer and recabling, followed by boot into the new
roles. Prepare and fill the 500 GB disk while it is still inside strix-worker,
booted from an installer USB with Ethernet to the BE550. The NAS and current
strix remain available as sources until that final power-off.

The NAS mounts the known serial-bearing by-id p2 path:

```text
/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482-part2
```

There is no PARTUUID option or placeholder to fill after partitioning. This
path works on both the bench and the NAS, regardless of controller enumeration.
The helper also checks the hardware serial, partition label, filesystem label,
and the actual mounted device and subvolume. Verify the expected by-id and
serial on the bench before staging; correct the Nix device and serial together
if the physical identity differs from the survey.

| Disk | Tonight's role |
| --- | --- |
| WD 500 GB, serial `260538801482` (verify on bench) | p1: `disk-primary-fast`, 176G ext4, filesystem label `nasfast`, reserved and unmounted. p2: `disk-primary-home`, remaining space, btrfs label `nashome`, `@home` and `@snapshots`. |
| Fanxiang 256 GB, serial `26040259615000015` | Stays in the NAS with `/mnt/fast`, `/nix` and current service state. |
| NAS HDD and eMMC | Stay in the NAS. Preserve escrow, sealed source archive and old eMMC home. |

## Before partitioning, with Windows still available

Follow DECISIONS.md 5: Tom saves anything wanted from Windows to the NAS HDD
before the 500 GB is erased. Complete the separate BIOS preparation while
Windows is available. Boot the installer USB without opening the worker or
moving its SSD. Confirm the disk's model, capacity, serial and by-id link.

Complete NAS escrow while the NAS is up; the helper's `escrow` command remains
NAS-only, dry-run by default, and uses the HDD. Preserve the full strix-home
archive at `/mnt/nas/backups/strix-home-2026-10-23` and the NAS eMMC home. This
curated SSD copy does not replace either archive.

Build the helper from the reviewed integration checkout and copy its closure
to the installer before the network goes away. Check `df -h /` before building
and stop if less than 25 GB is free. For example, after setting `bench_address`
to the installer's Ethernet address:

```sh
helper_path=$(nix build --no-link --print-out-paths .#nas-home-migrate)
nix copy --to "ssh-ng://root@$bench_address" "$helper_path"
```

Record that store path for the installer shell as `helper_path`. Arrange SSH
read access from the installer to the selected source; the archive has no NFS
export. The helper and source access must be ready before the simultaneous
power-off. These are attended cutover steps, not actions run by this PR.

## Hand-prepare the disk on the installer

The following destructive recipe is for the attended bench step **after Tom's
Windows preservation is complete and the serial is checked**. Never run NAS
disko on this disk or on the live NAS. The migration helper never partitions,
formats, mounts or controls services.

As root in the installer, first inspect the only intended disk:

```sh
disk=/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482
lsblk --nodeps --output SIZE,MODEL,SERIAL "$disk"
```

After confirming that identity and the saved Windows data, the hand recipe is:

```sh
sgdisk --zap-all "$disk"
sgdisk -n1:0:+176G -t1:8300 -c1:disk-primary-fast \
       -n2:0:0 -t2:8300 -c2:disk-primary-home "$disk"
udevadm settle
mkfs.ext4 -m 1 -L nasfast "$disk-part1"
mkfs.btrfs -L nashome "$disk-part2"
install -d -m 0700 /mnt/nas-home-bench /mnt/newhome
mount -t btrfs -o subvolid=5,compress=zstd:1,noatime "$disk-part2" /mnt/nas-home-bench
btrfs subvolume create /mnt/nas-home-bench/@home
btrfs subvolume create /mnt/nas-home-bench/@snapshots
chmod 0755 /mnt/nas-home-bench/@home
chmod 0700 /mnt/nas-home-bench/@snapshots
umount /mnt/nas-home-bench
mount -t btrfs -o subvol=@home,compress=zstd:1,noatime "$disk-part2" /mnt/newhome
install -d -m 0700 -o 1000 -g 100 /mnt/newhome/tom
```

Mount `@home` itself at the helper target, not the top-level btrfs tree. Leave
p1 unmounted. No generated UUID needs to be copied back into Nix.

## Pre-fill and verify before the shared power-off

Run the copied helper on the installer. These commands are dry-runs:

```sh
"$helper_path/bin/nas-home-migrate" home --bench \
  --source root@nas:/mnt/nas/backups/strix-home-2026-10-23/ --target /mnt/newhome

"$helper_path/bin/nas-home-migrate" home --bench \
  --source root@strix:/home/tom/ --target /mnt/newhome
```

Choose the archive or the still-live strix as the pre-fill source. Both source
paths contain Tom's home contents at their root; the helper places them inside
the mounted `@home/tom/`. After inspecting a dry-run, the attended operator
adds `--apply` to that same invocation to copy. `--bench` permits this home
operation on the installer; it does not skip any serial or mount check and
cannot be used for escrow. Keep credentials and history private on the bench.

Preserve the NAS's old `/home/tom/` in a separate
`/mnt/newhome/tom/nas-home-legacy-2026-10-23/` directory on this SSD, using
`rsync -aHAXS --numeric-ids` from `root@nas:/home/tom/`, before the NAS is
powered off. Do not merge the two homes. The helper never uses `--delete`, so
this legacy directory remains through subsequent curated copies.

The handover coordinator must arrange a consistent final source capture and
end the old harness sessions at the agreed handover point before their final
delta. Copy the final delta with `--final --apply`, then rerun `--final`
without `--apply` and require no itemized changes. Use the still-live strix
source for that final pass, or an explicitly refreshed, consistent sealed
archive. The initial archive recipe used `-aHS`; a final pass from the original
with `-aHAXS` also preserves ACLs and xattrs omitted by that earlier recipe.
If the host rename has already been activated, use its verified reachable
hostname in `--source`; `strix` here denotes the pre-cutover source.

Herdr's live store stays excluded. The sealed archive retains that history;
the NAS starts its own server store. Codex DB/WAL sets and Claude state need
the consistent final capture above. Reusing a stale archive after further
source activity does not complete the handover.

## Storage gate for the one shared power-off

All of these facts must be recorded before the fleet is powered off:

- Windows preservation and NAS escrow are complete; the sealed full-home
  archive is retained.
- The bench helper verified serial `260538801482`, p2 `disk-primary-home`,
  filesystem label `nashome`, the mounted `@home`, and a checksum final pass
  with no itemized differences. The legacy NAS home is preserved separately.
- `@home/tom` has UID 1000 ownership and suitable home permissions;
  `@snapshots` exists; p1 stays unmounted. Flush and unmount the bench home
  after the final copy, before the shared power-off.
- The integrated NAS generation is built and staged as its next boot, with
  the existing good generation retained as fallback. Its fstab names the
  by-id p2 above and the user manager requires `/home`. Stage this boot
  generation through the authorized cutover coordinator without activating
  a home remount while the disk is still on the bench.

The integration worker combines Linux 7.3, the NAS agent role and the other
fleet changes; this storage branch does not select the fleet kernel or stage
the standalone storage-only host. Its old `partUuid` test overrides should be
removed when this revision is integrated, including
`tests/cutover-integration/default.nix`.

Only after the overall cutover coordinator has verified the other fleet
gates does Tom power the fleet off together, move this prepared 500 GB SSD
from strix-worker to the NAS, move the spare 1 TB to strix-worker, and cable
the compute pair. The NAS's 256 GB Fanxiang stays put. Its first new-role boot
mounts the already-filled p2 without discovering or editing a UUID. A missing
home disk leaves the router bootable and the user manager stopped via
`RequiresMountsFor=/home`.

After that boot, verify the real `/home` source/subvolume, UID 1000's home,
the independent Herdr store and harness continuity as part of the fleet
acceptance. Fleet Tailscale enrollment is with the official tailscale.com
tailnet and non-expiring machine keys; compute links, offload and enrollment
belong to the integration gates. Passing this storage check alone is not the
instruction to power off the fleet.
