#!/usr/bin/env bash
# drain.sh [--stop-at HH:MM] [--max-papers N] [--min-free-gb N]
#
# Serial OCR drain driver: walks drain/worklist.jsonl (ascending page count),
# runs paper-e2e.js once per paper with a persisted per-paper flow-run-id so a
# rerun resumes instead of redoing pages. Stops when the work-list is dry, the
# stop-at wall-clock passes, free space on $HOME drops below the floor, or
# 3 consecutive papers fail (systemic-breakage fuse).
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/env.sh"

DATA_ROOT="${DATA_ROOT:-$HOME/.local/state/academic-ocr}"
DRAIN="$DATA_ROOT/drain"
FLOW="$SELF/paper-e2e.js"
BASH_BIN="$(command -v bash)"
STOP_AT="" MAX_PAPERS=0 MIN_FREE_GB=50

while [ $# -gt 0 ]; do
  case "$1" in
    --stop-at) STOP_AT="$2"; shift 2 ;;
    --max-papers) MAX_PAPERS="$2"; shift 2 ;;
    --min-free-gb) MIN_FREE_GB="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 64 ;;
  esac
done

STOP_EPOCH=""
if [ -n "$STOP_AT" ]; then
  STOP_EPOCH=$("$CORE/date" -d "$STOP_AT" +%s)
  [ "$STOP_EPOCH" -le "$("$CORE/date" +%s)" ] && STOP_EPOCH=$("$CORE/date" -d "tomorrow $STOP_AT" +%s)
fi

mkdir -p "$DRAIN/args" "$DRAIN/run-ids" "$DRAIN/logs"
exec 9>"$DRAIN/lock"
if ! flock -n 9; then echo "another drain is running" >&2; exit 75; fi

# Bootstrap: build the work-list from the NAS catalog if absent (fresh state
# root or post-wipe). Rebuilds are cheap afterwards thanks to the page cache.
[ -f "$DRAIN/worklist.jsonl" ] || python3 "$SELF/drain-worklist.py"

log() { echo "$("$CORE/date" -Is) $*" | "$CORE/tee" -a "$DRAIN/drain.log" >&2; }

ran=0 consecutive_failures=0
while IFS= read -r line; do
  db_id=$("$JQ" -r .db_id <<<"$line")
  pages=$("$JQ" -r .pages <<<"$line")

  [ -f "$DATA_ROOT/papers/$db_id/canonical/receipt.json" ] && continue
  if [ -n "$STOP_EPOCH" ] && [ "$("$CORE/date" +%s)" -ge "$STOP_EPOCH" ]; then
    log "stop-at reached; ending after $ran papers"; break
  fi
  if [ "$MAX_PAPERS" -gt 0 ] && [ "$ran" -ge "$MAX_PAPERS" ]; then
    log "max-papers $MAX_PAPERS reached"; break
  fi
  free_gb=$("$CORE/df" --output=avail -B G "$HOME" | "$CORE/tail" -1 | "$CORE/tr" -dc 0-9)
  if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
    log "free space ${free_gb}G below floor ${MIN_FREE_GB}G; stopping"; break
  fi

  args_file="$DRAIN/args/$db_id.json"
  "$JQ" --arg dataRoot "$DATA_ROOT" --arg tools "$SELF" --arg bash "$BASH_BIN" '{
    paperId: .db_id, title: .title, sourceUrl: .file_url, sha256: .sha256,
    pageCount: .pages, dataRoot: $dataRoot, tools: $tools, bash: $bash,
    dpi: 200, ocrModel: "qwen3-vl-8b-ocr", refineModel: "qwen3-vl-32b-ocr",
    embedModel: "qwen3-embedding-8b", minAgreementPermille: 700
  }' <<<"$line" >"$args_file"

  run_id_file="$DRAIN/run-ids/$db_id"
  [ -f "$run_id_file" ] || "$CORE/cat" /proc/sys/kernel/random/uuid >"$run_id_file"
  run_id=$("$CORE/cat" "$run_id_file")

  log "start $db_id pages=$pages run_id=$run_id"
  max_nodes=$((6 * pages + 30))
  # One file per attempt, appended to the paper's log afterwards: the
  # supersede check below must only ever see THIS attempt's output, or a
  # historical args-changed error in the accumulated log would rotate the
  # run id on every later unrelated failure.
  attempt_log="$DRAIN/logs/$db_id.attempt"
  ok=0
  tally flow run "$FLOW" --args "$("$CORE/cat" "$args_file")" \
    --flow-run-id "$run_id" --max-nodes "$max_nodes" \
    >"$attempt_log" 2>&1 && ok=1
  "$CORE/cat" "$attempt_log" >>"$DRAIN/logs/$db_id.log"
  if [ "$ok" = 1 ]; then
    "$CORE/rm" -f "$attempt_log"
    ran=$((ran + 1)); consecutive_failures=0
    sha=$("$JQ" -r .sha256 <<<"$line")
    "$CORE/rm" -f "$DATA_ROOT/blobs/$sha.pdf"
    "$JQ" -c --arg at "$("$CORE/date" -Is)" '. + {completed_at: $at}' <<<"$line" \
      >>"$DRAIN/completed.jsonl"
    log "done $db_id ($ran this session)"
  else
    # A tally pin advance can change the flow-args canonicalization, making
    # every in-flight run's recorded pin unresolvable (FlowReplayError
    # args-changed-mid-run, resolution "supersede" — first seen 2026-08-03,
    # tally.nix#371 class). That is not a systemic failure: rotate the run id
    # so the paper restarts fresh next time, and keep draining.
    if "$GREP" -q '"code":"args-changed-mid-run"' "$attempt_log"; then
      log "SUPERSEDE $db_id: flow-run pin invalidated by a tally pin advance; rotating run id"
      "$CORE/rm" -f "$run_id_file" "$attempt_log"
      continue
    fi
    "$CORE/rm" -f "$attempt_log"
    consecutive_failures=$((consecutive_failures + 1))
    log "FAIL $db_id (consecutive: $consecutive_failures) — see logs/$db_id.log"
    echo "$line" >>"$DRAIN/failed.jsonl"
    if [ "$consecutive_failures" -ge 3 ]; then
      log "3 consecutive failures; systemic fuse blown, stopping"; exit 2
    fi
  fi
done <"$DRAIN/worklist.jsonl"

log "drain session complete: $ran papers"

# Production absorption epilogue: place finished papers into notes and flip
# their sidecar status (one atomic notes commit per session). Non-fatal — a
# failed absorption never blocks the next night; absorb.py is idempotent.
if absorb_out=$(python3 "$SELF/absorb.py" 2>>"$DRAIN/drain.log"); then
  log "absorb: $absorb_out"
else
  log "absorb FAILED (will retry next session)"
fi
