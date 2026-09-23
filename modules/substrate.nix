{
  config,
  lib,
  pkgs,
  ...
}:
# services.substrate: the coordinator's two box-side programs of the Cloudflare Substrate, declared and OFF.
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
#   puller  the interpreter host: leases runtime:interpreter work from the floor and runs each workflow's agent()
#           calls on the runtimes this module renders into runtimes.toml (host, herdr, gvisor, ssh:worker) with
#           the cc2 seat's config dir by path. PENDING upstream: apps/puller is not in the pinned source yet
#           (pkgs/substrate-apps/SYNC.md), so `package` defaults to null and arming asserts.
#
# WHY USER UNITS. Both programs speak for Tom's logins: `seats` reads each Claude seat's OAuth usage from its
# config dir, and the puller runs claude, herdr and ssh as Tom. A system unit with User=tom would carry none of
# the session (herdr socket, ssh agent, XDG dirs). ConditionUser pins each unit to that one user's manager.
#
# THE TOKEN IS A PATH, NEVER A VALUE. The floor's operator bearer (FLOOR_TOKEN) is sealed as an agenix secret,
# decrypted at /run/agenix/<tokenSecret> for the user (owner = user, 0400), and handed to each unit as a private
# copy by LoadCredential; the programs get `%d/floor-token` (the pusher's --token-file; the puller's
# capacityFloorTokenFile through a runtime-rendered substrate.json). Nothing here reads, prints or interpolates
# the value; the rendered pusher.json and substrate.json carry only paths. Minting the token (wrangler secret put
# FLOOR_TOKEN and this age file) is Tom's hand.
#
# THE GATE. Both `enable`s default to false and hosts/coordinator sets them false explicitly. Arming needs the
# floor deployed at floorUrl, the sealed token, and for the puller its package. tests/substrate-modules renders
# both units armed with fixtures so the shape is proven at evaluation time without a token on disk.
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

  pullerLabels = lib.concatStringsSep "," cfg.puller.servedLabels;
  pullerExec = lib.escapeShellArgs (
    lib.optionals (cfg.puller.runtimeTestWrapper != null) [
      cfg.puller.runtimeTestWrapper
      "--"
    ]
    ++ [
      (lib.getExe cfg.puller.package)
      "--floor"
      cfg.floorUrl
      "--holder"
      cfg.puller.holder
      "--labels"
      pullerLabels
      "--max-in-flight"
      (toString cfg.puller.maxInFlight)
    ]
    ++ cfg.puller.extraArgs
  );

  pullerStart = pkgs.writeShellScript "substrate-puller-start" ''
    set -euo pipefail
    : "''${CREDENTIALS_DIRECTORY:?substrate-puller needs LoadCredential (no CREDENTIALS_DIRECTORY)}"
    : "''${RUNTIME_DIRECTORY:?substrate-puller needs RuntimeDirectory}"
    token="$CREDENTIALS_DIRECTORY/floor-token"
    test -r "$token" || { echo "substrate-puller: no floor-token credential" >&2; exit 78; }
    umask 077
    ${pkgs.gnused}/bin/sed "s|@FLOOR_TOKEN_FILE@|$token|" ${deployConfigTemplate} > "$RUNTIME_DIRECTORY/substrate.json"
    export SUBSTRATE_CONFIG="$RUNTIME_DIRECTORY/substrate.json"
    export AX_CONWIP_RUNTIMES=${runtimesToml}
    exec ${pullerExec} --token-file "$token"
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
      enable = mkEnableOption "the gentle capacity pusher (seats --json to the floor). OFF; see this file's header";

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

      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Merged last into pusher.json. Never a token.";
      };
    };

    puller = {
      enable = mkEnableOption "the coordinator puller (the interpreter host). OFF; PENDING its package, see pkgs/substrate-apps/SYNC.md";

      package = mkOption {
        type = types.nullOr types.package;
        default = substrateApps.puller or null;
        defaultText = lib.literalExpression "(pkgs.callPackage ../pkgs/substrate-apps { }).puller or null";
        description = "The puller. null until apps/puller is vendored; arming asserts on it.";
      };

      holder = mkOption {
        type = types.str;
        default = "coordinator-puller-1";
        description = "holderIdentity at the floor; one session per identity.";
      };

      servedLabels = mkOption {
        type = types.listOf types.str;
        default = [ "runtime:interpreter" ];
        description = "runs-on labels this puller leases (ARC W6: the coordinator serves the interpreter and the Claude seats; the NAS link serves seat:halogen runtime:gvisor).";
      };

      maxInFlight = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "Runs interpreted at once on this host.";
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
          default = "host";
          allow = [
            "host"
            "herdr"
            "gvisor"
            "ssh:worker"
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
          };
          runtime = {
            host = {
              type = "host";
              harness = "claude";
            };
            herdr = {
              type = "herdr";
              harness = "claude";
              mode = "action";
            };
            gvisor = {
              type = "gvisor";
              harness = "claude";
              runsc = "${pkgs.gvisor}/bin/runsc";
              pasta = "${pkgs.passt}/bin/pasta";
              state = "${home}/.local/state/substrate/runsc";
              network = "isolated";
            };
            "ssh:worker" = {
              type = "ssh";
              host = "worker";
              harness = "pi";
              seat = "halogen";
            };
          };
        };
        description = "The runtimes file (packages/runners/src/config.ts), rendered to TOML and passed as AX_CONWIP_RUNTIMES. Defaults: host, herdr, gvisor (nix runsc and pasta) and ssh:worker (pi on Halogen), default host, cc2's config dir as the claude credential.";
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
        description = "src/deploy-config.ts keys (SUBSTRATE_CONFIG). capacityFloorUrl and capacityFloorTokenFile are set by the unit from floorUrl and the credential.";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Appended to the puller's command line.";
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
        assertion = !cfg.puller.enable || cfg.puller.package != null;
        message = "services.substrate.puller has no package: apps/puller is not vendored yet (pkgs/substrate-apps/SYNC.md, Pending).";
      }
      {
        assertion = !cfg.pusher.enable || !(cfg.pusher.extraConfig ? tokenFile);
        message = "services.substrate.pusher.extraConfig must not name a tokenFile: the bearer arrives as the credential floor-token.";
      }
    ];

    age.secrets.${cfg.tokenSecret} = {
      file = cfg.tokenAgeFile;
      owner = cfg.user;
      mode = "0400";
    };

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
        RuntimeDirectory = "substrate-puller";
        RuntimeDirectoryMode = "0700";
        RestartPreventExitStatus = [ 78 ];
        MemoryMax = "2G";
      };
    };
  };
}
