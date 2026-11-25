#!/usr/bin/env bash
# tests/hc-core/smoke.sh: the repo's hc config and hc-restart-clean against a
# private, throwaway core of the fleet's herdr-core (0.1.22).
#
#   ~/.local/bin/runtime-test -- bash tests/hc-core/smoke.sh       # prints SMOKE_OK
#
# Phase 1, an isolated core (S2 §15.3): HC_SESSION=test and private XDG dirs under
#   /var/tmp/hc-D11-<pid>, the repo's home/dot_config/herdr-core/config.toml.
#   server start / status report the expected version and installed_by nix; a
#   terminal that reports OSC 7501 working, then done, shows both through
#   `ls --json`; server stop ends the core and removes its socket.
# Phase 2, hc-restart-clean: a default-session core under a private HOME (the
#   helper always means the default session), one live terminal; the helper
#   replaces the core (new pid) and the terminal is still live afterwards.
#
# Refuses to run outside runtime-test (pid 1 must be bwrap, no systemd/private and
# no herdr-core/ in /run/user/<uid>): it must never reach a live core. Every
# process it starts carries HOME=<root>; the exit trap kills those and removes
# the root. Env knobs: HC_SMOKE_EXPECT (default 0.1.22).
set -euo pipefail

die() {
  echo "smoke: $*" >&2
  exit 1
}

uid=$(id -u)
user=$(id -un)
[ "$(cat /proc/1/comm 2>/dev/null)" = bwrap ] || die "run me under ~/.local/bin/runtime-test (pid 1 is not bwrap)"
[ ! -e "/run/user/$uid/systemd/private" ] || die "/run/user/$uid is the live runtime dir"
[ ! -e "/run/user/$uid/herdr-core" ] || die "/run/user/$uid/herdr-core exists in this namespace"

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
config="$repo/home/dot_config/herdr-core/config.toml"
helper="$repo/home/dot_local/bin/hc-restart-clean"
hc="/etc/profiles/per-user/$user/bin/herdr-core"
jq="/etc/profiles/per-user/$user/bin/jq"
expect=${HC_SMOKE_EXPECT:-0.1.22}
[ -x "$hc" ] || die "no fleet herdr-core at $hc"
[ -x "$jq" ] || die "no jq at $jq"
[ -r "$config" ] || die "missing $config"
[ -r "$helper" ] || die "missing $helper"

root="/var/tmp/hc-D11-$$"
mkdir -m 0700 "$root" || die "cannot create $root"

pids_of_root() {
  local d
  for d in /proc/[0-9]*; do
    [ "${d#/proc/}" = "$$" ] && continue
    if { tr '\0' '\n' <"$d/environ"; } 2>/dev/null | grep -qxF "HOME=$root"; then
      echo "${d#/proc/}"
    fi
  done
}
cleanup() {
  local code=$? left
  left=$(pids_of_root | tr '\n' ' ')
  if [ -n "$left" ]; then
    echo "smoke: killing leftovers: $left" >&2
    # shellcheck disable=SC2086
    kill -9 $left 2>/dev/null || true
  fi
  case "$root" in /var/tmp/hc-D11-*) rm -rf -- "$root" ;; esac
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -m 0700 "$root/run" "$root/state" "$root/config"
base=(
  "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/$user/bin"
  "HOME=$root" "USER=$user" "LOGNAME=$user" "LANG=C.UTF-8"
  "XDG_RUNTIME_DIR=$root/run" "HC_SETTLE_MS=0"
)
p1=("${base[@]}" "HC_SESSION=test" "XDG_STATE_HOME=$root/state" "XDG_CONFIG_HOME=$root/config")
h1() { env -i "${p1[@]}" "$hc" "$@"; }
h2() { env -i "${base[@]}" "$hc" "$@"; }
field() { "$jq" -r "$1"; }

# ---------------- phase 1: an isolated core with the repo's config ----------------
install -D -m 0644 "$config" "$root/config/herdr-core/config.toml"

