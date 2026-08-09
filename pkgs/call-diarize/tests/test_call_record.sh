#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 && -f "$1" && -x "$2" && -f "$3" ]] || {
  echo "usage: test_call_record.sh <call-record> <bash> <backfill.sh>" >&2
  exit 1
}
call_record="$1"
test_bash="$2"
backfill="$3"

temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT

test_home="$temporary/home"
state_home="$temporary/state"
fake_bin="$temporary/bin"
mkdir -p "$test_home" "$state_home" "$fake_bin"

# Preserve the pre-enqueue stop contract exactly when no capture is active.
no_session_output="$temporary/no-session.out"
set +e
HOME="$test_home" XDG_STATE_HOME="$state_home" \
  "$test_bash" "$call_record" stop >"$no_session_output" 2>&1
no_session_status=$?
set -e
[[ $no_session_status -eq 1 ]]
[[ "$(<"$no_session_output")" == "no session running" ]]

# The fakes make a completed capture deterministic. The enqueue helper refuses
# to run before mix.wav is non-empty, records its exact argv, then simulates an
# unavailable events directory. `stop` must still close the session and exit 0.
printf '#!%s\n' "$test_bash" >"$fake_bin/sox"
cat >>"$fake_bin/sox" <<'EOF'
set -euo pipefail
[[ "${1:-}" == "-m" && $# -eq 7 ]]
printf 'finalized mix\n' >"$4"
EOF
printf '#!%s\n' "$test_bash" >"$fake_bin/soxi"
cat >>"$fake_bin/soxi" <<'EOF'
set -euo pipefail
printf '00:00:01.00\n'
EOF
printf '#!%s\n' "$test_bash" >"$fake_bin/call-diarize-backfill"
cat >>"$fake_bin/call-diarize-backfill" <<'EOF'
set -euo pipefail
: "${CALL_RECORD_TEST_LOG:?}"
[[ "${1:-}" == "--enqueue" && $# -eq 2 ]]
[[ -s "$2/mix.wav" ]]
printf '%s\n%s\n' "$1" "$2" >"$CALL_RECORD_TEST_LOG"
exit "${CALL_RECORD_TEST_ENQUEUE_STATUS:-0}"
EOF
chmod +x "$fake_bin/sox" "$fake_bin/soxi" "$fake_bin/call-diarize-backfill"

call_dir="$test_home/Recordings/calls/2026-08-09-regression"
current="$state_home/call-record/current"
enqueue_log="$temporary/enqueue.log"
stop_stdout="$temporary/stop.out"
stop_stderr="$temporary/stop.err"
mkdir -p "$call_dir" "$(dirname "$current")"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  CALL_RECORD_TEST_LOG="$enqueue_log" \
  CALL_RECORD_TEST_ENQUEUE_STATUS=23 \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

[[ ! -e "$current" ]]
[[ "$(<"$call_dir/mix.wav")" == "finalized mix" ]]
mapfile -t enqueue_argv <"$enqueue_log"
[[ ${#enqueue_argv[@]} -eq 2 ]]
[[ "${enqueue_argv[0]}" == "--enqueue" ]]
[[ "${enqueue_argv[1]}" == "$call_dir" ]]
[[ "$(<"$stop_stderr")" == \
  "warning: diarization was not queued; run call-diarize-backfill later" ]]
[[ "$(<"$stop_stdout")" == session\ closed:* ]]

# Replace the failing helper with the real event writer and exercise the whole
# stop -> atomic event path. A missing daemon is deliberately only a warning.
printf '#!%s\nexec "%s" "%s" "$@"\n' \
  "$test_bash" "$test_bash" "$backfill" >"$fake_bin/call-diarize-backfill"

call_dir="$test_home/Recordings/calls/2026-08-09-dry-event"
events_dir="$state_home/tally/events"
stop_stdout="$temporary/stop-dry-event.out"
stop_stderr="$temporary/stop-dry-event.err"
mkdir -p "$call_dir"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  TALLY_EVENTS_DIR="$events_dir" \
  TALLY_SOCKET="$temporary/missing-tally.sock" \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

mapfile -d '' event_files < <(
  find "$events_dir" -maxdepth 1 -type f -name '*.json' -print0
)
[[ ${#event_files[@]} -eq 1 ]]
jq -e --arg directory "$call_dir" '
  . == {
    argv: ["call-diarize", $directory],
    adapter: "shell",
    pool: ["coordinator-gpu"],
    priority: "low",
    source: "events-dir",
    dedupKey: "call-diarize:2026-08-09-dry-event",
    submission: {mode: "full"},
    evidence: ["exit:0"],
    runtimeMaxSec: 21600,
    noEnqueue: true
  }
' "${event_files[0]}" >/dev/null
[[ "$(<"$stop_stderr")" == \
  "warning: tally daemon is unavailable; event is queued for a later drain" ]]
[[ "$(<"$stop_stdout")" == queued\ diarization:*session\ closed:* ]]

# Exercise the real helper's failure path too: a non-directory parent makes
# the events directory unusable, but a finalized recording must still close.
blocked_events="$temporary/events-not-directory"
: >"$blocked_events"
call_dir="$test_home/Recordings/calls/2026-08-09-unavailable-events"
stop_stdout="$temporary/stop-unavailable-events.out"
stop_stderr="$temporary/stop-unavailable-events.err"
mkdir -p "$call_dir"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  TALLY_EVENTS_DIR="$blocked_events/events" \
  TALLY_SOCKET="$temporary/missing-tally.sock" \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

[[ ! -e "$current" ]]
[[ "$(<"$call_dir/mix.wav")" == "finalized mix" ]]
[[ "$(<"$stop_stderr")" == \
  *"warning: diarization was not queued; run call-diarize-backfill later"* ]]
[[ "$(<"$stop_stdout")" == session\ closed:* ]]
