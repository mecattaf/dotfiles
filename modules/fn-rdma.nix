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
#      needs a TB tunnel. (The zenbook-duo kept its entry because it docked
#      over Thunderbolt; that host left the fleet 2026-08-30.)
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
#      only because the staged dir lives on the ROOT filesystem, readable
#      before any udev-driven mount could exist.
#
#      That last clause was free while the twins were single-disk. It became
#      a LIVE CONSTRAINT on 2026-08-30 (#261): the coordinator gained the
#      500GB retired off the worker and /home moved onto it wholesale. This
#      unit runs at sysinit.target with DefaultDependencies=no, ordered only
#      after systemd-remount-fs.service — it fires long before any ordinary
#      mount unit could bring /home up. So stagedDir is /var/lib/... and NOT
#      ~/.local/state/...: vermagic-pinned .ko files are OS state, not user
#      data, and they were only ever under $HOME by accident of who built
#      them. The old path is the one thing about the /home split that would
#      have silently degraded both twins to the stock fallback forever.
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
# THE VERMAGIC TREADMILL (#279, measured 2026-08-31). stagedDir is keyed to
# the exact modDirVersion and stays that way — see the option's comment for
# why a more forgiving key would be worse, not kinder. The cost of an honest
# key is that EVERY kernel bump silently retargets the loader at an empty
# path, and that cost has been paid unnoticed: the twins have run 7.2.2 since
# the 08-30 bump (`uname -r` = 7.2.2 on both) while /var/lib/flashnext-rdma
# holds only 7.1.4 (Aug 29 00:03) and 7.2.0 (Aug 29 21:2x). Both are
# vermagic-dead the moment 7.2.2 boots, so both boxes took the sanctioned
# stock fallback and there is no verbs device on either: the coordinator's
# /sys/class/infiniband exists and is EMPTY with ib_core loaded at 0 users,
# the worker's does not exist at all.
#
# The loader DID say so, and that is the point: at PRIORITY=6.
#
#   coordinator 2026-08-30T18:42:47 fn-rdma-load[976]: fn-rdma: staged
#     thunderbolt-patched.ko missing under /var/lib/flashnext-rdma/7.2.2/out
#     — falling back to the STOCK set          <- PRIORITY=6, i.e. INFO
#
# `journalctl -p warning -b` on either twin showed nothing about RDMA, so the
# estate read this as "RDMA is parked pending a decision" when the true state
# was "RDMA cannot be tried at all". The miss is therefore now a WARNING
# (LOG_WARNING via systemd's SyslogLevelPrefix) plus a /run marker, and it is
# evaluated ABOVE the live-activation guard so a `switch` reports it too —
# that path previously printed "a thunderbolt core is already bound" and
# nothing whatsoever about whether a matched set even exists.
#
# The re-bake itself stays OUT of the config: it is one attended run of
# flashnext's host/rdma/fetch-and-build.sh per node, whose TARGET_KVER is
# already 7.2.2 and which refuses to build unless the box actually runs that
# kernel (and verifies the peer's over ssh), so it cannot mint another
# mismatch. Once a 7.2.2 tree is staged on both twins, 7.1.4 and 7.2.0 are
# prunable — nothing in this module reads a non-current tree, by design.
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
    # LOG_WARNING. The "<4>" is a syslog level prefix consumed by journald,
    # not printed text — systemd's SyslogLevelPrefix= defaults to true for
    # journal stdout, and serviceConfig below pins it explicitly so this does
    # not become a silent no-op if that default ever moves. #279: the miss
    # this reports was already being logged, just at PRIORITY=6 where
    # `journalctl -p warning -b` could never see it.
    warn() { echo "<4>fn-rdma: $*"; }
    staged=${cfg.stagedDir}
    kver=${config.boot.kernelPackages.kernel.modDirVersion}

    # ── #279 tripwire, deliberately ABOVE every early exit ───────────────
    # Whether a matched set is staged is independent of what is already
    # bound, so it is reported on EVERY activation — boot and live `switch`
    # alike. Detection is split from the fallback (which still happens
    # further down, in order, after the disable-flag check) purely so this
    # answer survives the live-activation guard immediately below.
    #
    # Deliberately NOT a myTripwire sensor, though tripwire-journal-sensor.sh
    # would match this line trivially: a missing bake is a STEADY state that
    # persists for as long as RDMA stays parked, and a tripwire with a
    # renotifySeconds on a permanently-true condition is a pager that cries
    # forever. Boot-time warning + /run marker is the right shape — one line
    # per boot, checkable on demand, silent once a bake lands.
    rdma_miss=""
    if [ ! -d "$staged" ]; then
      rdma_miss="no staged modules for $kver; falling back to stock thunderbolt, ibverbs unavailable ($staged does not exist)"
    else
      for m in thunderbolt-patched.ko thunderbolt_net.ko thunderbolt_ibverbs.ko; do
        [ -f "$staged/$m" ] && continue
        # Worse than a clean miss: a directory exists, so a bake was started
        # for THIS vermagic and did not finish. Same fallback, louder cause.
        rdma_miss="incomplete staged set for $kver ($staged/$m missing); falling back to stock thunderbolt, ibverbs unavailable"
        break
      done
    fi
    if [ -n "$rdma_miss" ] && [ ! -e /etc/fn-rdma-disable ]; then
      warn "$rdma_miss — re-bake with flashnext host/rdma/fetch-and-build.sh (#279)"
      # Counterpart to /run/fn-rdma-patched: the negative answer, greppable
      # without parsing the journal, for anything (or anyone) checking
      # whether this boot has a verbs device to reach for.
      echo "$kver" > /run/fn-rdma-stock-fallback || true
    elif [ -z "$rdma_miss" ]; then
      # A bake landed (or the tree was always complete). Detection runs on
      # every `switch` (restartIfChanged), so without this the marker written
      # by an earlier miss would keep answering "no matched set" for a box
      # that has one — the marker must track the CURRENT answer, not the
      # first one this boot.
      rm -f /run/fn-rdma-stock-fallback
    fi

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

    # Detected and warned about at the top of this script. Acting on it here
    # keeps the ORDER the header promises (disable flag first, then staging)
    # and keeps the fallback non-blocking: rails up, IP normal, no ibverbs.
    # A missing RDMA stack must never stop the rails carrying IP — that is
    # the design, and #279 changes only how loudly it is announced.
    if [ -n "$rdma_miss" ]; then
      say "falling back to the STOCK set — $rdma_miss"
      load_stock
      exit 0
    fi

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
    # rail0 is cable A's netdev by construction since #266 (a .link Name= on
    # the NHI's ID_PATH, applied by udev at add time — so the name that
    # appears here is already the pinned one). Before that pin this waited on
    # `thunderbolt0`, i.e. on whichever cable won the probe race, and bound
    # RoCE to it: on the 2026-08-31 flip that would have put the verbs
    # provider on cable B while the streams ran on cable A.
    for _ in $(seq 60); do
      [ -e /sys/class/net/rail0 ] && break
      sleep 0.5
    done
    [ -e /sys/class/net/rail0 ] || say "rail0 never registered; inserting anyway"
    # No native_rc_split_zcopy: that knob belongs to a local zero-copy patch
    # this build deliberately does not carry (fetch-and-build.sh header).
    if ! insmod "$staged/thunderbolt_ibverbs.ko" \
      profile=linux_perf bind_services=1 allocate_rings=1 start_rings=1 \
      negotiate_native=1 enable_tunnels=1 register_verbs=1 \
      native_tx_max_inflight=128 roce_netdev=rail0; then
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
      # modDirVersion, not version: the attended lane stages at $KVER =
      # `uname -r`, which is the modules-dir string ("7.2.0"), while
      # kernel.version is the bare series ("7.2") — using the latter is
      # exactly how the original never-matching "7.2/out" default was born.
      # Following the configured kernel means a kernel bump automatically
      # retargets the loader at the (initially empty) new path: the first
      # boot after a bump takes the sanctioned stock fallback until the
      # attended lane re-bakes for the new vermagic. That is the designed
      # sequence, not a regression.
      #
      # DECIDED 2026-08-31 (#279 suggestion 3, "key it to something more
      # forgiving than an exact modDirVersion"): NO — the exact key stays,
      # and the visibility problem is fixed instead (see THE VERMAGIC
      # TREADMILL in the header). A forgiving key cannot help, because the
      # thing being keyed has no ABI: a .ko carries a vermagic string the
      # kernel matches character-for-character, so a 7.2.0 tree is not "an
      # older set that mostly works" on 7.2.2, it is unloadable. Falling
      # back to the nearest tree would only trade this module's one clean,
      # diagnosable state (staging absent -> stock set, warned) for two
      # worse ones: a vermagic-refused insmod whose journal line blames the
      # module rather than the bump, or — with --force, which nothing here
      # will ever do — the patched core bound against mismatched struct
      # layouts, i.e. exactly the ring-ABI class of failure the
      # all-or-nothing pairing rule above exists to prevent. Honest key,
      # loud miss. Corollary: stale trees are dead weight, not a safety
      # net, so 7.1.4 and 7.2.0 are prunable the moment a 7.2.2 bake is
      # staged on both twins.
      default = "/var/lib/flashnext-rdma/${config.boot.kernelPackages.kernel.modDirVersion}/out";
      defaultText = lib.literalExpression ''"/var/lib/flashnext-rdma/''${config.boot.kernelPackages.kernel.modDirVersion}/out"'';
      description = ''
        Where fetch-and-build.sh staged the matched .ko set on THIS host.
        MUST be on the root filesystem — this unit runs before any /home
        mount unit can exist (#261; see loader 2 in the header).
        Deliberately a runtime path, not a store path: the modules are
        vermagic-pinned to the running kernel and rebuilt by the operator's
        attended lane, not by nix — route (b), the nix-native kernel swap,
        was evaluated and declined in host/rdma/attended-bringup.md.

        From boot the loadScript inserts the patched set staged here; if the
        staging is absent (fresh kernel bump awaiting its re-bake) or
        refuses to insert, the sanctioned fallback loads the STOCK
        thunderbolt set — rails up, IP normal, no ibverbs device. RDMA USE
        stays gated behind the attended lane either way (NCCL_IB_DISABLE=1
        is unconditional in fn-env.sh until the morning A/B flips it).

        An absent or incomplete staging is announced at LOG_WARNING and
        leaves /run/fn-rdma-stock-fallback naming the kernel that has no
        matched set (#279) — so the two questions worth asking are
        `journalctl -b -p warning -g fn-rdma` and
        `test -e /run/fn-rdma-stock-fallback`, not "is
        /sys/class/infiniband empty".
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
    # rail0 = cable A by construction (#266), so this door and roce_netdev
    # above can no longer drift onto different cables from each other.
    networking.firewall.interfaces.rail0.allowedUDPPorts = [ 4791 ];

    # ── The staging miss is now WATCHED, not just logged (#262, #279) ────────
    #
    # #279 made the miss loud at boot (LOG_WARNING plus the greppable negative
    # /run/fn-rdma-stock-fallback, which records the kernel the answer applies
    # to). That is still a log line: it scrolls past once per boot and nothing
    # asks about it again. #262's fourth acceptance item wanted a tripwire, and
    # this is it — the marker file makes the sensor a one-line existence test
    # rather than a journal grep, which is why it can be this cheap.
    #
    # Deliberately a SLOW tripwire. Unlike the rail tripwires, this watches a
    # state that is expected to persist for days: the re-bake is an attended,
    # per-node task (flashnext host/rdma/fetch-and-build.sh) and cannot be
    # automated from here. A 24 h refractory makes it a standing reminder
    # instead of a pager — the failure mode this guards against is FORGETTING,
    # not an outage.
    myTripwire.fn-rdma-staging = {
      description = "the patched thunderbolt ibverbs set is staged for the running kernel";
      intervalSeconds = 3600;
      onBootSec = "15min";
      threshold = 1;
      comparison = "ge";
      rearm = 0;
      refractorySeconds = 86400;
      valueField = "RDMA_STOCK_FALLBACK";
      sensorPath = [ pkgs.coreutils ];
      sensor = ''
        # Written by the boot unit whenever it falls back to the stock set;
        # its contents are the kernel release the fallback applies to, so a
        # stale file from an older kernel cannot read as a pass.
        if [ -e /run/fn-rdma-stock-fallback ]; then
          echo "1 fn-rdma:$(cat /run/fn-rdma-stock-fallback 2>/dev/null || echo unknown) 1"
        else
          echo "0 fn-rdma:staged 1"
        fi
      '';
      onFirePath = [ pkgs.coreutils ];
      onFire = ''
        mkdir -p /var/lib/failure-markers
        # $2 is the sensor's LABEL, namespaced "fn-rdma:<kver>" so the episode
        # key is unique across tripwires. The operator instruction below needs
        # the bare kernel release: TARGET_KVER=fn-rdma:7.2.2 would stage into
        # /var/lib/flashnext-rdma/fn-rdma:7.2.2/out, which the loader never
        # reads — a bake that reports success and still boots the stock set.
        kver="''${2#fn-rdma:}"
        printf '%s — fn-rdma is on the STOCK thunderbolt set for kernel %s; ibverbs is unavailable and any RDMA-vs-TCP comparison on this node is measuring sockets (episode %s)\n  This is the one attended task: run flashnext host/rdma/fetch-and-build.sh ON THIS NODE with TARGET_KVER=%s, which stages into ${cfg.stagedDir}, then reboot. Verify: ls ${cfg.stagedDir} and journalctl -b -p warning -g fn-rdma (silent when staged).\n' \
          "$(date '+%Y-%m-%d %H:%M')" "$kver" "$4" "$kver" \
          > /var/lib/failure-markers/fn-rdma-staging
      '';
    };

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
        # systemd's own default, pinned because the #279 tripwire depends on
        # it: without prefix parsing the loader's "<4>" would be printed as
        # literal text at PRIORITY=6 and the warning would be invisible all
        # over again.
        SyslogLevelPrefix = true;
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
