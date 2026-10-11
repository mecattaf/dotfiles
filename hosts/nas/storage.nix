{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.storage;
  # Keep the same absolute root the strix used for Immich and Navidrome.
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

    # ── hd-idle: spin the HDD down after 20 min idle (F2-4) ──────────────────
    # smartd above (D50) only watches health and is deliberately `-n
    # standby,q` so its own polling never wakes the disk — it does not spin
    # anything down by itself. hd-idle is the thing that issues the actual
    # spindown command. Upstream (adelolmo/hd-idle) warns it is "not
    # compatible with the usage of disk monitoring tools like smartmontools";
    # in practice the two have coexisted here because smartd's `standby,q`
    # mode checks power state first and skips the test instead of forcing a
    # spin-up — if F2-6's 48h acceptance check ever shows the start/stop
    # count climbing, suspect this interaction first.
    #
    # `-i 0` sets the default idle timeout to 0 (never spin down) for every
    # disk hd-idle can see, then the `-a <device> -i 1200` pair overrides
    # that for this HDD only (1200s = 20min). The NAS nix store and
    # everything else on this box live on NVMe and must never be told to
    # spin down. Do NOT use `hdparm -S`: WD Red firmware is known to ignore
    # it (sheet F2-4).
    #
    # NOTE: this alone does not get the disk to standby yet. The k3s
    # local-path PVs on it (ax postgres, rustfs, redis —
    # modules/ax-fleet/interface.nix:182-186) write continuously and will
    # keep waking it until ax is parked and those volumes are torn down or
    # moved (ruling pending: B1/C10/F2-1).
    systemd.services.hd-idle = {
      description = "Spin down the NAS HDD after 20 min idle (F2-4)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.hd-idle} -i 0 -a ${cfg.smartDevice} -i 1200";
        Restart = "on-failure";
        RestartSec = "10s";
      };
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
    # st_dev), so every crossing point is exported deliberately. The
    # strix is admitted read-write at its pinned LAN lease 10.42.0.2, and
    # since 2026-09-25 the worker read-only at 10.42.0.5 (storage root and
    # documents only; the models line lives in models.nix). Before that only
    # the strix was admitted (the
    # legacy /30 address was admitted beside it through the 2026-08-20
    # cutover and left with the tether, #264); other clients reach the relays
    # over Tailscale and the filesystem itself never leaves that one client.
    # No hostName bind: nfsd listens on the wildcard. In the /30-cable era,
    # binding 10.77.0.2 raced address assignment at boot even behind
    # network-online.target (NM reports online before the static address
    # exists — hit live on the first two post-cutover reboots: "nfsdctl:
    # Cannot assign requested address"), and a specific bind would race the
    # same way today. The nftables rule below (`ip saddr 10.42.0.2 tcp dport
    # 2049 accept`) is the actual access control.
    services.nfs.server = {
      enable = true;
      exports =
        let
          # The strix's pinned LAN lease (hosts/nas/router.nix
          # dhcp-host). Nothing else — the export ACL stays exactly as narrow
          # as the nftables rule below. The legacy /30 client that sat beside
          # it through the 2026-08-20 cutover was removed with the tether (#264).
          clients = opts: "10.42.0.2(${opts})";
        in
        # The worker (10.42.0.5, hosts/nas/router.nix dhcp-host) is a full
        # fleet member again (Tom, 2026-09-25: "the worker loan is mine, and a
        # full part of the nixos fleet"; "nas is where the pdf files are"). It
        # reads the academic-papers corpus under documents/ for the
        # academic-drain lanes (mecattaf/academic-drain, all on the worker),
        # READ-ONLY and root-squashed. The storage root is its NFSv4
        # pseudo-root (fsid=0 for this client), so `nas:/documents` and
        # `nas:/models` both resolve; models.nix carries the models line for
        # the same client (fsid=6, no longer fsid=0). Every other subvolume
        # stays invisible to it: no entry, no crossing (#131).
        ''
          ${storageRoot} ${clients "rw,sync,fsid=0,no_subtree_check,no_root_squash"}
          ${storageRoot}/photos ${clients "rw,sync,fsid=1,no_subtree_check,no_root_squash"}
          ${storageRoot}/music ${clients "rw,sync,fsid=2,no_subtree_check,no_root_squash"}
          ${storageRoot}/documents ${clients "rw,sync,fsid=3,no_subtree_check,no_root_squash"}
          ${storageRoot}/services ${clients "rw,sync,fsid=4,no_subtree_check,no_root_squash"}
          ${storageRoot}/videos ${clients "rw,sync,fsid=5,no_subtree_check,no_root_squash"}
        '';
    };
    networking.firewall.extraInputRules = ''
      ip saddr 10.42.0.2 tcp dport 2049 accept comment "NFSv4 from strix (LAN; /30 retired 2026-08-21)"
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
      # 'd' is safe here): destination of the strix-driven weekly journal
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
