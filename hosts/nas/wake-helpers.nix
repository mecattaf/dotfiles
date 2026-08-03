# Shared building blocks for the NAS's "wake on first connection" services
# (#130 convention 2: every user-facing service is `wantedBy = mkForce [ ]` +
# `StopWhenUnneeded`, fronted by a systemd-socket-proxyd `*-access` pair so the
# single rotating data disk can actually park).
#
# This is a PLAIN FUNCTION FILE, not a NixOS module: it must never appear in
# hosts/nas/default.nix's `imports`. Each consumer calls
#   inherit (import ./wake-helpers.nix { inherit lib pkgs; }) waitForHttp ...;
# from its own `let`. Factored out of media.nix for reuse by future wake pairs
# (#130) — the definitions are byte-identical to the originals, so the
# existing Immich/Navidrome units keep their exact store paths.
{ lib, pkgs }:
{
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";

  # ExecStartPre for an *-access proxy: hold the connection until the woken
  # backend actually answers HTTP, so the first client sees a slow response
  # instead of a connection reset while the disk spins up.
  waitForHttp =
    name: url:
    pkgs.writeShellScript "${name}-wait-for-http" ''
      for _ in $(${pkgs.coreutils}/bin/seq 1 90); do
        if ${pkgs.curl}/bin/curl --fail --silent --max-time 1 ${lib.escapeShellArg url} >/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "${name} did not become ready within 90 seconds" >&2
      exit 1
    '';

  # The hardening block shared by every *-access proxy. The proxy itself moves
  # bytes between two sockets and needs nothing else: no filesystem, no devices,
  # no privileges. Kept as one attrset so a future hardening fix lands on all of
  # them at once rather than on whichever file the author remembered.
  proxyHardening = {
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
}
