# Imported by home/tally.nix and populated on coordinator only. Every flow is
# one-shot (onCalendar = null): registered and generation-validated, then invoked
# manually with `tally flow run`. Args here are the defaults; override per run
# with --args.
{
  lib,
  osConfig,
  ...
}:
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  dotfiles = "/home/tom/mecattaf/dotfiles";
  notes = "/home/tom/mecattaf/notes";
  worktrees = "/home/tom/.local/state/tally-worktrees";
in
{
  services.tally.flows = lib.optionalAttrs isCoordinator {
    allowlist-implementation = {
      script = ./allowlist-implementation.js;
      onCalendar = null;
      maxNodes = 4;
      args = {
        repository = dotfiles;
        baseRev = "main";
        branch = "flow/allowlist";
        worktree = "${worktrees}/allowlist";
      };
    };

    parakeet-determinism = {
      script = ./parakeet-determinism.js;
      onCalendar = null;
      maxNodes = 4;
      args = {
        repository = dotfiles;
        baseRev = "main";
        branch = "flow/parakeet";
        worktree = "${worktrees}/parakeet";
      };
    };

    materialize-model-weights = {
      script = ./materialize-model-weights.js;
      onCalendar = null;
      maxNodes = 64;
      args = {
        flake = dotfiles;
        # Populate only from the accepted canonical allowlist after it lands;
        # uncensored = heretic artifacts only. Never include the retired
        # deepseek-v4-flash model or MTP artifact.
        models = [ ];
      };
    };

    docs-model-split = {
      script = ./docs-model-split.js;
      onCalendar = null;
      maxNodes = 3;
      args = {
        repository = dotfiles;
        baseRev = "main";
        branch = "flow/docs-model-split";
        worktree = "${worktrees}/docs-model-split";
      };
    };

    issue-96-drain = {
      script = ./issue-96-drain.js;
      onCalendar = null;
      maxNodes = 5;
      args = {
        repository = dotfiles;
        baseRev = "main";
        branch = "flow/issue-96";
        worktree = "${worktrees}/issue-96";
        promptPath = "${notes}/july23-notes-reshape/HANDOFF-PROMPT-B-issue-96-drain.md";
        notesRepo = notes;
      };
    };

    errata-map = {
      script = ./errata-map.js;
      onCalendar = null;
      maxNodes = 400;
      catalog = ./catalog.json;
      args = {
        notesRepo = notes;
        outDir = "${notes}/july23-notes-reshape";
        maxRows = 60;
      };
    };
  };
}
