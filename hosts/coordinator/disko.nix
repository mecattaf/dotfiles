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

  # ── The secondary: /home on the 500GB (2026-08-30, #261) ────────────────────
  # The WD_BLACK SN7100 500GB retired off the worker, serial 260538801482.
  # Wiped blank before the physical move (no partition table, no bootloader),
  # then laid out here.
  #
  # ── The rule this disk exists to enforce ────────────────────────────────────
  # The 1TB anchor holds the OS and only the OS: the nix store and everything
  # NixOS derives from it, /etc, /var, and the local-models weight collection.
  # EVERYTHING ELSE — the whole of /home — lives here. That is a durable
  # policy, not a one-off space reclaim: work that leaves large residue
  # (flashnext development, a from-source chromium, a stray 50GB build tree)
  # lands in $HOME and therefore lands on this disk, where filling it up
  # cannot threaten the system's ability to boot or rebuild.
  #
  # Note what this does NOT move. `~/mecattaf/dotfiles` is the git checkout
  # tom edits, so it is ordinary user data and lives here with every other
  # `mecattaf/` repo. The configuration NixOS actually reads is the evaluated
  # closure under /nix/store (/run/current-system, /etc/static) and stays on
  # the anchor. Verified before the split: nothing under /etc, /var/lib or
  # /run/current-system symlinks into /home, so the root filesystem has no
  # dependency on this disk being present.
  #
  # ── The one thing that had to move OUT of /home first ───────────────────────
  # modules/fn-rdma.nix stages vermagic-pinned .ko files and inserts them at
  # sysinit.target with DefaultDependencies=no. Its stagedDir default was
  # ~/.local/state/flashnext-rdma, which no mount unit could ever satisfy that
  # early; it is /var/lib/flashnext-rdma as of this commit. Kernel modules are
  # OS state and belong on the anchor regardless.
  #
  # `uuid` is declared for the same reason as the anchor's partitions: disko
  # then derives device = /dev/disk/by-partuuid/<uuid>, so neither a format nor
  # a mount can be resolved by a writable label or an unstable nvmeXn1 name.
  # Attr name `data` is deliberately disjoint from the anchor's `main` (and the
  # worker's `w1t`) — a duplicate `disk-main-*` label pair on one machine is
  # exactly the collision the transition had to defuse by hand.
  #
  # ⚠️ DESTRUCTIVE: an explicit disko/disko-install run wipes this disk.
  # `nixos-rebuild switch` never partitions and is safe.
  disko.devices.disk.data = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482";
    content = {
      type = "gpt";
      partitions = {
        home = {
          size = "100%";
          uuid = "7a1c9d2e-0b64-4f8a-9c31-5e2d8f4a6b70";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/home";
            # -m 1: the ext4 default reserves 5% for root, which on a 465GB
            # non-root filesystem is ~23GB spent to protect against a class of
            # failure (root cannot log in to clean up) that does not apply.
            extraArgs = [
              "-m"
              "1"
            ];
            mountOptions = [ "defaults" ];
          };
        };
      };
    };
  };
}
