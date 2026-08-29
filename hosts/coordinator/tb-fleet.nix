{
  config,
  lib,
  pkgs,
  ...
}:
# ─── The coordinator↔worker Thunderbolt link: MUST always work ──────────────
#
# Tom's ruling (2026-08-21, first dual-reboot night): "the coordinator-worker
# thunderbolt link MUST always be working. this is unacceptable really."
#
# What that night established, from both kernel journals (revised same night
# after the live forensics + recovery — the first write-up got the mechanism
# wrong):
#   - SINGLE-end reboot self-heals: the worker rebooted at 21:07 with the
#     coordinator up, and the link trained by itself within seconds
#     ("thunderbolt 0-2: new host found … Linux coordinator").
#   - The DUAL-reboot wedge is the CCGx PD CONTROLLER, not the cable and not
#     the thunderbolt stack. Strix Halo runs the SOFTWARE connection manager
#     (_OSC grants the OS USB3/DP/PCIe/XDomain — the earlier "firmware CM"
#     claim was wrong). The Infineon/Cypress CCGx that owns the rear USB4
#     ports latched blind: UCSI answered commands but reported zero
#     connections, 0 mV VBUS, and physical replugs produced ZERO kernel
#     events on both ends. It sits on standby power, so warm reboots and
#     even soft-off carried the wedge through.
#   - The PROVEN fix (2026-08-21 ~22:48, live): `framework_tool --pd-reset 2`
#     (HPI device reset of the "Back" CCGx via the EC) — CC detection, the
#     on-board retimers, the USB-C peripherals, and the XDomain host all
#     returned within seconds. Then rebind ucsi_acpi (the PPM times out
#     after the reset). No cold boot, no mains pull, no replug needed.
#   - NHI rebinds / PCI rescans / ucsi rebinds alone do nothing while the
#     PD controller is blind: link bring-up starts at CC detect, which is
#     below everything the thunderbolt driver can touch.
#   - Software CAN still lose the link with the PD layer fine: thunderbolt-net
#     not loaded (this box didn't load it at boot — no net service advertised,
#     no thunderbolt0), or NM not re-activating tb-fleet.
#
# So the guarantee is layered:
#   1. thunderbolt-net pinned into boot.kernelModules (both ends).
#   2. tb-link-heal (below + worker twin): every 2 min, if the peer is dark,
#      escalate by observed cost: re-up tb-fleet when the XDomain peer
#      exists; rebind the NHIs when retimers exist but no peer; and when the
#      bus shows NO retimers at all (the PD-blind signature) reset the CCGx
#      itself — rate-limited, because it also bounces the other rear port.
#   3. A tripwire that makes any remaining darkness LOUD within ~15 min,
#      with the recovery instruction in the marker text.
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
        pkgs.framework-tool
      ]
    }
    STATE=/var/lib/tb-link-heal
    # Healthy: peer answers. Clear the escalation stamp, say nothing.
    if ping -c 1 -W 3 ${peer} >/dev/null 2>&1; then
      rm -f "$STATE/pd-reset-stamp"
      exit 0
    fi
    # An XDomain peer entry looks like "0-2"/"1-2" — a route below a domain
    # that is not the host router itself ("0-0"/"1-0").
    if ls /sys/bus/thunderbolt/devices/ | grep -qE '^[0-9]+-[1-9]'; then
      echo "peer device present but ${peer} dark — re-activating tb-fleet"
      nmcli connection up tb-fleet || true
    elif ls /sys/bus/thunderbolt/devices/ | grep -qE '^[0-9]+-[0-9]+:'; then
      # Retimers ("0-0:2.1") enumerate only while the port electrically
      # trains — their presence means CC/PD is alive and the stall is in
      # the thunderbolt layer, where an NHI re-probe re-runs tb_start().
      echo "retimers present but no XDomain peer — rebinding USB4 NHIs"
      for d in ${toString nhiDevices}; do
        echo "$d" > /sys/bus/pci/drivers/thunderbolt/unbind 2>/dev/null || true
      done
      sleep 2
      for d in ${toString nhiDevices}; do
        echo "$d" > /sys/bus/pci/drivers/thunderbolt/bind 2>/dev/null || true
      done
    else
      # NO retimers at all: the PD-blind signature of 2026-08-21 — the CCGx
      # stopped doing CC detection and nothing above it can help. The proven
      # cure is an HPI reset of the "Back" PD controller (index 2; the only
      # one on this board) followed by a ucsi_acpi rebind (the PPM times out
      # after the reset). Rate-limited to one shot per 30 min because the
      # reset also bounces the OTHER rear USB-C port (audio devices blip),
      # and because "cable genuinely unplugged" looks identical from here.
      now=$(date +%s)
      stamp=$(stat -c %Y "$STATE/pd-reset-stamp" 2>/dev/null || echo 0)
      if [ $((now - stamp)) -gt 1800 ]; then
        echo "no retimers on the bus — PD-blind signature; resetting CCGx PD controller"
        framework_tool --pd-reset 2 || true
        sleep 5
        echo USBC000:00 > /sys/bus/platform/drivers/ucsi_acpi/unbind 2>/dev/null || true
        sleep 2
        echo USBC000:00 > /sys/bus/platform/drivers/ucsi_acpi/bind 2>/dev/null || true
        touch "$STATE/pd-reset-stamp"
      else
        echo "PD-blind but CCGx reset already fired recently — holding (replug or peer boot may still land)"
      fi
    fi
  '';
in
{
  # Layer 1: the net service must exist the moment the link trains — found
  # NOT loaded after the first reboot (worker had it, this box did not).
  # Gated off under fn-rdma (#241): systemd-modules-load ignores blacklists
  # and would drag the STOCK core in as this module's dependency, beating the
  # patched set to the bus; fn-rdma's boot unit inserts its own matched net.
  # thunderbolt_stream: the 7.2 in-tree USB4 streaming service (dotfiles#244's
  # "USB4STREAM"). Control plane verified live on both twins 2026-08-29: the
  # kstream XDomain service appears on BOTH rails (0-2.1/1-2.1), and a
  # configfs round-trip (/sys/kernel/config/thunderbolt/stream/<svc>/<name>)
  # materializes /dev/tbstreamN. Pinned here so the service is advertised to
  # the peer from boot, not from whenever someone modprobes it.
  boot.kernelModules = lib.mkIf (!config.myFnRdma.enable) [
    "thunderbolt-net"
    "thunderbolt_stream"
  ];

  # Layer 2: the reconciler.
  systemd.services.tb-link-heal = {
    description = "Heal the coordinator-worker Thunderbolt link where software can";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = healScript;
      StateDirectory = "tb-link-heal";
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
      printf '%s — the worker has not answered on the Thunderbolt link for ~15 min (episode %s)\n  tb-link-heal retries every 2 min and now includes the CCGx PD reset; if still dark, run on EACH blind end: sudo framework_tool --pd-reset 2, then rebind ucsi_acpi (see hosts/coordinator/tb-fleet.nix)\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/tb-fleet-reachability
    '';
  };
}
