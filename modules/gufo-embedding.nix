{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# The one text-embedding route (Tom, 2026-11-10: "i m a gufo maximalist";
# "embedder does not stay loaded besides flash-next ... ideally one embeding
# endpoint through llama-swap"). Gufo v0.33.0 serves Qwen3-Embedding-8B
# (Q8_0 GGUF) through the vendored community extension compiled in
# (pkgs/gufo-extensions/qwen3-embedding), answering POST /v1/embeddings.
# llama-swap has no groups, so loading this route unloads Flash-Next and the
# next text request unloads it: it is never resident beside Flash-Next.
# The engine comes from the isolated `gufo-embedding` input; every other
# route keeps the fleet's `gufo` input. No systemd unit and no PATH entry:
# the package is reached only through this launcher. Weights come from the
# explicit Library loan; never -hf.
let
  cfg = config.services.gufo-embedding;
  system = pkgs.stdenv.hostPlatform.system;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  artifact = modelStore.materialized.${cfg.artifact};
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  # The extension's probe claims the GGUF file itself, so --model is the
  # primary file and one served name selects nothing else.
  command = inputs.gufo-embedding.lib.${system}.mkGufoServe {
    gufo = cfg.package;
    modality = "embedding";
    model = artifact.primary;
    inherit (cfg) servedModelName extraArgs;
    host = "127.0.0.1";
    port = "$GUFO_DEMAND_PORT";
  };
  launcher = pkgs.writeShellScript "gufo-demand-embedding-${cfg.servedModelName}" ''
    set -eu
    GUFO_DEMAND_PORT="$1"
    ${bundleCheck [ cfg.artifact ]}
    exec ${command}
  '';
in
{
  options.services.gufo-embedding = {
    enable = lib.mkEnableOption "the on-demand Gufo embedding route (Qwen3-Embedding-8B extension)";
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.gufo-embedding.packages.${system}.default.override {
        extensions = [ ../pkgs/gufo-extensions/qwen3-embedding ];
      };
      defaultText = lib.literalExpression "inputs.gufo-embedding.packages.\${system}.default.override { extensions = [ ../pkgs/gufo-extensions/qwen3-embedding ]; }";
      description = "Gufo v0.33.0 with the Qwen3-Embedding-8B extension compiled in. Only the compiled-in form carries the extension metadata that mkGufoServe validates.";
    };
    artifact = lib.mkOption {
      type = lib.types.enum (builtins.attrNames modelStore.materialized);
      default = "qwen3-embedding-8b-q8-gguf";
      description = "Flat GGUF artifact from the NAS Library catalog; its primary file is passed as --model.";
    };
    servedModelName = lib.mkOption {
      type = lib.types.str;
      default = "qwen3-embedding-8b";
      description = "llama-swap route and Gufo --served-model-name.";
    };
    idleSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = config.services.gufo.demand.textIdleSeconds;
      defaultText = lib.literalExpression "config.services.gufo.demand.textIdleSeconds";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Further `gufo serve embedding` flags, rendered after the generated ones.";
    };
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      description = "The rendered `gufo serve ... embedding` command the launcher execs (read by tests/gufo-demand).";
    };
  };
  config = lib.mkMerge [
    { services.gufo-embedding.command = command; }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.services.gufo.enable;
          message = "The embedding route shares the Gufo llama-swap supervisor; services.gufo.enable is required.";
        }
      ];
      services.local-models.requirements.gufo-embedding = [ cfg.artifact ];
      services.llama-swap.settings.models.${cfg.servedModelName} = {
        cmd = "${launcher} \${PORT}";
        checkEndpoint = "/ready";
        ttl = cfg.idleSeconds;
        useModelName = cfg.servedModelName;
        timeouts.responseHeader = 1200;
      };
    })
  ];
}
