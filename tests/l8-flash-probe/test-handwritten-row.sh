#!/usr/bin/env bash
# tests/l8-flash-probe/test-handwritten-row.sh — the probe's hand-written-pair
# row, exercised BOTH ways (dotfiles#319, #293).
#
# The row that matters is the one that will still be FAILing on the coordinator
# when this lands, because its subject is Tom's shell act in P05 walkthrough
# step 4 (DEFERRED.md DF-U-D16-1). A row that is red on the day it is written is
# exactly the row nobody notices is broken, so it is tested here against a fake
# HOME in both states, and the test asserts the VERDICT, not the wording.
#
# Hermetic: a temp HOME, L8_FLASH_HOST=coordinator so the coordinator-only
# branch is taken on any box and inside the nix sandbox, and no systemd, tally
# or network call is consulted for this row. The probe never sets -e, so its
# other rows failing in the sandbox is expected and irrelevant — only the
# target row is read.
set -euo pipefail

PROBE="${L8_FLASH_PROBE:-$(cd "$(dirname "$0")/../.." && pwd)/home/dot_local/bin/l8-flash-probe}"
test -r "$PROBE" || { echo "no probe at $PROBE" >&2; exit 1; }

ROW='hand-written pair gone'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run() { # $1 = fake HOME; prints the target row's line
  HOME="$1" L8_FLASH_HOST=coordinator bash "$PROBE" 2>/dev/null \
    | grep -F "$ROW" || true
}

verdict() { printf '%s\n' "$1" | awk '{print $1}'; }

fails=0
check() { # $1 = name, $2 = want, $3 = got, $4 = whole line
  if [ "$2" = "$3" ]; then
    printf 'ok   %-44s %s\n' "$1" "$4"
  else
    printf 'FAIL %-44s want %s got %s: %s\n' "$1" "$2" "$3" "$4"
    fails=$((fails + 1))
  fi
}

# ── 1. the pair present as plain files: the state on the coordinator today ──
h1="$tmp/present"; mkdir -p "$h1/.config/systemd/user"
printf '[Unit]\n' > "$h1/.config/systemd/user/claude-transcript-mirror.service"
printf '[Unit]\n' > "$h1/.config/systemd/user/claude-transcript-mirror.timer"
line="$(run "$h1")"
check "pair present -> FAIL" FAIL "$(verdict "$line")" "$line"

# ── 2. the service alone: a half-done deletion must not read as done ────────
h2="$tmp/half"; mkdir -p "$h2/.config/systemd/user"
printf '[Unit]\n' > "$h2/.config/systemd/user/claude-transcript-mirror.timer"
line="$(run "$h2")"
check "timer alone -> FAIL" FAIL "$(verdict "$line")" "$line"

# ── 3. both gone: what step 4 produces ─────────────────────────────────────
h3="$tmp/gone"; mkdir -p "$h3/.config/systemd/user"
line="$(run "$h3")"
check "pair gone -> PASS" PASS "$(verdict "$line")" "$line"

# ── 4. home-manager's own links are NOT the hand-written pair ──────────────
# The declared units land in this same directory as SYMLINKS into /nix/store.
# A row that tested -e would call the successful switch a failure, which is the
# opposite reading, so the symlink case is pinned.
h4="$tmp/declared"; mkdir -p "$h4/.config/systemd/user" "$h4/fake-store"
printf '[Unit]\n' > "$h4/fake-store/claude-transcript-mirror.service"
printf '[Unit]\n' > "$h4/fake-store/claude-transcript-mirror.timer"
ln -s "$h4/fake-store/claude-transcript-mirror.service" "$h4/.config/systemd/user/claude-transcript-mirror.service"
ln -s "$h4/fake-store/claude-transcript-mirror.timer" "$h4/.config/systemd/user/claude-transcript-mirror.timer"
line="$(run "$h4")"
check "declared symlinks -> PASS" PASS "$(verdict "$line")" "$line"

# ── 5. off the coordinator the row does not apply ──────────────────────────
line="$(HOME="$h1" L8_FLASH_HOST=worker bash "$PROBE" 2>/dev/null | grep -F "$ROW" || true)"
check "non-coordinator -> SKIP" SKIP "$(verdict "$line")" "$line"

echo "$((5 - fails))/5 cases passed"
test "$fails" -eq 0
