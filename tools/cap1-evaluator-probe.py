#!/usr/bin/env python3
"""tools/cap1-evaluator-probe.py — the EVALUATOR's own probe of CAP-1.

Not the card's clauses (tools/seat-rows-oracle.sh is the DOMINANT oracle); the
floor the card did not ask for. Five cases, all hermetic — no network, no
credential, no cargo, no live meters dir, the clock pinned by TALLY_FEEDER_NOW:

  P1  pi-qwencloud with the hold RELEASED: the feeder writes `window:
      "UNKNOWN"` (tests/seat-feeder/test-seat-rows.py case H asserts exactly
      that) and the DOMINANT oracle is then run on the very same directory.
      The oracle requires `window` to be an OBJECT whose kind is nested or
      rolling, so the two instruments contradict each other on a state the
      box reaches by itself.
  P2  the 45 s boundary of D-B92: a reader that fails with a retained reading
      exactly 45 s old must grade MEASURED, and one 46 s old STALE-MEASURED.
  P3  clock skew: a retained reading stamped in the FUTURE must not publish a
      negative reading_age_seconds.
  P4  newer-first: with both a published row and a reader cache retained, the
      newer of the two must be the one re-published — in both orders.
  P5  the cold box: reader down and NOTHING retained anywhere — the row must
      still exist and refuse with a reason, never crash.

Exit 0 when every case behaves as recorded below; 1 naming each that does not.
Cases whose observed behaviour is itself the finding (P1) assert the finding.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEEDER = os.path.join(REPO, "home", "dot_local", "bin", "tally-seat-feeder")
ORACLE = os.path.join(REPO, "tools", "seat-rows-oracle.sh")
NOW = "2026-09-07T18:00:00Z"

FAILING_READER = "import sys; sys.stderr.write('down\\n'); sys.exit(3)\n"


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2)


def run_feeder(work, instrument, extra=None):
    env = dict(os.environ)
    env.update(
        {
            "TALLY_REWRITE_METERS": os.path.join(work, "meters"),
            "TALLY_WINDOW_CACHE_DIR": os.path.join(work, "cache"),
            "TALLY_PI_HOLD": os.path.join(work, "pi-hold.json"),
            "TALLY_STAMP_RECEIPT": os.path.join(work, "reader.py"),
            "TALLY_CODEX_SESSIONS": os.path.join(work, "codex-sessions"),
            "TALLY_CLAUDE_SEATS": "cc",
            "TALLY_FEEDER_NOW": NOW,
        }
    )
    env.update(extra or {})
    os.makedirs(env["TALLY_REWRITE_METERS"], exist_ok=True)
    os.makedirs(env["TALLY_WINDOW_CACHE_DIR"], exist_ok=True)
    proc = subprocess.run(
        [sys.executable, FEEDER, instrument],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    return proc, env["TALLY_REWRITE_METERS"]


def read_row(meters, seat):
    path = os.path.join(meters, seat + ".json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def failing_reader(work):
    path = os.path.join(work, "reader.py")
    os.makedirs(work, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(FAILING_READER)
    return path


def cache_reading(work, seat, observed_at, five=44.0, seven=61.0):
    write(
        os.path.join(work, "cache", ".window-cache-%s.json" % seat),
        {
            "observed_at": observed_at,
            "usage": {
                "five_hour": {"utilization": five, "resets_at": "2026-09-07T21:00:00Z"},
                "seven_day": {"utilization": seven, "resets_at": "2026-09-12T08:02:00Z"},
                "seven_day_opus": {"utilization": None, "resets_at": None},
                "seven_day_sonnet": {"utilization": None, "resets_at": None},
            },
        },
    )


def case(name, ok, detail, failures):
    print("%-4s %-5s %s" % (name, "ok" if ok else "FAIL", detail))
    if not ok:
        failures.append(name)


def p1(root, failures):
    work = os.path.join(root, "p1")
    failing_reader(work)
    write(
        os.path.join(work, "pi-hold.json"),
        {"held": False, "held_until": "2026-09-12T08:02:00Z", "released_at": "2026-09-06T00:00:00Z"},
    )
    _proc, meters = run_feeder(work, "pi-qwencloud")
    row = read_row(meters, "pi-qwencloud")
    shape = None if row is None else row.get("window")
    case(
        "P1a",
        shape == "UNKNOWN" and bool(row.get("window_reason")),
        "released hold -> window is %r (test H's assertion)" % (shape,),
        failures,
    )
    oracle = subprocess.run(
        ["bash", ORACLE, meters], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900
    )
    text = oracle.stdout.decode("utf-8", "replace")
    named = "FAIL pi-qwencloud" in text and "window is" in text
    case(
        "P1b",
        oracle.returncode == 1 and named,
        "the DOMINANT oracle on that same dir -> rc %d; it refuses the shape "
        "its own test asserts" % oracle.returncode,
        failures,
    )
    for line in text.splitlines():
        if line.startswith("FAIL pi-qwencloud"):
            print("       | " + line)


def p2(root, failures):
    for age, expected in ((45, "MEASURED"), (46, "STALE-MEASURED")):
        work = os.path.join(root, "p2-%d" % age)
        failing_reader(work)
        observed = "2026-09-07T17:59:%02dZ" % (60 - age) if age < 60 else "2026-09-07T17:59:14Z"
        cache_reading(work, "cc", observed)
        _proc, meters = run_feeder(work, "claude")
        row = read_row(meters, "cc") or {}
        got_age = row.get("reading_age_seconds")
        case(
            "P2/%d" % age,
            row.get("grade") == expected and got_age == age,
            "retained reading %ss old -> grade %r age %r (expected %r/%d)"
            % (age, row.get("grade"), got_age, expected, age),
            failures,
        )


def p3(root, failures):
    work = os.path.join(root, "p3")
    failing_reader(work)
    cache_reading(work, "cc", "2026-09-07T19:00:00Z")  # one hour in the future
    _proc, meters = run_feeder(work, "claude")
    row = read_row(meters, "cc") or {}
    age = row.get("reading_age_seconds")
    case(
        "P3",
        isinstance(age, int) and age >= 0,
        "reading stamped 3600 s in the FUTURE -> reading_age_seconds %r" % (age,),
        failures,
    )


def p4(root, failures):
    # the reader cache is the newer of the two
    work = os.path.join(root, "p4a")
    failing_reader(work)
    cache_reading(work, "cc", "2026-09-07T17:59:00Z", five=44.0)
    write(
        os.path.join(work, "meters", "cc.json"),
        {
            "seat": "cc",
            "reading_observed_at": "2026-09-07T17:00:00Z",
            "window": {
                "kind": "nested",
                "primary": {"minutes": 300, "resets_at": "2026-09-07T21:00:00Z", "utilization_pct": 11.0},
                "secondary": {"minutes": 10080, "resets_at": "2026-09-12T08:02:00Z", "utilization_pct": 12.0},
            },
        },
    )
    _proc, meters = run_feeder(work, "claude")
    row = read_row(meters, "cc") or {}
    case(
        "P4a",
        row.get("utilization_pct") == 44.0 and row.get("reading_age_seconds") == 60,
        "cache newer than published row -> utilization %r age %r (want 44.0/60)"
        % (row.get("utilization_pct"), row.get("reading_age_seconds")),
        failures,
    )

    # the published row is the newer of the two
    work = os.path.join(root, "p4b")
    failing_reader(work)
    cache_reading(work, "cc", "2026-09-07T17:00:00Z", five=44.0)
    write(
        os.path.join(work, "meters", "cc.json"),
        {
            "seat": "cc",
            "reading_observed_at": "2026-09-07T17:59:00Z",
            "window": {
                "kind": "nested",
                "primary": {"minutes": 300, "resets_at": "2026-09-07T21:00:00Z", "utilization_pct": 11.0},
                "secondary": {"minutes": 10080, "resets_at": "2026-09-12T08:02:00Z", "utilization_pct": 12.0},
            },
        },
    )
    _proc, meters = run_feeder(work, "claude")
    row = read_row(meters, "cc") or {}
    case(
        "P4b",
        row.get("utilization_pct") == 11.0 and row.get("reading_age_seconds") == 60,
        "published row newer than cache -> utilization %r age %r (want 11.0/60)"
        % (row.get("utilization_pct"), row.get("reading_age_seconds")),
        failures,
    )


def p5(root, failures):
    work = os.path.join(root, "p5")
    failing_reader(work)
    proc, meters = run_feeder(work, "claude")
    row = read_row(meters, "cc") or {}
    grade = (row.get("capacity") or {}).get("grade")
    reason = (row.get("capacity") or {}).get("reason") or ""
    case(
        "P5",
        proc.returncode == 0 and grade == "UNKNOWN" and "no MEASURED reading was retained" in reason,
        "cold box -> feeder rc %d, grade %r, reason names the empty retention"
        % (proc.returncode, grade),
        failures,
    )


def main():
    for tool in (FEEDER, ORACLE):
        if not os.path.exists(tool):
            print("cap1-evaluator-probe: %s is absent" % tool, file=sys.stderr)
            return 2
    root = tempfile.mkdtemp(prefix="cap1-probe.")
    failures = []
    try:
        p1(root, failures)
        p2(root, failures)
        p3(root, failures)
        p4(root, failures)
        p5(root, failures)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    if failures:
        print("\nFAIL cap1-evaluator-probe: %s" % ", ".join(failures))
        return 1
    print("\nPASS cap1-evaluator-probe: every case behaved as recorded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
