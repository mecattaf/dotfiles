{
  config,
  lib,
  pkgs,
  ...
}:
# ─── The model Library tree: /mnt/nas/models ────────────────────────────────
#
# Renamed from `archive` 2026-08-21 (Tom's ruling on cutover day: the disk
# should say what the tree IS — "Models (where i save LLMs)"), and broadened
# from "cold archive for retired weights" to the Library's whole byte plane:
#
#   models/weights  the forever collection — every LLM Tom downloads, kept,
#                   laid out /weights/<artifactId>/<file> mirroring the
#                   catalog. Includes the retired/unreproducible trees that
#                   were the original ws4 archive (models/flm/…).
#
# THE FLOW (2026-08-21, decisive — same-day v2 of this header): "model
# weights are static items, like a large pdf doc that we read." They are
# NEVER store paths and never part of any closure — the first update-center
# run proved the old FOD design impossible (three fleet builds dead on the
# 57G eMMC). Instead:
#   1. a new catalog row (lib/local-models.nix) is the ONLY trigger;
#   2. library-fetch (below, nightly + on demand) downloads the missing
#      files from Hugging Face ONCE, sha256-verified, into weights/;
#   3. each declaring node's local-models-sync borrows the bytes over the
#      LAN into /var/lib/local-models before llama-swap starts.
# An unchanged catalog moves zero bytes anywhere, on every nightly, ever.
# (The transient models/cache idea — a static nix binary cache of weight
# FODs — died with the FOD design and was never built.)
#
# Retiring a model is still the considered, manual procedure in
# docs/nas/model-archive.md — there is deliberately no automation for it,
# and library-fetch never deletes anything.
#
# History note (#130 ws4): the original problem this tree solved was that
# "retiring" a model (dropping it from `services.local-models.allow`) made
# its store paths unreferenced and the weekly nix-gc silently destroyed the
# bytes ~14 days later. That protection is now total — weights never enter
# any /nix/store at all.
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

  catalog = import ../../lib/local-models.nix { inherit lib; };
  modelStore = import ../../lib/model-store.nix { inherit catalog lib; };
  # The Library wants EVERY catalog artifact — canonical, candidate, and the
  # aux/appliance sets — because it is the archive; per-host selection happens
  # device-side via wanted.json. Retired rows keep their artifacts here too.
  libraryManifest = (pkgs.formats.json { }).generate "library-manifest.json" (
    modelStore.manifestFor (builtins.attrNames catalog.artifacts)
  );

  fetchScript = pkgs.writeShellApplication {
    name = "library-fetch";
    runtimeInputs = [
      pkgs.jq
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      weights=${lib.escapeShellArg "${modelsRoot}/weights"}
      fail=0

      # Authenticate when agenix has delivered the token (nas became a recipient
      # 2026-08-28). Public catalog rows never needed it; gated ones were 401ing
      # this loop into DOWNLOAD FAILED with no hint that a credential was the
      # missing piece. A box without the secret degrades to exactly the previous
      # anonymous behaviour rather than failing.
      #
      # The token goes in a 0600 header file, never on the curl argv — argv is
      # world-readable through /proc and this runs as root. curl drops the
      # Authorization header when huggingface.co redirects to its signed CDN
      # host; that is both correct and required, since cdn-lfs rejects a request
      # carrying a bearer it did not issue.
      auth=()
      token_file=/run/agenix/huggingface-token
      if [ -r "$token_file" ]; then
        hdr="$(mktemp)"
        chmod 600 "$hdr"
        printf 'Authorization: Bearer %s\n' "$(cat "$token_file")" > "$hdr"
        trap 'rm -f "$hdr"' EXIT
        auth=(-H "@$hdr")
        echo "library-fetch: authenticating to Hugging Face with the agenix token"
      else
        echo "library-fetch: no Hugging Face token readable; anonymous fetches only"
      fi
      while IFS=$'\t' read -r id name bytes oid url; do
        dest="$weights/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        echo "library-fetch: downloading $id/$name ($bytes bytes)"
        mkdir -p "$(dirname "$dest")"
        if ! curl -fL --retry 3 --retry-delay 10 "''${auth[@]}" -o "$dest.part" "$url"; then
          echo "library-fetch: DOWNLOAD FAILED: $url" >&2
          rm -f "$dest.part"
          fail=1
          continue
        fi
        actual="$(sha256sum "$dest.part" | cut -d' ' -f1)"
        if [ "$actual" != "$oid" ]; then
          echo "library-fetch: HASH MISMATCH for $id/$name (want $oid got $actual)" >&2
          rm -f "$dest.part"
          fail=1
          continue
        fi
        chmod 0644 "$dest.part"
        chown tom:users "$dest.part"
        mv -f "$dest.part" "$dest"
      done < <(jq -r '.[] | .id as $id | .files[] | [$id, .name, (.bytes|tostring), .oid, .url] | @tsv' ${libraryManifest})
      exit "$fail"
    '';
  };
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
      # directories inside it. Same doctrine as storage.nix. weights/ is
      # 0755: the worker reads it over the root-squashed ro export below.
      "z ${modelsRoot} 0755 tom users -"
      "d ${modelsRoot}/weights 0755 tom users -"
    ];

    # fsid=6, continuing storage.nix's explicit-per-subvolume export list. A
    # subvolume with no entry is invisible to NFSv4 clients (that is how
    # .snapshots and backups stay contained); this one is exported ON PURPOSE:
    # rw for the coordinator (archive/restore procedures over its /mnt/nas
    # mount), and READ-ONLY + root-squashed for the worker — its
    # local-models-sync borrows weights from here (mounted at /mnt/library,
    # hosts/worker/default.nix). The ACL still names hosts explicitly, per
    # the storage.nix doctrine; the nftables admission below is its twin.
    # NB the worker line carries fsid=0: NFSv4 clients resolve mount paths
    # against THEIR OWN pseudo-root, and the worker deliberately has no entry
    # on the storage-root export — so the models tree IS its pseudo-root and
    # it mounts `nas:/` (found live at first worker deploy: "nas:/models
    # failed: No such file or directory"). The coordinator's view is
    # unchanged (fsid=6 under its fsid=0 storage root).
    services.nfs.server.exports = ''
      ${modelsRoot} 10.42.0.2(rw,sync,fsid=6,no_subtree_check,no_root_squash)
      ${modelsRoot} 10.42.0.5(ro,sync,fsid=0,no_subtree_check,root_squash)
    '';
    networking.firewall.extraInputRules = ''
      ip saddr 10.42.0.5 tcp dport 2049 accept comment "NFSv4 from worker (models export, read-only)"
    '';

    # ── library-fetch: the ONLY thing that ever talks to Hugging Face ───────
    # Converges weights/ toward the full catalog manifest: present + right
    # size → untouched; missing → download once, sha256-verify (the catalog's
    # git-lfs oid IS the sha256), land atomically. Never deletes. Nightly at
    # 02:30 — after the 01:30 update-center has published the closures that
    # carry any new wanted.json, and before devices typically pull. Run it by
    # hand (`systemctl start library-fetch`) to stock a new model immediately.
    systemd.services.library-fetch = {
      description = "Download missing catalog model weights from Hugging Face into the Library";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ modelsRoot ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe fetchScript;
        # Big-model nights are long; a hung fetch becomes a failure, not a
        # zombie (same doctrine as update-center).
        TimeoutStartSec = "12h";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
    systemd.timers.library-fetch = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "02:30";
        Persistent = false;
        AccuracySec = "15min";
      };
    };
  };
}