start=$(h1 --json server start)
[ "$(field .version <<<"$start")" = "$expect" ] || die "server start: version is not $expect: $start"
status=$(h1 --json server status)
[ "$(field .version <<<"$status")" = "$expect" ] || die "server status: $status"
[ "$(field .installed_by <<<"$status")" = nix ] || die "server status: installed_by is not nix: $status"
[ -S "$root/run/herdr-core/test.sock" ] || die "no socket at $root/run/herdr-core/test.sock"
echo "smoke: phase 1 core up: version $expect pid $(field .pid <<<"$status")"

cat >"$root/osc-worker.sh" <<'SH'
printf '\033]7501;state=working\033\\'
sleep 1
printf '\033]7501;state=done\033\\'
sleep 3
SH
h1 --json run --bg --name osc --label smoke=d11 --cwd "$root" -- \
  /run/current-system/sw/bin/sh "$root/osc-worker.sh" >"$root/run-osc.json"
seen=""
for _ in $(seq 1 80); do
  # ls reports a terminal's root status as a string ("working"); `get` has the full record.
  state=$(h1 --json ls --label smoke=d11 | field '[.terminals[] | select(.name == "osc") | ((if (.status | type) == "object" then .status.state else .status end) // "none")][0] // "gone"')
  case " $seen " in *" $state "*) ;; *) seen="$seen $state" ;; esac
  [ "$state" = "done" ] && break
  sleep 0.1
done
case "$seen" in *working*done*) ;; *) die "OSC 7501 states seen through ls --json:$seen (want working, then done)" ;; esac
echo "smoke: phase 1 OSC 7501 through ls --json:$seen"

stop=$(h1 --json server stop)
[ "$(field .stopped <<<"$stop")" = true ] || die "server stop: $stop"
for _ in $(seq 1 50); do [ -S "$root/run/herdr-core/test.sock" ] || break; sleep 0.1; done
[ ! -S "$root/run/herdr-core/test.sock" ] || die "socket still there after server stop"
echo "smoke: phase 1 server stop ok"

# ---------------- phase 2: hc-restart-clean keeps a live terminal ----------------
# Default session, state and config under the private HOME (no XDG_*_HOME), so the
# helper, which passes neither HC_SESSION nor XDG_*_HOME, finds this core.
install -D -m 0644 "$config" "$root/.config/herdr-core/config.toml"
before=$(h2 --json server start)
pid_before=$(field .pid <<<"$before")
[ -S "$root/run/herdr-core/default.sock" ] || die "no socket at $root/run/herdr-core/default.sock"
h2 --json run --bg --name survivor --cwd "$root" -- /run/current-system/sw/bin/sleep 300 >"$root/run-survivor.json"

env -i "${base[@]}" /run/current-system/sw/bin/sh "$helper" --json >"$root/restart.json" \
  || die "hc-restart-clean failed: $(cat "$root/restart.json")"
after=$(h2 --json server status)
pid_after=$(field .pid <<<"$after")
[ "$(field .version <<<"$after")" = "$expect" ] || die "after restart: $after"
[ "$pid_after" != "$pid_before" ] || die "hc-restart-clean did not replace the core (pid $pid_before)"
survivor=$(h2 --json ls | field '[.terminals[] | select(.name == "survivor") | .state][0] // "gone"')
[ "$survivor" = live ] || die "the survivor terminal is $survivor after hc-restart-clean"
echo "smoke: phase 2 hc-restart-clean: core pid $pid_before -> $pid_after, terminal survivor $survivor"

# A refusal inside an hc terminal, without touching the core.
if env -i "${base[@]}" HC_TERMINAL_ID=t99 /run/current-system/sw/bin/sh "$helper" 2>"$root/refuse.err"; then
  die "hc-restart-clean ran with HC_TERMINAL_ID set"
fi
grep -q 'refusing inside hc terminal t99' "$root/refuse.err" || die "unexpected refusal text: $(cat "$root/refuse.err")"

stop=$(h2 --json server stop)
[ "$(field .stopped <<<"$stop")" = true ] || die "phase 2 server stop: $stop"
echo SMOKE_OK
