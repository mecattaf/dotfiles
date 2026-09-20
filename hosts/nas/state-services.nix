{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
# ─── State services for the sandbox lane: PostgreSQL, object store, registry ─
#
# Tom, 2026-09-20: "having local kubernetes s3 or redis or postgres or
# whatever it needs on the NAS". This is that sentence, item for item, for the
# three that Agent Substrate actually reads. It is state, not compute: the
# NAS has 8 threads and 22 GiB and runs the house's DNS, so control plane and
# state live here and the machines live on the Strix boxes. Appendix J
# section 5 is the long form of that split.
#
# ── WHY THIS IS ONE FILE AND NOT THREE ────────────────────────────────────
# All three are LAN-only, all three are reached by the same two consumers
# (the k3s agents on the twins), all three land and flip together, and all
# three share one firewall block. Splitting them would mean three gates that
# are only ever flipped at once.
#
# ── THE APPLIANCE'S NO-AGENIX DOCTRINE APPLIES TO TWO OF THE THREE ────────
# ./attic.nix, #130's ruling: "a root-owned env file placed by hand (runbook
# below) keeps the appliance's no-agenix doctrine." The doctrine was never
# "no agenix here" (hosts/nas/default.nix corrects that) -- it is "no STANDING
# decryption authority over ciphertext this box never reads". The test is
# whether the secret is consumed by this host alone and whether a runbook can
# place it once.
#
#   rustfs access keys   -> runbook-placed env file. Consumed here only.
#   the atepg password   -> runbook-placed file. Consumed here only.
#   the tunnel creds     -> agenix (./cloudflared.nix), because the ciphertext
#                           has to survive a reflash and be re-minted from
#                           Tom's key, not re-typed.
#
# ── /mnt/fast IS `nofail`, AND THAT IS LETHAL FOR STATE ───────────────────
# ./disko.nix marks the 256G M.2 `nofail`, correct for a budget NVMe holding
# regenerable state. ./attic.nix learned the second edition of the
# signing-key trap the hard way: if that disk fails to mount, a StateDirectory
# cheerfully creates a fresh EMPTY tree and the service starts against it. For
# an object store that means Substrate's snapshots silently vanish; for a
# registry it means every image digest 404s mid-run. So every unit below
# carries RequiresMountsFor and refuses to start rather than inventing state.
# That is a Tuesday instead of an outage. Do not remove those lines.
#
# ── RUNBOOK — walk this before flipping the gate ──────────────────────────
#   1. Directories on the NVMe (the units will not create them; see above):
#        install -d -m 0700 -o postgres -g postgres /mnt/fast/rustfs   # no: see 2
#   2. rustfs state and its key file:
#        install -d -m 0750 -o rustfs -g rustfs /mnt/fast/rustfs
#        install -d -m 0700 root:root /var/lib/rustfs-secrets
#        printf 'RUSTFS_ACCESS_KEY=%s\nRUSTFS_SECRET_KEY=%s\n' <ak> <sk> \
#          > /var/lib/rustfs-secrets/env
#        chmod 0400 /var/lib/rustfs-secrets/env
#      Generate the pair with `openssl rand -hex 24` twice. They are NOT
#      Cloudflare credentials and have nothing to do with R2.
#   3. registry storage:
#        install -d -m 0750 -o docker-registry -g docker-registry \
#          /mnt/fast/registry
#   4. The Substrate database password (the role and database themselves are
#      declarative below; only the password is by hand, because
#      `services.postgresql.ensureUsers` deliberately cannot set one):
#        install -d -m 0700 root:root /var/lib/postgresql-secrets
#        openssl rand -hex 24 > /var/lib/postgresql-secrets/atepg-password
#        chmod 0400 /var/lib/postgresql-secrets/atepg-password
#      The oneshot below ALTERs the role from that file on every start, so
#      rotating the password is "write the file, restart the unit".
#   5. Flip myNas.stateServices.enable, deploy the NAS.
#   6. Prove each one from the coordinator:
#        psql "postgresql://atepg:$(cat …)@nas:5432/atepg?sslmode=disable" -c '\conninfo'
#        curl -sS -o /dev/null -w '%{http_code}\n' http://nas:9000/          # rustfs
#        curl -sS http://nas:5000/v2/_catalog                                # registry
#
# ── THE DSN SUBSTRATE WANTS ───────────────────────────────────────────────
# MEASURED, ~/Downloads/substrate: `cmd/ateapi/main.go:347` reads
# ATE_API_POSTGRES_CONNECTION_STRING and `:348` reads ATE_API_POSTGRES_SCHEMA
# (default "public", hack/install-ate.sh:674). The installer skips its own
# bundled PostgreSQL StatefulSet entirely when the connection string is set
# (hack/install-ate.sh:274-286). The store is pgx v5
# (cmd/ateapi/internal/store/atepg/atepg.go:36-38) and its own header comment
# says it passes "standard libpq sslmode/sslrootcert/sslcert/sslkey
# parameters" through to Connect. The upstream default DSN uses
# client-certificate auth against a projected pod certificate, which is a
# property of running PostgreSQL INSIDE the mesh; an external instance uses
# its own:
#
#   ATE_API_POSTGRES_CONNECTION_STRING=postgresql://atepg:<pw>@nas:5432/atepg?sslmode=disable
#   ATE_API_POSTGRES_SCHEMA=public
#
# `sslmode=disable` is honest rather than lazy: this is a LAN segment behind
# the house router, the traffic never leaves enp1s0, and a self-signed TLS
# layer here would add a certificate to rotate and no attacker it excludes.
# Revisit if the k3s agents ever stop being on the same wire.
#
# PEER AUTH OVER A UNIX SOCKET IS NOT AVAILABLE and was checked: ateapi runs
# as a pod on a Strix box, not on this host (the k3s server here sets
# disableAgent = true and schedules nothing), so the connection is necessarily
# TCP. That is what forces enableTCPIP and the pg_hba lines below.
#
# ── GATE OFF ──────────────────────────────────────────────────────────────
# Lands with `enable = false`. Nothing about this host changes until Tom walks
# the runbook and flips it.
let
  cfg = config.myNas.stateServices;

  fastRoot = "/mnt/fast";
  lanInterface = "enp1s0";
  lanCidr = "10.42.0.0/24";

  # Kept in lockstep with modules/k3s-fleet.nix. If those move, these move.
  podCidr = "10.200.0.0/16";

  atepgPasswordFile = "/var/lib/postgresql-secrets/atepg-password";
  rustfsEnvironmentFile = "/var/lib/rustfs-secrets/env";
in
{
  options.myNas.stateServices = {
    enable = lib.mkEnableOption "PostgreSQL/object-store/registry state services for the sandbox lane (2026-09-20 spike; Appendix J section 5)";

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "atepg";
      description = "Substrate's database on the instance this box already runs. Upstream's own name; Paperless and Immich keep theirs, untouched.";
    };

    rustfsPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "S3 API port for the object store. LAN address only, never 0.0.0.0.";
    };

    registryPort = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Container registry port. LAN address only, plain HTTP; see the k3s mirror note in modules/k3s-fleet.nix.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Immich brings PostgreSQL up on this box (./media.nix). If that ever
        # stops being true, this module is silently adding a database to
        # nothing, and the failure would show up as a Substrate install that
        # cannot reach its store rather than as a NixOS error.
        assertion = config.services.postgresql.enable;
        message = "myNas.stateServices expects the NAS's existing PostgreSQL (brought up by hosts/nas/media.nix). Enable it, or drop the Substrate database from this module.";
      }
      {
        assertion = cfg.databaseName != "paperless" && cfg.databaseName != "immich";
        message = "myNas.stateServices.databaseName must not collide with an existing database on this instance.";
      }
    ];

    # ── 1. A SECOND DATABASE ON THE INSTANCE THAT ALREADY RUNS ────────────
    # Not a second PostgreSQL. ./media.nix already put the data directory on
    # the NVMe and pinned RequiresMountsFor; this rides that, so there is one
    # instance, one dataDir, one backup story.
    services.postgresql = {
      ensureDatabases = [ cfg.databaseName ];
      ensureUsers = [
        {
          name = cfg.databaseName;
          # Substrate runs goose migrations at startup
          # (cmd/ateapi/internal/store/atepg/schema.go) and creates its own
          # tables, so it needs ownership of the database rather than grants
          # on a schema someone else owns.
          ensureDBOwnership = true;
        }
      ];

      # Forced by the shape of the deployment, not by taste: ateapi is a pod
      # on a Strix box, so there is no unix socket to peer-authenticate over.
      # This flips listen_addresses to "*" -- the nftables block at the bottom
      # of this file is the actual access control, exactly as ./paperless.nix
      # says of its own port ("the firewall rule below is the actual access
      # control").
      enableTCPIP = true;

      # mkBefore so these land ABOVE the module's own generated rules and the
      # first match wins. scram-sha-256 and never trust: the LAN is not a
      # trusted segment just because it is a LAN, and this database holds the
      # control plane's record of every sandbox.
      #
      # Both source ranges are deliberate. Cilium masquerades pod traffic
      # leaving the cluster to the node's own address, so in practice the
      # connection arrives from 10.42.0.2 or 10.42.0.5; the pod CIDR line is
      # there for the day masquerading is turned off for this destination, so
      # that change is a Cilium edit and not also a pg_hba mystery.
      authentication = lib.mkBefore ''
        host ${cfg.databaseName} ${cfg.databaseName} ${lanCidr} scram-sha-256
        host ${cfg.databaseName} ${cfg.databaseName} ${podCidr} scram-sha-256
      '';
    };

    # `ensureUsers` deliberately cannot set a password (a password in the Nix
    # store is a password in git). This is the runbook's half: read the
    # root-owned file placed by hand and ALTER the role from it. Idempotent,
    # so rotation is "write the file, restart this unit".
    systemd.services.substrate-postgres-password = {
      description = "Set the Substrate database role's password from the runbook-placed file";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      # No file, no unit: a fresh box before step 4 of the runbook stays quiet
      # rather than failing every boot.
      unitConfig.ConditionPathExists = atepgPasswordFile;
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        RemainAfterExit = true;
        # The password never reaches the command line (ps is world-readable)
        # nor the journal: it goes in through psql's stdin as a bound value.
        LoadCredential = "atepg-password:${atepgPasswordFile}";
      };
      script = ''
        set -euo pipefail
        # The password reaches psql as a bound value read from the credential
        # file, so it appears in no argv (ps is world-readable) and in no
        # journal line.
        ${config.services.postgresql.package}/bin/psql \
          --no-psqlrc --quiet --set=ON_ERROR_STOP=1 --dbname=${cfg.databaseName} <<'SQL'
        \set pw `cat "$CREDENTIALS_DIRECTORY/atepg-password"`
        ALTER ROLE ${cfg.databaseName} WITH LOGIN PASSWORD :'pw';
        SQL
      '';
    };

    # ── 2. THE OBJECT STORE ───────────────────────────────────────────────
    # Substrate selects its backend by environment, not at compile time
    # (MEASURED, cmd/atelet/main.go:226-246): ATE_STORAGE_BACKEND=s3 plus the
    # standard AWS_* variables, with AWS_S3_USE_PATH_STYLE for a non-AWS
    # endpoint. rustfs is what Substrate's own kind path uses, which keeps
    # its manifests unchanged. Note that the base atelet.yaml hardcodes "gcs"
    # and the kind overlay patches it, so a non-kind install has to carry
    # that patch.
    #
    # WHY A HAND-WRITTEN UNIT AND NOT services.rustfs: this host rides
    # nixpkgs-stable (nixos-26.05, flake.nix:37) and stable has NO rustfs at
    # all, neither module nor package. The main pin has both --
    # nixos/modules/services/web-servers/rustfs.nix and rustfs 1.0.0-beta.9
    # -- but importing one nixpkgs's module tree into another's evaluation is
    # how you get a module that references options stable does not have. So:
    # the package comes across the ./unstable-pkgs.nix seam that attic-server
    # and Immich already use, and the unit below is modelled line for line on
    # the unstable module's own serviceConfig. When the NAS next rides a
    # stable that ships the module, delete this block and use it.
    #
    # rustfs takes no flags worth the name; everything is environment.
    users.users.rustfs = {
      isSystemUser = true;
      group = "rustfs";
    };
    users.groups.rustfs = { };

    systemd.services.rustfs = {
      description = "RustFS object store (Substrate snapshot backend)";
      documentation = [ "https://rustfs.com/docs/" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        RUSTFS_VOLUMES = "${fastRoot}/rustfs";
        # The LAN address and nothing else. Binding 0.0.0.0 here would put an
        # unauthenticated-by-default object store on every interface this box
        # has, tailnet included.
        RUSTFS_ADDRESS = "10.42.0.1:${toString cfg.rustfsPort}";
        # The bundled web console is a second attack surface for a store whose
        # only client is a Go program.
        RUSTFS_CONSOLE_ENABLE = "false";
      };

      unitConfig = {
        # The /mnt/fast lesson from ./attic.nix, second edition. Without this
        # a failed NVMe mount yields an empty store and silently lost
        # snapshots instead of a service that refuses to start.
        RequiresMountsFor = [ "${fastRoot}/rustfs" ];
        # No keys, no start. The upstream module prints a warning and exits;
        # this says the same thing before the process is spawned.
        ConditionPathExists = rustfsEnvironmentFile;
      };

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        User = "rustfs";
        Group = "rustfs";
        EnvironmentFile = rustfsEnvironmentFile;
        ExecStart = lib.getExe unstablePkgs.rustfs;
        LimitNOFILE = 1048576;
        LimitNPROC = 32768;
        TasksMax = "infinity";
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "30s";
        TimeoutStopSec = "30s";
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/rustfs-secrets 0700 root root -"
      "d /var/lib/postgresql-secrets 0700 root root -"
      # NB deliberately no rule for ${fastRoot}/rustfs or ${fastRoot}/registry,
      # for ./attic.nix's reason: a tmpfiles rule would race the mount and
      # create an empty directory for a failed NVMe to find, which is the
      # silent-data-loss path this module exists to avoid. Runbook steps 2
      # and 3 create them on the real disk, once.
    ];

    # ── 3. THE REGISTRY ───────────────────────────────────────────────────
    # The Nix-built /process image and the Substrate cmd/* images have to be
    # pullable by both agents. Plain HTTP on the LAN address: see the k3s
    # mirror note below, and note that k3s's containerd needs to be told this
    # endpoint is not TLS -- that registries.yaml lives in
    # modules/k3s-fleet.nix, not here, because it is the client's problem.
    services.dockerRegistry = {
      enable = true;
      listenAddress = "10.42.0.1";
      port = cfg.registryPort;
      storagePath = "${fastRoot}/registry";
      # A spike pushes the same tag many times. Without delete plus a
      # collection pass, /mnt/fast accumulates every superseded layer forever,
      # on the 118 GiB that the object store is also growing into.
      enableDelete = true;
      enableGarbageCollect = true;
      garbageCollectDates = "weekly";
      # openFirewall is deliberately NOT used: it opens the port on every
      # interface. The interface-scoped rule at the bottom of this file is the
      # access control, same shape as ./attic.nix and ./paperless.nix.
    };
    systemd.services.docker-registry.unitConfig.RequiresMountsFor = [ "${fastRoot}/registry" ];

    # ── THE ONE FIREWALL BLOCK ────────────────────────────────────────────
    # Interface-scoped, not subnet-scoped: `iifname "enp1s0"` is the LAN leg
    # and nothing else, so none of these three is reachable over the tailnet,
    # over headscale, or through the tunnel in ./cloudflared.nix. All three
    # are unauthenticated or weakly authenticated by design and all three are
    # on the never-routed list in that file.
    networking.firewall.extraInputRules = ''
      iifname "${lanInterface}" tcp dport ${toString config.services.postgresql.settings.port} accept comment "substrate postgres, LAN leg only"
      iifname "${lanInterface}" tcp dport ${toString cfg.rustfsPort} accept comment "rustfs S3 API, LAN leg only"
      iifname "${lanInterface}" tcp dport ${toString cfg.registryPort} accept comment "container registry, LAN leg only"
    '';

    # The unstable seam this module takes. Named here so `grep unstablePkgs`
    # finds every consumer; ./unstable-pkgs.nix's header lists the others.
    warnings = lib.optional (unstablePkgs.rustfs.version or "" == "") "hosts/nas/state-services.nix: unstablePkgs.rustfs has no version attribute; the pin may have moved.";
  };
}
