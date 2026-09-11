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
# FragmentPath --value` out of a table this test writes, a fake `ssh` beside it
# refuses every connection (so the probe's worker row reports UNKNOWN rather
# than dialling a real box), L8_FLASH_HOST selects the box, and no real
# systemd, tally or network call decides any assertion.
#
# The fixtures are SYMLINK-SHAPED on purpose (dotfiles#331). A declared unit's
# FragmentPath is the link home-manager wrote into ~/.config/systemd/user, not
# the store path behind it, so a table of bare /nix/store strings tested a shape
# that never occurs on a box and let the probe ship a glob that called every
# declared unit hand-installed. Each "declared" case here installs a real
# symlink in a fake ~/.config/systemd/user and hands the probe THAT path; the
# hand-installed case hands it a plain file in the same directory, which is the
# only shape that must stay RED.
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
# Shebang: the interpreter this test is ITSELF running under, by absolute path.
# `#!/usr/bin/env bash` is unrunnable inside the nix build sandbox — there is no
# /usr/bin there — so the fake exec'd nothing, every FragmentPath came back
# empty, and the four cases that assert PASS failed for a reason that had
# nothing to do with the probe.
BASH_ABS="$(command -v bash)"
cat > "$tmp/bin/systemctl" <<FAKE
#!$BASH_ABS
FAKE
cat >> "$tmp/bin/systemctl" <<'FAKE'
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
printf '#!%s\nexit 255\n' "$BASH_ABS" > "$tmp/bin/ssh"
chmod 755 "$tmp/bin/ssh"

FRAGMENTS="$tmp/fragments"
export FRAGMENTS
mkdir -p "$FRAGMENTS"

fragment() { # $1 = unit, $2 = value ("" = the unit does not exist)
  if [ -n "$2" ]; then printf '%s\n' "$2" > "$FRAGMENTS/$1"; else rm -f "$FRAGMENTS/$1"; fi
}

# A real, existing /nix/store file to stand in for a unit fragment. It must
# EXIST, because the probe resolves with `readlink -f`, and it must be a store
# path in both places this test runs (the nix sandbox and a NixOS checkout) —
# the interpreter's own store path is both.
STORE_FILE="$(readlink -f "$BASH_ABS")"
case "$STORE_FILE" in
  /nix/store/*) ;;
  *) echo "no /nix/store path to stand in for a fragment (bash resolved to '$STORE_FILE')" >&2; exit 1 ;;
esac

UNITDIR="$tmp/home/.config/systemd/user"
mkdir -p "$UNITDIR"

declared_link() { # $1 = unit; installs the home-manager-shaped symlink, echoes it
  ln -sfn "$STORE_FILE" "$UNITDIR/$1"
  printf '%s' "$UNITDIR/$1"
}

hand_installed_file() { # $1 = unit; installs the plain file, echoes it
  rm -f "$UNITDIR/$1"
  printf '# hand-written\n' > "$UNITDIR/$1"
  printf '%s' "$UNITDIR/$1"
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

# ── 2. post-switch: both shapes a declared fragment really takes ───────────
# The sampler gets the shape systemd actually prints for a home-manager user
# unit — the symlink in ~/.config/systemd/user (measured: #331) — and the row
# writer gets a bare store path, the shape the probe used to be the only one it
# accepted. Both are declared and both must PASS.
fragment util-sampler.timer "$(declared_link util-sampler.timer)"
fragment util-row.timer "$STORE_FILE"
out="$(run coordinator)"
check "declared: util-sampler.timer -> PASS" PASS "$(row "$out" util-sampler.timer)"
check "declared: util-row.timer -> PASS"     PASS "$(row "$out" util-row.timer)"

# ── 3. hand-installed: a fragment outside the store is the Rule 9 failure ──
# These units have never existed by hand and must not. A plain file in
# ~/.config/systemd/user wins the name over the declaration and the switch
# still reports success, so "the unit exists" must never be enough.
fragment util-sampler.timer "$(hand_installed_file util-sampler.timer)"
fragment util-row.timer "$(declared_link util-row.timer)"
out="$(run coordinator)"
check "hand-installed sampler -> FAIL" FAIL "$(row "$out" util-sampler.timer)"
check "hand-installed sampler leaves row writer PASS" PASS "$(row "$out" util-row.timer)"

# ── 4. the worker: the sampler runs there, the row writer does not ─────────
# util-sampler.timer is declared on BOTH boxes, so its row is real off the
# coordinator; util-row.timer is coordinator-gated (it pulls the worker's log),
# so its row is SKIP there and must never FAIL.
fragment util-sampler.timer "$(declared_link util-sampler.timer)"
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
