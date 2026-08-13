#!/usr/bin/env bash
# paper-intake-collect — sweep settled scans from the intake drop directory
# into a dated job directory and queue one tally job for the batch.
#
# The Brother ADS-1800W pushes (or an eSCL pull script drops) one JPEG per
# side into ~/Paper/intake. Files are considered settled once their mtime is
# at least SETTLE_SECONDS old, so a mid-transfer file is never claimed. The
# enqueue mirrors call-diarize-backfill exactly: an atomic full-submission
# EnqueuePayload into tally's shared events directory. A missing events
# directory or tally daemon must never lose scans — the job directory is
# created first and the payload failure only warns.
set -euo pipefail

SETTLE_SECONDS="${PAPER_INTAKE_SETTLE_SECONDS:-30}"
INTAKE="${PAPER_INTAKE_DIR:-$HOME/Paper/intake}"
JOBS="${PAPER_INTAKE_JOBS:-$HOME/Paper/jobs}"

events_directory() {
  if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s\n' "${XDG_STATE_HOME}/tally/events"
  else
    printf '%s\n' "${HOME}/.local/state/tally/events"
  fi
}

mkdir -p -- "$INTAKE" "$JOBS"

mapfile -t settled < <(
  find "$INTAKE" -maxdepth 1 -type f \
    \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.pdf' -o -name '*.tif' \) \
    -not -newermt "-${SETTLE_SECONDS} seconds" | sort
)
if [[ ${#settled[@]} -eq 0 ]]; then
  exit 0
fi

job_name="$(date +%F)-scan-$(date +%H%M%S)"
job_dir="$JOBS/$job_name"
mkdir -p -- "$job_dir/scans"

n=0
for f in "${settled[@]}"; do
  n=$((n + 1))
  ext="${f##*.}"
  mv -n -- "$f" "$(printf '%s/scans/page-%02d.%s' "$job_dir" "$n" "$ext")"
done
echo "paper-intake-collect: $n files -> $job_dir"

dedup_key="paper-intake:$job_name"
events_dir="$(events_directory)"
if [[ ! -d "$events_dir" ]]; then
  echo "paper-intake-collect: warning: no events directory; run later:" >&2
  echo "  paper-intake $job_dir" >&2
  exit 0
fi

event_hash="$(printf '%s' "$dedup_key" | sha256sum)"
event_hash="${event_hash%% *}"
event_path="$events_dir/paper-intake-${event_hash:0:32}.json"
temporary="$(mktemp "$events_dir/.paper-intake.XXXXXXXXXX")"
if ! jq -cn \
  --arg job_dir "$job_dir" \
  --arg dedup_key "$dedup_key" \
  '{
    argv: ["paper-intake", $job_dir],
    adapter: "shell",
    pool: ["coordinator-gpu"],
    priority: "low",
    source: "events-dir",
    dedupKey: $dedup_key,
    submission: {mode: "full"},
    evidence: ["exit:0"],
    runtimeMaxSec: 7200,
    noEnqueue: true
  }' >"$temporary"; then
  rm -f -- "$temporary"
  echo "paper-intake-collect: warning: cannot render event; run later:" >&2
  echo "  paper-intake $job_dir" >&2
  exit 0
fi
mv -fT -- "$temporary" "$event_path"
echo "paper-intake-collect: queued $dedup_key"
