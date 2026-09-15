{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  coordinator = osConfig.networking.hostName == "coordinator";
  client = osConfig.networking.hostName == "client";
in
{
  home.packages = lib.optionals coordinator [ pkgs.parakeet-service ];
  systemd.user.services.parakeet-service = lib.mkIf coordinator {
    Unit = {
      Description = "Resident Parakeet TDT on coordinator GPU";
    };
    Service = {
      ExecStart = "${pkgs.parakeet-service}/bin/parakeet-service serve";
      Environment = [ "ORT_MIGRAPHX_MODEL_CACHE_PATH=%h/.cache/parakeet-service/migraphx" ];
      RuntimeDirectory = "parakeet-service";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 15;
      KillMode = "control-group";
      MemoryMax = "12G";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.services.speech-wake = lib.mkIf client {
    Unit = {
      Description = "Alexa voice intake on the iContact USB microphone";
      After = [ "pipewire.service" ];
      Wants = [ "pipewire.service" ];
    };
    Service = {
      ExecStart = "${pkgs.speech-wake}/bin/speech-wake --live --dispatch";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      KillMode = "control-group";
      TimeoutStopSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
