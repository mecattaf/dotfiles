#!/usr/bin/env bash
# drain-stop.sh — THE stop verb for the academic drain (#145).
#
# The 2026-08-03 incident took five steps to stop the drain and still lost a
# paper to degraded quality. This is those steps as one command, in the only
# order that closes every race:
#
#   1. Stop the unit FIRST. That kills the driver and clears Restart=, so the
#      loop can never advance to the next paper while the flow is being
#      cancelled, and nothing respawns in RestartSec.
#   2. Cancel the in-flight flow run to terminal. `tally flow cancel` is a
#      snapshot verb — it cancels what is running at that instant and the DAG
#      keeps dispatching nodes that become ready afterwards — so it is
#      re-issued until the run reports no live nodes (two calls ~15s apart
#      were needed in the incident; there is still no terminal-kill verb).
#   3. If a receipt for the in-flight paper appeared while the cancel was in
#      progress, that is a degraded result racing the cancel (the incident
#      locked in six vlm8b-disputed pages exactly this way): remove the
#      receipt and the persisted run id so the next drain session redoes the
#      paper at full quality. paper-e2e.js now refuses to assemble after a
#      cancelled node, so this guard only catches the narrow window where
#      assembly was already past the cancelled pages when the cancel landed.
#
# The table backfill (academic-backfill-tables.service, transient) has its own
# lifecycle: `systemctl --user stop academic-backfill-tables` is safe at any
# point and it resumes where it left off on relaunch.
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/env.sh"

DATA_ROOT="${DATA_ROOT:-$HOME/.local/state/academic-ocr}"
DRAIN="$DATA_ROOT/drain"
SYSTEMCTL="${SYSTEMCTL:-/run/current-system/sw/bin/systemctl}"
CANCEL_TRIES="${CANCEL_TRIES:-12}"

log() { echo "$("$CORE/date" -Is) stop: $*" | "$CORE/tee" -a "$DRAIN/drain.log" >&2; }

stop_epoch=$("$CORE/date" +%s)
"$SYSTEMCTL" --user stop academic-drain.service
log "academic-drain.service stopped"

# One `start <db_id> pages=N run_id=<uuid>` line per attempt; the last one
# names the only run that can still be live now that the driver is dead.
last_start=$("$GREP" -E ' start [0-9a-f-]{36} .*run_id=' "$DRAIN/drain.log" 2>/dev/null | "$CORE/tail" -1 || true)
if [ -z "$last_start" ]; then
  log "no start line in drain.log; nothing to cancel"
  exit 0
fi
db_id=$(echo "$last_start" | "$AWK" '{ for (i=1;i<=NF;i++) if ($i=="start") { print $(i+1); exit } }')
run_id="${last_start##*run_id=}"

# Live means the daemon could still dispatch something for this run: any
# current node, or any task not yet done. A failed query (daemon down) reads
# as terminal — with the driver dead and the daemon down, nothing dispatches.
live() {
  tally query run "$run_id" --json 2>/dev/null | "$JQ" -e \
    '((.currentNodes | length) + .counts.running + .counts.blocked + .counts.pending) > 0' \
    >/dev/null 2>&1
}

if ! live; then
  log "run $run_id already terminal"
else
  tries=0
  while [ "$tries" -lt "$CANCEL_TRIES" ]; do
    tally flow cancel "$run_id" >/dev/null 2>&1 || true
    tries=$((tries + 1))
    "$CORE/sleep" 5
    live || break
  done
  if live; then
    log "run $run_id STILL reports live nodes after $tries cancels; inspect: tally query run $run_id"
    exit 1
  fi
  log "run $run_id cancelled to terminal after $tries cancel(s)"
fi

receipt="$DATA_ROOT/papers/$db_id/canonical/receipt.json"
if [ -f "$receipt" ] && [ "$("$CORE/stat" -c %Y "$receipt")" -ge "$stop_epoch" ]; then
  "$CORE/rm" -f "$receipt" "$DRAIN/run-ids/$db_id"
  log "receipt for $db_id was written during the cancel window; removed it and rotated the run id for a full-quality rerun"
fi

log "drain fully stopped"
