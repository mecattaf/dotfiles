#!/usr/bin/env python3
"""A deterministic `stamp-receipt.py window` source for the fixture only.

U-D12 DF-SEAT-FEEDER (dotfiles#315). tools/feeder-fixture.sh points
TALLY_STAMP_RECEIPT at this file, so the replay exercises the REAL feeder
program — its row shaping, its atomic write, its pinned-directory refusal, its
clock — with the one thing an oracle must never do redirected: no credential
file is opened, no token exists, and no request leaves the box.

The numbers are the MEASURED 11:39Z readings recorded in DECISIONS.md D-B5
(cc five_hour 43% resetting 13:39:59Z, seven_day 79% resetting 09-09T09:59Z;
cc2 five_hour 100% resetting 14:10Z, seven_day 52% resetting 09-10T06:00Z), so
the fixture's rows are the shape of a real reading rather than an invented one.
cc3 answers the way the real seat answered that morning — an expired token — so
the fixture also covers the grade-UNKNOWN path on a Claude seat.

The interface it must match is stamp-receipt.py's own: one JSON object on
stdout, `grade` MEASURED with `five_hour`/`seven_day` cells, or `grade` UNKNOWN
with a `reason`; exit 0 on MEASURED, 2 on UNKNOWN.
"""

import json
import os
import sys

SEATS = {
    "cc": {
        "grade": "MEASURED",
        "five_hour": {"utilization": 43, "resets_at": "2026-09-06T13:39:59Z"},
        "seven_day": {"utilization": 79, "resets_at": "2026-09-09T09:59:00Z"},
        "window_id": "2026-09-06T13:39:59Z",
    },
    "cc2": {
        "grade": "MEASURED",
        "five_hour": {"utilization": 100, "resets_at": "2026-09-06T14:10:00Z"},
        "seven_day": {"utilization": 52, "resets_at": "2026-09-10T06:00:00Z"},
        "window_id": "2026-09-06T14:10:00Z",
    },
    "cc3": {
        "grade": "UNKNOWN",
        "reason": "RuntimeError: token expired; run `claude` on that seat to refresh",
        "window_id": "unknown",
    },
}


def main(argv):
    if len(argv) < 4 or argv[1] != "window" or argv[2] != "--seat":
        sys.stderr.write("stamp-receipt-fixture: usage: window --seat <seat>\n")
        return 64
    seat = argv[3]
    out = dict(SEATS.get(seat) or {"grade": "UNKNOWN", "reason": f"no such seat {seat!r}"})
    out["seat"] = seat
    # The real reader stamps its source time.  The replay pins the clock for
    # each tick, so returning that same instant also proves the feeder preserves
    # a source timestamp instead of manufacturing a newer one.
    out["observed_at"] = os.environ.get("TALLY_FEEDER_NOW", "2026-09-06T00:00:00Z")
    print(json.dumps(out))
    return 0 if out.get("grade") == "MEASURED" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
