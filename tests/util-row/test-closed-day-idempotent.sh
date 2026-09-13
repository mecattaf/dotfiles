#!/usr/bin/env bash
# tests/util-row/test-closed-day-idempotent.sh — util-row's closed-day guard is
# idempotent BY COMPARISON (dotfiles#329).
#
# util-row.service runs `util-row` with no flags under a Persistent timer, so a
# catch-up or second trigger on a night already written used to exit 2 ("a
# closed day must reproduce, not re-freeze") and fail the unit. The guard now
# re-selects the slice and recomputes the row: both reproduce -> exit 0 and
# NOTHING is rewritten (bytes and mtimes unchanged); either differs -> exit 2 and
# nothing is written; --refresh-slice overwrites.
#
# Hermetic: the lease events, receipt roots and drain ledger are pointed at a
# scratch tree through util-row's UTIL_* test hooks, the box is the coordinator
# (so no scp of a worker log is attempted), and every write lands in a scratch
# meters root. python3 and coreutils only.
set -euo pipefail

ROW="${UTIL_ROW:-$(cd "$(dirname "$0")/../.." && pwd)/home/dot_local/bin/util-row}"
test -r "$ROW" || { echo "no util-row at $ROW" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
D=2026-09-12
M="$tmp/meters"
mkdir -p "$M/util-sampler" "$tmp/receipts"
export UTIL_LEASE_EVENTS="$tmp/lease-events.jsonl"
export UTIL_RECEIPT_ROOTS="$tmp/receipts"
export UTIL_COORDINATOR_LEDGER="$tmp/completed.jsonl"
: > "$UTIL_COORDINATOR_LEDGER"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS  $*"; }
no() { fail=$((fail + 1)); echo "FAIL  $*"; }

grant() { # $1 = HH:MM, $2 = unit
  printf '{"event":{"kind":"granted","grant":{"grantedAt":"%sT%s:00Z","pools":["coordinator-gpu"],"unit":"%s"}}}\n' "$D" "$1" "$2" >> "$UTIL_LEASE_EVENTS"
}
grant 11:00 unit-a
grant 13:00 unit-b
# a grant for another pool and one for another day: neither is in the slice
printf '{"event":{"kind":"granted","grant":{"grantedAt":"%sT12:00:00Z","pools":["worker-gpu"],"unit":"w"}}}\n' "$D" >> "$UTIL_LEASE_EVENTS"
printf '{"event":{"kind":"granted","grant":{"grantedAt":"2026-09-10T12:00:00Z","pools":["coordinator-gpu"],"unit":"old"}}}\n' >> "$UTIL_LEASE_EVENTS"

# Three samples around midday UTC, so the local date is the 12th in any zone
# within +-11 h. No `tz` key: the row falls back to the running box's zone, the
# same on every run of this test.
for t in 1789214400 1789214460 1789214520; do
  ts="$(python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp($t).astimezone().isoformat())")"
  printf '{"schema":"util-sample/2","ts":"%s","ts_epoch":%s,"box":"coordinator","sysfs":{"gpu_busy_percent":50,"gtt_used":100,"vram_used":1},"pools":{"ok":true,"held":{"coordinator-gpu":1}},"probes":[],"ledger":{}}\n' "$ts" "$t" >> "$M/util-sampler/coordinator-$D.jsonl"
done

SLICE="$M/util-sampler/coordinator-$D.lease-slice.jsonl"
RROW="$M/util-coordinator-$D.json"
WEEK="$M/util-coordinator-week-2026-W37.json"
state() { for f in "$SLICE" "$RROW" "$WEEK"; do sha256sum "$f" | cut -d' ' -f1; stat -c %y "$f"; done; }
run() { # stderr to $tmp/err, rc echoed
  set +e
  python3 "$ROW" --box coordinator --date "$D" --meters "$M" "$@" > "$tmp/out" 2> "$tmp/err"
  local rc=$?
  set -e
  echo "$rc"
}

# ── A: first run freezes and writes ────────────────────────────────────────
rc="$(run)"
if [ "$rc" = 0 ] && [ -s "$RROW" ] && [ -f "$WEEK" ] && [ "$(wc -l < "$SLICE")" = 2 ]; then
  ok "A first run writes slice (2 lines), row and week, rc 0"
else
  no "A first run rc=$rc slice=$(wc -l < "$SLICE" 2>/dev/null) $(cat "$tmp/err")"
fi
before="$(state)"
sleep 1.1

# ── B: the same run again reproduces and rewrites nothing ──────────────────
rc="$(run)"
if [ "$rc" = 0 ] && [ "$(state)" = "$before" ] && grep -q 'reproduce byte-for-byte' "$tmp/err"; then
  ok "B re-run rc 0, slice/row/week sha256 AND mtime unchanged"
else
  no "B re-run rc=$rc state-changed=$([ "$(state)" = "$before" ] && echo no || echo yes) $(cat "$tmp/err")"
fi

# ── C: a new counted receipt changes the row -> refused, row untouched ─────
printf '{"usage":{"completion_tokens":200},"fingerprint":"b1"}\n' > "$tmp/receipts/r.json"
touch -d "${D}T12:00:30Z" "$tmp/receipts/r.json"
rc="$(run)"
if [ "$rc" = 2 ] && grep -q 'differs from a recompute' "$tmp/err" && [ "$(state)" = "$before" ]; then
  ok "C row divergence rc 2, names it, nothing written"
else
  no "C row divergence rc=$rc $(cat "$tmp/err")"
fi
rm "$tmp/receipts/r.json"

# ── D: a late grant changes the selection -> refused, slice untouched ──────
grant 15:00 unit-c
rc="$(run)"
if [ "$rc" = 2 ] && grep -q 'differs from a fresh selection' "$tmp/err" && [ "$(state)" = "$before" ]; then
  ok "D slice divergence rc 2, names it, nothing written"
else
  no "D slice divergence rc=$rc $(cat "$tmp/err")"
fi

# ── E: --refresh-slice is the one way to overwrite ─────────────────────────
rc="$(run --refresh-slice)"
if [ "$rc" = 0 ] && [ "$(wc -l < "$SLICE")" = 3 ]; then
  ok "E --refresh-slice rc 0, slice now 3 lines"
else
  no "E --refresh-slice rc=$rc $(cat "$tmp/err")"
fi

# ── F: slice frozen but the row never landed -> the row is written, rc 0 ───
rm "$RROW"
rc="$(run)"
if [ "$rc" = 0 ] && [ -s "$RROW" ]; then
  ok "F slice present, row absent: row written, rc 0"
else
  no "F missing row rc=$rc $(cat "$tmp/err")"
fi

echo "test-closed-day-idempotent: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
