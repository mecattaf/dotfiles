#!/usr/bin/env bash
# tools/fix-e06-cc-window-unknown-oracle.sh — FIX-E06 (dotfiles#349).
#
# THE DEFECT. The usage endpoint answers the cc seat's five-hour span with a
# utilization and NO reset instant (MEASURED 2026-09-07T21:16Z:
# ~/.local/state/tally-rewrite/meters/.window-cache-cc.json holds five_hour
# utilization 0.0 with resets_at null, while .window-cache-cc2.json and
# .window-cache-cc3.json both carry the instant). tally-seat-feeder's fallback
# turned that ONE absent cell into FOUR blank ones — no window, no
# window_remaining_pct, no model_split, utilization_pct null — and graded the
# row UNKNOWN, which the kernel refuses outright (crates/tally-kernel/src/
# meter.rs:347-352, "row grades itself UNKNOWN"), so the only live Claude row
# admitted STOP observation_unusable.
#
# WHAT THIS ASSERTS, hermetically: no credential, no network, no live meters
# directory, no live seat capacity, and a pinned clock.
#
#   1. one feeder pass per instrument into a SCRATCH meters directory, with the
#      reader stubbed at the MEASURED cc answer above, exits 0;
#   2. the cc row keeps the measurement and NAMES the missing cell:
#        * utilization_pct is the number 0.0, never null;
#        * grade MEASURED with reading_age_seconds (never a grade of UNKNOWN,
#          which is itself a refusal at the door);
#        * window is the string UNKNOWN with window_unknown_cell
#          "window.primary.resets_at" and a window_reason naming the missing
#          reset instant — NOT a declared nested window carrying
#          resets_at: "UNKNOWN", which the kernel's own reader refuses
#          ("declared window has no reset instant", window.rs parse_span), and
#          NOT a reset defaulted to now;
#        * the row carries none of the flat window keys the kernel would
#          project a window out of (window_minutes / resets_at / secondary);
#        * window_remaining_pct UNKNOWN with a reason; model_split UNKNOWN with
#          a reason; the seven-day span the reading DID carry kept, unasserted,
#          under window_stated_spans; and no null cell anywhere in the row;
#        * cc2 and cc3, whose readings carry the instant, still publish the
#          nested pair — the fix is scoped to the absent cell;
#      and the row is retained: a second pass whose reader TIMES OUT
#      re-publishes the same number as STALE-MEASURED with its age, rather
#      than falling back to a blank row;
#   3. tools/seat-rows-oracle.sh — CAP-1's dominant row-shape oracle — exits 0
#      on that scratch directory, with zero FAIL lines;
#   4. the door: tally-admit on the scratch directory answers GO (0) or SLOW
#      (10) for cc, never STOP (20) observation_unusable. The binary is taken
#      from $TALLY_ADMIT, else `tally-admit` on PATH, else U-B10's recorded
#      build in the merged kernel checkout. If none exists the clause is
#      SKIPPED with the reason printed: the shipped kernel binary
#      (tally-b-kernel, `systemctl cat tally-kernel.service`) serves over a
#      socket and offers no offline `admit` verb, and this oracle will not
#      start a service.
#
# Exit: 0 every clause holds; 1 a clause fails (each failure is named on
# stdout); 2 a tool or fixture this oracle needs is absent.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
feeder="$repo/home/dot_local/bin/tally-seat-feeder"
inputs="$repo/tests/seat-feeder/inputs"

for tool in jq python3 nix; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'fix-e06-oracle: %s is not on PATH\n' "$tool" >&2
    exit 2
  }
