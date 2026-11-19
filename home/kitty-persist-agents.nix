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
#   Claude Code   hook entries written by the program's own
#   and Codex     `kitty-persist harness install NAME [--dir DIR]`, run by the
#                 remote-host module's user unit kitty-persist-hooks.service
#                 (services.kitty-persist.hooks in hosts/nas). Every entry
#                 runs the bare `kitty-persist hook NAME EVENT` found on PATH,
#                 so an update of the program never changes an entry or
#                 Codex's trust hash. Both Claude seats' settings.json are
#                 links to ~/.local/state/claude/settings.json
#                 (home/claude-settings.py); the program follows the link and
#                 replaces its target, so the links stay as they are, and the
#                 second seat's install finds the entries already there.
#   dsh           no settings file: the kitty-persist-hooks plugin
#                 (pkgs/dsh-plugins) is selected for each hand-run profile,
#                 and one harness definition per profile goes to
#                 ~/.config/kitty-persist/harness/dsh-<profile>.json. Each
#                 file is checked with `kitty-persist harness check` when it
#                 is built: a definition the program refuses fails the build.
#
# This module adds the dsh half and the resume overrides; it writes no agent
# settings itself. home/kitty-persist-hooks.py is the owner's dry run (the
# same installs on copies) and the after-activation check. The agents' own
# notifications are never forced or silenced: the hooks report state only.
# The launchers (cc, cc2, cac, cac2, cx, cax) need no wrapper.
let
  cfg = config.programs.kittyPersist.agents;
  hooksPlugin = pkgs.dsh-plugins.kitty-persist-hooks;
  defs = hooksPlugin.definitions;
  program = lib.getExe' cfg.package "kitty-persist";

  # A dsh definition as a file the program accepts: `harness check` runs on
  # it at build time, with the program the host installs.
  checked =
    profile:
    let
      name = defs.harnessName profile;
    in
    pkgs.runCommand "kitty-persist-${name}.json"
      {
        definition = builtins.toJSON (defs.definition profile) + "\n";
        passAsFile = [ "definition" ];
      }
      ''
        export HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR/config"
        cp "$definitionPath" ${name}.json
        ${program} harness check ${name}.json
        cp ${name}.json "$out"
      '';

  # A shipped definition with the launcher's flags put back into its resume
  # command, made from the program's own copy (`harness show NAME`) so that
  # recognition, events and install never drift from it. A file named like a
  # shipped definition replaces it (S21.5); it is checked like the dsh ones.
  override =
    name: flags: env:
    pkgs.runCommand "kitty-persist-${name}.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        flags = builtins.toJSON flags;
        carried = builtins.toJSON env;
      }
      ''
        export HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR/config"
        ${program} harness show ${name} > shipped.json
        jq --argjson flags "$flags" --argjson env "$carried" '
          .resume.command = [.resume.command[0]] + $flags + .resume.command[1:]
          | .resume.env = ((.resume.env // []) + $env | unique)
        ' shipped.json > ${name}.json
        ${program} harness check ${name}.json
        cp ${name}.json "$out"
      '';
in
{
  options.programs.kittyPersist.agents = {
    enable = lib.mkEnableOption "the dsh half of kitty-persist's agent hooks and the resume overrides on the session host";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The kitty-persist program the host installs (the remote-host module's
        package). It checks the generated definitions and prints the shipped
        ones the overrides are made from; the hooks themselves call the bare
        `kitty-persist` on PATH.
      '';
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
      description = "Flags put after the program name in a shipped definition's resume command (one override definition per name).";
    };

    resumeEnv = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      # Set by __claude_seat for the claude process only, so the resume
      # shell has it only if it is carried.
      default.claude = [ "CLAUDE_CODE_DISABLE_AGENT_VIEW" ];
      description = "Variables added to a shipped definition's carried environment.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Added to each profile's default plugins (same priority as the default,
    # so the lists merge); an explicit programs.dsh.plugins still wins.
    programs.dsh.plugins = lib.mkOptionDefault (
      lib.genAttrs cfg.dsh.profiles (_: [ "kitty-persist-hooks" ])
    );
    xdg.configFile =
      lib.listToAttrs (
        map (
          profile:
          lib.nameValuePair "kitty-persist/harness/${defs.harnessName profile}.json" {
            source = checked profile;
          }
        ) cfg.dsh.profiles
      )
      // lib.mapAttrs' (
        name: flags:
        lib.nameValuePair "kitty-persist/harness/${name}.json" {
          source = override name flags (cfg.resumeEnv.${name} or [ ]);
        }
      ) (lib.filterAttrs (_: flags: flags != [ ]) cfg.resumeFlags);
  };
}
