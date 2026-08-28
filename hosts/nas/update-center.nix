{
  config,
  lib,
  pkgs,
  ...
}:
# ─── The update center: nightly fleet builds on the appliance ───────────────
#
# The last piece of the App Store model (Tom's standing design, 2026-08-21:
# "NAS builds and publishes, every device pulls and decides"). Nightly, this
# box builds every fleet host's closure from the PUBLIC github repo and
# pushes the results into its own attic cache (./attic.nix, same machine —
# the push never leaves localhost). No device is ever touched: activation
# stays a per-device pull (`nixos-rebuild switch --flake`), exactly the
# BlueBuild "distribution split" — build farms and their garbage live here,
# endpoints download finished bytes at LAN speed.
#
# What this deliberately is NOT:
#   - a deploy mechanism. There are no SSH keys here, no push path, no
#     fleet-deploy resurrection. A broken nightly build costs nothing but a
#     stale cache; devices keep pulling whatever was last good.
#   - a self-update. The NAS is not even in the build list (Tom's ruling,
#     2026-08-21: "i asked that we do not build nas nightly, since i will not
#     be updating nas nightly") — its closure is built on demand at the
#     pinned ~6-month manual bump, by the operator, and never before.
#
# Source trust: the repo is public, fetched by commit over https — no repo
# key on the appliance (doctrine holds). Push trust: the attic token is
# minted LOCALLY each run via atticd-atticadm (the RS256 secret lives here,
# runbook-placed) — no fleet secret involved.
#
# Resource caps, because this CPU also routes the house: the build runs at
# the bottom of every scheduler's priority. Overnight window (01:30) is
# owned by this job per Tom's calendar rulings — snapshots deliberately sit
# at first-Saturday 08:00, clear of it. Persistent=false on purpose: a night
# missed (box off, power cut) is a build skipped, never a surprise daytime
# build — the C4 lesson from fleet-deploy's post-mortem.
#
# Model weights are NOT in these builds (2026-08-21 decisive ruling): the
# first observed run died filling the 57G eMMC with weight FODs, and the
# whole weight plane moved out of nix — see hosts/nas/models.nix
# (library-fetch) and modules/local-models.nix (local-models-sync). The
# closures built here are slim system closures and fit the eMMC comfortably.
let
  cfg = config.myNas.updateCenter;
  hosts = [
    "coordinator"
    "worker" # reintegrated 2026-08-21 (#229) — missed on the first pass
    "zenbook-duo"
  ];
  build = pkgs.writeShellScript "update-center-build" ''
    set -u
    export HOME=/var/lib/update-center
    export PATH=${
      lib.makeBinPath [
        config.nix.package
        pkgs.attic-client
        pkgs.coreutils
        pkgs.jq
      ]
    }:/run/current-system/sw/bin

    # Resolve main ONCE to an immutable rev so all three builds and the log
    # line describe the same candidate.
    rev="$(nix flake metadata --json --refresh github:mecattaf/dotfiles/main | jq -er .url)"
    echo "update-center: candidate $rev"

    # Fresh short-lived push token, minted against the local atticd.
    token="$(atticd-atticadm make-token --sub update-center --validity 1d \
      --pull fleet --push fleet)"
    attic login local http://127.0.0.1:8080 "$token" >/dev/null

    fail=0
    for host in ${lib.concatStringsSep " " hosts}; do
      echo "update-center: building $host"
      if out="$(nix build --no-link --print-out-paths \
        "$rev#nixosConfigurations.$host.config.system.build.toplevel")"; then
        echo "update-center: pushing $host ($out)"
        attic push local:fleet "$out" || {
          echo "update-center: push FAILED for $host" >&2
          fail=1
        }
      else
        echo "update-center: build FAILED for $host" >&2
        fail=1
      fi
    done

    exit $fail
  '';
