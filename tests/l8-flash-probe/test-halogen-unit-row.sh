#!/usr/bin/env bash
# tests/l8-flash-probe/test-halogen-unit-row.sh — the probe's two rows on the
# worker's podman-halogen.service, exercised in every state they can be in.
#
# The fleet's one inference serve is the worker's podman-halogen.service
# (modules/halogen.nix), and the probe reads it on the worker's own system bus:
# directly when it runs there, over `ssh worker` from anywhere else. Three
# outcomes are possible and each is pinned here by VERDICT, not wording:
#
#   PASS / FAIL  the unit was measured (active or not; Restart=on-failure or not)
#   UNKNOWN      the worker's bus was out of reach (no ssh, or ssh refused) —
#                nothing was measured, so the row is neither green nor red
#
# Hermetic: a fake `systemctl` answers `is-active` and `show -p Restart` out of
# two files this test writes; a fake `ssh` either refuses (exit 255, ssh's own
# code for a connection it could not make) or forwards its trailing argv to
# that same fake systemctl, standing in for the worker's bus. L8_FLASH_HOST
# selects the box. The probe never sets -e, so its other rows failing under
# the fakes is expected and irrelevant — only the two target rows are read.
set -euo pipefail

PROBE="${L8_FLASH_PROBE:-$(cd "$(dirname "$0")/../.." && pwd)/home/dot_local/bin/l8-flash-probe}"
test -r "$PROBE" || { echo "no probe at $PROBE" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/unit"
BASH_ABS="$(command -v bash)"

# The fake systemctl: `is-active <unit>` prints $UNIT_STATE/active and exits 0
# only for "active" (3 otherwise, as systemd does); `show <unit> -p Restart`
# prints $UNIT_STATE/restart verbatim. Every other verb is refused.
cat > "$tmp/bin/systemctl" <<FAKE
#!$BASH_ABS
FAKE
cat >> "$tmp/bin/systemctl" <<'FAKE'
case "${1:-}" in
  is-active)
    state="$(cat "$UNIT_STATE/active" 2>/dev/null || true)"
    printf '%s\n' "${state:-inactive}"
    [ "$state" = active ] && exit 0 || exit 3 ;;
  show)
    for arg in "$@"; do [ "$arg" = Restart ] && { cat "$UNIT_STATE/restart" 2>/dev/null || true; exit 0; }; done
    exit 1 ;;
esac
exit 1
FAKE
chmod 755 "$tmp/bin/systemctl"

# The fake ssh: $SSH_MODE=refuse exits 255 without reading its argv;
# $SSH_MODE=forward drops the options and host and runs the rest locally.
cat > "$tmp/bin/ssh" <<FAKE
#!$BASH_ABS
FAKE
cat >> "$tmp/bin/ssh" <<'FAKE'
[ "${SSH_MODE:-refuse}" = forward ] || exit 255
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift   # the host
exec "$@"
FAKE
chmod 755 "$tmp/bin/ssh"

UNIT_STATE="$tmp/unit"
export UNIT_STATE

unit() { # $1 = is-active answer, $2 = Restart= line
  printf '%s\n' "$1" > "$UNIT_STATE/active"
  printf '%s\n' "$2" > "$UNIT_STATE/restart"
}

run() { # $1 = host, $2 = ssh mode; prints the whole probe run
  PATH="$tmp/bin:$PATH" HOME="$tmp/home" L8_FLASH_HOST="$1" SSH_MODE="$2" \
    bash "$PROBE" 2>/dev/null || true
}

row() { # $1 = run output, $2 = row text; prints that row's verdict
  printf '%s\n' "$1" | grep -F "$2" | awk '{print $1}'
}

ACTIVE_ROW='podman-halogen.service active'
RESTART_ROW='podman-halogen.service Restart=on-failure'

fails=0
check() { # $1 = name, $2 = want, $3 = got
  if [ "$2" = "$3" ]; then
    printf 'ok   %-56s %s\n' "$1" "$2"
  else
    printf 'FAIL %-56s want %s got %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# ── 1. on the worker, the declared state: active, Restart=on-failure ───────
unit active 'Restart=on-failure'
out="$(run worker refuse)"
check "worker, unit up -> active PASS" PASS "$(row "$out" "$ACTIVE_ROW")"
check "worker, unit up -> restart PASS" PASS "$(row "$out" "$RESTART_ROW")"

# ── 2. on the worker, the unit down and its policy missing ─────────────────
unit inactive 'Restart=no'
out="$(run worker refuse)"
check "worker, unit down -> active FAIL" FAIL "$(row "$out" "$ACTIVE_ROW")"
check "worker, Restart=no -> restart FAIL" FAIL "$(row "$out" "$RESTART_ROW")"

# ── 3. off the worker, the bus reached over ssh: measured, not guessed ─────
unit active 'Restart=on-failure'
out="$(run coordinator forward)"
check "coordinator, ssh forwards -> active PASS" PASS "$(row "$out" "$ACTIVE_ROW")"
check "coordinator, ssh forwards -> restart PASS" PASS "$(row "$out" "$RESTART_ROW")"
unit inactive 'Restart=on-failure'
out="$(run coordinator forward)"
check "coordinator, ssh forwards, unit down -> FAIL" FAIL "$(row "$out" "$ACTIVE_ROW")"

# ── 4. off the worker with the worker unreachable: UNKNOWN, never a verdict ─
unit active 'Restart=on-failure'
out="$(run coordinator refuse)"
check "coordinator, ssh refused -> active UNKNOWN" UNKNOWN "$(row "$out" "$ACTIVE_ROW")"
check "coordinator, ssh refused -> restart UNKNOWN" UNKNOWN "$(row "$out" "$RESTART_ROW")"
n="$(printf '%s\n' "$out" | grep -c 'podman-halogen.service')"
check "exactly 2 halogen rows" 2 "$n"

# ── 5. the run's exit is not decided by an UNKNOWN row ─────────────────────
# Everything else fails under the fakes, so the exit is 1 regardless; what is
# pinned is that the summary counts the unknowns instead of folding them in.
summary="$(printf '%s\n' "$out" | grep -F 'l8-flash-probe:' | tail -1)"
case "$summary" in
  *" 2 unknown "*) check "summary counts 2 unknown" yes yes ;;
  *) check "summary counts 2 unknown" yes "no ($summary)" ;;
esac

total=11
echo "$((total - fails))/$total cases passed"
test "$fails" -eq 0
