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
# on BOTH ends, 63-90 us — 8.5x. Re-measured 2026-08-28 19:xx with the
# transient unit live: tb0 33/58/122 us mdev 18, eth 58/72/142 us mdev 9,
# 200 samples each.
#
# #238's "at no power cost" reading (76.22 W vs 74.14 W) did NOT survive
# review: both figures were sampled while the ping benchmark was running, so
# they compare load-power to load-power and never touched the idle floor,
# which is where the entire cost lived. See #257 and the pmqosHold comment.
#
# CAUSE, found in /sys/devices/system/cpu/cpu*/cpuidle/state*/latency on both
# twins: POLL 0us | C1 1us | C2 18us | C3 350us. Every inter-node packet was
# paying a C3 exit. Holding /dev/cpu_dma_latency below 350 blocks that exit;
# the budget is an OPTION (pmqosLatencyUs, default 100) because the value
# chooses which states survive, and the original 0 left only POLL.
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
# only `coordinator` and `worker` import. The gate was written while the fleet
# still had a laptop (zenbook-duo, retired 2026-08-30) and stays as written: it
# is the shape that keeps this safe to import from anywhere.
#
# ─── The rails this fleet actually has (STRUCTURAL since #266) ─────────────
#
# This table used to be a per-boot SNAPSHOT with a warning attached, because
# thunderbolt0/1 were PROBE-ORDER names rather than cables: the worker's own
# kernel named the same device — svc 1-2.0 — thunderbolt0 at 17:41 and
# thunderbolt1 at 18:42 on 2026-08-30, and the 2026-08-31 12:27 reboot
# flipped both twins at once. Since #266 the names are pinned to the NHIs by
# modules/fleet-rail-names.nix, so the table below is a FACT rather than a
# snapshot, and `rail0` means one specific cable on both twins forever.
#
# (The 2026-08-28 version of this table — "thunderbolt0 c4:00.5 -> domain0" —
# was the WORKER's snapshot presented as fleet fact, wrong for the
# coordinator on both the PCI function (c5 there) and the domain (#267).
# That class of error is what keying the table by hostName now prevents.)
#
#   rail0     coord c5:00.6/domain1 <-> worker c4:00.5/domain0   cable A
#                                      10.99.0.x/30   tb-fleet, the fast rail
#   rail2     coord c5:00.5/domain0 <-> worker c4:00.6/domain1   cable B
#                                      10.99.2.x/30   tb-fleet2, rail 2 (#274)
#   enp191s0  5GbE, probe-stable name  10.99.1.x/30   eth-fleet, the fallback
#
# Cable A reaches domain1 on the coordinator and domain0 on the worker: the
# two cabling crossings cancel. That asymmetry is real, triple-verified
# (#275), and the reason the pin table is per-host.
#
# Two USB4 host routers on SEPARATE NHIs and separate domains — genuinely
# independent controllers, not one controller split, which is why tb-link-heal
# rebinds both PCI functions (derived at runtime per node since #267). PM QoS
# is a CPU-level property and therefore helps all three rails at once; the
# MTU knob below is per-interface.
#
# ─── The link ceiling: 40 Gb/s per direction; no cable changes it (#267) ────
#
# Recorded so nobody re-runs this investigation. Read 2026-08-30 from
# /sys/kernel/debug/thunderbolt/{0-0,1-0}/port2/regs, capability 0x01, on
# ALL FOUR host lane adapters across both nodes — byte-identical every time:
#
#   LANE_ADP_CS_0 = 0x003c01c0   supported speeds Gen3+Gen4, widths x1+x2
#   LANE_ADP_CS_1 = 0x4824003c   TARGET speed 0xC (the CM is ALREADY asking
#                                for Gen3/4, dual), CURRENT speed Gen3
#                                (20 Gb/s per lane), CURRENT width DUAL
#
# Bonded x2 = 40 Gb/s per direction — the USB4 v1 / TB3 / TB4 number, and
# how Framework specs these ports. The hardware is asked for Gen4 and
# answers Gen3. The controlled experiment has already run by accident: one
# TB5 cable and one TB3 cable between the same two boxes train IDENTICALLY
# at Gen3 — the host is the limiter, not the medium. NO CABLE PURCHASE
# CHANGES THIS NUMBER. Two adjacent traps:
#   - sysfs `generation=4` is tb_switch.generation, i.e. "this is a USB4
#     router" — it is 4 for every USB4 router and never 5. It says nothing
#     about USB4 v1 vs v2 and must not be read as a link speed.
#   - retimers ARE enumerated on both ports of both boards (vendor 0x1da0
#     AMD, device 0x8833), but the scan is RACY: the worker enumerated all
#     four at [3653.4–3653.9], then a rescan 20 s later dropped 0-0:2.2 and
#     never re-found it. tb-fleet's "no retimers at all" PD-blind test stays
#     sound — it only needs ANY retimer present — but COUNTING retimers is
#     not a diagnostic.
#
# Rail 2 was deliberately left unaddressed here until 2026-08-31 (#274). The
# original reasoning was correct when written: a /30 is a topology change to
# a link Tom ruled "MUST always work" (tb-fleet.nix), it needs a matching
# worker profile, and nothing measured said a second rail helps — a TP=2
# decode all-reduce is a ~5 KB payload, latency-bound, not bandwidth-bound.
# Three things changed (#274):
#   1. ADDRESSED-BUT-PEERLESS IS THE ONE STATE THAT HANGS SILENTLY. Measured
#      on torch 2.13.0: a GLOO_SOCKET_IFNAME entry that does not resolve
#      fails loudly, naming the interface; thunderbolt1 on self-assigned
#      169.254.x RESOLVES, connects to nothing, and hangs forever with no
#      log line. A /30 on both ends removes that state permanently.
#   2. usb4-stream's carrier gate was designed against the IP rail's
#      bring-up sequence; an unaddressed cable B follows a different one,
#      which is part of how the 2026-08-30 DMA-ring leak happened (#275).
#   3. cable B has consumers now: the TB-IP-on-A-vs-A+B aggregation
#      experiment and the USB4STREAM bench are deliberately staged onto it.
# The /30s live beside the rail they extend — hosts/coordinator/tb-fleet.nix
# and hosts/worker/default.nix (profile tb-fleet2) — not in the module that
# tunes rails, exactly as the pre-#274 version of this comment prescribed.
# The hazards (both ends together; the worker controller's first-use DMA
# failure history) are documented at the profiles.
let
  cfg = config.myLowLatCluster;

  # A single 4-byte little-endian budget written to the PM QoS device, then the
  # fd held open forever. `exec sleep infinity` replaces the shell but keeps
  # fd 3 — the fd IS the constraint; closing it releases the budget.
  #
  # THE VALUE MATTERS AND 0 WAS THE WRONG ONE (#257). cpuidle admits exactly
  # the states whose exit latency is <= the budget. On Strix Halo:
  #
  #   POLL  0 us     C1  1 us     C2  18 us     C3  350 us
  #
  # so a budget of 0 admits POLL ALONE — a busy-wait spin at whatever the
  # governor holds, which here is EPP=performance at full boost. This module's
  # header used to claim 0 "floors the cores at C2"; it did not, and the cost
  # was measured on 2026-08-31 at 70.16 W package power with the box idle,
  # POLL holding 97.5% of wall clock against 0.4 s in C1 and 0.8 s in C2. That
  # is invisible to load, %CPU, top and htop, because POLL is accounted as
  # idle — only the fans give it away.
  #
  # MEASURED 2026-08-31, held on BOTH twins, 200-sample ping over rail 0, idle
  # package power from amdgpu power1_average with the bench stopped. This is
  # the measurement #257 asked for before picking a number:
  #
  #   budget  admits          RTT avg    coord idle   worker idle
  #   0       POLL            0.054 ms   70 W         70 W
  #   1       POLL+C1         0.104 ms   18 W          7 W
  #   100     POLL+C1+C2      0.116 ms   10 W          6 W
  #   (none)  +C3             0.829 ms   17 W          6 W
  #
  # Two readings that matter. First, essentially the whole 8.5x RTT win is the
  # C3 BLOCK, not the POLL floor: 0.116 ms against 0.829 ms unconstrained is
  # still ~7x, while the extra step from 0.116 to 0.054 costs 60 W to buy 62
  # us. Second, on an APU that 60 W is not merely waste — package power is
  # SHARED with the GPU, so idle cores spinning at full boost are taking
  # budget directly from the thing this fleet exists to run.
  #
  # 100 is chosen over 1 for the last 8 W; the two differ by 12 us, which is
  # inside the tripwire's margin either way (budget 200 us). If a future
  # tensor-path measurement shows those 12 us matter, set pmqosLatencyUs = 1
  # and keep almost all of the power win.
  pmqosHold = pkgs.writeShellScript "pmqos-hold" ''
    exec 3> /dev/cpu_dma_latency
    # 4-byte little-endian, built from the option rather than hand-escaped, so
    # changing the number cannot silently write the wrong bytes.
    v=${toString cfg.pmqosLatencyUs}
    printf "$(printf '\\%03o' \
      $((v & 255)) $(((v >> 8) & 255)) $(((v >> 16) & 255)) $(((v >> 24) & 255)))" >&3
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

    pmqosLatencyUs = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 100;
      description = ''
        CPU DMA latency budget in microseconds, held open on
        /dev/cpu_dma_latency for as long as the unit runs. cpuidle admits
        exactly the idle states whose exit latency is <= this number.

        On these boxes: POLL 0, C1 1, C2 18, C3 350 us. The default 100
        therefore admits POLL/C1/C2 and blocks C3, which is the whole point —
        C3's 350 us exit is what the remote wakeup was paying for.

        Do NOT set this to 0. That admits POLL alone, i.e. a full-boost
        busy-wait with no idling at all: measured 70.16 W package power on an
        idle coordinator with POLL at 97.5% of wall clock (#257). Any value in
        19..349 keeps the C3 block; 100 leaves margin on both sides.
      '';
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
          name = "rail0";
          mtu = 65520;
        }
        {
          name = "rail2";
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
    # ── TCP admission on the tensor rail (2026-08-30, cp-tp2 latent killer) ──
    # fn-env.sh computes NCCL_SOCKET_IFNAME from the rails that carry a
    # routable /30 — which names thunderbolt0 — but until this stanza the
    # rail's firewall admitted ONLY UDP 4791 (fn-rdma's RoCE door): every
    # NCCL/Ray TCP connect over the rail would have hung at cp-tp2's first
    # real bootstrap. Verified empirically (TCP connect over the rail-0 netdev
    # timed out; the same test over the trusted 5GbE worked). Interface-scoped
    # high-port range on a point-to-point /30 — the house per-interface idiom,
    # NOT trustedInterfaces. NCCL and Ray both use dynamic high ports.
    #
    # Since #266 this door names a CABLE, not a probe order: rail0 is pinned
    # to cable A's NHI by modules/fleet-rail-names.nix. Before that rename the
    # door and the /30 both chased `thunderbolt0` and so moved cables
    # together — right by coincidence, and only while both twins flipped in
    # the same direction.
    networking.firewall.interfaces.rail0.allowedTCPPortRanges = [
      {
        from = 1024;
        to = 65535;
      }
    ];
    # Rail 2's twin door (#274, 2026-08-31): the moment rail2 carries a real
    # /30 it inherits the same admission problem — an addressed rail whose TCP
    # connects silently time out is exactly the hang class #274 exists to
    # remove, and the second-socket-rail experiment (#274 reason 3) is a TCP
    # consumer. Same interface-scoped idiom, same point-to-point /30 exposure:
    # only the twin is on the far end. UDP 4791 stays rail-0-only — fn-rdma
    # owns that door and RoCE rides the IP rail.
    networking.firewall.interfaces.rail2.allowedTCPPortRanges = [
      {
        from = 1024;
        to = 65535;
      }
    ];

    # ── Layer 1: the PM QoS hold, the whole measured win ─────────────────────
    systemd.services.lowlat-cluster = {
      description = "PM QoS cpu_dma_latency hold for low-latency fleet rails";
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
        printf '%s — the fast rail is UP but SLOW: avg RTT over ${cfg.peer} has exceeded ${toString cfg.latencyBudgetMicros} us for ~1 h (episode %s)\n  This is the 2026-08-28 C3 regression (dotfiles#238), not a dead link. Check BOTH boxes: systemctl is-active lowlat-cluster, then sudo od -An -td4 /dev/cpu_dma_latency (must read ${toString cfg.pmqosLatencyUs} on each). PM QoS held on only one end measures ~468 us and looks like the knob did nothing (see modules/lowlat-cluster.nix)\n' \
          "$(date '+%Y-%m-%d %H:%M')" "$4" \
          > /var/lib/failure-markers/fleet-latency
      '';
    };
  };
}
