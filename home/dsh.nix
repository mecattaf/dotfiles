{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# dsh (DeepSeek Harness) on the agent host (T-31). The package, its policy and
# its sandbox runner live in pkgs/dsh; this module only decides where it is
# installed and hands it the host's agenix path for the Qwen key.
#
# Nothing here touches ~/.dsh. Everything there is dsh's own state, and its
# profile files are replaced by atomic rename on settings writes, which would
# break the next activation if Home Manager owned them. The policy reaches
# every DSH_HOME as store `--patch` overlays the wrapper adds instead.
#
# No units, no timers: dsh runs by hand, and unattended runs belong to
# substrate.
let
  cfg = config.programs.dsh;
  link = config.lib.rawDotfiles.link;
  # A host that does not declare the secret gets no key path, and the route
  # fails MISSING_CREDENTIAL instead of reading /run.
  qwenKeyFile = lib.attrByPath [ "age" "secrets" "qwencloud-token" "path" ] null osConfig;
in
{
  options.programs.dsh.enable = lib.mkOption {
    type = lib.types.bool;
    # The agent host only. The laptop client never gets dsh; the NAS takes
    # over after the 10-23 migration (T-26), with the key moved there.
    default = osConfig.networking.hostName == "strix";
    description = "Install the fleet's wrapped dsh (pkgs/dsh).";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ (pkgs.dsh.override { inherit qwenKeyFile; }) ];

    # dsh reads $DSH_HOME/AGENTS.md, then ~/.agents/AGENTS.md. The ~/.agents
    # copy survives any DSH_HOME and gives dsh agents the same runtime-test
    # rule Codex gets through ~/.codex/AGENTS.md (home/home.nix). Skills
    # already reach dsh through ~/.agents/skills.
    home.file.".agents/AGENTS.md".source = link "agent-runtime-rules.md";
  };
}
