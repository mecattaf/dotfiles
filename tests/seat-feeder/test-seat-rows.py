#!/usr/bin/env python3
"""CAP-1 SEAT-ROWS-UNTIL — the row-completeness cases, hermetically.

UNIT: CAP-1 (dotfiles#337). ORACLE: tools/seat-rows-oracle.sh.

WHY THIS EXISTS BESIDE tools/feeder-fixture.sh. That fixture replays the
declared clocks and needs U-B10's real `tally-admit` binary, so it costs a
Rust build. The cases CAP-1 adds are about the SHAPE of a row and nothing
else, and every one of them can be measured with the feeder alone: no network,
no credential, no cargo, no clock but the one the fixture pins.

Each case drives the REAL feeder program with its environment redirected —
`TALLY_STAMP_RECEIPT` at a stub reader this file writes, `TALLY_WINDOW_CACHE_DIR`
at a scratch cache, `TALLY_PI_HOLD` at a scratch hold record — and reads what
landed on disk. The cases:

  A  a fresh MEASURED read              nested pair, remaining off the BINDING
                                        span, model_split UNKNOWN with a reason
  B  a reader TIMEOUT with a retained
     reading in the reader's cache      STALE-MEASURED, the same numbers, the
                                        reading's age, and never a null
  C  a reader timeout with a retained
     row from a previous pass           the row is kept, and its age chains off
                                        reading_observed_at, not publication
  D  a reader timeout with nothing
     retained                           UNKNOWN with the reason — a hole is
                                        still better said than invented
  E  the reader's own <45 s cache       MEASURED (D-B92), with the age stated
  F  the reader's own >45 s cache       STALE-MEASURED, with the age stated
  G  pi-qwencloud, hold HELD            rolling 10080 to the stated held_until
  H  pi-qwencloud, hold RELEASED        window UNKNOWN with the reason; never a
                                        declared window with an unknown reset,
                                        which the kernel's reader refuses
  I  the seat list, comma or space      three rows either way

Exit 0 when every case holds; 1 naming each that does not.
"""

import json
import os
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FEEDER = os.path.join(REPO, "home", "dot_local", "bin", "tally-seat-feeder")
NOW = "2026-09-06T00:00:00Z"

# A reader that answers from a table this file writes, so a case can make one
# seat succeed and another time out without any credential existing anywhere.
STUB_READER = '''#!/usr/bin/env python3
import json, os, sys
table = json.load(open(os.environ["STUB_TABLE"], encoding="utf-8"))
seat = sys.argv[3]
answer = table.get(seat)
if answer is None:
    sys.stderr.write("no seat\\n")
    sys.exit(64)
if answer.get("hang"):
    import time
    time.sleep(float(answer["hang"]))
print(json.dumps(answer["out"]))
sys.exit(0 if answer["out"].get("grade") == "MEASURED" else 2)
'''

MEASURED_CC = {
    "seat": "cc",
    "grade": "MEASURED",
    "observed_at": "2026-09-05T23:59:00Z",
    "five_hour": {"utilization": 43, "resets_at": "2026-09-06T13:39:59Z"},
    "seven_day": {"utilization": 79, "resets_at": "2026-09-09T09:59:00Z"},
    "seven_day_opus": {"utilization": None, "resets_at": None},
    "seven_day_sonnet": {"utilization": None, "resets_at": None},
}


def fail(failures, message):
    failures.append(message)


def write(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)


def run_feeder(case, instrument, table=None, overrides=None):
    """One real feeder invocation with every outside path redirected."""
    meters = os.path.join(case, "meters")
    cache = os.path.join(case, "reader-cache")
    os.makedirs(meters, mode=0o700, exist_ok=True)
    os.makedirs(cache, mode=0o700, exist_ok=True)
    reader = os.path.join(case, "stub-reader.py")
    with open(reader, "w", encoding="utf-8") as stream:
        stream.write(STUB_READER)
    stub_table = os.path.join(case, "stub-table.json")
    write(stub_table, table or {})
    environment = {
        **os.environ,
        "TALLY_REWRITE_METERS": meters,
        "TALLY_STAMP_RECEIPT": reader,
        "TALLY_WINDOW_CACHE_DIR": cache,
        "TALLY_PI_HOLD": os.path.join(case, "pi-hold.json"),
        "TALLY_CLAUDE_SEATS": "cc",
        "TALLY_FEEDER_NOW": NOW,
        "STUB_TABLE": stub_table,
    }
    for key, value in (overrides or {}).items():
        if value is None:
            environment.pop(key, None)
        else:
            environment[key] = value
    process = subprocess.run(
        [sys.executable, FEEDER, instrument],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=False,
    )
    return process, meters, cache


