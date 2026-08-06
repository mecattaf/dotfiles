#!/usr/bin/env bash
# myTripwire sensor: how many new journal entries matched since the last poll.
#
# The journal is already a structured, indexed event store, so "watch for X"
# needs no new daemon — only a cursor. journalctl persists that cursor itself
# (--cursor-file), which is what keeps this sensor stateless-looking while
# being exactly-once across polls.
#
# Prints "<count> <kind>" and leaves the matching entries in
# $STATE_DIRECTORY/<kind>.new for the onFire script to quote.
#
# The unit of measure is the ENTRY, not the line. A systemd-coredump message
# carries the whole stack trace and module list, so one Chrome crash was
# reported as "638 new coredump(s)" and the marker quoted ten consecutive
# "Module ... without build-id" lines — a count nobody can act on attached to a
# digest nobody can read. JSON output puts exactly one entry on one line, which
# makes `wc -l` mean what `threshold` already assumed it meant, and lets the
# digest carry each entry's first line: the one naming the process and its fate.
set -euo pipefail

kind="${JOURNAL_KIND:?JOURNAL_KIND must name this watcher}"
state_dir="${STATE_DIRECTORY%%:*}"
cursor="$state_dir/${kind}.cursor"
digest="$state_dir/${kind}.new"
raw="$state_dir/${kind}.raw"
max_entries="${JOURNAL_MAX_ENTRIES:-50}"

read -r -a match <<<"${JOURNAL_MATCH:?JOURNAL_MATCH must be a journalctl match expression}"

# First run has no cursor. Seeding it from the newest entry — rather than
# replaying the whole journal — means a fresh host does not alert on history it
# was never asked to watch.
if [ ! -s "$cursor" ]; then
  journalctl --merge --quiet --no-pager -n 1 -o cat --cursor-file="$cursor" >/dev/null 2>&1 || true
  : > "$digest"
  printf '0 %s\n' "$kind"
  exit 0
fi

# --all because journalctl drops oversized fields from JSON output, and the
# oversized field here is exactly the coredump MESSAGE worth quoting.
#
# journalctl writes the cursor only after it has finished emitting, so the
# output is collected whole and truncated afterwards; piping into head would
# SIGPIPE it into re-reporting the same burst on every poll.
journalctl --merge --quiet --no-pager --all --cursor-file="$cursor" \
  --output=json --output-fields=MESSAGE,SYSLOG_IDENTIFIER,_HOSTNAME \
  "${match[@]}" > "$raw" 2>/dev/null || true

count="$(wc -l < "$raw")"

# head reads the file rather than a pipe from journalctl, so jq sees a closed
# stream instead of being SIGPIPEd. The count is the alarm and the digest is
# only its context, so a jq that chokes on a torn write costs the context and
# still reports the crash.
head -n "$max_entries" "$raw" | jq -r '
  (.__REALTIME_TIMESTAMP // "0" | tonumber / 1000000
    | strflocaltime("%Y-%m-%dT%H:%M:%S%z")) as $when
  | (.MESSAGE // ""
    | if type == "array" then "<binary message>" else . end
    | split("\n")[0]) as $what
  | "\($when) \(._HOSTNAME // "?") \(.SYSLOG_IDENTIFIER // "?"): \($what)"
' > "$digest" || :
rm -f "$raw"

printf '%s %s\n' "$count" "$kind"
