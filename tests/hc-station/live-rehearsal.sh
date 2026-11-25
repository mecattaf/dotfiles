#!/usr/bin/env bash
# The Mod+Enter rehearsal against the DECLARED live hc core on the NAS (plan P1 D20 step 7).
#
#   bash tests/hc-station/live-rehearsal.sh      -> REHEARSAL_OK, MODENTER_OK, exit 0
#
# For the orchestrator, after the hc cutover only. It refuses unless hc-core.service is
# active and its socket answers, and never runs a CLI call that could autostart a core:
# every herdr-core call gets a clean environment, after the socket was seen answering.
# It opens two stations labelled seat=rehearsal-<pid> (one through hc-station, one through
# domicile-terminal -> ssh -> the NAS's ~/.local/bin/hc-station) and removes exactly those.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
station=$repo/home/dot_local/bin/hc-station
terminal=$repo/home/dot_local/bin/domicile-terminal
drive=$here/pty_drive.py
die() { echo "rehearsal: FAIL: $*" >&2; exit 1; }
refuse() { echo "rehearsal: REFUSED: $*" >&2; exit 2; }

uid=$(id -u)
user=$(id -un)
bin=/etc/profiles/per-user/$user/bin/herdr-core
sock=/run/user/$uid/herdr-core/default.sock
[ -z "${HC_SESSION:-}" ] || refuse "HC_SESSION is set: this rehearsal is for the default session only"
[ -z "${HC_SOCKET:-}" ] || refuse "HC_SOCKET is set: this rehearsal is for the default socket only"
[ "$(cat /proc/1/comm 2>/dev/null)" != bwrap ] || refuse "inside runtime-test: this addresses the live core; run it outside"
[ "$(systemctl --user is-active hc-core.service 2>/dev/null || true)" = active ] || refuse "hc-core.service is not active"
[ -x "$bin" ] || refuse "no fleet herdr-core at $bin"
python=$(readlink -f "$(command -v python3)") || refuse "python3 missing"
"$python" -c 'import socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(2); s.connect(sys.argv[1])' "$sock" 2>/dev/null \
  || refuse "nothing answers on $sock (a CLI call would autostart a core)"

clean=(env -i "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/$user/bin" "HOME=$HOME" "USER=$user"
  "LOGNAME=$user" "LANG=${LANG:-C.UTF-8}" "XDG_RUNTIME_DIR=/run/user/$uid" TERM=xterm-256color)
hc() { "${clean[@]}" "$bin" "$@"; }
drive() { "${clean[@]}" "$python" "$drive" "$@"; }
field() {
  "$python" -c 'import json,sys; r=eval(sys.argv[2], {}, {"d": json.loads(sys.argv[1])}); print(r if isinstance(r, str) else json.dumps(r))' "$1" "$2"
}
seat=rehearsal-$$
cleanup() {
  local listing address state
  listing=$(hc ls --all --json --label "seat=$seat" 2>/dev/null) || return 0
  for address in $(field "$listing" '" ".join(t["address"] for t in d["terminals"])'); do
    state=$(field "$listing" "[t['state'] for t in d['terminals'] if t['address'] == '$address'][0]")
    [ "$state" = finished ] || hc kill "$address" >/dev/null 2>&1 || true
    hc rm "$address" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

status=$(hc server status --json)
echo "core: $(field "$status" '{k: d.get(k) for k in ("version", "installed_by", "live", "finished")}')"

echo "== hc-station new on the live core"
out=$(drive --timeout 20 -- "$python" "$station" new --no-fallback --label "seat=$seat" \
  -- sh -c 'echo REHEARSAL_OK; sleep 2')
grep -q REHEARSAL_OK <<<"$(field "$out" 'd["output"]')" || die "no REHEARSAL_OK: $out"
listing=$(hc ls --all --json --label "seat=$seat")
[ "$(field "$listing" 'len(d["terminals"])')" = 1 ] || die "ls --label seat=$seat: $listing"
info=$(hc get "$(field "$listing" 'd["terminals"][0]["address"]')" --json)
[ "$(field "$info" 'd["labels"].get("ui")')" = kitty ] || die "labels: $info"
[ "$(field "$info" 'd["labels"].get("owner")')" = "$user" ] || die "labels: $info"
echo "REHEARSAL_OK labels=$(field "$info" 'd["labels"]') identity=$(field "$info" 'd.get("identity")') ms=$(field "$out" 'd["until_ms"]')"

echo "== domicile-terminal from the NAS (ssh -> ~/.local/bin/hc-station -> hc attach)"
# The typed line shows MODENTER_(echo OK); only its execution prints MODENTER_OK.
out=$(drive --timeout 45 --until MODENTER_OK --send 'echo MODENTER_(echo OK); exit\r' --send-after 5 \
  -- "$python" "$terminal" --seat "$seat")
text=$(field "$out" 'd["output"]')
grep -q MODENTER_OK <<<"$text" || die "no MODENTER_OK (rc $(field "$out" 'd["rc"]')): $text"
grep -q 'plain fish, not persistent' <<<"$text" && die "Mod+Enter fell back to a plain fish: $text"
listing=$(hc ls --all --json --label "seat=$seat")
[ "$(field "$listing" 'len(d["terminals"])')" = 2 ] || die "want 2 rehearsal stations: $listing"
echo "MODENTER_OK rc=$(field "$out" 'd["rc"]') ms=$(field "$out" 'd["until_ms"]')"

cleanup
trap - EXIT
left=$(hc ls --all --json --label "seat=$seat")
[ "$(field "$left" 'len(d["terminals"])')" = 0 ] || die "rehearsal stations left: $left"
echo "live terminals now: $(field "$(hc ls --json)" 'len(d["terminals"])')"
echo "REHEARSAL_DONE"