def read_row(meters, row_id):
    path = os.path.join(meters, row_id + ".json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def nested_pair(row):
    window = (row or {}).get("window") or {}
    return window.get("primary") or {}, window.get("secondary") or {}


def case_a_fresh(work, failures):
    case = os.path.join(work, "a-fresh")
    _process, meters, _cache = run_feeder(case, "claude", {"cc": {"out": MEASURED_CC}})
    row = read_row(meters, "cc")
    if row is None:
        return fail(failures, "A no cc row was written for a MEASURED read")
    primary, secondary = nested_pair(row)
    if (row.get("window") or {}).get("kind") != "nested":
        fail(failures, "A the window is not nested")
    if primary.get("minutes") != 300 or primary.get("resets_at") != "2026-09-06T13:39:59Z":
        fail(failures, "A the five-hour span is not the reader's")
    if secondary.get("minutes") != 10080 or secondary.get("utilization_pct") != 79.0:
        fail(failures, "A the seven-day span is not the reader's")
    # 79 is the binding span, not 43: the remainder is off the MOST spent one.
    if row.get("window_remaining_pct") != 21.0:
        fail(failures, f"A window_remaining_pct is {row.get('window_remaining_pct')!r}, wanted 21.0")
    split = row.get("model_split") or {}
    if split.get("opus") != "UNKNOWN" or split.get("sonnet") != "UNKNOWN" or not split.get("reason"):
        fail(failures, "A model_split is not UNKNOWN with a reason")
    if row.get("grade") != "MEASURED" or row.get("reading_age_seconds") != 0:
        fail(failures, "A a fresh read is not MEASURED at age 0")


def case_b_timeout_with_cache(work, failures):
    case = os.path.join(work, "b-timeout-cache")
    os.makedirs(os.path.join(case, "reader-cache"), mode=0o700, exist_ok=True)
    write(
        os.path.join(case, "reader-cache", ".window-cache-cc.json"),
        {
            "observed_at": "2026-09-05T23:20:00Z",
            "usage": {
                "five_hour": {"utilization": 44, "resets_at": "2026-09-06T13:40:00Z"},
                "seven_day": {"utilization": 88, "resets_at": "2026-09-10T06:00:00Z"},
                "seven_day_opus": None,
                "seven_day_sonnet": None,
            },
        },
    )
    # The stub sleeps past the feeder's own 12-second reader bound: a real
    # subprocess.TimeoutExpired, not a simulated one.
    _process, meters, _cache = run_feeder(case, "claude", {"cc": {"hang": 14, "out": MEASURED_CC}})
    row = read_row(meters, "cc")
    if row is None:
        return fail(failures, "B no cc row was written after a reader timeout")
    if row.get("grade") != "STALE-MEASURED":
        fail(failures, f"B grade is {row.get('grade')!r}, wanted STALE-MEASURED")
    if row.get("utilization_pct") != 44.0:
        fail(failures, "B the retained reading's utilization was not kept")
    if row.get("reading_age_seconds") != 2400:
        fail(failures, f"B reading_age_seconds is {row.get('reading_age_seconds')!r}, wanted 2400")
    if "TimeoutExpired" not in (row.get("stale_reason") or ""):
        fail(failures, "B the row does not say the read timed out")
    primary, _secondary = nested_pair(row)
    if primary.get("resets_at") != "2026-09-06T13:40:00Z":
        fail(failures, "B the retained reset instant was not kept")


def case_c_timeout_with_row(work, failures):
    case = os.path.join(work, "c-timeout-row")
    run_feeder(case, "claude", {"cc": {"out": MEASURED_CC}})
    first = read_row(os.path.join(case, "meters"), "cc")
    if (first or {}).get("grade") != "MEASURED":
        return fail(failures, "C the seeding pass did not publish a MEASURED row")
    _process, meters, _cache = run_feeder(case, "claude", {"cc": {"hang": 14, "out": MEASURED_CC}})
    row = read_row(meters, "cc")
    if row is None:
        return fail(failures, "C no cc row survived the reader timeout")
    if row.get("grade") != "STALE-MEASURED" or row.get("utilization_pct") != 43.0:
        fail(failures, "C the previously published row was not re-published")
    # The reading was MEASURED at 23:59, published at 00:00, re-published at
    # 00:00. The age is off the MEASUREMENT, so 60 s and not 0.
    if row.get("reading_age_seconds") != 60:
        fail(failures, f"C reading_age_seconds is {row.get('reading_age_seconds')!r}, wanted 60")
    if row.get("reading_observed_at") != "2026-09-05T23:59:00Z":
        fail(failures, "C the reading's own clock was not carried forward")


def case_d_timeout_with_nothing(work, failures):
    case = os.path.join(work, "d-timeout-nothing")
    _process, meters, _cache = run_feeder(case, "claude", {"cc": {"hang": 14, "out": MEASURED_CC}})
    row = read_row(meters, "cc")
    if row is None:
        return fail(failures, "D no cc row was written with nothing retained")
    if (row.get("capacity") or {}).get("grade") != "UNKNOWN":
        fail(failures, "D a row with nothing retained is not UNKNOWN")
    if "no MEASURED reading was retained" not in ((row.get("capacity") or {}).get("reason") or ""):
        fail(failures, "D the row does not say that nothing was retained")
    if "window" in row:
        fail(failures, "D a row with no reading invented a window")


def cached_read_case(work, failures, label, age, wanted_grade):
    case = os.path.join(work, label)
    answer = dict(MEASURED_CC)
    answer["from_cache_seconds"] = age
    _process, meters, _cache = run_feeder(case, "claude", {"cc": {"out": answer}})
    row = read_row(meters, "cc")
    if row is None:
        return fail(failures, f"{label} no cc row was written")
    if row.get("grade") != wanted_grade:
        fail(failures, f"{label} grade is {row.get('grade')!r}, wanted {wanted_grade}")
    if row.get("reading_age_seconds") != age:
        fail(failures, f"{label} reading_age_seconds is {row.get('reading_age_seconds')!r}, wanted {age}")
    if row.get("utilization_pct") != 43.0:
        fail(failures, f"{label} the cached reading's utilization was not published")


def pi_case(work, failures, label, hold, check):
    case = os.path.join(work, label)
    os.makedirs(case, exist_ok=True)
    write(os.path.join(case, "pi-hold.json"), hold)
    _process, meters, _cache = run_feeder(case, "pi-qwencloud")
    row = read_row(meters, "pi-qwencloud")
    if row is None:
        return fail(failures, f"{label} no pi-qwencloud row was written")
    check(row)


def case_i_seat_list(work, failures):
    for label, spelling in (("i-comma", "cc,cc2,cc3"), ("i-space", "cc cc2 cc3")):
        case = os.path.join(work, label)
        table = {seat: {"out": dict(MEASURED_CC, seat=seat)} for seat in ("cc", "cc2", "cc3")}
        _process, meters, _cache = run_feeder(
            case, "claude", table, overrides={"TALLY_CLAUDE_SEATS": spelling}
        )
        written = sorted(
            name for name in os.listdir(meters) if name.endswith(".json") and not name.startswith(".")
        )
        if written != ["cc.json", "cc2.json", "cc3.json"]:
            fail(failures, f"{label} wrote {written!r}, wanted all three Claude rows")


def main():
    failures = []
    with tempfile.TemporaryDirectory(prefix="cap1-seat-rows.") as work:
        case_a_fresh(work, failures)
        case_b_timeout_with_cache(work, failures)
        case_c_timeout_with_row(work, failures)
        case_d_timeout_with_nothing(work, failures)
        cached_read_case(work, failures, "E", 20, "MEASURED")
        cached_read_case(work, failures, "F", 200, "STALE-MEASURED")

        def held(row):
            window = row.get("window") or {}
            if window.get("kind") != "rolling" or window.get("minutes") != 10080:
                fail(failures, "G the held pi row does not carry a rolling week")
            if window.get("resets_at") != "2026-09-12T08:02:00Z":
                fail(failures, "G the held pi row does not carry the provider's reset")
            if window.get("utilization_pct") != "UNKNOWN" or not window.get("utilization_reason"):
                fail(failures, "G the held pi row invented a utilization")
            if row.get("window_remaining_pct") != "UNKNOWN" or not row.get("window_remaining_reason"):
                fail(failures, "G the held pi row invented a remainder")

        def released(row):
            if row.get("window") != "UNKNOWN" or not row.get("window_reason"):
                fail(failures, "H the released pi row does not say its window is UNKNOWN")

        pi_case(work, failures, "g-held", {"held": True, "held_until": "2026-09-12T08:02:00Z"}, held)
        pi_case(
            work,
            failures,
            "h-released",
            {"held": False, "held_until": "2026-09-12T08:02:00Z", "released_at": "2026-09-06T00:00:00Z"},
            released,
        )
        case_i_seat_list(work, failures)

    for failure in failures:
        print("FAIL " + failure)
    if failures:
        print(f"\nFAIL test-seat-rows: {len(failures)} case(s)")
        return 1
    print("PASS test-seat-rows: A–I")
    return 0


if __name__ == "__main__":
    sys.exit(main())
