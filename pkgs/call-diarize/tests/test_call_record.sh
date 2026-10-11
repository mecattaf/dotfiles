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
  python3 "$(dirname "$0")/test_call_record_hold.py"

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

# ── Thin client (2026-10-11) ────────────────────────────────────────────────
# A host without call-diarize that is not the strix records into the hidden
# spool and, after `stop`, keeps no copy once the strix holds every file byte
# for byte; on any failure the session stays in the spool. The "strix" is a
# second temporary home behind a fake ssh that hands the remote command to
# bash there, like sshd; its call-diarize-start is a fake that logs its dir.
# The PATH is closed (symlinks to exactly the tools used), so a call-diarize
# on the build host cannot select the local branch.
thin_bin="$temporary/thin-bin"
strix_bin="$temporary/strix-bin"
strix_home="$temporary/strix-home"
thin_home="$temporary/thin-home"
thin_state="$temporary/thin-state"
spool="$thin_state/call-record/spool"
ssh_log="$temporary/ssh.log"
strix_start_log="$temporary/strix-start.log"
mkdir -p "$thin_bin" "$strix_bin" "$strix_home" "$thin_home" "$spool"
for tool in basename dirname find flock head mkdir realpath rm sha256sum tar; do
  real="$(command -v "$tool")" || { echo "test needs $tool on PATH" >&2; exit 1; }
  ln -s "$real" "$thin_bin/$tool"
done
cp "$fake_bin/sox" "$fake_bin/soxi" "$thin_bin/"
printf '#!%s\nprintf "client\\n"\n' "$test_bash" >"$thin_bin/hostname"
printf '#!%s\n' "$test_bash" >"$thin_bin/ssh"
cat >>"$thin_bin/ssh" <<'FAKE'
host="$1"; shift
printf '%s %s\n' "$host" "$*" >>"$CALL_RECORD_TEST_SSH_LOG"
[[ -z "${CALL_RECORD_TEST_SSH_DOWN:-}" ]] || exit 255
[[ "$host" == strix ]] || exit 255
cd "$CALL_RECORD_TEST_STRIX_HOME"
HOME="$CALL_RECORD_TEST_STRIX_HOME" PATH="$CALL_RECORD_TEST_STRIX_BIN:$PATH" \
  exec "$CALL_RECORD_TEST_BASH" -c "$*"
FAKE
printf '#!%s\n' "$test_bash" >"$strix_bin/call-diarize-start"
cat >>"$strix_bin/call-diarize-start" <<'FAKE'
printf '%s\n' "$1" >>"$CALL_RECORD_TEST_STRIX_LOG"
[[ -z "${CALL_RECORD_TEST_CORRUPT:-}" ]] || printf 'flipped\n' >"$1/far.wav"
exit "${CALL_RECORD_TEST_STRIX_START_STATUS:-0}"
FAKE
chmod +x "$thin_bin/hostname" "$thin_bin/ssh" "$strix_bin/call-diarize-start"

seed_session() { # $1 = session name; leaves a closed capture in the spool
  local session="$spool/$1"
  mkdir -p "$session"
  printf 'far audio %s\n' "$1" >"$session/far.wav"
  printf 'near audio %s\n' "$1" >"$session/near.wav"
  : >"$session/capture.log"
  printf '%s\n99999998\n99999999\n' "$session" >"$thin_state/call-record/current"
}
thin() { # call-record on the thin client; extra settings come from the env
  HOME="$thin_home" XDG_STATE_HOME="$thin_state" PATH="$thin_bin" \
    CALL_RECORD_TEST_SSH_LOG="$ssh_log" CALL_RECORD_TEST_STRIX_HOME="$strix_home" \
    CALL_RECORD_TEST_STRIX_BIN="$strix_bin" CALL_RECORD_TEST_STRIX_LOG="$strix_start_log" \
    CALL_RECORD_TEST_BASH="$test_bash" \
    "$test_bash" "$call_record" "$@"
}
strix_calls="$strix_home/Recordings/calls"

# Successful hand-off: the strix holds all four files, the diarizer was
# started there, and the local copy is gone.
seed_session 2026-10-11-thin-ok
session="$spool/2026-10-11-thin-ok"
thin stop >"$temporary/thin-ok.out" 2>"$temporary/thin-ok.err"
[[ ! -e "$session" ]]
[[ ! -e "$thin_state/call-record/current" ]]
for f in far.wav near.wav capture.log; do
  [[ -f "$strix_calls/2026-10-11-thin-ok/$f" ]]
