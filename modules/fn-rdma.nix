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
#      unaffected, because blacklist only gates alias resolution). But the
#      blacklist does NOT block DEPENDENCY loads: the first worker reboot
#      (00:35, 2026-08-29) came back with the stock core bound anyway,
#      pulled in as the `typec` module's dependency when coldplug loaded the
#      UCSI/USB-C stack at ~6.7s — the unit ran at 7.7s and its live-guard
#      correctly stood down. Blacklisting typec instead would break PD
#      management (framework_tool, tb-link-heal's ucsi unbind). The cure is
#      ORDERING: the unit runs before systemd-udev-trigger.service, so the
#      patched core is already resident when typec's dependency resolves —
#      a dependency on a loaded module is satisfied, not re-loaded. Possible
#      only because the staged dir lives on the root filesystem (single-fs
#      twins), readable before any udev-driven mount could exist.
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

    # Stock fallback loads the matched IN-TREE stream module (7.2 ships it);
    # the patched path below insmods the staged MATCHED build instead. Never
    # crossed: the series changes the XDomain protocol-handler ABI that
    # stream registers against — same all-or-nothing doctrine as net.
    load_stock() {
      modprobe thunderbolt
      modprobe thunderbolt_net
      modprobe thunderbolt_stream || true
    }

    if [ -e /etc/fn-rdma-disable ]; then
      say "/etc/fn-rdma-disable present — loading the STOCK set"
      load_stock
      exit 0
    fi

    for m in thunderbolt-patched.ko thunderbolt_net.ko thunderbolt_ibverbs.ko; do
      if [ ! -f "$staged/$m" ]; then
        say "staged $m missing under $staged — falling back to the STOCK set"
        load_stock
        exit 0
      fi
    done

    if ! insmod "$staged/thunderbolt-patched.ko"; then
      # The one sanctioned fallback: the patched CORE itself refused, so the
      # host runs the stock set — a plain, known-good boot.
      say "patched core failed to insert — falling back to the STOCK set"
      load_stock || true
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
    if [ -f "$staged/thunderbolt_stream.ko" ]; then
      insmod "$staged/thunderbolt_stream.ko" \
        || say "matched stream module refused to insert — USB4STREAM absent this boot"
    else
      say "no matched thunderbolt_stream.ko staged — USB4STREAM absent this boot (the in-tree one never loads over the patched core)"
    fi
    # Marker for fn-rdma-ibverbs: the leaf loads only over OUR core.
    touch /run/fn-rdma-patched
  '';

  # Split off the boot-critical path deliberately: the second worker reboot
  # spent 7.6s of the pre-udev-trigger window waiting for thunderbolt0 to
  # train, which stretched sysinit far enough to trip an unrelated unit's
  # start-rate limit (suid-sgid-wrappers, 5 activation requests inside one
  # window). Only the CORE has a first-bound requirement; the verbs provider
  # is a leaf and can take its time here, off every critical path.
  ibverbsScript = pkgs.writeShellScript "fn-rdma-ibverbs" ''
    PATH=${
      lib.makeBinPath [
        pkgs.kmod
        pkgs.coreutils
        pkgs.iproute2
      ]
    }
    say() { echo "fn-rdma-ibverbs: $*"; }
    staged=${cfg.stagedDir}

    modprobe configfs || true
    modprobe ib_core || true
    modprobe ib_uverbs || true
    for _ in $(seq 60); do
      [ -e /sys/class/net/thunderbolt0 ] && break
      sleep 0.5
    done
    [ -e /sys/class/net/thunderbolt0 ] || say "thunderbolt0 never registered; inserting anyway"
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
    say "verbs provider live: $(ls /sys/class/infiniband/ 2>/dev/null | tr '\n' ' ')"
  '';
in
{
  options.myFnRdma = {
    enable = lib.mkEnableOption "patched Thunderbolt core/net/ibverbs set, first-bound at boot (dotfiles#241)";

    stagedDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/tom/.local/state/flashnext-rdma/7.2.0/out";
      description = ''
        Where fetch-and-build.sh staged the matched .ko set on THIS host.
        Deliberately a runtime path, not a store path: the modules are
        vermagic-pinned to the running kernel and rebuilt by the operator's
        attended lane, not by nix — route (b), the nix-native kernel swap,
        was evaluated and declined in host/rdma/attended-bringup.md.

        RE-BAKED 2026-08-29 (#244): the 7.2.0 set is built and staged
        bit-identical on both twins (the script stages at $KVER = uname -r,
        so the path is 7.2.0/out — the earlier 7.2/out guess never matched
        anything). From the next boot the loadScript inserts the patched
        set; if the staging is ever absent or refuses to insert, the
        sanctioned fallback still loads the STOCK thunderbolt pair — rails
        up, IP normal, no ibverbs device. RDMA USE stays gated behind the
        attended lane either way (NCCL_IB_DISABLE=1 is unconditional in
        fn-env.sh until the morning A/B flips it).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Loader 2 of the three in the header: block stage-2 udev's modalias path.
    # thunderbolt_stream joined 2026-08-29: the peer advertising kstream would
    # otherwise make udev modalias-load the IN-TREE stream module over a
    # patched core (tbsvc:kstreamp… alias). The explicit modprobe in the
    # loader's stock fallback is unaffected — blacklist only gates alias
    # resolution.
    boot.blacklistedKernelModules = [
      "thunderbolt"
      "thunderbolt_net"
      "thunderbolt_stream"
    ];

    # RoCEv2 admission on rail 0 ONLY — the house per-interface idiom, never
    # trustedInterfaces (the config's own "re-blanket-trusting" warning).
    # Rail 1 gets nothing: RDMA on both rails puts both peers at route 0x2 in
    # each other's domains and the source-blind control handler cross-matches
    # their HELLOs — HopID state corruption, not a slowdown.
    networking.firewall.interfaces.thunderbolt0.allowedUDPPorts = [ 4791 ];

    systemd.services.fn-rdma-modules = {
      description = "insert the patched thunderbolt core/net/ibverbs set before anything else binds";
      # Early boot, before stage-2 udev coldplug — see loader 2 in the
      # header for why ordinary multi-user placement lost the race to the
      # typec dependency chain. DefaultDependencies=no is required to sit
      # this early; remount-fs guarantees the root fs (where the staged .ko
      # set lives) is in its final state.
      wantedBy = [ "sysinit.target" ];
      before = [
        "systemd-udev-trigger.service"
        "bolt.service"
        "systemd-networkd.service"
        "network.target"
      ];
      after = [
        "systemd-remount-fs.service"
        "systemd-modules-load.service"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = loadScript;
      };
    };

    # The leaf, off the critical path — see the ibverbsScript comment.
    systemd.services.fn-rdma-ibverbs = {
      description = "insert the thunderbolt verbs provider once the patched pair is up";
      wantedBy = [ "multi-user.target" ];
      after = [ "fn-rdma-modules.service" ];
      requires = [ "fn-rdma-modules.service" ];
      unitConfig.ConditionPathExists = "/run/fn-rdma-patched";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ibverbsScript;
      };
    };
  };
}
