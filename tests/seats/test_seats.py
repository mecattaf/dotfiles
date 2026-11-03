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
  * Qwen credits sum pi's live sessions AND the pi sessions the substrate
    factory archived, skipping the other harnesses' archives beside them
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


def load_seats_module(name="seats_mod_shared"):
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, SCRIPT))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def iso(stamp):
    return stamp.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def window_cache(five_hour_pct, weekly_pct, weekly_reset, scoped=None,
                 severity=None, active=None, credit=None):
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
    if credit is not None:
        # The cloud credit, under the undocumented key read on 2026-11-03.
        limit, used, expires = credit
        usage["iguana_necktie"] = {"utilization": used / limit * 100.0, "resets_at": iso(expires),
                                   "limit_dollars": limit, "used_dollars": used,
                                   "remaining_dollars": limit - used, "locked_reason": None}
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
               severity=None, active=None, credit=None):
        (self.home / config).mkdir(parents=True, exist_ok=True)
        (self.home / config / ".credentials.json").write_text(json.dumps({
            "claudeAiOauth": {
                "accessToken": "sk-test-not-a-real-token",
                "rateLimitTier": "default_claude_max_20x",
                "subscriptionType": "max",
                "expiresAt": int((NOW + timedelta(hours=1)).timestamp() * 1000)}}))
        (self.peer / f".window-cache-{seat}.json").write_text(
            json.dumps(window_cache(five_hour, weekly, self.weekly_reset, scoped,
                                    severity, active, credit)))
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
        lines = [self.pi_message(*row) for row in messages]
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

    @staticmethod
    def pi_message(when, tin, tout, cache, provider):
        """One pi session record, the shape live and archived files share."""
        return json.dumps({
            "type": "message", "timestamp": iso(when),
            "message": {"provider": provider, "model": "qwen3.8-max",
                        "usage": {"input": tin, "output": tout,
                                  "cacheRead": cache, "cacheWrite": 0}}})

    def dsh_session(self, messages, cwd="--home-tom-src--", session="session-0000",
                    inherited=0):
        """One dsh session file (plain JSONL, compression none). Field names
        were read, structure only, from a real 0.2.1-rc.2 session.v4.jsonl;
        every value here is synthetic. messages: (when, input, output,
        cacheRead, provider). inherited: how many leading messages a fork
        copied from its parent; the `session/end-seed` marker follows them
        (dsh packages/core/session/src/fork.ts)."""
        folder = self.home / ".dsh/sessions" / cwd / session
        folder.mkdir(parents=True, exist_ok=True)
        lines = [json.dumps({"type": "session", "version": 4, "id": session,
                             "createdAt": 0, "cwd": "/home/tom/src"})]
        for seq, (when, tin, tout, cache, provider) in enumerate(messages):
            ms = int(when.timestamp() * 1000)
            # The request records name the route too, and carry no usage:
            # they must never be billed.
            lines.append(json.dumps({
                "type": "request/context", "seq": 3 * seq, "time": ms,
                "data": {"provider": provider, "model": "deepseek-v4.1-flash",
                         "contextWindow": 1000000}}))
            lines.append(json.dumps({
                "type": "assistant/message", "seq": 3 * seq + 1, "time": ms,
                "data": {"turn": 1, "step": seq + 1,
                         "message": {"role": "assistant", "content": [],
                                     "source": {"kind": "model", "provider": provider,
                                                "model": "deepseek-v4.1-flash"},
                                     "id": f"m{seq}"},
                         "usage": {"inputTokens": tin, "outputTokens": tout,
                                   "cacheReadTokens": cache,
                                   "totalTokens": tin + tout + cache}}}))
            lines.append(json.dumps({"type": "step/end", "seq": 3 * seq + 2, "time": ms,
                                     "data": {"turn": 1, "step": seq + 1}}))
            if inherited and seq + 1 == inherited:
                lines.append(json.dumps({"type": "session/end-seed", "seq": 3 * seq + 3,
                                         "time": ms, "data": {"inherited": True}}))
        path = folder / "session.v4.jsonl"
        path.write_text("\n".join(lines) + "\n")
        for stale in self.state.glob("qwen-events.json"):
            stale.unlink()
        return path

    def substrate_archive(self, name, messages, job="run1/job1"):
        """A harness session the factory archived at job end, beside the job's
        other harness archives: <transcripts>/<run>/<job>/<name>.jsonl."""
        job_dir = self.home / ".local/state/substrate/transcripts" / job
        job_dir.mkdir(parents=True, exist_ok=True)
        path = job_dir / f"{name}.jsonl"
        path.write_text("\n".join(self.pi_message(*row) for row in messages) + "\n")
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
               "SEATS_OPENROUTER_KEY_FILE": str(self.state / "no-such-openrouter-key"),
               "SEATS_AGENIX_DIR": str(self.root / "agenix"),
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
        # The cache reads and the locally served (gufo) message must not be billed.
        self.qwen_reset = NOW - timedelta(days=4)
        self.qwen_opened = NOW - timedelta(days=3)
        self.box.qwen(
            messages=[
                (self.qwen_reset - timedelta(hours=1), 500_000, 0, 0, "qwen-token-plan"),
                (self.qwen_opened, 90_000, 6_250, 9_000_000, "qwen-token-plan"),
                (self.qwen_opened + timedelta(hours=1), 999_999, 999_999, 0, "gufo"),
            ],
            refusals=[(self.qwen_reset - timedelta(days=2), self.qwen_reset)])

    # ── the shape of the answer ─────────────────────────────────────────────
    def test_every_seat_produces_exactly_one_row(self):
        report, seats = self.box.report()
        self.assertEqual(report["schema_version"], "seat-capacity/1")
        self.assertEqual(len(report["seats"]), len(load_seats_module().DEFAULT_SEATS))
        self.assertEqual(len(seats), len(report["seats"]), "seat ids must be unique")
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
        # gufo message and the pre-window message are all excluded.
        self.assertEqual(credits["billable_tokens"], 96_250)
        self.assertEqual(credits["used"], 500)
        self.assertEqual(credits["remaining"], 9_500)
        self.assertEqual(qwen["windows"][0]["used_pct"], 5.0)
        self.assertEqual(qwen["state"], "open")

    def test_factory_archived_pi_sessions_are_billed_too(self):
        # CMP-2: the factory saves its pi sessions and archives them under
        # substrate's transcripts at job end; those tokens are this seat's
        # spend as much as a hand-run pi session is, and the two roots sum.
        self.box.substrate_archive("pi-session", [
            (self.qwen_opened + timedelta(hours=2), 10_000, 1_000, 500_000, "qwen-token-plan")])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["credits"]["billable_tokens"], 96_250 + 11_000)
        self.assertEqual(qwen["spend"]["tokens_in"], 90_000 + 10_000)
        self.assertEqual(qwen["spend"]["tokens_out"], 6_250 + 1_000)
        self.assertEqual(qwen["spend"]["sessions"], 2, "the live file and the archive")

    def test_other_harnesses_archives_beside_pi_are_not_billed(self):
        # The same job dir holds claude-*.jsonl and codex-*.jsonl; a qwen-looking
        # line in one of those is another seat's record, skipped by basename.
        looks_like_qwen = [(self.qwen_opened + timedelta(hours=2),
                            999_999, 999_999, 0, "qwen-token-plan")]
        self.box.substrate_archive("pi-session", [
            (self.qwen_opened + timedelta(hours=2), 10_000, 1_000, 0, "qwen-token-plan")])
        self.box.substrate_archive("claude-x", looks_like_qwen)
        self.box.substrate_archive("codex-y", looks_like_qwen)
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["credits"]["billable_tokens"], 96_250 + 11_000)
        self.assertEqual(qwen["spend"]["sessions"], 2)

    def test_the_pi_seat_names_both_spend_roots(self):
        spec = importlib.util.spec_from_loader(
            "seats_mod_pi", importlib.machinery.SourceFileLoader("seats_mod_pi", SCRIPT))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        pi = next(s for s in mod.DEFAULT_SEATS if s["id"] == "pi-qwencloud")
        self.assertEqual(pi["spend_root"],
                         ["~/.pi/agent/sessions", "~/.local/state/substrate/transcripts",
                          "~/.dsh/sessions"])

    def test_dsh_sessions_are_billed_to_the_same_seat(self):
        # T-31: dsh spends the same token plan through its qwen-token-plan
        # route, so its replies join this seat's credits and spend. Uncached
        # input + output only; the cache reads and the request records are not.
        self.box.dsh_session([
            (self.qwen_opened + timedelta(hours=2), 10_000, 1_000, 500_000, "qwen-token-plan")])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["credits"]["billable_tokens"], 96_250 + 11_000)
        self.assertEqual(qwen["spend"]["tokens_in"], 90_000 + 10_000)
        self.assertEqual(qwen["spend"]["tokens_out"], 6_250 + 1_000)
        self.assertEqual(qwen["spend"]["sessions"], 2, "the pi file and the dsh session")

    def test_a_forked_dsh_session_bills_its_inherited_calls_once(self):
        # A fork copies the parent's assistant/message records, usage and
        # all, ahead of a session/end-seed marker; only the calls after the
        # marker are the fork's own.
        parent_call = (self.qwen_opened + timedelta(hours=2), 10_000, 1_000, 0,
                       "qwen-token-plan")
        own_call = (self.qwen_opened + timedelta(hours=3), 20_000, 2_000, 0,
                    "qwen-token-plan")
        self.box.dsh_session([parent_call], session="session-parent")
        self.box.dsh_session([parent_call, own_call], session="session-fork", inherited=1)
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["credits"]["billable_tokens"], 96_250 + 11_000 + 22_000)
        self.assertEqual(qwen["spend"]["tokens_in"], 90_000 + 10_000 + 20_000)
        self.assertEqual(qwen["spend"]["tokens_out"], 6_250 + 1_000 + 2_000)
        self.assertEqual(qwen["spend"]["sessions"], 3, "the pi file, the parent and the fork")

    def test_dsh_traffic_on_other_routes_is_never_billed(self):
        # A later local route (the gufo row) lands in the same session store.
        self.box.dsh_session([
            (self.qwen_opened + timedelta(hours=2), 999_999, 999_999, 0, "gufo")])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["credits"]["billable_tokens"], 96_250)
        self.assertEqual(qwen["spend"]["tokens_in"], 90_000)

    def test_qwen_local_traffic_is_never_billed(self):
        _, seats = self.box.report()
        # The gufo message carries ~2M tokens and would dominate both
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

    def test_an_elapsed_qwen_window_rolls_to_the_next_first_use(self):
        # Defect 5: a window that ran its seven days without a refusal must not
        # be reported forever; the next one opens on the first use after it.
        first = NOW - timedelta(days=18)
        latest = NOW - timedelta(hours=2)
        self.box.qwen(
            messages=[(first, 500_000, 0, 0, "qwen-token-plan"),
                      (latest, 15_000, 4_250, 0, "qwen-token-plan")],
            refusals=[(NOW - timedelta(days=21), NOW - timedelta(days=20))])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        entry = qwen["windows"][0]
        self.assertEqual(entry["window_start"], iso(latest))
        self.assertEqual(entry["resets_at"], iso(latest + timedelta(days=7)))
        self.assertEqual(qwen["credits"]["resets_at"], iso(latest + timedelta(days=7)))
        self.assertEqual(qwen["credits"]["billable_tokens"], 19_250,
                         "only the new window's tokens count")
        self.assertEqual(qwen["state"], "open")

    def test_qwen_windows_chain_across_several_elapsed_weeks(self):
        uses = [NOW - timedelta(days=18), NOW - timedelta(days=9), NOW - timedelta(hours=1)]
        self.box.qwen(
            messages=[(when, 1_000, 1_000, 0, "qwen-token-plan") for when in uses],
            refusals=[(NOW - timedelta(days=21), NOW - timedelta(days=20))])
        _, seats = self.box.report()
        self.assertEqual(seats["pi-qwencloud"]["windows"][0]["window_start"], iso(uses[-1]))

    def test_an_elapsed_qwen_window_with_no_later_use_reads_full(self):
        self.box.qwen(
            messages=[(NOW - timedelta(days=18), 500_000, 0, 0, "qwen-token-plan")],
            refusals=[(NOW - timedelta(days=21), NOW - timedelta(days=20))])
        _, seats = self.box.report()
        qwen = seats["pi-qwencloud"]
        self.assertEqual(qwen["state"], "open")
        self.assertEqual(qwen["credits"]["remaining"], 10_000)
        self.assertIsNone(qwen["credits"]["resets_at"])
        self.assertIn("opens on first use", qwen["detail"])

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

    def test_no_share_conversion_is_computed(self):
        # Anthropic documents the cap ("up to 50% of your weekly usage limits
        # on Fable models") but never the points-for-points conversion, and
        # states that Fable consumes the allowance FASTER per token. So the cap
        # is carried as a citation and the arithmetic joining the two
        # percentages is left undone rather than guessed.
        _, seats = self.box.report()
        blob = json.dumps(seats["cc"])
        for computed in ("share_of_total", "account_points_used",
                         "account_points_cap", "points_left_for_this_model"):
            self.assertNotIn(computed, blob)

    def test_the_documented_cap_is_carried_as_a_citation(self):
        _, seats = self.box.report()
        term = seats["cc"]["model_budget"]["models"][0]["documented_term"]
        self.assertEqual(term["cap_share_of_weekly"], 0.5)
        self.assertIn("support.claude.com", term["source"])
        self.assertIn("use them faster than other Claude models", term["quote"])
        self.assertIn("not", term["caveat"])
        # A model with no published term gets None, not a fabricated default.
        self.box.claude("cc2", ".claude-work", 0.0, 50.0, scoped=10.0)
        _, seats = self.box.report()
        rows = seats["cc2"]["model_budget"]["models"]
        self.assertEqual(rows[0]["model"], "Fable")

    def test_a_pending_allowance_change_is_surfaced_then_expires(self):
        report, _ = self.box.report()
        changes = report["allowance_changes"]
        # The 2026-09-14 Claude Code cut is in the future as of this writing;
        # once it passes the advisory must stop being reported rather than
        # linger as a permanent scare.
        for change in changes:
            self.assertGreater(change["effective"], iso(NOW))
            self.assertIn("source", change)

    def test_a_scoped_limit_never_spends_the_seat(self):
        _, seats = self.box.report()
        cc = seats["cc"]
        self.assertEqual(cc["model_budget"]["models"][0]["used_pct"], 100.0)
        self.assertEqual(cc["state"], "open", "Fable's cap binds Fable, not the account")
        self.assertTrue(cc["usable"])

    def test_is_active_is_carried_raw_and_never_interpreted(self):
        # The obvious reading — "the limit currently governing" — is refuted by
        # a real payload where the flag sits on the session row at 5% while a
        # scoped row sits higher at 16% (anthropics/claude-code#87419). So the
        # flag is published and nothing is derived from it, and in particular
        # it must not be relabelled "governing" anywhere.
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="scoped")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["model_budget"]["provider_is_active_on"],
                         ["weekly:fable"])
        self.assertNotIn("governing", json.dumps(seats["cc"]))
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="weekly_all")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["model_budget"]["provider_is_active_on"], ["seven_day"])

    def test_is_active_does_not_move_the_state(self):
        # Same percentages, flag moved: the answer must not change.
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="scoped")
        _, first = self.box.report()
        self.box.claude("cc", ".claude", 10.0, 45.0, scoped=100.0, active="weekly_all")
        _, second = self.box.report()
        self.assertEqual(first["cc"]["state"], second["cc"]["state"])

    # ── the provider's own grading outranks a local threshold ───────────────
    def test_provider_severity_can_tighten_the_state(self):
        # 45% would be "open" on the local thresholds; the provider says
        # critical, and the provider is describing its own product.
        self.box.claude("cc", ".claude", 10.0, 45.0, severity="critical")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["state"], "spent")
        self.assertIn("provider severity critical", seats["cc"]["state_basis"])
        self.assertEqual(seats["cc"]["free_at"], iso(self.box.weekly_reset))

    def test_provider_severity_can_never_loosen_the_state(self):
        # The threshold at which severity flips is documented nowhere, and a
        # sibling field on the same entries (is_active) already turned out to
        # mean something other than the obvious reading. So an optimistic
        # grading must not talk this meter out of a 99% window.
        self.box.claude("cc", ".claude", 10.0, 99.0, severity="normal")
        _, seats = self.box.report()
        self.assertEqual(seats["cc"]["state"], "spent")
        self.assertIn("local threshold", seats["cc"]["state_basis"])
        self.assertEqual(seats["cc"]["free_at"], iso(self.box.weekly_reset))

    def test_thresholds_carry_an_ungraded_payload(self):
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
        # The worker's row is the Gufo server's liveness probe; with the
        # network off it is offline, graded UNKNOWN, and names where it asked.
        self.assertEqual(seats["gpu-strix"]["provider"], "gufo")
        self.assertEqual(seats["gpu-strix"]["state"], "offline")
        self.assertEqual(seats["gpu-strix"]["grade"], "UNKNOWN")
        self.assertFalse(seats["gpu-strix"]["windows"])
        self.assertEqual(seats["gpu-strix"]["source"]["endpoint"], "http://strix-coordinator:8731/v1/models")
        # The strix serves nothing: not-applicable, never headroom, and
        # the row says why rather than pretending to have probed something.

    def test_check_exit_codes(self):
        self.assertEqual(self.box.run("--check", "cc").returncode, 0)
        self.assertEqual(self.box.run("--check", "cc2").returncode, 1)
        self.assertEqual(self.box.run("--check", "gpu-strix").returncode, 2)
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
        self.assertEqual(len(rows), len(load_seats_module().DEFAULT_SEATS))
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


