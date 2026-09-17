{
  lib,
  osConfig,
  pkgs,
  ...
}:
# update-center-seed — put the fleet flake's PRIVATE locked sources into the
# NAS store before the nightly build, from the one box that can fetch them.
#
# WHY (2026-09-13). The NAS update-center failed every night from 2026-09-10:
# `error: Failed to fetch git repository 'https://github.com/mecattaf/tally'`.
# flake.lock pins tally-b (mecattaf/tally) and tally-lake (mecattaf/tally-ts-sdk),
# both PRIVATE, and hosts/nas/update-center.nix's doctrine is "no repo key on
# the appliance". Both stay true: Nix does not fetch a locked input whose
# content-addressed store path (computed from the lock's narHash) is already
# valid, so copying the exact source trees in is enough. MEASURED 2026-09-13
# 22:50: with the two trees seeded, `nix eval` of
# github:mecattaf/dotfiles/1214c6d#nixosConfigurations.worker…drvPath as root
# on the NAS with a FRESH HOME (no git cache, no credential) exits 0.
#
# HOW. As tom, who fetches the private repos through the gh credential helper:
#   1. resolve main to one immutable rev with --refresh, exactly as the NAS
#      will at 01:30, and read that rev's lock;
#   2. select every locked node owned by mecattaf (git+https or github type),
#      because a transitive input of tally-b could be private too and seeding
#      a public tree costs a few kB;
#   3. make each tree valid locally (`nix flake archive` fetches the lot) and
#      check its path equals the one computed from narHash;
#   4. `nix copy` them to ssh-ng://root@nas (tom's key is authorized there);
#   5. GC-root each at /var/lib/update-center/seeds/<node> on the NAS, and
#      drop roots of nodes the current lock no longer names, so the build's
#      ExecStopPost `nix-store --gc` never removes a live seed and old pins do
#      not accumulate.
# It skips (exit 0) while update-center is running on the NAS, and fails loudly
# otherwise, so failure-surfacing's user-unit watcher sees a broken seed.
#
# RACE. A push to main between this run and the NAS's 01:30 resolution can leave
# a newly-bumped private pin unseeded. Two runs (00:45 and 01:20) shrink the
# window, and the NAS names any gap itself: update-center's preflight logs
# `seed-missing <node>` for every private node whose tree is absent.
#
# FONTS (2026-09-15, extended 2026-09-17). pkgs/sf-pro.nix, pkgs/sfmono-liga.nix,
# pkgs/anthropic-mono-nerd.nix, pkgs/anthropic-ui.nix and
# pkgs/anthropic-webfonts.nix pin every vendor face to the fleet's own tarballs
# on the NAS M.2 (nas:/mnt/fast/fonts/{apple,anthropic}), never a download. The
# same run has the NAS add each tarball to its own store straight from that disk
# and root it here beside the source trees, so the nightly build finds them.
let
  isCoordinator = osConfig.networking.hostName == "coordinator";
  # Full paths, not bare names: since 2026-09-17 there is a second vendor
  # directory on the M.2 (anthropic/ beside apple/). The GC-root name is the
  # BASENAME stripped at the FIRST dot, so every basename must stay dot-free
  # before ".tar.zst" AND unique across directories — /var/lib/update-center/
  # seeds is one flat namespace shared with the locked flake nodes (tally,
  # tally-b, tally-lake) and the cleanup sweep below does not descend.
  #
  # Two failure modes. (1) A colliding basename silently clobbers the other
  # vendor's GC root, and the loss is discovered on the NAS at 01:30. This is
  # the one fontRootNames catches at EVAL time — but only font-vs-font; the
  # locked node names are discovered at RUNTIME from the lock and are invisible
  # here, so font-vs-node is checked in the shell instead (see the pairs loop).
  # (2) Without the basename strip, ''${f%%.*} on a PATH yields an ABSOLUTE name,
  #     so `nix-store --realise --add-root "$d/$name"` targets a nonexistent
  #     directory and fails. The remote body runs under `set -eu`, so the script
  #     aborts THERE and the sweep below never runs: the failure is loud (the unit
  #     fails, failure-surfacing sees it) and no existing root is touched.
  #     Measured 2026-09-17.
  # Keep the strip anyway: a loud nightly failure is still a broken seed.
  fontArchives = [
    "/mnt/fast/fonts/apple/sf-pro-fonts.tar.zst"
    "/mnt/fast/fonts/apple/sfmono-liga-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-mono-nerd-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-ui-fonts.tar.zst"
    "/mnt/fast/fonts/anthropic/anthropic-webfonts.tar.zst"
  ];
  # An INDEPENDENT second implementation of the shell's ''${f##*/} + ''${b%%.*}
  # below; nothing ties the two together, so change them as a pair.
  fontRootNames = map (p: lib.head (lib.splitString "." (baseNameOf p))) fontArchives;
  fontRootNamesCollide = lib.length (lib.unique fontRootNames) != lib.length fontRootNames;
  fontRootNameEmpty = lib.any (n: n == "") fontRootNames;
  # In the second guard below, only `n == ""` can ever fire, and only for a
  # basename beginning with a dot: `baseNameOf` cannot return a string
  # containing "/", so a `lib.hasInfix "/" n` disjunct would be dead code (it
  # was in the first draft). One case still slips through both guards and is
  # accepted: a path with a TRAILING slash, for which baseNameOf returns the
  # parent directory name (baseNameOf "/mnt/fast/fonts/anthropic/" ->
  # "anthropic"). The message wording is the documented contract; leave it.
  checkedFontArchives =
    lib.throwIf fontRootNamesCollide
      "update-center-seed: font archive basenames collide once stripped at the first dot: ${toString fontRootNames}"
      (
        lib.throwIf fontRootNameEmpty
          "update-center-seed: a font archive basename yields an empty or nested GC-root name"
          fontArchives
      );

  seed = pkgs.writeShellApplication {
    name = "update-center-seed";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssh
    ];
    # nix, git and gh come from the system and the user profile: the unit must
    # use the SAME nix the daemon runs and the SAME credential helper tom's git
    # config names (`gh auth git-credential`), not a second copy.
    text = ''
      export PATH="$PATH:/run/current-system/sw/bin:/etc/profiles/per-user/tom/bin"
      nas="''${UPDATE_CENTER_SEED_NAS:-root@nas}"
      log() { printf 'update-center-seed: %s\n' "$*"; }
      sshnas() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$nas" "$@"; }

      if sshnas systemctl is-active --quiet update-center.service; then
        log "update-center is running on the NAS; not seeding under a live build"
        exit 0
      fi

      meta="$(nix flake metadata --json --refresh github:mecattaf/dotfiles/main)"
      url="$(jq -er .url <<<"$meta")"
      log "candidate $url"

      # node<TAB>narHash for every mecattaf-owned locked node.
      nodes="$(jq -r '
        .locks.nodes | to_entries[]
        | select(.value.locked != null) | .value.locked as $l
        | select(($l.type == "git" and ($l.url // "" | test("^https://github.com/mecattaf/")))
              or ($l.type == "github" and $l.owner == "mecattaf"))
        | [.key, $l.narHash] | @tsv' <<<"$meta")"
      paths=()
      names=()
      archived=0
      while IFS=$'\t' read -r name nar; do
        [ -n "$name" ] || continue
        path="$(nix-store --print-fixed-path --recursive sha256 \
          "$(nix hash convert --hash-algo sha256 --to nix32 "$nar")" source)"
        if ! nix-store --check-validity "$path" 2>/dev/null; then
          if [ "$archived" -eq 0 ]; then
            log "fetching the lock's inputs locally (nix flake archive)"
            nix flake archive "$url" >/dev/null
            archived=1
          fi
          nix-store --check-validity "$path" || {
            log "FAILED: $name did not materialise at $path after archive" >&2
            exit 1
          }
        fi
        log "seed $name $path"
        paths+=("$path")
        names+=("$name")
      done <<<"$nodes"

      [ "''${#paths[@]}" -eq 0 ] || nix copy --to "ssh-ng://$nas" "''${paths[@]}"

      # Root each seed by node name, then drop names this lock no longer has.
      # Arguments are name=path pairs; node names and store paths carry no
      # shell metacharacters, and the remote body is a quoted heredoc. A font
      # pair names a file on the NAS M.2 instead, which is added there first;
      # its GC-root name is the BASENAME up to the first dot, so the directory
      # in the value is what distinguishes apple/ from anthropic/.
      pairs=()
      for i in "''${!paths[@]}"; do
        pairs+=("''${names[$i]}=''${paths[$i]}")
      done
      # The eval-time lib.throwIf above covers font-vs-font name collisions.
      # This covers font-vs-NODE, which it cannot: the locked node names come
      # from the lock at RUNTIME. Measured 2026-09-17 — a font archive named
      # tally.tar.zst evaluates cleanly and the unmodified remote heredoc then
      # silently CLOBBERS seeds/tally with the tarball (keep contains "tally",
      # so the sweep preserves the wrong one), surfacing only as update-center's
      # `seed-missing tally` on the NAS at 01:30. Fail here instead.
      for f in ${lib.escapeShellArgs checkedFontArchives}; do
        b="''${f##*/}"
        n="''${b%%.*}"
        # ''${names[@]+...} keeps this safe under `set -u` when the lock names
        # no mecattaf node at all.
        for m in ''${names[@]+"''${names[@]}"}; do
          if [ "$m" = "$n" ]; then
            log "FAILED: font archive $b would take the GC-root name '$n', already claimed by locked node $m" >&2
            exit 1
          fi
        done
        pairs+=("$n=$f")
      done
      sshnas bash -s -- "''${pairs[@]}" <<'REMOTE'
      set -eu
      d=/var/lib/update-center/seeds
      mkdir -p "$d"
      keep=" "
      for pair in "$@"; do
        name="''${pair%%=*}"
        path="''${pair#*=}"
        case "$path" in
          /nix/store/*) ;;
          *) path="$(nix-store --add-fixed sha256 "$path")" ;;
        esac
        nix-store --realise --add-root "$d/$name" "$path" >/dev/null
        keep="$keep$name "
      done
      for f in "$d"/*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        case "$keep" in *" ''${f##*/} "*) ;; *) rm -f "$f" ;; esac
      done
      REMOTE
      log "seeded ''${#pairs[@]} source(s) for $url"
    '';
  };
in
lib.mkIf isCoordinator {
  home.packages = [ seed ];

  systemd.user.services.update-center-seed = {
    Unit = {
      Description = "Seed the fleet flake's private locked sources into the NAS store";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe seed;
      TimeoutStartSec = "30min";
    };
  };

  systemd.user.timers.update-center-seed = {
    Unit.Description = "Seed private sources before the NAS nightly build (01:30)";
    Timer = {
      OnCalendar = [
        "*-*-* 00:45"
        "*-*-* 01:20"
      ];
      # A missed night is a skipped seed, same as update-center's own
      # Persistent=false: no surprise daytime copy.
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
