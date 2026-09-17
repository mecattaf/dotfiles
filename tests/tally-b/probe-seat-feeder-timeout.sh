#!/usr/bin/env bash
# THE SEAT-FEEDER READER BOUND, AS A FIXTURE (Int-G11).
#
# Two facts about `home/dot_local/bin/tally-seat-feeder` that only a running
# clock can establish, and that the flake's eval-time checks cannot see:
#
#   1. A read that takes FOURTEEN seconds now LANDS. The bound was 12 s, and
#      MEASURED over ~/.local/state/tally-rewrite/uplink/events.jsonl for
#      2026-09-16T04Z -> 09-17T04Z the `cc` row read STALE-MEASURED on 135 of
#      286 wakes. A reading thrown away at 12 s for a retained one is a row
#      that says it is older than the measurement it could have had. So: a
#      reader that sleeps 14 s and then serves its own 30-second-old D-B92
#      cache must produce grade MEASURED (30 <= the 45 s D-B92 boundary),
#      `reading_age_seconds` 30, and NO `stale_reason`.
#
#   2. A read that CANNOT land is still bounded, and what it re-publishes is
#      the READER'S OWN CACHE. A reader that sleeps 20 s is cut off at 16 s
#      (`subprocess.TimeoutExpired`), and the row must be STALE-MEASURED with
#      `stale_reason` naming TimeoutExpired, `reading_source` naming
#      `.window-cache-cc.json` by path, and `reading_age_seconds` equal to that
#      cache's TRUE age — not the age of the row the feeder last published.
#      The second run of clause 2 is deliberately run after a successful one,
#      so BOTH retained sources exist at the SAME observed instant: the tie is
#      the whole point, and the cache is what must win it.
#
# WHAT THIS TOUCHES. A scratch directory and nothing else. The reader is a fake
# written here — no credential file is opened, no token exists, nothing leaves
# the box, and `TALLY_REWRITE_METERS` / `TALLY_WINDOW_CACHE_DIR` both point into
# the scratch tree, so the live ~/.local/state/tally-rewrite/meters is neither
# read nor written. No unit is started, restarted or enabled.
#
# THE CLOCK. `TALLY_FEEDER_NOW` pins the feeder's own clock so the published
# ages are exact integers rather than a race with the sleeps; the SLEEPS are
# real wall time, because the bound under test is a wall-clock bound.
#
# A GUARD NOBODY HAS SEEN RED IS NOT A GUARD. This one was run against the
# PRE-CHANGE feeder (a worktree at `main`) by passing that tree as `repo`, and
# it went red in exactly the four places the change moves and nowhere else:
#
#   [F] T0 CLAUDE_READER_TIMEOUT_SECONDS is '12', wanted 16
#   [F] T1 wall time 12s is not a landed 14-second read
#   [F] T1 the row carries stale_reason 'the reader could not be run:
#          TimeoutExpired' after a successful read
#   [F] T2 wall time 12s: the read was not bounded at 16 s
#   [F] T2 reading_source is 'the last row this feeder published at …/cc.json',
#          wanted the .window-cache-cc.json path
#
# Re-run it that way — `bash tests/tally-b/probe-seat-feeder-timeout.sh
# <a checkout without this change> <a scratch dir>` — whenever either half is
# touched.
#
# Usage: bash tests/tally-b/probe-seat-feeder-timeout.sh [repo] [scratch-dir]
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
scratch="${2:-${TMPDIR:-/tmp}/tally-seat-feeder-timeout.$$}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }

feeder="$repo/home/dot_local/bin/tally-seat-feeder"
[ -f "$feeder" ] || { echo "FAIL: no feeder at $feeder"; exit 2; }

# The python the coordinator's own unit runs the feeder under (home/seat-feeder.nix
# puts pkgs.python3 on the unit's PATH and nothing else). Evaluated, never a
# hardcoded store path.
python_store=$(nix eval --offline --raw "$repo#nixosConfigurations.coordinator.pkgs.python3.outPath" 2>/dev/null)
python="$python_store/bin/python3"
if [ ! -x "$python" ]; then
  printf '[S] the evaluated python3 is unavailable (%s); this is an ENV limit, not a divergence\n' "${python_store:-<eval failed>}"
  exit 3
fi

work="$scratch"
rm -rf -- "$work"
mkdir -p "$work/meters" || { echo "FAIL: cannot create $work/meters"; exit 2; }
trap 'rm -rf -- "$work"' EXIT

