{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.qwen-tts;
  root = "/var/lib/local-models";
in
{
  options.services.qwen-tts.enable = lib.mkEnableOption "on-demand Qwen speech for the Zenbook";
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.hostName == "coordinator";
        message = "Qwen TTS inference belongs on the coordinator; the client only plays audio.";
      }
    ];
    services.local-models.artifacts = lib.mkAfter [
      "qwen3-tts-1.7b-base-q8-0"
      "qwen-k2so-midway-b"
      "parakeet-tdt-0.6b-v3-onnx"
      "qwen3-tts-tokenizer-f32"
    ];
    environment.systemPackages = [
      pkgs.mykonos-speech
      pkgs.qwen-speech
      pkgs.qwentts
    ];
    systemd.user.services.mykonos-speech-queue = {
      description = "Read queued Markdown through Qwen and the client";
      unitConfig.ConditionUser = "tom";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.mykonos-speech}/bin/mykonos-speech-queue --qwen ${pkgs.qwen-speech}/bin/qwen-speech --player ${pkgs.mykonos-speech}/bin/mykonos-play";
        TimeoutStartSec = "infinity";
        UMask = "0077";
      };
    };
    systemd.user.paths.mykonos-speech-queue = {
      wantedBy = [ "default.target" ];
      pathConfig = {
        PathChanged = "%h/Speech/intake";
        MakeDirectory = true;
        DirectoryMode = "0700";
      };
    };
    systemd.user.timers.mykonos-speech-queue = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = [
          "*-*-* *:*:00,30"
          "*-*-* 06:05:00"
        ];
        Persistent = true;
      };
    };
    # No WantedBy: requests start the unit. Boot/switch never loads weights.
    systemd.user.services.qwen-tts = {
      description = "Qwen speech synthesis for client playback (on demand)";
      unitConfig.ConditionUser = "tom";
      environment.QWEN_VOICE_PROFILE = "${root}/qwen-k2so-midway-b/voice.json";
      environment.VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        ExecStart = lib.escapeShellArgs [
          "${pkgs.qwen-speech}/bin/qwen-speech"
          "serve"
          "--engine"
          "${pkgs.qwentts}/bin/qwen-tts-server"
          "--model"
          "${root}/qwen3-tts-1.7b-base-q8-0/qwen-talker-1.7b-base-Q8_0.gguf"
          "--codec"
          "${root}/qwen3-tts-tokenizer-f32/qwen-tokenizer-12hz-F32.gguf"
          "--idle-seconds"
          "300"
        ];
        TimeoutStartSec = 300;
        TimeoutStopSec = 15;
        KillMode = "control-group";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
