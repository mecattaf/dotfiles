#!/usr/bin/env bash
# pump.sh — the release station, hand-rolled, until W-04 can do it.
# Each tick: harvest deliveries -> start a mechanical evaluator for anything delivered and ungraded
# -> repair station -> release anything whose dependsOn are all PASS-by-someone-other-than-the-author -> report.
# Concurrency is capped; nothing is ever started twice; a unit with a FAIL/CRASH receipt goes to repair.py.
# PUMP_LIB=1 sources the functions below without running the loop (tests/EXTENSION-2026-09-06.md t7).
# --once runs exactly ONE tick and exits 0 (FIX-E11, D-E24): the cadence then belongs to a scheduler
# (dotfiles home/tally-pump.nix's tally-pump.timer, every 5 min) instead of to this script's `sleep 60`.
set -uo pipefail
# 2026-09-20 corrections: this script is now carried by the repository (pkgs/tally-lane-scripts)
# and runs from the nix store, so the lane directory and the receipts directory are named by
# the caller. home/tally-pump.nix sets both. Defaults are UNCHANGED, so a hand-run pump on a
# box where nothing has moved yet behaves exactly as it did.
LANE=${LANE_DIR:-/home/tom/sept7/plan/codex-lane}   # LANE_DIR: the lane tree (tests pass a scratch lane; the unit passes the live one)
RECEIPTS=${PUMP_RECEIPTS_DIR:-/home/tom/research-methods/receipts/FACTORY-2026-09-06}
MAXW=${MAXW:-14}
# ONCE (FIX-E11, D-E24): why a verb and not a second script. MEASURED 2026-09-07: the looping form broke out of
# the while loop after two quiescent ticks ("PUMP: quiescent — nothing running, nothing releasable" at tick137),
# pump.pid was left naming a process dead since 21:42, and nothing — no unit, no timer, no cron — restarted it, so
# every start on record was a typed line. A tick is idempotent already (harvest, reconcile, seat pick, evaluators,
# repair, release), so the fix is to let a scheduler own the cadence: --once does one tick, sleeps not at all,
# never applies the two-quiet-tick break (which is LOOP control and means nothing when there is no loop), never
# prints the quiescent line, and exits 0 — a timer that finds nothing to do must not read as a failure. The
# looping form is unchanged for a human who wants to watch it.
ONCE=0
# Guarded by PUMP_LIB because "$@" is the CALLER's argv when this file is sourced as a library (t7), and a
# probe's own flags must not be read as the pump's.
if [ -z "${PUMP_LIB:-}" ]; then
  for arg in "$@"; do
    case "$arg" in
      --once) ONCE=1;;
      *) echo "PUMP: unknown argument '$arg' (usage: pump.sh [--once])"; exit 2;;
    esac
  done
fi
CLAUDE_EVAL="E2E-1"  # D-B59 supersedes D-B36: D-B57 measured two Claude evaluators missing a defect a Codex
                     # evaluator then caught, so routing by harness is retired. E2E-1 stays out because it is
                     # orchestrator-held (next.py HELD), not because of who evaluates it.

