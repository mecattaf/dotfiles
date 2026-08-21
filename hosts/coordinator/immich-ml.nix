{
  lib,
  pkgs,
  ...
}:
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
  # Standalone from services.immich so the endpoint stays on coordinator after
  # PostgreSQL, Redis, the Immich server, and Navidrome move to the NAS.
  systemd.services.immich-machine-learning = {
    description = "Immich machine learning on coordinator";
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
      ExecStart = lib.getExe pkgs.immich.machine-learning;
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

  # ML has no application-layer authentication. Port 3003 is deliberately NOT
  # opened on Tailscale; the NAS's Immich points at http://coordinator:3003
  # (hosts/nas/media.nix) and its requests arrive over the BE550 LAN on
  # wlp192s0 (2026-08-21: the /30 cable and its enp191s0 admission are
  # retired). The wifi admission is LAN-wide by interface; every LAN client is
  # a pinned house device. The proxy wakes the backend for a batch and
  # retires after 15 idle minutes.
  networking.firewall.interfaces.wlp192s0.allowedTCPPorts = [ 3003 ];
  systemd.sockets.immich-ml-access = {
    description = "Wake coordinator Immich ML on the first private request";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "0.0.0.0:3003";
      NoDelay = true;
    };
  };
  systemd.services.immich-ml-access = {
    description = "On-demand private proxy for coordinator Immich ML";
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
