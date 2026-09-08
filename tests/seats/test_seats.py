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

import importlib.machinery
import importlib.util
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


def window_cache(five_hour_pct, weekly_pct, weekly_reset, scoped=None,
                 severity=None, active=None):
    """The shape tally-seat-feeder leaves beside its meter rows.

    `severity` and `active` are the provider's own grading, which the meter now
    reads in preference to its local thresholds. Passing None for severity
    leaves the payload ungraded, which is how the threshold fallback is tested.
    """
    usage = {
        "five_hour": {"utilization": five_hour_pct,
                      "resets_at": iso(NOW + timedelta(hours=3))},
        "seven_day": {"utilization": weekly_pct, "resets_at": iso(weekly_reset)},
        "seven_day_opus": None,
        "extra_usage": {"is_enabled": False, "utilization": None},
        "spend": {"enabled": False, "can_purchase_credits": False},
        "limits": [
            {"kind": "session", "group": "session", "percent": five_hour_pct,
             "resets_at": iso(NOW + timedelta(hours=3)), "scope": None,
             "severity": "normal" if severity else None, "is_active": False},
            {"kind": "weekly_all", "group": "weekly", "percent": weekly_pct,
             "resets_at": iso(weekly_reset), "scope": None,
             "severity": severity, "is_active": active is None or active == "weekly_all"},
        ],
    }
    if scoped is not None:
        usage["limits"].append({
            "kind": "weekly_scoped", "group": "weekly", "percent": scoped,
            "resets_at": iso(weekly_reset), "severity": severity,
            "is_active": active == "scoped",
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
    def claude(self, seat, config, five_hour, weekly, scoped=None, events=(),
               severity=None, active=None):
        (self.home / config).mkdir(parents=True, exist_ok=True)
        (self.home / config / ".credentials.json").write_text(json.dumps({
            "claudeAiOauth": {
                "accessToken": "sk-test-not-a-real-token",
                "rateLimitTier": "default_claude_max_20x",
                "subscriptionType": "max",
                "expiresAt": int((NOW + timedelta(hours=1)).timestamp() * 1000)}}))
        (self.peer / f".window-cache-{seat}.json").write_text(
            json.dumps(window_cache(five_hour, weekly, self.weekly_reset, scoped,
                                    severity, active)))
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

    def qwen(self, messages=(), refusals=(), hold=None):
        """messages: (when, input, output, cacheRead, provider). refusals:
        (when, reset). hold: an explicit hold record, for the paths that still
        depend on one."""
        session = self.home / ".pi/agent/sessions/-proj"
        session.mkdir(parents=True, exist_ok=True)
        lines = []
        for when, tin, tout, cache, provider in messages:
            lines.append(json.dumps({
                "type": "message", "timestamp": iso(when),
                "message": {"provider": provider, "model": "qwen3.8-max",
                            "usage": {"input": tin, "output": tout,
                                      "cacheRead": cache, "cacheWrite": 0}}}))
        for when, reset in refusals:
            lines.append(json.dumps({
                "type": "error", "timestamp": iso(when),
                "error": ("429 insufficient_quota: Your token-plan 1-week quota has been "
                          "exhausted. The quota will reset at %s UTC."
                          % reset.strftime("%m-%d %H:%M:%S"))}))
        (session / "s.jsonl").write_text("\n".join(lines) + "\n")
        path = self.state / "qwen-hold.json"
        if hold is not None:
            path.write_text(json.dumps(hold))
        elif path.exists():
            path.unlink()
        # The event cache is keyed by (mtime, size); a rewritten fixture in the
        # same second with the same length must not be served from it.
        for stale in self.state.glob("qwen-events.json"):
            stale.unlink()
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
        # Qwen: a reset four days ago, the window opened by first use three
        # days ago, and 96,250 billable tokens spent inside it — 500 credits at
        # the calibrated 192.5 tokens/credit, so 5.0% of the 10,000 allowance.
        # The cache reads and the llama-swap message must not be billed.
        self.qwen_reset = NOW - timedelta(days=4)
        self.qwen_opened = NOW - timedelta(days=3)
        self.box.qwen(
            messages=[
                (self.qwen_reset - timedelta(hours=1), 500_000, 0, 0, "qwen-token-plan"),
                (self.qwen_opened, 90_000, 6_250, 9_000_000, "qwen-token-plan"),
                (self.qwen_opened + timedelta(hours=1), 999_999, 999_999, 0, "llama-swap"),
            ],
            refusals=[(self.qwen_reset - timedelta(days=2), self.qwen_reset)])

    # ── the shape of the answer ─────────────────────────────────────────────
    def test_every_seat_produces_exactly_one_row(self):
        report, seats = self.box.report()
        self.assertEqual(report["schema_version"], "seat-capacity/1")
        self.assertEqual(len(report["seats"]), 7)
        self.assertEqual(len(seats), 7, "seat ids must be unique")
        for seat in report["seats"]:
            self.assertIn("state", seat)
            self.assertIn(seat["grade"],
                          {"MEASURED", "CACHED", "MEASURED-FROM-REFUSAL",
                           "ESTIMATED", "UNKNOWN"})

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
    def test_codex_falls_back_to_rollouts_and_says_that_is_what_it_did(self):
        # The account is the default source. With no way to reach it, the
        # rollout read is a fallback and is graded and labelled as one: it is
        # what Codex was last TOLD, which on this box was once 98% while the
        # account said 0% because the window had reset.
        _, seats = self.box.report()
        codex = seats["codex"]
        self.assertEqual(codex["grade"], "CACHED")
        self.assertEqual(codex["source"]["kind"], "codex-rollout-rate-limits")
        self.assertTrue(codex["source"]["path"].endswith("new.jsonl"))
        self.assertIn("not what the account says now", codex["detail"])
        primary = [w for w in codex["windows"] if w["id"] == "codex:primary"]
        self.assertEqual(primary[0]["used_pct"], 98.0)
        self.assertEqual(primary[0]["minutes"], 10080)
        self.assertEqual(codex["state"], "spent")

    def test_codex_rollouts_flag_forces_the_local_read(self):
        result = self.box.run("--json", "--codex-rollouts")
        seats = {s["id"]: s for s in json.loads(result.stdout)["seats"]}
        self.assertEqual(seats["codex"]["source"]["kind"], "codex-rollout-rate-limits")

    def test_codex_totals_are_differenced_not_summed(self):
        _, seats = self.box.report()
        spend = seats["codex"]["spend"]
        # Cumulative 1000/100/500 then 2500/400/900 is a spend of 2500/400/900,
        # not the 3500/500/1400 a naive sum would report.
        self.assertEqual(spend["tokens_in"], 2500)
        self.assertEqual(spend["tokens_out"], 400)
        self.assertEqual(spend["cache_tokens"], 900)

    # ── Qwen Cloud ──────────────────────────────────────────────────────────
    def test_qwen_window_opens_on_first_use_not_on_the_reset(self):
        _, seats = self.box.report()
        entry = seats["pi-qwencloud"]["windows"][0]
        self.assertEqual(entry["window_start"], iso(self.qwen_opened))
        self.assertEqual(entry["resets_at"], iso(self.qwen_opened + timedelta(days=7)),
                         "seven days from first use, not seven days from the reset")

    def test_qwen_resets_are_recovered_from_the_refusal_history(self):
        _, seats = self.box.report()
        self.assertIn(iso(self.qwen_reset),
                      seats["pi-qwencloud"]["source"]["known_resets"])

    def test_qwen_credits_come_from_billable_tokens_only(self):
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["grade"], "ESTIMATED")
        credits = qwen["credits"]
        # 90,000 + 6,250 = 96,250 billable; the 9,000,000 cache reads, the
        # llama-swap message and the pre-window message are all excluded.
        self.assertEqual(credits["billable_tokens"], 96_250)
        self.assertEqual(credits["used"], 500)
        self.assertEqual(credits["remaining"], 9_500)
        self.assertEqual(qwen["windows"][0]["used_pct"], 5.0)
        self.assertEqual(qwen["state"], "open")

    def test_qwen_local_traffic_is_never_billed(self):
        _, seats = self.box.report()
        # The llama-swap message carries ~2M tokens and would dominate both
        # the credit estimate and the spend row if the provider went unchecked.
        self.assertEqual(seats["pi-qwencloud"]["spend"]["tokens_in"], 90_000)

    def test_a_live_refusal_outranks_the_estimate(self):
        held = NOW + timedelta(days=3)
        self.box.qwen(
            messages=[(NOW - timedelta(hours=2), 10, 10, 0, "qwen-token-plan")],
            refusals=[(NOW - timedelta(hours=1), held)])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["grade"], "MEASURED-FROM-REFUSAL")
        self.assertEqual(qwen["state"], "spent")
        self.assertEqual(qwen["free_at"], iso(held))
        self.assertEqual(qwen["credits"]["remaining"], 0,
                         "the provider saying exhausted beats an estimate saying otherwise")

    def test_qwen_with_no_use_since_the_reset_holds_the_full_allowance(self):
        self.box.qwen(refusals=[(NOW - timedelta(days=3), NOW - timedelta(days=1))])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["state"], "open")
        self.assertEqual(qwen["credits"]["remaining"], 10_000)
        self.assertEqual(qwen["windows"][0]["used_pct"], 0.0)
        self.assertIn("opens on first use", qwen["detail"])

    def test_the_plan_terms_are_published_with_the_seat(self):
        _, seats = self.box.report()
        plan = seats["pi-qwencloud"]["plan"]
        self.assertEqual(plan["credits_per_window"], 10_000)
        self.assertEqual(plan["window_days"], 7)
        self.assertEqual(plan["max_concurrent_agents"], 4)
        self.assertIn("cache reads are free", plan["counts"])

    def test_the_plan_can_be_overridden_without_editing_the_program(self):
        config = self.box.home / ".config/seats"
        config.mkdir(parents=True, exist_ok=True)
        (config / "qwen-plan.json").write_text(json.dumps(
            {"credits_per_window": 2500, "tokens_per_credit": 192.5}))
        _, seats = self.box.report()
        credits = seats["pi-qwencloud"]["credits"]
        self.assertEqual(credits["allowance"], 2500)
        self.assertEqual(credits["used"], 500)
        self.assertEqual(seats["pi-qwencloud"]["windows"][0]["used_pct"], 20.0)

    # ── scoped model caps: repeated from the API, never converted ───────────
    def test_scoped_and_account_limits_are_both_reported_verbatim(self):
        _, seats = self.box.report()
        budget = seats["cc"]["model_budget"]
        self.assertEqual(budget["account_used_pct"], 45.0)
        self.assertEqual(budget["account_remaining_pct"], 55.0)
        row = budget["models"][0]
        self.assertEqual(row["model"], "Fable")
        self.assertEqual(row["used_pct"], 100.0)
        self.assertEqual(row["remaining_pct"], 0.0)

    def test_no_share_conversion_is_invented(self):
        # An earlier version turned a scoped percentage into "points of the
        # account's week" with an assumed 50% share. The box's own data refuses
        # any fixed share, so the meter must not publish one.
        _, seats = self.box.report()
        blob = json.dumps(seats["cc"])
        for invented in ("share_of_total", "account_points_used",
                         "account_points_cap", "points_left_for_this_model"):
            self.assertNotIn(invented, blob)

    def test_a_scoped_limit_never_spends_the_seat(self):
        _, seats = self.box.report()
        cc = seats["cc"]
        self.assertEqual(cc["model_budget"]["models"][0]["used_pct"], 100.0)
        self.assertEqual(cc["state"], "open", "Fable's cap binds Fable, not the account")
        self.assertTrue(cc["usable"])

    def test_the_governing_limit_is_taken_from_the_provider(self):
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="scoped")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["model_budget"]["governing_limit"], "weekly:fable")
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="weekly_all")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["model_budget"]["governing_limit"], "seven_day")

    # ── the provider's own grading outranks a local threshold ───────────────
    def test_provider_severity_decides_the_state(self):
        # 45% would be "open" on the local thresholds; the provider says
        # critical, and the provider is describing its own product.
        self.box.claude("cc", ".claude", 10.0, 45.0, severity="critical")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["state"], "spent")
        self.assertIn("provider severity critical", seats["cc"]["state_basis"])
        self.assertEqual(seats["cc"]["free_at"], iso(self.box.weekly_reset))

    def test_thresholds_apply_only_when_the_provider_does_not_grade(self):
        _, seats = self.box.report()
        self.assertEqual(seats["cc3"]["state"], "tight")   # 85%, ungraded payload
        self.assertIn("local threshold", seats["cc3"]["state_basis"])

    def test_overage_terms_are_reported(self):
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["overage"]["extra_usage_enabled"], False)
        self.assertEqual(seats["cc"]["overage"]["can_purchase_credits"], False)

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
        # Qwen sits at 5% of its allowance, so it outranks cc's 55% even after
        # the estimate is docked its own ±10.7% calibration spread.
        result = self.box.run("--pick")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "pi-qwencloud")

    def test_an_estimate_is_ranked_at_the_conservative_end_of_its_error_bar(self):
        # Qwen at 50% leaves 50 points, docked to 39.3 by the spread, so cc's
        # measured 55 wins — a calibrated guess must not beat a measurement on
        # a margin thinner than the calibration's own uncertainty.
        self.box.qwen(
            messages=[(self.qwen_opened, 962_500, 0, 0, "qwen-token-plan")],
            refusals=[(self.qwen_reset - timedelta(days=2), self.qwen_reset)])
        _, seats = self.box.report()
        self.assertEqual(seats["pi-qwencloud"]["windows"][0]["used_pct"], 50.0)
        self.assertEqual(self.box.run("--pick").stdout.strip(), "cc")

    def test_pick_fails_when_nothing_is_open(self):
        for seat, config in (("cc", ".claude"), ("cc2", ".claude-work"), ("cc3", ".claude-3")):
            self.box.claude(seat, config, 99.0, 99.0)
        self.box.qwen(
            messages=[(NOW - timedelta(hours=2), 10, 10, 0, "qwen-token-plan")],
            refusals=[(NOW - timedelta(hours=1), NOW + timedelta(days=3))])
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