# eval_gate <unit> [tick] — 0: start an evaluator for this unit; 1: do not.
# The stale-pid hole (2026-09-06): the old test was '[ -e evals/<u>/pid ] && continue', so a unit whose evaluator
# had DIED without writing a verdict (killed at the stop, crashed, machine rebooted) was skipped forever, its dead
# pid file standing in for a grading that never happened. Now a dead evaluator pid with no verdict is quarantined
# (moved to evals/.dead-<u>-<utc>, never deleted) and the unit is re-evaluated. A dead evaluator whose verdict is
# FAIL/CRASH did grade ONLY IF the receipt graded the commit that is delivered now (C-1, 2026-09-06): a FAIL receipt
# at an OLDER commit is a stale verdict — the post-repair delivery's evaluator died before writing its receipt, so
# the unit is quarantined and re-evaluated exactly like a verdict-less death; otherwise repair.py would wait on it
# forever. Only a same-commit FAIL/CRASH belongs to the repair station. PASS is skipped before this (D-B61).
eval_gate() {
  local u="$1" tick="${2:-?}" v vout vrc ep q graded delivered
  # V-2 (2026-09-06): FAIL CLOSED. next.py prints the whole state table before the verdict line, so a crash
  # after the table left 'tail -1' holding a state line (or nothing), which matched neither PASS nor
  # FAIL|CRASH and fell through to "evaluate" — a guard that opened on the very failure it was meant to
  # catch. The rc is captured first; a non-zero rc, or a last line outside the closed set of verdicts
  # next.py can print, is 'do not evaluate' with the reason on stdout.
  vout=$(python3 "$LANE/next.py" --verdict "$u" 2>/dev/null); vrc=$?
  if [ "$vrc" != 0 ]; then echo "PUMP tick$tick: next.py failed for $u (rc $vrc) — not evaluating"; return 1; fi
  v=$(printf '%s\n' "$vout" | tail -1)
  case "$v" in
    none|PASS|PASS-UNMERGED|FAIL|CRASH|SELF-CLAIM) ;;
    *) echo "PUMP tick$tick: next.py printed an unknown verdict '$v' for $u — not evaluating"; return 1;;
  esac
  # D-B61: a unit already graded PASS is done; re-grading it burns a window and races the merge that
  # already happened. Removing the CLAUDE_EVAL list in D-B59 removed the guard that had been doing
  # this by accident, and tick 1 started evaluators on U-A17, U-A18 and U-D17, all merged and PASS.
  [ "$v" = PASS ] && return 1
  # V-3 (2026-09-06): a receipt PASS whose merge_commit is none/pending-integrator reads PASS-UNMERGED
  # (D-B45). It is graded; what is missing is a merge, which is the integrator's act, not a re-grade.
  # Before this line it matched neither PASS nor FAIL|CRASH, so a dead evaluator pid quarantined the
  # dir and the unit was graded again — burning a window to reach the same PASS it already holds.
  # D-B45 keeps its dependents blocked until the merge lands; the orchestrator handles the merge.
  if [ "$v" = PASS-UNMERGED ]; then echo "PUMP tick$tick: $u graded PASS but not merged — integrator needed, not re-grading"; return 1; fi
  # N-7 (2026-09-07, D-B86): a FAIL/CRASH receipt that graded the commit currently delivered is the repair
  # station's, whether or not an evals dir still exists (resume.sh removes it, so the same-commit check inside
  # the pid branch below was skipped and U-E6 was re-graded at the same sha — one codex grading wasted).
  case "$v" in FAIL|CRASH)
    graded=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('commit_sha') or '')" "$RECEIPTS/$u/receipt.json" 2>/dev/null)
    delivered=$(python3 -c "import json,sys;print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get('commit_sha') or '')" "$LANE/results.json" "$u" 2>/dev/null)
    if [ -n "$graded" ] && [ -n "$delivered" ] && { case "$graded" in "$delivered"*) true;; *) case "$delivered" in "$graded"*) true;; *) false;; esac;; esac; }; then return 1; fi;;
  esac
  if [ -e "$LANE/evals/$u/pid" ]; then
    ep=$(cat "$LANE/evals/$u/pid" 2>/dev/null)
    if [ -n "$ep" ] && kill -0 "$ep" 2>/dev/null; then return 1; fi
    case "$v" in FAIL|CRASH)
      graded=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('commit_sha') or '')" "$RECEIPTS/$u/receipt.json" 2>/dev/null)
      delivered=$(python3 -c "import json,sys;print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get('commit_sha') or '')" "$LANE/results.json" "$u" 2>/dev/null)
      if [ -n "$graded" ] && [ -n "$delivered" ] && { case "$graded" in "$delivered"*) true;; *) case "$delivered" in "$graded"*) true;; *) false;; esac;; esac; }; then return 1; fi
      v="$v@${graded:-?} (delivered ${delivered:-?}) — stale";;
    esac
    q="$LANE/evals/.dead-$u-$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$LANE/evals/$u" "$q" || return 1
    echo "PUMP tick$tick: evaluator of $u is DEAD (pid ${ep:-none}) with verdict '$v' — quarantined to $q, re-evaluating"
  fi
  return 0
}

