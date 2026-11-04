{
  config,
  lib,
  pkgs,
  ...
}:
# The custom ROCmFP4 GGUF needs SuperROC's tensor encodings and kernels.
# Register its separate backend with the existing single-model supervisor.
let
  cfg = config.services.superroc;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  artifact = modelStore.materialized.${cfg.artifact};
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  launcher = pkgs.writeShellScript "superroc-demand-flash-next" ''
    set -eu
    ${bundleCheck [ cfg.artifact ]}
    exec ${cfg.package}/bin/superroc serve --host 127.0.0.1 --port "$1" llm \
      --model ${lib.escapeShellArg artifact.primary} \
      --served-model-name ${lib.escapeShellArg cfg.servedModelName} \
      --sessions 1 --context ${toString cfg.context} \
      --think on --reasoning-effort low \
      --speculative mtp --mtp-model ${lib.escapeShellArg "${artifact.directory}/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"} \
      --draft-tokens 3 --cache-ram-bytes 1073741824
  '';
in
{
  options.services.superroc = {
    enable = lib.mkEnableOption "SuperROC for the abliterated ROCmFP4 Flash-Next model";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/superroc { };
    };
    artifact = lib.mkOption {
      type = lib.types.enum (builtins.attrNames modelStore.materialized);
      default = "qwen38-flash-next-abliterated-rocmfp4-gguf";
    };
    servedModelName = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.8-flash-next-abliterated";
    };
    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.gufo.enable;
        message = "SuperROC shares the Gufo llama-swap supervisor; services.gufo.enable is required.";
      }
    ];
    services.local-models.requirements.superroc = [ cfg.artifact ];
    services.llama-swap.settings.models.${cfg.servedModelName} = {
      cmd = "${launcher} \${PORT}";
      checkEndpoint = "/ready";
      ttl = 600;
      useModelName = cfg.servedModelName;
      timeouts.responseHeader = 1200;
      capabilities = {
        "in" = [ "text" ];
        out = [ "text" ];
        tools = true;
        context = cfg.context;
      };
    };
    environment.systemPackages = [ cfg.package ];
  };
}