NOW="2026-09-17T12:00:00Z"

# --- the fake reader --------------------------------------------------------
# stamp-receipt.py's interface only: `window --seat <seat>`, one JSON object on
# stdout, exit 0 on MEASURED. It sleeps for TALLY_FIXTURE_SLEEP seconds and then
# serves the cache file the REAL reader would have served (D-B92), stamping
# `from_cache_seconds` the way the real one does. It opens no credential.
cat > "$work/fake-reader.py" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone

def stamp(text):
    return datetime.fromisoformat(text.strip().replace("Z", "+00:00")).astimezone(timezone.utc)

def main(argv):
    if len(argv) < 4 or argv[1] != "window" or argv[2] != "--seat":
        sys.stderr.write("fake-reader: usage: window --seat <seat>\n")
        return 64
    seat = argv[3]
    time.sleep(float(os.environ.get("TALLY_FIXTURE_SLEEP", "0")))
    path = os.path.join(os.environ["TALLY_WINDOW_CACHE_DIR"], f".window-cache-{seat}.json")
    with open(path, encoding="utf-8") as fh:
        cached = json.load(fh)
    observed = stamp(cached["observed_at"])
    now = stamp(os.environ["TALLY_FEEDER_NOW"])
    out = {"grade": "MEASURED", "seat": seat, "observed_at": cached["observed_at"],
           "from_cache_seconds": int((now - observed).total_seconds())}
    out.update(cached["usage"])
    print(json.dumps(out))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

write_cache() {  # write_cache <age-seconds>
  "$python" - "$work/meters" "$NOW" "$1" <<'PY'
import json, os, sys
from datetime import datetime, timedelta, timezone
meters, now_text, age = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.fromisoformat(now_text.replace("Z", "+00:00")).astimezone(timezone.utc)
observed = (now - timedelta(seconds=age)).strftime("%Y-%m-%dT%H:%M:%SZ")
doc = {
    "observed_at": observed,
    "usage": {
        "five_hour": {"utilization": 43, "resets_at": "2026-09-17T16:39:59Z"},
        "seven_day": {"utilization": 79, "resets_at": "2026-09-23T09:59:00Z"},
        "seven_day_opus": {"utilization": None, "resets_at": None},
        "seven_day_sonnet": {"utilization": None, "resets_at": None},
    },
}
with open(os.path.join(meters, ".window-cache-cc.json"), "w", encoding="utf-8") as fh:
    json.dump(doc, fh)
print(observed)
PY
}

run_feeder() {  # run_feeder <sleep-seconds>
  TALLY_REWRITE_METERS="$work/meters" \
  TALLY_WINDOW_CACHE_DIR="$work/meters" \
  TALLY_STAMP_RECEIPT="$work/fake-reader.py" \
  TALLY_CLAUDE_SEATS=cc \
  TALLY_FEEDER_NOW="$NOW" \
  TALLY_FIXTURE_SLEEP="$1" \
  "$python" "$feeder" claude >"$work/feeder.out" 2>"$work/feeder.err"
}

cell() {  # cell <key>
  "$python" -c 'import json,sys; row=json.load(open(sys.argv[1])); v=row.get(sys.argv[2]); print("" if v is None else v)' \
    "$work/meters/cc.json" "$1" 2>/dev/null
}

# --- the declared bound, as bytes ------------------------------------------
declared=$(sed -n 's/^CLAUDE_READER_TIMEOUT_SECONDS = \([0-9]*\)$/\1/p' "$feeder")
if [ "$declared" = "16" ]; then
  pass "T0 CLAUDE_READER_TIMEOUT_SECONDS is 16 (30 + 1 + 20 = 51 < 60 keeps D-B54; three CONCURRENT 16 s reads fit the 20 s TimeoutStartSec)"
else
  bad  "T0 CLAUDE_READER_TIMEOUT_SECONDS is '${declared:-<unreadable>}', wanted 16"
fi

# --- T1: a slow-but-successful read is MEASURED with the cache's own age ----
observed=$(write_cache 30)
started=$(date +%s)
run_feeder 14
rc=$?
elapsed=$(( $(date +%s) - started ))
if [ "$rc" -ne 0 ]; then
  bad "T1 the feeder exited $rc: $(head -3 "$work/feeder.err")"
