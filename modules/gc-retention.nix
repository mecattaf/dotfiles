{
  config,
  lib,
  pkgs,
  ...
}:
# System-generation retention: keep the last K *and* the booted one. Refs #133.
#
# This replaces `nix.gc.options = "--delete-older-than 14d"`. That looked like
# "two weeks of rollback depth" but is the opposite of a safety net: nix only
# guarantees the *current* generation survives an age sweep, and current is not
# necessarily good. Switch onto a broken config, leave it a fortnight, and age
# expiry deletes the last generation that actually booted while faithfully
# preserving the broken one. Count-based retention structurally cannot do that.
#
# Why an explicit booted-generation exemption on top of the count: K alone is a
# bet on churn rate, and the coordinator's churn is not gentle — generations
# 49→96 landed in 8.7 days (2026-07-25 → 2026-08-03), i.e. ~5.5/day during
# active work, ~3.4/day averaged since the flash. At that rate any K small
# enough to be useful for disk is small enough to prune the generation you are
# running from. So the booted generation is excluded by name, and K just sets
# how much *extra* history to keep.
#
# INCIDENT (2026-08-20): found the coordinator holding exactly ONE system
# generation — rollback depth zero on the daily driver. Cause: a hand-run
# `nix-collect-garbage -d` against the 90%-full disk. `-d` deletes every
# non-current generation FIRST and only then collects, silently defeating
# everything this module argues for. Runbook rule: when the disk is full,
# reap roots and run PLAIN `nix store gc` (or wait for this module's timer);
# never reach for `-d` on a machine you might need to roll back. Depth
# restores itself as switches accumulate — nothing to repair, only to stop
# repeating.
#
# Note what this is and is not protecting. /run/booted-system and
# /run/current-system are GC roots, so nix-collect-garbage can never free the
# running closure's store paths no matter what happens here — the store is safe
# either way. What the exemption preserves is the *profile entry*: without it,
# `rollback-offline --list` (#106) and the boot menu would stop offering the
# generation you booted from, even though its paths were still on disk.
let
  keep = 20;

  pruneGenerations = pkgs.writeShellScript "nix-gc-prune-generations" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    profile=/nix/var/nix/profiles/system
    nixenv=${config.nix.package.out}/bin/nix-env
    keep=${toString keep}

    booted=$(readlink -f /run/booted-system 2>/dev/null || echo none)
    current=$(readlink -f "$profile" 2>/dev/null || echo none)

    # Generation numbers, newest first.
    gens=$(
      for link in "$profile"-*-link; do
        [ -L "$link" ] || continue
        gen=''${link##*/system-}
        printf '%s\n' "''${gen%-link}"
      done | sort -rn
    )

    doomed=""
    n=0
    for gen in $gens; do
      n=$((n + 1))
      # Inside the keep window.
      if [ "$n" -le "$keep" ]; then continue; fi
      target=$(readlink -f "$profile-$gen-link" 2>/dev/null || echo none)
      # Never drop the entry for the system we are running, nor the one the
      # profile currently points at.
      if [ "$target" = "$booted" ] || [ "$target" = "$current" ]; then
        echo "nix-gc: keeping generation $gen (booted/current) outside the last $keep"
        continue
      fi
      doomed="$doomed $gen"
    done

    if [ -n "$doomed" ]; then
      echo "nix-gc: deleting system generations:$doomed"
      # shellcheck disable=SC2086
      "$nixenv" --profile "$profile" --delete-generations $doomed
    else
      echo "nix-gc: nothing to prune (last $keep kept)"
    fi
  '';
in
{
  # A nightly candidate creates one generation per participating host, so this
  # runs weekly alongside the store sweep rather than on its own timer.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    # Deliberately empty: generation retention is pruneGenerations below, and
    # nix-collect-garbage on its own only sweeps what is already unreferenced.
    # Anything here would reintroduce age-based expiry.
    options = "";
  };

  # Ordered before the store sweep: trimming generations first is what makes
  # their closures collectable in the same run.
  systemd.services.nix-gc.preStart = "${pruneGenerations}";
}
