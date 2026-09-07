#!/usr/bin/env bash
# tools/seat-rows-oracle.sh — CAP-1 SEAT-ROWS-UNTIL, the DOMINANT oracle.
#
# UNIT: CAP-1 (dotfiles#337). CARD: /home/tom/sept7/plan/UNITS-2026-09-06.json.
# SPEC: TALLY-SPEC-2026-09-06.md §2.4; mecattaf/tally docs/rows.md and
# docs/meter-row-contract.md §window; DECISIONS D-B92, D-B95.
#
# WHAT IT ASSERTS. For each of cc, cc2, cc3, codex, pi-qwencloud, in the
# rewrite's meters directory:
#
#   * the row exists and is JSON;
#   * `window.kind` is `nested` or `rolling` — never absent, never `none` — or
#     the WHOLE window is the string UNKNOWN with a `window_reason` beside it,
#     which is the one honest answer when nothing on this box states the span's
#     reset instant (dotfiles#343 for pi-qwencloud, dotfiles#349/FIX-E06 for a
#     Claude seat whose five-hour reset the endpoint omits). A row in that state
#     must ALSO carry none of the flat window keys (`window_minutes`,
#     `resets_at`, `secondary`), because the kernel's reader would project a
#     window out of them that the row declined to declare;
#   * every span of that window carries `minutes` > 0, a `resets_at` that is
#     RFC 3339, and a `utilization_pct` that is a number in 0..100 — or the
#     whole span is the string UNKNOWN with a reason cell beside it, or its
#     utilization alone is UNKNOWN with a `utilization_reason`. A nested
#     window must carry BOTH spans: the Claude seats' promise is the pair;
#   * `window_remaining_pct` is a number in 0..100, or UNKNOWN with a
#     `window_remaining_reason`;
#   * cc, cc2 and cc3 carry `model_split.opus == "UNKNOWN"` and
#     `model_split.sonnet == "UNKNOWN"` with a reason (the usage endpoint
#     answers null for seven_day_opus/seven_day_sonnet);
#   * cc, cc2, cc3 and codex carry a NUMBER in `utilization_pct` — a reader
#     timeout must keep the last MEASURED reading, never blank the row — and a
#     row grading itself STALE-MEASURED must say how old its reading is
#     (`reading_age_seconds`);
#   * the kernel's own rows (gpu-coordinator, gpu-worker, mechanical) are
#     skipped BY NAME: the kernel re-stamps them at probe time and this unit
#     changes nothing about them;
#
# and finally that `nix flake check --offline --no-build` stays green.
#
# HOW TO RUN IT.
#
#   bash tools/seat-rows-oracle.sh              # runs ONE feeder pass into a
#                                               # scratch dir and asserts on it
#   bash tools/seat-rows-oracle.sh <meters-dir> # asserts on a directory that
#                                               # already holds a feeder pass
#
# With no argument the script is self-contained, which is what a fresh
# worktree needs: it runs the repository's own feeder — the three instruments,
# unmodified — with TALLY_REWRITE_METERS pointed at a scratch directory, then
# asserts on what landed there. It writes nothing under ~/.local/state at all.
# With an argument it asserts on the live directory after a feeder pass
# (`systemctl --user start tally-seat-feeder-claude.service` etc.).
#
# TALLY_METERS_DIR is honoured as the directory when no argument is given, so
# the manifest's own wording for the scratch-dir form works verbatim.
#
# Exit: 0 all rows complete and the flake check green; 1 a row is incomplete
# (every failing row and cell is named on stdout); 2 usage or a missing tool.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SEAT_ROWS=(cc cc2 cc3 codex pi-qwencloud)
CLAUDE_ROWS=(cc cc2 cc3)
NUMERIC_ROWS=(cc cc2 cc3 codex)
# Named so the skip is a decision and not an accident of globbing: these are
# the kernel's own rows, re-stamped by the kernel at every admit probe.
KERNEL_ROWS=(gpu-coordinator gpu-worker mechanical)

usage() {
  printf 'usage: bash tools/seat-rows-oracle.sh [meters-dir]\n' >&2
  exit 2
}