done
[[ -f "$feeder" ]] || { printf 'fix-e06-oracle: no feeder at %s\n' "$feeder" >&2; exit 2; }
[[ -d "$inputs/codex-sessions" ]] || { printf 'fix-e06-oracle: no codex fixture in %s\n' "$inputs" >&2; exit 2; }
[[ -f "$inputs/pi-hold.json" ]] || { printf 'fix-e06-oracle: no pi hold fixture in %s\n' "$inputs" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/fix-e06-cc-window-unknown.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
meters="$work/meters"
cache="$work/reader-cache"
mkdir -p -m 700 "$meters" "$cache"

# The pinned clock. NOW is deliberately BEFORE the seven-day reset the endpoint
# did state for cc, so nothing in the run depends on the wall clock.
NOW=2026-09-07T21:16:00Z
NOW_MS=$(python3 - "$NOW" <<'PY'
import datetime, sys
print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp() * 1000))
PY
)

# The stub reader: the sanctioned reader's OUTPUT shape, from a table on disk.
# It opens no credential and calls nothing.
cat >"$work/stub-reader.py" <<'PY'
#!/usr/bin/env python3
import json, os, sys, time
table = json.load(open(os.environ["STUB_TABLE"], encoding="utf-8"))
answer = table.get(sys.argv[3])
if answer is None:
    sys.stderr.write("no seat\n")
    sys.exit(64)
if answer.get("hang"):
    time.sleep(float(answer["hang"]))
print(json.dumps(answer["out"]))
sys.exit(0 if answer["out"].get("grade") == "MEASURED" else 2)
PY

# cc is the MEASURED live answer: a five-hour utilization with resets_at null.
# cc2 and cc3 carry the instant, exactly as their caches do.
cat >"$work/stub-table.json" <<'PY'
{
  "cc": {"out": {
    "seat": "cc", "grade": "MEASURED", "observed_at": "2026-09-07T21:15:30Z",
    "five_hour": {"utilization": 0.0, "resets_at": null},
    "seven_day": {"utilization": 96.0, "resets_at": "2026-09-09T10:00:00Z"},
    "seven_day_opus": {"utilization": null, "resets_at": null},
    "seven_day_sonnet": {"utilization": null, "resets_at": null}}},
  "cc2": {"out": {
    "seat": "cc2", "grade": "MEASURED", "observed_at": "2026-09-07T21:15:30Z",
    "five_hour": {"utilization": 26.0, "resets_at": "2026-09-07T23:39:59Z"},
    "seven_day": {"utilization": 97.0, "resets_at": "2026-09-09T10:00:00Z"},
    "seven_day_opus": {"utilization": null, "resets_at": null},
    "seven_day_sonnet": {"utilization": null, "resets_at": null}}},
  "cc3": {"out": {
    "seat": "cc3", "grade": "MEASURED", "observed_at": "2026-09-07T21:15:30Z",
    "five_hour": {"utilization": 3.0, "resets_at": "2026-09-08T01:50:00Z"},
    "seven_day": {"utilization": 12.0, "resets_at": "2026-09-09T10:00:00Z"},
    "seven_day_opus": {"utilization": null, "resets_at": null},
    "seven_day_sonnet": {"utilization": null, "resets_at": null}}}
}
PY
# The same table with cc's reader hanging past the feeder's 12-second bound: a
# real timeout, for the retention clause.
jq '.cc.hang = 14' "$work/stub-table.json" >"$work/stub-table-timeout.json"

run_feeder() {
  local instrument=$1 table=$2
  TALLY_REWRITE_METERS="$meters" \
    TALLY_STAMP_RECEIPT="$work/stub-reader.py" \
    TALLY_WINDOW_CACHE_DIR="$cache" \
    TALLY_PI_HOLD="$inputs/pi-hold.json" \
    TALLY_CODEX_SESSIONS="$inputs/codex-sessions" \
    TALLY_CLAUDE_SEATS="cc,cc2,cc3" \
    TALLY_FEEDER_NOW="$NOW" \
    STUB_TABLE="$table" \
    python3 "$feeder" "$instrument"
}

failures=0
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

printf '== clause 1: one feeder pass per instrument into %s\n' "$meters"
for instrument in claude codex pi-qwencloud; do
  if ! run_feeder "$instrument" "$work/stub-table.json"; then
    fail "the $instrument instrument exited non-zero"
  fi
