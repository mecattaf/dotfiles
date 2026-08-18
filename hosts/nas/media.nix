{
  config,
  inputs,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
let
  cfg = config.myNas.media;
  # The NAS base system rides nixpkgs-stable (#135), but the Immich database
  # was created by the coordinator's unstable Immich (3.0.3 at migration time)
  # and its schema must never run under an older server (stable had 2.7.5).
  # So the media stack's version-coupled piece — Immich module + package —
  # comes from the main unstable input (`unstablePkgs`, see
  # ./unstable-pkgs.nix) and keeps riding it through the daily fleet
  # auto-update, exactly like the data expects. Navidrome, Plex, PostgreSQL 17
  # and vectorchord were identical across both pins when this was wired
  # (2026-08-02); they stay stable-sourced.
  #
  # Deliberately identical to the coordinator's historical media root. Immich
  # and Navidrome can then retain every stored absolute path after restore.
  storageRoot = "/mnt/nas";
  # The NVMe fast tier (disko.nix, 2026-08-02 role widening): database and
  # regenerable state live here for random-I/O speed and so the HDD only
  # works when actual media moves. Everything under fastRoot is either
  # rebuildable (thumbs, caches) or dump-protected onto the HDD nightly
  # (PostgreSQL via Immich's backups, Navidrome via its Backup settings) —
  # losing the budget NVMe must never cost more than a day of metadata.
  fastRoot = "/mnt/fast";
  generatedRoot = "${fastRoot}/immich-generated";
  navidromeRoot = "${fastRoot}/navidrome";
  # The nixpkgs module generates this inline inside its own ExecStart, so it
  # is not exposed anywhere reusable. Rebuilding it from the same settings and
  # the same formatter keeps the backup timer's view of DataFolder/Backup.Path
  # identical to the server's by construction.
  navidromeConfigFile =
    (pkgs.formats.json { }).generate "navidrome.json"
      config.services.navidrome.settings;
  # Shared helpers (#130); the definitions moved verbatim, so the
  # Immich/Navidrome wait scripts keep their pre-refactor store paths.
  inherit (import ./wake-helpers.nix { inherit lib pkgs; })
    socketProxyd
    waitForHttp
    proxyHardening
    ;
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

    # The database lives on the NVMe: Immich's queries (timeline, vector
    # search) are random-I/O and the HDD serviced them at rotating-disk IOPS.
    # Safety net: Immich's nightly pg_dump lands on the HDD (photos/backups,
    # see the BindPaths note below), so NVMe loss costs at most a day.
    services.postgresql.dataDir = "${fastRoot}/postgresql/${config.services.postgresql.package.psqlSchema}";
    systemd.services.postgresql.unitConfig.RequiresMountsFor = [ fastRoot ];

    systemd.tmpfiles.rules = [
      "d ${storageRoot}/photos/thumbs 0700 tom users -"
      "d ${storageRoot}/photos/encoded-video 0700 tom users -"
      "d ${storageRoot}/photos/profile 0700 tom users -"
      # REAL directory in the photos subvolume, not a bind target: DB dumps
      # write here, stay on the HDD, and ride the quarterly LaCie mirror with
      # the rest of photos/. 0755 so the postgres-owned db/ subdir (the
      # nas-db-dump target) is reachable.
      "d ${storageRoot}/photos/backups 0755 tom users -"
      "d ${storageRoot}/photos/backups/db 0700 postgres postgres -"
      "d ${generatedRoot} 0700 tom users -"
      "d ${generatedRoot}/thumbs 0700 tom users -"
      "d ${generatedRoot}/encoded-video 0700 tom users -"
      "d ${generatedRoot}/profile 0700 tom users -"
      # Both levels must pre-exist: the unit mount-namespaces the versioned
      # dataDir before ExecStartPre can initdb it, and fails NAMESPACE if the
      # directory is absent.
      "d ${fastRoot}/postgresql 0700 postgres postgres -"
      "d ${config.services.postgresql.dataDir} 0700 postgres postgres -"
      "d ${navidromeRoot} 0700 tom users -"
      "d ${navidromeRoot}/cache 0700 tom users -"
      "d ${storageRoot}/services/navidrome-backups 0700 tom users -"
      "d ${storageRoot}/services/plex 0700 tom users -"
    ];

    systemd.services.immich-server = {
      wantedBy = lib.mkForce [ ];
      requires = [ "redis-immich.service" ];
      after = [ "redis-immich.service" ];
      environment.CPU_CORES = "4";
      unitConfig = {
        StopWhenUnneeded = true;
        RequiresMountsFor = [
          storageRoot
          fastRoot
        ];
      };
      # Rebuildable generated media overlays onto the photos tree from the
      # NVMe. photos/backups is deliberately NOT bound: the nightly DB dump
      # must land on the real HDD directory (and thence the LaCie mirror),
      # not on the same NVMe it is the safety net for.
      serviceConfig.BindPaths = [
        "${generatedRoot}/thumbs:${storageRoot}/photos/thumbs"
        "${generatedRoot}/encoded-video:${storageRoot}/photos/encoded-video"
        "${generatedRoot}/profile:${storageRoot}/photos/profile"
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
      serviceConfig = proxyHardening // {
        ExecStartPre = waitForHttp "Immich" "http://127.0.0.1:2284/api/server/ping";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:2284";
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
        # No automatic scanning at all: ~34k tracks that change maybe once a
        # year, on a spinning disk hd-idle parks after 20 min. Scans are
        # requested by hand — `mscan` (the navidrome-scan fish function, which
        # calls /rest/startScan) or the web UI's Scan button — after a beets run.
        Scanner = {
          # The master switch, and the only one that is strictly necessary:
          # cmd/root.go:92-97 wraps BOTH startScanWatcher and
          # schedulePeriodicScan in `if conf.Server.Scanner.Enabled`, logging
          # "Automatic Scanning is DISABLED" instead. Manual scans are
          # unaffected — the /rest/startScan handler in
          # server/subsonic/library_scanning.go never consults this flag (nor
          # does anything under scanner/), so `mscan` keeps working.
          Enabled = false;
          # The three individual triggers, set explicitly as well. Redundant
          # while Enabled is false, but each is the thing that actually has to
          # be off, and spelling them out means a future upstream change to the
          # Enabled gate cannot quietly re-enable one of them.
          #
          # Periodic rescan cron; "0" disables. This was written as a top-level
          # `ScanSchedule = "@daily"` from 2026-07-13 to 2026-08-18 — not a key
          # Navidrome has, and absent from its deprecation map, so it was
          # dropped on the floor and the schedule sat at its default the entire
          # time. The daily scan that comment described never once ran.
          Schedule = "0";
          # Rescan ~2s after every process start (cmd/root.go:197, gated on
          # Enabled && ScanOnStartup). Upstream defaults this to TRUE, and this
          # is what was actually firing: the service is socket-activated,
          # StopWhenUnneeded, behind a proxy that exits after 15 min idle, so
          # it restarts constantly and every cliamp launch or web-UI visit
          # after a quiet spell triggered a full 34k-file walk. One was watched
          # taking 9+ minutes on 2026-08-18.
          ScanOnStartup = false;
          # Live inotify watcher over MusicFolder, debouncing filesystem events
          # into automatic scans (scanner/watcher.go). Gated ONLY on this
          # duration being zero (cmd/root.go:229-232); upstream's default is
          # consts.DefaultWatcherWait = 5s, i.e. ON. Pointless on a static tree
          # and it holds watches across a disk meant to stay spun down.
          WatcherWait = "0s";
        };
        LogLevel = "info";
        SessionTimeout = "168h";
        AutoImportPlaylists = true;
        # State is on the NVMe; the nightly SQLite backup is its HDD safety
        # net, same doctrine as the Immich dump. Path and Count stay — the
        # navidrome-backup timer below reads both — but Schedule is empty on
        # purpose. Navidrome registers it with an in-process robfig/cron
        # instance (cmd/root.go schedulePeriodicBackup) that only ticks while
        # the process is alive, and this one is socket-activated with
        # StopWhenUnneeded behind a proxy that exits after 15 min idle. It was
        # therefore asleep at essentially every firing and the "nightly"
        # backup had no catch-up, so it silently almost never ran — the exact
        # failure the nas-db-dump timer below already exists to avoid for
        # Postgres. Driven by systemd now, for the same reason.
        Backup = {
          Path = "${storageRoot}/services/navidrome-backups";
          Schedule = "";
          Count = 14;
        };
      };
    };
    systemd.services.navidrome = {
      wantedBy = lib.mkForce [ ];
      unitConfig = {
        RequiresMountsFor = [
          storageRoot
          fastRoot
        ];
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
      serviceConfig = proxyHardening // {
        ExecStartPre = waitForHttp "Navidrome" "http://127.0.0.1:4534/";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:4534";
      };
    };

    # Nightly Navidrome SQLite backup, driven by systemd rather than by the
    # server's own scheduler — see the Backup block above for why that one
    # could not be relied on. `backup create` then `backup prune` mirrors what
    # the in-process job did (create ignores Count; prune is what applies it).
    # Same --configfile expression the module builds for the server, so the
    # two can never disagree about DataFolder or Backup.Path.
    systemd.services.navidrome-backup = {
      description = "Nightly Navidrome database backup to the HDD";
      unitConfig.RequiresMountsFor = [
        storageRoot
        fastRoot
      ];
      serviceConfig = {
        Type = "oneshot";
        # Same identity as the server: DataFolder on the NVMe and the backup
        # directory are both tom-owned 0700.
        User = "tom";
        Group = "users";
        ExecStart = [
          "${lib.getExe config.services.navidrome.finalPackage} --configfile ${navidromeConfigFile} backup create"
          "${lib.getExe config.services.navidrome.finalPackage} --configfile ${navidromeConfigFile} backup prune"
        ];
      };
    };
    systemd.timers.navidrome-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Offset from nas-db-dump's 02:15 so the two do not contend for the
        # HDD, and Persistent so a powered-off night is caught up on boot.
        OnCalendar = "*-*-* 02:45:00";
        Persistent = true;
      };
    };

    # Independent nightly DB dump to the HDD. Immich has its own nightly
    # backup, but it runs inside immich-server — which is socket-activated
    # and asleep most nights, so it cannot be the safety net for the NVMe
    # dataDir. This timer talks straight to PostgreSQL. Dumps land in the
    # real photos/backups (HDD + quarterly LaCie mirror); 14 kept, matching
    # Immich's own retention.
    systemd.services.nas-db-dump = {
      description = "Nightly pg_dump of the media database to the HDD";
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
      unitConfig.RequiresMountsFor = [ storageRoot ];
      # Root, not User=postgres: photos/ is tom 0700 and the dump target must
      # stay inside the mirrored photos tree, so the shell runs as root (which
      # traverses) and only the pg_dump itself drops to postgres for peer auth.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nas-db-dump" ''
          set -eu
          out="${storageRoot}/photos/backups/db/nas-pg-dump-$(date +%Y%m%dT%H%M%S).sql.gz"
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/pg_dump --clean --if-exists tom \
            | ${pkgs.gzip}/bin/gzip > "$out"
          ls -1t ${storageRoot}/photos/backups/db/nas-pg-dump-*.sql.gz \
            | tail -n +15 | ${pkgs.findutils}/bin/xargs -r rm --
        '';
      };
    };
    systemd.timers.nas-db-dump = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 02:15:00";
        Persistent = true;
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
