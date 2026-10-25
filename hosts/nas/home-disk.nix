{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.homeDisk;
  shared = cfg.layout == "shared-btrfs";
  partition = if shared then "1" else "2";
  partLabel = if shared then "disk-primary" else "disk-primary-home";
  fsLabel = if shared then "nasprimary" else "nashome";
  migrate = pkgs.callPackage ../../pkgs/nas-home-migrate {
    expectedDisk = cfg.device;
    expectedSerial = cfg.serial;
    expectedLabel = fsLabel;
    expectedPartition = partition;
    expectedPartLabel = partLabel;
    hddUuid = config.myNas.storage.filesystemUuid;
    postgresql = config.services.postgresql.package;
  };
in
{
  options.myNas.homeDisk = {
    enable = lib.mkEnableOption "the manually prepared NAS home SSD (#599)";
    layout = lib.mkOption {
      type = lib.types.enum [
        "shared-btrfs"
        "legacy-split"
      ];
      default = "shared-btrfs";
      description = "Shared 500GB primary pool (@home/@fast/@snapshots), or the earlier split home-only layout. Never formats or migrates data.";
    };
    device = lib.mkOption {
      type = lib.types.str;
      # VERIFY on the installer bench before the simultaneous fleet power-off.
      default = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482";
      description = "Whole-disk by-id identity; shared pool uses p1, legacy home-only layout uses p2";
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

    # Prepared manually only after the incoming serial is verified. A single
    # primary btrfs partition shares capacity between home and old fast state;
    # eMMC root/boot stays unchanged. Keep the 256GB intact until new @fast
    # has booted and passed acceptance, then release its memory-only gate.
    fileSystems."/home" = {
      device = "${cfg.device}-part${partition}";
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
      device = "${cfg.device}-part${partition}";
      fsType = "btrfs";
      options = [
        "subvol=@snapshots"
        "noatime"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    fileSystems."/mnt/fast" = lib.mkIf shared {
      device = lib.mkForce "${cfg.device}-part1";
      fsType = lib.mkForce "btrfs";
      # mkForce also drops the x-initrd.mount that neededForBoot adds. Without it the
      # systemd initrd never mounts @fast, the /nix bind from /sysroot/mnt/fast/nix
      # fails and stage 1 stops in emergency mode (the 2026-10-25 19:10 cutover hang).
      options = lib.mkForce [
        "subvol=@fast"
        "compress=zstd:1"
        "noatime"
        "x-initrd.mount"
      ];
      neededForBoot = true;
    };

    # Refuse a second agent home on eMMC. In shared mode the same SSD is
    # additionally boot-critical through @fast/nix; retain the old generation
    # and untouched 256GB fast tier until that first shared-pool boot passes.
    systemd.services."user@1000".unitConfig.RequiresMountsFor = [ "/home" ];

    # Export the SAME helper that is installed, including the server-matched
    # pg_dumpall. Copy its closure to the installer for bench preparation.
    system.build.nas-home-migrate = migrate;
    environment.systemPackages = [ migrate ];
  };
}
