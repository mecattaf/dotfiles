{
  config,
  lib,
  pkgs,
  ...
}:
# ─── myFnRdma: the patched Thunderbolt module set, first-bound at boot ───────
#
# dotfiles#241, baked 2026-08-29 during the attended flashnext pre-arm pass.
# The twins run three out-of-tree modules built from westeri/thunderbolt @
# 503c5ae1 + the hellas-ai thunderbolt-ibverbs 10-file series @ 76ba39b6,
# staged by flashnext's host/rdma/fetch-and-build.sh (route (a): stock kernel,
# out-of-tree modules — never a kernel swap). RDMA stays rail 0 ONLY, and
# sockets remain the overnight transport of record: an ibverbs device existing
# means the pair env MUST carry NCCL_IB_DISABLE=1 until the morning A/B lane
# (gated on a banked TCP benchmark) deliberately flips it.
#
# THE ONE NON-NEGOTIABLE RULE, from the reference bring-up: the patched
# thunderbolt CORE must be the FIRST thunderbolt driver bound at boot. Loading
# it over an already-bound stock core, or hot-swapping a live core, wedges the
# HopID/tunnel allocator. Three loaders had to be silenced for that to be true
# on these hosts, and this module owns or documents all three:
#
#   1. The initrd. hardware.nix listed "thunderbolt" in
#      boot.initrd.availableKernelModules, and the initrd's udev coldplug
#      bound the stock core BEFORE "Switching root" (verified in the 08-21
#      boot journal: bus registered at 21:26:00, root switch at :03). No
#      stage-2 unit can ever be first past that. Removed in the twins'
#      hardware.nix — these boxes boot from NVMe and nothing in early boot
#      needs a TB tunnel; the zenbook (docking) keeps its entry.
#   2. Stage-2 udev coldplug. boot.blacklistedKernelModules below blocks the
#      modalias path (udev loads with `modprobe -b`, which honors blacklists;
#      the explicit `modprobe thunderbolt` in the fallback paths below is
#      unaffected, because blacklist only gates alias resolution).
#   3. systemd-modules-load. tb-fleet.nix (coordinator) and the worker's
#      default.nix pinned "thunderbolt-net" into boot.kernelModules — an
#      explicit load that ignores blacklists AND drags the stock core in as a
#      dependency. Both pins are now gated on !myFnRdma.enable.
#
# All-or-nothing pairing, per host: patched core+net together, or stock
# core+net together, NEVER stock net over a patched core — the DMA-ring ABI
# differs and that mix is the panic-on-cable-connect case. Cross-HOST version
# skew is fine for plain IP (packets over a USB4 tunnel, not a shared ring),
# which is what makes the worker-first sequential reboot safe; only
# RDMA/ibverbs USE requires both twins on the matched set.
#
# ESCAPE HATCH: `touch /etc/fn-rdma-disable` + one attended reboot returns
# that host to the stock pair — no config revert, no redeploy. Remove the
# flag and reboot to come back.
#
# Import-is-the-gate: only modules/strix.nix imports this file, so only the
# twins can ever see it, and it is enabled THERE rather than per-host because
# the matched-set requirement is a both-ends invariant — same reasoning as
# myLowLatCluster directly above it in that file.
let
  cfg = config.myFnRdma;

  loadScript = pkgs.writeShellScript "fn-rdma-load" ''
    PATH=${
      lib.makeBinPath [
        pkgs.kmod
        pkgs.coreutils
        pkgs.iproute2
        pkgs.gnugrep
      ]
    }
    say() { echo "fn-rdma: $*"; }
    staged=${cfg.stagedDir}

    # Boot-time only. On a live `switch` this unit starts immediately, but a
    # bound core must never be swapped hot — so a system that already carries
    # any thunderbolt core (stock or patched) is left exactly as it is. The
    # module set takes effect at the next boot, which the pre-arm pass
    # supervises deliberately.
    if grep -q '^thunderbolt ' /proc/modules; then
      say "a thunderbolt core is already bound — live activation, not boot; leaving it untouched"
      exit 0
    fi

    if [ -e /etc/fn-rdma-disable ]; then
      say "/etc/fn-rdma-disable present — loading the STOCK pair"
      modprobe thunderbolt
      modprobe thunderbolt_net
      exit 0
    fi

    for m in thunderbolt-patched.ko thunderbolt_net.ko thunderbolt_ibverbs.ko; do
      if [ ! -f "$staged/$m" ]; then
        say "staged $m missing under $staged — falling back to the STOCK pair"
        modprobe thunderbolt
        modprobe thunderbolt_net
        exit 0
      fi
    done

    if ! insmod "$staged/thunderbolt-patched.ko"; then
      # The one sanctioned fallback: the patched CORE itself refused, so the
      # host runs the stock pair — a plain, known-good boot.
      say "patched core failed to insert — falling back to the STOCK pair"
      modprobe thunderbolt || true
      modprobe thunderbolt_net || true
      exit 0
    fi

    if ! insmod "$staged/thunderbolt_net.ko"; then
      # NOT the sanctioned fallback. Stock net over the patched core is the
      # ring-ABI-mismatch panic case, so no net module loads at all: the TB
      # rails carry no IP this boot, and the fleet lives on the 5GbE — which
      # is exactly why #241 step 1 repointed the deploy path first.
      say "patched net failed over the patched core — refusing stock net (ring ABI mismatch); TB rails carry no IP this boot"
      exit 1
    fi
    say "patched core + net inserted"

    # The verbs provider is a leaf; its failure costs tonight's rdma DEVICE,
    # never the rails. Give thunderbolt0 a moment to register first — the
    # driver's netdev binding is named at insert time.
    modprobe configfs || true
    modprobe ib_core || true
    modprobe ib_uverbs || true
    for _ in $(seq 30); do
      [ -e /sys/class/net/thunderbolt0 ] && break
      sleep 0.5
    done
    # No native_rc_split_zcopy: that knob belongs to a local zero-copy patch
    # this build deliberately does not carry (fetch-and-build.sh header).
    if ! insmod "$staged/thunderbolt_ibverbs.ko" \
      profile=linux_perf bind_services=1 allocate_rings=1 start_rings=1 \
      negotiate_native=1 enable_tunnels=1 register_verbs=1 \
      native_tx_max_inflight=128 roce_netdev=thunderbolt0; then
      say "thunderbolt_ibverbs failed to insert — core+net stay patched, no rdma device this boot"
      exit 0
    fi

    d=$(ls /sys/class/infiniband/ 2>/dev/null | head -1)
    if [ -n "$d" ] && [ "$d" != usb4_rdma0 ]; then
      rdma dev set "$d" name usb4_rdma0 || say "device rename failed; still usable as $d"
    fi
    say "module set live: $(ls /sys/class/infiniband/ 2>/dev/null | tr '\n' ' ')"
  '';
