{
  config,
  lib,
  pkgs,
  ...
}:
# Immich ML moved intact from the retired worker to Strix. The NAS calls
# http://strix:3003 over Ethernet. Socket activation wakes the local backend;
# models expire after five minutes and the idle proxy stops after fifteen.
# Use the same Immich package as the NAS server (asserted by closet-topology).
let
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
  waitForMl = pkgs.writeShellScript "immich-ml-wait-for-http" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 90); do
      if ${pkgs.curl}/bin/curl --fail --silent --max-time 1 \
        http://127.0.0.1:3004/ping >/dev/null; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "Immich ML did not become ready within 90 seconds" >&2
    exit 1
  '';
in
{
  systemd.services.immich-machine-learning = {
    description = "Immich machine learning on Strix";
    after = [ "network.target" ];
    wantedBy = [ ];
    environment = {
      HOME = "/var/cache/immich";
      IMMICH_HOST = "127.0.0.1";
      IMMICH_PORT = "3004";
      MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
      MACHINE_LEARNING_MODEL_TTL = "300";
      MACHINE_LEARNING_WORKERS = "1";
      MACHINE_LEARNING_WORKER_TIMEOUT = "120";
      XDG_CACHE_HOME = "/var/cache/immich";
    };
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      ExecStart = lib.getExe config.services.immich.package.machine-learning;
      CacheDirectory = "immich";
      User = "tom";
      Group = "users";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  # ML has no application-layer authentication, so the door is interface-scoped
  # rather than global. enp191s0 is this box's LAN leg (wired into the BE550;
  # see the interface-name pin in ./default.nix); every client on that segment
  # is a pinned house device. Port 3003 is
  # deliberately NOT opened anywhere else, and there is no tailnet on this host
  # to open it on. The requesting party is the NAS at 10.42.0.1.
  networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 3003 ];
  systemd.sockets.immich-ml-access = {
    description = "Wake Strix Immich ML on the first private request";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "0.0.0.0:3003";
      NoDelay = true;
    };
  };
  systemd.services.immich-ml-access = {
    description = "On-demand private proxy for Strix Immich ML";
    requires = [ "immich-machine-learning.service" ];
    after = [ "immich-machine-learning.service" ];
    serviceConfig = {
      ExecStartPre = waitForMl;
      ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:3004";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      TimeoutStartSec = "2min";
    };
  };
}
