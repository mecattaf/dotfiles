#!/usr/bin/env bash
# onFire for the journal-watching tripwires: drop a marker in the same place
# unit failures land, so a shell login shows crashes and unit failures through
# one channel rather than two.
#
# The digest the sensor left behind is quoted verbatim: the point of #134 is
# that both crash bursts were found by `du`, so the marker has to carry enough
# to recognise the burst without opening the journal.
set -euo pipefail

count="${1:?usage: tripwire-journal-onfire <count> <kind> <threshold> <episode_id>}"
kind="${2:?}"
episode_id="${4:?}"

marker_dir="${FAILURE_MARKER_DIR:?FAILURE_MARKER_DIR must be set}"
label="${JOURNAL_LABEL:-$kind}"
state_dir="${STATE_DIRECTORY%%:*}"
digest="$state_dir/${kind}.new"
quote_lines="${JOURNAL_MARKER_LINES:-10}"

[[ "$count" =~ ^[0-9]+$ ]]
[[ "$kind" =~ ^[A-Za-z0-9:_.-]+$ ]]

install -d -m 0755 "$marker_dir"
exec 9>"$marker_dir/.failure-marker-reconcile.lock"
flock 9
marker="$marker_dir/$kind"

{
  printf '%s — %s new %s (episode %s)\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$count" "$label" "$episode_id"
  if [ -s "$digest" ]; then
    head -n "$quote_lines" "$digest"
  fi
} > "$marker"
chmod 0644 "$marker"
