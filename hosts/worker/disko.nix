{
  # Worker install target — the internal WD_BLACK SN7100 **1TB** NVMe, serial
  # 26051Y809195, fitted 2026-08-30 (dotfiles#259). It replaces the 500GB
  # SN7100 (serial 260538801482) that carried this host from the 2026-08-21
  # reintegration until the SSD transition; the twins are a matched pair and a
  # 500GB paired against the coordinator's 1TB was the fleet's dual-node
  # capacity ceiling.
  #
  # ── Why the attr is `w1t` and NOT `main` ────────────────────────────────────
  # disko derives GPT partition NAMES from the attr: `main` yields
  # `disk-main-ESP` / `disk-main-root`. The coordinator's anchor uses those same
  # two names, and BOTH hosts mount / and /boot through
  # /dev/disk/by-partlabel/<name> with x-initrd.mount. Two disks carrying the
  # same names on one machine is a coin flip resolved by udev, and the migration
  # deliberately puts the old 500GB inside the coordinator afterwards. A
  # disjoint attr means this disk can never contend with the anchor's, in any
  # slot, on either box. See dotfiles#258.
  #
  # ── Why explicit partition `uuid`s ──────────────────────────────────────────
  # Without `uuid`, disko derives each partition's device from
  # /dev/disk/by-partlabel/<label> — and during the transient dual-disk phase
  # the LIVE 500GB already owned those links, so a create run would have
  # formatted and mounted the RUNNING system instead of the new disk (its
  # blkid guard skips mkfs on an already-formatted root, then mounts it at
  # /mnt). With `uuid` set, disko writes that exact GUID via --partition-guid
  # and derives device = /dev/disk/by-partuuid/<uuid>, so format and mount can
  # only ever land on this disk. The rendered fstab names by-partuuid too,
  # which is what makes the disk boot correctly once it moves to slot 1.
  #
  # `device` is by-id, not /dev/nvme0n1: NVMe enumeration order is not an
  # identity once two drives are present — this disk is nvme1n1 while the 500GB
  # is still fitted, and becomes nvme0n1 after the swap. The plain
  # model_serial alias is used deliberately (not the `_1` duplicate, not the
  # `eui.` form).
  #
  # ── Status: the transition is DONE (2026-08-30) ─────────────────────────────
  # This host now runs FROM this disk. It was installed with disko-install
  # while the 500GB was still live and booted via a one-shot NVRAM entry keyed
  # to the ESP's PARTUUID, with the 500GB left fitted as rollback. Across that
  # reboot the kernel's NVMe enumeration FLIPPED — this disk went from nvme1n1
  # to nvme0n1 with no hardware change — which is the whole argument for the
  # pinned identifiers above, observed rather than theorised. The 500GB's GPT
  # labels were then renamed `disk-main-*` → `oldworker-*` so it can never
  # contend with the coordinator's anchor once refitted there.
  #
  # ⚠️ DESTRUCTIVE: an explicit disko/disko-install run wipes this disk.
  # `nixos-rebuild switch` never partitions and is safe. The earlier standing
  # ban on switching this declaration onto the host is retired — the host's
  # running root IS these PARTUUIDs now.
  disko.devices.disk.w1t = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          uuid = "25db1b50-f51c-499b-a628-26a25fa02662";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          uuid = "e4869fbf-f6c5-4bf5-960f-cf19376e139d";
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
