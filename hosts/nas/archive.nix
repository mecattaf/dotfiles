{ config, lib, ... }:
# ─── #130 ws4: cold archive for retired LLM model weights ───────────────────
#
# The problem this solves is narrower and sharper than "archive my models".
# Weights are not files in a directory anywhere on this fleet: lib/local-models.nix
# is a catalog, lib/model-store.nix turns each entry into a fixed-output
# `pkgs.fetchurl`, and the bytes live in /nix/store. "Retiring" a model means
# dropping it from `services.local-models.allow`, which makes its store paths
# unreferenced — and modules/common.nix runs a weekly `nix.gc` with
# `--delete-older-than 14d`. So today, retiring a model silently destroys the
# bytes about two weeks later. THAT is the bug. This tree is the fix.
#
# Full retire/restore procedure: docs/nas/model-archive.md. This module only
# provides the destination and its filesystem properties; there is deliberately
# no automation. A retire is a considered, occasional, human decision, and a
# cron job that copied multi-GB weights around on a guess would be worse than
# the manual `cp` the doc describes.
#
# ── Why this is a separate gate rather than tmpfiles in storage.nix ─────────
# storage.nix is LIVE and its NFS export list is load-bearing for the running
# media stack. Adding an export entry for a path the Day-2 runbook has not
# created yet risks `exportfs` erroring on the next switch and taking NFS —
# hence Immich, Navidrome and Plex — down with it. Gating the whole thing keeps
# that failure impossible until someone has actually made the subvolume.
#
# ── compress=none, and why it is a subvolume ────────────────────────────────
# GGUF weights are already quantised; zstd:3 over them buys essentially nothing
# and costs CPU on every write of a multi-GB file. Btrfs compression is a
# per-subvolume/per-file property, so `archive` has to be its own subvolume for
# the setting to be inheritable and durable.
#
# ── NOT in the LaCie mirror, on purpose ─────────────────────────────────────
# hosts/nas/lacie-mirror.nix mirrors exactly `photos music documents videos`, so
# `archive` is excluded by construction — no change needed there, and none
# should be made. #130's reasoning, which stands: these weights are
# re-downloadable from HuggingFace, and the LaCie is the binding capacity
# constraint at 4 TB. This tree is insurance against nix-gc, not against
# HuggingFace. If a model ever needs insurance against the REPO disappearing —
# a revision rewritten, a repo pulled — that is a different judgement and it
# belongs in the mirror; say so explicitly at retire time and add `archive` to
# the loop in lacie-mirror.nix, accepting that something else gives up space.
#
# RUNBOOK — enable
#   1. On the NAS:
#        btrfs subvolume create /mnt/nas/archive
#        btrfs property set /mnt/nas/archive compression none
#        btrfs property get /mnt/nas/archive compression   # -> compression=none
#      (Not retroactive. Do it before the first model lands.)
#   2. hosts/nas/default.nix: myNas.archive.enable = true; deploy the NAS.
#   3. From the coordinator, confirm the export appeared:
#        ls /mnt/nas/archive/models
#      It is exported read-write so the retire procedure is a plain `cp` from
#      the coordinator, which is where the store paths being archived live.
#   4. Then follow docs/nas/model-archive.md when a model is actually retired.
let
  cfg = config.myNas.archive;
  storageRoot = "/mnt/nas";
  archiveRoot = "${storageRoot}/archive";
in
{
  options.myNas.archive.enable = lib.mkEnableOption "the cold archive subvolume for retired model weights (#130 ws4)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.archive requires the verified myNas.storage mount";
      }
    ];

    systemd.tmpfiles.rules = [
      # 'z' for the subvolume root (adjust-only — a 'd' would manufacture a
      # plain compressed directory if the runbook step were skipped, which is
      # the whole failure this gate exists to prevent), 'd' for the plain
      # directory inside it. Same doctrine as storage.nix.
      "z ${archiveRoot} 0750 tom users -"
      "d ${archiveRoot}/models 0750 tom users -"
    ];

    # fsid=6, continuing storage.nix's explicit-per-subvolume export list. A
    # subvolume with no entry is invisible to NFSv4 clients (that is how
    # .snapshots and backups stay contained); this one is exported ON PURPOSE,
    # because the retire procedure copies store paths from the coordinator and
    # a plain `cp` over the mount is far less error-prone than an rsync-over-ssh
    # incantation typed at 11pm.
    services.nfs.server.exports = ''
      ${archiveRoot} 10.77.0.1(rw,sync,fsid=6,no_subtree_check,no_root_squash)
    '';
  };
}
