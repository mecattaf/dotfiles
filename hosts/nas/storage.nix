{
  config,
  lib,
  ...
}:
let
  cfg = config.myNas.storage;
  # Keep the same absolute root the coordinator used for Immich and Navidrome.
  # Their databases contain media paths, so preserving /mnt/nas makes the
  # restore a data move rather than an in-database path rewrite.
  storageRoot = "/mnt/nas";
in
{
  options.myNas.storage = {
    enable = lib.mkEnableOption "the verified NAS data disk and its NFS export";
    filesystemUuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Verified Btrfs filesystem UUID of the NAS data disk";
    };
    smartDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/disk/by-id/ata-...";
      description = "Verified stable by-id path for SMART monitoring";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.filesystemUuid != null;
        message = "myNas.storage.filesystemUuid must be recorded from the real HDD before enabling storage";
      }
      {
        assertion = cfg.smartDevice != null;
        message = "myNas.storage.smartDevice must be a verified /dev/disk/by-id path before enabling storage";
      }
    ];

    fileSystems.${storageRoot} = {
      device = "/dev/disk/by-uuid/${cfg.filesystemUuid}";
      fsType = "btrfs";
      options = [
        "noatime"
        "compress=zstd:3"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    services.btrfs.autoScrub = {
      enable = true;
      fileSystems = [ storageRoot ];
      interval = "monthly";
    };

    services.smartd = {
      enable = true;
      autodetect = false;
      devices = [
        {
          device = cfg.smartDevice;
          options = "-a -n standby,q -W 4,45,50";
        }
      ];
    };

    # NFSv4 exports the data root only to the coordinator on the dedicated /30.
    # Other clients reach coordinator over Tailscale; it relays the applications
    # over Ethernet. The filesystem itself never leaves this /30.
    services.nfs.server = {
      enable = true;
      hostName = "10.77.0.2";
      exports = ''
        ${storageRoot} 10.77.0.1(rw,sync,fsid=0,no_subtree_check,no_root_squash)
      '';
    };
    networking.firewall.extraInputRules = ''
      ip saddr 10.77.0.1 tcp dport 2049 accept comment "NFSv4 from coordinator"
    '';

    systemd.tmpfiles.rules = [
      "d ${storageRoot}/music 0750 tom users -"
      "d ${storageRoot}/photos 0700 tom users -"
      "d ${storageRoot}/documents 0750 tom users -"
      "d ${storageRoot}/services 0711 root root -"
    ];
  };
}
