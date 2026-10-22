{
  lib,
  formats,
  runner,
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
#   policy : every profile the wrapper boots (headless, sdk, acp)
#   acp    : acp only; its bundle pins the official DeepSeek route in its own row
#   smoke  : the gate's one inference call (no retries, low effort); never
#            installed, built only as `nix build .#dsh.smoke`
let
  yaml = formats.yaml { };
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

  # FOLLOW-UP, NOT IMPLEMENTED (Tom, 2026-10-22: "leave local models out for
  # tonight"). Local inference through gufo is ONE more attribute here, beside
  # qwen-token-plan, with its endpoint taken from the gufo module's client
  # option, never a literal host:
  #   gufo = {
  #     displayName = "gufo (local)";
  #     api = "openai-completions";
  #     baseURL = "<gufo client endpoint>/v1";
  #     apiKeyEnv = "GUFO_API_KEY"; # placeholder; the server is keyless
  #     compat = { supportsDeveloperRole = false; supportsStore = false; maxTokensField = "max_tokens"; };
  #     models = [ { id = "<served id>"; contextWindow = <server ctx>; maxTokens = <cap>; input = [ "text" ]; } ];
  #   };
  providers = retryPolicy: {
    qwen-token-plan = qwenTokenPlan retryPolicy;
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
    # 4. Inference: Qwen Cloud is the only route.
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
  smoke = yaml.generate "dsh-smoke.patch.yml" smoke;
  # Row ids the policy touches, for checks.dsh-config.
  policyIds = map (row: row.id) policy;
  disabledIds = map (row: row.id) (lib.filter (row: row.disabled or false) policy);
}
