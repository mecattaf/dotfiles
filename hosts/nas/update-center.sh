#!/usr/bin/env bash
# The update center's nightly body (hosts/nas/update-center.nix carries the
# unit, the reasoning and the PATH). Kept as a file so tests/update-center
# can run it hermetically with fake nix/attic binaries first on PATH.
#
#   update-center                                  nightly: resolve, build, push, publish
#   update-center --publish-only HOST PATH FLAKEREF publish one already-built closure
#
# Seams (all unset in the real unit):
#   UPDATE_CENTER_HOSTS        space-separated host list (the unit sets it)
#   UPDATE_CENTER_FLAKE        default github:mecattaf/dotfiles/main
#   UPDATE_CENTER_STATE_DIR    default /var/lib/update-center
#   UPDATE_CENTER_SIGNING_KEY  default /etc/ssh/ssh_host_ed25519_key
#   UPDATE_CENTER_STORE_DIR    default /nix/store
set -u

flake="${UPDATE_CENTER_FLAKE:-github:mecattaf/dotfiles/main}"
state="${UPDATE_CENTER_STATE_DIR:-/var/lib/update-center}"
signing_key="${UPDATE_CENTER_SIGNING_KEY:-/etc/ssh/ssh_host_ed25519_key}"
store_dir="${UPDATE_CENTER_STORE_DIR:-/nix/store}"
keep_releases=3

log() { printf 'update-center: %s\n' "$*"; }

attic_login() {
  # Fresh short-lived push token, minted against the local atticd.
  local token
  token="$(atticd-atticadm make-token --sub update-center --validity 1d \
    --pull fleet --push fleet)" || return 1
  attic login local http://127.0.0.1:8080 "$token" >/dev/null
}

# ── Candidate publication (#354) ────────────────────────────────────────────
# publish HOST STORE_PATH REV_URL LAST_MODIFIED
#
# Called ONLY after the host's closure is in Attic, so a pointer never names
# bytes the fleet cannot substitute. One immutable release directory per
# publication holds manifest.json + manifest.json.sig (ssh-keygen -Y, namespace
# fleet-update, this box's host key — the omarchy publisher's doctrine), and
# public/candidates/HOST is a symlink swapped with rename(2): the two files
# always change together, and a host whose build or push failed keeps its
# previous pointer untouched. The adopter re-reads its revision from the closure
# itself; last_modified here only lets it skip downloading an older candidate.
publish() {
  local host="$1" path="$2" rev="$3" last_modified="$4"
  local releases="$state/public/releases" candidates="$state/public/candidates"
  local stamp name dir hash
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  hash="$(basename "$path" | cut -c1-8)"
  name="$host-$stamp-$hash"
  dir="$releases/$name"
  mkdir -p "$releases" "$candidates" || return 1
  rm -rf "$dir"
  mkdir "$dir" || return 1
  jq -n \
    --arg host "$host" \
    --arg rev "$rev" \
    --arg store_path "$path" \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson last_modified "$last_modified" \
    '{schema: 1, host: $host, rev: $rev, last_modified: $last_modified,
      store_path: $store_path, built_at: $built_at, channel: "rolling"}' \
    >"$dir/manifest.json" || return 1
  ssh-keygen -q -Y sign -f "$signing_key" -n fleet-update "$dir/manifest.json" || return 1
  [ -s "$dir/manifest.json.sig" ] || return 1
  chmod 0755 "$dir" && chmod 0644 "$dir/manifest.json" "$dir/manifest.json.sig" || return 1
  sync "$dir/manifest.json" "$dir/manifest.json.sig" 2>/dev/null || true
  ln -sfn "../releases/$name" "$candidates/.$host.new" || return 1
  mv -T "$candidates/.$host.new" "$candidates/$host" || return 1
  log "published candidate $host -> $path"

  # Keep the newest $keep_releases releases of this host (the live one always).
  local live old
  live="$(readlink "$candidates/$host")"
  live="${live##*/}"
  find "$releases" -mindepth 1 -maxdepth 1 -type d -name "$host-*" -printf '%f\n' |
    sort -r | tail -n +$((keep_releases + 1)) | while read -r old; do
      [ "$old" = "$live" ] || rm -rf "${releases:?}/$old"
    done
  return 0
}

