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
  home.packages = lib.optionals coordinator [ pkgs.mykonos-parakeet ];
  systemd.user.services.mykonos-parakeet = lib.mkIf coordinator {
    Unit = {
      Description = "Resident Parakeet TDT on coordinator GPU";
    };
    Service = {
      ExecStart = "${pkgs.mykonos-parakeet}/bin/mykonos-parakeet serve";
      Environment = [ "ORT_MIGRAPHX_MODEL_CACHE_PATH=%h/.cache/mykonos-parakeet/migraphx" ];
      RuntimeDirectory = "mykonos-parakeet";
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
  systemd.user.services.mykonos-wake = lib.mkIf client {
    Unit = {
      Description = "Alexa voice intake on the iContact USB microphone";
      After = [ "pipewire.service" ];
      Wants = [ "pipewire.service" ];
    };
    Service = {
      ExecStart = "${pkgs.mykonos-wake}/bin/mykonos-wake --live --dispatch";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      KillMode = "control-group";
      TimeoutStopSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
