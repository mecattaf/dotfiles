{
  config,
  lib,
  pkgs,
  ...
}:
# Declarative FastFlowLM roster for ad-hoc NPU inference.
#
# This module deliberately creates no systemd units and performs no activation
# pull. The ordinary `flm run <model>` command owns interactive load/use/unload.
# `flm pull <model>` remains an explicit operator action when runtime-owned
# files are absent. Nix owns only the allowed model identities and an
# inspectable manifest.
#
# The `utility-model` wrapper used to live here too, because the stable
# `utility` id was backed by an FLM row and this module owned one
# start/request/stop cycle around it. It moved to modules/local-models.nix on
# 2026-08-29 with the slot itself: the utility deployment is now a GPU roster
# row served by llama-swap, which has nothing to do with FastFlowLM. Nothing in
# this module reads catalog.utility any more.
let
  cfg = config.services.npu-llm;
  catalog = import ../lib/local-models.nix { inherit lib; };
  host = config.networking.hostName;
  catalogModels = map (deployment: deployment.model) (
    lib.filter (
      deployment:
      deployment.status == "canonical" && deployment.backend == "npu" && lib.elem host deployment.hosts
    ) (builtins.attrValues catalog.deployments)
  );
  manifest = (pkgs.formats.json { }).generate "fastflowlm-models.json" {
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
    }) cfg.models;
  };
in
{
  options.services.npu-llm = {
    enable = lib.mkEnableOption "the declarative ad-hoc FastFlowLM NPU roster";

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        FastFlowLM model tags approved for ad-hoc `flm run` use on this host.
        This option never starts, serves, or downloads a model.
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
        assertion = builtins.length cfg.models == builtins.length (lib.unique cfg.models);
        message = "services.npu-llm.models must not contain duplicate tags.";
      }
      {
        assertion = lib.sort builtins.lessThan cfg.models == lib.sort builtins.lessThan catalogModels;
        message = "services.npu-llm.models must exactly match this host's canonical NPU catalog rows.";
      }
    ];

    environment.systemPackages = [ pkgs.fastflowlm ];
    environment.etc."local-models/fastflowlm.json".source = manifest;
  };
}