done
[[ "$(<"$strix_calls/2026-10-11-thin-ok/far.wav")" == "far audio 2026-10-11-thin-ok" ]]
[[ "$(<"$strix_calls/2026-10-11-thin-ok/mix.wav")" == "finalized mix" ]]
[[ "$(<"$strix_start_log")" == "$strix_calls/2026-10-11-thin-ok" ]]
[[ -z "$(<"$temporary/thin-ok.err")" ]]
grep -qx 'handed to strix: ~/Recordings/calls/2026-10-11-thin-ok (every file verified by sha256)' \
  "$temporary/thin-ok.out"
grep -q '^  far.wav  *strix:~/Recordings/calls/2026-10-11-thin-ok/far.wav ' "$temporary/thin-ok.out"
grep -qx "local copy removed: $session" "$temporary/thin-ok.out"
[[ ! -e "$thin_home/Recordings" ]]
echo "ok thin client: verified hand-off removes the local copy"

# Strix unreachable: `stop` still closes (exit 0), the session stays in the
# spool with every file, and stderr says where and how to retry.
seed_session 2026-10-11-thin-down
session="$spool/2026-10-11-thin-down"
CALL_RECORD_TEST_SSH_DOWN=1 thin stop >"$temporary/thin-down.out" 2>"$temporary/thin-down.err"
for f in far.wav near.wav mix.wav capture.log; do
  [[ -f "$session/$f" ]]
done
[[ ! -e "$strix_calls/2026-10-11-thin-down" ]]
grep -qx "warning: hand-off to the strix failed; the local copy is kept at $session" \
  "$temporary/thin-down.err"
grep -qx "         re-run: call-record handoff $session" "$temporary/thin-down.err"
grep -q "^  mix.wav  *$session/mix.wav " "$temporary/thin-down.out"
echo "ok thin client: failed hand-off keeps the session in the spool"

# The retry verb, strix back: same copy, verification and delete.
thin handoff "$session" >"$temporary/thin-retry.out" 2>"$temporary/thin-retry.err"
[[ ! -e "$session" ]]
[[ "$(<"$strix_calls/2026-10-11-thin-down/mix.wav")" == "finalized mix" ]]
grep -qx "local copy removed: $session" "$temporary/thin-retry.out"
echo "ok thin client: call-record handoff retries and then removes"

# The copy on the strix differs from the local one (corrupted after the
# extraction): the transfer "succeeded", but nothing is deleted.
seed_session 2026-10-11-thin-corrupt
session="$spool/2026-10-11-thin-corrupt"
CALL_RECORD_TEST_CORRUPT=1 thin stop >"$temporary/thin-corrupt.out" 2>"$temporary/thin-corrupt.err"
[[ "$(<"$session/far.wav")" == "far audio 2026-10-11-thin-corrupt" ]]
[[ -f "$session/mix.wav" ]]
grep -qx "warning: hand-off to the strix failed; the local copy is kept at $session" \
  "$temporary/thin-corrupt.err"
echo "ok thin client: a strix copy that differs keeps the local one"
rm -rf -- "$session"

# The diarizer refuses on the strix, but the copy there is verified: the
# local copy goes, and stderr says how to start the diarizer there.
seed_session 2026-10-11-thin-refused
session="$spool/2026-10-11-thin-refused"
CALL_RECORD_TEST_STRIX_START_STATUS=1 thin stop >"$temporary/thin-refused.out" 2>"$temporary/thin-refused.err"
[[ ! -e "$session" ]]
[[ "$(<"$strix_calls/2026-10-11-thin-refused/near.wav")" == "near audio 2026-10-11-thin-refused" ]]
grep -q "diarization was not started; on the strix run: call-diarize-start ~/Recordings/calls/2026-10-11-thin-refused" \
  "$temporary/thin-refused.err"
echo "ok thin client: verified copy is enough even when the diarizer refuses"

# A host that keeps its recordings (call-diarize here) refuses the verb.
set +e
HOME="$test_home" XDG_STATE_HOME="$state_home" PATH="$fake_bin:$PATH" \
  "$test_bash" "$call_record" handoff "$temporary" >/dev/null 2>"$temporary/keep.err"
keep_status=$?
set -e
[[ $keep_status -eq 1 ]]
grep -q "nothing to hand off" "$temporary/keep.err"
echo "ok keeping host: handoff refused"