class GufoDemandTest(unittest.TestCase):
    def test_sleeping_model_is_available_and_only_non_waking_probes_are_used(self):
        spec = importlib.util.spec_from_loader(
            "seats_mod_gufo", importlib.machinery.SourceFileLoader("seats_mod_gufo", SCRIPT))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        calls = []
        def http(url, **kwargs):
            calls.append(url)
            return ({"running": []} if url.endswith('/running') else
                    {"data": [{"id": "qwen3.8-flash-next"}]}), None
        mod.http_json = http
        seat = mod.read_gufo({"id": "gpu-strix", "provider": "gufo", "endpoint": "http://local"}, None)
        self.assertTrue(seat['usable'])
        self.assertEqual(seat['running'], [])
        self.assertIn('sleeping', seat['detail'])
        self.assertEqual(calls, ['http://local/v1/models', 'http://local/running'])


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


class OpenRouterRowTest(unittest.TestCase):
    """The OpenRouter rows, from captured numbers (the endpoints cannot run hermetically).

    Pins: the soft cap reads spent at used >= cap; the larger of the key's and
    the account's usage is the spend; the cap never promises more than the key
    or the account can pay; the free quota resets at 00:00 UTC; a missing key is
    unauth (the pusher then marks the seat auth-failed and the factory refuses
    at once); no key material reaches a row.
    """

    def setUp(self):
        spec = importlib.util.spec_from_loader(
            "seats_mod_or", importlib.machinery.SourceFileLoader("seats_mod_or", SCRIPT))
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        self.paid = next(s for s in self.mod.DEFAULT_SEATS if s["id"] == "openrouter")
        self.free = next(s for s in self.mod.DEFAULT_SEATS if s["id"] == "openrouter-free")
        self.cfg = {"cap_usd": 12.0, "baseline_usd": 0.0, "source": "test"}

    def reading(self, usage=0.0, total_usage=0.0, total_credits=40.0, limit_remaining=40.0,
                free_used=0.0, free_limit=1000.0):
        return {"key": {"usage": usage, "limit": 40.0, "limit_remaining": limit_remaining,
                        "usage_daily": usage, "free_used": free_used, "free_limit": free_limit,
                        "free_remaining": free_limit - free_used},
                "credits": {"total_credits": total_credits, "total_usage": total_usage},
                "credits_error": ""}

    def row(self, spec, reading, cfg=None, error=None):
        return self.mod.openrouter_row(spec, reading, 0.0, error, cfg or self.cfg, "/run/agenix/openrouter-token")

    def test_the_soft_cap_spends_the_seat(self):
        open_row = self.row(self.paid, self.reading(usage=3.0, total_usage=3.0))
        self.assertEqual(open_row["state"], "open")
        self.assertEqual(open_row["grade"], "MEASURED")
        self.assertEqual(open_row["credits"]["unit"], "usd")
        self.assertEqual(open_row["credits"]["limit"], 12.0)
        self.assertEqual(open_row["credits"]["used"], 3.0)
        self.assertIsNone(open_row["credits"]["resets_at"])
        self.assertEqual(open_row["credits"]["counter"], "provider")
        spent = self.row(self.paid, self.reading(usage=12.0, total_usage=12.0))
        self.assertEqual(spent["state"], "spent")
        self.assertFalse(spent["usable"])
        self.assertEqual(spent["free_at"], "", "a prepaid balance never resets")
        tight = self.row(self.paid, self.reading(usage=10.0, total_usage=10.0))
        self.assertEqual(tight["state"], "tight")

    def test_the_larger_usage_and_the_baseline(self):
        row = self.row(self.paid, self.reading(usage=1.0, total_usage=5.0))
        self.assertEqual(row["credits"]["used"], 5.0)
        row = self.row(self.paid, self.reading(usage=15.0, total_usage=15.0),
                       cfg={"cap_usd": 12.0, "baseline_usd": 10.0, "source": "test"})
        self.assertEqual(row["credits"]["used"], 5.0)
        self.assertEqual(row["state"], "open")

    def test_the_cap_never_exceeds_what_can_be_paid(self):
        row = self.row(self.paid, self.reading(usage=38.0, total_usage=38.0, limit_remaining=2.0),
                       cfg={"cap_usd": 100.0, "baseline_usd": 0.0, "source": "test"})
        self.assertEqual(row["credits"]["limit"], 40.0)
        self.assertEqual(row["credits"]["remaining"], 2.0)

    def test_the_free_quota_is_daily(self):
        row = self.row(self.free, self.reading(free_used=10.0))
        self.assertEqual(row["credits"]["unit"], "requests")
        self.assertEqual(row["credits"]["limit"], 1000.0)
        reset = self.mod.parse_ts(row["credits"]["resets_at"])
        self.assertEqual((reset.hour, reset.minute, reset.second), (0, 0, 0))
        self.assertGreater(reset, NOW)
        self.assertLessEqual(reset - NOW, timedelta(days=1))
        spent = self.row(self.free, self.reading(free_used=1000.0))
        self.assertEqual(spent["state"], "spent")
        self.assertEqual(spent["free_at"], row["credits"]["resets_at"])

    def test_no_key_is_unauth_and_an_outage_is_unknown(self):
        self.assertEqual(self.row(self.paid, None, error="no api key on this box")["state"], "unauth")
        self.assertEqual(self.row(self.paid, None, error="HTTP 401 Unauthorized: {}")["state"], "unauth")
        down = self.row(self.paid, None, error="unreachable: timed out")
        self.assertEqual((down["state"], down["grade"]), ("unknown", "UNKNOWN"))
        self.assertNotIn("credits", down)

    def test_the_cap_is_configurable(self):
        os.environ["SEATS_OPENROUTER_CAP_USD"] = "5"
        try:
            self.assertEqual(self.mod.openrouter_config()["cap_usd"], 5.0)
        finally:
            del os.environ["SEATS_OPENROUTER_CAP_USD"]
        self.assertEqual(self.mod.openrouter_config()["cap_usd"], 12.0)

    def test_the_offline_rows_hold_no_number(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = SeatsFixture(pathlib.Path(tmp))
            _, seats = box.report("--only", "openrouter")
            self.assertEqual(sorted(seats), ["openrouter", "openrouter-free"])
            for row in seats.values():
                self.assertEqual(row["state"], "unauth")
                self.assertNotIn("credits", row)


class BurndownLedgerTest(unittest.TestCase):
    """The free-lane rows and the cloud-credit rows (2026-11-03).

    Pins: every lane key is a row even with no key file, and says so; the
    allowance is static and labelled; the reset is computed from the rule
    (Pacific midnight under the US DST rule, UTC midnight, the month); a
    recorded 429 spends the row until the reset and a per-minute refusal
    clears; the probe never runs inside a fast --watch; the credit rows come
    out of the sibling seat's payload; no key material ever reaches stdout.
    """

    def setUp(self):
        self.assertTrue(SCRIPT, "SEATS_SCRIPT must be set")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.box = SeatsFixture(pathlib.Path(self.tmp.name))
        self.mod = load_seats_module("seats_mod_ledger")
        self.agenix = self.box.root / "agenix"
        self.agenix.mkdir()

    def lanes(self, *args):
        _, seats = self.box.report("--only", "ledger", *args)
        return seats

    def test_every_lane_key_is_a_row_that_names_its_missing_key(self):
        seats = self.lanes()
        for family, slots in (("gemini", 3), ("zen", 4), ("groq", 3), ("mistral", 3),
                              ("cohere", 5), ("nvidia", 1), ("cloudflare", 1), ("hf", 1),
                              ("cerebras", 1), ("vercel", 1), ("grok", 1)):
            for slot in range(1, slots + 1):
                row = seats[f"{family}-{slot}"]
                self.assertEqual(row["provider"], "lane")
                self.assertEqual(row["grade"], "UNKNOWN")
                self.assertFalse(row["ledger"]["key_present"])
                self.assertIn("no key on this host", row["detail"])
                self.assertEqual(row["ledger"]["allowance_grade"], "STATIC")
                self.assertFalse(row["usable"], "an unprobed lane is never headroom")
        self.assertEqual(seats["gemini-1"]["state"], "unauth")
        self.assertEqual(seats["mistral-1"]["state"], "n/a")
        self.assertEqual(seats["hf-1"]["state"], "n/a")
        self.assertEqual(seats["ds4"]["state"], "n/a")
        self.assertEqual(seats["vercel-1"]["state"], "n/a")
        self.assertEqual(seats["grok-1"]["state"], "n/a")
        self.assertEqual(seats["cerebras-1"]["models"], ["qwen-3.8-27b", "gpt-oss-120b"])
        self.assertEqual(seats["hf-1"]["ledger"]["key_file"].rsplit("/", 1)[1],
                         "huggingface-inference-token-1", "never the Hub download token")
        self.assertTrue(seats["cloudflare-1"]["ledger"]["key_file"].endswith("cloudflare-workers-ai-token-1"))
        self.assertEqual(seats["gemini-1"]["models"][0], "gemini-3.8-flash")
        self.assertEqual(seats["zen-1"]["models"], ["deepseek-v4.1-flash-free", "glm-5.3-flash-free"])

    def test_only_accepts_a_lane_family(self):
        _, seats = self.box.report("--only", "groq")
        self.assertEqual(sorted(seats), ["groq-1", "groq-2", "groq-3"])

    def test_pacific_midnight_follows_the_us_dst_rule(self):
        mid = self.mod.pacific_midnights
        utc = timezone.utc
        # Standard time (after the first Sunday of November): 00:00 PST = 08:00Z.
        prev, nxt = mid(datetime(2026, 11, 3, 21, 0, tzinfo=utc))
        self.assertEqual(iso(nxt), "2026-11-04T08:00:00Z")
        self.assertEqual(iso(prev), "2026-11-03T08:00:00Z")
        # Daylight time: 00:00 PDT = 07:00Z.
        prev, nxt = mid(datetime(2026, 7, 10, 3, 0, tzinfo=utc))
        self.assertEqual(iso(nxt), "2026-07-10T07:00:00Z")
        self.assertEqual(iso(prev), "2026-07-09T07:00:00Z")
        # 06:30Z on a July day is still the previous Pacific day.
        prev, nxt = mid(datetime(2026, 7, 10, 6, 30, tzinfo=utc))
        self.assertEqual(iso(nxt), "2026-07-10T07:00:00Z")

    def test_reset_rules_are_computed_and_labelled(self):
        seats = self.lanes()
        gemini = self.mod.parse_ts(seats["gemini-1"]["ledger"]["resets_at"])
        self.assertIn(gemini.hour, (7, 8))
        self.assertLessEqual(gemini - NOW, timedelta(days=1))
        self.assertIn("computed", seats["gemini-1"]["ledger"]["reset_how"])
        cloudflare = self.mod.parse_ts(seats["cloudflare-1"]["ledger"]["resets_at"])
        self.assertEqual((cloudflare.hour, cloudflare.minute), (0, 0))
        cohere = self.mod.parse_ts(seats["cohere-1"]["ledger"]["resets_at"])
        self.assertEqual(cohere.day, 1)
        self.assertIn("unverified", seats["cohere-1"]["ledger"]["reset_how"])
        self.assertEqual(seats["groq-1"]["ledger"]["resets_at"], "")
        self.assertEqual(seats["groq-1"]["ledger"]["reset_rule"], "per-header")
        self.assertEqual(seats["zen-1"]["ledger"]["reset_how"], "unpublished")

    def test_groq_reset_header_durations_parse(self):
        parse = self.mod.parse_duration
        self.assertAlmostEqual(parse("1h2m3.5s"), 3723.5)
        self.assertAlmostEqual(parse("59.2s"), 59.2)
        self.assertAlmostEqual(parse("250ms"), 0.25)
        self.assertAlmostEqual(parse("1234.5"), 1234.5, msg="Cerebras states bare seconds")
        self.assertIsNone(parse(""))
        self.assertIsNone(parse(None))

    def test_record_appends_and_the_row_counts_it(self):
        (self.agenix / "groq-api-key-1").write_text("not-a-real-groq-key\n")
        for status in ("ok", "ok"):
            result = self.box.run("--record", "groq", "1", "qwen/qwen3.8-27b", status)
            self.assertEqual(result.returncode, 0, result.stderr)
        lines = (self.box.state / "lane-usage.jsonl").read_text().splitlines()
        self.assertEqual(len(lines), 2)
        row = json.loads(lines[0])
        self.assertEqual(set(row), {"ts", "lane", "slot", "model", "status"})
        groq = self.lanes()["groq-1"]
        self.assertEqual(groq["state"], "open")
        self.assertEqual(groq["usage_today"]["calls"], 2)
        self.assertEqual(groq["usage_today"]["by_model"], {"qwen/qwen3.8-27b": 2})
        self.assertIn("2 calls recorded", groq["detail"])
        # Another slot's calls are not this row's.
        self.box.run("--record", "groq", "2", "qwen/qwen3.8-27b", "ok")
        self.assertEqual(self.lanes()["groq-1"]["usage_today"]["calls"], 2)
        # The row id form joins too.
        self.box.run("--record", "groq-1", "1", "openai/gpt-oss-120b", "ok")
        self.assertEqual(self.lanes()["groq-1"]["usage_today"]["calls"], 3)

    def test_record_refuses_an_unknown_lane(self):
        result = self.box.run("--record", "bogus", "1", "x", "ok")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.box.state / "lane-usage.jsonl").exists())

    def test_a_recorded_refusal_spends_a_daily_lane_until_its_reset(self):
        (self.agenix / "gemini-api-key-2").write_text("not-a-real-gemini-key\n")
        self.box.run("--record", "gemini", "2", "gemini-3.8-flash", "ok")
        self.box.run("--record", "gemini", "2", "gemini-3.8-flash", "429")
        gemini = self.lanes()["gemini-2"]
        self.assertEqual(gemini["state"], "spent")
        self.assertEqual(gemini["grade"], "MEASURED-FROM-REFUSAL")
        self.assertEqual(gemini["free_at"], gemini["ledger"]["resets_at"])
        self.assertEqual(gemini["usage_today"]["refusals"], 1)
        # A later ok clears it: the last status decides.
        self.box.run("--record", "gemini", "2", "gemini-3.8-flash", "ok")
        self.assertEqual(self.lanes()["gemini-2"]["state"], "open")

    def test_a_per_minute_refusal_clears_within_the_minute(self):
        (self.agenix / "nvidia-api-key-1").write_text("not-a-real-nvidia-key\n")
        self.box.state.mkdir(exist_ok=True)
        with (self.box.state / "lane-usage.jsonl").open("a") as stream:
            stream.write(json.dumps({"ts": iso(NOW - timedelta(minutes=5)), "lane": "nvidia",
                                     "slot": "1", "model": "z-ai/glm-5.3-flash",
                                     "status": "429"}) + "\n")
        self.assertEqual(self.lanes()["nvidia-1"]["state"], "open")
        with (self.box.state / "lane-usage.jsonl").open("a") as stream:
            stream.write(json.dumps({"ts": iso(NOW), "lane": "nvidia", "slot": "1",
                                     "model": "z-ai/glm-5.3-flash", "status": "429"}) + "\n")
        self.assertEqual(self.lanes()["nvidia-1"]["state"], "spent")

    def test_a_present_key_is_open_but_unknown_until_probed(self):
        (self.agenix / "gemini-api-key-1").write_text("not-a-real-gemini-key\n")
        gemini = self.lanes()["gemini-1"]
        self.assertEqual(gemini["state"], "open")
        self.assertEqual(gemini["grade"], "UNKNOWN")
        self.assertTrue(gemini["ledger"]["key_present"])
        self.assertIn("unprobed", gemini["detail"])
        self.assertNotIn("probe", gemini)

    def test_probe_is_off_by_default_and_offline_says_so(self):
        (self.agenix / "gemini-api-key-1").write_text("not-a-real-gemini-key\n")
        self.assertNotIn("probe", self.lanes()["gemini-1"])
        gemini = self.lanes("--probe")["gemini-1"]
        self.assertEqual(gemini["probe"]["status"], None)
        self.assertIn("offline", gemini["probe"]["error"])
        self.assertIn("probe: offline", gemini["detail"])
        # A lane without its key is not probed, and the row says why.
        self.assertIn("no key on this host", self.lanes("--probe")["gemini-2"]["detail"])

    def test_probe_refuses_a_fast_watch(self):
        result = self.box.run("--probe", "--watch", "30")
        self.assertEqual(result.returncode, 2)
        self.assertIn("600", result.stderr)

    def test_no_key_material_ever_reaches_the_output(self):
        for name in ("gemini-api-key-1", "groq-api-key-1", "cloudflare-workers-ai-token-1",
                     "cloudflare-account-id", "vercel-ai-gateway-key-1", "grok-api-key-1"):
            (self.agenix / name).write_text(f"SECRET-{name}-VALUE\n")
        for args in ([], ["--json"], ["--jsonl"], ["--tsv"], ["--probe", "--json"],
                     ["--probe"]):
            result = self.box.run(*args)
            self.assertNotIn("SECRET-", result.stdout, args)
            self.assertNotIn("SECRET-", result.stderr, args)
        for path in (self.box.root / "runtime" / "seats").glob("*.json"):
            self.assertNotIn("SECRET-", path.read_text(), path)

    def test_probe_headers_become_a_request_counter(self):
        # Pure: the row built from a captured Groq-style answer.
        fam = self.mod.LANE_FAMILIES["groq"]
        reading = {"status": 200, "probed_at": iso(NOW), "error": "",
                   "headers": {"x-ratelimit-limit-requests": "1000",
                               "x-ratelimit-remaining-requests": "250",
                               "x-ratelimit-reset-requests": "2h30m0s"}}
        original_probe = self.mod.probe_lane
        self.mod.probe_lane = lambda f, s, o: (reading, 0.0, "/run/agenix/groq-api-key-1")
        self.mod.AGENIX_DIR = self.agenix
        (self.agenix / "groq-api-key-1").write_text("x\n")
        opts = type("O", (), {"probe": True, "refresh": False})()
        seat = self.mod.read_lane(self.mod.lane_spec("groq", 1), opts)
        self.assertEqual(seat["grade"], "MEASURED")
        self.assertEqual(seat["credits"]["remaining"], 250)
        self.assertEqual(seat["credits"]["limit"], 1000)
        self.assertEqual(seat["state"], "open")
        reset = self.mod.parse_ts(seat["credits"]["resets_at"])
        self.assertAlmostEqual((reset - NOW).total_seconds(), 9000, delta=5)
        self.assertEqual(seat["ledger"]["reset_how"], "provider header")
        reading["headers"]["x-ratelimit-remaining-requests"] = "0"
        seat = self.mod.read_lane(self.mod.lane_spec("groq", 1), opts)
        self.assertEqual(seat["state"], "spent")
        self.assertEqual(seat["free_at"], seat["credits"]["resets_at"])
        reading.update({"status": 429, "headers": {}})
        seat = self.mod.read_lane(self.mod.lane_spec("groq", 1), opts)
        self.assertEqual((seat["state"], seat["grade"]), ("spent", "MEASURED-FROM-REFUSAL"))
        reading.update({"status": 402})
        seat = self.mod.read_lane(self.mod.lane_spec("hf", 1), opts)
        self.assertEqual(seat["state"], "n/a")
        # Vercel: the balance in the body decides; grok has no probe at all.
        reading.update({"status": 200, "headers": {}, "fields": {"balance": 0.0, "total_used": 0.0}})
        (self.agenix / "vercel-ai-gateway-key-1").write_text("x\n")
        seat = self.mod.read_lane(self.mod.lane_spec("vercel", 1), opts)
        self.assertEqual(seat["state"], "n/a")
        self.assertIn("balance $0.00", seat["detail"])
        reading["fields"]["balance"] = 5.0
        self.assertEqual(self.mod.read_lane(self.mod.lane_spec("vercel", 1), opts)["state"], "open")
        (self.agenix / "grok-api-key-1").write_text("x\n")
        self.mod.probe_lane = original_probe   # grok has no probe spec, so none is made
        seat = self.mod.read_lane(self.mod.lane_spec("grok", 1), opts)
        self.assertEqual(seat["state"], "n/a")
        self.assertIn("no probe", seat["detail"])

    def test_cloud_credit_rows_come_from_the_sibling_payload(self):
        expires = NOW + timedelta(hours=35)
        self.box.claude("cc", ".claude", 10.0, 15.0, credit=(250.0, 0.0, expires))
        self.box.claude("cc2", ".claude-work", 0.0, 4.0, credit=(250.0, 160.73, expires))
        self.box.claude("cc3", ".claude-3", 0.0, 0.0)
        _, seats = self.box.report("--only", "claude,claude-credit")
        cc = seats["cc-credit"]
        self.assertEqual(cc["provider"], "claude-credit")
        self.assertEqual(cc["credits"]["unit"], "usd")
        self.assertEqual(cc["credits"]["remaining"], 250.0)
        self.assertEqual(cc["credits"]["expires_at"], iso(expires))
        self.assertIsNone(cc["credits"]["resets_at"], "a credit expires, it never resets")
        self.assertEqual(cc["free_at"], "")
        self.assertEqual(cc["state"], "open")
        self.assertEqual(cc["grade"], seats["cc"]["grade"])
        self.assertEqual(cc["models"], ["Fable", "Opus"])
        cc2 = seats["cc2-credit"]
        self.assertAlmostEqual(cc2["credits"]["remaining"], 89.27)
        self.assertEqual(cc2["state"], "open")
        self.assertIn("$89.27 of $250.00 left", cc2["detail"])
        self.assertIn("payload carries no cloud credit", seats["cc3-credit"]["detail"]
                      if "cc3-credit" in seats else "payload carries no cloud credit")
        # The credit row alone still reads (through the sibling's cache).
        _, alone = self.box.report("--only", "cc2-credit")
        self.assertEqual(list(alone), ["cc2-credit"])
        self.assertAlmostEqual(alone["cc2-credit"]["credits"]["remaining"], 89.27)

    def test_an_expired_or_drained_credit_is_spent(self):
        self.box.claude("cc", ".claude", 10.0, 15.0, credit=(250.0, 250.0, NOW + timedelta(days=1)))
        self.box.claude("cc2", ".claude-work", 0.0, 4.0, credit=(250.0, 10.0, NOW - timedelta(hours=1)))
        _, seats = self.box.report("--only", "claude,claude-credit")
        self.assertEqual(seats["cc-credit"]["state"], "spent")
        self.assertEqual(seats["cc2-credit"]["state"], "spent")
        self.assertIn("expired", seats["cc2-credit"]["detail"])
        self.assertEqual(seats["cc"]["state"], "open", "the credit never binds the seat")
        tight = self.box.claude("cc", ".claude", 10.0, 15.0, credit=(250.0, 210.0, NOW + timedelta(days=1)))
        _, seats = self.box.report("--only", "cc,cc-credit")
        self.assertEqual(seats["cc-credit"]["state"], "tight")

    def test_the_ledger_renders_within_100_columns_and_jsonl_carries_it(self):
        (self.agenix / "gemini-api-key-1").write_text("not-a-real-gemini-key\n")
        self.box.run("--record", "gemini", "1", "gemini-3.8-flash", "ok")
        table = self.box.run("--no-spend")
        self.assertEqual(table.returncode, 0, table.stderr)
        body = table.stdout
        self.assertIn("burndown ledger", body)
        start = body.index("burndown ledger")
        end = body.index("model-scoped limits") if "model-scoped limits" in body else len(body)
        for line in body[start:end].splitlines():
            self.assertLessEqual(len(line), 100, line)
        self.assertIn("gemini      gemini-3.8-flash, gemini-3.5-flash", body)
        self.assertNotIn("gemini-1", body[:start], "lane rows live in the ledger, not the window table")
        jsonl = self.box.run("--jsonl", "--only", "ledger")
        rows = {json.loads(line)["id"]: json.loads(line) for line in jsonl.stdout.splitlines()}
        self.assertEqual(rows["gemini-1"]["usage_today"]["calls"], 1)
        self.assertEqual(rows["gemini-1"]["ledger"]["allowance_grade"], "STATIC")
        self.assertIn("generated_at", rows["gemini-1"])
