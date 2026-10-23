"""Hermetic test for home/dot_local/bin/nightly-record (dotfiles#298).

Runs the REAL program against tests/nightly-record/fixtures, with
NIGHTLY_RECORD_HOME pointing at the fixture home. No network, no live seat, no
tally, no systemd.

What it pins:
  * every lane produces exactly one row per run, always five rows
  * the numbers are the fixture's numbers (so a parser change is visible)
  * only the requested DATE is counted
  * an unparseable line does not lose the rest of the file
  * a forked dsh session counts only its own calls, not the parent's copied
    prefix ahead of its session/end-seed marker
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
        self.assertEqual(sorted(rows), ["cc", "cc2", "cc3", "codex", "dsh"])
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

    def test_dsh_lane_reads_its_own_usage_shape(self):
        _, rows = run(pathlib.Path(FIXTURES) / "home", self.out)
        dsh = rows["dsh"]
        self.assertEqual(dsh["lane"], "dsh")
        # session-0000: 70 + 30 in, 8 + 2 out, (3+2) + 0 cache, a 20-second
        # span; its 2026-09-06 call and the trailing garbage line are skipped.
        # session-fork: only the 11/1/4 call after the end-seed marker; the
        # copied 500/50 call is the parent's.
        self.assertEqual(dsh["tokens_in"], 111)
        self.assertEqual(dsh["tokens_out"], 11)
        self.assertEqual(dsh["cache"], 9)
        self.assertEqual(dsh["seconds"], 20)
        self.assertEqual(dsh["source_files"], 2)
        self.assertEqual(dsh["grade"], "MEASURED")

    def test_a_pi_store_is_no_longer_read(self):
        home = pathlib.Path(self.tmp.name) / "pi-home"
        store = home / ".pi/agent/sessions/slug"
        store.mkdir(parents=True)
        (store / "session.jsonl").write_text(json.dumps({
            "type": "message", "timestamp": DATE + "T07:00:05.000Z",
            "message": {"role": "assistant", "usage": {"input": 70, "output": 8}}}) + "\n")
        result, rows = run(home, self.out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pi", rows)
        self.assertEqual(rows["dsh"]["grade"], "UNKNOWN")

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
