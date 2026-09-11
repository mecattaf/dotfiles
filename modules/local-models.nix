{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.local-models;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix {
    inherit catalog lib;
  };
  isSafeArtifactPath =
    path:
    path != ""
    && !(lib.hasPrefix "/" path)
    && lib.all (component: component != "" && component != "." && component != "..") (
      lib.splitString "/" path
    );

  hostArtifactIds = lib.unique cfg.artifacts;

  # The host's wanted-set manifest: the ONLY thing Nix contributes about
  # weights (2026-08-21 decisive ruling — weights are static documents, never
  # store paths; see lib/model-store.nix). It is metadata for an explicit
  # operator transaction; evaluating or activating NixOS never moves bytes.
  wantedManifest = (pkgs.formats.json { }).generate "local-models-wanted.json" (
    modelStore.manifestFor hostArtifactIds
  );

  borrowScript = pkgs.writeShellApplication {
    name = "local-models-borrow";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
      # local-models-prune-audit + local-models-prune-set: the would-prune set,
      # printed and never acted on. See pkgs/local-models-prune.nix.
      pkgs.local-models-prune
    ];
    text = ''
      case "''${1:-}" in
        --dry-run) mode=dry-run ;;
        --yes) mode=apply ;;
        *)
          echo "usage: local-models-borrow --dry-run|--yes" >&2
          echo "Model borrowing is an explicit transaction; NixOS activation never runs it." >&2
          exit 2
          ;;
      esac
      if [ "$#" -ne 1 ]; then
        echo "usage: local-models-borrow --dry-run|--yes" >&2
        exit 2
      fi

      default_library=${lib.escapeShellArg cfg.libraryPath}
      default_root=${lib.escapeShellArg modelStore.runtimeRoot}
      manifest="''${LOCAL_MODELS_MANIFEST:-/etc/local-models/wanted.json}"
      library="''${LOCAL_MODELS_LIBRARY:-$default_library}"
      root="''${LOCAL_MODELS_ROOT:-$default_root}"
      lock="''${LOCAL_MODELS_BORROW_LOCK:-/run/lock/local-models-borrow.lock}"
      reserve="''${LOCAL_MODELS_RESERVE_BYTES:-8589934592}"

      case "$reserve" in
        "" | *[!0-9]*)
          echo "local-models-borrow: REFUSING — reserve must be a non-negative byte count" >&2
          exit 2
          ;;
      esac
      if [ ! -r "$manifest" ]; then
        echo "local-models-borrow: REFUSING — cannot read manifest $manifest" >&2
        exit 6
      fi

      mkdir -p "$root"
      chmod 0755 "$root"
      mkdir -p "$(dirname "$lock")"
      exec 9>"$lock"
      if ! flock -n 9; then
        echo "local-models-borrow: REFUSING — another borrow transaction holds $lock" >&2
        exit 4
      fi

      rows() {
        jq -r '.[] | .id as $id | .files[] | [$id, .name, (.bytes|tostring), .oid] | @tsv' "$manifest"
      }

      # Preflight the WHOLE transaction before moving one byte. Reserving 8 GiB
      # keeps an operator borrow from filling the system disk. This is
      # intentionally conservative for a wrong-sized existing destination: the
      # old file remains usable until its verified replacement lands.
      needed=0
      entries=0
      fail=0
      while IFS=$'\t' read -r id name bytes oid; do
        dest="$root/$id/$name"
        src="$library/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        entries=$((entries + 1))
        needed=$((needed + bytes))
        echo "local-models-borrow: WOULD borrow $id/$name ($bytes bytes)"
        if [ ! -e "$src" ]; then
          echo "local-models-borrow: MISSING in Library: $id/$name (run library-fetch on the NAS?)" >&2
          fail=1
        elif [ "$(stat -c %s "$src")" != "$bytes" ]; then
          echo "local-models-borrow: WRONG SIZE in Library: $id/$name" >&2
          fail=1
        fi
      done < <(rows)

      available_blocks="$(stat -f -c %a "$root")"
      block_size="$(stat -f -c %S "$root")"
      available=$((available_blocks * block_size))
      if [ "$available" -gt "$reserve" ]; then
        usable=$((available - reserve))
      else
        usable=0
      fi
      echo "local-models-borrow: PLAN $entries file(s), $needed bytes; $available bytes free, $reserve reserved"

      if [ "$fail" -ne 0 ]; then
        echo "local-models-borrow: REFUSING — the canonical NAS Library is incomplete" >&2
        exit 5
      fi
      if [ "$needed" -gt "$usable" ]; then
        echo "local-models-borrow: REFUSING — transaction needs $needed bytes but only $usable are available after reserve" >&2
        exit 3
      fi
      if [ "$mode" = dry-run ]; then
        exit 0
      fi

      # Apply exactly the preflighted plan. Present + right size is untouched;
      # missing or wrong size is copied from the canonical NAS Library,
      # sha256-verified during the copy, and atomically landed.
      current_part=""
      trap '[ -z "$current_part" ] || rm -f "$current_part"' EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      while IFS=$'\t' read -r id name bytes oid; do
        dest="$root/$id/$name"
        src="$library/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        echo "local-models-borrow: borrowing $id/$name ($bytes bytes)"
        mkdir -p "$(dirname "$dest")"
        current_part="$dest.part"
        # Hash DURING the copy (tee splits the stream), not after: the old
        # cp-then-sha256sum shape re-read the whole artifact from local NVMe
        # as a second pass — ~40-60s of pure overhead on an 80GB borrow
        # (2026-08-29). Failure behavior is unchanged: pipefail + set -e
        # abort on a failed read/write exactly as a failed cp did.
        if ! actual="$(tee "$dest.part" < "$src" | sha256sum | cut -d' ' -f1)"; then
          echo "local-models-borrow: COPY FAILED for $id/$name" >&2
          rm -f "$dest.part"
          current_part=""
          fail=1
          continue
        fi
        if [ "$actual" != "$oid" ]; then
          echo "local-models-borrow: HASH MISMATCH for $id/$name (want $oid got $actual)" >&2
          rm -f "$dest.part"
          current_part=""
          fail=1
          continue
        fi
        chmod 0644 "$dest.part"
        mv -f "$dest.part" "$dest"
        current_part=""
      done < <(rows)

      # THIS TRANSACTION NEVER DELETES (dotfiles#296, ruled pruner disposition:
      # "wanted.json aligned", with a guard). It used to end here with two
      # unconditional prune branches — `rm -rf` of any artifact directory the
      # manifest no longer named, and `rm -f` of any stray file inside a kept
      # one — run by a boot-time oneshot with no operator present. Any change
      # that narrowed the wanted set therefore became tens of GiB of deleted
      # weights at the next boot, before anyone read the diff.
      #
      # What is left is an AUDIT: the same set, computed by the same rules,
      # printed and not touched. Deletion moved to the explicit manual verb
      # `local-models-prune`, which refuses unless the set it computes is
      # byte-for-byte the set a preceding `--dry-run` recorded.
      #
      # Still gated on a fully clean pass: a set computed from a failed borrow
      # would name files that are merely MISSING, not retired.
      if [ "$fail" = 0 ]; then
        local-models-prune-audit
      fi
      exit "$fail"
    '';
  };

  artifactIds = builtins.attrNames catalog.artifacts;
  artifactRows = builtins.attrValues catalog.artifacts;
  manifest = (pkgs.formats.json { }).generate "local-model-catalog.json" catalog;
  artifactEtc = lib.listToAttrs (
    map (artifactId: {
      name = "local-models/artifacts/${artifactId}";
      value.source = modelStore.materialized.${artifactId}.directory;
    }) cfg.artifacts
  );
  snapshotAliasArtifacts = lib.filterAttrs (
    artifactId: artifact: lib.elem artifactId cfg.artifacts && artifact.source.localName != null
  ) catalog.artifacts;
  snapshotAliasNames = map (artifact: artifact.source.localName) (
    builtins.attrValues snapshotAliasArtifacts
  );
  snapshotAliasEtc = lib.mapAttrs' (
    artifactId: artifact:
    lib.nameValuePair "local-models/snapshots/${artifact.source.localName}" {
      source = modelStore.materialized.${artifactId}.directory;
    }
  ) snapshotAliasArtifacts;

  catalogAssertions = [
    {
      assertion = lib.all (
        artifact: lib.elem artifact.source.primary (map (file: file.path) artifact.source.files)
      ) artifactRows;
      message = "Every local-model artifact primary must name one of its source files.";
    }
    {
      assertion = lib.all (
        artifact: lib.all (file: isSafeArtifactPath file.path) artifact.source.files
      ) artifactRows;
      message = "Local-model artifact paths must be safe repository-relative paths.";
    }
    {
      assertion = lib.all (
        artifact:
        let
          paths = map (file: file.path) artifact.source.files;
        in
        builtins.length paths == builtins.length (lib.unique paths)
      ) artifactRows;
      message = "Local-model artifacts must not repeat a repository-relative path.";
    }
    {
      assertion = lib.all (
        artifact:
        let
          basenames = map (file: builtins.baseNameOf file.path) artifact.source.files;
        in
        artifact.source.layout == "snapshot"
        || builtins.length basenames == builtins.length (lib.unique basenames)
      ) artifactRows;
      message = "Flat local-model artifact files must have unique basenames.";
    }
    {
      assertion = builtins.length cfg.artifacts == builtins.length (lib.unique cfg.artifacts);
      message = "services.local-models.artifacts must not contain duplicate artifact IDs.";
    }
    {
      assertion = lib.all (artifactId: lib.elem artifactId artifactIds) cfg.artifacts;
      message = "services.local-models.artifacts references an unknown artifact ID.";
    }
    {
      assertion = lib.all (
        name: isSafeArtifactPath name && builtins.baseNameOf name == name
      ) snapshotAliasNames;
      message = "Local-model snapshot aliases must be safe single directory names.";
    }
    {
      assertion = builtins.length snapshotAliasNames == builtins.length (lib.unique snapshotAliasNames);
      message = "Selected local-model snapshot aliases must be unique.";
    }
  ];