[[ $# -le 1 ]] || usage
case "${1:-}" in -h | --help) usage ;; esac

for tool in jq python3 nix; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'seat-rows-oracle: %s is not on PATH\n' "$tool" >&2
    exit 2
  }
done

meters=${1:-${TALLY_METERS_DIR:-}}
scratch=""
if [[ -z "$meters" ]]; then
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/seat-rows-oracle.XXXXXX")
  trap 'rm -rf -- "$scratch"' EXIT
  meters="$scratch"
  printf '== one feeder pass into %s\n' "$meters"
  for instrument in claude codex pi-qwencloud; do
    TALLY_REWRITE_METERS="$meters" \
      SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt} \
      NIX_SSL_CERT_FILE=${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt} \
      python3 "$repo/home/dot_local/bin/tally-seat-feeder" "$instrument" ||
      {
        printf 'seat-rows-oracle: the %s instrument exited non-zero\n' "$instrument"
        exit 1
      }
  done
else
  printf '== asserting on %s (no feeder pass; the caller made one)\n' "$meters"
fi

[[ -d "$meters" ]] || {
  printf 'seat-rows-oracle: %s is not a directory\n' "$meters" >&2
  exit 2
}

printf '== kernel rows skipped by name: %s\n' "${KERNEL_ROWS[*]}"

# The whole row contract, as one jq program. $claude and $numeric carry the two
# per-row distinctions; everything else is the same question of every row.
read -r -d '' PROGRAM <<'JQEOF' || true
def rfc3339:
  type == "string"
  and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$");
def isnum: type == "number";
def unknownstr: type == "string" and (ascii_downcase == "unknown");
def hasreason: type == "string" and (length > 0);

