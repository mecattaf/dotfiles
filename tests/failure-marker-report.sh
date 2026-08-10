#!/usr/bin/env bash
set -euo pipefail

reporter="${FAILURE_MARKER_REPORTER:?FAILURE_MARKER_REPORTER must be set}"
root="$(mktemp -d)"
marker_dir="$root/markers"
export XDG_STATE_HOME="$root/state"
mkdir -p "$marker_dir"

printf '%s\n' '2026-08-10 04:49 — 1 new coredump(s) (episode coredump-1)' \
  >"$marker_dir/coredump"
printf '%s\n' '2026-08-10 00:13 — 1 new user unit failure(s) (episode user-1)' \
  >"$marker_dir/user-unit-failure"

# First use baselines episodes that the old shell hook already displayed. The
# first terminal after deploying this fix therefore starts quiet.
test -z "$(bash "$reporter" "$marker_dir")"

# Unchanged root-owned markers do not nag in every later terminal.
test -z "$(bash "$reporter" "$marker_dir")"

# Removing one marker does not make a remaining old episode look new again.
rm "$marker_dir/coredump"
test -z "$(bash "$reporter" "$marker_dir")"

# Rewriting a marker with a genuinely new episode produces one new receipt.
printf '%s\n' '2026-08-11 00:13 — 1 new user unit failure(s) (episode user-2)' \
  >"$marker_dir/user-unit-failure"
second="$(bash "$reporter" "$marker_dir")"
grep -Fq 'episode user-2' <<<"$second"
test -z "$(bash "$reporter" "$marker_dir")"

# Simultaneous shells serialize their receipts; exactly one reports the event.
printf '%s\n' 'example.service failed at 2026-08-11 00:14 — journalctl' \
  >"$marker_dir/example.service"
bash "$reporter" "$marker_dir" >"$root/concurrent-a" &
pid_a=$!
bash "$reporter" "$marker_dir" >"$root/concurrent-b" &
pid_b=$!
wait "$pid_a"
wait "$pid_b"
test "$(grep -Fhc 'example.service failed' "$root"/concurrent-* | awk '{ total += $1 } END { print total }')" -eq 1

test "$(stat -c '%a' "$XDG_STATE_HOME/fleet-deploy/failure-episodes.seen")" = 600
