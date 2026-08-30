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
#
# What this module owns — the CONFIGURATION half the kernel pin alone doesn't
# give (module loading lives in tb-fleet.nix / worker default.nix for stock
# boots and modules/fn-rdma.nix for patched boots):
#   1. udev: /dev/tbstream* opens for the operator group, not just root.
#   2. A provisioning oneshot that resolves the stream service ON THE SAME
#      CABLE as the IP rail and creates N named stream groups. Service names
#      are per-host and per-domain and the two cables CROSS between the twins
#      (coordinator domain0 ↔ worker domain1); never hardcode "0-2.1" — the
#      only stable anchor is "the cable thunderbolt0 rides".
#   3. Stream names are the cross-host rendezvous: both twins create fn0..fnN
#      and the driver pairs them by name over XDomain properties (hopids
#      auto-allocate; each end advertises, the peer inherits).
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
#   - Rail 1 (the second cable) is parked with no IP and its worker-side
#     controller failed DMA activation on first-ever use; streams provision
#     on the rail-0 cable only until that link earns trust.
#   - HopIDs are a SHARED, RACEABLE budget with thunderbolt_net, and the netdev
#     existing does not mean it has claimed its own yet — it claims in
#     tbnet_open, not at probe. Provisioning inside that window starves the IP
#     rail (#262). The provisioner therefore gates on CARRIER, not on the
#     netdev's presence. Do not relax that back to a -e test.
let
  cfg = config.myUsb4Stream;

  provisionScript = pkgs.writeShellScript "usb4-stream-provision" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }
    say() { echo "usb4-stream: $*"; }

    rail=${cfg.rail}
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

    netsvc=$(basename "$(readlink -f "/sys/class/net/$rail/device")")
    xd=''${netsvc%.*}
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

    base="/sys/kernel/config/thunderbolt/stream/$svc"
    mkdir -p "$base"
    for i in $(seq 0 $((${toString cfg.streams} - 1))); do
      g="$base/fn$i"
      mkdir -p "$g"
      # EBUSY while a consumer holds the stream open — leave live values be.
      echo ${toString cfg.ringSize} > "$g/ring_size" 2>/dev/null || true
      echo ${toString cfg.throttlingNs} > "$g/throttling" 2>/dev/null || true
      # 0 means unallocated; -1 asks the driver to allocate. Nonzero values
      # (allocated here earlier, or inherited from the peer's advertisement)
      # are kept.
      [ "$(cat "$g/in_hopid")" != 0 ] || echo -1 > "$g/in_hopid"
      [ "$(cat "$g/out_hopid")" != 0 ] || echo -1 > "$g/out_hopid"
      say "fn$i ready: /dev/tbstream$(cat "$g/index") in_hopid=$(cat "$g/in_hopid") out_hopid=$(cat "$g/out_hopid") ring=$(cat "$g/ring_size") throttle=$(cat "$g/throttling")ns"
    done
  '';
in
{
  options.myUsb4Stream = {
    enable = lib.mkEnableOption "declarative USB4STREAM stream provisioning on the twins";

    rail = lib.mkOption {
      type = lib.types.str;
      default = "thunderbolt0";
      description = "Netdev whose cable carries the streams; the stream service is resolved as its XDomain sibling.";
    };

    streams = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        How many named streams (fn0..fnN-1) to provision. Each consumes one
        in + one out HopID from the adapter's tunneling range (8..19 on these
        hosts, shared with thunderbolt_net), so keep this small.
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
    # The stream devices are operator surface (bench harnesses, transport
    # shims), not a root-only debug interface.
    #
    # The second rule is the lifecycle fix (learned 2026-08-30, worker
    # reboot): the peer rebooting tears down and re-creates the XDomain, and
    # the configfs group tree goes with it — a boot-time oneshot provisions
    # NOTHING that survives the peer bouncing. Every (re)appearance of a
    # stream service re-pulls the provisioner via the systemd-udev WANTS
    # idiom, and the service is idempotent + re-runnable (no RemainAfterExit).
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
      };
    };
  };
}
