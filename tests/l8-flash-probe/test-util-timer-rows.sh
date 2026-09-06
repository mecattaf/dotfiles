#!/usr/bin/env bash
# tests/l8-flash-probe/test-util-timer-rows.sh — the probe's two UTIL-01 rows,
# exercised BOTH ways (dotfiles#320, #311).
#
# Like the hand-written-pair row, these two rows are RED on the day they are
# written: nothing has switched yet, so `util-sampler.timer` and
# `util-row.timer` have no fragment at all and both rows FAIL. A row that is
# red on the day it lands is exactly the row nobody notices is broken, so it is
# tested here in every state it can be in, and the test asserts the VERDICT,
# not the wording.
#
# Hermetic: a fake `systemctl` earlier on PATH answers `--user show <unit> -p
# FragmentPath --value` out of a table this test writes, L8_FLASH_HOST selects
# the box, and no real systemd, tally or network call decides any assertion.
# The probe never sets -e, so its other rows failing under the fake systemctl
# is expected and irrelevant — only the two target rows are read.
set -euo pipefail

PROBE="${L8_FLASH_PROBE:-$(cd "$(dirname "$0")/../.." && pwd)/home/dot_local/bin/l8-flash-probe}"
test -r "$PROBE" || { echo "no probe at $PROBE" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── the fake systemctl ─────────────────────────────────────────────────────
# It answers FragmentPath from $FRAGMENTS/<unit> (absent file = empty value,
# which is what systemd prints for a unit it has never heard of) and refuses
# every other verb, so nothing else in the probe can accidentally pass.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
unit=""
want_fragment=0
for arg in "$@"; do
  case "$arg" in
    -p) ;;
    FragmentPath) want_fragment=1 ;;
    *.timer|*.service) unit="$arg" ;;
  esac
done
if [ "$want_fragment" = "1" ] && [ -n "$unit" ]; then
  cat "$FRAGMENTS/$unit" 2>/dev/null || true
  exit 0
fi
exit 1
FAKE
chmod 755 "$tmp/bin/systemctl"

FRAGMENTS="$tmp/fragments"
export FRAGMENTS
mkdir -p "$FRAGMENTS"

fragment() { # $1 = unit, $2 = value ("" = the unit does not exist)
  if [ -n "$2" ]; then printf '%s\n' "$2" > "$FRAGMENTS/$1"; else rm -f "$FRAGMENTS/$1"; fi
}

run() { # $1 = host; prints the whole probe run
  PATH="$tmp/bin:$PATH" HOME="$tmp/home" L8_FLASH_HOST="$1" bash "$PROBE" 2>/dev/null || true
}

row() { # $1 = run output, $2 = unit; prints that unit's verdict
  printf '%s\n' "$1" | grep -F " $2 declared" | awk '{print $1}'
}

mkdir -p "$tmp/home"

fails=0
check() { # $1 = name, $2 = want, $3 = got
  if [ "$2" = "$3" ]; then
    printf 'ok   %-52s %s\n' "$1" "$2"
  else
    printf 'FAIL %-52s want %s got %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

STORE="/nix/store/8w0ky4v0p3g0000000000000000000-home-manager-files/share/systemd/user"

# ── 1. pre-switch: neither unit exists — the state on the box today ────────
fragment util-sampler.timer ""
fragment util-row.timer ""
out="$(run coordinator)"
check "pre-switch: util-sampler.timer -> FAIL" FAIL "$(row "$out" util-sampler.timer)"
check "pre-switch: util-row.timer -> FAIL"     FAIL "$(row "$out" util-row.timer)"
# The count the issue names: exactly two rows come from this section, so the
# probe gains exactly two FAIL rows on the coordinator and no more.
n="$(printf '%s\n' "$out" | grep -cE ' (util-sampler|util-row)\.timer declared')"
check "pre-switch: exactly 2 util rows" 2 "$n"

# ── 2. post-switch: both fragments under /nix/store ────────────────────────
fragment util-sampler.timer "$STORE/util-sampler.timer"
fragment util-row.timer "$STORE/util-row.timer"
out="$(run coordinator)"
check "declared: util-sampler.timer -> PASS" PASS "$(row "$out" util-sampler.timer)"
check "declared: util-row.timer -> PASS"     PASS "$(row "$out" util-row.timer)"

# ── 3. hand-installed: a fragment outside the store is the Rule 9 failure ──
# These units have never existed by hand and must not. A plain file in
# ~/.config/systemd/user wins the name over the declaration and the switch
# still reports success, so "the unit exists" must never be enough.
fragment util-sampler.timer "$tmp/home/.config/systemd/user/util-sampler.timer"
fragment util-row.timer "$STORE/util-row.timer"
out="$(run coordinator)"
check "hand-installed sampler -> FAIL" FAIL "$(row "$out" util-sampler.timer)"
check "hand-installed sampler leaves row writer PASS" PASS "$(row "$out" util-row.timer)"

# ── 4. the worker: the sampler runs there, the row writer does not ─────────
# util-sampler.timer is declared on BOTH boxes, so its row is real off the
# coordinator; util-row.timer is coordinator-gated (it pulls the worker's log),
# so its row is SKIP there and must never FAIL.
fragment util-sampler.timer "$STORE/util-sampler.timer"
fragment util-row.timer ""
out="$(run worker)"
check "worker: util-sampler.timer -> PASS" PASS "$(row "$out" util-sampler.timer)"
check "worker: util-row.timer -> SKIP"     SKIP "$(row "$out" util-row.timer)"

# ── 5. the worker with no sampler either: still FAIL, not SKIP ─────────────
fragment util-sampler.timer ""
out="$(run worker)"
check "worker pre-switch: util-sampler.timer -> FAIL" FAIL "$(row "$out" util-sampler.timer)"

total=10
echo "$((total - fails))/$total cases passed"
test "$fails" -eq 0
