{
  config,
  lib,
  options,
  ...
}:
# ─── /var and /tmp off the eMMC — GATE OFF, REBOOT-ONLY (O1, 2026-11-10) ─────
#
# Tom, 2026-11-10: "58gb emmc is still quite large for it to be full. i think
# that only the nixos flash should be on there?" and "/tmp goes straight to
# the 1tb". /nix has been on the 1TB pool since 2026-08-22 (./nix-on-nvme.nix),
# /home since 2026-10-25 (./home-disk.nix). This moves the last two writers:
# /var (7.4G on 2026-11-10: 4.0G journal, a 2.2G one-off fleet backup,
# AdGuard) and /tmp (8.9G that day, 24G on 2026-11-05, mostly agent scratch)
# onto the same pool as subvolumes @var and @tmp, beside @home and @fast. The
# eMMC keeps /boot and a root holding /etc, /root and the host identity.
# The pool is already boot-critical through /nix and /mnt/fast, so this adds
# no new hardware dependency. Immich stays on the 256GB (./immich-disk.nix).
#
# ── WHY THIS LANDS OFF, and must not be flipped remotely ────────────────────
# Same rule as #232. /var is in NixOS's pathsNeededForBoot, so the initrd
# mounts it (x-initrd.mount) and it takes effect only at boot. Flip it only
# with `nixos-rebuild boot` and a supervised one-shot trial reboot. A live
# `switch` into it would mount the subvolumes over the running /var and /tmp;
# the switch inhibitor below makes switch-to-configuration refuse that, in
# both directions, once the running generation carries it.
#
# Never boot it before @var holds a full copy of /var: an empty /var/lib/nixos
# reallocates every uid and gid, AdGuard (house DNS) loses its config and
# Tailscale its node key. After the flip the eMMC /var and /tmp stay intact
# but hidden under the mounts; they are the rollback and are reclaimed only
# after 7 clean days, behind a no-loss check.
#
# RUNBOOK: docs/nas/system-off-emmc.md (copy, flip, trial boot, rollback,
# reclaim). The flip commit sets myNas.systemOffEmmc.enable = true in
# ./default.nix and is merged inside the reboot window, not before.
let
  cfg = config.myNas.systemOffEmmc;
  pool = "${config.myNas.homeDisk.device}-part1";
  # myNas.storageAlerts (./storage-alerts.nix, O1 PR-1) owns the mount-presence
  # tripwire. Extend it when present so this lands in either order.
  hasStorageAlerts = lib.hasAttrByPath [
    "myNas"
    "storageAlerts"
    "requiredMounts"
  ] options;
in
{
  options.myNas.systemOffEmmc.enable = lib.mkEnableOption "/var and /tmp on the 1TB pool as @var and @tmp (REBOOT-ONLY, docs/nas/system-off-emmc.md)";

  config = lib.mkMerge [
    {
      # Present in both states, so a `switch` or `test` between them is refused
      # (nixos/modules/system/activation/switchable-system.nix); `boot` is not.
      system.switch.inhibitors.nas-var-tmp-backing =
        if cfg.enable then "1TB pool @var and @tmp" else "eMMC root";
    }

    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          assertions = [
            {
              assertion =
                config.myNas.homeDisk.enable
                && config.myNas.homeDisk.layout == "shared-btrfs"
                && config.myNas.nixOnNvme.enable;
              message = "myNas.systemOffEmmc needs the shared 1TB pool that already carries /nix and /home.";
            }
          ];

          # Do NOT mkForce these: neededForBoot adds x-initrd.mount through the
          # option merge, and mkForce would drop it (./home-disk.nix /mnt/fast,
          # the 2026-10-25 19:10 hang).
          fileSystems."/var" = {
            device = pool;
            fsType = "btrfs";
            options = [
              "subvol=@var"
              "compress=zstd:1"
              "noatime"
            ];
            neededForBoot = true;
          };

          # Not boot-critical: nofail, so a missing @tmp leaves the house router
          # up on the eMMC directory instead of in emergency mode. nofail alone
          # also drops the Before=local-fs.target ordering (systemd.mount(5)),
          # which would let systemd-tmpfiles-setup run cleanOnBoot's `D! /tmp`
          # against the hidden eMMC /tmp before @tmp is mounted; restore it.
          fileSystems."/tmp" = {
            device = pool;
            fsType = "btrfs";
            options = [
              "subvol=@tmp"
              "noatime"
              "nosuid"
              "nodev"
              "nofail"
              "x-systemd.device-timeout=10s"
              "x-systemd.before=local-fs.target"
            ];
          };

          # tmpfs rejected: /tmp reached 24G on 2026-11-05 on a 22.9 GiB box.
          # From the flip on, /tmp is emptied at every boot: nothing that must
          # survive a reboot belongs there.
          boot.tmp.cleanOnBoot = true;
        }

        # /var/lib/private/atticd (./attic.nix) and /var/log/journal/remote
        # (./journal.nix) keep their binds from @fast; systemd orders them
        # after var.mount by path.
        (lib.optionalAttrs hasStorageAlerts {
          myNas.storageAlerts.requiredMounts = [
            "/var"
            "/tmp"
          ];
        })
      ]
    ))
  ];
}