if [ "${1:-}" = --publish-only ]; then
  # For the live exercise and for closures built elsewhere (the coordinator
  # builds, `nix copy`s here, and this pushes and publishes): no build, and no
  # pointer unless the path is valid here, is this host's system, and reaches
  # Attic.
  host="${2:?usage: --publish-only HOST STORE_PATH FLAKEREF}"
  path="${3:?usage: --publish-only HOST STORE_PATH FLAKEREF}"
  ref="${4:?usage: --publish-only HOST STORE_PATH FLAKEREF}"
  case "$path" in
    "$store_dir"/*-nixos-system-"$host"-*) ;;
    *)
      log "refusing: $path is not a $host system closure" >&2
      exit 2
      ;;
  esac
  if ! nix-store --check-validity "$path" 2>/dev/null; then
    log "refusing: $path is not valid in this store (nix copy it here first)" >&2
    exit 2
  fi
  meta="$(nix flake metadata --json "$ref")" || exit 1
  rev="$(jq -er .url <<<"$meta")" || exit 1
  last_modified="$(jq -er .lastModified <<<"$meta")" || exit 1
  attic_login || exit 1
  attic push local:fleet "$path" || {
    log "push FAILED for $host; not publishing" >&2
    exit 1
  }
  publish "$host" "$path" "$rev" "$last_modified" || exit 1
  exit 0
fi

hosts="${UPDATE_CENTER_HOSTS:?UPDATE_CENTER_HOSTS must name the hosts to build}"

# Resolve main ONCE to an immutable rev so every build, every log line and
# every manifest describe the same candidate.
meta="$(nix flake metadata --json --refresh "$flake")" || {
  log "could not resolve $flake" >&2
  exit 1
}
rev="$(jq -er .url <<<"$meta")" || exit 1
last_modified="$(jq -er .lastModified <<<"$meta")" || exit 1
log "candidate $rev"

# ── Seed preflight (2026-09-13) ─────────────────────────────────────────────
# Private locked inputs (mecattaf/tally, mecattaf/tally-ts-sdk, and anything
# else mecattaf-owned) cannot be fetched here: there is no repo credential on
# the appliance. The coordinator's update-center-seed copies their exact trees
# in and roots them under $state/seeds. Name every gap BEFORE building, so a
# failed night reads "seed-missing tally-b" rather than a git auth error three
# hosts deep. A gap does not stop the loop: a host that does not need the tree
# may still build.
seeds_ok=1
while IFS=$'\t' read -r name nar url; do
  [ -n "$name" ] || continue
  path="$(nix-store --print-fixed-path --recursive sha256 \
    "$(nix hash convert --hash-algo sha256 --to nix32 "$nar")" source)"
  if nix-store --check-validity "$path" 2>/dev/null; then
    log "seed present: $name $path"
  else
    log "seed-missing $name $url ($path) — run update-center-seed on the coordinator" >&2
    seeds_ok=0
  fi
done < <(jq -r '
  .locks.nodes | to_entries[]
  | select(.value.locked != null) | .value.locked as $l
  | select(($l.type == "git" and ($l.url // "" | test("^https://github.com/mecattaf/")))
        or ($l.type == "github" and $l.owner == "mecattaf"))
  | [.key, $l.narHash, ($l.url // ("github:" + $l.owner + "/" + $l.repo)) + "@" + $l.rev]
  | @tsv' <<<"$meta")
[ "$seeds_ok" -eq 1 ] || log "preflight: private seeds incomplete; builds needing them will fail" >&2

attic_login || {
  log "could not log in to the local attic" >&2
  exit 1
}

fail=0
for host in $hosts; do
  log "building $host"
  if out="$(nix build --no-link --print-out-paths \
    "$rev#nixosConfigurations.$host.config.system.build.toplevel")"; then
    log "pushing $host ($out)"
    if ! attic push local:fleet "$out"; then
      log "push FAILED for $host; its candidate pointer is unchanged" >&2
      fail=1
    elif ! publish "$host" "$out" "$rev" "$last_modified"; then
      log "publish FAILED for $host; its candidate pointer is unchanged" >&2
      fail=1
    fi
  else
    log "build FAILED for $host; its candidate pointer is unchanged" >&2
    fail=1
  fi
done

exit $fail
