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
  # NO hardcoded NHI list. The one that used to sit here — "0000:c4:00.5/.6,
  # identical PCI addresses on both twins" — was FALSE: those are the
  # WORKER's functions; this box binds 0000:c5:00.5/.6 (verified live on
  # each: ls /sys/bus/pci/drivers/thunderbolt/). So the rebind rung wrote a
  # nonexistent device into unbind, "2>/dev/null || true" swallowed the
  # failure, and the rung NEVER fired on the coordinator (#267). The heal
  # script now derives the bound functions at runtime from the driver
  # directory — correct on either twin, survives board revisions.
  peer = "10.99.0.2"; # the worker's end of the rail-0 /30
  peer2 = "10.99.2.2"; # the worker's end of the rail-2 /30 (#274)
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
      # The NHI functions are DERIVED from the driver's bound-device
      # symlinks (c5:00.5/.6 here, c4:00.5/.6 on the worker — per-host,
      # never hardcode, #267), captured BEFORE unbinding removes them.
      # Failures are loud now: the old "2>/dev/null || true" is exactly
      # what hid #267 for the life of this file.
      nhis=$(ls /sys/bus/pci/drivers/thunderbolt/ | grep -E '^[0-9a-f]+:' || true)
      if [ -z "$nhis" ]; then
        echo "retimers present but NO NHI bound to the thunderbolt driver — nothing to rebind"
      else
        echo "retimers present but no XDomain peer — rebinding USB4 NHIs: $nhis"
        for d in $nhis; do
          echo "$d" > /sys/bus/pci/drivers/thunderbolt/unbind || echo "unbind failed for $d"
        done
        sleep 2
        for d in $nhis; do
          echo "$d" > /sys/bus/pci/drivers/thunderbolt/bind || echo "bind failed for $d"
        done
      fi
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

  # ── Rail 2 (#274, 2026-08-31): thunderbolt1 gets a real /30 ────────────────
  #
  # Cable B ran link-local-only since the fleet was built. #274's measured
  # finding (torch 2.13.0+rocm7.14.0): with a comma list like
  # GLOO_SOCKET_IFNAME=thunderbolt0,thunderbolt1, any NON-resolving name
  # fails loudly and immediately, naming the bad interface — but a name that
  # RESOLVES (thunderbolt1's self-assigned 169.254.x) with nothing configured
  # on the far end HANGS FOREVER, no exception, no log line. That is the one
  # undiagnosable state in the matrix, and cable B sat in it. A /30 on BOTH
  # ends removes it permanently: the name resolves AND the peer answers. It
  # also makes cable B's bring-up sequence match the one usb4-stream's
  # carrier gate was designed against (#275), and cable B has consumers on
  # purpose now — the TB-IP aggregation experiment and the USB4STREAM bench
  # are deliberately staged onto it so a hop-table wedge cannot take down
  # the tensor rail.
  #
  # Declarative (the eth-fleet ensureProfiles idiom), UNLIKE rail 0's
  # tb-fleet, which is imperative NM state on both ends and must not be
  # disturbed (hosts/worker/default.nix doctrine). Rail 2 has no imperative
  # history to preserve — only NM's volatile auto "Wired connection 2"
  # (ipv4.method=link-local, from NM_AUTO_DEFAULT_LINK_LOCAL_ONLY=1 in NM's
  # own 90-nm-thunderbolt.rules), which loses autoconnect to any real
  # profile (priority 50 vs the auto default's -999) and is not regenerated
  # while a profile matches the device.
  #
  # HAZARDS (#274):
  #   - BOTH ENDS TOGETHER. A one-sided /30 recreates the exact
  #     addressed-but-peerless hang and is WORSE than link-local. This
  #     profile and the worker's (hosts/worker/default.nix) land in one
  #     commit and must switch in the same deploy window.
  #   - Rail 2's worker-side controller failed DMA activation on its
  #     FIRST-EVER tunnel use (config-space read timeout — usb4-stream.nix
  #     HAZARDS; flashnext DECISIONS-2026-08-30 §3.2). This /30 is where
  #     that history gets retested: WATCH THE FIRST BRING-UP; the tripwire
  #     below makes a recurrence loud within ~1 h.
  #   - thunderbolt1 is a PROBE-ORDER name (#266). With both cables now
  #     addressed, a one-sided name flip would land the two /30s on crossed
  #     cables — both TB rails dark with carrier up. The match.path pin
  #     below keeps THIS /30 off the wrong cable entirely; rail 0's
  #     imperative name-bound profile keeps its exposure until #266's own
  #     fix, mitigated by its heal ladder (whose rebind re-rolls the
  #     assignment) and tripwire.
  networking.networkmanager.ensureProfiles.profiles.tb-fleet2 = {
    connection = {
      id = "tb-fleet2";
      type = "ethernet";
      interface-name = "thunderbolt1";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    # #266 mitigation — the strongest pin landable without a rename
    # (2026-08-31). match.path binds this profile to the PHYSICAL NHI via
    # udev's ID_PATH, which is per-host: cable B is pci-0000:c5:00.5 here
    # and pci-0000:c4:00.6 on the worker (cable map triple-verified —
    # unique_id reciprocity, configfs hopid interlock, byte-counter
    # cross-match; #275). interface-name AND match.path must BOTH match, so
    # on a probe-order flip (thunderbolt1 = cable A's netdev) this profile
    # goes UNAVAILABLE instead of addressing the wrong cable: rail 2 dark
    # and loud (tb-rail2-reachability fires; nmcli shows the profile
    # inactive), never silently crossed.
    #
    # Why not a .link rename to cable-stable names: renaming inside the
    # kernel's thunderbolt%d namespace races EEXIST when two netdevs swap,
    # and leaving that namespace forces a sweep of every name consumer
    # (usb4-stream's rail anchor, fn-rdma's roce_netdev + UDP 4791 door,
    # the per-interface firewall stanzas) — that sweep is #266's own work,
    # owned elsewhere, and needs more than one reboot to trust.
    #
    # If the cables are ever re-plugged into swapped ports these paths go
    # stale on BOTH ends at once — update both profiles in one commit,
    # from readlink -f /sys/class/net/thunderbolt*.
    match.path = "pci-0000:c5:00.5;";
    ipv4 = {
      method = "manual";
      addresses = "10.99.2.1/30";
      never-default = true;
      ignore-auto-dns = true;
      # DELIBERATELY no routeN: fleet-identity (10.99.9.x) failover stays on
      # the 5GbE at metric 20 and rail 0 at metric 50 (#240 ruling — admin
      # traffic prefers the wire, TB as failover). Rail 2 is the
      # experiment/bench rail, not a third failover path.
    };
    ipv6.method = "disabled";
  };

  # Rail 2's tripwire — gentler than rail 0's ON PURPOSE. Rail 0 carries the
  # 2026-08-21 MUST-always-work ruling and stays loud within ~15 min; rail 2
  # is the experiment rail, so loud within ~1 h is enough, and a tighter
  # clock would just double-fire alongside rail 0's during any shared
  # PD/CCGx event (one CCGx owns both rear ports).
  myTripwire.tb-rail2-reachability = {
    description = "the worker answers pings over the rail-2 /30 (cable B)";
    intervalSeconds = 900;
    onBootSec = "10min";
    threshold = 1;
    comparison = "ge";
    sustainSeconds = 3600;
    rearm = 0;
    refractorySeconds = 43200;
    valueField = "TB2_DARK";
    sensorPath = [ pkgs.iputils ];
    sensor = ''
      if ping -c 2 -W 3 ${peer2} >/dev/null 2>&1; then
        echo "0 tb2 1"
      else
        echo "1 tb2 1"
      fi
    '';
    onFirePath = [ pkgs.coreutils ];
    onFire = ''
      mkdir -p /var/lib/failure-markers
      printf '%s — rail 2 (cable B, tb-fleet2) has not answered on ${peer2} for ~1 h (episode %s)\n  Check BOTH ends: nmcli -g GENERAL.STATE connection show tb-fleet2 (must be activated on each). Then readlink -f /sys/class/net/thunderbolt1 — must end in c5:00.5/domain0/... on the coordinator and c4:00.6/domain1/... on the worker; a mismatch is the #266 probe-order name flip, not a dead cable. If the profile is active and the path is right, suspect the worker controller DMA-activation history (HAZARDS in hosts/coordinator/tb-fleet.nix)\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/tb-rail2-reachability
    '';
  };
}