fi
if [ "$elapsed" -ge 14 ] && [ "$elapsed" -lt 30 ]; then
  pass "T1 the 14-second read LANDED (${elapsed}s wall) — under the old 12-second bound it could not have"
else
  bad  "T1 wall time ${elapsed}s is not a landed 14-second read"
fi
grade=$(cell grade); age=$(cell reading_age_seconds); stale=$(cell stale_reason)
if [ "$grade" = "MEASURED" ]; then
  pass "T1 grade MEASURED (the cache was $age s old, inside D-B92's 45 s)"
else
  bad  "T1 grade is '${grade:-<no row>}', wanted MEASURED"
fi
if [ "$age" = "30" ]; then
  pass "T1 reading_age_seconds is the cache's true age: $age (cache observed $observed)"
else
  bad  "T1 reading_age_seconds is '${age:-<none>}', wanted 30"
fi
if [ -z "$stale" ]; then
  pass "T1 no stale_reason — a read that landed is not a stale row"
else
  bad  "T1 the row carries stale_reason '$stale' after a successful read"
fi
util=$(cell utilization_pct)
if [ "$util" = "43.0" ]; then
  pass "T1 the measurement itself is published: utilization_pct $util"
else
  bad  "T1 utilization_pct is '${util:-<none>}', wanted 43.0"
fi

# --- T2: a read that cannot land -> STALE-MEASURED, from the CACHE ----------
# First a successful pass over a 300-second-old cache, so the feeder publishes a
# row whose reading_observed_at EQUALS the cache's. Both retained sources then
# sit at the same instant and the tie-break is what is under test.
observed=$(write_cache 300)
run_feeder 0
seeded=$(cell reading_observed_at)
if [ "$seeded" = "$observed" ]; then
  pass "T2 seeded: the published row and the cache now name the same measured instant ($observed)"
else
  bad  "T2 could not seed the tie: row says '${seeded:-<none>}', cache says '$observed'"
fi
started=$(date +%s)
run_feeder 20
rc=$?
elapsed=$(( $(date +%s) - started ))
if [ "$rc" -ne 0 ]; then
  bad "T2 the feeder exited $rc: $(head -3 "$work/feeder.err")"
fi
if [ "$elapsed" -ge 16 ] && [ "$elapsed" -lt 20 ]; then
  pass "T2 the 20-second read was CUT OFF at the bound (${elapsed}s wall < the reader's own 20 s)"
else
  bad  "T2 wall time ${elapsed}s: the read was not bounded at 16 s"
fi
grade=$(cell grade); age=$(cell reading_age_seconds)
stale=$(cell stale_reason); origin=$(cell reading_source)
if [ "$grade" = "STALE-MEASURED" ]; then
  pass "T2 grade STALE-MEASURED — the numbers are old and the row says so"
else
  bad  "T2 grade is '${grade:-<no row>}', wanted STALE-MEASURED"
fi
case "$stale" in
  *TimeoutExpired*) pass "T2 stale_reason names the failure: $stale" ;;
  *)                bad  "T2 stale_reason is '${stale:-<none>}', wanted one naming TimeoutExpired" ;;
esac
case "$origin" in
  *"/.window-cache-cc.json")
    pass "T2 reading_source is the READER'S OWN cache, not this feeder's last row: $origin" ;;
  *)
    bad  "T2 reading_source is '${origin:-<none>}', wanted the .window-cache-cc.json path" ;;
esac
if [ "$age" = "300" ]; then
  pass "T2 reading_age_seconds is the cache's true age: $age"
else
  bad  "T2 reading_age_seconds is '${age:-<none>}', wanted 300"
fi
if [ "$(cell utilization_pct)" = "43.0" ]; then
  pass "T2 the retained measurement is re-published, not blanked: utilization_pct 43.0"
else
  bad  "T2 the retained measurement was lost: utilization_pct '$(cell utilization_pct)'"
fi

# --- T3: nothing outside the scratch tree was written ----------------------
# The fixture's whole state is $work. The live meters dir is named here only to
# say that it was never opened for writing: the two environment variables above
# point elsewhere, and this clause is the assertion that they were honoured.
live="$HOME/.local/state/tally-rewrite/meters"
if [ ! -e "$work/../.window-cache-cc.json" ] && [ -f "$work/meters/cc.json" ]; then
  pass "T3 every row and cache this fixture wrote is under $work (the live $live was not a target)"
else
  bad  "T3 the fixture wrote outside its scratch tree"
fi

exit "$fail"
