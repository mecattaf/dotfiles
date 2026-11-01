{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# dsh (DeepSeek Harness) on the agent host (T-31). The package, its policy and
# its sandbox runner live in pkgs/dsh; this module selects its installed
# plugins on the agent host. The QwenCloud credential was retired 2026-11-01.
#
# Nothing here touches ~/.dsh. Everything there is dsh's own state, and its
# profile files are replaced by atomic rename on settings writes, which would
# break the next activation if Home Manager owned them. The policy reaches
# every DSH_HOME as store `--patch` overlays the wrapper adds instead, and the
# wrapper links each hand-run profile's selected plugins into
# $DSH_HOME/profiles/<name> when it boots (pkgs/dsh, pkgs/dsh-plugins).
#
# No units, no timers: dsh runs by hand, and unattended runs belong to
# substrate.
let
  cfg = config.programs.dsh;
  link = config.lib.rawDotfiles.link;
in
{
  options.programs.dsh.enable = lib.mkOption {
    type = lib.types.bool;
    # Harnesses and their credentials follow the brain role to the NAS.
    default = osConfig.myFleet.has "brain";
    description = "Install the fleet's wrapped dsh (pkgs/dsh).";
  };
  options.programs.dsh.plugins = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf (lib.types.enum (builtins.attrNames pkgs.dsh-plugins)));
    default = pkgs.dsh.profilePlugins;
    description = "Nix-delivered plugins selected by each hand-run DSH profile.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.dsh.override {
        qwenKeyFile = null;
        profilePlugins = cfg.plugins;
      })
      pkgs.mnemon
    ];

    # dsh reads $DSH_HOME/AGENTS.md, then ~/.agents/AGENTS.md. The ~/.agents
    # copy survives any DSH_HOME and gives dsh agents the same runtime-test
    # rule Codex gets through ~/.codex/AGENTS.md (home/home.nix). Skills
    # already reach dsh through ~/.agents/skills.
    home.file.".agents/AGENTS.md".source = link "agent-runtime-rules.md";
  };
}