in
{
  options.myFnRdma = {
    enable = lib.mkEnableOption "patched Thunderbolt core/net/ibverbs set, first-bound at boot (dotfiles#241)";

    stagedDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/tom/.local/state/flashnext-rdma/7.1.4/out";
      description = ''
        Where fetch-and-build.sh staged the matched .ko set on THIS host.
        Deliberately a runtime path, not a store path: the modules are
        vermagic-pinned to the running kernel and rebuilt by the operator's
        attended lane, not by nix — route (b), the nix-native kernel swap,
        was evaluated and declined in host/rdma/attended-bringup.md.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Loader 2 of the three in the header: block stage-2 udev's modalias path.
    boot.blacklistedKernelModules = [
      "thunderbolt"
      "thunderbolt_net"
    ];

    # RoCEv2 admission on rail 0 ONLY — the house per-interface idiom, never
    # trustedInterfaces (the config's own "re-blanket-trusting" warning).
    # Rail 1 gets nothing: RDMA on both rails puts both peers at route 0x2 in
    # each other's domains and the source-blind control handler cross-matches
    # their HELLOs — HopID state corruption, not a slowdown.
    networking.firewall.interfaces.thunderbolt0.allowedUDPPorts = [ 4791 ];

    systemd.services.fn-rdma-modules = {
      description = "insert the patched thunderbolt core/net/ibverbs set before anything else binds";
      wantedBy = [ "multi-user.target" ];
      # Before bolt: the daemon must find the patched core's bus, never
      # trigger a stock load. Before networkd: thunderbolt0's static /30
      # should configure onto the patched net's netdev in one pass.
      before = [
        "bolt.service"
        "systemd-networkd.service"
        "network.target"
      ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = loadScript;
      };
    };
  };
}
