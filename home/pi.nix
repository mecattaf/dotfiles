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
# dependencies. pi-llama-swap has none — every non-relative import is either
# `import type` (erased before module resolution) or a node: builtin, and its
# sole package.json dependency (undici-types) is types-only. So the store SOURCE
# *is* the loadable package. An extension that DID carry runtime deps would need
# pkgs.buildNpmPackage (with an npmDepsHash) to vendor node_modules — swap `src`
# for that derivation and the rest of this module is unchanged.
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
  # Embedded home-manager exposes the host's evaluated NixOS config here. Only
  # load the local provider where that host actually runs llama-swap; Pi itself
  # remains available everywhere.
  llamaSwap = lib.attrByPath [ "services" "llama-swap" ] null osConfig;
  hasLocalLlamaSwap = llamaSwap != null && llamaSwap.enable;

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

  # ── Local inference providers (flashnix pair + llama-swap) ───────────────
  # These three lived ONLY in a hand-edited ~/.pi/agent/models.json, which this
  # module also generates — so every `home-manager switch` silently reverted the
  # file to the qwen-token-plan-only version and local AI went dark until someone
  # re-pasted them. Declaring them here is the fix: the generated file now IS the
  # roster, and a switch is a no-op instead of a regression.
  #
  # WHY THESE AND NOT the pi-llama-swap extension's dynamic discovery: that
  # extension registers ONE provider (`llama-swap`) against LLAMA_SWAP_PORT on
  # localhost, so it can neither reach the worker's proxy nor name the two
  # planes apart in a receipt. The static entries below are addressable by an
  # exact `--provider/--model` pair, which is what the flashnix bring-up
  # receipts quote verbatim. Both routes coexist; neither shadows the other.
  #
  # WHY UNCONDITIONAL (no `hasLocalLlamaSwap` gate): a provider entry is an inert
  # endpoint declaration — pi dials it only when a run names it. Gating would
  # reintroduce exactly the failure this commit removes, i.e. a host evaluating
  # to a models.json with no local providers in it. Cost of keeping them
  # everywhere is three unreachable rows in `pi --list-models`.
  zeroCost = {
    input = 0;
    output = 0;
    cacheRead = 0;
    cacheWrite = 0;
  };

  # llama-swap and the vLLM lane are both auth-free on the LAN; pi still wants a
  # non-empty key or it refuses to build the Authorization header.
  openaiCompat = {
    supportsDeveloperRole = false;
    supportsReasoningEffort = false;
    supportsStore = false;
  };

  # This host's own proxy port where NixOS declares it, else the fleet-wide
  # convention (modules/llama-swap.nix pins 9292 on every box that runs it).
  llamaSwapPort = if hasLocalLlamaSwap then llamaSwap.port else 9292;

  localModelsJson = {
    providers = {
      # The flashnix TP=2 vLLM pair (modules/flashnext-lane.nix arbitrates it
      # against llama-swap — exactly one plane holds the GPUs at a time, so this
      # provider answers only while the pair is up).
      flashnix-local = {
        api = "openai-completions";
        apiKey = "flashnix-local-no-auth";
        authHeader = true;
        baseUrl = "http://127.0.0.1:1234/v1";
        compat = openaiCompat;
        models = [
          {
            id = "flashnix";
            name = "Qwen3.8-Flash-Next FP8 (flashnix pair, TP=2)";
            contextWindow = 262144;
            maxTokens = 32768;
            input = [ "text" ];
            reasoning = false;
            cost = zeroCost;
          }
        ];
      };

      llama-swap-coordinator = {
        api = "openai-completions";
        apiKey = "llama-swap-no-auth";
        authHeader = true;
        baseUrl = "http://127.0.0.1:${toString llamaSwapPort}/v1";
        compat = openaiCompat;
        models = [
          {
            id = "qwen3.8-27b";
            name = "Qwen3.8 27B Q8_0 (llama-swap, coordinator)";
            contextWindow = 32768;
            maxTokens = 8192;
            input = [ "text" ];
            reasoning = false;
            cost = zeroCost;
          }
          {
            id = "qwen3.6-35b-a3b";
            name = "Qwen3.6 35B-A3B MTP (llama-swap, coordinator)";
            contextWindow = 32768;
            maxTokens = 8192;
            input = [ "text" ];
            reasoning = false;
            cost = zeroCost;
          }
        ];
      };

      # The twin's proxy, by hostname — resolved over the same 10.42.0.0/24 the
      # weight staging uses, not over Tailscale.
      llama-swap-worker = {
        api = "openai-completions";
        apiKey = "llama-swap-no-auth";
        authHeader = true;
        baseUrl = "http://worker:9292/v1";
        compat = openaiCompat;
        models = [
          {
            id = "gemma4-31b-it";
            name = "Gemma4 31B IT (llama-swap, worker)";
            contextWindow = 32768;
            maxTokens = 8192;
            input = [ "text" ];
            reasoning = false;
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
  extensions = {
    # llama-swap provider with dynamic model discovery — feeds the local model
    # roster served on this box (see modules/llama-swap.nix) into pi as a
    # first-class provider. https://pi.dev/packages/@danielmeneses/pi-llama-swap
    pi-llama-swap = {
      enable = hasLocalLlamaSwap;
      src = pkgs.pi-llama-swap-extension;
    };
  };

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
    # The extension's upstream default is :8080; our one caller-facing local
    # LLM endpoint comes from this host's service config. Preserve an explicit
    # caller override for diagnostics and remote endpoints.
    ${lib.optionalString hasLocalLlamaSwap ''
      if test -z "''${LLAMA_SWAP_URL-}" && test -z "''${LLAMA_SWAP_PORT-}"; then
        export LLAMA_SWAP_PORT=${toString llamaSwap.port}
      fi
    ''}
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
