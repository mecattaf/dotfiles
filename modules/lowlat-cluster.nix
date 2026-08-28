{
  config,
  lib,
  pkgs,
  ...
}:
# ─── myLowLatCluster: the fleet rails' SPEED guarantee ───────────────────────
#
# hosts/coordinator/tb-fleet.nix and eth-fleet.nix guarantee the links EXIST.
# This module guarantees they are FAST. Measured on the live pair 2026-08-28
# (dotfiles#238): as found, 577 us avg RTT over Thunderbolt; with PM QoS held
# on BOTH ends, 63-90 us — 8.5x, at no power cost (76.22 W vs 74.14 W, inside
# noise). Re-measured 2026-08-28 19:xx with the transient unit live: tb0
# 33/58/122 us mdev 18, eth 58/72/142 us mdev 9, 200 samples each.
#
# CAUSE, found in /sys/devices/system/cpu/cpu*/cpuidle/state*/latency on both
# twins: POLL 0us | C1 1us | C2 18us | C3 350us. Every inter-node packet was
# paying a C3 exit. Holding /dev/cpu_dma_latency at 0 floors the cores at C2.
#
# IT MUST BE HELD ON BOTH ENDS. Coordinator-only measured 468 us: the REMOTE
# wakeup dominates the round trip. That asymmetry is almost certainly why
# published thunderbolt-net tuning results are inconsistent — one-sided PM QoS
# looks like it did nothing, so people conclude the knob is useless. It is not;
# it is just not unilateral. Any RDMA-vs-TCP comparison measured on unheld
# C-states is comparing C3 exits, not transports.
#
# The constraint lifts the moment the fd closes, so this is a HELD fd, not a
# write-and-exit. A bash `exec 3>` fd is not close-on-exec, so it survives the
# `exec sleep infinity` that replaces the shell — verified live 2026-08-28:
# /proc/<pid>/fd/3 -> /dev/cpu_dma_latency. That is why there is no python3 in
# this closure, unlike the throwaway transient unit this file replaces.
#
# WHY AN OPTION AND NOT AN UNCONDITIONAL BLOCK: flooring C3 is right for a
# dedicated inference node and wrong for a laptop. The gate is twofold — the
# option below defaults OFF, and the only importer is modules/strix.nix, which
# only `coordinator` and `worker` import. The zenbook can never see it.
#
# ─── The rails this fleet actually has, 2026-08-28 ──────────────────────────
#
#   thunderbolt0   c4:00.5 -> domain0   10.99.0.1/30   tb-fleet, the fast rail
#   thunderbolt1   c4:00.6 -> domain1   link-local     TRAINED BUT UNCONFIGURED
#   enp191s0       5GbE                 10.99.1.1/30   eth-fleet, the fallback
#
# Two USB4 host routers on SEPARATE NHIs and separate domains — genuinely
# independent controllers, not one controller split, which is why tb-fleet.nix
# rebinds both PCI functions. PM QoS is a CPU-level property and therefore
# helps all three rails at once; the MTU knob below is per-interface.
#
# Rail 2 is deliberately left unaddressed HERE. Giving it a /30 is a topology
# change to a link Tom has ruled "MUST always work" (tb-fleet.nix), it needs a
# matching profile on the worker, and nothing measured yet says a second rail
# helps: a TP=2 decode all-reduce is a ~5 KB payload, i.e. latency-bound, not
# bandwidth-bound. When that changes, it belongs in tb-fleet.nix beside the
# rail it extends, not in the module that tunes rails.
let
  cfg = config.myLowLatCluster;

  # A single 4-byte little-endian 0 written to the PM QoS device, then the fd
  # held open forever. `exec sleep infinity` replaces the shell but keeps fd 3.
  pmqosHold = pkgs.writeShellScript "pmqos-hold" ''
    exec 3> /dev/cpu_dma_latency
    printf '\0\0\0\0' >&3
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  mtuScript = pkgs.writeShellScript "fleet-mtu" ''
    PATH=${lib.makeBinPath [ pkgs.iproute2 ]}
    # Idempotent, and silent about rails that are down: Thunderbolt interfaces
    # come and go with the link, so this runs on a timer rather than once.
    ${lib.concatMapStringsSep "\n" (i: ''
      if [ -e /sys/class/net/${i.name} ]; then
        ip link set dev ${i.name} mtu ${toString i.mtu} 2>/dev/null || true
      fi
    '') cfg.jumboInterfaces}
  '';