# pick_eval_seat <tick> — sets EVAL_SEAT (D-B70): codex while codex-window.py reads < 96; at >= 96, or when the
# window is unreadable AND grading has already moved off codex, the Claude seat with the larger MEASURED seven-day
# headroom through seat.py --pick-eval (which holds a seat at its five-hour wall or with an UNKNOWN reading).
# If no Claude seat is free the current seat is kept and it says so. Never estimated.
pick_eval_seat() {
  local tick="${1:-?}" cx moved=0 pick
  cx=$(python3 "$LANE/codex-window.py" 2>/dev/null || echo "")
  if [ -n "$cx" ] && [ "${cx%%.*}" -ge 96 ] 2>/dev/null; then moved=1
  elif [ -z "$cx" ] && [ "${EVAL_SEAT:-codex}" != codex ]; then moved=1; echo "PUMP tick$tick: codex window unreadable; grading already off codex (${EVAL_SEAT}), re-picking"
  elif [ -z "$cx" ]; then echo "PUMP tick$tick: codex window unreadable; grading stays on ${EVAL_SEAT:-codex}"; fi
  if [ "$moved" = 1 ]; then
    pick=$(python3 "$LANE/seat.py" --pick-eval 2>/dev/null | tail -1)
    case "$pick" in
      cc2|cc3) [ "${EVAL_SEAT:-codex}" != "$pick" ] && echo "PUMP tick$tick: codex window ${cx:+$cx%}${cx:-unreadable} — grading moves to $pick"; export EVAL_SEAT="$pick";;
      *) if [ "${EVAL_SEAT:-codex}" = codex ]; then
           # D-E12: codex at/over 96 is never graded on; with no Claude seat free, no evaluator starts this tick.
           echo "PUMP tick$tick: codex window ${cx:+$cx%}${cx:-unreadable} and no Claude seat is free ($pick) — no evaluator this tick"; export EVAL_SEAT=HOLD
         else echo "PUMP tick$tick: codex window ${cx:+$cx%}${cx:-unreadable} but no Claude seat is free ($pick) — grading stays on ${EVAL_SEAT}"; fi;;
    esac
  fi
}

# harvest_step <tick> — the tick's harvest, which can now FAIL LOUDLY (FIX-E02, D-E24).
# The old line was `python3 "$LANE/harvest.py" >/dev/null 2>&1 || true`: a throw left results.json STALE and
# silent while every downstream decision of the same tick — eval_gate's delivered sha, repair.py's results.get(u),
# next.py's delivered_unevaluated — read whatever the last successful harvest wrote. The output is now kept in
# harvest.log and a non-zero rc is logged with the tail that explains it. The step still returns 0: a failed
# harvest does not abort the tick (the tick's other steps are what notice a stale reading), it is RECORDED.
harvest_step() {
  local tick="${1:-?}" rc=0 tail
  if [ -f "$LANE/harvest.log" ] && [ "$(stat -c%s "$LANE/harvest.log" 2>/dev/null || echo 0)" -gt 4000000 ]; then
    : > "$LANE/harvest.log"
  fi
  echo "== tick$tick $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LANE/harvest.log"
  python3 "$LANE/harvest.py" >> "$LANE/harvest.log" 2>&1 || rc=$?
  if [ "$rc" != 0 ]; then
    tail=$(tail -3 "$LANE/harvest.log" | tr '\n' ' ' | tail -c 200)
    echo "PUMP tick$tick: harvest FAILED rc $rc — decisions this tick read a stale results.json [$tail]"
  fi
  return 0
}

[ -n "${PUMP_LIB:-}" ] && return 0 2>/dev/null

# D-B89 (2026-09-07): exactly one pump. The pump records ITS OWN pid (a pid captured by the launcher's $! was the
# harness wrapper's once, so a kill-by-recorded-pid missed and two pumps ran for 47 minutes, one of them
# re-launching a delivered unit over its evaluator). If pump.pid names a live process that is not us, exit.
# FIX-E11 keeps this guard in front of --once too, and that is the whole reason --once still writes the pid
# file: a 5-minute timer tick and a human's looping pump must never overlap, whichever started first. The
# refusal is rc 3 with 'PUMP: another pump holds <pid>' — never rc 0, so the manager records the skip.
if [ -z "${PUMP_LIB:-}" ]; then
  if [ -s "$LANE/pump.pid" ]; then
    op=$(cat "$LANE/pump.pid"); if [ -n "$op" ] && [ "$op" != "$$" ] && kill -0 "$op" 2>/dev/null; then echo "PUMP: another pump holds $op — refusing to start a second one"; exit 3; fi
  fi
  echo $$ > "$LANE/pump.pid"
