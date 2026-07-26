# DRAFT — NOT IMPORTED YET. Wired in at T0 (see flows/README.md) after the
# flow-era tally input bump, next to home/tally.nix on coordinator. Every flow is
# one-shot (onCalendar = null): registered and flake-check-validated, invoked
# manually with `tally flow run`. Args here are the defaults; override per run
# with --args.
{ ... }:
let
  dotfiles = "/home/tom/mecattaf/dotfiles";
  notes = "/home/tom/mecattaf/notes";
  worktrees = "/home/tom/.local/state/tally-worktrees";
in
{
  services.tally.flows = {
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
        coordinatorFlake = dotfiles;
        # worker builds from its own checkout via the SSH executor
        workerFlake = "/home/tom/dotfiles";
        # Populate only from the accepted canonical allowlist after it lands;
        # uncensored = heretic artifacts only. Never include the retired
        # deepseek-v4-flash model or MTP artifact.
        coordinatorModels = [ ];
        workerModels = [ ];
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
