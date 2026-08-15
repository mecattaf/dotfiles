#!/usr/bin/env bash
set -euo pipefail

reporter="${FAILURE_MARKER_REPORTER:?FAILURE_MARKER_REPORTER must be set}"
sensor="${JOURNAL_SENSOR:?JOURNAL_SENSOR must be set}"
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

# Coredump exclusions remove known-recovering process names and one narrowly
# matched intentional crash test without hiding a live daemon or an unrelated
# process. A fake journal keeps the cursor/filter behavior deterministic.
fake_bin="$root/bin"
sensor_state="$root/sensor-state"
fixture="$root/journal.json"
mkdir -p "$fake_bin" "$sensor_state"
printf 'seed\n' > "$sensor_state/coredump.cursor"
printf '%s\n' \
  "#!$(command -v bash)" \
  'exec cat "$JOURNAL_FIXTURE"' > "$fake_bin/journalctl"
chmod +x "$fake_bin/journalctl"

printf '%s\n' \
  '{"__REALTIME_TIMESTAMP":"1786715301893875","MESSAGE":"intentional tally test abort","SYSLOG_IDENTIFIER":"systemd-coredump","_HOSTNAME":"coordinator","COREDUMP_COMM":"tally-5a1153098","COREDUMP_CMDLINE":"/build/source/target/x86_64-unknown-linux-gnu/release/deps/tally-5a11530984080fbb --exact cli::campaign::tests::release_execute_crash_child --nocapture --test-threads=1"}' \
  '{"__REALTIME_TIMESTAMP":"1786715301893876","MESSAGE":"live tally daemon abort","SYSLOG_IDENTIFIER":"systemd-coredump","_HOSTNAME":"coordinator","COREDUMP_COMM":"tally","COREDUMP_CMDLINE":"/nix/store/example-tally/bin/tally daemon run"}' \
  '{"__REALTIME_TIMESTAMP":"1786715301893877","MESSAGE":"chrome renderer abort","SYSLOG_IDENTIFIER":"systemd-coredump","_HOSTNAME":"coordinator","COREDUMP_COMM":"chrome","COREDUMP_CMDLINE":"/nix/store/example-chrome/bin/chrome --type=renderer"}' \
  '{"__REALTIME_TIMESTAMP":"1786715301893878","MESSAGE":"unrelated process abort","SYSLOG_IDENTIFIER":"systemd-coredump","_HOSTNAME":"coordinator","COREDUMP_COMM":"other","COREDUMP_CMDLINE":"/nix/store/example/bin/other"}' \
  > "$fixture"

pattern='^/build/source/target/[^ ]+/release/deps/tally-[0-9a-f]+ --exact cli::campaign::tests::release_execute_crash_child --nocapture --test-threads=1$'
patterns_json="$(jq -cn --arg pattern "$pattern" '[$pattern]')"
sensor_output="$(
  PATH="$fake_bin:$PATH" \
  TZ=UTC \
  STATE_DIRECTORY="$sensor_state" \
  JOURNAL_FIXTURE="$fixture" \
  JOURNAL_KIND=coredump \
  JOURNAL_MATCH='MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1' \
  JOURNAL_EXCLUDE_FIELD=COREDUMP_COMM \
  JOURNAL_EXCLUDE_VALUES=chrome \
  JOURNAL_EXCLUDE_REGEX_FIELD=COREDUMP_CMDLINE \
  JOURNAL_EXCLUDE_REGEX_PATTERNS="$patterns_json" \
    bash "$sensor"
)"

[[ "$sensor_output" == "2 coredump" ]]
grep -Fqx '2026-08-14T13:48:21+0000 coordinator systemd-coredump: live tally daemon abort' "$sensor_state/coredump.new"
grep -Fqx '2026-08-14T13:48:21+0000 coordinator systemd-coredump: unrelated process abort' "$sensor_state/coredump.new"
! grep -Fq 'intentional tally test abort' "$sensor_state/coredump.new"
! grep -Fq 'chrome renderer abort' "$sensor_state/coredump.new"

# Invalid regexes fail open for that filter while preserving the exact COMM
# exclusion already applied: three non-Chrome events remain visible.
sensor_output="$(
  PATH="$fake_bin:$PATH" \
  TZ=UTC \
  STATE_DIRECTORY="$sensor_state" \
  JOURNAL_FIXTURE="$fixture" \
  JOURNAL_KIND=coredump \
  JOURNAL_MATCH='MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1' \
  JOURNAL_EXCLUDE_FIELD=COREDUMP_COMM \
  JOURNAL_EXCLUDE_VALUES=chrome \
  JOURNAL_EXCLUDE_REGEX_FIELD=COREDUMP_CMDLINE \
  JOURNAL_EXCLUDE_REGEX_PATTERNS='["["]' \
    bash "$sensor"
)"
[[ "$sensor_output" == "3 coredump" ]]
