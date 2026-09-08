"""Hermetic test for home/dot_local/bin/seats.

Runs the REAL program with SEATS_NO_NETWORK=1 against a home tree this file
builds from scratch. No network, no live seat, no credential, no systemd.

The tree is BUILT rather than checked in because every fact this program
reports is time-relative: a window that reset "two days ago" and a transcript
written "yesterday" cannot be pinned to fixture files without the test rotting
the first time it is run on a different day.

What it pins:
  * one row per configured seat, always, whatever fails
  * a scoped per-model window at 100% does NOT spend the seat — only the
    session and weekly windows bind, which is the whole reason the field exists
  * open / tight / spent land on the right side of WARN_PCT and WALL_PCT
  * free_at is the earliest reset among the windows actually at the wall
  * Codex rate_limits come from the newest rollout that carries one, and its
    CUMULATIVE token totals are differenced rather than summed
  * the Qwen window is parsed out of the provider's own 429 text, year and all,
    and an expired hold stops holding
  * spend counts from the seat's own weekly window start, not a rolling week,
    and excludes events before it
  * --check returns 0 headroom / 1 spent / 2 unmeasurable
  * a seat whose store is missing still produces a row and never changes the
    exit code
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

SCRIPT = os.environ.get("SEATS_SCRIPT")
NOW = datetime.now(timezone.utc)


def iso(stamp):
    return stamp.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def window_cache(five_hour_pct, weekly_pct, weekly_reset, scoped=None):
    """The shape tally-seat-feeder leaves beside its meter rows."""
    usage = {
        "five_hour": {"utilization": five_hour_pct,
                      "resets_at": iso(NOW + timedelta(hours=3))},
        "seven_day": {"utilization": weekly_pct, "resets_at": iso(weekly_reset)},
        "seven_day_opus": None,
        "limits": [
            {"kind": "session", "group": "session", "percent": five_hour_pct,
             "resets_at": iso(NOW + timedelta(hours=3)), "scope": None},
            {"kind": "weekly_all", "group": "weekly", "percent": weekly_pct,
             "resets_at": iso(weekly_reset), "scope": None},
        ],
    }
    if scoped is not None:
        usage["limits"].append({
            "kind": "weekly_scoped", "group": "weekly", "percent": scoped,
            "resets_at": iso(weekly_reset),
            "scope": {"model": {"id": None, "display_name": "Fable"}}})
    return {"observed_at": iso(NOW - timedelta(seconds=30)), "usage": usage}


class SeatsFixture:
    """A whole box on disk: three Claude seats, a Codex, a pi, two GPUs."""

    def __init__(self, root: pathlib.Path):
        self.root = root
        self.home = root / "home"
        self.peer = root / "peer"
        self.state = root / "state"
        for path in (self.home, self.peer, self.state):
            path.mkdir(parents=True, exist_ok=True)
        self.weekly_reset = NOW + timedelta(days=2)
        self.window_start = self.weekly_reset - timedelta(days=7)

    # ── seats ───────────────────────────────────────────────────────────────
    def claude(self, seat, config, five_hour, weekly, scoped=None, events=()):
        (self.home / config).mkdir(parents=True, exist_ok=True)
        (self.home / config / ".credentials.json").write_text(json.dumps({
            "claudeAiOauth": {
                "accessToken": "sk-test-not-a-real-token",
                "rateLimitTier": "default_claude_max_20x",
                "subscriptionType": "max",
                "expiresAt": int((NOW + timedelta(hours=1)).timestamp() * 1000)}}))
        (self.peer / f".window-cache-{seat}.json").write_text(
            json.dumps(window_cache(five_hour, weekly, self.weekly_reset, scoped)))
        project = self.home / config / "projects" / "-proj"
        project.mkdir(parents=True, exist_ok=True)
        lines = []
        for when, tin, tout, cache in events:
            lines.append(json.dumps({
                "type": "assistant", "timestamp": iso(when),
                "message": {"usage": {"input_tokens": tin, "output_tokens": tout,
                                      "cache_read_input_tokens": cache,
                                      "cache_creation_input_tokens": 0}}}))
        lines.append("{ this line is not json")   # one bad line loses only itself
        (project / "session.jsonl").write_text("\n".join(lines) + "\n")

    def codex(self, used_percent, resets_at, totals):
        day = self.home / ".codex/sessions/2026/09/07"
        day.mkdir(parents=True, exist_ok=True)
        # An older rollout with no rate_limits at all must not shadow the newer.
        (day / "rollout-2026-09-07T00-00-00-old.jsonl").write_text(
            json.dumps({"timestamp": iso(NOW - timedelta(days=3)), "payload": {"type": "message"}}) + "\n")
        lines = []
        for when, cumulative in totals:
            lines.append(json.dumps({
                "timestamp": iso(when),
                "payload": {"type": "token_count", "info": {
                    "total_token_usage": {"input_tokens": cumulative[0],
                                          "output_tokens": cumulative[1],
                                          "cached_input_tokens": cumulative[2],
                                          "cache_write_input_tokens": 0}},
                    "rate_limits": {"limit_id": "codex",
                                    "primary": {"used_percent": used_percent,
                                                "window_minutes": 10080,
                                                "resets_at": int(resets_at.timestamp())},
                                    "secondary": None,
                                    "credits": {"has_credits": False, "balance": "0"}}}}))
        newer = day / "rollout-2026-09-07T12-00-00-new.jsonl"
        newer.write_text("\n".join(lines) + "\n")
        os.utime(newer, (NOW.timestamp(), NOW.timestamp()))

    def qwen(self, reason, observed_at, held_until=None):
        record = {"held": True, "reason": reason, "observed_at": iso(observed_at)}
        if held_until:
            record["held_until"] = iso(held_until)
        path = self.state / "qwen-hold.json"
        path.write_text(json.dumps(record))
        session = self.home / ".pi/agent/sessions/-proj"
        session.mkdir(parents=True, exist_ok=True)
        (session / "s.jsonl").write_text(json.dumps({
            "type": "message", "timestamp": iso(NOW - timedelta(hours=2)),
            "message": {"usage": {"input": 100, "output": 20,
                                  "cacheRead": 5, "cacheWrite": 0}}}) + "\n")
        return path

    # ── driving the program ─────────────────────────────────────────────────
    def env(self, extra=None):
        env = {**os.environ,
               "SEATS_NO_NETWORK": "1",
               "SEATS_HOME": str(self.home),
               "SEATS_STATE": str(self.state),
               "SEATS_PEER_CACHE_DIR": str(self.peer),
               "SEATS_QWEN_HOLD": str(self.state / "qwen-hold.json"),
               "SEATS_QWEN_KEY_FILE": str(self.state / "no-such-key"),
               "PYTHONDONTWRITEBYTECODE": "1",
               "NO_COLOR": "1"}
        env.pop("XDG_RUNTIME_DIR", None)   # never touch the caller's live cache
        env["XDG_RUNTIME_DIR"] = str(self.root / "runtime")
        (self.root / "runtime").mkdir(exist_ok=True)
        env.update(extra or {})
        return env

    def run(self, *args, extra_env=None):
        return subprocess.run([sys.executable, SCRIPT, *args],
                              env=self.env(extra_env), capture_output=True,
                              text=True, check=False)

    def report(self, *args):
        result = self.run("--json", *args)
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        return report, {seat["id"]: seat for seat in report["seats"]}


class SeatsTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT, "SEATS_SCRIPT must be set")
        self.tmp = tempfile.TemporaryDirectory()
        self.box = SeatsFixture(pathlib.Path(self.tmp.dir if False else self.tmp.name))
        self.addCleanup(self.tmp.cleanup)

        inside = self.box.window_start + timedelta(hours=6)
        before = self.box.window_start - timedelta(days=1)
        # cc: open, and one event before the window opens that must not count.
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, events=[
            (inside, 1000, 200, 50_000), (before, 999_999, 999_999, 0)])
        # cc2: weekly at the wall.
        self.box.claude("cc2", ".claude-work", 0.0, 96.0, events=[(inside, 10, 5, 0)])
        # cc3: tight, not spent.
        self.box.claude("cc3", ".claude-3", 85.0, 20.0, events=[])
        codex_inside = NOW - timedelta(days=1)     # codex's window opens at NOW-3d
        self.box.codex(98.0, NOW + timedelta(days=4), totals=[
            (codex_inside, (1000, 100, 500)),
            (codex_inside + timedelta(hours=1), (2500, 400, 900))])
        self.box.qwen(
            '429: {"message":"Your token-plan 1-week quota has been exhausted. '
            'The quota will reset at %s 08:02:00 UTC.","code":"insufficient_quota"}'
            % (NOW + timedelta(days=3)).strftime("%m-%d"),
            observed_at=NOW - timedelta(hours=5))

    # ── the shape of the answer ─────────────────────────────────────────────
    def test_every_seat_produces_exactly_one_row(self):
        report, seats = self.box.report()
        self.assertEqual(report["schema_version"], "seat-capacity/1")
        self.assertEqual(len(report["seats"]), 7)
        self.assertEqual(len(seats), 7, "seat ids must be unique")
        for seat in report["seats"]:
            self.assertIn("state", seat)
            self.assertIn(seat["grade"],
                          {"MEASURED", "CACHED", "MEASURED-FROM-REFUSAL", "UNKNOWN"})

    def test_a_scoped_model_window_does_not_spend_the_seat(self):
        _, seats = self.box.report()
        cc = seats["cc"]
        scoped = [w for w in cc["windows"] if w["id"] == "weekly:fable"]
        self.assertEqual(len(scoped), 1)
        self.assertEqual(scoped[0]["used_pct"], 100.0)
        self.assertFalse(scoped[0]["binding"])
        self.assertEqual(cc["state"], "open", "a scoped row must not bind the seat")
        self.assertTrue(cc["usable"])

    def test_thresholds_place_each_seat(self):
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["state"], "open")     # worst binding 45
        self.assertEqual(seats["cc3"]["state"], "tight")   # worst binding 85
        self.assertEqual(seats["cc2"]["state"], "spent")   # worst binding 96
        self.assertFalse(seats["cc2"]["usable"])
        self.assertTrue(seats["cc3"]["usable"], "tight is still usable")

    def test_free_at_is_the_walled_windows_reset(self):
        _, seats = self.box.report()
        self.assertEqual(seats["cc2"]["free_at"], iso(self.box.weekly_reset))
        self.assertEqual(seats["cc"]["free_at"], "", "an open seat is free now")

    def test_remaining_is_the_complement_of_used(self):
        _, seats = self.box.report()
        for seat in seats.values():
            for entry in seat["windows"]:
                if entry["used_pct"] is not None:
                    self.assertAlmostEqual(
                        entry["used_pct"] + entry["remaining_pct"], 100.0, places=6)

    # ── Codex ───────────────────────────────────────────────────────────────
    def test_codex_reads_the_newest_rollout_that_carries_limits(self):
        _, seats = self.box.report()
        codex = seats["codex"]
        self.assertEqual(codex["grade"], "MEASURED")
        self.assertEqual(codex["source"]["kind"], "codex-rollout-rate-limits")
        self.assertTrue(codex["source"]["path"].endswith("new.jsonl"))
        primary = [w for w in codex["windows"] if w["id"] == "codex:primary"]
        self.assertEqual(primary[0]["used_pct"], 98.0)
        self.assertEqual(primary[0]["minutes"], 10080)
        self.assertEqual(codex["state"], "spent")

    def test_codex_totals_are_differenced_not_summed(self):
        _, seats = self.box.report()
        spend = seats["codex"]["spend"]
        # Cumulative 1000/100/500 then 2500/400/900 is a spend of 2500/400/900,
        # not the 3500/500/1400 a naive sum would report.
        self.assertEqual(spend["tokens_in"], 2500)
        self.assertEqual(spend["tokens_out"], 400)
        self.assertEqual(spend["cache_tokens"], 900)

    # ── Qwen Cloud ──────────────────────────────────────────────────────────
    def test_qwen_window_comes_out_of_the_refusal_text(self):
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["grade"], "MEASURED-FROM-REFUSAL")
        self.assertEqual(qwen["state"], "spent")
        expected = (NOW + timedelta(days=3)).strftime("%Y-%m-%dT08:02:00Z")
        self.assertEqual(qwen["free_at"], expected)
        self.assertEqual(qwen["windows"][0]["used_pct"], 100.0)

    def test_an_expired_qwen_hold_stops_holding(self):
        self.box.qwen(
            '429: {"message":"Your token-plan 1-week quota has been exhausted. '
            'The quota will reset at %s 08:02:00 UTC."}'
            % (NOW - timedelta(days=2)).strftime("%m-%d"),
            observed_at=NOW - timedelta(days=9))
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertNotEqual(qwen["state"], "spent")
        self.assertIn("hold expired", qwen["detail"])

    # ── spend ───────────────────────────────────────────────────────────────
    def test_spend_counts_the_seats_own_window_only(self):
        _, seats = self.box.report()
        spend = seats["cc"]["spend"]
        self.assertEqual(spend["basis"], "seat-weekly-window")
        self.assertEqual(spend["window_start"], iso(self.box.window_start))
        self.assertEqual(spend["tokens_in"], 1000)
        self.assertEqual(spend["tokens_out"], 200)
        self.assertEqual(spend["cache_tokens"], 50_000)
        self.assertEqual(spend["billable_tokens"], 1200)
        self.assertEqual(spend["total_tokens"], 51_200)

    def test_no_spend_skips_the_scan_entirely(self):
        _, seats = self.box.report("--no-spend")
        self.assertIsNone(seats["cc"]["spend"])

    # ── failure is a row, not a silence ─────────────────────────────────────
    def test_a_missing_store_still_produces_a_row(self):
        for path in (self.box.peer / ".window-cache-cc3.json",
                     self.box.home / ".claude-3/.credentials.json"):
            path.unlink()
        result = self.box.run("--json")
        self.assertEqual(result.returncode, 0)
        seats = {s["id"]: s for s in json.loads(result.stdout)["seats"]}
        self.assertIn("cc3", seats)
        self.assertEqual(seats["cc3"]["state"], "unauth")
        self.assertEqual(seats["cc3"]["windows"], [])
        self.assertEqual(seats["cc"]["state"], "open", "one dead seat is not seven")

    def test_offline_reports_the_gpu_rows_without_guessing(self):
        _, seats = self.box.report()
        self.assertEqual(seats["gpu-worker"]["state"], "offline")
        self.assertEqual(seats["gpu-worker"]["grade"], "UNKNOWN")
        self.assertFalse(seats["gpu-worker"]["windows"])

    # ── the oracles ─────────────────────────────────────────────────────────
    def test_check_exit_codes(self):
        self.assertEqual(self.box.run("--check", "cc").returncode, 0)
        self.assertEqual(self.box.run("--check", "cc2").returncode, 1)
        self.assertEqual(self.box.run("--check", "gpu-worker").returncode, 2)
        self.assertEqual(self.box.run("--check", "no-such-seat").returncode, 2)

    def test_check_honours_window_and_threshold(self):
        # cc3 is 85% on the session window and 20% weekly, so which window is
        # asked about decides the answer, and so does where the wall is put.
        self.assertEqual(self.box.run("--check", "cc3", "--window", "seven_day").returncode, 0)
        self.assertEqual(self.box.run("--check", "cc3", "--window", "five_hour").returncode, 0)
        self.assertEqual(
            self.box.run("--check", "cc3", "--window", "five_hour",
                         "--threshold", "80").returncode, 1)
        self.assertEqual(
            self.box.run("--check", "cc3", "--threshold", "80").returncode, 1,
            "--window any takes the worst binding window")

    def test_pick_names_the_seat_with_the_most_headroom(self):
        result = self.box.run("--pick")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "cc")

    def test_pick_fails_when_nothing_is_open(self):
        for seat, config in (("cc", ".claude"), ("cc2", ".claude-work"), ("cc3", ".claude-3")):
            self.box.claude(seat, config, 99.0, 99.0)
        self.assertEqual(self.box.run("--pick").returncode, 1)

    # ── the other renderings ────────────────────────────────────────────────
    def test_table_tsv_and_jsonl_all_render(self):
        table = self.box.run()
        self.assertEqual(table.returncode, 0)
        self.assertIn("cc3", table.stdout)
        self.assertIn("SEAT", table.stdout)
        for line in table.stdout.splitlines():
            self.assertNotIn("\t", line, "the table must not emit tabs")

        tsv = self.box.run("--tsv")
        header = tsv.stdout.splitlines()[0].split("\t")
        for row in tsv.stdout.splitlines()[1:]:
            self.assertEqual(len(row.split("\t")), len(header))

        jsonl = self.box.run("--jsonl")
        rows = [json.loads(line) for line in jsonl.stdout.splitlines()]
        self.assertEqual(len(rows), 7)
        self.assertTrue(all("generated_at" in row for row in rows))

    def test_only_filters_by_id_and_by_provider(self):
        _, seats = self.box.report("--only", "cc3")
        self.assertEqual(list(seats), ["cc3"])
        _, seats = self.box.report("--only", "claude")
        self.assertEqual(sorted(seats), ["cc", "cc2", "cc3"])

    def test_no_token_is_ever_printed(self):
        for args in ([], ["--json"], ["--tsv"], ["--jsonl"]):
            result = self.box.run(*args)
            self.assertNotIn("sk-test-not-a-real-token", result.stdout)
            self.assertNotIn("sk-test-not-a-real-token", result.stderr)


if __name__ == "__main__":
    unittest.main()
