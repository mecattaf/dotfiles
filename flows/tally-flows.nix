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
  # 2026-09-13: pin each script to its own store path. The tally module types
  # `script` and `catalog` as types.path, so a bare `./X.js` rendered as
  # /nix/store/<hash>-source/flows/X.js: the whole flake source. Every commit,
  # even a DECISIONS.md-only one, then changed tally's checked config, and its
  # restartTriggers restarted tally-daemon on the next coordinator switch.
  # builtins.path copies just the file, so the store path follows the file's
  # content. The flow scripts have no relative imports (errata-map reads the
  # catalog through its own option), so a lone file is complete.
  pin =
    p:
    builtins.path {
      path = p;
      name = baseNameOf (toString p);
    };
in
{
  services.tally.flows = lib.optionalAttrs isCoordinator {
    allowlist-implementation = {
      script = pin ./allowlist-implementation.js;
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
      script = pin ./parakeet-determinism.js;
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
      script = pin ./materialize-model-weights.js;
      onCalendar = null;
      maxNodes = 64;
      args = {
        flake = dotfiles;
        # Left empty on purpose: the flow refuses at run time. Model bytes
        # reach a host only through the operator's local-models-borrow
        # transaction, never through a flake build.
        models = [ ];
      };
    };

    docs-model-split = {
      script = pin ./docs-model-split.js;
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
      script = pin ./issue-96-drain.js;
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
      script = pin ./errata-map.js;
      onCalendar = null;
      maxNodes = 400;
      catalog = pin ./catalog.json;
      args = {
        notesRepo = notes;
        outDir = "${notes}/july23-notes-reshape";
        maxRows = 60;
      };
    };
  };
}
