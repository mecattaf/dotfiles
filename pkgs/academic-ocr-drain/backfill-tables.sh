#!/usr/bin/env bash
# backfill-tables.sh [--scan] [--max-papers N] [--min-numeric-run K]
#
# One-time repair pass for the table defect (Tom's ruling, 2026-08-06: tables
# route to the VLM lane). Every page that resolved source:mech before the gate
# shipped was accepted on a column-major linearization of its table — all the
# values, none of the row/column association — and receipts make each of those
# pages individually targetable. Measured at ship time: 462 pages across 142
# papers, 17.4% of all source:mech pages.
#
# The repair re-runs the WHOLE paper through paper-e2e.js on a fresh flow-run
# id rather than re-implementing the per-page ladder here. That costs 175
# redundant VLM re-runs across the queue (pages in affected papers that already
# went to the VLM) on top of the 462 pages that actually need it, and buys the
# only property worth having in a repair tool: the repaired paper goes through
# the exact same audited flow, assembler, chunker, embedder, indexer and
# receipt as a freshly drained one. No second ladder to keep in sync.
#
# Runs ALONGSIDE the live drain, deliberately, on its own lock: the drain skips
# any paper carrying a receipt, and every paper in this queue has one, so the
# two never contend for a paper. The shared blob directory is sha-keyed, and
# tally's low-priority coordinator-gpu pool arbitrates GPU time exactly as it
# does between the drain and interactive work. Interruption is safe at any
# point: a paper keeps its old receipt and old paper.md until the new ones
# replace them atomically at the end of its flow.
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/env.sh"

DATA_ROOT="${DATA_ROOT:-$HOME/.local/state/academic-ocr}"
NOTES="${NOTES_REPO:-$HOME/mecattaf/notes}"
DRAIN="$DATA_ROOT/drain"
FLOW="$SELF/paper-e2e.js"
BASH_BIN="$(command -v bash)"
SCAN_ONLY=0 MAX_PAPERS=0 MIN_RUN=4

while [ $# -gt 0 ]; do
  case "$1" in
    --scan) SCAN_ONLY=1; shift ;;
    --max-papers) MAX_PAPERS="$2"; shift 2 ;;
    --min-numeric-run) MIN_RUN="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$DRAIN/args" "$DRAIN/run-ids" "$DRAIN/logs"
log() { echo "$("$CORE/date" -Is) backfill: $*" | "$CORE/tee" -a "$DRAIN/backfill.log" >&2; }

