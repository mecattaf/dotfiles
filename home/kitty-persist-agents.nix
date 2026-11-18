{
  config,
  lib,
  pkgs,
  ...
}:
# kitty-persist agent integration on the host that holds the sessions: the
# agents' own hooks report their state (S21 to S23 of the kitty-persist
# specification), and a restarted host brings running agents back through
# each harness definition's resume command.
#
#   Claude Code   `kitty-persist harness install claude`, once, into the
#                 settings file both seats share: ~/.claude/settings.json and
#                 ~/.claude-work/settings.json are links to
#                 ~/.local/state/claude/settings.json (home/claude-settings.py).
#                 The install is pointed at that file's own directory, so its
#                 temp-file-and-rename replaces the file, never a seat link.
#   Codex         `kitty-persist harness install codex` into the mutable,
#                 unmanaged ~/.codex/config.toml; the program keeps comments and
#                 records the trust hashes Codex asks for.
#   dsh           no settings file: the kitty-persist-hooks plugin
#                 (pkgs/dsh-plugins) is selected for each hand-run profile, and
#                 one harness definition per profile goes to
#                 ~/.config/kitty-persist/harness/dsh-<profile>.json.
#
# home/kitty-persist-hooks.py wraps both installs and checks that nothing else
# in either file changed, that no notification override appeared and that the
# seat links survived; it puts the previous bytes back otherwise. The agents'
# own notifications are never forced or silenced here: the hooks report state
# only. The launchers (cc, cc2, cac, cac2, cx, cax) need no wrapper.
#
# Hooks are harmless outside a kitty-persist session (the hook exits at once
# when KITTY_PERSIST_ID is unset), so they are installed once and left in
# place. Removing them: `harness uninstall` through the same wrapper (see the
# activation step below with `uninstall`).
#
# DRAFT. The kitty-persist program with `hook` and `harness install` is not in
# the flake input yet: `package` stays null until it is, and then only the
# dsh plugin and the dsh definitions are in effect (the plugin finds the
# program on PATH). See the follow-up notes at `package` and `resumeFlags`.
let
  cfg = config.programs.kittyPersist.agents;
  hooksPlugin = pkgs.dsh-plugins.kitty-persist-hooks;
  defs = hooksPlugin.definitions;
  home = config.home.homeDirectory;

  # A shipped definition with the launcher's flags put back into its resume
  # command, built from the program's own copy so recognition and events never
  # drift. A file named like a shipped definition replaces it (S21.5).
  # FOLLOW-UP: the subcommand and field paths (`harness show NAME`,
  # .resume.command, .resume.env) are the draft names; match them to the
  # published schema.
  override =
    name: flags: env:
    pkgs.runCommand "kitty-persist-${name}-definition.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        flags = builtins.toJSON flags;
        carried = builtins.toJSON env;
      }
      ''
        export HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR/config"
        ${lib.getExe' cfg.package "kitty-persist"} harness show ${name} > shipped.json
        jq --argjson flags "$flags" --argjson env "$carried" '
          .resume.command = [.resume.command[0]] + $flags + .resume.command[1:]
          | .resume.env = ((.resume.env // []) + $env | unique)
        ' shipped.json > "$out"
      '';

  # One run of home/kitty-persist-hooks.py, as an activation command line.
  wrapper =
    verb:
    lib.concatStringsSep " " (
      [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${./kitty-persist-hooks.py}"
        verb
        "--program"
        (lib.getExe' cfg.package "kitty-persist")
        "--home"
        ''"$HOME"''
      ]
      ++ lib.optionals cfg.claude.enable (
        [
          "--claude-dir"
          (lib.escapeShellArg cfg.claude.settingsDir)
        ]
        ++ lib.concatMap (seat: [
          "--claude-seat"
          (lib.escapeShellArg seat)
        ]) cfg.claude.seats
      )
      ++ lib.optionals cfg.codex.enable [
        "--codex-home"
        ''"''${CODEX_HOME:-${home}/.codex}"''
      ]
    );
in
{
  options.programs.kittyPersist.agents = {
    enable = lib.mkEnableOption "kitty-persist agent hooks and harness definitions on the session host";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The kitty-persist program with the `hook` and `harness` commands. null
        until the flake input exposes it (the pinned input's packages predate
        the one-program build); then the Claude and Codex installs and the
        resume overrides are skipped with a warning.
      '';
    };

    installHooks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the hook installs for Claude Code and Codex at every activation (idempotent: an unchanged file is not written).";
    };

    claude = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the Claude Code hooks.";
      };
      settingsDir = lib.mkOption {
        type = lib.types.str;
        default = "${home}/.local/state/claude";
        description = "Directory of the settings file every seat links to; the install targets it directly.";
      };
      seats = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "${home}/.claude"
          "${home}/.claude-work"
        ];
        description = "Seat directories whose settings.json link must survive the install.";
      };
    };

    codex.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the Codex hooks into $CODEX_HOME/config.toml (default ~/.codex).";
    };

    dsh.profiles = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (builtins.attrNames pkgs.dsh.profilePlugins));
      default = builtins.attrNames pkgs.dsh.profilePlugins;
      description = "Hand-run dsh profiles that load the kitty-persist-hooks plugin and get a harness definition. Never the stock headless, sdk or acp profiles.";
    };

    resumeFlags = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      # The fish launchers' flags (home/dot_config/fish/config.fish): an agent
      # brought back after a restart runs as it was started.
      default = {
        claude = [ "--dangerously-skip-permissions" ];
        codex = [
          "--disable"
          "daemon_auto_start"
          "--dangerously-bypass-approvals-and-sandbox"
        ];
      };
      description = "Flags put after the program name in a shipped definition's resume command (an override definition per name). Needs `package`.";
    };

    resumeEnv = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      # Set by __claude_seat for the claude process only, so the resume
      # shell has it only if it is carried.
      default.claude = [ "CLAUDE_CODE_DISABLE_AGENT_VIEW" ];
      description = "Variables added to a shipped definition's carried environment.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Added to each profile's default plugins (same priority as the
        # default, so the lists merge); an explicit programs.dsh.plugins still
        # wins.
        programs.dsh.plugins = lib.mkOptionDefault (
          lib.genAttrs cfg.dsh.profiles (_: [ "kitty-persist-hooks" ])
        );
        xdg.configFile = lib.listToAttrs (
          map (
            profile:
            lib.nameValuePair "kitty-persist/harness/${defs.harnessName profile}.json" {
              text = builtins.toJSON (defs.definition profile) + "\n";
            }
          ) cfg.dsh.profiles
        );
      }
      (lib.mkIf (cfg.package == null) {
        warnings = [
          "programs.kittyPersist.agents: no kitty-persist package with `hook` and `harness` yet; the Claude Code and Codex hook installs and the resume overrides are skipped."
        ];
      })
      (lib.mkIf (cfg.package != null) {
        xdg.configFile = lib.mapAttrs' (
          name: flags:
          lib.nameValuePair "kitty-persist/harness/${name}.json" {
            source = override name flags (cfg.resumeEnv.${name} or [ ]);
          }
        ) (lib.filterAttrs (_: flags: flags != [ ]) cfg.resumeFlags);
      })
      (lib.mkIf (cfg.package != null && cfg.installHooks) {
        # After the seeder made the shared Claude file and the seat links.
        home.activation.kittyPersistHooks = lib.hm.dag.entryAfter [ "linkGeneration" "claudeSettings" ] ''
          if ! run ${wrapper "install"}; then
            echo "kitty-persist hooks: not installed; see the lines above (the previous files were kept)" >&2
          fi
        '';
      })
    ]
  );
}
