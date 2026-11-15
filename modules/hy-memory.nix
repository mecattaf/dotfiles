{
  config,
  lib,
  pkgs,
  ...
}:
# Hy-Memory-30B-A3B for the paired memory-writer comparison (#603; Tom,
# 2026-11-09). Its hy_v3 architecture needs a newer llama.cpp than the
# fleet's nix-strix-halo build, and Gufo does not load it, so a plain
# llama-server joins the existing llama-swap supervisor as one more
# demand-loaded backend. No systemd unit and no PATH entry: the package is
# reached only through this launcher, so the fleet's own llama-server stays
# first on PATH. Weights come from the explicit Library loan; never -hf.
let
  cfg = config.services.hy-memory;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  artifact = modelStore.materialized.${cfg.artifact};
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  templateKwargs = builtins.toJSON { reasoning_effort = "no_think"; };
  # The publisher's llama.cpp quickstart, served from the borrowed GGUF. The
  # embedded chat template is applied with --jinja; no_think keeps the writer
  # in its documented non-reasoning mode.
  launcher = pkgs.writeShellScript "llama-server-demand-hy-memory" ''
    set -eu
    ${bundleCheck [ cfg.artifact ]}
    exec ${cfg.package}/bin/llama-server \
      --model ${lib.escapeShellArg artifact.primary} \
      --alias ${lib.escapeShellArg cfg.servedModelName} \
      --host 127.0.0.1 --port "$1" \
      --n-gpu-layers all --flash-attn on \
      --ctx-size ${toString cfg.context} --parallel 1 \
      --batch-size 2048 --ubatch-size 512 \
      --cache-type-k f16 --cache-type-v f16 \
      --temp 0.7 --top-k 0 --top-p 1.0 --repeat-penalty 1.0 \
      --jinja --chat-template-kwargs ${lib.escapeShellArg templateKwargs} \
      --no-webui
  '';
in
{
  options.services.hy-memory = {
    enable = lib.mkEnableOption "the on-demand Hy-Memory memory-writer evaluation route";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp-hy-memory;
      defaultText = lib.literalExpression "pkgs.llama-cpp-hy-memory";
      description = "llama.cpp with hy_v3 support (the nixpkgs-fresh Vulkan build).";
    };
    artifact = lib.mkOption {
      type = lib.types.enum (builtins.attrNames modelStore.materialized);
      default = "hy-memory-30b-a3b-q8-gguf";
      description = "Flat GGUF artifact from the NAS Library catalog; its primary file is passed as --model.";
    };
    servedModelName = lib.mkOption {
      type = lib.types.str;
      default = "hy-memory-30b-a3b";
      description = "llama-swap route and llama-server --alias.";
    };
    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 65536;
    };
    idleSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.gufo.enable;
        message = "Hy-Memory shares the Gufo llama-swap supervisor; services.gufo.enable is required.";
      }
    ];
    services.local-models.requirements.hy-memory = [ cfg.artifact ];
    services.llama-swap.settings.models.${cfg.servedModelName} = {
      cmd = "${launcher} \${PORT}";
      checkEndpoint = "/health";
      ttl = cfg.idleSeconds;
      useModelName = cfg.servedModelName;
      timeouts.responseHeader = 1200;
      capabilities = {
        "in" = [ "text" ];
        out = [ "text" ];
        tools = false;
        context = cfg.context;
      };
    };
  };
}
