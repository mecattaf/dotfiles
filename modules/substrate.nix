{
  config,
  lib,
  pkgs,
  ...
}:
# services.substrate: the coordinator's two box-side programs of the Cloudflare Substrate, declared ON on the
# coordinator since 2026-09-24.
#
# CODE: pkgs/substrate-apps (vendored from agency-agency/substrate at the sha in its SYNC.md). ARCHITECTURE:
# ~/today/wednesday-prep-2026-09-23/03-substrate-ax-conwip.md section 2. RULING: E1 (2026-09-23), the code that
# wraps ax lives in dotfiles; A2, the NAS link, the coordinator puller and the capacity pusher are dotfiles
# packages and modules. The NAS side is hosts/nas/substrate-link.nix (Lane A); this file is the coordinator side.
#
#   pusher  reads `seats --json --no-spend` (the box's one capacity oracle, ~/.local/bin/seats) under the gentle
#           policy (120 s floor, 900 s idle, 300 s active, 180 s above 85 percent, one read at reset + 90 s) and
#           posts seat-capacity/2 snapshots to the floor's POST /capacity/snapshots. A dead pusher fails closed
#           at the floor: readings grade STALE after 1200 s and admission stops.
#   puller  the interpreter host: leases runs (runtime:interpreter) from the floor with its per-link token, runs
#           each workflow's agent() calls on the runtimes this module renders into runtimes.toml (opus, halogen,
#           codex, codex-rw: all host runtimes, the shape proven live on 2026-09-24), each claude seat spending
#           its own config dir by path ([credentials.seats], RG-1), heartbeats, completes, resumes from the run's
#           journal. Its config is the [puller] table of a client config.toml (packages/api/src/config.ts),
#           rendered here with placeholders for the two credential paths and filled at unit start.
#
# WHY USER UNITS. Both programs speak for Tom's logins: `seats` reads each Claude seat's OAuth usage from its
# config dir, and the puller runs claude, herdr and ssh as Tom. A system unit with User=tom would carry none of
# the session (herdr socket, ssh agent, XDG dirs). ConditionUser pins each unit to that one user's manager.
#
# NO runtime-test WRAPPER. The hand-started proof (2026-09-23/24) ran both programs inside ~/.local/bin/runtime-test,
# which is a test harness: a private /run/user and PID/IPC namespaces. A unit is not a test. The puller runs on the
# user manager with the real /run/user so herdr's socket and the ssh agent stay reachable, and the host runtimes
# see the same session a login shell does (runtimeTestWrapper stays available, off, for the microvm runtime).
# Consequence at cutover: the hand-started processes wrote their pidfiles from inside the namespace, so
# ~/.local/state/substrate/puller.pid holds namespace pid 2. Seen from the host, pid 2 is a kernel thread the puller
# cannot signal (EPERM), which apps/puller/src/pidfile.ts counts as alive, so the unit would exit 3 until that
# pidfile is removed. Retire the nohup processes first (SIGTERM their HOST pids, RUN.md), then remove
# ~/.local/state/substrate/{puller,pusher}.pid, then start the units.
#
# THE TOKENS ARE PATHS, NEVER VALUES. The floor's operator bearer (FLOOR_TOKEN) and the puller's per-link token
# (one entry of the floor's LINK_TOKENS, bound to `holder`) are agenix secrets, decrypted at /run/agenix/<name>
# for the user (owner = user, 0400), and handed to each unit as private copies by LoadCredential; the pusher gets
# `--token-file %d/floor-token`, the puller a config.toml and a substrate.json written into its RuntimeDirectory
# at start with `$CREDENTIALS_DIRECTORY/floor-token` and `.../link-token` as token_file, link_token_file and
# capacityFloorTokenFile. Nothing here reads, prints or interpolates a value; every rendered file carries paths.
# Minting (wrangler secret put FLOOR_TOKEN and LINK_TOKENS, the two age files) is Tom's hand.
#
# THE GATE. Both `enable`s default to false. hosts/coordinator sets both true as of 2026-09-24, replacing the
# hand-started processes of ~/today/wednesday-prep-2026-09-23/substrate (RUN.md), with the floor live at floorUrl
# and the two tokens sealed as secrets/substrate-floor-token.age and secrets/substrate-link-token-coordinator.age
# (secrets.nix, editors ++ coordinatorOnly). The rendered files match that proven deployment: prove/runtimes.toml,
# prove/client.config.toml, tom.pusher.config.json and tom.substrate.config.json (axProtoFallbackPath excepted:
# null here, the vendored ax.proto). tests/substrate-modules renders both units armed with fixtures, so the shape is
# proven at evaluation time without a token on disk.
let
  cfg = config.services.substrate;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  substrateApps = pkgs.callPackage ../pkgs/substrate-apps { };
  home = config.users.users.${cfg.user}.home;
  tomlFormat = pkgs.formats.toml { };
  anyEnabled = cfg.pusher.enable || cfg.puller.enable;
  credentialPath = config.age.secrets.${cfg.tokenSecret}.path;

  # The pusher's config file: apps/pusher/pusher.example.json shape, minus tokenFile (given as --token-file).
  pusherConfig = pkgs.writeText "substrate-pusher.json" (
    builtins.toJSON (
      {
        floorUrl = cfg.floorUrl;
        seatsBin = cfg.pusher.seatsBin;
        host = cfg.pusher.host;
        seats = cfg.pusher.seats;
        seatIds = cfg.pusher.seatIds;
        owners = cfg.pusher.owners;
        not_dispatchable = cfg.pusher.notDispatchable;
        plans = cfg.pusher.plans;
        slots = cfg.pusher.slots;
        estimatedProviders = cfg.pusher.estimatedProviders;
        peerCacheDir = cfg.pusher.peerCacheDir;
      }
      // cfg.pusher.extraConfig
    )
  );

  runtimesToml = tomlFormat.generate "substrate-runtimes.toml" cfg.puller.runtimes;

  # The deploy config (src/deploy-config.ts) with the bearer path left as a placeholder; the unit fills it from
  # $CREDENTIALS_DIRECTORY at start, into its RuntimeDirectory, so no path to a credential is guessed at eval.
  deployConfigTemplate = pkgs.writeText "substrate.json.in" (
    builtins.toJSON (
      cfg.puller.deployConfig
      // {
        capacityFloorUrl = cfg.floorUrl;
        capacityFloorTokenFile = "@FLOOR_TOKEN_FILE@";
      }
    )
  );

  # The client config (packages/api/src/config.ts, deploy/client.config.example.toml): the floor, WHERE each
  # credential is, and the [puller] table. Both token paths are placeholders until unit start.
  clientConfigTemplate = tomlFormat.generate "substrate-client.toml.in" ({
    floor_url = cfg.floorUrl;
    token_file = "@FLOOR_TOKEN_FILE@";
    puller = {
      holder = cfg.puller.holder;
      link_token_file = "@LINK_TOKEN_FILE@";
      state_dir = cfg.puller.stateDir;
      pidfile = cfg.puller.pidfile;
      max_runs = cfg.puller.maxRuns;
      node_dispatch = cfg.puller.nodeDispatch;
      runtimes = "${runtimesToml}";
      seat = cfg.puller.claudeSeat;
      cap = cfg.puller.cap;
      default_model = cfg.puller.defaultModel;
      node_runs_on = cfg.puller.nodeRunsOn;
      demand_dir = cfg.puller.demandDir;
      drain_timeout_s = cfg.puller.drainTimeoutS;
      capacity_wait_s = cfg.puller.capacityWaitS;
    }
    // lib.optionalAttrs (cfg.puller.axServer != null) { ax_server = cfg.puller.axServer; }
    // lib.optionalAttrs (cfg.puller.healthAddr != null) { health_addr = cfg.puller.healthAddr; };
  });

  pullerExec = lib.escapeShellArgs (
    lib.optionals (cfg.puller.runtimeTestWrapper != null) [
      cfg.puller.runtimeTestWrapper
      "--"
    ]
    ++ [ (lib.getExe cfg.puller.package) ]
  );

  pullerStart = pkgs.writeShellScript "substrate-puller-start" ''
    set -euo pipefail
    : "''${CREDENTIALS_DIRECTORY:?substrate-puller needs LoadCredential (no CREDENTIALS_DIRECTORY)}"
    : "''${RUNTIME_DIRECTORY:?substrate-puller needs RuntimeDirectory}"
    token="$CREDENTIALS_DIRECTORY/floor-token"
    link="$CREDENTIALS_DIRECTORY/link-token"
    test -r "$token" || { echo "substrate-puller: no floor-token credential" >&2; exit 78; }
    test -r "$link" || { echo "substrate-puller: no link-token credential" >&2; exit 78; }
    umask 077
    ${pkgs.gnused}/bin/sed "s|@FLOOR_TOKEN_FILE@|$token|" ${deployConfigTemplate} > "$RUNTIME_DIRECTORY/substrate.json"
    ${pkgs.gnused}/bin/sed -e "s|@FLOOR_TOKEN_FILE@|$token|" -e "s|@LINK_TOKEN_FILE@|$link|" ${clientConfigTemplate} > "$RUNTIME_DIRECTORY/config.toml"
    export SUBSTRATE_CONFIG="$RUNTIME_DIRECTORY/substrate.json"
    export SUBSTRATE_CLIENT_CONFIG="$RUNTIME_DIRECTORY/config.toml"
    # [puller].runtimes is the primary; loadRuntimes (packages/runners/src/config.ts) still falls back to this.
    export AX_CONWIP_RUNTIMES=${runtimesToml}
    exec ${pullerExec}
  '';

  commonService = {
    Restart = "on-failure";
    RestartSec = "30s";
    TimeoutStopSec = "30s";
    UMask = "0077";
    NoNewPrivileges = true;
    LoadCredential = [ "floor-token:${credentialPath}" ];
  };
