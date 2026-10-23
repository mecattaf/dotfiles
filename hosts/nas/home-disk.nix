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
    hddUuid = config.myNas.storage.filesystemUuid;
    postgresql = config.services.postgresql.package;
  };
in
{
  options.myNas.homeDisk = {
    enable = lib.mkEnableOption "the manually prepared NAS home SSD (#599)";
    partUuid = lib.mkOption {
      type = lib.types.str;
      default = "VERIFY-HOME-PARTUUID";
      description = "Verified GPT partition UUID (PARTUUID, not filesystem UUID) of the incoming SSD's p2";
    };
    device = lib.mkOption {
      type = lib.types.str;
      # VERIFY against the incoming disk before filling partUuid.
      default = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482";
      description = "Verified whole-disk by-id path; used for SMART and migration identity checks";
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
          builtins.match "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" cfg.partUuid
          != null;
        message = "NAS home disk: replace VERIFY-HOME-PARTUUID in myNas.homeDisk.partUuid with the verified p2 PARTUUID after checking the incoming SSD serial; do not deploy this placeholder";
      }
      {
        assertion =
          lib.hasPrefix "/dev/disk/by-id/nvme-" cfg.device
          && lib.hasSuffix "_${cfg.serial}" cfg.device
          && cfg.serial != "";
        message = "NAS home disk: device must be a whole NVMe by-id path ending in the verified serial";
      }
    ];

    # Prepared BY HAND in tonight's stage 4, never added to disko:
    # p1 disk-primary-fast, 176G ext4, RESERVED AND UNMOUNTED.
    # p2 disk-primary-home, remaining space, btrfs @home + @snapshots.
    # /mnt/fast, /nix, service state and the kernel remain on their current path.
    fileSystems."/home" = {
      device = "/dev/disk/by-partuuid/${cfg.partUuid}";
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
      device = "/dev/disk/by-partuuid/${cfg.partUuid}";
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
    # pg_dumpall. This package can be built before the PARTUUID is filled.
    system.build.nas-home-migrate = migrate;
    environment.systemPackages = [ migrate ];
  };
}
