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
  options.services.qwen-tts.enable = lib.mkEnableOption "on-demand Qwen speech for the physical seats";
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myFleet.has "compute";
        message = "Qwen TTS inference requires the compute role; the client only plays audio.";
      }
    ];
    services.local-models.artifacts = lib.mkAfter [
      "qwen3-tts-1.7b-base-q8-0"
      "qwen-k2so-midway-b"
      "qwen3-tts-tokenizer-f32"
    ];
    environment.systemPackages = [
      pkgs.speech-session
      pkgs.qwen-speech
      pkgs.qwentts
    ];
    # No WantedBy: requests start the unit. Boot/switch never loads weights.
    systemd.user.services.qwen-tts = {
      description = "Qwen speech synthesis for seat playback (on demand)";
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
