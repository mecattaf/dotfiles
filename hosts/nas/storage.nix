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

    # ── Subvolume layout (the #130 "decide before data lands" decision) ──────
    # The four data roots are BTRFS SUBVOLUMES, not plain directories, created
    # by the Day-2 runbook right after mkfs:
    #
    #   btrfs subvolume create /mnt/nas/photos     # 0700 tom
    #   btrfs subvolume create /mnt/nas/music      # 0750 tom
    #   btrfs subvolume create /mnt/nas/documents  # 0750 tom
    #   btrfs subvolume create /mnt/nas/videos     # 0750 tom (added Day 2: the
    #                                              # LaCie's 545 GiB library, now
    #                                              # served by NAS-local Plex)
    #   btrfs subvolume create /mnt/nas/services   # 0711 root
    #   btrfs subvolume create /mnt/nas/.snapshots # 0700 root, NEVER exported
    #
    # Why: snapshots are per-subvolume, so future btrbk retention (#130 §2a)
    # needs these boundaries to exist before the LaCie data arrives — cheap
    # now, a full re-migration later. .snapshots stays containment-safe with
    # zero effort: NFSv4 does not cross a subvolume boundary without its own
    # export entry, and it never gets one.
    #
    # NFSv4 exports use EXPLICIT UNIQUE fsids per #131: subvolumes below a
    # lone fsid=0 export are a known sharp edge (each subvolume has its own
    # st_dev), so every crossing point is exported deliberately. Only the
    # coordinator on the /30 is admitted; other clients reach the relays over
    # Tailscale and the filesystem itself never leaves this cable.
    # No hostName bind: nfsd listening on the wildcard is fine on a box whose
    # only network is the /30 cable, and binding 10.77.0.2 raced address
    # assignment at boot even behind network-online.target (NM reports online
    # before the static address exists — hit live on the first two
    # post-cutover reboots: "nfsdctl: Cannot assign requested address").
    # nftables scoping 2049 to 10.77.0.1 is the actual access control.
    services.nfs.server = {
      enable = true;
      exports = ''
        ${storageRoot} 10.77.0.1(rw,sync,fsid=0,no_subtree_check,no_root_squash)
        ${storageRoot}/photos 10.77.0.1(rw,sync,fsid=1,no_subtree_check,no_root_squash)
        ${storageRoot}/music 10.77.0.1(rw,sync,fsid=2,no_subtree_check,no_root_squash)
        ${storageRoot}/documents 10.77.0.1(rw,sync,fsid=3,no_subtree_check,no_root_squash)
        ${storageRoot}/services 10.77.0.1(rw,sync,fsid=4,no_subtree_check,no_root_squash)
        ${storageRoot}/videos 10.77.0.1(rw,sync,fsid=5,no_subtree_check,no_root_squash)
      '';
    };
    networking.firewall.extraInputRules = ''
      ip saddr 10.77.0.1 tcp dport 2049 accept comment "NFSv4 from coordinator"
    '';

    # With the wildcard bind the address race is gone, but nfsd must still not
    # start before the exported tree is mounted — exporting the bare mountpoint
    # directory would hand clients an empty fsid=0 root. network-online stays
    # as ordering hygiene only; it is NOT sufficient for address availability
    # (see the hostName retirement above) and nothing here depends on it being.
    systemd.services.nfs-server = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ storageRoot ];
    };

    # 'z' (adjust-only), deliberately not 'd': if a runbook step were skipped,
    # 'd' would silently create plain DIRECTORIES where subvolumes belong and
    # the data migration would land unsnapshottable. 'z' only enforces
    # ownership/mode on what the runbook created.
    systemd.tmpfiles.rules = [
      # Plain directory INSIDE the services subvolume (not a subvolume root, so
      # 'd' is safe here): destination of the coordinator-driven weekly journal
      # archive (#135). Never NFS-exported.
      "d ${storageRoot}/services/journal-archive 0700 root root -"
      "z ${storageRoot}/music 0750 tom users -"
      "z ${storageRoot}/photos 0700 tom users -"
      "z ${storageRoot}/documents 0750 tom users -"
      "z ${storageRoot}/videos 0750 tom users -"
      "z ${storageRoot}/services 0711 root root -"
      "z ${storageRoot}/.snapshots 0700 root root -"
    ];
  };
}
