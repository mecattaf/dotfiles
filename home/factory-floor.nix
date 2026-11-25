{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# The factory floor (`agency`, ~/mecattaf/factory-floor): a Cordis
# orchestrator on herdr-core, the floor that replaces the retired dshd
# instance `floor` (2026-11-26). This file declares its user unit on the brain
# host, in the shape of communications.service (the communications Home
# Manager module): every path is an option, no default names a host except
# through config.home.homeDirectory and the XDG directories, and the host's
# own floor.jsonc lives in configDir, outside this repository.
#
# LOCAL CHECKOUT. The floor repository is not a flake input yet, so with
# `package = null` the unit runs the entry of a checkout that a person (or
# the floor's own track) has built: `pnpm install && pnpm build` in
# `checkout`. The unit never builds, fetches or installs anything. Its
# ExecStart is a small store launcher that checks the entry, puts node 24 and
# the fleet's herdr-core first on PATH, and execs the entry. An entry that is
# missing or not executable exits 78 (EX_CONFIG), which
# RestartPreventExitStatus keeps from looping; ConditionPathExists skips the
# start outright when the checkout is absent, so a host without one shows no
# failed unit. Once the floor repo has a flake, `package` names it and
# `entry` defaults into the store.
#
# NOT AUTOSTARTED, NO WAKE (2026-11-26). The unit is declared but wanted by no
# target, and the heartbeat does not start it: the heartbeat's inbox holds
# Tom's real items (fleet-update among them), and a first-night floor must not
# be woken into them unattended. It is started by hand
# (`systemctl --user start factory-floor`). Two flips, both Tom's:
#   autostart = true      -> WantedBy=default.target (comes up at boot)
#   heartbeatWake = true  -> floorUnit = "factory-floor.service", which
#                            home/scheduled.nix passes to the heartbeat as
#                            SCHEDULED_FLOOR_UNIT, so a tick with records
#                            waiting runs `systemctl --user start` on it.
#
# HC. The floor talks to the declared core (hc-core.service,
# home/herdr-core.nix) on the default socket and never starts a core itself;
# Wants=/After= order it behind that oneshot. Workers live in hc's own
# transient holder units, not in this cgroup, so stopping or restarting the
# floor ends no agent. The per-launch variables of whatever shell last fed the
# user manager (a Claude Code session's CLAUDE_CODE_*, hc selectors) are unset
# as for hc-core.service: the floor hands environment to its workers, and the
# two lists must stay equal (tests/factory-floor asserts it).
#
# SWITCH. X-SwitchMethod=keep-old: a switch never restarts a running floor
# (it carries live Assignments); restart it by hand to take a new launcher.
# On a unit that is not running this is inert.
#
# Runbook, the contract with the floor repository, and the transient-unit
# fallback for a host that was not switched: docs/factory-floor.md.
let
  cfg = config.services.factory-floor;
  inherit (lib) mkOption types;
  home = config.home.homeDirectory;
  herdrCore = pkgs.llm-agents.herdr-core;

  # A relative entry is resolved against the checkout, here for the unit's
  # condition and in the launcher for a hand-run copy.
  entryPath = if lib.hasPrefix "/" cfg.entry then cfg.entry else "${cfg.checkout}/${cfg.entry}";

  launcher = pkgs.writeShellApplication {
    name = "factory-floor-service";
    runtimeInputs = [
      pkgs.nodejs_24
      herdrCore
      pkgs.coreutils
    ];
    text = ''
      checkout=''${FACTORY_FLOOR_CHECKOUT:?factory-floor-service: FACTORY_FLOOR_CHECKOUT is not set}
      entry=''${FACTORY_FLOOR_ENTRY:-bin/agency-service}
      case $entry in
        /*) ;;
        *) entry=$checkout/$entry ;;
      esac
      if [ ! -f "$entry" ] || [ ! -x "$entry" ]; then
        echo "factory-floor-service: $entry is not an executable file; build the checkout first (pnpm install && pnpm build)" >&2
        exit 78
      fi
      # The running system's tools after node and herdr-core, never a login
      # shell's.
      PATH=$PATH:/run/current-system/sw/bin
      export PATH
      exec "$entry" "$@"
    '';
  };

  # The per-launch names the floor drops from the user manager's environment:
  # the list home/herdr-core.nix carries for hc-core.service.
  unsetEnvironment = [
    "CLOUDFLARE_API_TOKEN"
    "CLAUDECODE"
    "CLAUDE_CODE_ENTRYPOINT"
    "CLAUDE_CODE_CHILD_SESSION"
    "CLAUDE_CODE_SESSION_ID"
    "CLAUDE_CODE_SESSION_ATTENDED"
    "CLAUDE_CODE_MESSAGING_SOCKET"
    "CLAUDE_CODE_MESSAGING_TOKEN"
    "CLAUDE_CODE_EXECPATH"
    "CLAUDE_PID"
    "CLAUDE_EFFORT"
    "CLAUDE_ENVELOPE"
    "CODEX_THREAD_ID"
    "DSH_SESSION_ID"
    "DSH_SHELL"
    "DSH_PROFILE_DIR"
    "DSH_WEB_URL"
    "HC_SESSION"
    "HC_SOCKET"
    "HC_TERMINAL_ID"
    "HC_TERMINAL_SOCKET"
  ];
in
{
  options.services.factory-floor = {
    enable = mkOption {
      type = types.bool;
      default = osConfig.myFleet.has "brain";
      defaultText = lib.literalExpression ''osConfig.myFleet.has "brain"'';
      description = "Declare the factory floor's user unit (factory-floor.service).";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        The floor package, once the floor repository has a flake. null is local-checkout mode: the unit runs
        `entry` from `checkout`, which must be built by hand.
      '';
    };

    checkout = mkOption {
      type = types.str;
      default = "${home}/mecattaf/factory-floor";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/mecattaf/factory-floor"'';
      description = "The local checkout of the floor repository (local-checkout mode).";
    };

    entry = mkOption {
      type = types.str;
      default =
        if cfg.package == null then
          "${cfg.checkout}/bin/agency-service"
        else
          lib.getExe' cfg.package "agency-service";
      defaultText = lib.literalExpression ''"''${cfg.checkout}/bin/agency-service", or the package's bin/agency-service'';
      description = ''
        The program the unit runs, with no arguments: a foreground process that exits non-zero when a plugin fails to
        start, ends within 60 s of SIGTERM, and never builds. A relative path is resolved against `checkout`.
      '';
    };

    stateDir = mkOption {
      type = types.str;
      default = "${home}/.agency/state/master/factory-floor";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.agency/state/master/factory-floor"'';
      description = ''
        The floor's own state directory (its database, briefs, tokens, its own inbox/scheduled). A fresh directory:
        never the retired floor's orchestrator.sqlite beside it.
      '';
    };

    workDir = mkOption {
      type = types.str;
      default = "${config.xdg.stateHome}/factory-floor";
      defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/factory-floor"'';
      description = "The floor's working directory (generated Cordis config, profile, caches). No data.";
    };

    configDir = mkOption {
      type = types.str;
      default = "${config.xdg.configHome}/agency/factory-floor";
      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/agency/factory-floor"'';
      description = "The host-local config directory holding floor.jsonc, outside this repository.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "The panel's bind address. Loopback; a wildcard is refused.";
    };

    port = mkOption {
      type = types.port;
      default = 3082;
      description = "The panel's TCP port; scheduled-panel-tunnel forwards 3082 to the seat.";
    };

    autostart = mkOption {
      type = types.bool;
      default = false;
      description = "Want the unit from default.target, so it starts at boot and at switch. Off on 2026-11-26.";
    };

    heartbeatWake = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Let the heartbeat start the unit when occurrence records wait (through `floorUnit`). Off on 2026-11-26: the
        heartbeat's inbox holds the host's real scheduled items.
      '';
    };

    floorUnit = mkOption {
      type = types.nullOr types.str;
      readOnly = true;
      default = if cfg.enable && cfg.heartbeatWake then "factory-floor.service" else null;
      defaultText = lib.literalMD ''`"factory-floor.service"` when `enable` and `heartbeatWake`, else `null`'';
      description = "The unit the heartbeat wakes (home/scheduled.nix reads it), or null for no wake.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(builtins.elem cfg.host [
            ""
            "*"
            "0.0.0.0"
            "::"
            "[::]"
          ]);
        message = "services.factory-floor.host must not be a wildcard address; the floor binds loopback.";
      }
    ];

    systemd.user.services.factory-floor = {
      Unit = {
        Description = "Factory floor (agency: a Cordis orchestrator on herdr-core)";
        Documentation = [ "https://github.com/mecattaf/dotfiles/blob/main/docs/factory-floor.md" ];
        After = [
          "network-online.target"
          "hc-core.service"
        ];
        Wants = [ "hc-core.service" ];
        StartLimitIntervalSec = 600;
        StartLimitBurst = 10;
        ConditionPathExists = entryPath;
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "exec";
        ExecStart = "${launcher}/bin/factory-floor-service";
        Environment = [
          "FACTORY_FLOOR_CHECKOUT=${cfg.checkout}"
          "FACTORY_FLOOR_ENTRY=${entryPath}"
          "FACTORY_FLOOR_STATE_DIR=${cfg.stateDir}"
          "FACTORY_FLOOR_WORK_DIR=${cfg.workDir}"
          "FACTORY_FLOOR_CONFIG_DIR=${cfg.configDir}"
          "FACTORY_FLOOR_HOST=${cfg.host}"
          "FACTORY_FLOOR_PORT=${toString cfg.port}"
          "HC_BIN=${lib.getExe' herdrCore "herdr-core"}"
        ];
        UnsetEnvironment = unsetEnvironment;
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 15;
        # 78 (EX_CONFIG) is the launcher's "the checkout is not built": no retry.
        RestartPreventExitStatus = 78;
        KillSignal = "SIGTERM";
        TimeoutStopSec = 60;
      };
      Install = lib.mkIf cfg.autostart { WantedBy = [ "default.target" ]; };
    };
  };
}
