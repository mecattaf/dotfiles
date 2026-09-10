{
  writeShellApplication,
  coreutils,
  findutils,
  jq,
  symlinkJoin,
  runtimeRoot ? "/var/lib/local-models",
  manifestPath ? "/etc/local-models/wanted.json",
  stateFile ? "/var/lib/local-models/.prune-intent",
}:
# local-models prune, split into an ORACLE and a VERB (dotfiles#296).
#
# WHY THIS EXISTS. Until 2026-09-06 the boot-time local-models-sync oneshot
# ended with two unconditional `rm -rf`/`rm -f` branches over
# /var/lib/local-models, computed from /etc/local-models/wanted.json. Any change
# that narrowed the wanted set — a host `artifacts` edit, a roster change, a
# deployment selection change — became tens of GiB of deleted weights at the
# next boot, before anyone read the diff. Re-borrowable from the NAS Library in
# principle; still a delete nobody approved.
#
# THE SHAPE, per the ruled pruner disposition (CONSOLIDATED §3, at the sheet's
# default — "wanted.json aligned", with a guard):
#
#   local-models-prune-set   pure oracle. Prints the would-prune set, one
#                            TSV row per entry, deterministically sorted.
#                            Deletes nothing, ever, and has no flags. The
#                            explicit borrow transaction prints its AUDIT.
#
#   local-models-prune       the only verb that deletes.
#                              --dry-run  recompute, print, and RECORD the
#                                         sha256 of the exact set
#                              --yes      recompute, and delete ONLY if the
#                                         sha256 still equals what --dry-run
#                                         recorded — i.e. the dry-run diff must
#                                         be 0. Any drift, or no preceding
#                                         dry-run, refuses and deletes nothing.
#
# Both take their paths from the environment (LOCAL_MODELS_ROOT,
# LOCAL_MODELS_MANIFEST, LOCAL_MODELS_PRUNE_STATE) with the fleet defaults
# baked in, which is also how tests/local-models-sync drives them hermetically.
#
# Both touch root-owned paths under /var/lib/local-models in production, so the
# verb is run as `sudo local-models-prune --dry-run` then
# `sudo local-models-prune --yes`.
let
  # The paths both scripts read, environment-overridable so
  # tests/local-models-sync can drive them against a fixture tree.
  #
  # Split in two because the VERB never reads the manifest itself — it delegates
  # the whole computation to the ORACLE — and writeShellApplication runs
  # shellcheck, which fails the derivation on an unused `manifest=` assignment
  # (SC2034). That failure is why `nix build .#checks.<sys>.local-models-sync`
  # reported "1 dependency failed" and why no built binary ever existed to put
  # on PATH.
  rootPath = ''
    root="''${LOCAL_MODELS_ROOT:-${runtimeRoot}}"
  '';
  manifestPathLine = ''
    manifest="''${LOCAL_MODELS_MANIFEST:-${manifestPath}}"
  '';
  paths = rootPath + manifestPathLine;

  pruneSet = writeShellApplication {
    name = "local-models-prune-set";
    runtimeInputs = [
      coreutils
      findutils
      jq
    ];
    text = ''
      ${paths}
      if [ ! -d "$root" ]; then
        exit 0
      fi
      if [ ! -r "$manifest" ]; then
        echo "local-models-prune-set: cannot read manifest $manifest" >&2
        exit 2
      fi

      # One row per entry: <kind>\t<path>\t<bytes>. `artifact` is a whole
      # retired directory; `file` is a stray file inside an artifact the
      # manifest still wants. Sorted so the sha256 of this output is stable
      # across runs — that stability IS the dry-run contract.
      {
        for dir in "$root"/*/; do
          [ -e "$dir" ] || continue
          id="$(basename "$dir")"
          if ! jq -e --arg id "$id" 'any(.[]; .id == $id)' "$manifest" >/dev/null; then
            printf 'artifact\t%s\t%s\n' "''${dir%/}" "$(du -sb "$dir" | cut -f1)"
            continue
          fi
          while IFS= read -r f; do
            rel="''${f#"$root/$id/"}"
            if ! jq -e --arg id "$id" --arg rel "$rel" \
              'any(.[]; .id == $id and any(.files[]; .name == $rel))' "$manifest" >/dev/null; then
              printf 'file\t%s\t%s\n' "$f" "$(stat -c %s "$f")"
            fi
          done < <(find "$dir" -type f ! -name '*.part')
        done
      } | LC_ALL=C sort
    '';
  };

  # The audit the explicit borrow transaction prints instead of deleting.
  # Separated into its own binary so the guard suite can prove it removes
  # nothing.
  audit = writeShellApplication {
    name = "local-models-prune-audit";
    runtimeInputs = [
      coreutils
      pruneSet
    ];
    text = ''
      entries=0
      bytes=0
      while IFS=$'\t' read -r kind path size; do
        [ -n "''${kind:-}" ] || continue
        echo "local-models-prune: AUDIT would prune $path ($size bytes)"
        entries=$((entries + 1))
        bytes=$((bytes + size))
      done < <(local-models-prune-set)
      echo "local-models-prune: AUDIT prune-set $entries entries, $bytes bytes"
    '';
  };

  prune = writeShellApplication {
    name = "local-models-prune";
    runtimeInputs = [
      coreutils
      findutils
      jq
      pruneSet
    ];
    text = ''
      ${rootPath}
      state="''${LOCAL_MODELS_PRUNE_STATE:-${stateFile}}"

      # printf rather than a heredoc: this text is a Nix indented string, and a
      # heredoc terminator's column is not something to make depend on how the
      # formatter reindents the file.
      usage() {
        printf '%s\n' \
          'local-models-prune --dry-run   recompute the would-prune set, print it,' \
          '                               and record its sha256 as the delete intent' \
          'local-models-prune --yes       delete that set, and ONLY if it is still' \
          '                               byte-for-byte what --dry-run recorded' \
          'Nothing else deletes. Borrowing audits and never removes.' >&2
      }

      mode=""
      case "''${1:-}" in
        --dry-run) mode=dry ;;
        --yes) mode=yes ;;
        -h | --help)
          usage
          exit 0
          ;;
        *)
          usage
          exit 2
          ;;
      esac
      if [ "$#" -gt 1 ]; then
        usage
        exit 2
      fi

      set_file="$(mktemp)"
      trap 'rm -f "$set_file"' EXIT
      local-models-prune-set >"$set_file"
      digest="$(sha256sum <"$set_file" | cut -d' ' -f1)"

      entries=0
      bytes=0
      while IFS=$'\t' read -r kind _path size; do
        [ -n "''${kind:-}" ] || continue
        entries=$((entries + 1))
        bytes=$((bytes + size))
      done <"$set_file"

      if [ "$mode" = dry ]; then
        while IFS=$'\t' read -r kind path size; do
          [ -n "''${kind:-}" ] || continue
          echo "local-models-prune: would prune $kind $path ($size bytes)"
        done <"$set_file"
        echo "local-models-prune: prune-set $entries entries, $bytes bytes"
        mkdir -p "$(dirname "$state")"
        printf '%s\n' "$digest" >"$state"
        echo "local-models-prune: recorded intent $digest in $state"
        echo "local-models-prune: run 'local-models-prune --yes' to delete exactly this set"
        exit 0
      fi

      # --yes from here. Two refusals, both silent about nothing: the operator
      # is told exactly which precondition failed.
      if [ ! -r "$state" ]; then
        echo "local-models-prune: REFUSING — no recorded dry-run intent at $state" >&2
        echo "local-models-prune: run 'local-models-prune --dry-run' first" >&2
        exit 3
      fi
      recorded="$(cat "$state")"
      if [ "$recorded" != "$digest" ]; then
        echo "local-models-prune: REFUSING — the prune set changed since the dry-run" >&2
        echo "local-models-prune:   recorded $recorded" >&2
        echo "local-models-prune:   current  $digest" >&2
        echo "local-models-prune: the dry-run diff must be 0; re-run --dry-run and read it" >&2
        exit 4
      fi

      while IFS=$'\t' read -r kind path size; do
        [ -n "''${kind:-}" ] || continue
        case "$kind" in
          artifact)
            echo "local-models-prune: removing retired artifact $path ($size bytes)"
            rm -rf "$path"
            ;;
          file)
            echo "local-models-prune: removing stray file $path ($size bytes)"
            rm -f "$path"
            ;;
          *)
            echo "local-models-prune: unknown entry kind $kind for $path" >&2
            exit 5
            ;;
        esac
      done <"$set_file"

      # Only after a delete pass, and only inside artifact dirs that survive.
      if [ -d "$root" ]; then
        find "$root" -mindepth 2 -type d -empty -delete
      fi

      rm -f "$state"
      echo "local-models-prune: removed $entries entries, $bytes bytes"
    '';
  };
in
# One derivation carrying both binaries, so the module installs one package and
# the hermetic check builds one attribute.
symlinkJoin {
  name = "local-models-prune";
  paths = [
    prune
    pruneSet
    audit
  ];
  meta = {
    description = "Audit-first prune for the local model working copies";
    mainProgram = "local-models-prune";
  };
}
