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
set -euo pipefail

kind="${JOURNAL_KIND:?JOURNAL_KIND must name this watcher}"
state_dir="${STATE_DIRECTORY%%:*}"
cursor="$state_dir/${kind}.cursor"
digest="$state_dir/${kind}.new"
raw="$state_dir/${kind}.raw"
max_lines="${JOURNAL_MAX_LINES:-50}"

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

# journalctl writes the cursor only after it has finished emitting, so the
# output is collected whole and truncated afterwards; piping into head would
# SIGPIPE it into re-reporting the same burst on every poll.
journalctl --merge --quiet --no-pager --cursor-file="$cursor" \
  --output=short-iso "${match[@]}" > "$raw" 2>/dev/null || true

count="$(wc -l < "$raw")"
head -n "$max_lines" "$raw" > "$digest"
rm -f "$raw"

printf '%s %s\n' "$count" "$kind"
