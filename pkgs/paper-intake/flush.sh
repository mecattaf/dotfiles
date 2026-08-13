#!/usr/bin/env bash
# paper-print-flush — submit spooled print jobs from the outbox to CUPS.
#
# Quiet hours (00:00–06:00): print-auto renders documents at any hour but
# spools the physical submission as one JSON entry per job in
# ~/Paper/outbox. This flusher runs from a Persistent 06:05 user timer (or
# by hand) and mirrors print-paper.py's exact lp invocation. It refuses to
# flush during quiet hours unless PAPER_PRINT_FORCE=1, so a stray manual
# run at 03:00 cannot defeat the window. A failed submission keeps its
# spool entry and fails the unit so it surfaces; nothing is ever deleted
# without a successful lp hand-off.
set -euo pipefail

OUTBOX="${PAPER_OUTBOX:-$HOME/Paper/outbox}"
DEFAULT_PRINTER="${PRINT_PAPER_PRINTER:-Brother_HL_L2445DW}"

hour="$(date +%-H)"
if [[ "${PAPER_PRINT_FORCE:-0}" != "1" && "$hour" -lt 6 ]]; then
  echo "paper-print-flush: quiet hours (0-6); leaving outbox untouched"
  exit 0
fi

shopt -s nullglob
entries=("$OUTBOX"/*.json)
if [[ ${#entries[@]} -eq 0 ]]; then
  exit 0
fi

failures=0
for entry in "${entries[@]}"; do
  pdf="$(jq -r '.pdf' "$entry")"
  sides="$(jq -r '.sides // "two-sided-long-edge"' "$entry")"
  printer="$(jq -r --arg d "$DEFAULT_PRINTER" '.printer // $d' "$entry")"
  job_dir="$(jq -r '.job_dir // empty' "$entry")"

  if [[ ! -f "$pdf" ]]; then
    echo "paper-print-flush: missing PDF for $entry ($pdf); keeping entry" >&2
    failures=$((failures + 1))
    continue
  fi

  if out="$(lp -d "$printer" -n 1 -o media=A4 -o "sides=$sides" "$pdf" 2>&1)"; then
    if [[ -n "$job_dir" && -d "$job_dir" ]]; then
      printf '{"printed_at":"%s","lp":"%s"}\n' "$(date -Is)" "$out" \
        >"$job_dir/printed.json"
    fi
    rm -f -- "$entry"
    echo "paper-print-flush: submitted $pdf ($out)"
  else
    echo "paper-print-flush: lp failed for $pdf: $out" >&2
    failures=$((failures + 1))
  fi
done

exit "$((failures > 0 ? 1 : 0))"
