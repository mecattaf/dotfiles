{
  inputs,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
# Voxtype — local streaming dictation on the interactive AMD Strix Halo
# coordinator. The upstream Home Manager module owns the package, generated
# TOML, and sole systemd user service. Other NixOS hosts and standalone bridge
# import the options but leave the complete integration disabled.
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.onnx-migraphx;
  parakeetModel = "parakeet-unified-en-0.6b";
in
{
  imports = [ inputs.voxtype.homeManagerModules.default ];

  programs.voxtype = lib.mkIf (hostName == "coordinator") {
    enable = true;
    engine = "parakeet";
    inherit package;
    service.enable = true;

    settings = {
      state_file = "auto";

      hotkey = {
        enabled = false;
        mode = "toggle";
      };

      audio.device = "iContact";

      parakeet = {
        # Current upstream's streaming-capable TDT-v3-family model. The similarly
        # named parakeet-tdt-0.6b-v3 model is batch-only and is rejected when
        # streaming is enabled.
        model = parakeetModel;
        model_type = "tdt";
        streaming = true;
        on_demand_loading = false;
      };

      output = {
        mode = "type";
        fallback_to_clipboard = true;
        driver_order = [
          "wtype"
          "clipboard"
        ];
      };
    };
  };

  # The selected model is the only entry in Voxtype 0.7.5's registry marked as
  # compatible with its cache-aware live-streaming pipeline. Bootstrap it through
  # Voxtype's own idempotent downloader before the daemon starts, mirroring the
  # intentional runtime-pull boundary used by FastFlowLM.
  systemd.user.services.voxtype = lib.mkIf (hostName == "coordinator") {
    Service = {
      ExecStartPre = "${package}/bin/voxtype setup --download --model ${parakeetModel} --quiet";
      TimeoutStartSec = "infinity";
    };
  };
}