fi
tick=0
while true; do
  tick=$((tick+1))
  [ "$ONCE" = 1 ] && echo "PUMP tick$tick: --once begin $(date -u +%Y-%m-%dT%H:%M:%SZ) (pid $$, MAXW $MAXW)"
  harvest_step "$tick"
  # D-B88: stamp merge_commit on PASS receipts the world shows merged (evaluators merge after writing).
  rec=$(python3 "$LANE/merge-reconcile.py" 2>/dev/null | grep "^RECONCILE" || true); [ -n "$rec" ] && echo "PUMP tick$tick: $rec"
  pick_eval_seat "$tick"
  alive=$(ls -d "$LANE"/runs/*/ "$LANE"/evals/*/ 2>/dev/null | while read -r d; do p=$(cat "$d/pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo x; done | wc -l)
  # 1. evaluators for delivered, ungraded units (runs/*/ and evals/*/ are bash globs: dot-dirs — probes and
  #    quarantined evaluators — are never seen)
  for d in "$LANE"/runs/*/; do
    u=$(basename "$d")
    case " $CLAUDE_EVAL " in *" $u "*) continue;; esac
    eval_gate "$u" "$tick" || continue
    p=$(cat "$d/pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && continue
    st=$(python3 -c "import json;print((json.load(open('$LANE/results.json')).get('$u') or {}).get('status',''))" 2>/dev/null)
    [ "$st" = delivered ] || continue
    [ "$alive" -ge "$MAXW" ] && break
    [ "${EVAL_SEAT:-codex}" = HOLD ] && { echo "PUMP tick$tick: $u delivered, evaluator held (no seat)"; continue; }
    echo "PUMP tick$tick: evaluating $u on ${EVAL_SEAT:-codex}"
    "$LANE/evaluate.sh" "$u" >/dev/null 2>&1 && alive=$((alive+1))
  done
  # 1b. the repair station (D-B67): a unit graded FAIL, idle, whose receipt names defects against the
  # commit that is actually delivered, gets its own worker resumed on its own thread with those defects
  # quoted verbatim. Parks with a written reason on an empty defect list, a repeated defect list (not
  # converging) or the round cap; a stale verdict (receipt at an older sha than the delivery) is WAITED on,
  # not parked (C-1) — eval_gate above re-grades it. Without this the release station stalls on every FAIL
  # and waits for a human, which is the one thing this factory is built not to need.
  if [ "$alive" -lt "$MAXW" ]; then
    rep=$(python3 "$LANE/repair.py" 2>&1 | grep '^REPAIR' || true)
    [ -n "$rep" ] && echo "$rep"
  fi

  # 2. release whatever the graph now allows (next.py routes each unit by measured headroom; ROUTE/HOLD lines are kept)
  if [ "$alive" -lt "$MAXW" ]; then
    # FIX-E02: LAUNCH-FAIL / LAUNCH-SKIP / MANIFEST BAD are release decisions and are kept in the log too.
    out=$(python3 "$LANE/next.py" --launch 2>"$LANE/next.err" | grep -E '^(launching|ROUTE|HOLD|LAUNCH-FAIL|LAUNCH-SKIP|MANIFEST BAD|ISSUES BAD)' || true)
    if [ -s "$LANE/next.err" ]; then echo "PUMP tick$tick: next.py STDERR: $(tail -3 "$LANE/next.err" | tr '\n' ' ')"; fi
    [ -n "$out" ] && echo "PUMP tick$tick: $out"
  fi
  # 3. --once ends HERE: one tick, rc 0, no sleep and no quiescence test at all. The block below is loop
  #    control — it decides whether to iterate again — so under --once it is not merely skipped for its
  #    output's sake, it has nothing to decide. pump.pid is left on disk exactly as the looping form leaves
  #    it (the guard above tolerates a dead pid), so the next timer tick and any looping pump still see it.
  if [ "$ONCE" = 1 ]; then
    echo "PUMP tick$tick: --once end rc 0 $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    exit 0
  fi
  # 3b. stop when nothing is running and nothing is releasable (LOOPING form only).
  # D-B60: `alive` above is measured at the top of the tick and this tick may have started workers,
  # so recount processes here; and require two consecutive quiescent ticks, because a worker that has
  # just been forked can be missed once. The earlier form exited during its own launch race.
  now=$(ls -d "$LANE"/runs/*/ "$LANE"/evals/*/ 2>/dev/null | while read -r d; do p=$(cat "$d/pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo x; done | wc -l)
  rel=$(python3 "$LANE/next.py" 2>/dev/null | sed -n 's/^releasable now: //p')
  if [ "$now" = 0 ] && [ "$rel" = "none" ]; then
    quiet=$((${quiet:-0}+1))
    echo "PUMP tick$tick: quiet $quiet/2"
    [ "$quiet" -ge 2 ] && { echo "PUMP: quiescent — nothing running, nothing releasable"; break; }
  else quiet=0; fi
  sleep 60
done
