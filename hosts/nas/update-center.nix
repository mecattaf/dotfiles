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

    # ── Flush the day's build, keep nothing (Tom's rule, 2026-08-22) ────────
    # "we only keep the latest armed update on disk, and yesterday's one gets
    # flushed." Once a closure is pushed above, the LOCAL copy is pure
    # garbage: attic on this same box holds the authoritative bytes, and
    # that is the only copy any device ever pulls. Leaving it in the store
    # means every night's three closures pile up until the weekly sweep,
    # which is precisely the accumulation that filled the eMMC twice.
    #
    # Nothing is lost by collecting immediately. These paths are unrooted the
    # moment the build ends (--no-link, so not even a result symlink), and
    # tomorrow's run re-substitutes anything still current from attic over
    # localhost at memory speed rather than rebuilding it.
    #
    # PLAIN gc, never -d: the -d ban in ../../modules/gc-retention.nix is
    # fleet doctrine, and it applies with full force on the box that is also
    # the house router. This removes unreachable paths only and cannot touch
    # a live generation or the running system.
    echo "update-center: flushing the day's build (attic holds the bytes)"
    nix-store --gc 2>&1 | tail -2 || echo "update-center: gc did not complete cleanly" >&2

    exit $fail
  '';
in
{
  options.myNas.updateCenter.enable = lib.mkEnableOption "nightly fleet closure builds pushed to the local attic cache";

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
        # Bottom of every queue: the house router's day job always wins.
        Nice = 19;
        CPUWeight = 20;
        IOSchedulingClass = "idle";
        MemoryHigh = "14G";
        MemoryMax = "16G";
      };
    };

    systemd.timers.update-center = {
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
