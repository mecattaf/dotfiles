{ pkgs, ... }:
# ─── The coordinator↔worker Thunderbolt link: MUST always work ──────────────
#
# Tom's ruling (2026-08-21, first dual-reboot night): "the coordinator-worker
# thunderbolt link MUST always be working. this is unacceptable really."
#
# What that night established, from both kernel journals:
#   - SINGLE-end reboot self-heals: the worker rebooted at 21:07 with the
#     coordinator up, and the link trained by itself within seconds
#     ("thunderbolt 0-2: new host found … Linux coordinator").
#   - DUAL reboot wedges the CABLE level: after the coordinator's 21:26 boot,
#     neither end saw the peer OR the cable retimers again. Driver rebinds of
#     the USB4 NHIs on both ends changed nothing — on AMD the USB4 connection
#     manager is firmware, and once the sideband is wedged the only recovery
#     is a PHYSICAL REPLUG of the cable (either end, five seconds).
#   - Software CAN still lose the link with the cable fine: thunderbolt-net
#     not loaded (this box didn't load it at boot — no net service advertised,
#     no thunderbolt0), or NM not re-activating tb-fleet.
#
# So the guarantee is layered:
#   1. thunderbolt-net pinned into boot.kernelModules (both ends).
#   2. tb-link-heal (below + worker twin): every 2 min, if the peer is dark,
#      fix what software can — rebind the NHIs when no XDomain peer exists,
#      re-up tb-fleet when the peer exists but doesn't answer.
#   3. A tripwire that makes any remaining darkness LOUD within ~15 min,
#      with the replug instruction in the marker text. Silent failure is the
#      part that was actually unacceptable; a wedged cable can only be
#      surfaced, not software-healed.
let
  # Strix Halo USB4 NHI functions — identical PCI addresses on both twins
  # (verified live on each: /sys/bus/pci/drivers/thunderbolt).
  nhiDevices = [
    "0000:c4:00.5"
    "0000:c4:00.6"
  ];
  peer = "10.99.0.2"; # the worker's end of the /30
  healScript = pkgs.writeShellScript "tb-link-heal" ''
    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.iputils
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.networkmanager
      ]
    }
    # Healthy: peer answers. Nothing to do, nothing to log.
    ping -c 1 -W 3 ${peer} >/dev/null 2>&1 && exit 0
    # An XDomain peer entry looks like "0-2"/"1-2" — a route below a domain
    # that is not the host router itself ("0-0"/"1-0").
    if ls /sys/bus/thunderbolt/devices/ | grep -qE '^[0-9]+-[1-9]'; then
      echo "peer device present but ${peer} dark — re-activating tb-fleet"
      nmcli connection up tb-fleet || true
    else
      echo "no XDomain peer — rebinding USB4 NHIs (software replug attempt)"
      for d in ${toString nhiDevices}; do
        echo "$d" > /sys/bus/pci/drivers/thunderbolt/unbind 2>/dev/null || true
      done
      sleep 2
      for d in ${toString nhiDevices}; do
        echo "$d" > /sys/bus/pci/drivers/thunderbolt/bind 2>/dev/null || true
      done
    fi
  '';
in
{
  # Layer 1: the net service must exist the moment the link trains — found
  # NOT loaded after the first reboot (worker had it, this box did not).
  boot.kernelModules = [ "thunderbolt-net" ];

  # Layer 2: the reconciler.
  systemd.services.tb-link-heal = {
    description = "Heal the coordinator-worker Thunderbolt link where software can";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = healScript;
    };
  };
  systemd.timers.tb-link-heal = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
    };
  };

  # Layer 3: loud within ~15 min, with the recovery instruction attached.
  myTripwire.tb-fleet-reachability = {
    description = "the worker answers pings over the Thunderbolt /30";
    intervalSeconds = 300;
    onBootSec = "5min";
    threshold = 1;
    comparison = "ge";
    sustainSeconds = 900;
    rearm = 0;
    refractorySeconds = 21600;
    valueField = "TB_DARK";
    sensorPath = [ pkgs.iputils ];
    sensor = ''
      if ping -c 2 -W 3 ${peer} >/dev/null 2>&1; then
        echo "0 tb 1"
      else
        echo "1 tb 1"
      fi
    '';
    onFirePath = [ pkgs.coreutils ];
    onFire = ''
      mkdir -p /var/lib/failure-markers
      printf '%s — the worker has not answered on the Thunderbolt link for ~15 min (episode %s)\n  tb-link-heal retries every 2 min; if this followed a DUAL reboot the cable is wedged below software: REPLUG the TB cable at either end (see hosts/coordinator/tb-fleet.nix)\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/tb-fleet-reachability
    '';
  };
}
