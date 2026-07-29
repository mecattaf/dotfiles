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
  turnerBlob = "${academicState}/blobs/sha256/${turnerSha}.pdf";
  turnerRun = "${academicState}/runs/${turnerId}-${builtins.substring 0 12 turnerSha}";
  turnerPages = map (pageNumber: {
    paperId = turnerId;
    inherit pageNumber;
    sourcePath = turnerBlob;
  }) (lib.range 1 5);
  academicProtocols = [
    {
      id = "poppler-text";
      tier = "cheap";
    }
    {
      id = "mupdf-text";
      tier = "cheap";
    }
    {
      id = "qwen3-vl-8b-ocr";
      tier = "standard";
    }
    {
      id = "qwen3-vl-32b-ocr";
      tier = "specialist";
    }
  ];
  academicDriver = {
    adapter = "ocr-driver";
    program = "${pkgs.academic-ocr}/bin/academic-ocr-driver";
    runtimeMaxSec = 1800;
  };

  # Keep the pinned upstream control program. Only the ruled physical pool name
  # changes at build time; no forked JavaScript source lives in dotfiles.
  academicOcrFlow = pkgs.runCommand "academic-ocr-flow.js" { } ''
    substitute ${inputs.tally}/examples/flows/academic-ocr.js "$out" \
      --replace-fail '"ocr-gpu"' '"coordinator-gpu"'
  '';

  sampleSelections = map (pageNumber: {
    paperId = turnerId;
    inherit pageNumber;
    status = "converged";
    resolution = "tier";
    inputVariant = "original";
    chosenArtifactPath = "${turnerRun}/ocr/${turnerId}/page-${toString pageNumber}/qwen3-vl-8b-ocr/original.json";
    textDigest = "sha256:${builtins.hashString "sha256" "turner-page-${toString pageNumber}-sample"}";
    disagreementPermille = 0;
    agreementProtocols = [
      "qwen3-vl-32b-ocr"
      "qwen3-vl-8b-ocr"
    ];
    attemptCount = 4;
    proof = {
      taskUuid = "00000000-0000-4000-8000-000000000124";
      witnessSeq = pageNumber;
    };
  }) (lib.range 1 5);
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

    academic-ocr = {
      script = academicOcrFlow;
      onCalendar = null;
      maxNodes = 1700;
      args = {
        pages = turnerPages;
        protocols = academicProtocols;
        driver = academicDriver;
        outputDir = "${turnerRun}/ocr";
        rasterDpi = 400;
        maxMutationIterations = 3;
        maxDisagreementPermille = 375;
      };
    };

    academic-assemble = {
      script = ./academic-assemble.js;
      onCalendar = null;
      maxNodes = 6;
      args = {
        paper = {
          paperId = turnerId;
          title = turner.title;
          sourceUrl = turner.sourceUrl;
          sourceSha256 = turnerSha;
        };
        pages = sampleSelections;
        protocols = academicProtocols;
        driver = academicDriver;
        outputDir = "${turnerRun}/package";
        receiptPath = "${turnerRun}/receipt.json";
        chunkWords = 512;
        embedding = {
          endpoint = "http://localhost:9292";
          model = "qwen3-embedding-8b";
          batchSize = 16;
          dimensions = 4096;
        };
      };
    };
  };
}