in
{
  options.services.local-models = {
    artifacts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Catalogue artifact IDs this host WANTS as working copies under
        /var/lib/local-models: the wanted set local-models-borrow loans from
        the NAS Library and the exact set local-models-prune keeps. This does
        not transfer bytes; both verbs are explicit operator transactions.
      '';
    };

    libraryPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/models/weights";
      description = ''
        Where this host reads the NAS model Library from (the coordinator's
        NFS mount by default; the worker mounts the read-only models export
        at /mnt/library). The explicit local-models-borrow transaction reads
        wanted artifacts here and copies them into /var/lib/local-models.
      '';
    };
  };

  config = {
    assertions = catalogAssertions;

    # Borrow and prune are both explicit operator transactions. Neither is a
    # service, timer, boot unit, or activation hook. local-models-prune is the
    # ONLY thing on this fleet that deletes a working copy (dotfiles#296):
    #   sudo local-models-borrow --dry-run  # inspect bytes and free-space gate
    #   sudo local-models-borrow --yes      # copy + verify from the NAS Library
    #   sudo local-models-prune --dry-run    # read the set, record the intent
    #   sudo local-models-prune --yes        # delete it, iff it has not changed
    environment.systemPackages = lib.optionals (hostArtifactIds != [ ]) [
      borrowScript
      pkgs.local-models-prune
    ];

    # Metadata stays generational and inspectable alongside the selected artifacts.
    environment.etc = {
      "local-models/catalog.json".source = manifest;
      "local-models/wanted.json".source = wantedManifest;
    }
    // artifactEtc
    // snapshotAliasEtc;

    # Weights live OUTSIDE the store (2026-08-21 decisive ruling). NixOS creates
    # only the empty root and publishes metadata; it NEVER starts, schedules,
    # orders against, or waits for a model-byte transfer. Working copies stay
    # world-readable so a read-only container mount (modules/halogen.nix) and
    # a hand-run llama-server both read them. Missing rows fail only when an
    # operator tries to use them.
    systemd.tmpfiles.rules = lib.mkIf (hostArtifactIds != [ ]) [
      "d ${modelStore.runtimeRoot} 0755 root root -"
    ];
  };
}
