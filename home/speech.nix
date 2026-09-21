{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  coordinator = osConfig.networking.hostName == "coordinator";
  displayHost = osConfig.myDisplay.enable;
in
{
  home.packages = lib.optionals coordinator [ pkgs.parakeet-service ];
  # Socket-activated, not resident (#448). Residency was nominal: after five
  # idle days the kernel had paged 2.6G of the model into zram anyway, so the
  # warm start it existed to guarantee was not being delivered. systemd owns
  # the listening socket, the first connect loads the model (~4.2s), and
  # --idle-timeout releases it again. `parakeet-relay` waits on the ready
  # handshake, which is what absorbs the cold start.
  systemd.user.sockets.parakeet-service = lib.mkIf coordinator {
    Unit = {
      Description = "Activation socket for Parakeet TDT on the coordinator GPU";
    };
    Socket = {
      ListenStream = "%t/parakeet-service/engine.sock";
      SocketMode = "0600";
      RuntimeDirectory = "parakeet-service";
      RuntimeDirectoryMode = "0700";
    };
    Install.WantedBy = [ "sockets.target" ];
  };
  systemd.user.services.parakeet-service = lib.mkIf coordinator {
    Unit = {
      Description = "Parakeet TDT on the coordinator GPU (socket-activated)";
      Requires = [ "parakeet-service.socket" ];
      After = [ "parakeet-service.socket" ];
    };
    Service = {
      ExecStart = "${pkgs.parakeet-service}/bin/parakeet-service serve --idle-timeout 900";
      Environment = [ "ORT_MIGRAPHX_MODEL_CACHE_PATH=%h/.cache/parakeet-service/migraphx" ];
      RuntimeDirectory = "parakeet-service";
      RuntimeDirectoryMode = "0700";
      # systemd's socket lives in this directory and outlives the server.
      RuntimeDirectoryPreserve = "yes";
      UMask = "0077";
      # The socket is the whole lifecycle: a clean idle exit is success, and a
      # crash is re-armed by the next connect rather than by a restart loop.
      Restart = "no";
      TimeoutStopSec = 15;
      KillMode = "control-group";
      MemoryMax = "12G";
    };
    # Deliberately no Install: the socket is the only activation path.
  };
  systemd.user.services.speech-wake = lib.mkIf displayHost {
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
