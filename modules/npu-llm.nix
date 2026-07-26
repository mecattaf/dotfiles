{
  config,
  lib,
  pkgs,
  ...
}:
# NPU-served local-LLM runtimes on both Strix Halo hosts.
#
# Each declared FastFlowLM tag gets its own loopback-only `flm serve` unit and
# fixed port. llama-swap is the only caller-facing endpoint; these native peers
# stay implementation details. Separate units are necessary because one FLM
# server accepts exactly one model tag.
#
# The amdxdna driver, XRT userspace, and the `flm` binary itself all come from
# hardware.amd-npu (nix-amd-ai) — upstream ships no serve unit or model option,
# so this module only adds model choices, serve units, and a declarative
# bootstrap. Weights are multi-GB and are pulled at RUNTIME into the serving
# user's ~/.config/flm/models — deliberately NEVER into the nix store.
let
  cfg = config.services.npu-llm;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  safeUnitName = tag: lib.replaceStrings [ ":" "." "/" ] [ "-" "-" "-" ] tag;
  modelType = types.submodule {
    options = {
      tag = mkOption {
        type = types.str;
        description = "FastFlowLM model tag, as printed by `flm list`.";
      };
      port = mkOption {
        type = types.port;
        description = "Loopback port for this model's dedicated FLM server.";
      };
    };
  };
  runtimeEnvironment = {
    # System units do not inherit login-session plugin-discovery paths.
    XILINX_XRT = config.environment.sessionVariables.XILINX_XRT or "";
    XRT_PATH = config.environment.sessionVariables.XRT_PATH or "";
    FLM_DISABLE_UPDATE_CHECK = "1";
  };
  bootstrap = pkgs.writeShellScript "flm-model-bootstrap" (
    lib.concatMapStringsSep "\n" (
      model: "${pkgs.fastflowlm}/bin/flm pull ${lib.escapeShellArg model.tag}"
    ) cfg.models
  );
in
{
  options.services.npu-llm = {
    enable = mkEnableOption "the FastFlowLM `flm serve` NPU model runtime";

    models = mkOption {
      type = types.listOf modelType;
      default = [ ];
      description = ''
        FastFlowLM model tags to download and serve on the NPU. Every entry gets
        an idempotent runtime pull and a dedicated loopback endpoint.
      '';
    };

    user = mkOption {
      type = types.str;
      description = ''
        User `flm serve` runs as. Its ~/.config/flm/models holds the pulled
        weights, and it must be in the video/render groups for NPU access (the
        unit adds those as SupplementaryGroups regardless).
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address for `flm serve`. Localhost keeps it on-box only.";
    };

    powerMode = mkOption {
      type = types.enum [
        "powersaver"
        "balanced"
        "performance"
        "turbo"
      ];
      default = "performance";
      description = "`flm --pmode` NPU power profile.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.amd-npu.enable && config.hardware.amd-npu.enableFastFlowLM;
        message = "services.npu-llm requires hardware.amd-npu.enable + enableFastFlowLM (which provide the amdxdna NPU stack, XRT, and the `flm` binary).";
      }
      {
        assertion = cfg.models != [ ];
        message = "services.npu-llm.models must contain at least one model.";
      }
      {
        assertion =
          builtins.length cfg.models == builtins.length (lib.unique (map (model: model.tag) cfg.models));
        message = "services.npu-llm.models must use unique model tags.";
      }
      {
        assertion =
          builtins.length cfg.models == builtins.length (lib.unique (map (model: model.port) cfg.models));
        message = "services.npu-llm.models must use unique ports.";
      }
    ];

    systemd.services = {
      # Pull sequentially so first boot never has two FLM writers racing in the
      # same per-user model registry. Re-evaluation is cheap because pull is
      # idempotent and validates already-present snapshots.
      flm-model-bootstrap = {
        description = "Download the declared FastFlowLM NPU models";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = runtimeEnvironment;
        path = [
          pkgs.fastflowlm
          "/run/current-system/sw"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          ExecStart = bootstrap;
          RemainAfterExit = true;
          TimeoutStartSec = "infinity";
        };
      };
    }
    // lib.listToAttrs (
      map (model: {
        name = "flm-serve-${safeUnitName model.tag}";
        value = {
          description = "FastFlowLM NPU model server (${model.tag})";
          after = [ "flm-model-bootstrap.service" ];
          requires = [ "flm-model-bootstrap.service" ];
          wantedBy = [ "multi-user.target" ];
          # `flm` and XRT reach the system profile via hardware.amd-npu.
          path = [
            pkgs.fastflowlm
            "/run/current-system/sw"
          ];
          environment = runtimeEnvironment;
          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            SupplementaryGroups = [
              "video"
              "render"
            ];
            ExecStart = "${pkgs.fastflowlm}/bin/flm serve ${model.tag} --host ${cfg.host} --port ${toString model.port} --pmode ${cfg.powerMode}";
            Restart = "on-failure";
            RestartSec = "5s";
            KillSignal = "SIGINT";
            LimitMEMLOCK = "infinity";
          };
        };
      }) cfg.models
    );
  };
}