# One span: an object with a period, an RFC 3339 reset and a utilization that
# is a number or an UNKNOWN naming its reason — or the whole span replaced by
# the string UNKNOWN, with its reason on the window beside it.
def span($cell; $reasonkey; $holder):
  . as $s
  | if ($s | unknownstr) then
      (if ($holder[$reasonkey] // null | hasreason) then []
       else ["\($cell) is UNKNOWN with no \($reasonkey) cell beside it"] end)
    elif ($s | type) != "object" then
      ["\($cell) is \($s | tojson), neither a span object nor the string UNKNOWN"]
    else
      (if ($s.minutes | isnum) and ($s.minutes > 0) then []
       else ["\($cell).minutes is \($s.minutes | tojson), not a positive number"] end)
      + (if ($s.resets_at // null | rfc3339) then []
         else ["\($cell).resets_at is \($s.resets_at | tojson), not RFC 3339"] end)
      + (if ($s.utilization_pct | isnum) then
           (if ($s.utilization_pct >= 0 and $s.utilization_pct <= 100) then []
            else ["\($cell).utilization_pct is \($s.utilization_pct), outside 0..100"] end)
         elif ($s.utilization_pct | unknownstr) then
           (if ($s.utilization_reason // null | hasreason) then []
            else ["\($cell).utilization_pct is UNKNOWN with no utilization_reason cell"] end)
         else ["\($cell).utilization_pct is \($s.utilization_pct | tojson), neither a number nor UNKNOWN with a reason"] end)
    end;

. as $row
| (.window) as $w
| (
    if ($w | unknownstr) then
      (if ($row.window_reason // null | hasreason) then []
       else ["window is UNKNOWN with no window_reason cell beside it"] end)
      + ([ "window_minutes", "resets_at", "secondary" ]
         | map(select($row[.] != null))
         | map("window is UNKNOWN and the row still carries the flat key \(.): the kernel would project a window this row declined to declare"))
    elif ($w | type) != "object" then
      ["window is \($w | tojson): a row must state its window as an object whose kind is nested or rolling, or the string UNKNOWN with a window_reason"]
    elif (($w.kind // "") | ascii_downcase) == "nested" then
      (($w.primary // null) | span("window.primary"; "primary_reason"; $w))
      + (if ($w.secondary // null) == null then
           ["window.secondary is absent: a nested window states its pair, both spans"]
         else ($w.secondary | span("window.secondary"; "secondary_reason"; $w)) end)
    elif (($w.kind // "") | ascii_downcase) == "rolling" then
      ($w | span("window"; "window_reason"; $row))
    else
      ["window.kind is \($w.kind | tojson), neither nested nor rolling"]
    end
  )
+ (
    (.window_remaining_pct) as $r
    | if ($r | isnum) then
        (if ($r >= 0 and $r <= 100) then [] else ["window_remaining_pct is \($r), outside 0..100"] end)
      elif ($r | unknownstr) then
        (if (.window_remaining_reason // null | hasreason) then []
         else ["window_remaining_pct is UNKNOWN with no window_remaining_reason cell"] end)
      else ["window_remaining_pct is \($r | tojson), neither a number 0..100 nor UNKNOWN with a reason"] end
  )
+ (
    if $claude then
      (.model_split) as $m
      | if ($m | type) != "object" then ["model_split is \($m | tojson), not an object"]
        else
          (if ($m.opus | unknownstr) then [] else ["model_split.opus is \($m.opus | tojson), not UNKNOWN"] end)
          + (if ($m.sonnet | unknownstr) then [] else ["model_split.sonnet is \($m.sonnet | tojson), not UNKNOWN"] end)
          + (if ($m.reason // null | hasreason) then [] else ["model_split carries no reason cell"] end)
        end
    else [] end
  )
+ (
    if $numeric then
      (if (.utilization_pct | isnum) then []
       else ["utilization_pct is \(.utilization_pct | tojson), not a number: a reader timeout keeps the last MEASURED reading and never blanks the row"] end)
    else [] end
  )
+ (
    if ((.grade // "") == "STALE-MEASURED") then
      (if (.reading_age_seconds | isnum) then []
       else ["grade is STALE-MEASURED with no reading_age_seconds: a kept reading must state its age"] end)
    else [] end
  )
JQEOF

failures=0
in_list() {
  local needle=$1
  shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

for row in "${SEAT_ROWS[@]}"; do
  path="$meters/$row.json"
  if [[ ! -f "$path" ]]; then
    printf 'FAIL %-13s the row does not exist at %s\n' "$row" "$path"
    failures=$((failures + 1))
    continue
  fi
  claude=false
  numeric=false
  in_list "$row" "${CLAUDE_ROWS[@]}" && claude=true
  in_list "$row" "${NUMERIC_ROWS[@]}" && numeric=true
  if ! problems=$(jq -e -r --argjson claude "$claude" --argjson numeric "$numeric" \
    "$PROGRAM | .[]" "$path" 2>&1); then
    # jq -e exits 1 on an empty result, which here is the row with nothing
    # wrong; anything else is a jq error and must not read as a pass.
    if [[ -n "$problems" ]]; then
      printf 'FAIL %-13s %s\n' "$row" "$problems"
      failures=$((failures + 1))
      continue
    fi
  fi
  if [[ -n "$problems" ]]; then
    while IFS= read -r problem; do
      printf 'FAIL %-13s %s\n' "$row" "$problem"
      failures=$((failures + 1))
    done <<<"$problems"
    continue
  fi
  kind=$(jq -r 'if (.window | type) == "object" then .window.kind else (.window | tojson) end' "$path")
  grade=$(jq -r '.grade // .capacity.grade // "none"' "$path")
  printf 'ok   %-13s window %-7s grade %-15s remaining %s\n' \
    "$row" "$kind" "$grade" "$(jq -r '.window_remaining_pct | tojson' "$path")"
done

if ((failures)); then
  printf '\nFAIL seat-rows-oracle: %d cell(s) missing or unreadable in %s\n' "$failures" "$meters"
  exit 1
fi

printf '\n== nix flake check --offline --no-build\n'
if ! nix flake check --offline --no-build 2>&1 | tail -3; then
  printf 'FAIL seat-rows-oracle: nix flake check --offline --no-build is not green\n'
  exit 1
fi

printf 'PASS seat-rows-oracle: %s — every seat row states its window\n' "$meters"
