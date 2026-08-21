{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Paperless-ngx v3 as the human-facing PDF catalog (#136): a same-inode
# PROJECTION of the canonical /mnt/nas/documents tree, never a second payload
# copy. The stable-pinned NAS gets module AND package from the dedicated
# `nixpkgs-paperless` input (pinned nixos-unstable rev, paperless-ngx 3.0.4
# from upstream tag v3.0.4, src sha256-3gQtrafqr0avRkFCIlvu7apk2NUNVOFxkdhFE
# USCz9I=) — v3 only, never the stable 2.x; upgrades happen by bumping that
# one input deliberately, not by riding a rolling resolver (a database with
# schema migrations must not auto-upgrade nightly like nixpkgs-fresh's
# browser charter allows).
#
# Storage contract (constrains #130 subvolume decisions, already satisfied:
# documents/ is one subvolume):
#   /mnt/nas/documents/...                    canonical originals (tom-owned)
#   /mnt/nas/documents/.paperless-view        Paperless originals dir — every
#                                             file here is a HARDLINK to a
#                                             canonical inode after relink
#   /mnt/nas/documents/.paperless-consume     hardlink staging spool
#   /mnt/nas/services/paperless/...           service state, db dumps, bridge
#                                             ledger (separate subvolume)
#   /mnt/nas/views/paperless                  read-only browsable bind of the
#                                             view tree
# All three document-side paths are inside the documents subvolume because
# hardlinks cannot cross Btrfs subvolumes.
#
# Always-on exception (documented per the StopWhenUnneeded doctrine): unlike
# Immich/Navidrome, Paperless keeps a consumer watching the spool and a
# scheduler running maintenance, so socket activation would thrash it. Idle
# RSS on the 8 GB box is a gate-flip validation measurement.
#
# Gate-flip runbook (walk on the real hardware, then flip
# myNas.paperless.enable and invert the checks in flake.nix):
#   1. mkdir the runbook dirs (tmpfiles 'z'-only doctrine, storage.nix):
#        mkdir -m 750 /mnt/nas/documents/.paperless-view    (chown paperless)
#        mkdir -m 770 /mnt/nas/documents/.paperless-consume (chown tom:paperless)
#        mkdir -m 755 /mnt/nas/views
#   2. deploy; verify paperless-web answers on 10.77.0.2:28981 from the
#      coordinator only, and http://paperless.internal works from a tailnet
#      client with auto-login (needs myNasClient.relayPaperless flipped in
#      the same commit — the checks pair them).
#   3. mint the bridge API token:
#        paperless-manage drf_create_token tom \
#          > /mnt/nas/services/paperless/bridge/api-token   (0600 tom)
#   4. canary corpus admission per #136 §4: paperless-bridge scan / ingest
#      --batch 4 / relink / verify on one born-digital academic, one scanned
#      academic, one legacy scan, one general PDF; prove identical sha256 AND
#      identical st_dev:st_ino for canonical + projected paths.
#   5. measure idle/import RSS + disk wakeups alongside Immich/Navidrome
#      before bulk admission; bulk-ingest in bounded batches afterwards.
#   6. (future AI phase only) the coordinator's llama-swap endpoint is already
#      reachable from here at http://coordinator:9292 over the /30 cable —
#      modules/llama-swap.nix admits enp191s0 explicitly. An earlier revision
#      of this comment claimed the opposite ("tailnet0 ONLY ... the NAS cannot
#      reach 10.77.0.1:9292"); that was never true — the cable was blanket-
#      trusted then and is explicitly admitted now — and it misled readers into
#      believing the LLM plane had a Tailscale dependency. Nothing in v1 uses
#      it regardless (PAPERLESS_AI_ENABLED=false, enrich reads files + the
#      local API); turn it on with the #136 AI-batching admission design, but
#      the firewall is not what is stopping you.
let
  cfg = config.myNas.paperless;
  storageRoot = "/mnt/nas";
  documentsRoot = "${storageRoot}/documents";
  serviceRoot = "${storageRoot}/services/paperless";
  viewDir = "${documentsRoot}/.paperless-view";
  spoolDir = "${documentsRoot}/.paperless-consume";
  # Lazy: only forced when the gate is on.
  paperlessPkgs = import inputs.nixpkgs-paperless {
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  bridge = pkgs.callPackage ../../pkgs/paperless-bridge { };
  paperlessUnits = [
    "paperless-scheduler.service"
    "paperless-consumer.service"
    "paperless-web.service"
    "paperless-task-queue.service"
  ];
in
{
  # Swap in the v3-era module unconditionally (imports cannot depend on
  # cfg.enable); it stays inert while services.paperless.enable is false.
  # Same pattern as the unstable Immich swap in ./media.nix.
  disabledModules = [ "services/misc/paperless.nix" ];
  imports = [ "${inputs.nixpkgs-paperless}/nixos/modules/services/misc/paperless.nix" ];

  options.myNas.paperless.enable = lib.mkEnableOption "Paperless-ngx v3 as the same-inode PDF projection of /mnt/nas/documents (#136)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.paperless requires the verified myNas.storage mount";
      }
      {
        assertion = lib.versionAtLeast config.services.paperless.package.version "3";
        message = "myNas.paperless is a v3-only deployment (#136); a 2.x package means the nixpkgs-paperless input regressed";
      }
    ];

    services.paperless = {
      enable = true;
      package = paperlessPkgs.paperless-ngx;
      dataDir = "${serviceRoot}/data";
      mediaDir = "${serviceRoot}/media";
      consumptionDir = spoolDir;
      # The bridge (running as tom) hardlinks into the spool; this keeps the
      # module from clamping the directory to the service user.
      consumptionDirIsPublic = true;
      # Wildcard bind + nftables scoping, NOT a 10.77.0.2 bind: binding the
      # cable address raced address assignment at boot (hit live on nfsd,
      # storage.nix). The firewall rule below is the actual access control.
      address = "0.0.0.0";
      port = 28981;
      passwordFile = "${serviceRoot}/admin-password";
      database.createLocally = true;
      # configureTika stays default-false: no Tika/Gotenberg, PDFs only (#136).
      settings = {
        PAPERLESS_ADMIN_USER = "tom";
        # Tailscale is the access boundary; auto-login only removes the second
        # UI login, everything else (secret key, admin bootstrap, API tokens,
        # CSRF) stays real.
        PAPERLESS_AUTO_LOGIN_USERNAME = "tom";
        PAPERLESS_URL = "http://paperless.internal";
        PAPERLESS_ALLOWED_HOSTS = "paperless.internal,nas,10.77.0.2,127.0.0.1,localhost";
        PAPERLESS_CSRF_TRUSTED_ORIGINS = "http://paperless.internal";
        # Embedded text is extracted directly; only true scans get the cheap
        # Tesseract baseline — and no PDF/A twin is ever persisted. The web
        # viewer serves the original (= canonical) bytes.
        PAPERLESS_OCR_MODE = "auto";
        PAPERLESS_ARCHIVE_FILE_GENERATION = "never";
        # Defer the LLM/vector index: it is built once, deliberately, after
        # the bulk enrichment pass converges (#136), and any AI runs through
        # coordinator llama-swap — never model weights on this box.
        PAPERLESS_AI_ENABLED = false;
        # 8 GB box shared with Immich/Navidrome/Plex: modest fixed concurrency.
        PAPERLESS_TASK_WORKERS = 1;
        PAPERLESS_THREADS_PER_WORKER = 2;
        PAPERLESS_WEBSERVER_WORKERS = 2;
        # Browsable view-tree paths for the projection (storage-path renames
        # move only the hardlink directory entry; canonical never moves).
        PAPERLESS_FILENAME_FORMAT = "{{ document_type }}/{{ created_year }}/{{ title }}";
      };
    };

    # Paperless's "originals" are the hidden view tree on the documents
    # subvolume, so the relink helper can hardlink them to canonical inodes.
    # Thumbnails and the rest of mediaDir stay real service state.
    fileSystems."${serviceRoot}/media/documents/originals" = {
      device = viewDir;
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.requires-mounts-for=${storageRoot}"
      ];
    };
    # Human-browsable, read-only face of the projection.
    fileSystems."${storageRoot}/views/paperless" = {
      device = viewDir;
      fsType = "none";
      options = [
        "bind"
        "ro"
        "nofail"
        "x-systemd.requires-mounts-for=${storageRoot}"
      ];
    };

    systemd.services =
      lib.genAttrs (map (lib.removeSuffix ".service") paperlessUnits) (_: {
        unitConfig.RequiresMountsFor = [ storageRoot ];
      })
      // {
        # First-boot admin credential, generated on the box like the module's
        # own secret key — never a committed secret (mySecrets stays off, #136).
        paperless-admin-password = {
          description = "Generate the Paperless admin bootstrap password once";
          wantedBy = [ "multi-user.target" ];
          before = paperlessUnits;
          unitConfig.RequiresMountsFor = [ storageRoot ];
          serviceConfig.Type = "oneshot";
          script = ''
            f='${serviceRoot}/admin-password'
            if [ ! -s "$f" ]; then
              (umask 077; ${pkgs.openssl}/bin/openssl rand -base64 24 > "$f")
              chown ${config.services.paperless.user}:${config.services.paperless.user} "$f"
            fi
          '';
        };

        # Nightly pg_dump of the paperless DB to the HDD services subvolume,
        # same doctrine and retention as nas-db-dump in ./media.nix (the
        # postgres dataDir lives on the NVMe fast tier). The full
        # document-exporter snapshot is deliberately NOT enabled here: with
        # originals it would be a same-disk payload copy of the whole corpus —
        # it belongs on the #130 backup target when that gate flips.
        paperless-db-dump = {
          description = "Nightly pg_dump of the paperless database to the HDD";
          requires = [ "postgresql.service" ];
          after = [ "postgresql.service" ];
          unitConfig.RequiresMountsFor = [ storageRoot ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "paperless-db-dump" ''
              set -eu
              out="${serviceRoot}/backups/db/paperless-pg-dump-$(date +%Y%m%dT%H%M%S).sql.gz"
              ${pkgs.util-linux}/bin/runuser -u postgres -- \
                ${config.services.postgresql.package}/bin/pg_dump --clean --if-exists paperless \
                | ${pkgs.gzip}/bin/gzip > "$out"
              ls -1t ${serviceRoot}/backups/db/paperless-pg-dump-*.sql.gz \
                | tail -n +15 | ${pkgs.findutils}/bin/xargs -r rm --
            '';
          };
        };
      };
    systemd.timers.paperless-db-dump = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 02:45:00";
        Persistent = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${serviceRoot} 0711 root root -"
      "d ${serviceRoot}/backups 0700 root root -"
      "d ${serviceRoot}/backups/db 0700 postgres postgres -"
      # Bridge state (ledger, receipts, token, accepted-tag sidecars) is
      # tom's: the bridge runs unprivileged; only the relink helper is root.
      "d ${serviceRoot}/bridge 0700 tom users -"
      "d ${storageRoot}/views 0755 root root -"
      # Runbook-created ('z' adjust-only, storage.nix doctrine — a 'd' here
      # could silently precede the documents subvolume mount):
      "z ${viewDir} 0750 ${config.services.paperless.user} ${config.services.paperless.user} -"
      "z ${spoolDir} 0770 tom ${config.services.paperless.user} -"
    ];

    # The bridge CLI and its narrow root helper. The sudo rule is the entire
    # privilege surface: tom may run exactly this helper as root, which
    # itself refuses anything not ledger-known, allowlisted, and
    # hash-identical (pkgs/paperless-bridge/relink-helper.py).
    environment.systemPackages = [ bridge ];
    security.sudo.extraRules = [
      {
        users = [ "tom" ];
        commands = [
          {
            command = "${bridge}/bin/paperless-relink-helper";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Backend admitted only from the coordinator's end of the /30 cable; the
    # tailnet reaches it through the coordinator relay + Caddy front door.
    networking.firewall.extraInputRules = ''
      ip saddr 10.42.0.2 tcp dport 28981 accept comment "paperless from coordinator (LAN; /30 retired 2026-08-21)"
    '';
  };
}