class CodexLivePayloadTest(unittest.TestCase):
    """The live account payload, parsed directly.

    The RPC itself cannot run in a hermetic test — it would spawn Codex against
    a real account — so the parsing is exercised against a captured payload of
    the real shape. This is the DEFAULT path now, so it needs cover.
    """

    def setUp(self):
        spec = importlib.util.spec_from_loader(
            "seats_mod", importlib.machinery.SourceFileLoader("seats_mod", SCRIPT))
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        self.payload = {
            "rateLimits": {"limitId": "codex", "limitName": None,
                           "primary": {"usedPercent": 12, "windowDurationMins": 10080,
                                       "resetsAt": int((NOW + timedelta(days=6)).timestamp())},
                           "secondary": None,
                           "credits": {"hasCredits": False, "unlimited": False, "balance": "0"},
                           "spendControlReached": False, "planType": "pro"},
            "rateLimitsByLimitId": {
                "codex": {"limitId": "codex", "limitName": None,
                          "primary": {"usedPercent": 12, "windowDurationMins": 10080,
                                      "resetsAt": int((NOW + timedelta(days=6)).timestamp())},
                          "secondary": None},
                "codex_bengalfox": {
                    "limitId": "codex_bengalfox", "limitName": "GPT-5.3-Codex-Spark",
                    "primary": {"usedPercent": 40, "windowDurationMins": 300,
                                "resetsAt": int((NOW + timedelta(hours=4)).timestamp())},
                    "secondary": {"usedPercent": 55, "windowDurationMins": 10080,
                                  "resetsAt": int((NOW + timedelta(days=6)).timestamp())}}},
            "rateLimitResetCredits": {
                "availableCount": 3,
                "credits": [
                    {"status": "available", "title": "Full reset",
                     "expiresAt": int((NOW + timedelta(days=12)).timestamp())},
                    {"status": "available", "title": "Full reset",
                     "expiresAt": int((NOW + timedelta(days=40)).timestamp())},
                    {"status": "spent", "title": "Full reset",
                     "expiresAt": int((NOW + timedelta(days=2)).timestamp())}]},
        }

    def test_account_rows_bind_and_model_rows_do_not(self):
        windows = {w["id"]: w for w in self.mod.codex_windows_from_live(self.payload)}
        self.assertTrue(windows["codex:primary"]["binding"])
        self.assertEqual(windows["codex:primary"]["used_pct"], 12.0)
        self.assertEqual(windows["codex:primary"]["minutes"], 10080)
        # A per-model cap restricts that model, exactly as a Claude scoped row.
        self.assertFalse(windows["codex_bengalfox:primary"]["binding"])
        self.assertFalse(windows["codex_bengalfox:secondary"]["binding"])
        self.assertEqual(windows["codex_bengalfox:primary"]["scope"], "GPT-5.3-Codex-Spark")
        self.assertEqual(windows["codex_bengalfox:secondary"]["used_pct"], 55.0)

    def test_a_model_row_at_55_does_not_spend_an_account_at_12(self):
        seat = self.mod.blank_seat(
            {"id": "codex", "provider": "codex", "owner": "third-party"}, "unknown", "UNKNOWN")
        seat["windows"] = self.mod.codex_windows_from_live(self.payload)
        self.mod.classify(seat)
        self.assertEqual(seat["state"], "open")
        self.assertEqual(seat["worst_pct"], 12.0)

    def test_only_available_reset_credits_are_counted(self):
        grants = self.payload["rateLimitResetCredits"]
        available = [g for g in grants["credits"] if g["status"] == "available"]
        self.assertEqual(len(available), 2)
        self.assertEqual(grants["availableCount"], 3)
        # The soonest expiry belongs to a SPENT credit; it must not be reported
        # as the next deadline.
        soonest = min(self.mod.parse_ts(g["expiresAt"]) for g in available)
        self.assertEqual(soonest.date(), (NOW + timedelta(days=12)).date())

    def test_a_payload_without_the_by_id_map_still_yields_the_account_row(self):
        payload = {"rateLimits": self.payload["rateLimits"]}
        windows = self.mod.codex_windows_from_live(payload)
        self.assertEqual([w["id"] for w in windows], ["codex:primary"])
        self.assertTrue(windows[0]["binding"])


if __name__ == "__main__":
    unittest.main()
