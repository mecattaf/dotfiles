{
  config,
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
  osdPackage = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-gtk4;
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

      # CPAL exposes this host's PipeWire/ALSA bridge as `default`, while the
      # selected USB microphone's friendly name ("iContact") is not a CPAL
      # device identifier. Follow PipeWire's selected source so recording also
      # keeps working when the preferred microphone is temporarily absent.
      audio.device = "default";

      # The launcher is part of the main package, but upstream ships each GUI
      # frontend separately. Keep the selected frontend and installed package
      # paired so recording state is visible under niri.
      osd.frontend = "gtk4";

      parakeet = {
        # Current upstream's streaming-capable TDT-v3-family model. The similarly
        # named parakeet-tdt-0.6b-v3 model is batch-only and is rejected when
        # streaming is enabled.
        model = parakeetModel;
        model_type = "tdt";
        streaming = true;
        # Voxtype 0.7.5's implicit 0.5/1.5/0.5-second defaults do not pass
        # parakeet-rs's mel-frame divisibility check. These are the pinned
        # upstream streaming values: 32/560/32 frames, each divisible by 8.
        streaming_chunk_secs = 0.32;
        streaming_left_context_secs = 5.6;
        streaming_right_context_secs = 0.32;
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

  home.packages = lib.optionals (hostName == "coordinator") [ osdPackage ];

  # The selected model is the only entry in Voxtype 0.7.5's registry marked as
  # compatible with its cache-aware live-streaming pipeline. Bootstrap it through
  # Voxtype's own idempotent downloader before the daemon starts, mirroring the
  # intentional runtime-pull boundary used by FastFlowLM.
  systemd.user.services.voxtype = lib.mkIf (hostName == "coordinator") {
    Unit.X-Restart-Triggers = [ config.xdg.configFile."voxtype/config.toml".source ];

    Service = {
      # `setup --download` also persists its selected model to the default
      # config path. Home Manager owns that path with an immutable store
      # symlink, so give setup a throw-away XDG config root while leaving
      # XDG_DATA_HOME untouched: the model still lands in Voxtype's canonical
      # ~/.local/share/voxtype/models directory and the daemon continues to use
      # the declarative config generated above.
      ExecStartPre = "${pkgs.coreutils}/bin/env XDG_CONFIG_HOME=%t/voxtype-bootstrap ${package}/bin/voxtype setup --download --model ${parakeetModel} --quiet";
      RuntimeDirectory = "voxtype-bootstrap";
      RuntimeDirectoryMode = "0700";
      TimeoutStartSec = "infinity";
    };
  };
}
