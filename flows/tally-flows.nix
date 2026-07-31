# Imported by home/tally.nix and populated on coordinator only. Every flow is
# one-shot (onCalendar = null): registered and generation-validated, then invoked
# manually with `tally flow run`. Args here are the defaults; override per run
# with --args.
{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  dotfiles = "/home/tom/mecattaf/dotfiles";
  notes = "/home/tom/mecattaf/notes";
  worktrees = "/home/tom/.local/state/tally-worktrees";

  academicState = "/home/tom/.local/state/academic-ocr";
  fixedPapers = builtins.fromJSON (builtins.readFile ../pkgs/academic-ocr/fixed-papers.json);
  turner = fixedPapers.turner;
  turnerId = turner.paperId;
  turnerSha = turner.sourceSha256;

  # The production drain flow + tools (home/academic-drain.nix runs the same
  # package 24/7; this registry entry generation-validates the flow and keeps
  # it invocable by name). Default args are the 5-page Turner acceptance
  # paper read from its NAS mirror — the per-paper drain overrides them.
  academicDrain = pkgs.callPackage ../pkgs/academic-ocr-drain {
    tally = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;
  };
  academicDrainLib = "${academicDrain}/libexec/academic-ocr-drain";

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

    # One mecattaf/crm build issue end-to-end: worktree prep, codex
    # implementation, deterministic go gates, push + PR. Invoked per issue by
    # the crm-build gh producer's dispatch job (home/tally.nix); the default
    # issue number below only satisfies generation validation.
    crm-issue = {
      script = ./crm-issue.js;
      onCalendar = null;
      maxNodes = 8;
      args = {
        issue = 1;
      };
    };

    # The production per-paper flow (replaces the retired academic-ocr /
    # academic-assemble Turner samples, 2026-07-29). R2 is purged: sources
    # are file:// paths into the NAS corpus of record.
    academic-paper-e2e = {
      script = "${academicDrainLib}/paper-e2e.js";
      onCalendar = null;
      maxNodes = 10000;
      args = {
        paperId = turnerId;
        title = turner.title;
        sourceUrl = "file:///mnt/nas/documents/academic-papers/originals/knowledge/psychology/mythopoetic/Victor-Turner-Betwixt-and-Between.pdf";
        sha256 = turnerSha;
        pageCount = 5;
        dataRoot = academicState;
        tools = academicDrainLib;
        bash = "${pkgs.bash}/bin/bash";
        dpi = 200;
        ocrModel = "qwen3-vl-8b-ocr";
        refineModel = "qwen3-vl-32b-ocr";
        embedModel = "qwen3-embedding-8b";
        minAgreementPermille = 700;
      };
    };
  };
}
