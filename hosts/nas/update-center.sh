#!/usr/bin/env bash
# The update center's nightly body (hosts/nas/update-center.nix carries the
# unit, the reasoning and the PATH). Kept as a file so tests/update-center
# can run it hermetically with fake nix/attic binaries first on PATH.
#
# Seams (all unset in the real unit):
#   UPDATE_CENTER_HOSTS        space-separated host list (the unit sets it)
#   UPDATE_CENTER_FLAKE        default github:mecattaf/dotfiles/main
set -u

hosts="${UPDATE_CENTER_HOSTS:?UPDATE_CENTER_HOSTS must name the hosts to build}"
flake="${UPDATE_CENTER_FLAKE:-github:mecattaf/dotfiles/main}"

log() { printf 'update-center: %s\n' "$*"; }

# Resolve main ONCE to an immutable rev so every build and every log line
# describe the same candidate.
meta="$(nix flake metadata --json --refresh "$flake")" || {
  log "could not resolve $flake" >&2
  exit 1
}
rev="$(jq -er .url <<<"$meta")" || exit 1
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

# Fresh short-lived push token, minted against the local atticd.
token="$(atticd-atticadm make-token --sub update-center --validity 1d \
  --pull fleet --push fleet)"
attic login local http://127.0.0.1:8080 "$token" >/dev/null

fail=0
for host in $hosts; do
  log "building $host"
  if out="$(nix build --no-link --print-out-paths \
    "$rev#nixosConfigurations.$host.config.system.build.toplevel")"; then
    log "pushing $host ($out)"
    if ! attic push local:fleet "$out"; then
      log "push FAILED for $host" >&2
      fail=1
    fi
  else
    log "build FAILED for $host" >&2
    fail=1
  fi
done

exit $fail
