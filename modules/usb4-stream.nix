{
  config,
  lib,
  pkgs,
  ...
}:
# ─── myUsb4Stream: declarative USB4STREAM provisioning (twins) ───────────────
#
# Linux 7.2's in-tree `thunderbolt_stream` (Westerberg/Borzeszkowski, the
# thunderbolt maintainer shipping the primitive upstream) exposes host-to-host
# DMA ring pipes over a USB4 cable: configfs control plane at
# /sys/kernel/config/thunderbolt/stream/<svc>/<name>, data plane at
# /dev/tbstreamN. NO IP STACK — no netdev, no skb, no firewall interaction;
# reliable, ordered, framed (4KB frames), hardware E2E flow control, blocking
# read/write + poll. ABI: Documentation/ABI/testing/configfs-thunderbolt_stream.
#
# Measured on the twins 2026-08-30 (dotfiles#244 trail, stock 7.2.0 cores,
# cable A, python/dd through the raw device — no tuning of the consumer):
#   RTT   64B  p50 14.3µs  (TCP over the 5GbE: 60.4µs)
#   RTT  4KB  p50 21.8µs p99 25.3µs  (TCP 5GbE: 137.8µs p50)
#   throughput, single stream, ring 4096/throttle 2048: ~841 MB/s
# The 5GbE figures were independently corroborated 2026-08-31 by a second
# harness: 56.6µs p50 at 64B / 138.33µs at 4KiB against the 60.4/137.8
# above — two harnesses, two days, close agreement.
#
# TCP over thunderbolt0 ITSELF, measured 2026-08-31 (#278; cable A, 20 000
# iterations × 2 rounds, interface pinning proven by per-netdev counter
# deltas on both nodes) — the baseline the block above lacked:
#   p50 RTT:  64B 130.42 | 4KiB 130.42 | 8KiB 130.44 | 16KiB 130.44
#             | 64KiB 329.43 µs
#   p99 RTT:  64B 191.45 | 4KiB 274.75 | 8KiB 345.37 | 16KiB 225.86
#             | 64KiB 411.25 µs
#   minimum at 64B: 34.41µs;  throughput TX/RX: 8.81/9.20 Gb/s
# p50 flat to 0.03µs across an eight-fold size range against a 34µs floor:
# that is not fabric cost, it is thunderbolt_net's wakeup/coalescing path —
# roughly 100µs of pure software overhead on a fast link. Whether it is
# recoverable by tuning the interrupt/coalescing path is UNTESTED; flagged
# as the obvious cheap experiment, not a claim.
# The SAME-CABLE comparison is the meaningful one: 14.3µs vs 130.42µs at
# 64B makes the stream primitive a ~9x win on its own cable, not the ~4x
# the cross-cable 5GbE figures imply.
# Caveat on the ~841 MB/s: it was taken at ring 4096, while ring 1024 /
# throttling 2048 is what is actually in force on all four fn groups on
# both nodes (read 2026-08-31) — do not expect that number to reproduce
# as-is at the provisioned defaults.
#
# What this module owns — the CONFIGURATION half the kernel pin alone doesn't
# give (module loading lives in tb-fleet.nix / worker default.nix for stock
# boots and modules/fn-rdma.nix for patched boots):
#   1. udev: /dev/tbstream* opens for the operator group, not just root.
#   2. A provisioning oneshot that resolves the stream service on the rail-0
#      CABLE and creates N named stream groups. Service names are per-host
#      and per-domain and the two cables CROSS between the twins (cable A =
#      coordinator domain1 ↔ worker domain0, 2026-08-31); never hardcode
#      "0-2.1". The 2026-08-28 version of this comment called the netdev name
#      "the only stable anchor" — DISPROVEN 2026-08-30 (#275): on the
#      coordinator, "the cable thunderbolt0 rides" resolved to cable B at
#      18:42:54 and cable A at 23:22:48 of the SAME boot; the worker did the
#      same (17:41:49 cable B, 18:42:56 cable A) with correct-for-itself heal
#      hardcodes, so this was never a coordinator-only #267 artifact. The
#      name is kept as the ENTRY POINT only; the resolved physical identity
#      (NHI function + peer router unique_id) is gated against a per-host pin
#      (railNhi) and a recorded identity file (/var/lib/usb4-stream/
#      rail-identity), and the provisioner REFUSES — loudly, unit failed —
#      when they disagree, rather than provisioning whatever cable the name
#      points at today.
#   3. Stream names are the cross-host rendezvous: both twins create fn0..fnN
#      and the driver pairs them by name over XDomain properties. HopIDs are
#      NOT auto-allocated anymore: fnN is pinned at hopid 10+N on both sides
#      (see HAZARDS — hop 8 belongs to thunderbolt_net). The driver makes the
#      pin exact: writing a specific hopid either allocates precisely that
#      value or fails EBUSY (stream.c tbstream_dev_alloc_in_hopid), so a
#      collision cannot happen silently.
#   4. A release path (#275): groups this module no longer owns — a stale
#      service directory from a drifted name, or fnN beyond the configured
#      count — are rmdir'd once the identity gates pass. Orphaned groups are
#      load-bearing misinformation: they made cable B look deliberately
#      provisioned to every human and script that read configfs on
#      2026-08-31. configfs does not survive reboot, so this path matters for
#      drift DURING uptime (the udev re-fire provisioned two different cables
#      inside one coordinator boot), not for post-reboot cleanup. Groups a
#      consumer holds open are never touched — refusal, not force. Touch
#      /var/lib/usb4-stream/keep-foreign to suppress the sweep for deliberate
#      out-of-module provisioning (e.g. a cable-B bench pass).
#
# EXPECTED ABSENCE (#272, #275): after this fix, cable B carries NO stream
# groups from this module — exactly one service directory (the rail-0
# cable's) in /sys/kernel/config/thunderbolt/stream/ is the fix WORKING. A
# human checking configfs must not read the second cable's absence as a
# provisioning failure; a benchmark on cable B needs its own deliberate,
# explicit provisioning.
#
# HAZARDS, all observed live 2026-08-30 — read before "improving" this:
#   - Ring memory is a shared budget: two streams at ring_size 4096 ENOMEM'd
#     on concurrent open. 1024 is the proven multi-stream size.
#   - Open/close cycling against a half-configured or mismatched peer WEDGES
#     the router hop tables — config-space reads start timing out, and the
#     damage spreads to thunderbolt_net's paths (the IP rail went dark).
#     Recovery required rebooting the wedged end. Consumers must treat a
#     stream open as long-lived pair state, not a retry loop; provisioning
#     here deliberately only CREATES config and never opens the devices.
#     (Releasing an UNOPENED group is the safe direction: rmdir releases its
#     hopids and index without ever touching the data path.)
#   - Rail 1 (the second cable) is parked with no IP and its worker-side
#     controller failed DMA activation on first-ever use; streams provision
#     on the rail-0 cable only until that link earns trust. Since #274
#     (2026-08-31) that cable carries 10.99.2.x/30 as tb-fleet2 — addressed,
#     but still NOT stream-provisioned here; see EXPECTED ABSENCE above.
#   - THE NAME-DRIFT HAZARD (#275): provisioning on the wrong cable is not
#     harmless config noise. On 2026-08-30 the coordinator provisioned cable
#     B thirteen seconds after boot, inside the tbnet claim window; the
#     worker's tbnet then failed to allocate its Rx HopID (cable-B fn0 held
#     hopid 8), and at 18:48:16 both twins' cable-B NHIs warned from
#     tbnet_tear_down (nhi.c:760, RX ring 1 AND TX ring 1 "already stopped")
#     — a leaked DMA ring on each side. The budget is 3 DMA rings per NHI
#     (flashnext DECISIONS-2026-08-30.md §3.1), so one leaked ring means
#     EVERY subsequent stream open on that cable returns ENOMEM, which is
#     what blocked the USB4STREAM bench until the next reboot. The identity
#     gates above exist to make this class impossible, not just observable.
#   - HopIDs are a SHARED, RACEABLE budget with thunderbolt_net, and the netdev
#     existing does not mean it has claimed its own yet — it claims in
#     tbnet_open, not at probe. Provisioning inside that window starves the IP
#     rail (#262). The provisioner therefore gates on CARRIER, not on the
#     netdev's presence. Do not relax that back to a -e test. Two additions
#     2026-08-31: (a) #274 gave cable B its /30 (tb-fleet2), so BOTH cables
#     now run the addressed bring-up sequence this gate was designed against
#     — the gate is no longer correct-for-one-cable-only; (b) the hopid half
#     of the race is now closed structurally: thunderbolt_net holds
#     in_hop_id 8 on every host router in this fleet (0x801c0801 on every
#     port2, all four routers, both twins, read 2026-08-31), and this module
#     pins stream hopids at 10+N — hop 8 can never be taken by a stream even
#     if provisioning does land inside the window, and hop 9 is left free as
#     headroom. Cable B's pre-fix fn0 sat at in/out 8 (#276) precisely
#     because it was provisioned before tbnet claimed; the pin replaces that
#     ordering luck with a driver-enforced guarantee.
let
  cfg = config.myUsb4Stream;

  provisionScript = pkgs.writeShellScript "usb4-stream-provision" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.psmisc
      ]
    }
    say() { echo "usb4-stream: $*"; }
    fail=0

    rail=${cfg.rail}
    identity=/var/lib/usb4-stream/rail-identity
    for _ in $(seq 60); do
      [ -e "/sys/class/net/$rail/device" ] && break
      sleep 1
    done
    if [ ! -e "/sys/class/net/$rail/device" ]; then
      say "rail $rail never appeared; provisioning nothing (streams need the XDomain link)"
      exit 0
    fi

    # The netdev EXISTING is not enough to provision safely. thunderbolt_net
    # allocates its Rx HopID in tbnet_open — when the link is brought UP — not
    # at probe, so there is a window where $rail is present but has claimed
    # nothing yet. Allocating stream HopIDs inside that window takes the ones
    # the net rail is about to ask for, and the rail comes up dark with
    # "failed to allocate Rx HopID" (#262, observed 2026-08-30: the peer booted
    # ~2 min after this host, the udev re-fire landed exactly in the window,
    # and rail 0 lost its IP while rail 1 — which this unit never provisions —
    # was unaffected). Carrier is the observable for "tbnet_open already won".
    # Since #274 both cables are addressed (tb-fleet / tb-fleet2), so this
    # sequence now holds for whichever cable the name points at; the
    # WRONG-cable case is handled by the identity gates below, and the hopid
    # stakes of losing this race are removed by the 10+N pin (see HAZARDS).
    for _ in $(seq 120); do
      [ "$(cat "/sys/class/net/$rail/carrier" 2>/dev/null || echo 0)" = 1 ] && break
      sleep 1
    done
    if [ "$(cat "/sys/class/net/$rail/carrier" 2>/dev/null || echo 0)" != 1 ]; then
      # Skip rather than race. The IP rail outranks the streams (tb-fleet.nix:
      # "the coordinator-worker thunderbolt link MUST always be working"), and
      # this is self-healing: the recovery for a dark rail is tb-link-heal's
      # NHI rebind, which tears down and re-creates the XDomain devices and so
      # re-fires this unit through the same udev rule that started it.
      say "rail $rail has no carrier after 120s; NOT provisioning — streams must never outrank the IP rail (#262)"
      exit 0
    fi

    # ── Resolve the PHYSICAL cable the name currently rides (#275) ──────────
    # The name is probe-order (#266); the NHI PCI function and the peer host
    # router's unique_id are the physical facts. Both are read from the same
    # sysfs walk the svc resolution below uses, so they describe the cable
    # that WOULD be provisioned, not the one we hope for.
    devpath=$(readlink -f "/sys/class/net/$rail/device")
    netsvc=$(basename "$devpath")
    xd=''${netsvc%.*}
    nhi=''${devpath%%/domain*}
    nhi=''${nhi##*/}
    peer=$(cat "/sys/bus/thunderbolt/devices/$xd/unique_id" 2>/dev/null || echo unknown)
    if [ "$peer" = unknown ]; then
      say "REFUSING to provision: cannot read /sys/bus/thunderbolt/devices/$xd/unique_id — the cable identity is unresolvable, and identity is the gate (#275)"
      exit 1
    fi

    # Gate 1 — the per-host pin. Fail CLOSED: a wrong or missing pin refuses
    # and paints the unit red; it can never provision the wrong cable.
    intended="${lib.optionalString (cfg.railNhi != null) cfg.railNhi}"
    if [ -n "$intended" ] && [ "$nhi" != "$intended" ]; then
      say "REFUSING to provision: $rail rides NHI $nhi (xdomain $xd, peer $peer) but the rail-0 cable enters this host at $intended — the name has drifted to the other cable (#275, observed live 2026-08-30). Diagnose: readlink -f /sys/class/net/$rail; tb-link-heal's NHI rebind re-rolls the name assignment."
      exit 1
    fi
    if [ -z "$intended" ]; then
      say "WARNING: no railNhi pin for this host; the identity file is the only drift guard, and a FIRST run will trust whatever cable $rail names right now. Set myUsb4Stream.railNhi."
    fi

    # Gate 2 — the recorded identity (#275 fix 1+2). The module now has a
    # memory of what it created; drift is a refusal, not a re-provision.
    if [ -f "$identity" ]; then
      rec_nhi=$(grep -m1 '^nhi=' "$identity" | cut -d= -f2)
      rec_peer=$(grep -m1 '^peer_uid=' "$identity" | cut -d= -f2)
      if [ "$nhi" != "$rec_nhi" ] || [ "$peer" != "$rec_peer" ]; then
        say "REFUSING to provision: resolved cable identity (nhi=$nhi peer_uid=$peer) differs from the recorded one (nhi=$rec_nhi peer_uid=$rec_peer) in $identity — the name drifted (#275) or the cabling changed. If the change is DELIBERATE: rm $identity and re-trigger this unit to re-anchor."
        exit 1
      fi
    fi

    svc=""
    for _ in $(seq 60); do
      for d in /sys/bus/thunderbolt/devices/"$xd".*; do
        [ -f "$d/key" ] || continue
        if [ "$(cat "$d/key")" = stream ]; then
          svc=$(basename "$d")
          break 2
        fi
      done
      sleep 1
    done
    if [ -z "$svc" ]; then
      say "no stream service under $xd after 60s (peer not advertising kstream?); provisioning nothing"
      exit 0
    fi

    # ── Release groups this module no longer owns (#275 fix 3) ──────────────
    # Runs only after both identity gates passed, so "stale" is well-defined:
    # any fnN group under a service that is not the rail's, or beyond the
    # configured count. Never forces: a group a consumer holds open is
    # long-lived pair state (HAZARDS) and gets a refusal line instead.
    if [ -e /var/lib/usb4-stream/keep-foreign ]; then
      say "keep-foreign marker present; skipping the stale-group sweep (deliberate out-of-module provisioning in progress)"
    else
      for d in /sys/kernel/config/thunderbolt/stream/*/fn[0-9]*; do
        [ -d "$d" ] || continue
        g=$(basename "$(dirname "$d")")
        f=$(basename "$d")
        if [ "$g" = "$svc" ] && [ "''${f#fn}" -lt ${toString cfg.streams} ] 2>/dev/null; then
          continue
        fi
        idx=$(cat "$d/index" 2>/dev/null || echo "")
        if [ -n "$idx" ] && fuser -s "/dev/tbstream$idx" 2>/dev/null; then
          say "NOT releasing stale group $g/$f (/dev/tbstream$idx): a consumer holds it open — close it and re-trigger this unit"
          fail=1
          continue
        fi
        if rmdir "$d"; then
          say "released stale group $g/$f (was /dev/tbstream''${idx:-?}) — not on the rail-0 cable or beyond the configured count (#275)"
        else
          say "FAILED to release stale group $g/$f — do not trust configfs until this is understood"
          fail=1
        fi
      done
      for d in /sys/kernel/config/thunderbolt/stream/*/; do
        [ -d "$d" ] || continue
        g=$(basename "$d")
        [ "$g" = "$svc" ] && continue
        if rmdir "$d" 2>/dev/null; then
          say "released stale service group $g (#275)"
        else
          say "leaving service group $g: it still has member groups this module does not own (fine if deliberate; see keep-foreign)"
        fi
      done
    fi

    base="/sys/kernel/config/thunderbolt/stream/$svc"
    mkdir -p "$base"
    for i in $(seq 0 $((${toString cfg.streams} - 1))); do
      g="$base/fn$i"
      want=$((10 + i))
      mkdir -p "$g"
      # EBUSY while a consumer holds the stream open — leave live values be.
      echo ${toString cfg.ringSize} > "$g/ring_size" 2>/dev/null \
        || say "fn$i: ring_size stays $(cat "$g/ring_size") — write refused (EBUSY while open is expected; live values are deliberately left be)"
      echo ${toString cfg.throttlingNs} > "$g/throttling" 2>/dev/null \
        || say "fn$i: throttling stays $(cat "$g/throttling") — write refused (same rule)"
      # HopID pin (#276): fnN gets exactly 10+N on both sides, never -1
      # auto-allocation — hop 8 is thunderbolt_net's on every router in this
      # fleet and 9 is left as headroom. The driver guarantees exactness:
      # a specific value is either granted verbatim or refused EBUSY. Values
      # already equal to the pin (ours from an earlier run, or inherited from
      # a peer running the same pin) are left alone; DIFFERENT nonzero values
      # mean an interlocked pre-pin pair and are never rewritten one-sided —
      # that is the mismatched-peer wedge in HAZARDS.
      for side in in out; do
        cur=$(cat "$g/''${side}_hopid")
        if [ "$cur" = 0 ]; then
          if ! echo "$want" > "$g/''${side}_hopid" 2>/dev/null; then
            say "REFUSED: fn$i ''${side}_hopid=$want not granted (EBUSY) — something else holds hopid $want on $xd; NOT falling back to auto-allocation, the pin IS the #276 guarantee"
            fail=1
          fi
        elif [ "$cur" = "$want" ]; then
          :
        else
          say "WARNING: fn$i ''${side}_hopid=$cur, not the pinned $want — inherited from a peer on pre-pin config? NOT rewriting an interlocked pair one-sided. If $cur is 8 this stream MUST NOT be opened: thunderbolt_net holds hop 8 on every router in this fleet (#276)."
          fail=1
        fi
      done
      say "fn$i ready: /dev/tbstream$(cat "$g/index") in_hopid=$(cat "$g/in_hopid") out_hopid=$(cat "$g/out_hopid") ring=$(cat "$g/ring_size") throttle=$(cat "$g/throttling")ns"
    done

    # ── Record the identity (#275 fix 1) ─────────────────────────────────────
    # Written only on a fully clean pass, so the record always describes a
    # state worth defending. xdomain/svc are diagnostics only — domain
    # numbers are probe-order like the names; nhi + peer_uid are the
    # comparison keys.
    if [ "$fail" = 0 ]; then
      first=""
      [ -f "$identity" ] || first=yes
      {
        echo "# usb4-stream-provision: identity of the one cable this module provisions (#275)"
        echo "# comparison keys: nhi, peer_uid. rm this file only to re-anchor DELIBERATELY."
        echo "recorded=$(date -Is)"
        echo "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
        echo "nhi=$nhi"
        echo "peer_uid=$peer"
        echo "xdomain=$xd"
        echo "svc=$svc"
        for i in $(seq 0 $((${toString cfg.streams} - 1))); do
          echo "fn''${i}_hopids=$(cat "$base/fn$i/in_hopid")/$(cat "$base/fn$i/out_hopid")"
        done
      } > "$identity.tmp" && mv "$identity.tmp" "$identity"
      if [ -n "$first" ]; then
        say "RECORDED rail identity for the first time: nhi=$nhi peer_uid=$peer (xdomain $xd, svc $svc). VERIFY this is the intended rail-0 cable — cable A, the one carrying 10.99.0.x on both twins; if not, rm $identity and re-trigger after healing the rail."
      fi
    else
      say "finished with refusals; identity NOT (re)recorded"
      exit 1
    fi
  '';
in
{
  options.myUsb4Stream = {
    enable = lib.mkEnableOption "declarative USB4STREAM stream provisioning on the twins";

    rail = lib.mkOption {
      type = lib.types.str;
      default = "thunderbolt0";
      description = ''
        Netdev whose cable carries the streams; the stream service is resolved
        as its XDomain sibling. The name is the ENTRY POINT, not the anchor —
        it is probe-order (#266/#275) and the resolved physical identity is
        gated against railNhi and the recorded identity file before anything
        is provisioned.
      '';
    };

    railNhi = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        {
          coordinator = "0000:c5:00.6";
          worker = "0000:c4:00.5";
        }
        .${config.networking.hostName} or null;
      defaultText = lib.literalMD ''
        per-host table — coordinator `"0000:c5:00.6"`, worker `"0000:c4:00.5"`
        (cable A's NHIs, verified by unique_id reciprocity 2026-08-31); `null`
        on unknown hosts
      '';
      description = ''
        PCI function of the NHI the rail-0 cable enters on THIS host; the
        provisioner refuses to run when the rail netdev resolves to any other
        NHI. Per-host constants are safe here where tb-fleet's flat nhiDevices
        list was not (#267): the table is keyed by hostName so one host's
        constant can never be consulted on the other, the values name soldered
        PCI functions rather than probe-order names, and a wrong value fails
        CLOSED — a loud refusal and a red unit, never a wrong-cable provision.
        null disables the gate (recorded-identity gate still applies) with a
        warning every run.
      '';
    };

    streams = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        How many named streams (fn0..fnN-1) to provision. Each is PINNED to
        in/out hopid 10+N (see the HAZARDS block: 8 is thunderbolt_net's on
        every router in this fleet, 9 is headroom), and the lane adapters'
        Max Input HopID is 19 on these hosts — so at most 10 streams, and
        keep it small anyway: the budget is shared with thunderbolt_net.
      '';
    };

    ringSize = lib.mkOption {
      type = lib.types.int;
      default = 1024;
      description = "TX/RX ring entries per stream (32..4096). 4096 ENOMEM'd on two concurrent streams; 1024 is the proven multi-stream size.";
    };

    throttlingNs = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "Interrupt throttling in ns; lower is better latency (driver default 8192).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.streams >= 1 && cfg.streams <= 10;
        message = "myUsb4Stream.streams must be 1..10: hopids are pinned at 10+N and Max Input HopID is 19 on these hosts (measured 2026-08-31, all four host lane adapters).";
      }
    ];

    # The stream devices are operator surface (bench harnesses, transport
    # shims), not a root-only debug interface.
    #
    # The second rule is the lifecycle fix (learned 2026-08-30, worker
    # reboot): the peer rebooting tears down and re-creates the XDomain, and
    # the configfs group tree goes with it — a boot-time oneshot provisions
    # NOTHING that survives the peer bouncing. Every (re)appearance of a
    # stream service re-pulls the provisioner via the systemd-udev WANTS
    # idiom, and the service is idempotent + re-runnable (no RemainAfterExit).
    # The same re-fire is what let the pre-#275 module provision TWO different
    # cables inside one coordinator boot (cable B at 18:42:54, cable A at
    # 23:22:48, 2026-08-30) — every re-fire now passes the identity gates
    # first, so a drifted name produces a refusal instead of a second cable.
    services.udev.extraRules = ''
      KERNEL=="tbstream[0-9]*", GROUP="users", MODE="0660"
      ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{key}=="stream", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb4-stream-provision.service"
    '';

    systemd.services.usb4-stream-provision = {
      description = "Provision named USB4STREAM groups on the rail-0 cable";
      wantedBy = [ "multi-user.target" ];
      # After the boot-path module loader on patched boots (stock boots load
      # thunderbolt_stream via boot.kernelModules / the loader's fallback);
      # after network.target so the rail netdev exists to anchor resolution.
      after = [
        "network.target"
        "fn-rdma-modules.service"
      ];
      # Re-fired by udev on every stream-service appearance; a flapping cable
      # must not trip the start limiter and leave streams unprovisioned.
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = provisionScript;
        # The identity record (#275) and the keep-foreign marker live here.
        StateDirectory = "usb4-stream";
      };
    };
  };
}
