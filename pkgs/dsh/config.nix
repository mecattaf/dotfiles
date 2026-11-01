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
#   policy : every profile the wrapper boots (headless, sdk, acp, herdr)
#   acp    : acp only; its bundle pins the official DeepSeek route in its own row
#   herdr  : the hand-run plugin profile only (jevcore's row; ./default.nix)
#   mnemon : the dedicated local-memory profile, including its Gufo route
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

  # Qwen Cloud token plan through llm-pi-ai's catalog route `qwen-token-plan`
  # (OpenAI chat-completions on the same endpoint pi uses; URL, protocol and
  # compat come from the pi-ai catalog). The key arrives as an env var the
  # wrapper reads from the agenix file; naming it here makes a missing key fail
  # MISSING_CREDENTIAL instead of falling back to anything ambient.
  qwenTokenPlan = retryPolicy: {
    displayName = "Qwen Cloud (token plan)";
    apiKeyEnv = "QWEN_TOKEN_PLAN_API_KEY";
    # QUOTA and AUTH are never retried by dsh whatever this says.
    inherit retryPolicy;
    # Narrows the 20-id catalog to what the plan serves. No automatic failover
    # exists in dsh: a fallback is an explicit model pick.
    models = [
      { id = "deepseek-v4.1-flash"; } # default: DeepSeek's latest Flash
      # Dated pin, not in the pi-ai catalog, so every field is declared.
      # Runtime admission is unverified (the gate calls the undated alias).
      {
        id = "deepseek-v4.1-flash-1017";
        name = "DeepSeek V4.1 Flash 1017";
        contextWindow = 1000000;
        maxTokens = 384000;
        input = [
          "text"
          "image"
        ];
        reasoningEfforts = {
          low = "low";
          high = "high";
          max = "max";
        };
      }
      { id = "qwen3.8-max"; } # fallback: the model this key has run under pi
      { id = "deepseek-v4-pro"; } # explicit pick, hard tasks
      { id = "qwen3.8-flash"; } # explicit pick, cheap
    ];
  };

  # Gufo's keyless LAN route. The wrapper supplies a public dummy bearer:
  # pi-ai still requires a nonempty credential for a custom provider.
  # The alternate shares the endpoint and must be selected with gufo-switch first.
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
    ) ([ localModel.modelId ] ++ localModel.alternates);
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
  providers = retryPolicy: {
    qwen-token-plan = qwenTokenPlan retryPolicy;
    inherit gufo ds4;
  };

  defaultRoute = {
    provider = "qwen-token-plan";
    model = "deepseek-v4.1-flash";
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
    # 4. Inference: Qwen Cloud stays the default; Gufo and ds4 are explicit picks.
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
  smoke = yaml.generate "dsh-smoke.patch.yml" smoke;
  # Local provider data for offline config checks.
  localProviders = { inherit gufo ds4; };
  # The herdr profile's rows as data, for checks.dsh-plugins.
  herdrRows = builtins.listToAttrs (map (row: lib.nameValuePair row.id row.config) herdr);
  mnemonRows = builtins.listToAttrs (
    map (row: lib.nameValuePair row.id row.config) (lib.filter (row: row ? config) mnemonProfile)
  );
  # Row ids the policy touches, for checks.dsh-config.
  policyIds = map (row: row.id) policy;
  disabledIds = map (row: row.id) (lib.filter (row: row.disabled or false) policy);
}
