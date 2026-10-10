#!/usr/bin/env bash
# call-record's stop contract (2026-10-10: Tally retired, the stop starts the
# diarizer itself through call-diarize-start; see that script's header).
set -euo pipefail

[[ $# -eq 3 && -f "$1" && -x "$2" && -f "$3" ]] || {
  echo "usage: test_call_record.sh <call-record> <bash> <call-diarize-start>" >&2
  exit 1
}
call_record="$1"
test_bash="$2"
diarize_start="$3"

temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT

test_home="$temporary/home"
state_home="$temporary/state"
fake_bin="$temporary/bin"
mkdir -p "$test_home" "$state_home" "$fake_bin"

# Preserve the stop contract exactly when no capture is active.
no_session_output="$temporary/no-session.out"
set +e
HOME="$test_home" XDG_STATE_HOME="$state_home" \
  "$test_bash" "$call_record" stop >"$no_session_output" 2>&1
no_session_status=$?
set -e
[[ $no_session_status -eq 1 ]]
[[ "$(<"$no_session_output")" == "no session running" ]]

# The fakes make a completed capture deterministic. A fake call-diarize on PATH
# selects the local branch (the host has the diarizer); a fake
# call-diarize-start refuses to run before mix.wav is non-empty, records its
# exact argv, then fails. `stop` must still close the session and exit 0.
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
printf '#!%s\nexit 99\n' "$test_bash" >"$fake_bin/call-diarize"
printf '#!%s\n' "$test_bash" >"$fake_bin/call-diarize-start"
cat >>"$fake_bin/call-diarize-start" <<'EOF'
set -euo pipefail
: "${CALL_RECORD_TEST_LOG:?}"
[[ $# -eq 1 ]]
[[ -s "$1/mix.wav" ]]
printf '%s\n' "$1" >"$CALL_RECORD_TEST_LOG"
exit "${CALL_RECORD_TEST_START_STATUS:-0}"
EOF
chmod +x "$fake_bin/sox" "$fake_bin/soxi" "$fake_bin/call-diarize" "$fake_bin/call-diarize-start"

call_dir="$test_home/Recordings/calls/2026-08-09-regression"
current="$state_home/call-record/current"
start_log="$temporary/start.log"
stop_stdout="$temporary/stop.out"
stop_stderr="$temporary/stop.err"
mkdir -p "$call_dir" "$(dirname "$current")"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  CALL_RECORD_TEST_LOG="$start_log" \
  CALL_RECORD_TEST_START_STATUS=23 \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

[[ ! -e "$current" ]]
[[ "$(<"$call_dir/mix.wav")" == "finalized mix" ]]
[[ "$(<"$start_log")" == "$call_dir" ]]
[[ "$(<"$stop_stderr")" == \
  "warning: diarization was not started; run call-diarize-start $call_dir later" ]]
[[ "$(<"$stop_stdout")" == session\ closed:* ]]

# The lifecycle extension uses only fake PipeWire processes. Its own temporary
# HOME/state/runtime are independent of the hand-off regressions above.
CALL_RECORD_TEST_SCRIPT="$call_record" \
CALL_RECORD_TEST_BASH="$test_bash" \
  python3 "$(dirname "$0")/test_call_record_wake.py"

# Replace the fake with the REAL call-diarize-start and exercise the whole
# stop -> detached transient unit path against a fake systemd-run that records
# its argv. The unit is named after the recording dir and logs beside it.
printf '#!%s\nexec "%s" "%s" "$@"\n' \
  "$test_bash" "$test_bash" "$diarize_start" >"$fake_bin/call-diarize-start"
printf '#!%s\n' "$test_bash" >"$fake_bin/systemd-run"
cat >>"$fake_bin/systemd-run" <<'EOF'
set -euo pipefail
: "${CALL_RECORD_TEST_LOG:?}"
printf '%s\n' "$@" >"$CALL_RECORD_TEST_LOG"
if [[ -n "${CALL_RECORD_TEST_SYSTEMD_RUN_FAIL:-}" ]]; then
  echo "Failed to start transient service unit: boom" >&2
  exit 1
fi
EOF
printf '#!%s\nexit 3\n' "$test_bash" >"$fake_bin/systemctl"
chmod +x "$fake_bin/call-diarize-start" "$fake_bin/systemd-run" "$fake_bin/systemctl"

call_dir="$test_home/Recordings/calls/2026-08-09-dry-event"
run_log="$temporary/systemd-run.log"
stop_stdout="$temporary/stop-dry-event.out"
stop_stderr="$temporary/stop-dry-event.err"
mkdir -p "$call_dir"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  CALL_RECORD_TEST_LOG="$run_log" \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

[[ ! -e "$current" ]]
mapfile -t run_argv <"$run_log"
[[ "${run_argv[0]}" == "--user" ]]
[[ " ${run_argv[*]} " == *" --no-block "* ]]
[[ " ${run_argv[*]} " == *" --collect "* ]]
[[ " ${run_argv[*]} " == *" --unit call-diarize-2026-08-09-dry-event "* ]]
[[ " ${run_argv[*]} " == *" -p StandardOutput=append:$call_dir/diarize.log "* ]]
[[ "${run_argv[-2]}" == "call-diarize" ]]
[[ "${run_argv[-1]}" == "$call_dir" ]]
[[ -z "$(<"$stop_stderr")" ]]
[[ "$(<"$stop_stdout")" == "diarization started: call-diarize-2026-08-09-dry-event (log $call_dir/diarize.log)"$'\n'session\ closed:* ]]

# The real helper's failure path too: systemd-run refuses, but a finalized
# recording must still close, with the re-run hint on stderr.
call_dir="$test_home/Recordings/calls/2026-08-09-unavailable-manager"
stop_stdout="$temporary/stop-unavailable-manager.out"
stop_stderr="$temporary/stop-unavailable-manager.err"
mkdir -p "$call_dir"
printf 'far audio\n' >"$call_dir/far.wav"
printf 'near audio\n' >"$call_dir/near.wav"
printf '%s\n99999998\n99999999\n' "$call_dir" >"$current"

HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$fake_bin:$PATH" \
  CALL_RECORD_TEST_LOG="$run_log" \
  CALL_RECORD_TEST_SYSTEMD_RUN_FAIL=1 \
  "$test_bash" "$call_record" stop >"$stop_stdout" 2>"$stop_stderr"

[[ ! -e "$current" ]]
[[ "$(<"$call_dir/mix.wav")" == "finalized mix" ]]
[[ "$(<"$stop_stderr")" == *"could not start call-diarize-2026-08-09-unavailable-manager:"* ]]
[[ "$(<"$stop_stderr")" == *"boom"* ]]
[[ "$(<"$stop_stderr")" == \
  *"warning: diarization was not started; run call-diarize-start $call_dir later"* ]]
[[ "$(<"$stop_stdout")" == session\ closed:* ]]
