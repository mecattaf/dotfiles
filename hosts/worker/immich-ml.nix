{
  config,
  lib,
  pkgs,
  ...
}:
# Immich machine learning — MOVED here from the coordinator 2026-08-21 (#229,
# Tom's ruling: he uses this box rarely, so the ML batches belong on it rather
# than on the machine he is actually typing on).
#
# Shape is unchanged from hosts/coordinator/immich-ml.nix (now deleted): the
# backend is standalone from services.immich — which lives on the NAS since the
# 2026-08-02 cutover — and is woken on demand by a socket-activated proxy that
# retires after 15 idle minutes. Only the admitted interface and the identity of
# the box changed. The NAS's Immich now dials http://worker:3003
# (hosts/nas/media.nix), which resolves through the fleet-wide
# networking.hosts pin for 10.42.0.5 in modules/common.nix.
#
# Why this host and not the NAS itself: the NAS is a stable-pinned appliance
# with no accelerator worth the name, and Immich's own
# services.immich.machine-learning stays disabled there (asserted in the flake).
# Why on-demand and not resident: the model TTL is 300s and Tom triggers ML
# rarely, so a resident worker process would hold memory for nothing.
#
# VERSION COUPLING, now across a host boundary. The server (NAS) and this ML
# backend are halves of one application and must be the same Immich. That was
# implicit while both lived beside each other and is not implicit any more, so
# the package is taken from `services.immich.package` — the same option the NAS
# sets from inputs.nixpkgs — rather than reaching for pkgs.immich directly. The
# flake asserts the two versions are equal; if they ever drift, that is a build
# failure instead of a confusing runtime error mid-batch.
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
    description = "Immich machine learning on worker";
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
  # rather than global. wlp192s0 is this box's LAN leg (the same interface name
  # as on its twin — see the interface-name pin in ./default.nix); every client
  # on that segment is a pinned house device. Port 3003 is deliberately NOT
  # opened anywhere else, and there is no tailnet on this host to open it on.
  # The requesting party is the NAS at 10.42.0.1.
  networking.firewall.interfaces.wlp192s0.allowedTCPPorts = [ 3003 ];
  systemd.sockets.immich-ml-access = {
    description = "Wake worker Immich ML on the first private request";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "0.0.0.0:3003";
      NoDelay = true;
    };
  };
  systemd.services.immich-ml-access = {
    description = "On-demand private proxy for worker Immich ML";
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