done

printf '\n== clause 2: the cc row keeps the measurement and names the missing cell\n'
python3 - "$meters" "$NOW" <<'PY' || failures=$((failures + 1))
import json, os, sys

meters, now = sys.argv[1], sys.argv[2]
problems = []


def row(seat):
    with open(os.path.join(meters, seat + ".json"), encoding="utf-8") as fh:
        return json.load(fh)


def nulls(value, path="row"):
    if value is None:
        return [path]
    if isinstance(value, dict):
        return [p for k, v in value.items() for p in nulls(v, f"{path}.{k}")]
    if isinstance(value, list):
        return [p for i, v in enumerate(value) for p in nulls(v, f"{path}[{i}]")]
    return []


cc = row("cc")
if cc.get("utilization_pct") != 0.0 or not isinstance(cc.get("utilization_pct"), float):
    problems.append(f"cc utilization_pct is {cc.get('utilization_pct')!r}, wanted the number 0.0")
if cc.get("grade") != "MEASURED":
    problems.append(f"cc grade is {cc.get('grade')!r}, wanted MEASURED")
if (cc.get("capacity") or {}).get("grade") == "UNKNOWN":
    problems.append("cc grades itself UNKNOWN under capacity: the kernel refuses that row")
if not isinstance(cc.get("reading_age_seconds"), int):
    problems.append(f"cc reading_age_seconds is {cc.get('reading_age_seconds')!r}, wanted a number")
if cc.get("window") != "UNKNOWN":
    problems.append(f"cc window is {cc.get('window')!r}, wanted the string UNKNOWN")
if cc.get("window_unknown_cell") != "window.primary.resets_at":
    problems.append(f"cc window_unknown_cell is {cc.get('window_unknown_cell')!r}")
reason = cc.get("window_reason") or ""
if "reset instant" not in reason:
    problems.append(f"cc window_reason does not name the missing reset instant: {reason!r}")
for key in ("window_minutes", "resets_at", "secondary", "minutes"):
    if key in cc:
        problems.append(f"cc carries the flat window key {key!r}: the kernel would project a window from it")
if cc.get("window_remaining_pct") != "UNKNOWN" or not (cc.get("window_remaining_reason") or ""):
    problems.append("cc window_remaining_pct is not UNKNOWN with a reason")
split = cc.get("model_split") or {}
if split.get("opus") != "UNKNOWN" or split.get("sonnet") != "UNKNOWN" or not split.get("reason"):
    problems.append(f"cc model_split is not UNKNOWN with a reason: {split!r}")
stated = (cc.get("window_stated_spans") or {}).get("seven_day") or {}
if stated.get("resets_at") != "2026-09-09T10:00:00Z" or stated.get("utilization_pct") != 96.0:
    problems.append(f"cc did not keep the seven-day span the reading carried: {stated!r}")
if cc.get("weekly_utilization_pct") != 96.0:
    problems.append(f"cc weekly_utilization_pct is {cc.get('weekly_utilization_pct')!r}, wanted 96.0")
found = nulls(cc)
if found:
    problems.append("cc carries null cells: " + ", ".join(found))
# A defaulted reset of now is the one wrong answer that would pass every shape
# check, so it is named explicitly: the clock's own instant may appear in the
# publication stamp and nowhere else.
def instants(value, path="row"):
    if isinstance(value, str):
        return [path] if value.strip() == now else []
    if isinstance(value, dict):
        return [p for k, v in value.items() for p in instants(v, f"{path}.{k}")]
    if isinstance(value, list):
        return [p for i, v in enumerate(value) for p in instants(v, f"{path}[{i}]")]
    return []


stamped = [p for p in instants(cc) if p not in ("row.observed_at", "row.updated_at")]
if stamped:
    problems.append(
        "cc carries the clock's own instant outside its publication stamp — a "
        "defaulted reset: " + ", ".join(stamped)
    )

