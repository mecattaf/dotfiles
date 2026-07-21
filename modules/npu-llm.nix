{
  config,
  lib,
  pkgs,
  ...
}:
# NPU-served small-LLM runtime on the coordinator.
#
# Makes the FastFlowLM model choice DECLARATIVE: `services.npu-llm.model` is the
# single obvious place that names the model the coordinator preloads on its XDNA2
# NPU (today gemma4-it:e4b — Q4_1, 128k max ctx). Changing which model gets
# warmed later = edit that one string. `flm serve` runs as a warm systemd unit so
# the local OpenAI-compatible backend (FastFlowLM's default port 52625, bound to
# localhost) stays warm behind llama-swap. zmx session titling and every other
# consumer enter through llama-swap's port 9292; the NPU endpoint is never a
# public application-facing route.
#
# The amdxdna driver, XRT userspace, and the `flm` binary itself all come from
# hardware.amd-npu (nix-amd-ai) — upstream ships no serve unit or model option,
# so this module only adds the model choice, the serve unit, and a declarative
# pre-start pull. Weights are multi-GB and are pulled at RUNTIME into the serving
# user's ~/.config/flm/models — deliberately NEVER into the nix store.
let
  cfg = config.services.npu-llm;
  inherit (lib) mkEnableOption mkOption mkIf types;
in {
  options.services.npu-llm = {
    enable = mkEnableOption "the FastFlowLM `flm serve` NPU model runtime";

    model = mkOption {
      type = types.str;
      default = "gemma4-it:e4b";
      description = ''
        FastFlowLM model tag to preload and serve on the NPU (see `flm list`).
        THE one place to change which small model the coordinator warms.
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

    port = mkOption {
      type = types.port;
      default = 52625;
      description = "Bind port for `flm serve` (FastFlowLM's default server port).";
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
    ];

    systemd.services.flm-serve = {
      description = "FastFlowLM NPU model server (${cfg.model})";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # `flm` and the XRT userspace reach the system profile via hardware.amd-npu.
      path = [
        pkgs.fastflowlm
        "/run/current-system/sw"
      ];
      environment = {
        # systemd units don't inherit login-session vars, so re-export the XRT
        # plugin-discovery paths hardware.amd-npu publishes as sessionVariables —
        # without them XRT can't dlopen the amdxdna driver plugin. `or ""` guards
        # against the (asserted-against) NPU-off misconfig at eval time.
        XILINX_XRT = config.environment.sessionVariables.XILINX_XRT or "";
        XRT_PATH = config.environment.sessionVariables.XRT_PATH or "";
        # Silence FLM's per-run auto-update probe against the read-only nix binary.
        FLM_DISABLE_UPDATE_CHECK = "1";
      };
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        SupplementaryGroups = [
          "video"
          "render"
        ];
        # Ensure the model is present before serving. `flm pull` is idempotent (a
        # no-op once the weights are on disk) and downloads multi-GB files into
        # the user's ~/.config/flm at RUNTIME — never the nix store. First boot
        # can take a while, hence the disabled start timeout.
        ExecStartPre = "${pkgs.fastflowlm}/bin/flm pull ${cfg.model}";
        ExecStart = "${pkgs.fastflowlm}/bin/flm serve ${cfg.model} --host ${cfg.host} --port ${toString cfg.port} --pmode ${cfg.powerMode}";
        TimeoutStartSec = "infinity";
        Restart = "on-failure";
        RestartSec = "5s";
        KillSignal = "SIGINT";
        LimitMEMLOCK = "infinity";
      };
    };
  };
}
