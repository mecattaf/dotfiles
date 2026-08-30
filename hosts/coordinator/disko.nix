{
  # Coordinator install target — the internal WD_BLACK SN7100 1TB NVMe, serial
  # 25140U804698. This is the fleet's ANCHOR: the one disk that never moves.
  # Flashed LAST during the initial fleet bring-up (2026-07-05); re-pinned
  # 2026-08-30 when the SSD transition made this host dual-disk (#259, #258).
  #
  # ── Why `device` is by-id and no longer /dev/nvme0n1 ────────────────────────
  # This box now has a SECOND NVMe: the 500GB SN7100 (serial 260538801482)
  # retired off the worker. NVMe enumeration order is not an identity — the
  # worker proved it during the transition, where the same physical disk was
  # nvme1n1 before a reboot and nvme0n1 after, with no hardware change at all.
  # A destructive disko run against a bare /dev/nvme0n1 would therefore be a
  # coin flip between the anchor and the secondary. by-id cannot drift.
  #
  # ── Why explicit partition `uuid`s ──────────────────────────────────────────
  # These are the GUIDs the disk ALREADY carries (read off the live machine,
  # 2026-08-30) — declaring them is a no-op for the running system's identity
  # and changes only how the layout is addressed. Two effects, both wanted:
  # disko derives device = /dev/disk/by-partuuid/<uuid> instead of
  # /dev/disk/by-partlabel/<label>, so neither a format nor a mount can land on
  # the wrong disk; and the rendered fstab names by-partuuid, which retires the
  # last by-partlabel dependency in the fleet. Partition LABELS are a weak
  # identity — they are writable metadata, and the transition renamed the
  # 500GB's `disk-main-*` pair to `oldworker-*` with a single sfdisk call
  # precisely because a duplicate label pair on one machine is resolved by
  # whichever udev saw first. by-partuuid has no such failure mode.
  #
  # ⚠️ DESTRUCTIVE: an explicit disko/disko-install run wipes this disk.
  # `nixos-rebuild switch` never partitions and is safe.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_25140U804698";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          uuid = "bbfd7cf3-0014-4ed4-b26c-d841dc6e36a0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          uuid = "155d5ec6-48fd-477c-a80d-005e732810af";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