in
{
  options.services.substrate = {
    user = mkOption {
      type = types.str;
      default = "tom";
      description = "The login whose user manager runs both units and whose seats they speak for.";
    };

    floorUrl = mkOption {
      type = types.str;
      default = "";
      example = "https://substrate.example.dev";
      description = "The floor Worker's base URL. HTTPS only; the bearer never travels in clear.";
    };

    tokenSecret = mkOption {
      type = types.str;
      default = "substrate-floor-token";
      description = "The agenix secret NAME holding the floor's operator bearer (FLOOR_TOKEN). Declared by this module when a unit is enabled, decrypted for `user`, handed to each unit as the credential `floor-token`. A name, never a value.";
    };

    tokenAgeFile = mkOption {
      type = types.path;
      default = ../secrets/substrate-floor-token.age;
      defaultText = lib.literalExpression "../secrets/substrate-floor-token.age";
      description = "The sealed bearer (secrets.nix: editors ++ the coordinator key). Evaluated only when a unit is enabled.";
    };

    pusher = {
      enable = mkEnableOption "the gentle capacity pusher (seats --json to the floor). ON on the coordinator; see this file's header";

      package = mkOption {
        type = types.package;
        default = substrateApps.pusher;
        defaultText = lib.literalExpression "(pkgs.callPackage ../pkgs/substrate-apps { }).pusher";
        description = "The pusher, built from pkgs/substrate-apps/src/apps/pusher.";
      };

      configFile = mkOption {
        type = types.path;
        readOnly = true;
        default = pusherConfig;
        description = "The rendered pusher.json (read-only; for tests).";
      };

      seatsBin = mkOption {
        type = types.str;
        default = "${home}/.local/bin/seats";
        defaultText = lib.literalExpression ''"''${home}/.local/bin/seats"'';
        description = "The capacity oracle. A chezmoi-managed script (home/dot_local/bin/seats), stdlib python.";
      };

      host = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "The host name the snapshot carries.";
      };

      seats = mkOption {
        type = types.listOf types.str;
        default = [
          "cc"
          "cc2"
          "codex"
          "pi-qwencloud"
          "halogen"
        ];
        description = "Seats published to the floor (runs-on seat ids).";
      };

      seatIds = mkOption {
        type = types.attrsOf types.str;
        default = {
          gpu-worker = "halogen";
        };
        description = "Oracle seat id to runs-on seat id.";
      };

      owners = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          codex = "tom";
        };
        description = "Overrides the oracle's third-party marks (E6: codex is Tom's login tonight).";
      };

      notDispatchable = mkOption {
        type = types.attrsOf types.str;
        default = {
          cc3 = "evicted";
          gpu-coordinator = "halogen is declared but not resident on the coordinator";
        };
        description = "Seats never published, with the reason.";
      };

      plans = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Plan expiry per seat (ISO instant).";
      };

      slots = mkOption {
        type = types.attrsOf types.int;
        default = {
          halogen = 1;
        };
        description = "Slot capacity for seats the oracle reports no holders for (rule 15: the floor subtracts its own WIP).";
      };

      estimatedProviders = mkOption {
        type = types.listOf types.str;
        default = [ "qwen" ];
        description = "Providers whose readings grade ESTIMATED (never admitted unless the floor ungates them).";
      };

      peerCacheDir = mkOption {
        type = types.str;
        default = "inherit";
        description = "pusher.json peerCacheDir: the seats oracle's peer cache. `inherit` (the proven setting) keeps the oracle's own default, so `seats` reuses the tally seat-feeder cache and adds no usage-endpoint calls; a path gives the pusher its own cache (never a tally-rewrite path; apps/pusher/src/seatsOracle.mjs refuses one).";
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Merged last into pusher.json. Never a token.";
      };
    };

    puller = {
      enable = mkEnableOption "the coordinator puller (the interpreter host). ON on the coordinator; see this file's header";

      package = mkOption {
        type = types.package;
        default = substrateApps.puller;
        defaultText = lib.literalExpression "(pkgs.callPackage ../pkgs/substrate-apps { }).puller";
        description = "The puller, built from pkgs/substrate-apps/src/apps/puller with its workspace.";
      };

      holder = mkOption {
        type = types.str;
        default = "coordinator";
        description = "The holder its link token is bound to in the floor's LINK_TOKENS (which also binds the runs-on labels it may lease, runtime:interpreter and seat:coordinator in docs/DEPLOY.md). One session per holder (L5, exit 75).";
      };

      linkTokenSecret = mkOption {
        type = types.str;
        default = "substrate-link-token-coordinator";
        description = "The agenix secret NAME holding this puller's per-link token (the LINK_TOKENS entry for `holder`). Handed to the unit as the credential `link-token`. A name, never a value.";
      };

      linkTokenAgeFile = mkOption {
        type = types.path;
        default = ../secrets/substrate-link-token-coordinator.age;
        defaultText = lib.literalExpression "../secrets/substrate-link-token-coordinator.age";
        description = "The sealed per-link token. Evaluated only when the puller is enabled.";
      };

      maxRuns = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "[puller].max_runs: runs held at once (the Lease capacity).";
      };

      cap = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "[puller].cap: the WIP cap across this puller's agent() calls (node_dispatch = local).";
      };

      nodeDispatch = mkOption {
        type = types.enum [
          "local"
          "floor"
        ];
        default = "local";
        description = "[puller].node_dispatch: local runs agent() nodes on this box's runtimes; floor sends every node back to the floor as an AgentJob for whichever link serves its labels.";
      };

      nodeRunsOn = mkOption {
        type = types.listOf types.str;
        default = [
          "seat:halogen"
          "runtime:gvisor"
        ];
        description = "[puller].node_runs_on: runs-on for a node that names none (floor dispatch).";
      };

      defaultModel = mkOption {
        type = types.str;
        default = "claude-opus-5-5";
        description = "[puller].default_model.";
      };

      axServer = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "nas:7070";
        description = "[puller].ax_server: probed only to say why an ax node is refused here (the NAS link dispatches ax).";
      };

      demandDir = mkOption {
        type = types.str;
        default = "${home}/.local/state/substrate/demand";
        defaultText = lib.literalExpression ''"''${home}/.local/state/substrate/demand"'';
        description = "[puller].demand_dir: marked while a run is held, so the pusher (same dir by default) reads at its active cadence.";
      };

      drainTimeoutS = mkOption {
        type = types.ints.unsigned;
        default = 60;
        description = "[puller].drain_timeout_s: on the first SIGTERM, how long in-flight runs may finish before they are aborted. Keep TimeoutStopSec above it.";
      };

      capacityWaitS = mkOption {
        type = types.ints.unsigned;
        default = 600;
        description = "[puller].capacity_wait_s: how long a node waits for capacity (a stale or refused reading) before it fails.";
      };

      healthAddr = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "127.0.0.1:9311";
        description = "[puller].health_addr: loopback host:port for GET /status.json and /metrics. null: no endpoint (key omitted).";
      };

      stateDir = mkOption {
        type = types.str;
        default = "${home}/.local/state/substrate/puller";
        defaultText = lib.literalExpression ''"''${home}/.local/state/substrate/puller"'';
        description = "[puller].state_dir: held leases, verdict outbox, runs/<id>/ journals.";
      };

      pidfile = mkOption {
        type = types.str;
        default = "${home}/.local/state/substrate/puller.pid";
        defaultText = lib.literalExpression ''"''${home}/.local/state/substrate/puller.pid"'';
        description = "[puller].pidfile: one puller per box (a second exits 3).";
      };

      clientConfigFile = mkOption {
        type = types.path;
        readOnly = true;
        default = clientConfigTemplate;
        description = "The rendered config.toml template, credential paths as placeholders (read-only; for tests).";
      };

      claudeSeat = mkOption {
        type = types.str;
        default = "cc2";
        description = "The Claude seat this host's claude harness spends ([seats].claude and TALLY_SEAT).";
      };

      claudeConfigDir = mkOption {
        type = types.str;
        default = "${home}/.claude-work";
        defaultText = lib.literalExpression ''"''${home}/.claude-work"'';
        description = "CLAUDE_CONFIG_DIR for that seat, by path (cc2 = ~/.claude-work, the seats oracle's table). Mounted, never copied, into sandboxed runtimes.";
      };

      runtimeTestWrapper = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/home/tom/.local/bin/runtime-test";
        description = "When set, ExecStart runs under this wrapper (`<wrapper> -- <puller> ...`): a private /run/user tree and PID/IPC namespaces, which the microvm runtime requires (packages/runners/src/microvm.ts). Off by default: herdr and ssh want the live session.";
      };

      runtimes = mkOption {
        type = tomlFormat.type;
        default = {
          default = "opus";
          allow = [
            "opus"
            "halogen"
            "codex"
            "codex-rw"
          ];
          seats = {
            claude = cfg.puller.claudeSeat;
            pi = "halogen";
            codex = "codex";
          };
          credentials = {
            claude = cfg.puller.claudeConfigDir;
            mode = "rw";
            scope = "credential";
            # RG-1 (critique pass 2026-09-24): a claude job mounts the dir of the seat it is gated on, never another.
            # cc is ~/.claude; claudeSeat (cc2) is claudeConfigDir. `//` so claudeSeat = "cc" overrides, not clashes.
            seats = {
              cc = "${home}/.claude";
            }
            // {
              ${cfg.puller.claudeSeat} = cfg.puller.claudeConfigDir;
            };
          };
          runtime = {
            opus = {
              type = "host";
              harness = "claude";
              seat = cfg.puller.claudeSeat;
              timeoutMs = 900000;
            };
            # pi on the coordinator against the Halogen server on the worker (the proven pattern). ssh:worker was
            # refused in the proof and never exercised, so it is not declared.
            halogen = {
              type = "host";
              harness = "pi";
              seat = "halogen";
              timeoutMs = 1800000;
            };
            codex = {
              type = "host";
              harness = "codex";
              seat = "codex";
              timeoutMs = 900000;
              codexSandbox = "read-only";
            };
            # The build-node runtime: codex may write in its job dir.
            codex-rw = {
              type = "host";
              harness = "codex";
              seat = "codex";
              timeoutMs = 900000;
              codexSandbox = "workspace-write";
            };
          };
        };
        description = "The runtimes file (packages/runners/src/config.ts), rendered to TOML and named by [puller].runtimes (and AX_CONWIP_RUNTIMES). Default: the shape proven live on 2026-09-24. opus (host, claude on claudeSeat), halogen (host, pi against the worker's Halogen server), codex (read-only) and codex-rw (workspace-write), default opus, each claude seat bound to its config dir in [credentials.seats]. herdr, gvisor and ssh:worker tables are not declared by default (never exercised); override this option to add them.";
      };

      runtimesFile = mkOption {
        type = types.path;
        readOnly = true;
        default = runtimesToml;
        description = "The rendered runtimes.toml (read-only; for tests).";
      };

      deployConfig = mkOption {
        type = types.attrs;
        default = {
          forbiddenReadPrefixes = [
            "~/rawa"
            "~/.local/state/secrets-holdout-2026-09-18"
          ];
          forbiddenLedgerPrefixes = [
            "/run/user"
            "~/.local/state/tally-rewrite"
          ];
          metersDir = "~/.local/state/tally-rewrite/meters";
          axProtoFallbackPath = null;
          realSeats = [
            "cc"
            "cc2"
            "cc3"
            "halogen"
            "codex"
          ];
          codexWorkdir = "~/mecattaf/substrate";
        };
        description = "src/deploy-config.ts keys (SUBSTRATE_CONFIG, read by the capacity gate). capacityFloorUrl and capacityFloorTokenFile are set by the unit from floorUrl and the credential.";
      };

      extraPath = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages on the unit's PATH besides openssh and coreutils (claude, pi, herdr come from the user profile).";
      };
    };
  };

  config = mkIf anyEnabled {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.floorUrl;
        message = "services.substrate.floorUrl must be an https:// URL (the bearer never travels in clear).";
      }
      {
        assertion = !cfg.puller.enable || cfg.puller.linkTokenSecret != cfg.tokenSecret;
        message = "services.substrate.puller.linkTokenSecret must differ from tokenSecret: the per-link token is not the operator bearer.";
      }
      {
        assertion = !cfg.pusher.enable || !(cfg.pusher.extraConfig ? tokenFile);
        message = "services.substrate.pusher.extraConfig must not name a tokenFile: the bearer arrives as the credential floor-token.";
      }
    ];

    age.secrets = lib.mkMerge [
      {
        ${cfg.tokenSecret} = {
          file = cfg.tokenAgeFile;
          owner = cfg.user;
          mode = "0400";
        };
      }
      (mkIf cfg.puller.enable {
        ${cfg.puller.linkTokenSecret} = {
          file = cfg.puller.linkTokenAgeFile;
          owner = cfg.user;
          mode = "0400";
        };
      })
    ];

    systemd.user.services.substrate-pusher = mkIf cfg.pusher.enable {
      description = "substrate-pusher: seats --json to the Substrate floor, gently";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = cfg.user;
      path = [
        pkgs.python3
        pkgs.coreutils
      ];
      serviceConfig = commonService // {
        ExecStart = "${lib.getExe cfg.pusher.package} --config ${pusherConfig} --token-file %d/floor-token";
        # 2 usage, 3 another pusher holds the pidfile: neither is cured by a restart.
        RestartPreventExitStatus = [
          2
          3
        ];
        MemoryMax = "256M";
      };
    };

    systemd.user.services.substrate-puller = mkIf cfg.puller.enable {
      description = "substrate-puller: the Substrate interpreter host on this box";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = cfg.user;
      path = [
        pkgs.openssh
        pkgs.coreutils
      ]
      ++ cfg.puller.extraPath;
      environment = {
        CLAUDE_CONFIG_DIR = cfg.puller.claudeConfigDir;
        TALLY_SEAT = cfg.puller.claudeSeat;
      };
      serviceConfig = commonService // {
        ExecStart = pullerStart;
        LoadCredential = commonService.LoadCredential ++ [
          "link-token:${config.age.secrets.${cfg.puller.linkTokenSecret}.path}"
        ];
        RuntimeDirectory = "substrate-puller";
        RuntimeDirectoryMode = "0700";
        # 3 another puller holds the pidfile, 75 another session holds this holder (L5), 78 bad config or token:
        # none is cured by a restart.
        RestartPreventExitStatus = [
          3
          75
          78
        ];
        # Above drain_timeout_s, so the first SIGTERM's drain can finish before systemd escalates.
        TimeoutStopSec = "${toString (cfg.puller.drainTimeoutS + 30)}s";
        MemoryMax = "2G";
      };
    };
  };
}
