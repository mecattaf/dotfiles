{
  # Coordinator install target — the internal WD_BLACK SN7100 1TB NVMe, serial
  # 25140U804698. This is the fleet's ANCHOR: the one disk that never moves.
  # Flashed LAST during the initial fleet bring-up (2026-07-05); re-pinned
  # 2026-08-30 when the SSD transition made this host dual-disk (#259, #258).
  #
  # ── Why `device` is by-id and no longer /dev/nvme0n1 ────────────────────────
  # This box now has a SECOND NVMe: the 500GB SN7100 (serial 260538801482)
  # moved here from the worker, which took a 1TB in its place. It is not spare
  # capacity — it carries the whole of /home and the box is expected to boot
  # with it fitted. NVMe enumeration order is not an identity — the
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

  # ── INTERIM (2026-10-04): no secondary; /home lives on the anchor ────────────
  # The 500GB SN7100 260538801482 is SODIMO'S and left with the `worker`
  # chassis on 2026-10-04. Before it left, /home was copied onto this anchor
  # (rsync -aHAXSx into the anchor's own /home directory, verified with a
  # checksum dry-run), so dropping the `data` disk below IS the cutover: /home
  # is now a plain directory on `/`.
  #
  # This knowingly breaks the anchor=OS-only rule for a while. Tom's own 1TB
  # 26051Y809195 (formerly the worker's disk) is now fitted in this box as the
  # next /home secondary (ruling 2026-10-04: both 1TBs go to this host, which
  # supersedes the 09-19 "NUC or NAS /mnt/fast" note). /home moves onto it in a
  # second short outage: format it STANDALONE (never `disko --flake
  # .#coordinator`, which would act on the anchor too), copy, then declare it
  # here as a new attr `h1t` with a fresh partition uuid, nofail and
  # x-systemd.device-timeout=10s exactly as the 500GB had them.
  #
  # Until then home-on-secondary.service (./default.nix) asserts the interim
  # shape instead: /home must NOT be a separate mount and must hold the
  # dotfiles checkout.
}
