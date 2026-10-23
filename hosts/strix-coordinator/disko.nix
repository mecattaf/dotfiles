{
  # Coordinator install target — the internal WD_BLACK SN7100 1TB NVMe, serial
  # 25140U804698. This is the fleet's ANCHOR: the one disk that never moves.
  # NVMe enumeration changes across boots; only this serial is an install target.
  # The second 1TB (26051Y809195) belongs to strix-worker.
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
