#!/usr/bin/env bash
# hc-station against a real hc core (the fleet herdr-core), fully isolated.
#
#   ~/.local/bin/runtime-test -- bash tests/hc-station/smoke.sh     -> SMOKE_OK and a median
#
# It refuses to run outside runtime-test (pid 1 must be bwrap), and on top of
# that private /run/user the core gets its own HC_SESSION=test, runtime, state
# and config dirs under /var/tmp/hc-D12-<pid>.*, so no live core is ever
# addressed and no user manager is reachable (hc then starts its core with a
# plain setsid, which dies with the sandbox).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
station=$repo/home/dot_local/bin/hc-station
drive=$here/pty_drive.py
die() { echo "smoke: FAIL: $*" >&2; exit 1; }

[ "$(cat /proc/1/comm 2>/dev/null)" = bwrap ] || die "run me under ~/.local/bin/runtime-test (pid 1 is not bwrap)"
[ ! -e "/run/user/$(id -u)/systemd/private" ] || die "the live user manager is visible here"
[ -z "${HC_TERMINAL_ID:-}" ] || die "do not run inside an hc terminal"
bin=$(readlink -f "${HC_BIN:-/etc/profiles/per-user/$(id -un)/bin/herdr-core}")
[ -x "$bin" ] || die "no herdr-core at $bin"
case "$bin" in /nix/store/*) ;; *) die "want the fleet (Nix) herdr-core, not $bin" ;; esac
python=$(readlink -f "$(command -v python3)") || die "python3 missing"

root=$(mktemp -d "/var/tmp/hc-D12-$$.XXXX")
mkdir -p "$root"/{run,state,config/herdr-core,home,bin}
chmod 700 "$root" "$root/run"
cat >"$root/config/herdr-core/config.toml" <<'EOF'
shell = ["/bin/sh"]
headless = "120x40"
notes = true
history_mb = 8
EOF
# hc-station asks systemd only for the default session; this one never may.
printf '#!/bin/sh\necho "smoke: unexpected systemctl $*" >&2\nexit 1\n' >"$root/bin/systemctl"
# The fallback shell, so a fallback ends instead of waiting for input.
printf '#!/bin/sh\necho "FALLBACK_FISH $*"\n' >"$root/bin/fish"
chmod +x "$root/bin/systemctl" "$root/bin/fish"
# xterm-kitty for the sandbox HOME, so the Kitty identity path runs against the
# real core (on the NAS: kitty.terminfo in the system, else the old ~/.terminfo).
kitty_terminfo=""
for f in /run/current-system/sw/share/terminfo/x/xterm-kitty "$HOME/.terminfo/x/xterm-kitty"; do
  [ -r "$f" ] && { kitty_terminfo=$f; break; }
done
if [ -n "$kitty_terminfo" ]; then
  mkdir -p "$root/home/.terminfo/x" && cp "$kitty_terminfo" "$root/home/.terminfo/x/"
fi

hcenv=(env -i "PATH=$root/bin:$(dirname "$python"):$(dirname "$bin"):/run/current-system/sw/bin"
  "HOME=$root/home" "USER=$(id -un)" LANG=C.UTF-8 TERM=xterm-256color HC_SESSION=test
  "XDG_RUNTIME_DIR=$root/run" "XDG_STATE_HOME=$root/state" "XDG_CONFIG_HOME=$root/config"
  HC_SETTLE_MS=0 "HC_BIN=$bin")
hc() { "${hcenv[@]}" "$bin" "$@"; }
drive() { "${hcenv[@]}" "$python" "$drive" "$@"; }
# field JSON EXPR: evaluate EXPR on the parsed JSON `d`; strings print raw, the rest as JSON.
field() {
  "$python" -c 'import json,sys; r=eval(sys.argv[2], {}, {"d": json.loads(sys.argv[1])}); print(r if isinstance(r, str) else json.dumps(r))' "$1" "$2"
}

cleanup() {
  hc server stop >/dev/null 2>&1 || true
  rm -rf "$root"
}
trap cleanup EXIT

echo "== core: $bin"
hc server start >/dev/null
status=$(hc server status --json)
[ "$(field "$status" 'd["version"]')" = 0.1.22 ] || die "core version: $status"
echo "   $(field "$status" '{k: d.get(k) for k in ("version", "installed_by", "live")}')"
[ -S "$root/run/herdr-core/test.sock" ] || die "no socket at $root/run/herdr-core/test.sock"

echo "== a station runs its program, then attach reports it finished"
out=$(drive --timeout 20 -- "$python" "$station" new --no-fallback --kitty-version 0.50.0 \
  -- sh -c 'echo STATION_OK; sleep 1')
text=$(field "$out" 'd["output"]')
grep -q STATION_OK <<<"$text" || die "no STATION_OK: $out"
grep -Eq '\[t[0-9a-z]+ finished' <<<"$text" || die "no finished line: $out"
echo "   STATION_OK; $(grep -Eo '\[t[0-9a-z]+ finished[^]]*\]' <<<"$text" | head -1); rc=$(field "$out" 'd["rc"]')"
listing=$(hc ls --all --json --label ui=kitty)
[ "$(field "$listing" 'len(d["terminals"])')" = 1 ] || die "ls --all --label ui=kitty: $listing"
first=$(hc get "$(field "$listing" 'd["terminals"][0]["address"]')" --json)
want="{\"kind\": \"agent\", \"owner\": \"$(id -un)\", \"ui\": \"kitty\"}"
[ "$(field "$first" 'dict(sorted(d["labels"].items()))')" = "$want" ] || die "labels: $first"
identity=$(field "$first" 'd.get("identity")')
if [ -n "$kitty_terminfo" ]; then
  [ "$identity" = "kitty 0.50.0" ] || die "identity $identity, want kitty 0.50.0 (terminfo from $kitty_terminfo)"
else
  echo "   (no xterm-kitty terminfo here: the Kitty identity path was not exercised)"
fi
echo "   labels $want; identity $identity"

echo "== closing the window (SIGHUP to attach) only detaches"
out=$(drive --timeout 15 --hup-after 2 -- "$python" "$station" new --no-fallback --label smoke=hup -- sleep 300)
grep -q 'detached from' <<<"$(field "$out" 'd["output"]')" || die "no detach line: $out"
live=$(hc ls --json --label smoke=hup)
[ "$(field "$live" 'len(d["terminals"])')" = 1 ] || die "the station is gone: $live"
[ "$(field "$live" 'd["terminals"][0]["state"]')" = live ] || die "not live: $live"
address=$(field "$live" 'd["terminals"][0]["address"]')
echo "   $address still live after SIGHUP"
hc kill "$address" >/dev/null

echo "== unavailable hc: one line, then the plain shell"
out=$(drive --timeout 15 -- env HC_SESSION=nosuch "$python" "$station" new --cwd "$root/home")
text=$(field "$out" 'd["output"]')
grep -q 'hc-station: hc unavailable (no core): plain fish, not persistent' <<<"$text" || die "no banner: $out"
grep -q 'FALLBACK_FISH --login --interactive' <<<"$text" || die "no fallback shell: $out"
echo "   banner and fallback shell seen"

echo "== new to first output, five times (ms; DA1 answered at once, as Kitty does)"
times=()
for n in 1 2 3 4 5; do
  out=$(drive --timeout 15 --until "FIRST_$n" -- "$python" "$station" new --no-fallback \
    -- sh -c "echo FIRST_$n; sleep 0.2")
  ms=$(field "$out" 'd["until_ms"]')
  [ "$ms" != null ] || die "run $n never printed FIRST_$n: $out"
  times+=("$ms")
  echo "   run $n: first byte $(field "$out" 'd["first_byte_ms"]') ms, program output $ms ms"
done
median=$(printf '%s\n' "${times[@]}" | sort -n | sed -n 3p)
echo "   median new -> program output: $median ms"

hc server stop >/dev/null
[ ! -e "$root/run/herdr-core/test.sock" ] || die "socket left after server stop"
echo "SMOKE_OK median_ms=$median"