in
{
  options.myLowLatCluster = {
    enable = lib.mkEnableOption "PM QoS + MTU tuning for the coordinator↔worker fleet rails";

    peer = lib.mkOption {
      type = lib.types.str;
      description = "The peer's fast-rail /30 address, watched by the latency tripwire.";
    };

    latencyBudgetMicros = lib.mkOption {
      type = lib.types.int;
      default = 200;
      description = ''
        Average RTT over the fast rail, in microseconds, above which the
        tripwire fires. 200 sits well above the measured 58-90 us held figure
        and well below the 577 us unheld one, so it distinguishes "PM QoS
        stopped being held somewhere" from ordinary jitter.
      '';
    };

    jumbo = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Raise MTU on the fleet rails. DEFAULT OFF, DELIBERATELY.

        MTU is a both-ends contract: a box that switches while its twin has
        not will blackhole every large frame on that rail, and the fast rail
        is the one Tom ruled MUST always work. Turning this on is therefore a
        TWO-STEP deploy — switch both boxes, then verify with
        `ping -M do -s 60000 <peer>` from each end — not a flag flip.

        The measured RTT win in this module comes entirely from PM QoS. Jumbo
        frames buy throughput, which nothing has yet shown to be the limiter.
      '';
    };

    jumboInterfaces = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            mtu = lib.mkOption { type = lib.types.int; };
          };
        }
      );
      default = [
        # thunderbolt-net tops out at 65520. The 5GbE path is a normal NIC and
        # takes the conventional 9000 — NOT 65520, which it will silently
        # refuse, leaving the rail at 1500 and the operator none the wiser.
        {
          name = "thunderbolt0";
          mtu = 65520;
        }
        {
          name = "thunderbolt1";
          mtu = 65520;
        }
        {
          name = "enp191s0";
          mtu = 9000;
        }
      ];
      description = "Fleet rails and their target MTU, applied only when `jumbo` is on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Layer 1: the PM QoS hold, the whole measured win ─────────────────────
    systemd.services.lowlat-cluster = {
      description = "PM QoS cpu_dma_latency=0 for low-latency fleet rails";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      serviceConfig = {
        ExecStart = pmqosHold;
        Restart = "always";
        RestartSec = "5s";
        # The fd IS the constraint: if this process dies, C3 returns. Restart
        # unconditionally and let the tripwire catch a crash-loop.
      };
    };

    # ── Layer 2: MTU, opt-in, on a timer because TB rails re-train ───────────
    systemd.services.fleet-mtu = lib.mkIf cfg.jumbo {
      description = "Raise MTU on the coordinator↔worker fleet rails";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = mtuScript;
      };
    };
    systemd.timers.fleet-mtu = lib.mkIf cfg.jumbo {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "2min";
        AccuracySec = "30s";
      };
    };

    # ── Layer 3: make a silent regression loud ───────────────────────────────
    #
    # The failure this watches for is specifically NOT darkness — tb-fleet.nix
    # already owns that. It is the rail being UP and SLOW, which is exactly
    # what happened before this module existed and is invisible to a ping/fail
    # check. A transient unit reverting on reboot, a failed switch on one twin,
    # or someone stopping the service reproduces the 577 us world silently.
    myTripwire.fleet-latency = {
      description = "the fast rail's average RTT stays inside the PM QoS budget";
      intervalSeconds = 900;
      onBootSec = "10min";
      threshold = cfg.latencyBudgetMicros;
      comparison = "ge";
      sustainSeconds = 3600;
      rearm = 0;
      refractorySeconds = 43200;
      valueField = "RTT_US";
      sensorPath = [
        pkgs.iputils
        pkgs.gawk
        pkgs.coreutils
      ];
      # Report average RTT in microseconds. A dark rail reports 0, not a huge
      # number: darkness is tb-fleet-reachability's job and double-firing on
      # one cable would only bury the signal that matters here.
      sensor = ''
        out=$(ping -q -i 0.01 -c 50 -W 2 ${cfg.peer} 2>/dev/null | tail -1)
        if [ -z "$out" ]; then
          echo "0 rtt 1"
        else
          echo "$out" | awk -F'[/ ]' '{ printf "%d rtt 1\n", $8 * 1000 }'
        fi
      '';
      onFirePath = [ pkgs.coreutils ];
      onFire = ''
        mkdir -p /var/lib/failure-markers
        printf '%s — the fast rail is UP but SLOW: avg RTT over ${cfg.peer} has exceeded ${toString cfg.latencyBudgetMicros} us for ~1 h (episode %s)\n  This is the 2026-08-28 C3 regression (dotfiles#238), not a dead link. Check BOTH boxes: systemctl is-active lowlat-cluster, then sudo od -An -td4 /dev/cpu_dma_latency (must read 0 on each). PM QoS held on only one end measures ~468 us and looks like the knob did nothing (see modules/lowlat-cluster.nix)\n' \
          "$(date '+%Y-%m-%d %H:%M')" "$4" \
          > /var/lib/failure-markers/fleet-latency
      '';
    };
  };
}
