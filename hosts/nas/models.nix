{ config, lib, ... }:
# ─── The model Library tree: /mnt/nas/models ────────────────────────────────
#
# Renamed from `archive` 2026-08-21 (Tom's ruling on cutover day: the disk
# should say what the tree IS — "Models (where i save LLMs)"), and broadened
# from "cold archive for retired weights" to the Library's whole byte plane:
#
#   models/weights  the forever collection — every LLM Tom downloads, kept.
#                   Includes the retired/unreproducible trees that were the
#                   original ws4 archive (models/flm/…, rescued FLM weights).
#   models/cache    static Nix binary cache of the ACTIVE catalog (written
#                   nightly by the update-center job via `nix copy --to
#                   file://…`; regenerable, never precious). Fixed-output
#                   store paths are self-authenticating, so this cache needs
#                   NO signing key — the appliance's no-secrets doctrine
#                   survives. Devices list it as a substituter and pull
#                   models over the LAN instead of from Hugging Face.
#
# The flow this serves (2026-08-21 design, confirmed by Tom): models are
# downloaded ONCE from Hugging Face by the NAS overnight; coordinator/worker
# select what to load via the per-row `hosts` field in lib/local-models.nix
# and substitute the bytes from here at LAN speed. Retiring a model is still
# the considered, manual procedure in docs/nas/model-archive.md — there is
# deliberately no automation for it.
#
# History note (#130 ws4): the original problem this tree solved was that
# "retiring" a model (dropping it from `services.local-models.allow`) made
# its store paths unreferenced and the weekly nix-gc silently destroyed the
# bytes ~14 days later. That protection stands — weights live here, outside
# any /nix/store, immune to gc.
#
# ── Why this is a separate gate rather than tmpfiles in storage.nix ─────────
# storage.nix is LIVE and its NFS export list is load-bearing for the running
# media stack. Adding an export entry for a path that doesn't exist yet risks
# `exportfs` erroring on the next switch and taking NFS — hence Immich,
# Navidrome and Plex — down with it. Gating keeps that failure impossible
# until the subvolume is real.
#
# ── compress=none, and why it is a subvolume ────────────────────────────────
# GGUF weights are already quantised; zstd:3 over them buys essentially
# nothing and costs CPU on every write of a multi-GB file. Btrfs compression
# is a per-subvolume property, so the tree is its own subvolume for the
# setting to be inheritable and durable.
#
# ── In the LaCie mirror (2026-08-21 ruling, superseding #130's exclusion) ───
# hosts/nas/lacie-mirror.nix mirrors this tree. #130 excluded the old archive
# ("re-downloadable from HuggingFace; LaCie capacity is the constraint"), but
# the tree now also holds unreproducible runtime-owned weights and Tom's
# forever collection — insurance against the REPO disappearing, not just
# against nix-gc. models/cache rides along; if LaCie capacity ever binds,
# exclude cache/ first — it is the only regenerable part.
#
# ── NOT snapshotted, deliberately ───────────────────────────────────────────
# Weights are immutable multi-GB files; btrbk would pin nothing that the
# LaCie mirror doesn't already cover, and cache/ churns nightly. snapshots.nix
# does not list this subvolume, and should not.
#
# RUNBOOK — rename migration (do ON THE NAS, BEFORE deploying this module):
#   1. mv /mnt/nas/archive /mnt/nas/models          # subvolume rename
#      mv /mnt/nas/models/models /mnt/nas/models/weights
#   2. btrfs property get /mnt/nas/models compression   # -> none (inherited)
#   3. Deploy the NAS (tmpfiles adjusts perms, exportfs re-exports fsid=6).
#   4. From the coordinator: ls /mnt/nas/models/weights  # flm/… visible
#   5. Next LaCie dump: the mirror sees `models` as a new tree — the old
#      `archive` copy parks under .previous-versions/<date>/ and the 17G
#      recopies. Expected, accepted (one extra hour of USB time).
let
  cfg = config.myNas.models;
  storageRoot = "/mnt/nas";
  modelsRoot = "${storageRoot}/models";
in
{
  options.myNas.models.enable = lib.mkEnableOption "the model Library subvolume: weights (forever collection) + cache (static binary cache)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.models requires the verified myNas.storage mount";
      }
    ];

    systemd.tmpfiles.rules = [
      # 'z' for the subvolume root (adjust-only — a 'd' would manufacture a
      # plain compressed directory if the migration step were skipped, which
      # is the whole failure this gate exists to prevent), 'd' for the plain
      # directories inside it. Same doctrine as storage.nix.
      "z ${modelsRoot} 0755 tom users -"
      "d ${modelsRoot}/weights 0750 tom users -"
      # Written by the nightly update-center job (root), read by the static
      # cache HTTP front when that lands (ws5 follow-up).
      "d ${modelsRoot}/cache 0755 root root -"
    ];

    # fsid=6, continuing storage.nix's explicit-per-subvolume export list. A
    # subvolume with no entry is invisible to NFSv4 clients (that is how
    # .snapshots and backups stay contained); this one is exported ON PURPOSE,
    # because the retire procedure copies store paths from the coordinator and
    # a plain `cp` over the mount is far less error-prone than an
    # rsync-over-ssh incantation typed at 11pm. Both coordinator rails
    # admitted until the /30 retires in the cleanup commit.
    services.nfs.server.exports = ''
      ${modelsRoot} 10.77.0.1(rw,sync,fsid=6,no_subtree_check,no_root_squash) 10.42.0.2(rw,sync,fsid=6,no_subtree_check,no_root_squash)
    '';
  };
}