for seat, five_hour in (("cc2", "2026-09-07T23:39:59Z"), ("cc3", "2026-09-08T01:50:00Z")):
    other = row(seat)
    window = other.get("window")
    if not isinstance(window, dict) or window.get("kind") != "nested":
        problems.append(f"{seat} lost its nested window: {window!r}")
    elif (window.get("primary") or {}).get("resets_at") != five_hour:
        problems.append(f"{seat} five-hour reset is {(window.get('primary') or {}).get('resets_at')!r}")

for problem in problems:
    print("FAIL " + problem)
sys.exit(1 if problems else 0)
PY

printf '\n== clause 2b: a reader timeout re-publishes the retained reading, never a blank row\n'
if ! run_feeder claude "$work/stub-table-timeout.json" >/dev/null; then
  fail "the claude instrument exited non-zero on the timeout pass"
fi
# The reading was MEASURED 30 s before the pinned clock, so it is re-published
# at age 30 — inside D-B92's 45 s, hence still MEASURED — with the timeout named
# in stale_reason and the same UNKNOWN window. What must never happen is the
# blank row: a null utilization and a grade of UNKNOWN.
retained=$(jq -r '[(.utilization_pct|tojson), (.grade|tojson), (.window|tojson), ((.reading_age_seconds//"absent")|tojson), (if ((.stale_reason//"") | test("Timeout")) then "timeout-named" else "no-timeout-reason" end)] | join(" ")' "$meters/cc.json")
if [[ "$retained" != '0.0 "MEASURED" "UNKNOWN" 30 timeout-named' ]]; then
  fail "the retained cc row is [$retained], wanted [0.0 \"MEASURED\" \"UNKNOWN\" 30 timeout-named]"
fi

printf '\n== clause 3: tools/seat-rows-oracle.sh on the scratch directory\n'
if ! bash "$repo/tools/seat-rows-oracle.sh" "$meters"; then
  fail "tools/seat-rows-oracle.sh did not exit 0 on $meters"
fi

printf '\n== clause 4: the door\n'
admit=${TALLY_ADMIT:-}
if [[ -z "$admit" ]]; then
  if command -v tally-admit >/dev/null 2>&1; then
    admit=$(command -v tally-admit)
  elif [[ -x /home/tom/mecattaf/tally/target/debug/tally-admit-as-shipped ]]; then
    admit=/home/tom/mecattaf/tally/target/debug/tally-admit-as-shipped
  fi
fi
if [[ -z "$admit" ]]; then
  printf 'SKIP clause 4: no tally-admit binary ($TALLY_ADMIT unset, none on PATH, none\n'
  printf '     built in the kernel checkout). The SHIPPED kernel binary named by\n'
  printf '     `systemctl cat tally-kernel.service` serves over a socket and has no\n'
  printf '     offline admit verb, and this oracle starts no service. Clause 2 still\n'
  printf '     asserts the two cells the door refuses on: a grade of UNKNOWN and a\n'
  printf '     null utilization.\n'
else
  set +e
  verdict=$("$admit" cc --meters "$meters" --ledger "$work/admit-ledger.jsonl" --now "$NOW_MS" 2>&1)
  rc=$?
  set -e
  printf '%s (rc %s, %s)\n' "$verdict" "$rc" "$admit"
  case "$rc" in
    0 | 10) : ;;
    *) fail "tally-admit cc exited $rc, wanted 0 (GO) or 10 (SLOW)" ;;
  esac
  if [[ "$verdict" == *observation_unusable* ]]; then
    fail "tally-admit cc answered observation_unusable on a row that carries its measurement"
  fi
fi

printf '\n'
if ((failures)); then
  printf 'FAIL fix-e06-cc-window-unknown-oracle: %d clause(s)\n' "$failures"
  exit 1
fi
printf 'PASS fix-e06-cc-window-unknown-oracle: the cc row names its missing reset\n'
printf 'instant, keeps its measurement, and the door admits it\n'
