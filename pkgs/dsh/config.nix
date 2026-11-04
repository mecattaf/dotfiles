{
  lib,
  formats,
  runner,
  mnemon,
  profilePlugins,
}:
# dsh (DeepSeek Harness 0.2.1-rc.2) fleet policy as Nix data.
#
# Rendered by pkgs.formats.yaml, which can only emit plain data: no `!!js` tag
# can reach these files, so they are never code. The one `!!js` row the fleet
# needs (the sessions root, which must follow DSH_HOME) is hand-written in
# ./sessions.patch.yml. Every output here is a `--patch` overlay the wrapper
# (./default.nix) puts after the profile word, so it is the LAST config layer
# whatever DSH_HOME is in use: after the bundles, after the profile's own
# writable cordis.patch.yml, after $DSH_HOME/cordis.patch.yml. Nix manages no
# file inside ~/.dsh.
#
# A patch REPLACES a row's whole `config`, never merges it, so each row below
# restates every key it keeps. A patch whose id matches no row is skipped with
# a warning on stderr; checks.dsh-config fails on any stderr from a dump.
#
# Outputs:
#   policy : every profile the wrapper boots (headless, sdk, acp, herdr, mnemon, zen)
#   acp    : acp only; its bundle pins the official DeepSeek route in its own row
#   herdr  : the hand-run plugin profile only (jevcore's row; ./default.nix)
#   mnemon : the dedicated local-memory profile, including its Gufo route
#   zen    : the hand-run OpenCode Zen free-model profile (jiesou's provider
#            plugin, credentials re-enabled, Zen as the default route)
#   routeOverlays : one-row `agent-default-model` overlays, one per name in
#            `routes`, for `DSH_ROUTE=<name>` (./default.nix). The keyed free
#            lanes (Gemini, Groq, Mistral, Cohere, NVIDIA, Cloudflare Workers
#            AI, Hugging Face, Cerebras, Vercel AI Gateway) are selected only
#            this way; Gemini is the default
#   smoke  : the gate's one inference call (no retries, low effort); never
#            installed, built only as `nix build .#dsh.smoke`
let
  yaml = formats.yaml { };
  localModel = import ../../lib/local-model.nix;
  off = id: {
    inherit id;
    disabled = true;
  };
  set = id: config: { inherit id config; };

  # Google Gemini through llm-pi-ai's NATIVE catalog route `google` (api
  # google-generative-ai, https://generativelanguage.googleapis.com/v1beta,
  # pi-ai 1.3.0). The route name must stay `google`: a hand-declared name can
  # only use the openai-*/anthropic protocols. The wrapper puts one of three AI
  # Studio keys in GEMINI_API_KEY per run (DSH_KEY_SLOT, ./default.nix); naming
  # it here makes a missing key fail MISSING_CREDENTIAL instead of reading
  # anything ambient. `models` replaces the 23-id catalog; each entry defaults
  # from the catalog (3.8-flash: 1,048,576 context, 65,536 output, text+image,
  # thinking low/medium/high, so `reasoningEffort = "high"`, never `max`).
  # Free tier (AI Studio terms): prompts are used for training and human
  # review, so non-sensitive inputs only; anything sensitive stays on Gufo.
  # The 11 ids below were all served to the three keys on 2026-11-03;
  # gemini-3.1-pro-preview is paid-only, so it refuses a free key.
  # (The former `qwen-token-plan` route was deleted: the account closed
  # 2026-11-01 and its keyless rows could only fail MISSING_CREDENTIAL.)
  google = retryPolicy: {
    displayName = "Google Gemini (AI Studio)";
    apiKeyEnv = "GEMINI_API_KEY";
    # QUOTA and AUTH are never retried by dsh whatever this says.
    inherit retryPolicy;
    models = [
      { id = "gemini-3.8-flash"; } # default; free; strongest free-eligible
      { id = "gemini-3.7-flash"; } # free status unknown
      { id = "gemini-3.6-flash"; } # free
      { id = "gemini-3.5-flash"; } # free status unknown
      { id = "gemini-3-flash-preview"; } # free, tighter limits
      { id = "gemini-3.1-pro-preview"; } # PAID ONLY on free keys
      { id = "gemini-2.5-pro"; } # deprecated, rerouted 2026-12-01
      { id = "gemini-2.5-flash"; } # deprecated, rerouted 2026-12-01
      { id = "gemini-3.5-flash-lite"; } # cheap
      { id = "gemini-3.1-flash-lite"; } # cheap
      { id = "gemini-2.5-flash-lite"; } # cheapest
    ];
  };

  # The second batch of free lanes (issue 687, docs/free-lanes.md). Five of
  # them reuse pi-ai 1.3.0's NATIVE catalog routes under the catalog's own
  # name, like `google` above: no api/baseURL here, the catalog's endpoint and
  # wire protocol, the key named through apiKeyEnv so nothing ambient is read,
  # and `models` narrowing the catalog to the ids measured on 2026-11-03,
  # strongest first. An id the catalog does not describe is declared by hand
  # on the same route (its api and baseURL come from the catalog provider;
  # its sizes are stated here and are a claim, not a measurement). Cohere has
  # no catalog route, so it is a hand-declared openai-completions route on
  # Cohere's compatibility endpoint. Retry: QUOTA and AUTH are never retried
  # by dsh whatever retryPolicy says; a 429 means another DSH_KEY_SLOT.
  # Data posture is the free lanes' (see docs/free-lanes.md section 4):
  # nothing sensitive goes through any of them.
  keyed =
    displayName: apiKeyEnv: retryPolicy: extra:
    {
      inherit displayName apiKeyEnv retryPolicy;
    }
    // extra;

  # Groq (https://api.groq.com/openai/v1): three keys, 1,000 requests and
  # 200K tokens per day per key (measured headers: 8,000 tokens/minute). All
  # three ids are catalog-verified (qwen3.8-27b: 131,042 context, 16,384 out).
  groq =
    retryPolicy:
    keyed "Groq" "GROQ_API_KEY" retryPolicy {
      models = [
        {
          id = "qwen/qwen3.8-27b"; # default; Tom's wanted model
          # pi-ai sends the instructions as a `developer` message to every
          # reasoning model whose compat allows it; Groq's Qwen chat template
          # answers 400 "Unexpected message role" to that (measured
          # 2026-11-03), so this model takes a `system` message instead.
          compat.supportsDeveloperRole = false;
        }
        { id = "openai/gpt-oss-120b"; }
        { id = "openai/gpt-oss-20b"; }
      ];
    };

  # Mistral (https://api.mistral.ai, catalog api `mistral-conversations`, NOT
  # the OpenAI-compatible /v1 the orchestrator measured): three keys on the
  # free Experiment plan, which answers 429 with a 0 requests/minute limit
  # until Tom activates it per account. Catalog-verified ids; the measured
  # `ministral-14b-latest` alias is the catalog's dated ministral-14b-2512.
  mistral =
    retryPolicy:
    keyed "Mistral (Experiment plan)" "MISTRAL_API_KEY" retryPolicy {
      models = [
        { id = "mistral-medium-latest"; } # default; reasoning
        { id = "magistral-medium-latest"; } # reasoning
        { id = "codestral-latest"; } # code; DSH_ROUTE=codestral
        { id = "devstral-latest"; } # agentic code
        { id = "mistral-small-latest"; }
        { id = "ministral-14b-2512"; }
      ];
    };

  # Cohere: no pi-ai catalog route, so a hand-declared openai-completions
  # route on the compatibility endpoint (docs.cohere.com/docs/compatibility-api:
  # bearer auth, /chat/completions with streaming and tools; `store` is not
  # accepted; reasoning_effort takes only `none` and `high`). The endpoint
  # answered 401 without a key on 2026-11-03, so it exists; the chat call is
  # the first live smoke. Five trial keys, 20 calls/minute and 1,000/month
  # each. Sizes are Cohere's published context/output figures, declared by
  # hand (not measured); command-a-plus-05-2026 is assumed command-a-sized.
  cohereModels = [
    {
      id = "command-a-plus-05-2026"; # default; the page's own example model
      contextWindow = 256000;
      maxTokens = 8192;
      reasoningEfforts.high = "high";
    }
    {
      id = "command-a-reasoning-08-2025";
      contextWindow = 256000;
      maxTokens = 32768;
      reasoningEfforts.high = "high";
    }
    {
      id = "command-a-03-2025";
      contextWindow = 256000;
      maxTokens = 8192;
    }
    {
      id = "command-r-plus-08-2024";
      contextWindow = 128000;
      maxTokens = 4096;
    }
  ];
  cohere =
    retryPolicy:
    keyed "Cohere (trial)" "COHERE_API_KEY" retryPolicy {
      api = "openai-completions";
      baseURL = "https://api.cohere.com/compatibility/v1";
      compat = {
        supportsStore = false;
        supportsDeveloperRole = true;
        supportsReasoningEffort = true;
      };
      models = map (m: m // { input = [ "text" ]; }) cohereModels;
    };

  # NVIDIA NIM (https://integrate.api.nvidia.com/v1): one key, about 40
  # requests/minute (docs, unconfirmed). glm-5.3-flash answered with
  # reasoning; the other catalog ids were listed. nemotron-3-super and
  # minimax-m3.1-flash are listed for this account but absent from the
  # catalog, so they are declared by hand (sizes assumed, no reasoning
  # offered). moonshotai/kimi-k2.6 is in the catalog but 404 for this
  # account, so it is left out.
  nvidia =
    retryPolicy:
    keyed "NVIDIA NIM" "NVIDIA_API_KEY" retryPolicy {
      models = [
        { id = "z-ai/glm-5.3-flash"; } # default; answered with reasoning
        { id = "deepseek-ai/deepseek-v4.1-flash"; }
        { id = "nvidia/nemotron-3.5-super-vl-120b-a12b"; }
        {
          id = "nvidia/nemotron-3-super-120b-a12b"; # listed, not in the catalog
          contextWindow = 262144;
          maxTokens = 32768;
        }
        {
          id = "minimaxai/minimax-m3.1-flash"; # listed, not in the catalog
          contextWindow = 262144;
          maxTokens = 32768;
        }
        { id = "openai/gpt-oss-20b"; }
      ];
    };

  # Cloudflare Workers AI: the catalog route `cloudflare-workers-ai`, whose
  # model endpoints carry the placeholder {CLOUDFLARE_ACCOUNT_ID}; pi-ai's
  # own resolver fills it from the CLOUDFLARE_ACCOUNT_ID variable of the
  # process environment at request time, which the wrapper exports from the
  # agenix file beside the token (./default.nix, home/dsh.nix). The route
  # must keep the catalog name for that resolver to run, and a hand-declared
  # id cannot be added to it (the catalog provider carries no fixed endpoint
  # to default it from), so the measured @cf/deepseek-ai/deepseek-v4.1-flash-1017
  # waits for a pi-ai catalog that lists it. 10,000 neurons/day, reset 00:00Z.
  cloudflare =
    retryPolicy:
    keyed "Cloudflare Workers AI" "CLOUDFLARE_WORKERS_AI_TOKEN" retryPolicy {
      models = [
        { id = "@cf/qwen/qwen3.8-27b"; } # default
        { id = "@cf/deepseek-ai/deepseek-v4-pro-0813"; }
        { id = "@cf/openai/gpt-oss-120b"; }
        { id = "@cf/google/gemma-4-26b-a4b-it"; }
        { id = "@cf/meta/llama-4-scout-17b-16e-instruct"; }
      ];
    };

  # Hugging Face Inference Providers (https://router.huggingface.co/v1): a
  # Free account with no included credits, so every chat is HTTP 402 today.
  # The route is declared so it works the day Tom buys credits or PRO; it is
  # the default of nothing and reachable only as DSH_ROUTE=huggingface. The
  # `:cheapest` suffix is the router's provider selection, declared by hand
  # with the catalog's gpt-oss-120b sizes; the plain catalog ids follow.
  huggingface =
    retryPolicy:
    keyed "Hugging Face (no credits)" "HF_TOKEN" retryPolicy {
      models = [
        {
          id = "openai/gpt-oss-120b:cheapest"; # default; router picks the cheapest provider
          contextWindow = 131072;
          maxTokens = 32768;
        }
        { id = "openai/gpt-oss-120b"; }
        { id = "Qwen/Qwen3.8-27B"; }
        { id = "deepseek-ai/DeepSeek-V4.1-Flash"; }
        { id = "zai-org/GLM-5.3-Flash"; }
      ];
    };

  # Cerebras (https://api.cerebras.ai/v1): one key, no per-key rotation.
  # The strongest lane by allowance (measured headers: 450 requests/minute,
  # 648K/day, 150K tokens/minute, 216M tokens/day). Both ids are
  # catalog-verified (131,072 context, 40,960 out, reasoning); qwen-3.8-27b
  # answered.
  cerebras =
    retryPolicy:
    keyed "Cerebras" "CEREBRAS_API_KEY" retryPolicy {
      models = [
        { id = "qwen-3.8-27b"; } # default; answered
        { id = "gpt-oss-120b"; }
      ];
    };

  # Vercel AI Gateway: the catalog route `vercel-ai-gateway` (pi-ai speaks
  # anthropic-messages to https://ai-gateway.vercel.sh for its chat ids,
  # not the OpenAI-compatible /v1 that was measured). One key, valid, with a
  # credits balance of 0 today, so every call fails until Tom tops it up;
  # declared so it works then, the default of nothing (DSH_ROUTE=vercel).
  # No model was measured; the id is the catalog's qwen3.8-27b.
  vercel =
    retryPolicy:
    keyed "Vercel AI Gateway (no credits)" "AI_GATEWAY_API_KEY" retryPolicy {
      models = [
        { id = "alibaba/qwen3.8-27b"; } # default; catalog id, not measured
      ];
    };

  # Gufo's keyless LAN route. The wrapper supplies a public dummy bearer:
  # pi-ai still requires a nonempty credential for a custom provider.
  # llama-swap demand-loads the exact wire model ID on this shared endpoint.
  gufoModels = {
    ${localModel.modelId} = {
      name = "Qwen3.8 Flash-Next (Gufo)";
      contextWindow = 102400;
      input = [
        "text"
        "image"
      ];
      reasoningEfforts = false;
    };
    "qwen3.8-27b" = {
      name = "Qwen3.8 27B (Gufo alternate)";
      contextWindow = 131072;
      input = [
        "text"
        "image"
      ];
      reasoningEfforts = {
        low = "low";
        high = "high";
        max = "max";
      };
    };
    "qwen3.8-27b-ara" = {
      name = "Qwen3.8 27B Heretic ARA Q8 (local)";
      contextWindow = 102400;
      input = [ "text" ];
      # Thinking is selected by the server. The route below leaves the
      # optional request-level effort unset instead of overriding it.
      reasoningEfforts = false;
    };
    "qwen3.8-flash-next-abliterated" = {
      name = "Qwen3.8 Flash-Next Uncensored ROCmFP4 (local)";
      contextWindow = 32768;
      input = [ "text" ];
      reasoningEfforts = false;
    };
  };
  gufo = {
    displayName = "Gufo (local)";
    api = "openai-completions";
    baseURL = "${localModel.endpoint}/v1";
    apiKeyEnv = "GUFO_API_KEY";
    compat = {
      supportsDeveloperRole = false;
      supportsReasoningEffort = true;
      supportsStore = false;
    };
    models = map (
      id:
      gufoModels.${id}
      // {
        inherit id;
        maxTokens = 16384;
      }
    ) (
      [ localModel.modelId ]
      ++ localModel.alternates
      ++ [
        "qwen3.8-27b-ara"
        "qwen3.8-flash-next-abliterated"
      ]
    );
  };
  # ds4's keyless LAN route: DeepSeek V4.1 Flash 1017 on strix-worker
  # (modules/ds4.nix, single host with SSD expert streaming), at the contract
  # in lib/local-model.nix. Same public dummy bearer as Gufo. It answers only
  # while an operator has started `ds4.service` there, which stops the
  # worker's Gufo units; the fleet endpoint on strix-coordinator is untouched.
  # ds4-server takes `thinking` and `reasoning_effort` and returns
  # `reasoning_content`; Think Max needs --ctx >= 393216, so at this context
  # only high is offered.
  ds4 = {
    displayName = "ds4 DeepSeek V4.1 (local)";
    api = "openai-completions";
    baseURL = "${localModel.ds4.endpoint}/v1";
    apiKeyEnv = "DS4_API_KEY";
    compat = {
      supportsDeveloperRole = false;
      supportsReasoningEffort = true;
      supportsStore = false;
    };
    models = [
      {
        id = localModel.ds4.modelId;
        name = "DeepSeek V4.1 Flash 1017 (ds4, strix-worker)";
        inherit (localModel.ds4) contextWindow;
        maxTokens = 16384;
        input = [ "text" ];
        reasoningEfforts.high = "high";
        compat = {
          thinkingFormat = "deepseek";
          requiresReasoningContentOnAssistantMessages = true;
        };
      }
    ];
  };
  # The keyed cloud routes, by their pi-ai route name (catalog names where
  # pi-ai ships the provider; `cohere` is hand-declared).
  keyedProviders = retryPolicy: {
    google = google retryPolicy;
    groq = groq retryPolicy;
    mistral = mistral retryPolicy;
    cohere = cohere retryPolicy;
    nvidia = nvidia retryPolicy;
    cloudflare-workers-ai = cloudflare retryPolicy;
    huggingface = huggingface retryPolicy;
    cerebras = cerebras retryPolicy;
    vercel-ai-gateway = vercel retryPolicy;
  };
  providers = retryPolicy: keyedProviders retryPolicy // { inherit gufo ds4; };

  defaultRoute = {
    provider = "google";
    model = "gemini-3.8-flash";
  };

  # The Zen provider id jiesou's plugin registers (its `name` export), the row
  # id its bundle inserts and the settings namespace it reads.
  zenProvider = "opencode-zen-free-provider";

  # Per-run route selection, `DSH_ROUTE=<name> dsh <profile> ...` (./default.nix):
  # each name is a one-row `agent-default-model` overlay laid AFTER the
  # profile's own layers (a caller's --patch still comes last). There is no
  # model flag in dsh and no ordered fallback: a 429 means the operator re-runs
  # with another DSH_KEY_SLOT or route. The zen-* routes answer only in the
  # `zen` profile, where the plugin is mounted; model ids there come from the
  # live catalog at mount, so an id missing tonight fails UNKNOWN_MODEL.
  routes = {
    gemini = defaultRoute;
    gemini-pro = {
      provider = "google";
      model = "gemini-3.1-pro-preview";
    };
    gemini-lite = {
      provider = "google";
      model = "gemini-3.5-flash-lite";
    };
    gufo = {
      provider = "gufo";
      model = localModel.modelId;
    };
    qwen-ara = {
      provider = "gufo";
      model = "qwen3.8-27b-ara";
      reasoningEffort = null;
    };
    qwen-flash-abliterated = {
      provider = "gufo";
      model = "qwen3.8-flash-next-abliterated";
      reasoningEffort = null;
    };
    groq = {
      provider = "groq";
      model = "qwen/qwen3.8-27b";
    };
    groq-oss = {
      provider = "groq";
      model = "openai/gpt-oss-120b";
    };
    mistral = {
      provider = "mistral";
      model = "mistral-medium-latest";
    };
    codestral = {
      provider = "mistral";
      model = "codestral-latest";
    };
    cohere = {
      provider = "cohere";
      model = "command-a-plus-05-2026";
    };
    nvidia = {
      provider = "nvidia";
      model = "z-ai/glm-5.3-flash";
    };
    nvidia-deepseek = {
      provider = "nvidia";
      model = "deepseek-ai/deepseek-v4.1-flash";
    };
    # The Cloudflare ids and the hand-declared Hugging Face id carry no
    # reasoning metadata, so the overlay's `high` effort is refused
    # (UNSUPPORTED_REASONING_EFFORT, measured 2026-11-03); `null` leaves the
    # row without an effort and the provider at its own default.
    cloudflare = {
      provider = "cloudflare-workers-ai";
      model = "@cf/qwen/qwen3.8-27b";
      reasoningEffort = null;
    };
    cloudflare-deepseek = {
      provider = "cloudflare-workers-ai";
      model = "@cf/deepseek-ai/deepseek-v4-pro-0813";
      reasoningEffort = null;
    };
    huggingface = {
      provider = "huggingface";
      model = "openai/gpt-oss-120b:cheapest";
      reasoningEffort = null;
    };
    cerebras = {
      provider = "cerebras";
      model = "qwen-3.8-27b";
    };
    cerebras-oss = {
      provider = "cerebras";
      model = "gpt-oss-120b";
    };
    vercel = {
      provider = "vercel-ai-gateway";
      model = "alibaba/qwen3.8-27b";
    };
    zen-deepseek = {
      provider = zenProvider;
      model = "deepseek-v4.1-flash-free";
    };
    zen-glm = {
      provider = zenProvider;
      model = "glm-5.3-flash-free";
    };
  };

  policy = [
    # 1. DeepSeek-bound egress. `disabled` rows never load, which is stronger
    #    than `config.enabled: false`. No DeepSeek key exists on the fleet, so
    #    a misroute fails locally.
    (off "session-log-deepseek") # whole session log on every request, ON upstream
    (off "plugin-package-inventory-deepseek") # plugin inventory, ON upstream
    (off "deepseek-llm-api-extensions") # the carrier for both
    (off "llm-deepseek") # attaches both to ANY base URL, plus a user-id header
    (off "llm-deepseek-account")
    (off "deepseek-account") # PKCE sign-in to the DeepSeek platform
    (off "web-search-deepseek")
    (off "web-deepseek-api")
    # 2. Telemetry and feedback (the wrapper also sets DSH_TELEMETRY_DISABLED=1).
    (off "session-telemetry-otel")
    (off "otel")
    (off "command-feedback") # /feedback; mints $DSH_HOME/.anonymous-user-id
    # 3. No runtime plugin installs; plugins come from Nix only.
    (off "plugin-manager")
    (off "tool-plugin-manager")
    # 4. Inference: Gemini (free tier) is the default; the other keyed lanes,
    #    Gufo and ds4 are explicit DSH_ROUTE picks.
    (set "llm-pi-ai" {
      providers = providers {
        mode = "normal";
        maxRetries = 3;
      };
    })
    (set "agent-default-model" (defaultRoute // { reasoningEffort = "high"; }))
    # 5. One model request per turn: no LLM-written session titles.
    (off "session-title-llm")
    # 6. web_fetch only. web_search had DeepSeek as its only provider.
    (set "web" { fetchProvider = "http"; })
    (set "tool-web" {
      search = false;
      fetch = true;
    })
    # 7. Sandbox. A pinned runner skips dsh's PATH lookup for bwrap and its
    #    silent fallback to the weaker Landlock backend; dsh-bwrap adds the
    #    fleet masks (./dsh-bwrap.sh). The mode is pinned so DSH_PERMISSION_MODE
    #    cannot widen it, and the danger-full-access preset is gone from
    #    /permission. Escalations still ask, and with no answerer (headless)
    #    an ask fails closed.
    (set "sandbox" {
      runnerCommand = [ "${runner}/bin/dsh-bwrap" ];
      runnerFailureSignatures = [
        "bwrap: "
        "dsh-bwrap: "
      ];
    })
    (set "sandbox-policy" { mode = "workspace-write"; })
    (set "approval" { policy = "ask"; })
    (set "permission" {
      presets = {
        read-only = {
          sandbox = "read-only";
          approval = "ask";
        };
        workspace-write = {
          sandbox = "workspace-write";
          approval = "ask";
        };
      };
      defaultPreset = "workspace-write";
    })
    # 8. The plan runs at most 4 agents at once: the parent plus 3 children.
    (set "workflow-ptc" {
      provider = "spawn";
      maxConcurrentAgents = 3;
    })
  ];

  acp = [ (set "acp" defaultRoute) ];

  # The `herdr` profile's own rows. jevcore stays on its offline mock: no
  # network path exists without the SDK, and its startup line at `info`
  # (`[jevcore] ready · provider=mock`) reaches stderr through the profile's
  # stderr-log plugin. Both gates stay off: on the mock every gated
  # bash, edit or git call would become an ask, which headless denies.
  # FOLLOW-UP, NOT IMPLEMENTED: a real Jev route is this one row (provider
  # live, baseURL, model, apiKeyRef) plus the SDK back in pkgs/dsh-plugins.
  herdr = lib.optionals (builtins.elem "jevcore" (profilePlugins.herdr or [ ])) [
    (set "jev" {
      provider = "mock";
      logLevel = "info";
      gates = {
        safety = false;
        context = false;
      };
    })
  ];

  # Memory work is explicitly selected with `dsh mnemon`. Existing profiles,
  # Claude and Codex do not acquire hooks. Writes are intended tool calls;
  # there is no idle review, automatic capture, skill editing or Git sync.
  mnemonProfile = [
    (set "agent-default-model" {
      provider = "gufo";
      model = localModel.modelId;
    })
  ]
  ++ lib.optionals (builtins.elem "mnemon" (profilePlugins.mnemon or [ ])) [
    (set "mnemon" {
      cliPath = lib.getExe mnemon;
      storageScope = "global"; # ~/.mnemon; MNEMON_DATA_DIR may select a batch store.
      lifecycleEnabled = true;
      routingGuidance = true;
      recallMode = "guided";
      writebackMode = "off";
      writeEnabled = true;
      remoteAccess = "read-only";
      tabEnabled = false;
      timeoutMs = 30000;
      embedding.enabled = false;
      idleReview.enabled = false;
      skills = {
        evolution = false;
        allowCreate = false;
        allowUpdate = false;
        autoBacktest = false;
      };
      syncEnabled = false;
      taskAgentModel = {
        mode = "fixed";
        provider = "gufo";
        model = localModel.modelId;
        followConversation = false;
      };
    })
    (set "mnemon-source-memory-spaces" {
      providers = [
        {
          use = "dsh-mnemon-provider-mnemon-native";
          instanceId = "mnemon-native";
        }
      ];
    })
    (off "mnemon-source-skills")
  ];

  # `dsh zen "<task>"`: the Zen free models (jiesou's provider) as the default
  # route. `credentials` is re-enabled for this profile only: the headless
  # bundle disables it, and the plugin reads its key solely through that
  # service (otherwise it sends the anonymous `public` bearer). With it on,
  # credentials-local resolves $DSH_HOME/.credentials.yaml first, then the
  # inherited environment (the wrapper's OPENCODE_ZEN_FREE_API_KEY), then .env
  # files: a stored key outranks the slot. The pi-ai routes of the policy
  # overlay (Gemini, Gufo, ds4) stay available as explicit picks. A patch
  # REPLACES a row's config, so the plugin row restates every key it keeps.
  # Retry: the design proposed `mode = "always"`, which in this dsh has no
  # maxRetries and would retry a 429 FreeUsageLimitError without bound; the
  # fleet's bounded policy is used instead (QUOTA is not retryable there).
  zenProfile = [
    {
      id = "credentials";
      disabled = false;
    }
  ]
  ++ lib.optionals (builtins.elem "opencode-zen-free" (profilePlugins.zen or [ ])) [
    (set zenProvider {
      retryPolicy = {
        mode = "normal";
        maxRetries = 3;
      };
      maxRequestImageBytes = 2097152;
      requestImageMaxBytes = 1048576;
    })
    (set "agent-default-model" (routes.zen-deepseek // { reasoningEffort = "high"; }))
  ];

  # The gate's single call: fail on the first error rather than spend retries,
  # and think as little as the model allows.
  smoke = [
    (set "llm-pi-ai" {
      providers = providers {
        mode = "normal";
        maxRetries = 0;
      };
    })
    (set "agent-default-model" (defaultRoute // { reasoningEffort = "low"; }))
  ];
in
{
  policy = yaml.generate "dsh-policy.patch.yml" policy;
  acp = yaml.generate "dsh-acp.patch.yml" acp;
  herdr = yaml.generate "dsh-herdr.patch.yml" herdr;
  mnemon = yaml.generate "dsh-mnemon.patch.yml" mnemonProfile;
  zen = yaml.generate "dsh-zen.patch.yml" zenProfile;
  smoke = yaml.generate "dsh-smoke.patch.yml" smoke;
  routeOverlays = lib.mapAttrs (
    name: route:
    yaml.generate "dsh-route-${name}.patch.yml" [
      # `high` unless the route names its own effort; `null` drops the key.
      (set "agent-default-model" (
        lib.filterAttrs (_: v: v != null) ({ reasoningEffort = "high"; } // route)
      ))
    ]
  ) routes;
  # Local provider data for offline config checks.
  localProviders = { inherit gufo ds4; };
  # The keyed cloud providers of the policy, for checks.dsh-config (the
  # policy's retry settings, not the smoke's): apiKeyEnv, the model ids and,
  # for the hand-declared cohere route, its api and baseURL.
  cloudProviders = keyedProviders {
    mode = "normal";
    maxRetries = 3;
  };
  inherit defaultRoute routes zenProvider;
  # The herdr profile's rows as data, for checks.dsh-plugins.
  herdrRows = builtins.listToAttrs (map (row: lib.nameValuePair row.id row.config) herdr);
  mnemonRows = builtins.listToAttrs (
    map (row: lib.nameValuePair row.id row.config) (lib.filter (row: row ? config) mnemonProfile)
  );
  zenRows = builtins.listToAttrs (
    map (row: lib.nameValuePair row.id row.config) (lib.filter (row: row ? config) zenProfile)
  );
  # Row ids the policy touches, for checks.dsh-config.
  policyIds = map (row: row.id) policy;
  disabledIds = map (row: row.id) (lib.filter (row: row.disabled or false) policy);
}