# ── Scan: which receipted pages resolved mech on a table? ────────────────────
# Verdict files land under the paper's own verdicts/ dir, so a scan leaves the
# same evidence a live run would.
scan() {
  local queue="$1" pdir id page p mech hits
  : > "$queue"
  for pdir in "$DATA_ROOT"/papers/*/; do
    id="$(basename "$pdir")"
    [ -f "$pdir/canonical/receipt.json" ] || continue
    hits=""
    while IFS= read -r page; do
      p=$("$CORE/printf" '%03d' "$page")
      mech="$pdir/mech/$p/poppler.txt"
      [ -f "$mech" ] || continue
      if ! "$BASH_BIN" "$SELF/tables.sh" "$mech" \
           "$pdir/verdicts/$p-tables.json" "$MIN_RUN" >/dev/null 2>&1; then
        hits="$hits $page"
      fi
    done < <("$JQ" -r '.pages[] | select(.source | startswith("mech")) | .page' \
             "$pdir/canonical/receipt.json")
    [ -n "$hits" ] && "$JQ" -nc --arg id "$id" --arg pages "${hits# }" \
      '{db_id: $id, pages: ($pages | split(" ") | map(tonumber))}' >> "$queue"
  done
}

queue="$DRAIN/backfill-queue.jsonl"
if [ "$SCAN_ONLY" = 1 ]; then
  scan "$queue"
  "$JQ" -s '{papers: length, pages: (map(.pages | length) | add // 0),
             minNumericRun: '"$MIN_RUN"'}' "$queue"
  exit 0
fi

exec 9>"$DRAIN/backfill.lock"
if ! flock -n 9; then echo "another backfill is running" >&2; exit 75; fi

scan "$queue"
total=$("$CORE/wc" -l < "$queue")
log "queue: $total papers with table-evidence mech pages"

repaired=0 consecutive_failures=0
declare -a absorbed_ids=()
while IFS= read -r entry; do
  db_id=$("$JQ" -r .db_id <<<"$entry")
  npages=$("$JQ" -r '.pages | length' <<<"$entry")
  if [ "$MAX_PAPERS" -gt 0 ] && [ "$repaired" -ge "$MAX_PAPERS" ]; then
    log "max-papers $MAX_PAPERS reached"; break
  fi

  # Rebuild the flow args from the drain's own record of this paper, repointed
  # at THIS package (the recorded tools path is the store path that drained it)
  # and carrying the table threshold the scan used.
  src_args="$DRAIN/args/$db_id.json"
  if [ ! -f "$src_args" ]; then
    log "SKIP $db_id: no recorded flow args"; continue
  fi
  args_file="$DRAIN/args/$db_id.backfill.json"
  "$JQ" --arg tools "$SELF" --arg bash "$BASH_BIN" --arg dr "$DATA_ROOT" \
    --argjson run "$MIN_RUN" \
    '.tools=$tools | .bash=$bash | .dataRoot=$dr | .tableMinNumericRun=$run' \
    "$src_args" > "$args_file"
  pages=$("$JQ" -r .pageCount "$args_file")

  # A fresh run id, not the drained one: that run recorded the pre-gate script
  # pin, which no longer resolves. Persisted so an interrupted backfill resumes
  # the same run instead of starting over.
  run_id_file="$DRAIN/run-ids/$db_id.backfill"
  [ -f "$run_id_file" ] || "$CORE/cat" /proc/sys/kernel/random/uuid >"$run_id_file"
  run_id=$("$CORE/cat" "$run_id_file")

  log "repair $db_id ($npages table page(s) of $pages) run_id=$run_id"
  attempt_log="$DRAIN/logs/$db_id.backfill.attempt"
  ok=0
  tally flow run "$FLOW" --args "$("$CORE/cat" "$args_file")" \
    --flow-run-id "$run_id" --max-nodes $((8 * pages + 30)) \
    >"$attempt_log" 2>&1 && ok=1
  "$CORE/cat" "$attempt_log" >>"$DRAIN/logs/$db_id.log"

  if [ "$ok" = 1 ]; then
    "$CORE/rm" -f "$attempt_log" "$args_file"
    sha=$("$JQ" -r .sha256 "$src_args")
    "$CORE/rm" -f "$DATA_ROOT/blobs/$sha.pdf"
    repaired=$((repaired + 1)); consecutive_failures=0
    absorbed_ids+=("$db_id")
    "$JQ" -nc --arg id "$db_id" --argjson n "$npages" --arg at "$("$CORE/date" -Is)" \
      '{db_id: $id, tablePagesRepaired: $n, repaired_at: $at}' >> "$DRAIN/backfilled.jsonl"
    log "done $db_id ($repaired repaired)"
  else
    # Same supersede class the drain handles: a tally pin advance or a flow
    # ship invalidates the recorded pin mid-run. Rotate and let the next pass
    # start the paper fresh rather than counting it against the fuse.
    if "$GREP" -qE '"code":"(args|script)-changed-mid-run"' "$attempt_log"; then
      log "SUPERSEDE $db_id: run pin invalidated; rotating run id"
      "$CORE/rm" -f "$run_id_file" "$attempt_log"
      continue
    fi
    "$CORE/rm" -f "$attempt_log"
    consecutive_failures=$((consecutive_failures + 1))
    log "FAIL $db_id (consecutive: $consecutive_failures) — see logs/$db_id.log"
    if [ "$consecutive_failures" -ge 3 ]; then
      log "3 consecutive failures; systemic fuse blown, stopping"; exit 2
    fi
  fi
done <"$queue"

log "backfill pass complete: $repaired papers repaired"

# ── Re-absorption ────────────────────────────────────────────────────────────
# absorb.py cannot do this one: it treats a paper as done once it is in the
# ledger, and it refuses to overwrite an existing target .md — both correct for
# the forward path, both wrong for a repair. Here the target is known from the
# ledger and overwriting it IS the point. Papers not yet absorbed need nothing;
# the drain's own epilogue will place the repaired paper.md when it gets there.
[ "${#absorbed_ids[@]}" -eq 0 ] && exit 0
ledger="$DRAIN/absorbed.jsonl"
[ -f "$ledger" ] || exit 0
placed=0
for db_id in "${absorbed_ids[@]}"; do
  target=$("$JQ" -r --arg id "$db_id" 'select(.db_id==$id) | .target' "$ledger" | "$CORE/tail" -1)
  [ -n "$target" ] && [ -f "$target" ] || continue
  "$CORE/cp" "$DATA_ROOT/papers/$db_id/canonical/paper.md" "$target"
  git -C "$NOTES" add -- "$target" || continue
  placed=$((placed + 1))
done
if [ "$placed" -gt 0 ]; then
  if git -C "$NOTES" commit -q -m "reabsorb $placed OCR papers repaired by the table backfill

Pages that resolved source:mech on a linearized table are re-transcribed
through the VLM lane and the papers reassembled (pipeline stamp
tally-flow-e2e-2026-08-06). Text-only, per the standing option-A ruling.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"; then
    log "reabsorbed $placed papers into notes"
  else
    log "reabsorb commit FAILED (files staged; rerun to retry)"
  fi
fi
