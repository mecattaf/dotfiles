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
in
{
  imports = [ inputs.voxtype.homeManagerModules.default ];

  programs.voxtype = lib.mkIf (hostName == "coordinator") {
    enable = true;
    engine = "parakeet";
    package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.onnx-migraphx;
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
        model = "parakeet-unified-en-0.6b";
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
}
