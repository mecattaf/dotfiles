{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# Voxtype — local streaming dictation on the interactive AMD Strix Halo
# coordinator. The upstream Home Manager module owns the package, generated
# TOML, and sole systemd user service. Other NixOS hosts import the options but
# leave the complete integration disabled.
let
  hostName = osConfig.networking.hostName;
  package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.onnx-migraphx;
  osdPackage = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-gtk4;
  parakeetModel = "parakeet-unified-en-0.6b";

  # Voxtype 0.7.5 runs `output.post_process.command` and both output hooks
  # through a bare `sh -c`: no argument interpolation, no injected environment
  # (src/output/post_process.rs, src/output/mod.rs `run_hook`). Every command
  # below therefore resolves its own target.

  # The dictation route. `hk voice text` delivers stdin into the focused
  # window's herdr pane and prints nothing; on any other window it prints
  # nothing, sends zero bytes and exits 3 (herdr-kitten hk/voice.py). Translate
  # that one exit code back into the transcript on stdout so the wtype driver
  # types it, and let every other status propagate — voxtype reuses the original
  # text on a non-zero exit by itself, so a herdr outage still gets typed.
  dictationRoute = ''
    text=$(cat)
    printf '%s' "$text" | hk voice text
    status=$?
    [ "$status" -eq 3 ] || exit "$status"
    printf '%s' "$text"
  '';

  # The recording spinner. `hk voice begin`/`end` need both a kitty socket in
  # $KITTY_LISTEN_ON and an explicit --window id (herdr-kitten hk/kittyc.py);
  # the voxtype daemon has neither, so the start hook resolves the focused kitty
  # instance from niri and its focused window from kitty — the same `is_focused`
  # predicate `hk voice text` uses to pick its delivery target — and records the
  # pair so the stop hook clears the spinner from the window that got it. A
  # focused non-kitty surface has no socket to reach and simply gets no spinner.
  spinnerState = "$XDG_RUNTIME_DIR/voxtype-spinner-window";

  spinnerStart = ''
    pid=$(niri msg --json focused-window | jq -er .pid) || exit 0
    KITTY_LISTEN_ON="unix:@kitty-$pid"
    export KITTY_LISTEN_ON
    window=$(kitty @ --to "$KITTY_LISTEN_ON" ls |
      jq -er 'first(.[].tabs[].windows[] | select(.is_focused) | .id)') || exit 0
    hk voice begin --window "$window" || exit 0
    printf '%s %s\n' "$KITTY_LISTEN_ON" "$window" > "${spinnerState}"
  '';

  spinnerStop = ''
    read -r socket window 2>/dev/null < "${spinnerState}" || exit 0
    rm -f "${spinnerState}"
    KITTY_LISTEN_ON="$socket" hk voice end --window "$window" || exit 0
  '';
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

      # niri binds have no on-release trigger, so hold-to-talk lives in
      # voxtype's own evdev layer (spec B B12) rather than in a compositor
      # keybinding. Tom is already in the `input` group, so the listener needs
      # no NixOS change; niri swallows Mod+Space so the focused surface never
      # receives the chord while dictating.
      hotkey = {
        enabled = true;
        key = "SPACE";
        modifiers = [ "LEFTMETA" ];
        mode = "push_to_talk";
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

        # Dictation goes global (spec B B13): herdr panes are fed by send-text,
        # every other Wayland surface by the wtype driver. `fallback_on_empty =
        # false` is what makes the herdr half silent — the route exits 0 with
        # empty stdout once the text is already in the pane, and voxtype must
        # then type nothing rather than re-type the transcript on top of it.
        #
        # CONFLICT, not resolvable in this file: at the pinned rev post_process
        # is dead while `parakeet.streaming = true`. The daemon does hand the
        # processor to `StreamingSession::commit_segment`, which binds it to
        # `_post_process` and never calls it ("post_process is intentionally
        # bypassed during streaming", src/output/streaming.rs:180). B13 asserts
        # the opposite and cites that same doc block. Streaming is pinned byte
        # for byte by U.5/F.18 and this route is required by R5.4, so both land
        # as ruled and the runtime claim R5.5 is left to adjudicate upstream.
        post_process = {
          command = dictationRoute;
          fallback_on_empty = false;
        };

        # Spinner on when recording starts, off after the output burst. Under
        # streaming these output hooks fire once per typed segment by design
        # (src/output/streaming.rs:158-162), so the spinner clears at the first
        # burst rather than at key release.
        pre_recording_command = spinnerStart;
        post_output_command = spinnerStop;
      };
    };
  };

  home.packages = lib.optionals (hostName == "coordinator") [ osdPackage ];

  # The selected model is the only entry in Voxtype 0.7.5's registry marked as
  # compatible with its cache-aware live-streaming pipeline. Bootstrap it through
  # Voxtype's own idempotent downloader before the daemon starts, mirroring the
  # runtime-owned model-data boundary used by FastFlowLM.
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