in
{
  options.myNas.updateCenter = {
    enable = lib.mkEnableOption "nightly fleet closure builds pushed to the local attic cache";
    schedule.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Arm the 01:30 timer. Off leaves the service defined and hand-startable
        but nothing fires on a clock — the committed form of "paused", which a
        runtime `systemctl stop update-center.timer` is not (#234).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.attic.enable;
        message = "the update center pushes into the local attic cache; enable myNas.attic first";
      }
    ];

    systemd.services.update-center = {
      description = "Build all fleet closures and publish them to the attic cache";
      after = [
        "network-online.target"
        "atticd.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = build;
        StateDirectory = "update-center";
        # A cold ROCm-class build night can be very long on this CPU; the
        # ceiling exists so a hung fetch becomes a failure, not a zombie
        # (the fleet-deploy 11.5h-hang lesson).
        TimeoutStartSec = "8h";
        # ── Flush the day's build, however the job ended (Tom's rule) ───────
        # "we only keep the latest armed update on disk, and yesterday's one
        # gets flushed." This lived at the END of the build script until
        # 2026-08-22, which quietly did not work: the first real run under the
        # new layout hit TimeoutStartSec and was SIGTERMed mid-push, so the
        # script never reached its last line and nothing was collected.
        # Timeout is not the exceptional path here — a cold three-host night
        # genuinely approaches 8h — so the cleanup has to be owned by systemd,
        # not by the script's happy path. ExecStopPost runs on success, on
        # failure, and on timeout alike.
        #
        # Once a closure is pushed, the local copy is garbage: attic on this
        # same box holds the authoritative bytes and is the only copy any
        # device pulls. Plain gc, never -d (../../modules/gc-retention.nix),
        # and it removes unreachable paths only — it cannot touch a live
        # generation or the running system.
        ExecStopPost = "${pkgs.writeShellScript "update-center-flush" ''
          echo "update-center: flushing the build (attic holds the bytes)"
          ${config.nix.package}/bin/nix-store --gc 2>&1 | tail -2 \
            || echo "update-center: gc did not complete cleanly" >&2
        ''}";
        # The sweep must be allowed to finish; the default stop timeout would
        # kill it partway and leave exactly the accumulation it exists to stop.
        TimeoutStopSec = "1h";
        # ── The throttle, retuned 2026-08-28 after measuring it (#234) ──────
        # #234 filed three suspects for the KiB/s localhost push — Nice=19,
        # CPUWeight=20, IOSchedulingClass=idle "throttle the whole cgroup and
        # the attic push client inherits them". Measured on the live box while
        # a push ran (idle machine, load 0.23, nothing else building):
        #
        #   PID   NI  %CPU  COMMAND
        #   1172   0  99.0  atticd                ← the whole cost is HERE
        #  17703   0   0.1  attic push … local:fleet …
        #
        # The client is asleep. atticd does the chunking, hashing and zstd
        # server-side, it is a SEPARATE unit with NO limits at all (Nice=0, no
        # CPUWeight, no MemoryMax), and it is not in this cgroup — so none of
        # these three dials was ever in the push path. They are exonerated and
        # two of them are removed anyway, because they were doing harm or
        # nothing:
        #
        #   IOSchedulingClass=idle — a NO-OP on this machine. ionice classes
        #   are honoured only by BFQ; nvme0n1 runs `none` and mmcblk0 runs
        #   `mq-deadline` (both blk-mq, both ignore ioprio). It read as a
        #   deployed protection and was never one. Deleted rather than swapped
        #   for IOWeight, which needs BFQ too — the real politeness lever on
        #   this box is CPU, and that stays.
        #
        #   MemoryHigh=14G — this one was actively hurting. memory.high is not
        #   a ceiling, it is a *penalty*: past it the kernel injects reclaim
        #   stalls into every allocation, forever, and page cache from reading
        #   the store counts. That is why every run reports its peak as exactly
        #   14G (2026-08-28: "14G memory peak" — the limit, not a coincidence):
        #   the job spent its whole life pinned at the throttle point. Nix runs
        #   in-process here (root talks to the store directly, no daemon — see
        #   the 18.9G incoming / 28.5G written charged to THIS unit), so that
        #   penalty was taxing substitution and build too. MemoryMax below is
        #   the real bound and needs no help: at the limit the kernel simply
        #   reclaims the cache, with no allocator penalty and no OOM unless the
        #   anonymous set genuinely does not fit.
        #
        # Kept as-is, deliberately: the house router's day job still wins, and
        # #235 makes CPU politeness worth MORE, not less (the mt7925u uplink
        # has a documented wedge mode under CPU starvation). Nothing here is
        # raised in the name of speed.
        Nice = 19;
        CPUWeight = 20;
        MemoryMax = "16G";
      };
    };

    # ── The pause has to be committable (#234, 2026-08-28) ─────────────────
    # `systemctl stop update-center.timer` is runtime-only, and `wantedBy` is
    # re-asserted on every activation: three separate nixos-rebuilds during the
    # #235 recovery silently re-armed it, and the 08-28 run fired four minutes
    # after the power cycle that ended a five-day outage. A pause that has to
    # be re-applied by hand after every switch will be forgotten exactly once.
    # So the schedule is its own gate: flip it false to park the nightly in the
    # repo, where the reason lives next to it. The SERVICE stays defined and
    # `systemctl start update-center` still works — this parks the clock, not
    # the build farm.
    systemd.timers.update-center = lib.mkIf cfg.schedule.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "01:30";
        # Never catch up in daylight (see header).
        Persistent = false;
        AccuracySec = "15min";
      };
    };
  };
}
