{
  config,
  lib,
  pkgs,
  ...
}:
# Declarative FastFlowLM roster for ad-hoc NPU inference.
#
# This module deliberately creates no systemd units and performs no activation
# pull. The ordinary `flm run <model>` command owns interactive load/use/unload;
# the utility wrapper owns one start/request/stop cycle. `flm pull <model>`
# remains an explicit operator action when runtime-owned files are absent. Nix
# owns only the allowed model identities and an inspectable manifest.
let
  cfg = config.services.npu-llm;
  catalog = import ../lib/local-models.nix { inherit lib; };
  host = config.networking.hostName;
  utilityDeployment = catalog.deployments.${catalog.utility.deployment};
  utilityEnabled =
    utilityDeployment.status == "canonical"
    && utilityDeployment.backend == "npu"
    && lib.elem host utilityDeployment.hosts;
  utilityModel = utilityDeployment.model;
  declaredModels = cfg.models ++ lib.optional utilityEnabled utilityModel;
  catalogModels = map (deployment: deployment.model) (
    lib.filter (
      deployment:
      deployment.status == "canonical" && deployment.backend == "npu" && lib.elem host deployment.hosts
    ) (builtins.attrValues catalog.deployments)
  );
  utilityRunner = pkgs.writeShellApplication {
    name = "utility-model";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../pkgs/utility-model/utility_model.py} "$@" \
        --flm ${pkgs.fastflowlm}/bin/flm \
        --concrete-model ${lib.escapeShellArg utilityModel} \
        --context-tokens ${toString catalog.utility.contextTokens}
    '';
  };
  manifest = (pkgs.formats.json { }).generate "fastflowlm-models.json" (
    {
      schema = 2;
      runtime = "fastflowlm";
      lifecycle = "ad-hoc";
      persistentServer = false;
      models = map (tag: {
        inherit tag;
        command = [
          "flm"
          "run"
          tag
        ];
      }) declaredModels;
    }
    // lib.optionalAttrs utilityEnabled {
      utility = {
        id = catalog.utility.stableId;
        model = utilityModel;
        owner = "utility-model";
        lifecycle = "request-scoped";
        contextTokens = catalog.utility.contextTokens;
        command = [ "utility-model" ];
      };
    }
  );
in
{
  options.services.npu-llm = {
    enable = lib.mkEnableOption "the declarative ad-hoc FastFlowLM NPU roster";

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional FastFlowLM model tags approved for ad-hoc `flm run` use on
        this host. The canonical utility deployment is projected separately
        from the typed catalog. This option never starts, serves, or downloads
        a model.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.amd-npu.enable && config.hardware.amd-npu.enableFastFlowLM;
        message = "services.npu-llm requires the amdxdna NPU stack and FastFlowLM CLI.";
      }
      {
        assertion = cfg.models != [ ];
        message = "services.npu-llm.models must contain at least one tag.";
      }
      {
        assertion = builtins.length declaredModels == builtins.length (lib.unique declaredModels);
        message = "services.npu-llm.models must not contain duplicate tags.";
      }
      {
        assertion = lib.sort builtins.lessThan declaredModels == lib.sort builtins.lessThan catalogModels;
        message = "services.npu-llm plus the utility slot must exactly match this host's canonical NPU catalog rows.";
      }
    ];

    environment.systemPackages = [ pkgs.fastflowlm ] ++ lib.optional utilityEnabled utilityRunner;
    environment.etc."local-models/fastflowlm.json".source = manifest;
  };
}
