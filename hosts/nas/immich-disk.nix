{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
# The 256GB Fanxiang, the NAS's secondary SSD, is Immich's fast tier: the
# PostgreSQL cluster (Immich's `tom` database, plus atuin and paperless) and
# Immich's generated media (thumbs, encoded-video, profile). Tom, 2026-10-28:
# "immich db (that needs "fast" storage, so the 256gb ssd secondary becomes the
# place where the immich cache or whatever lives)". This replaces the earlier
# Screenpipe/CUA recording reservation (`myNas.memoryDisk`), which never ran.
# The disk was the old /mnt/fast before the 1TB pool took that role.
let
  cfg = config.myNas.immichDisk;
  device = "/dev/disk/by-id/nvme-Fanxiang_S500Pro_256GB_26040259615000015";
  partition = "${device}-part1";
  mountUnit = "${utils.escapeSystemdPath cfg.mountPoint}.mount";
in
{
  options.myNas.immichDisk = {
    enable = lib.mkEnableOption "the 256GB secondary SSD as Immich's fast tier (PostgreSQL and generated media)";
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/immich";
      description = "Mount point of the Immich fast tier; media.nix roots PostgreSQL and Immich's generated media here.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.homeDisk.layout == "shared-btrfs";
        message = "The 256GB Immich disk is free only once /mnt/fast lives on the shared home pool.";
      }
    ];
    # nofail keeps a dead SSD from blocking boot; PostgreSQL and Immich declare
    # RequiresMountsFor on this path, so they stay down rather than initdb an
    # empty cluster on the eMMC root.
    fileSystems.${cfg.mountPoint} = {
      device = partition;
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };
    systemd.services.nas-immich-disk-identity = {
      description = "Refuse the Immich disk mount until the serial and label match";
      requiredBy = [ mountUnit ];
      before = [ mountUnit ];
      after = [ "${utils.escapeSystemdPath partition}.device" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        test "$(${pkgs.util-linux}/bin/lsblk --nodeps --noheadings --raw --output SERIAL ${device})" = 26040259615000015
        test "$(${pkgs.util-linux}/bin/blkid -s LABEL -o value ${partition})" = immich
      '';
    };
  };
}
