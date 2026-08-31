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

  # ── Rail 0 (#266, 2026-08-31): the last imperative rail becomes declarative
  #
  # Until #266 this /30 was NOT in this file at all: it lived as a hand-made
  # keyfile at /etc/NetworkManager/system-connections/tb-fleet.nmconnection on
  # each twin, bound purely by `interface-name=thunderbolt0`, and the doctrine
  # in this file said it "must not be disturbed". The rename forces the issue
  # — after it there IS no thunderbolt0, so the imperative profile would have
  # matched nothing and taken the fast rail down with it. Declaring it here is
  # therefore not scope creep; it is the only way the rename is safe.
  #
  # Faithful to the keyfile it replaces, including the piece that is easy to
  # miss: route1 is the metric-50 leg of the #240 failover ruling (this twin
  # reaches the OTHER twin's fleet identity 10.99.9.x over TB when the 5GbE
  # metric-20 leg is gone). Dropping it would have quietly demoted the fleet
  # to a single admin path.
  #
  # MIGRATION, one time, both twins: the legacy /etc keyfile must be removed
  # in the same window, or NM loads two profiles named tb-fleet with different
  # UUIDs. The stale one binds thunderbolt0 and so can never activate, but it
  # clutters `nmcli con` and would win the name on any future rollback.
  networking.networkmanager.ensureProfiles.profiles.tb-fleet = {
    connection = {
      id = "tb-fleet";
      type = "ethernet";
      interface-name = "rail0";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    # Cable A's NHI on this host — same both-pins-name-one-cable shape as
    # tb-fleet2 below, and the same fail-closed property.
    match.path = "pci-0000:c5:00.6;";
    ipv4 = {
      method = "manual";
      addresses = "10.99.0.1/30";
      never-default = true;
      ignore-auto-dns = true;
      # The #240 failover leg, carried over verbatim from the keyfile.
      # Keyfile syntax (routeN=dest,next-hop,metric) — an nmcli-style
      # `routes` key is silently ignored by the parser, which here would
      # have meant losing the TB failover path without a single error.
      route1 = "10.99.9.2/32,10.99.0.2,50";
    };
    ipv6.method = "disabled";
  };

  # ── Rail 2 (#274, 2026-08-31): cable B gets a real /30 ─────────────────────
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
      interface-name = "rail2";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    # BOTH pins now name the SAME cable, which is the whole difference
    # between this and the 2026-08-31 12:25 version of this file.
    #
    # That version paired interface-name=thunderbolt1 with match.path=cable B
    # and reasoned that requiring both to match made a probe-order flip park
    # the profile rather than cross the cables. The reasoning was right and
    # the fail-safe fired exactly as designed at the 12:27 reboot — but it
    # fired on EVERY flip, because a probe-order name and a soldered PCI
    # function can only agree by luck. Rail 2 was down from that reboot until
    # #266 landed.
    #
    # `rail2` is now cable B's netdev by construction
    # (modules/fleet-rail-names.nix pins it with a .link Name= on this
    # ID_PATH), so name and path agree on every boot. Keeping match.path as
    # well is deliberate belt-and-braces: if the rename ever regressed, the
    # two would disagree again and this profile would park LOUDLY
    # (tb-rail2-reachability fires; nmcli shows it inactive) instead of
    # addressing the wrong cable. Fail-closed, but no longer fail-often.
    #
    # The .link objection recorded here previously — that renaming races
    # EEXIST when two netdevs swap — applies only to renaming WITHIN the
    # kernel's thunderbolt%d namespace. rail0/rail2 are a disjoint namespace
    # the kernel never mints, so the collision is unreachable; see the header
    # of modules/fleet-rail-names.nix.
    #
    # If the cables are ever re-plugged into swapped ports this path goes
    # stale on BOTH ends at once — update the table in
    # modules/fleet-rail-names.nix and this profile in one commit, from
    # `udevadm info /sys/class/net/rail2 | grep ID_PATH`.
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
      printf '%s — rail 2 (cable B, tb-fleet2) has not answered on ${peer2} for ~1 h (episode %s)\n  Check BOTH ends: nmcli -g GENERAL.STATE connection show tb-fleet2 (must be activated on each). Then confirm the cable pin held: ip link show rail2 must EXIST, and udevadm info /sys/class/net/rail2 must report ID_PATH=pci-0000:c5:00.5 on the coordinator and pci-0000:c4:00.6 on the worker. A MISSING rail2 means the .link pin did not apply (modules/fleet-rail-names.nix, #266) — look for a thunderbolt1 that should have been renamed. A present rail2 with the right path and no peer is a real dead cable: suspect the worker controller DMA-activation history (HAZARDS in hosts/coordinator/tb-fleet.nix)\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/tb-rail2-reachability
    '';
  };
}
