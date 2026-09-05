"""Hermetic test for home/dot_local/bin/nightly-record (dotfiles#298).

Runs the REAL program against tests/nightly-record/fixtures, with
NIGHTLY_RECORD_HOME pointing at the fixture home. No network, no live seat, no
tally, no systemd.

What it pins:
  * every lane produces exactly one row per run, always five rows
  * the numbers are the fixture's numbers (so a parser change is visible)
  * only the requested DATE is counted
  * an unparseable line does not lose the rest of the file
  * a store that exists but has nothing for the date is MEASURED with zeros,
    not UNKNOWN — "the seat was idle" and "the seat is unreadable" are
    different facts
  * a missing store is UNKNOWN with zeros, and the program still exits 0
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.environ.get("NIGHTLY_RECORD_SCRIPT")
FIXTURES = os.environ.get("NIGHTLY_RECORD_FIXTURES")
DATE = "2026-09-05"


def run(home, out):
    result = subprocess.run(
        [sys.executable, SCRIPT, "--date", DATE, "--out", str(out)],
        env={**os.environ, "NIGHTLY_RECORD_HOME": str(home)},
        capture_output=True,
        text=True,
        check=False,
    )
    rows = {}
    written = pathlib.Path(out) / f"{DATE}.jsonl"
    if written.exists():
        for line in written.read_text().splitlines():
            row = json.loads(line)
            rows[row["seat"]] = row
    return result, rows


class NightlyRecordTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT, "NIGHTLY_RECORD_SCRIPT must be set")
        self.assertTrue(FIXTURES, "NIGHTLY_RECORD_FIXTURES must be set")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = pathlib.Path(self.tmp.name) / "out"

    def test_every_lane_produces_exactly_one_row(self):
        result, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(rows), ["cc", "cc2", "cc3", "codex", "pi"])
        for seat, row in rows.items():
            self.assertEqual(row["date"], DATE, seat)
            self.assertIn(row["grade"], ("MEASURED", "UNKNOWN"), seat)

    def test_claude_lane_counts_the_fixture_and_only_that_date(self):
        _, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        cc = rows["cc"]
        # 100 + 50 in, 20 + 10 out, (5+7) + (1+2) cache. The 2026-09-06 record
        # in the same file is excluded, and the trailing garbage line is
        # skipped without losing the two good records before it.
        self.assertEqual(cc["tokens_in"], 150)
        self.assertEqual(cc["tokens_out"], 30)
        self.assertEqual(cc["cache"], 15)
        self.assertEqual(cc["seconds"], 30)
        self.assertEqual(cc["source_files"], 1)
        self.assertEqual(cc["grade"], "MEASURED")

    def test_codex_lane_takes_the_last_cumulative_token_count(self):
        _, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        codex = rows["codex"]
        self.assertEqual(codex["tokens_in"], 40)
        self.assertEqual(codex["tokens_out"], 9)
        self.assertEqual(codex["cache"], 10)
        self.assertEqual(codex["seconds"], 120)
        self.assertEqual(codex["grade"], "MEASURED")

    def test_pi_lane_reads_its_own_usage_shape(self):
        _, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        pi = rows["pi"]
        self.assertEqual(pi["tokens_in"], 70)
        self.assertEqual(pi["tokens_out"], 8)
        self.assertEqual(pi["cache"], 5)
        self.assertEqual(pi["grade"], "MEASURED")

    def test_idle_seat_is_measured_zero_not_unknown(self):
        _, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        cc3 = rows["cc3"]
        self.assertEqual(cc3["grade"], "MEASURED")
        self.assertEqual(cc3["tokens_in"], 0)
        self.assertEqual(cc3["tokens_out"], 0)
        self.assertEqual(cc3["source_files"], 0)

    def test_missing_stores_grade_unknown_and_still_exit_zero(self):
        empty = pathlib.Path(self.tmp.name) / "empty-home"
        empty.mkdir()
        result, rows = run(empty, self.out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(rows), 5)
        for seat, row in rows.items():
            self.assertEqual(row["grade"], "UNKNOWN", seat)
            self.assertEqual(row["tokens_in"], 0, seat)
            self.assertEqual(row["seconds"], 0, seat)


if __name__ == "__main__":
    unittest.main()
