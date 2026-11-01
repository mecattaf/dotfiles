{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

# The journal lane belongs to the agent host. The drain skill runs only where
# the Claude/Codex seats are (the NAS); on the thin client this activation
# used to create ~/mecattaf/notes/journal on every switch, an empty
# non-repository in a home Tom wants clean (2026-10-11). The brain role owns
# this agent state. Retrieval is external; activation only creates the manual
# drain destination and never indexes or rewrites existing notes.
let
  cfg = config.programs.ai-memory;
in
{
  options.programs.ai-memory.journalDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/mecattaf/notes/journal";
    description = ''
      Sole routing destination for manually drained AI-session journal notes.
    '';
  };

  config = lib.mkIf (osConfig.myFleet.has "brain") {
    xdg.configFile."ai-memory/config.json".text = builtins.toJSON {
      schema = 1;
      journal_dir = cfg.journalDir;
    };

    # The drain remains the sole writer of journal Markdown. Keep existing
    # notes and retired retrieval state untouched when the package is removed.
    home.activation.aiMemoryJournal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      journal_dir=${lib.escapeShellArg cfg.journalDir}
      run ${pkgs.coreutils}/bin/mkdir -p "$journal_dir"
    '';
  };
}
