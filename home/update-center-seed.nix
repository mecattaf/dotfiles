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
# FONTS (2026-09-15). pkgs/sf-pro.nix pins SF Pro to the fleet's own copy on
# the NAS instead of Apple's CDN. The same run adds that archive to the local
# store and seeds + roots it on the NAS as `sf-pro-fonts`, so the nightly
# build finds it without downloading anything.
let
  isCoordinator = osConfig.networking.hostName == "coordinator";
  sfProArchive = "/mnt/nas/documents/fonts/sf-pro/sf-pro-fonts.tar.zst";

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

      # SF Pro is not fetchable at all (pkgs/sf-pro.nix requireFile): add the
      # fleet's NAS copy to this store, and seed it like a private tree.
      fonts="$(nix-store --add-fixed sha256 ${lib.escapeShellArg sfProArchive})"
      log "seed sf-pro-fonts $fonts"
      paths+=("$fonts")
      names+=("sf-pro-fonts")

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

      nix copy --to "ssh-ng://$nas" "''${paths[@]}"

      # Root each seed by node name, then drop names this lock no longer has.
      # Arguments are name=path pairs; node names and store paths carry no
      # shell metacharacters, and the remote body is a quoted heredoc.
      pairs=()
      for i in "''${!paths[@]}"; do
        pairs+=("''${names[$i]}=''${paths[$i]}")
      done
      sshnas bash -s -- "''${pairs[@]}" <<'REMOTE'
      set -eu
      d=/var/lib/update-center/seeds
      mkdir -p "$d"
      keep=" "
      for pair in "$@"; do
        name="''${pair%%=*}"
        nix-store --realise --add-root "$d/$name" "''${pair#*=}" >/dev/null
        keep="$keep$name "
      done
      for f in "$d"/*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        case "$keep" in *" ''${f##*/} "*) ;; *) rm -f "$f" ;; esac
      done
      REMOTE
      log "seeded ''${#paths[@]} source(s) for $url"
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
