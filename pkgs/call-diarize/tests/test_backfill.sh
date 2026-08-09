#!/usr/bin/env bash
set -euo pipefail

temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT

recordings="$temporary/Recordings/calls"
events="$temporary/state/tally/events"
mkdir -p \
  "$recordings/2026-08-07-existing" \
  "$recordings/2026-08-08-needs-diarization" \
  "$recordings/2026-08-09-needs-diarization"
: >"$recordings/2026-08-07-existing/transcript.md"

TALLY_EVENTS_DIR="$events" \
  TALLY_SOCKET="$temporary/missing-tally.sock" \
  bash backfill.sh "$recordings"

mapfile -d '' event_files < <(find "$events" -maxdepth 1 -type f -name '*.json' -print0 | sort -z)
[[ ${#event_files[@]} -eq 2 ]]

for event in "${event_files[@]}"; do
  jq -e '
    .argv[0] == "call-diarize" and
    (.argv[1] | startswith("/")) and
    .adapter == "shell" and
    .pool == ["coordinator-gpu"] and
    .priority == "low" and
    .source == "events-dir" and
    .dedupKey == ("call-diarize:" + (.argv[1] | split("/")[-1])) and
    .submission == {"mode":"full"} and
    .evidence == ["exit:0"] and
    .runtimeMaxSec == 21600 and
    .noEnqueue == true and
    (keys | sort) == ([
      "adapter", "argv", "dedupKey", "evidence", "noEnqueue", "pool",
      "priority", "runtimeMaxSec", "source", "submission"
    ] | sort)
  ' "$event" >/dev/null
done

# Repeating the scan replaces the same deterministic pending files rather than
# multiplying events before tally has a chance to claim them.
TALLY_EVENTS_DIR="$events" \
  TALLY_SOCKET="$temporary/missing-tally.sock" \
  bash backfill.sh "$recordings" >/dev/null
[[ "$(find "$events" -maxdepth 1 -type f -name '*.json' -print | wc -l)" -eq 2 ]]

single="$recordings/2026-08-10-single"
mkdir -p "$single"
TALLY_EVENTS_DIR="$events" \
  TALLY_SOCKET="$temporary/missing-tally.sock" \
  bash backfill.sh --enqueue "$single" >/dev/null

single_event="$(
  find "$events" -maxdepth 1 -type f -name '*.json' -print0 \
    | xargs -0 jq -r 'select(.dedupKey == "call-diarize:2026-08-10-single") | input_filename'
)"
[[ -n "$single_event" ]]
jq -e --arg directory "$(realpath "$single")" \
  '.argv == ["call-diarize", $directory]' "$single_event" >/dev/null
