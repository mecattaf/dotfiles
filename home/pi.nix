{
  lib,
  osConfig,
  pkgs,
  ...
}:
# pi extensions — the nix-native, immutable analog of `pi install`.
#
# `pi install npm:@foo/bar` is the IMPURE path: it fetches over the network into
# ~/.pi/agent/{npm,git}/ and mutates ~/.pi/agent/settings.json. We do neither.
# Instead each extension is fetched into the store (fetchFromGitHub, pinned by
# rev+hash) and handed to pi as a `-e <store-path>` flag through a thin wrapper.
# pi reads the package's package.json `pi` manifest and loads its resources IN
# PLACE — no copy, no network, no npm install (see below). settings.json stays
# 100% pi-owned and mutable; the roster lives here, in git, reproducibly.
#
# WHY -e AND NOT settings.json `packages`/`extensions`: settings.json is state
# pi writes to (theme, lastChangelogVersion, `pi config` toggles). Managing it
# from home-manager would make it a read-only symlink and fight those writes.
# The wrapper keeps the two planes cleanly separated — declared here, state there.
#
# WHY NO BUILD STEP: these are pi packages, i.e. TypeScript that pi transpiles
# and runs itself. A package needs a Nix build only if it has real *runtime*
# dependencies. A pure-TypeScript extension (only `import type` and node:
# builtins) loads straight from the store SOURCE. An extension that DID carry
# runtime deps would need pkgs.buildNpmPackage (with an npmDepsHash) to vendor
# node_modules — swap `src` for that derivation and the rest of this module is
# unchanged.
#
# LAZY LOADING (the nvim question): pi loads extensions eagerly at startup —
# they're cheap JS modules, so there is no per-keystroke `lazy`-style deferral to
# win here. The knobs that matter are (1) the `enable` flag below — the exact
# analog of commenting a plugin out of a lazy.nvim spec — and (2) genuinely
# conditional loading, which pi already does via project-local `.pi/settings.json`
# (`packages`/`extensions` arrays, loaded only in trusted project dirs). Reach for
# the latter to scope an extension to one repo instead of the whole fleet.
#
let
  # Embedded home-manager exposes the host's evaluated NixOS config here. The
  # fleet's one local endpoint is the worker's Halogen server; its address and
  # model id come from modules/halogen.nix's client options on whichever host
  # renders this, falling back to the fleet convention where that module is
  # not imported.
  halogen = lib.attrByPath [ "services" "halogen" ] null osConfig;
  halogenEndpoint = if halogen != null then halogen.client.endpoint else "http://worker:8731";
  halogenModelId = if halogen != null then halogen.modelId else "halogen-qwen3.8-flash-next";

  # ── Qwen Token Plan (Alibaba MaaS subscription) ──────────────────────────
  # pi ships `qwen-token-plan` as a BUILT-IN provider on exactly our endpoint
  # (https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1), so
  # nothing here registers a provider — models.json only (a) supplies the key and
  # (b) upserts the two model ids the live endpoint serves that pi 0.82.1's
  # bundled catalog does not yet know. Verified 2026-08-07 against GET /v1/models
  # plus a real completion per model.
  #
  # Gated on the agenix secret actually being delivered on this host, so the
  # laptop never grows a models.json pointing at a /run path it cannot read.
  qwenTokenPath = lib.attrByPath [ "age" "secrets" "qwencloud-token" "path" ] null osConfig;
  hasQwenTokenPlan = qwenTokenPath != null;

  # WHY `!cat` AND NOT $QWEN_TOKEN_PLAN_API_KEY (the env var pi's built-in
  # provider also accepts): an exported key is inherited by every process pi's
  # bash tool spawns, so any agent turn could read it back out of its own
  # environment. models.json's `!command` form is resolved by pi itself at
  # request time (and cached in-process), so the key never enters the agent's
  # environment at all.
  qwenModelsJson = {
    providers.qwen-token-plan = {
      apiKey = "!cat ${toString qwenTokenPath}";

      # Only ids missing from the bundled catalog. `qwen3.7-max` and `glm-5.2`
      # are already built in verbatim and are deliberately NOT redeclared here —
      # models.json REPLACES a built-in entry it names, so restating them would
      # freeze their metadata at today's values for no gain. Delete an entry
      # below once pi's own catalog ships that id.
      models = [
        # Endpoint serves `qwen3.8-max`; pi 0.82.1 only knows `qwen3.8-max-preview`.
        # Metadata mirrors that sibling. Image input confirmed live — a 1x1 PNG was
        # rejected for being under the 10px floor, not for being an image.
        {
          id = "qwen3.8-max";
          name = "Qwen3.8 Max";
          api = "openai-completions";
          baseUrl = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1";
          reasoning = true;
          input = [
            "text"
            "image"
          ];
          contextWindow = 1000000;
          maxTokens = 131072;
          # Subscription plan: usage is metered in plan credits, not dollars, so
          # every rate is zero — same as the built-in entries for this provider.
          cost = {
            input = 0;
            output = 0;
            cacheRead = 0;
            cacheWrite = 0;
          };
          compat = {
            thinkingFormat = "qwen"; # DashScope top-level enable_thinking
            supportsDeveloperRole = false;
            supportsStore = false;
          };
        }

        # Endpoint serves the dated `deepseek-v4-flash-0731`; pi 0.82.1 knows the
        # undated `deepseek-v4-flash`. Text-only: the same image probe that
        # qwen3.8-max rejected on size was silently dropped here (prompt_tokens
        # unchanged), matching the sibling's `input = ["text"]`.
        {
          id = "deepseek-v4-flash-0731";
          name = "DeepSeek V4 Flash 0731";
          api = "openai-completions";
          baseUrl = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1";
          reasoning = true;
          input = [ "text" ];
          contextWindow = 1000000;
          maxTokens = 384000;
          cost = {
            input = 0;
            output = 0;
            cacheRead = 0;
            cacheWrite = 0;
          };
          compat = {
            thinkingFormat = "deepseek";
            supportsDeveloperRole = false;
            supportsStore = false;
            # Confirmed live: replies carry `reasoning_content`, which must be
            # echoed back on replayed assistant messages.
            requiresReasoningContentOnAssistantMessages = true;
          };
          # DeepSeek V4 exposes only high/max; the holes hide the rest from the
          # thinking picker instead of silently clamping them.
          thinkingLevelMap = {
            minimal = null;
            low = null;
            medium = null;
            high = "high";
            max = "max";
          };
        }
      ];
    };
  };

  # ── the local inference provider ─────────────────────────────────────────
  # Declared HERE, in the generated models.json, and unconditionally: a
  # provider entry is an inert endpoint declaration that pi dials only when a
  # run names it, so every host renders the same row and a `home-manager
  # switch` can never regress a hand-edited file back to cloud-only. The row
  # is addressable by an exact `--provider/--model` pair, which is what
  # receipts quote verbatim.
  zeroCost = {
    input = 0;
    output = 0;
    cacheRead = 0;
    cacheWrite = 0;
  };

  # Halogen is auth-free on the LAN; pi still wants a non-empty key or it
  # refuses to build the Authorization header.
  openaiCompat = {
    supportsDeveloperRole = false;
    supportsReasoningEffort = false;
    supportsStore = false;
  };

  localModelsJson = {
    providers = {
      # The fleet's one local model: Halogen Flash on the worker, by hostname
      # over the house LAN (modules/halogen.nix). Vision-capable; reasoning is
      # on by default and the token budget covers thinking, so maxTokens is
      # generous. Halogen accepts pi's /v1/chat/completions shape and also
      # serves /v1/responses.
      halogen = {
        api = "openai-completions";
        apiKey = "halogen-no-auth";
        authHeader = true;
        baseUrl = "${halogenEndpoint}/v1";
        compat = openaiCompat;
        models = [
          {
            id = halogenModelId;
            name = "Qwen3.8-Flash-Next (Halogen, worker)";
            contextWindow = 262144;
            maxTokens = 32768;
            input = [
              "text"
              "image"
            ];
            reasoning = true;
            cost = zeroCost;
          }
        ];
      };
    };
  };

  # The cloud provider is the only one that needs a host gate: its key is an
  # agenix path that does not exist off the fleet. Local rows are always present.
  modelsJson = lib.recursiveUpdate localModelsJson (
    lib.optionalAttrs hasQwenTokenPlan qwenModelsJson
  );

  # ── extension roster ─────────────────────────────────────────────────────
  # One entry per extension — the whole "standard": a name, an `enable` toggle,
  # and an immutable `src`. Add a package by adding a stanza; disable one by
  # flipping `enable = false` (or deleting it). Update by bumping rev + hash
  # (nix-prefetch-url --unpack <github-archive-url>, then nix hash to-sri).
  # Empty today: the local provider is plain models.json config (above), which
  # needs no extension.
  extensions = { };

  # Enabled specs → a flat `-e <store-path>` argv the wrapper prepends.
  enabled = lib.filterAttrs (_: e: e.enable) extensions;
  loadArgs = lib.concatLists (
    lib.mapAttrsToList (_: e: [
      "-e"
      (toString e.src)
    ]) enabled
  );

  pi = pkgs.llm-agents.pi;

  # The wrapper IS the loader. Interactive/agent runs get the roster prepended;
  # management subcommands pass straight through so `pi install/remove/update/
  # list/config` still operate on the real (unshadowed) settings.json.
  piWrapped = pkgs.writeShellScriptBin "pi" ''
    case "''${1-}" in
      install | remove | uninstall | update | list | config)
        exec ${pi}/bin/pi "$@"
        ;;
    esac
    exec ${pi}/bin/pi ${lib.escapeShellArgs loadArgs} "$@"
  '';
in
{
  # Replaces the bare `pi` that home/home.nix used to pull from the llm-agents
  # buildEnv (that entry is dropped there so this is the only `pi` on PATH).
  home.packages = [ piWrapped ];

  # models.json is pure declared CONFIG, not pi state — pi only ever reads it
  # (re-reading on every /model open), so unlike settings.json it is safe to own
  # as a read-only store symlink. Same separation of planes as the `-e` roster
  # above: what we declare lives in git, what pi mutates stays in ~/.pi.
  #
  # Unconditional since 2026-09-03: it used to be gated on the agenix cloud token,
  # which meant a host without that secret got NO file at all and the local
  # providers below only existed as a hand-edit that the next switch destroyed.
  # The gate now lives on the one provider that actually needs it (see modelsJson).
  home.file.".pi/agent/models.json" = {
    source = (pkgs.formats.json { }).generate "pi-models.json" modelsJson;
  };
}
