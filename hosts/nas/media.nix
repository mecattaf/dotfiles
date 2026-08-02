{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.media;
  # The NAS base system rides nixpkgs-stable (#135), but the Immich database
  # was created by the coordinator's unstable Immich (3.0.3 at migration time)
  # and its schema must never run under an older server (stable had 2.7.5).
  # So the media stack's version-coupled piece — Immich module + package —
  # comes from the main unstable input and keeps riding it through the daily
  # fleet auto-update, exactly like the data expects. Navidrome, Plex,
  # PostgreSQL 17 and vectorchord were identical across both pins when this
  # was wired (2026-08-02); they stay stable-sourced.
  unstablePkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  # Deliberately identical to the coordinator's historical media root. Immich
  # and Navidrome can then retain every stored absolute path after restore.
  storageRoot = "/mnt/nas";
  generatedRoot = "${storageRoot}/services/immich-generated";
  navidromeRoot = "${storageRoot}/services/navidrome";
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
  waitForHttp =
    name: url:
    pkgs.writeShellScript "${name}-wait-for-http" ''
      for _ in $(${pkgs.coreutils}/bin/seq 1 90); do
        if ${pkgs.curl}/bin/curl --fail --silent --max-time 1 ${lib.escapeShellArg url} >/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "${name} did not become ready within 90 seconds" >&2
      exit 1
    '';
in
{
  # Swap in the unstable Immich module unconditionally (imports cannot depend
  # on cfg.enable); it stays inert while services.immich.enable is false.
  disabledModules = [ "services/web-apps/immich.nix" ];
  imports = [ "${inputs.nixpkgs}/nixos/modules/services/web-apps/immich.nix" ];

  options.myNas.media.enable = lib.mkEnableOption "Immich, Navidrome, and Plex on the verified NAS data disk";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.media requires the verified myNas.storage mount";
      }
    ];

    services.immich = {
      enable = true;
      package = unstablePkgs.immich;
      mediaLocation = "${storageRoot}/photos";
      host = "127.0.0.1";
      port = 2284;
      user = "tom";
      group = "users";
      database.user = "tom";
      database.name = "tom";
      machine-learning.enable = false;
      # Keep Smart Search and Face Detection on the much faster coordinator.
      # This endpoint is reachable only over the dedicated private link.
      environment.IMMICH_MACHINE_LEARNING_URL = lib.mkForce "http://coordinator:3003";
      accelerationDevices = [ "/dev/dri/renderD128" ];
    };

    # Database and rebuildable media state belong on the HDD, not the 64 GB eMMC.
    services.postgresql.dataDir = "${storageRoot}/services/postgresql/${config.services.postgresql.package.psqlSchema}";
    systemd.services.postgresql.unitConfig.RequiresMountsFor = [ storageRoot ];

    systemd.tmpfiles.rules = [
      "d ${storageRoot}/photos/thumbs 0700 tom users -"
      "d ${storageRoot}/photos/encoded-video 0700 tom users -"
      "d ${storageRoot}/photos/profile 0700 tom users -"
      "d ${storageRoot}/photos/backups 0700 tom users -"
      "d ${generatedRoot} 0700 tom users -"
      "d ${generatedRoot}/thumbs 0700 tom users -"
      "d ${generatedRoot}/encoded-video 0700 tom users -"
      "d ${generatedRoot}/profile 0700 tom users -"
      "d ${generatedRoot}/backups 0700 tom users -"
      # Both levels must pre-exist: the unit mount-namespaces the versioned
      # dataDir before ExecStartPre can initdb it, and fails NAMESPACE if the
      # directory is absent.
      "d ${storageRoot}/services/postgresql 0700 postgres postgres -"
      "d ${config.services.postgresql.dataDir} 0700 postgres postgres -"
      "d ${navidromeRoot} 0700 tom users -"
      "d ${navidromeRoot}/cache 0700 tom users -"
      "d ${storageRoot}/services/plex 0700 tom users -"
    ];

    systemd.services.immich-server = {
      wantedBy = lib.mkForce [ ];
      requires = [ "redis-immich.service" ];
      after = [ "redis-immich.service" ];
      environment.CPU_CORES = "4";
      unitConfig = {
        StopWhenUnneeded = true;
        RequiresMountsFor = [ storageRoot ];
      };
      serviceConfig.BindPaths = [
        "${generatedRoot}/thumbs:${storageRoot}/photos/thumbs"
        "${generatedRoot}/encoded-video:${storageRoot}/photos/encoded-video"
        "${generatedRoot}/profile:${storageRoot}/photos/profile"
        "${generatedRoot}/backups:${storageRoot}/photos/backups"
      ];
    };
    systemd.services.redis-immich = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };

    systemd.sockets.immich-access = {
      description = "Wake NAS Immich on the first client connection";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:2283";
        NoDelay = true;
      };
    };
    systemd.services.immich-access = {
      description = "On-demand proxy for NAS Immich";
      requires = [ "immich-server.service" ];
      after = [ "immich-server.service" ];
      serviceConfig = {
        ExecStartPre = waitForHttp "Immich" "http://127.0.0.1:2284/api/server/ping";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:2284";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        TimeoutStartSec = "2min";
      };
    };

    services.navidrome = {
      enable = true;
      user = "tom";
      group = "users";
      settings = {
        MusicFolder = "${storageRoot}/music";
        DataFolder = navidromeRoot;
        CacheFolder = "${navidromeRoot}/cache";
        Address = "127.0.0.1";
        Port = 4534;
        ScanSchedule = "@daily";
        LogLevel = "info";
        SessionTimeout = "168h";
        AutoImportPlaylists = true;
      };
    };
    systemd.services.navidrome = {
      wantedBy = lib.mkForce [ ];
      unitConfig = {
        RequiresMountsFor = [ storageRoot ];
        StopWhenUnneeded = true;
      };
    };
    systemd.sockets.navidrome-access = {
      description = "Wake NAS Navidrome on the first client connection";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:4533";
        NoDelay = true;
      };
    };
    systemd.services.navidrome-access = {
      description = "On-demand proxy for NAS Navidrome";
      requires = [ "navidrome.service" ];
      after = [ "navidrome.service" ];
      serviceConfig = {
        ExecStartPre = waitForHttp "Navidrome" "http://127.0.0.1:4534/";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:4534";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        TimeoutStartSec = "2min";
      };
    };

    # Plex serves the videos subvolume (Tom's 2026-08-02 call: Plex over
    # Jellyfin). Unlike Immich/Navidrome it stays resident — Plex keeps
    # long-lived plex.tv sessions and library state that socket activation
    # would thrash. Reachable only through the coordinator's 32400 relay.
    # No hardware-transcode config until a Plex Pass exists (precondition
    # not true yet); CPU direct-play/remux is the baseline.
    services.plex = {
      enable = true;
      user = "tom";
      group = "users";
      dataDir = "${storageRoot}/services/plex";
    };
    systemd.services.plex.unitConfig.RequiresMountsFor = [ storageRoot ];

    networking.firewall.extraInputRules = ''
      ip saddr 10.77.0.1 tcp dport { 2283, 4533, 32400 } accept comment "media from coordinator"
    '';
  };
}
