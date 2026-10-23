{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.homeDisk;
  migrate = pkgs.callPackage ../../pkgs/nas-home-migrate {
    expectedDisk = cfg.device;
    expectedSerial = cfg.serial;
    expectedLabel = "nashome";
    hddUuid = config.myNas.storage.filesystemUuid;
    postgresql = config.services.postgresql.package;
  };
in
{
  options.myNas.homeDisk = {
    enable = lib.mkEnableOption "the manually prepared NAS home SSD (#599)";
    device = lib.mkOption {
      type = lib.types.str;
      # VERIFY on the installer bench before the simultaneous fleet power-off.
      default = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482";
      description = "Whole-disk by-id path; p2 backs home, and the whole disk is used for SMART and migration identity checks";
    };
    serial = lib.mkOption {
      type = lib.types.str;
      # VERIFY on arrival; this is the expected serial from the survey.
      default = "260538801482";
      description = "Expected hardware serial of the incoming home SSD";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.hasPrefix "/dev/disk/by-id/nvme-" cfg.device
          && lib.hasSuffix "_${cfg.serial}" cfg.device
          && cfg.serial != "";
        message = "NAS home disk: device must be a whole NVMe by-id path ending in the verified serial";
      }
    ];

    # Prepared BY HAND on the worker's installer bench BEFORE the whole-fleet
    # power-off; see docs/nas/home-disk-cutover.md. Never added to disko:
    # p1 disk-primary-fast, 176G ext4, RESERVED AND UNMOUNTED.
    # p2 disk-primary-home, remaining space, btrfs label nashome, @home + @snapshots.
    # Serial-bearing by-id p2 is known before partitioning creates any UUID.
    # Both mounts are ready to build/stage before the unplug and SSD transfer.
    # /mnt/fast, /nix, service state and the kernel remain on their current path.
    fileSystems."/home" = {
      device = "${cfg.device}-part2";
      fsType = "btrfs";
      options = [
        "subvol=@home"
        "compress=zstd:1"
        "noatime"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };
    fileSystems."/mnt/home-snapshots" = {
      device = "${cfg.device}-part2";
      fsType = "btrfs";
      options = [
        "subvol=@snapshots"
        "noatime"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    # nofail keeps the router bootable, but a missing SSD must keep the user
    # manager down instead of creating a second agent home on the eMMC.
    systemd.services."user@1000".unitConfig.RequiresMountsFor = [ "/home" ];

    # Export the SAME helper that is installed, including the server-matched
    # pg_dumpall. Copy its closure to the installer for bench preparation.
    system.build.nas-home-migrate = migrate;
    environment.systemPackages = [ migrate ];
  };
}
