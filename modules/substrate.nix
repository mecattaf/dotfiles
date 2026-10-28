{
  config,
  lib,
  pkgs,
  ...
}:
# The NAS runs the Cloudflare scheduler's capacity pusher and interpreter.
# Agent processes, credentials and session history stay on NAS; explicit
# fleet-exec commands send build/test work to strix-coordinator.
# Gufo is a DSH provider on the host, not a Pi installation. Model choices
# remain runtime data in the private models.toml catalog, seeded only if absent.
# Both units use Tom's profile and credential paths; no token enters the store.
# The puller drains before stopping, and a changed unit never restarts live work.
# Before commissioning a replacement executor, audit queued sessions and rebind
# the nightly routine to DSH. A Pi-bound session cannot be resumed as DSH.

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

  # NixOS renders a unit's `path` as Environment=PATH=..., which REPLACES the user manager's PATH rather than
  # extending it. The runners spawn bare `claude`, `dsh` and `codex` (packages/runners/src/harness.ts) and `seats`
  # spawns bare `codex` for the codex seat, so both units carry the user's own profile explicitly (each entry
  # gets /bin appended), in the manager's order: ~/.local/bin (seats), the per-user profile (claude, codex, dsh,
  # herdr), then the system profile.
  userProfilePath = [
    "${home}/.local"
    "/etc/profiles/per-user/${cfg.user}"
    "/run/current-system/sw"
  ];

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

  # The model catalog's seed: installed to puller.modelsFile at unit start only when that file is absent. The store
  # copy is never the file the runners read; the one in $HOME is Tom's, mutable, and survives every switch.
  modelsSeedFile = pkgs.writeText "substrate-models-seed.toml" cfg.puller.modelsSeed;

  # puller.sshRuntimes, rendered as [runtime."ssh:<host>"] tables in the shape of SshRuntime in
  # packages/runners/src/config.ts:116-121 (type "ssh", host, plus the common harness, seat and timeoutMs of
  # :44-58). MERGED into the default runtimes below and appended to its allow list: a host that instead sets
  # puller.runtimes.runtime."ssh:strix" REPLACES the whole default and drops opus, gufo, codex, codex-rw,
  # allow, seats and credentials (MEASURED 2026-09-25 by nix eval through extendModules).
  # The name is the loader's SSH_SHORTHAND (config.ts:284); builtins.match anchors the whole string.
  sshRuntimeNameRe = "ssh:[A-Za-z0-9][A-Za-z0-9_.@-]*";
  sshRuntimeTables = lib.mapAttrs (name: r: {
    type = "ssh";
    inherit (r) host harness seat;
    # A runtime with no callTimeoutMs entry of its own gets gufo's ceiling (the seat ssh:strix spends).
    timeoutMs = cfg.puller.callTimeoutMs.${name} or cfg.puller.callTimeoutMs.gufo;
  }) cfg.puller.sshRuntimes;

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
      pidfile =
        if cfg.puller.pidfile == null then "@RUNTIME_DIRECTORY@/puller.pid" else cfg.puller.pidfile;
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
    ${pkgs.gnused}/bin/sed -e "s|@FLOOR_TOKEN_FILE@|$token|" -e "s|@LINK_TOKEN_FILE@|$link|" -e "s|@RUNTIME_DIRECTORY@|$RUNTIME_DIRECTORY|" ${clientConfigTemplate} > "$RUNTIME_DIRECTORY/config.toml"
    export SUBSTRATE_CONFIG="$RUNTIME_DIRECTORY/substrate.json"
    export SUBSTRATE_CLIENT_CONFIG="$RUNTIME_DIRECTORY/config.toml"
    # [puller].runtimes is the primary; loadRuntimes (packages/runners/src/config.ts) still falls back to this.
    export AX_CONWIP_RUNTIMES=${runtimesToml}
    # The model catalog (runtimes.toml models_file): seeded once if absent, then Tom's. Never overwritten here; a
    # set but missing models_file is a config error in the puller, so the seed is what makes a fresh box start.
    models=${lib.escapeShellArg cfg.puller.modelsFile}
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$models")"
    if [ ! -e "$models" ]; then
      ${pkgs.coreutils}/bin/install -m 600 ${modelsSeedFile} "$models"
      echo "substrate-puller: seeded $models" >&2
    fi
    command -v dsh >/dev/null || { echo "substrate-puller: DSH is absent from the NAS profile" >&2; exit 78; }
    ${pkgs.python3}/bin/python3 - "$models" <<'PYTHON'
    import sys, tomllib
    with open(sys.argv[1], "rb") as source:
        models = tomllib.load(source).get("models", [])
    if any(model.get("harness") == "pi" for model in models):
        raise SystemExit("substrate-puller: retired Pi catalog; review substrate-dsh-catalog, then apply explicitly")
    if not any(model.get("harness") == "dsh" and model.get("provider") == "gufo" for model in models):
        raise SystemExit("substrate-puller: no DSH Gufo model configured")
    PYTHON
    # Review 2026-09-24 (low): hostHarnessEnv passes CREDENTIALS_DIRECTORY through to every host agent. The token
    # paths are already in the rendered files, so the variable is dropped here; the directory stays readable.
    unset CREDENTIALS_DIRECTORY
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
      description = "The sealed bearer (secrets.nix: editors and the NAS brain key). Evaluated only when a unit is enabled.";
    };

    pusher = {
      enable = mkEnableOption "the NAS capacity pusher (seats --json to the floor)";

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
        description = "The capacity oracle. A Home Manager-linked script (home/dot_local/bin/seats), stdlib python.";
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
          "gufo"
          # 2026-09-30: credit-metered seats read by `seats` from OpenRouter's /credits and /key endpoints.
        ];
        description = "Seats published to the floor (runs-on seat ids).";
      };

      seatIds = mkOption {
        type = types.attrsOf types.str;
        default = {
          gpu-strix = "gufo";
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
        # The resident Gufo execution slot is shared by local utility calls.
        default = {
          gufo = 1;
        };
        description = "Slot capacity per seat (rule 15: the floor and the puller subtract their own WIP). Gufo is a slot row whenever it is up (1 unless set here); any other seat is one only when it is named here.";
      };

      estimatedProviders = mkOption {
        type = types.listOf types.str;
        default = [ ];
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
      enable = mkEnableOption "the NAS interpreter host for the Cloudflare scheduler";

      package = mkOption {
        type = types.package;
        default = substrateApps.puller;
        defaultText = lib.literalExpression "(pkgs.callPackage ../pkgs/substrate-apps { }).puller";
        description = "The puller, built from pkgs/substrate-apps/src/apps/puller with its workspace.";
      };

      holder = mkOption {
        type = types.str;
        default = "coordinator"; # Existing remote LINK_TOKENS identity; independent of hostname.
        description = "The holder its link token is bound to in the floor's LINK_TOKENS (which also binds the runs-on labels it may lease, runtime:interpreter and seat:strix in docs/DEPLOY.md). One session per holder (L5, exit 75).";
      };

      linkTokenSecret = mkOption {
        type = types.str;
        default = "substrate-link-token-strix";
        description = "The agenix secret NAME holding this puller's per-link token (the LINK_TOKENS entry for `holder`). Handed to the unit as the credential `link-token`. A name, never a value.";
      };

      linkTokenAgeFile = mkOption {
        type = types.path;
        default = ../secrets/substrate-link-token-strix.age;
        defaultText = lib.literalExpression "../secrets/substrate-link-token-strix.age";
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
          "seat:gufo"
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
        type = types.nullOr types.str;
        default = null;
        description = "[puller].pidfile: one puller per box (a second exits 3). null (the default) renders $RUNTIME_DIRECTORY/puller.pid, which systemd clears on unit stop and at boot, so a pidfile left by an unclean exit cannot block the next start. A path on persistent disk brings that stale-pidfile trap back.";
      };

      clientConfigFile = mkOption {
        type = types.path;
        readOnly = true;
        default = clientConfigTemplate;
        description = "The rendered config.toml template, credential paths as placeholders (read-only; for tests).";
      };

      claudeSeat = mkOption {
        type = types.str;
        default = "cc";
        description = "The Claude seat this host's claude harness spends ([seats].claude and TALLY_SEAT).";
      };

      claudeConfigDir = mkOption {
        type = types.str;
        default = "${home}/.claude";
        defaultText = lib.literalExpression ''"''${home}/.claude"'';
        description = "CLAUDE_CONFIG_DIR for that seat, by path (cc2 = ~/.claude-work, the seats oracle's table). Mounted, never copied, into sandboxed runtimes.";
      };

      runtimeTestWrapper = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/home/tom/.local/bin/runtime-test";
        description = "When set, ExecStart runs under this wrapper (`<wrapper> -- <puller> ...`): a private /run/user tree and PID/IPC namespaces, which the microvm runtime requires (packages/runners/src/microvm.ts). Off by default: herdr and ssh want the live session.";
      };

      sshRuntimes = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              host = mkOption {
                type = types.str;
                example = "worker";
                description = "The ssh destination: a Host of `user`'s ~/.ssh/config (SshRuntime.host, packages/runners/src/config.ts).";
              };
              harness = mkOption {
                type = types.enum [
                  "claude"
                  "dsh"
                  "codex"
                ];
                default = "dsh";
                description = "The harness CLI the runner starts on the remote host (it must be on the remote non-interactive ssh PATH).";
              };
              seat = mkOption {
                type = types.str;
                example = "gufo";
                description = "The capacity seat a call on this runtime spends. An ssh runtime spends the REMOTE login (config.ts common.seat), so it is named here, never inherited from [seats].";
              };
            };
          }
        );
        default = { };
        example = lib.literalExpression ''
          {
            "ssh:strix" = {
              host = "strix";
              harness = "dsh";
              seat = "gufo";
            };
          }
        '';
        description = "Extra type = \"ssh\" runtimes, one [runtime.\"<name>\"] table each (name ^ssh:[A-Za-z0-9][A-Za-z0-9_.@-]*$), MERGED into the default `runtimes` and appended to its allow list; timeoutMs is callTimeoutMs.<name>, else callTimeoutMs.gufo. The runner (packages/runners/src/ssh.ts) runs the job in its own remote session, kills that process group on timeout or abort over a second ssh, and reaps leftover groups after a runner crash. Setting `runtimes` by hand drops these (an assertion says so).";
      };

      runtimes = mkOption {
        type = tomlFormat.type;
        default = {
          default = "opus";
          # The model catalog lives outside the store (puller.modelsFile); the runners re-read it on every call.
          models_file = cfg.puller.modelsFile;
          # The project MCP for substrate sessions (projects build 2026-10-12, EXCHANGE.md section 8): the runner
          # writes each session's MCP config from these. project_bin is the CLI out-link's own binary by absolute path
          # (nix build --out-link, pattern B), so the MCP launch depends on neither PATH nor HOME; the token is a
          # path, never a value (0600, read as this user). root and codex keep the loader's defaults.
          sessions = {
            project_bin = "${home}/.local/state/agency/project/cli/bin/project";
            project_url = "https://project.mecattaf.dev";
            project_token_file = "${home}/.config/project/token";
          };
          allow = [
            "opus"
            "gufo"
            "codex"
            "codex-rw"
          ]
          ++ builtins.attrNames cfg.puller.sshRuntimes;
          seats = {
            claude = cfg.puller.claudeSeat;
            dsh = "gufo";
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
              timeoutMs = cfg.puller.callTimeoutMs."opus";
            };
            # Local calls use the host's Gufo provider. Remote execution uses
            # an explicit SSH runtime with its own configured seat.
            gufo = {
              type = "host";
              harness = "dsh";
              provider = "gufo";
              seat = "gufo";
              timeoutMs = cfg.puller.callTimeoutMs."gufo";
            };
            codex = {
              type = "host";
              harness = "codex";
              seat = "codex";
              timeoutMs = cfg.puller.callTimeoutMs."codex";
              codexSandbox = "read-only";
            };
            # The build-node runtime: codex may write in its job dir.
            codex-rw = {
              type = "host";
              harness = "codex";
              seat = "codex";
              timeoutMs = cfg.puller.callTimeoutMs."codex-rw";
              codexSandbox = "workspace-write";
            };

          }
          // sshRuntimeTables;
        };
        description = "Host runtimes for Claude, DSH against Gufo, and Codex. The mutable model catalog is read per call. Extra SSH runtimes must be explicit; compute hosts do not receive agent credentials.";
      };

      runtimesFile = mkOption {
        type = types.path;
        readOnly = true;
        default = runtimesToml;
        description = "The rendered runtimes.toml (read-only; for tests).";
      };

      modelsFile = mkOption {
        type = types.str;
        default = "${home}/.config/substrate/models.toml";
        defaultText = lib.literalExpression ''"''${home}/.config/substrate/models.toml"'';
        description = "The mutable model catalog (runtimes.toml models_file), read at run time by the runners on every call. Seeded from modelsSeed if absent at unit start, never rewritten by nix: edit it to change a model with no rebuild (Tom 2026-10-10: model names are not nixos dotfiles data). An absolute path; ~ is not expanded.";
      };

      modelsSeed = mkOption {
        type = types.lines;
        default = ''
          # Seed only. The existing private catalog is never overwritten.
          [[models]]
          id = "claude-opus-5-5"
          harness = "claude"
          aliases = ["opus"]
          default = true

          [[models]]
          id = "claude-fable-5-1"
          harness = "claude"
          aliases = ["fable"]
          ceilings = { model_scoped = 90 }

          [[models]]
          id = "qwen3.8-flash-next"
          harness = "dsh"
          provider = "gufo"
          aliases = ["local"]
          default = true
        '';
        description = "The TOML text installed at modelsFile when that file is absent at unit start (mode 600). Fresh catalogs contain the local DSH/Gufo route and the existing Claude models. Changing this option changes only what a FRESH box gets; an existing file is never touched.";
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
            "gufo"
            "codex"
          ];
          codexWorkdir = "~/mecattaf/substrate";
        };
        description = "src/deploy-config.ts keys (SUBSTRATE_CONFIG, read by the capacity gate). capacityFloorUrl and capacityFloorTokenFile are set by the unit from floorUrl and the credential.";
      };

      callTimeoutMs = mkOption {
        type = types.attrsOf types.ints.positive;
        default = {
          opus = 1800000;
          gufo = 1800000;
          codex = 1800000;
          codex-rw = 2700000;
        };
        description = "Per-runtime wall-clock ceiling for one agent() call (timeoutMs in runtimes.toml). A call may shorten it, never extend it. Raised from 15 min on 2026-09-24 17:35: three codex-rw implement nodes of the crm and email builds hit exit 124 at 900000 ms while still executing commands. A puller.sshRuntimes entry with no key here gets the gufo value. A host that sets this option replaces the whole default, so it names every runtime it declares.";
      };
      workingDirectory = mkOption {
        type = types.str;
        default = "${home}/mecattaf/substrate";
        defaultText = lib.literalExpression ''"''${home}/mecattaf/substrate"'';
        description = "The unit's WorkingDirectory. The live puller ran from the substrate checkout: the runners derive a worktree from process.cwd() for agent({isolation = \"worktree\"}) calls and the interpreter's fallback resolver looks in cwd/.claude/workflows, so a git checkout keeps parity with the proof (review 2026-09-24).";
      };
      memoryHigh = mkOption {
        type = types.str;
        default = "1G";
        description = "Soft memory limit for the NAS executor and its children.";
      };
      memoryMax = mkOption {
        type = types.str;
        default = "2G";
        description = "Hard memory limit for the NAS executor; compute work runs remotely.";
      };
      extraPath = mkOption {
        type = types.listOf types.package;
        default = [
          pkgs.nodejs_24
          pkgs.pnpm_11_17
        ];
        defaultText = lib.literalExpression "[ pkgs.nodejs_24 pkgs.pnpm_11_17 ]";
        description = "Packages on the unit's PATH besides openssh, coreutils and the user's profile directories (~/.local/bin, /etc/profiles/per-user/<user>/bin, /run/current-system/sw/bin), which supply claude, dsh, codex and herdr. Default: the gate toolchain of stack v1 (Node 24, pnpm 11.17.0; overlays/default.nix pnpm_11_17) so a spec-task gate runs `node` and `pnpm` bare in a worktree (factory defect 6, 2026-10-10); git and gh come from the user profile as before. Overridable.";
      };
    };
  };

  config = mkIf (anyEnabled && config.myFleet.has "brain") {
    environment.systemPackages = [ substrateApps.catalogMigrate ];
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
    ]
    ++ lib.concatMap (name: [
      {
        assertion = builtins.match sshRuntimeNameRe name != null;
        message = "services.substrate.puller.sshRuntimes.\"${name}\": the name must match ^${sshRuntimeNameRe}$ (packages/runners/src/config.ts SSH_SHORTHAND).";
      }
      {
        # A hand-set `runtimes` replaces the default this option merges into.
        assertion =
          (cfg.puller.runtimes.runtime or { }) ? ${name}
          && (!(cfg.puller.runtimes ? allow) || builtins.elem name cfg.puller.runtimes.allow);
        message = "services.substrate.puller.sshRuntimes.\"${name}\" is not in the rendered runtimes (table and allow): puller.runtimes was set by hand, which drops the merged ssh tables; restate it there or drop the override.";
      }
    ]) (builtins.attrNames cfg.puller.sshRuntimes);

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
      ]
      ++ userProfilePath;
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
      # Running factory jobs outlive configuration switches. The mutable model
      # catalog is reread per call; apply new runner code only after a drain.
      restartIfChanged = false;
      description = "substrate-puller: the Substrate interpreter host on this box";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = cfg.user;
      path = [
        pkgs.openssh
        pkgs.coreutils
      ]
      ++ cfg.puller.extraPath
      ++ userProfilePath;
      environment = {
        LOCAL_MODEL_ENDPOINT = (import ../lib/local-model.nix).endpoint;
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
        # 75 another session holds this holder (L5), 78 bad config or token: neither is cured by a restart. 3 (another
        # puller holds the pidfile) is retried every RestartSec: the pidfile is in the RuntimeDirectory, so a hold is
        # transient and a restart is the cure.
        RestartPreventExitStatus = [
          75
          78
        ];
        # Above drain_timeout_s, so the first SIGTERM's drain can finish before systemd escalates.
        TimeoutStopSec = "${toString (cfg.puller.drainTimeoutS + 30)}s";
        # Review 2026-09-24 (medium): the default KillMode=control-group would SIGTERM every claude, codex and dsh
        # child at once and defeat the puller's own drain ladder; mixed signals only the puller, which drains its
        # nodes (drain_timeout_s) and kills its live groups itself. One OOM-killed node must not stop the puller.
        KillMode = "mixed";
        OOMPolicy = "continue";
        WorkingDirectory = cfg.puller.workingDirectory;
        MemoryHigh = cfg.puller.memoryHigh;
        MemoryMax = cfg.puller.memoryMax;
        # The proof ran inside runtime-test with a private /run/user. The unit keeps the real one (herdr and ssh
        # stay reachable) but the desktop session's sockets are not something a headless agent should inherit.
        UnsetEnvironment = [
          "DBUS_SESSION_BUS_ADDRESS"
          "WAYLAND_DISPLAY"
          "DISPLAY"
          "NIRI_SOCKET"
          # scroll's IPC socket is a full command channel (`exit`, `exec`) with no authorization, and scroll
          # exports it under all three names (sway/ipc-server.c:116-118). A headless agent inherits none.
          "SCROLLSOCK"
          "SWAYSOCK"
          "I3SOCK"
        ];
      };
    };
  };
}
