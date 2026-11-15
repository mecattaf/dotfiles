"""Security/provenance/cursor checks; fake sources never touch live runtime."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(os.environ.get("FLEET_STATUS_OBSERVER_PY", Path(__file__).resolve().parents[2] / "pkgs/fleet-status/observer.py"))
sys.path.insert(0, str(SOURCE.parent))
spec = importlib.util.spec_from_file_location("fleet_observer", SOURCE)
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)
from incremental import tail_jsonl


class ObserverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        config = {"dshSessions": str(self.root / "sessions"), "laneMeter": str(self.root / "meter.jsonl"), "intervals": {"hosts": 300, "metrics": 60, "instances": 60, "seats": 600, "tails": 10}}
        self.value = observer.Observer(config, self.root / "state")
        self.addCleanup(self.value.pool.shutdown, wait=True)
        self.addCleanup(self.value.publisher_pool.shutdown, wait=True)

    def test_projection_refuses_secrets_paths_objects_nan_and_unknown_keys(self):
        for value in ["Bearer secret-token", "/private/home", {"secret": "abc"}, float("nan")]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                observer.public_observation("host-nas", "fleet.snapshot", "host.reachability", value)
        with self.assertRaises(ValueError):
            observer.public_observation("host-nas", "fleet.snapshot", "argv", "secret")

    def test_native_usage_only_projects_reviewed_gemini_pool(self):
        report = "Gemini Models\tWeekly Limit Remaining\t96%\t2099-11-22T10:26:55Z\nClaude and GPT models\tWeekly Limit Remaining\t0%\t2099-11-17T23:52:59Z\n"
        with patch.object(observer, "command", return_value=report) as call:
            rows = self.value.antigravity_quota("2", ["agy2", "--print", "/usage"])
        self.assertEqual(call.call_args.kwargs, {"timeout": 18, "cap": 16384, "as_json": False})
        self.assertEqual(rows[0]["value"], 4)
        self.assertEqual(rows[0]["subjectId"], "quota-antigravity-2-gemini-weekly")
        self.assertEqual(len(rows), 3)
        self.assertNotIn("Claude", json.dumps(rows))
        for text in [report.replace("96%", "101%"), report.replace("2099-11-22T10:26:55Z", "private-secret"), report.replace("Gemini Models", "Unreviewed account")]:
            with patch.object(observer, "command", return_value=text), self.assertRaises(RuntimeError):
                self.value.antigravity_quota("2", ["agy2"])

    def test_unknown_token_placeholders_do_not_claim_reporting_coverage(self):
        self.value.state["usage"]["gufo"] = {"calls": 2, "successes": 2, "seenTokens": []}
        self.value.accept("tails", self.value.acquire("tails", self.value.tails))
        coverage = {row["sourceId"]: row for row in self.value.snapshot()["coverage"]}
        self.assertEqual(coverage["compute.tokens"]["state"], "not-configured")
        self.assertEqual(coverage["compute.call-history"]["state"], "reporting")

    def test_zen_native_tokens_are_separate_deduplicated_and_missing_stays_unknown(self):
        self.value.state["usage"]["zen"] = {"calls": 1, "successes": 1, "inputTokens": 7, "seenTokens": ["inputTokens"]}
        row = {"lane": "zen", "slot": 2, "invocation_id": "private-invocation", "ts": "2026-11-15T22:00:00Z", "usage_steps": [{"input": 12, "output": 3, "cache": {"read": 4}, "total": 99, "text": "SECRET"}], "receipt": "/private/SECRET"}
        self.value.zen_ledger(row)
        self.value.zen_ledger(row)
        self.value.zen_ledger({**row, "invocation_id": "empty", "usage_steps": []})
        rows = self.value.tails()
        counts = self.value.state["ledgerUsage"]["2"]
        self.assertEqual(counts["inputTokens"], 12)
        self.assertEqual(counts["cacheReadTokens"], 4)
        self.assertNotIn("reasoningTokens", counts)
        self.assertEqual(self.value.state["usage"]["zen"]["inputTokens"], 7)
        account = [r for r in rows if r["subjectId"] == "account-zen-2"]
        self.assertEqual(len(account), 5)
        self.assertIsNone(next(r["value"] for r in account if r["key"] == "usage.reasoningTokens"))
        self.assertNotIn("SECRET", json.dumps(account))

    def test_stale_publication_retains_original_last_good_without_fresh_timestamp(self):
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 2.0, at="2000-01-01T00:00:00Z", ttl=60)
        result = observer.refresh_rows([row], "2026-11-15T21:00:00Z")[0]
        self.assertIsNone(result["value"])
        self.assertEqual(result["errorCode"], "stale")
        self.assertEqual(result["lastGood"], {"value": 2.0, "observedAt": "2000-01-01T00:00:00Z"})
        self.assertEqual(result["observedAt"], "2000-01-01T00:00:00Z")
        row = observer.public_observation("quota-cloudflare-1-neurons", "compute.quota-headers", "quota.remaining", 100, at="2026-11-15T23:59:00Z", unit="neurons", ttl=7200)
        observer.expire_at_reset([row], "2026-11-16T00:00:00Z")
        self.assertEqual(row["expiresAt"], "2026-11-16T00:00:00Z")

    def test_complete_line_cursor_survives_partial_append_and_restart(self):
        path = self.root / "input.jsonl"
        path.write_bytes(b'{"one":1}\n{"two":')
        state = {}
        rows, gap, more = tail_jsonl(path, state)
        self.assertEqual(rows, [{"one": 1}])
        self.assertTrue(more)
        with path.open("ab") as stream:
            stream.write(b'2}\n')
        rows, gap, more = tail_jsonl(path, state)
        self.assertEqual(rows, [{"two": 2}])
        self.assertFalse(more)
        self.assertEqual(tail_jsonl(path, state)[0], [])

    def test_truncation_is_gap_and_does_not_recount_retained_history(self):
        path = self.root / "input.jsonl"
        path.write_text('{"a":1}\n')
        state = {}
        tail_jsonl(path, state)
        path.write_text('{}\n')
        rows, gap, _ = tail_jsonl(path, state)
        self.assertTrue(gap)
        self.assertEqual(rows, [])

    def test_enrollment_skips_old_transcript_and_next_completion_joins_usage_once(self):
        path = self.root / "sessions" / "workspace-secret" / "session-secret" / "session.v4.jsonl"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"type": "assistant/message", "data": {"content": "SECRET PROMPT", "usage": {"inputTokens": 99999}}}) + "\n")
        self.value.tails()
        with path.open("a") as stream:
            for row in [
                {"type": "request/context", "seq": 2, "time": 1794776146775, "data": {"provider": "groq", "model": "secret-custom-model"}},
                {"type": "assistant/message", "seq": 3, "time": 1794776146775, "data": {"turn": 1, "step": 1, "message": {"content": "SECRET RESPONSE"}, "usage": {"inputTokens": 12, "outputTokens": 8, "raw": "SECRET"}}},
                {"type": "step/end", "seq": 4, "time": 1794776146775, "data": {"turn": 1, "step": 1, "usage": {"inputTokens": 12, "outputTokens": 8}}},
            ]:
                stream.write(json.dumps(row) + "\n")
        self.value.accept("tails", self.value.acquire("tails", self.value.tails))
        self.value.tails()
        self.assertEqual(self.value.state["usage"]["groq"]["inputTokens"], 12)
        self.assertEqual(self.value.state["usage"]["groq"]["outputTokens"], 8)
        self.assertEqual(self.value.state["usage"]["groq"]["calls"], 1)
        snapshot = self.value.publish()
        public = json.dumps(snapshot)
        for secret in ["SECRET", "workspace-secret", "session-secret", "secret-custom-model", str(path)]:
            self.assertNotIn(secret, public)

    def test_journal_projection_ignores_message_argv_and_cursor_is_private(self):
        self.value.results.put({"MESSAGE_ID": "39f53479d3a045ac8e11786248231fbf", "USER_UNIT": "dshd@private-sensitive-title.service", "USER_INVOCATION_ID": "private-invocation", "__CURSOR": "private-cursor", "__REALTIME_TIMESTAMP": "1794776146775000", "MESSAGE": "SECRET PROMPT", "argv": "SECRET"})
        self.value.drain_journal()
        snapshot = self.value.publish()
        self.assertEqual(snapshot["events"][0]["summary"], "Supervised run started")
        for private in ["SECRET", "private-sensitive-title", "private-invocation", "private-cursor"]:
            self.assertNotIn(private, json.dumps(snapshot))
        self.assertEqual(self.value.state["journalCursor"], "private-cursor")

    def test_restored_state_advances_past_publisher_remote_sequence(self):
        (self.root / "state/publisher.json").write_text('{"remoteSequence":42}')
        value = self.value.publish()
        self.assertEqual(value["publisher"]["sequence"], 43)
        again = observer.Observer(self.value.config, self.root / "state")
        self.addCleanup(again.pool.shutdown, wait=True)
        self.addCleanup(again.publisher_pool.shutdown, wait=True)
        self.assertEqual(again.publish()["publisher"]["sequence"], 44)

    def test_failed_source_retains_its_last_good_dated_value(self):
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 1.0)
        self.value.accept("metrics", {"rows": [row], "error": None})
        self.value.accept("metrics", {"rows": None, "error": "source-timeout"})
        result = [r for r in self.value.publish()["observations"] if r["key"] == "host.load1"][0]
        self.assertEqual(result["grade"], "unknown")
        self.assertEqual(result["lastGood"]["value"], 1.0)

    def test_every_source_has_explicit_coverage_and_missing_tokens_are_unknown(self):
        value = self.value.publish()
        self.assertEqual(set(observer.SOURCES), {r["sourceId"] for r in value["coverage"]})
        self.assertTrue(all(r["value"] is None for r in value["observations"]))
        self.assertFalse(value["synthetic"])
        subjects = {r["id"] for r in value["subjects"]}
        self.assertTrue(all(r["subjectId"] in subjects for r in value["observations"]))

    def test_event_and_subject_ids_are_opaque_and_stable_within_owner(self):
        ident = self.value.public_id("session", "/secret/cwd")
        self.assertRegex(ident, r"^session-[a-f0-9]{24}$")
        self.assertEqual(ident, self.value.public_id("session", "/secret/cwd"))
        initial = self.value.publish()["catalogRevision"]
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 1.0)
        self.value.accept("metrics", {"rows": [row], "error": None})
        descriptor = self.value.publish()["catalogRevision"]
        self.assertNotEqual(initial, descriptor, "new signal descriptors change the catalogue")
        row["value"] = 2.0
        self.value.accept("metrics", {"rows": [row], "error": None})
        self.assertEqual(descriptor, self.value.publish()["catalogRevision"], "fresh measurements do not change descriptors")

    def test_retained_private_cache_cannot_inject_new_public_fields_or_strings(self):
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 1.0)
        row["privateSecret"] = "must never publish"
        self.value.accept("metrics", {"rows": [row], "error": None})
        with self.assertRaises(ValueError):
            self.value.publish()
        self.assertFalse((self.root / "state/public/status.json").exists())

    def test_an_oversized_record_cannot_wedge_the_cursor_or_be_publicly_copied(self):
        path = self.root / "large.jsonl"
        path.write_text(json.dumps({"private": "x" * 4096}) + "\n")
        cursors = {}
        rows, gap, more = tail_jsonl(path, cursors, byte_budget=1024)
        self.assertEqual(rows, [])
        self.assertTrue(gap)
        self.assertFalse(more)
        self.assertEqual(cursors[str(path)]["offset"], path.stat().st_size)

    def test_retry_after_does_not_block_heartbeat_or_get_shortened_by_local_backoff(self):
        future = observer.time.time() + 7200
        self.value.accept("metrics", {"rows": None, "error": "source-failed", "retryAfterAt": future})
        self.assertGreaterEqual(self.value.cache["metrics"]["nextAt"], future)
        self.assertEqual(self.value.publish()["snapshotId"], "snapshot-1")

    def test_unknown_token_fields_stay_unknown_while_explicit_zero_is_preserved(self):
        self.value.new_process = False
        path = self.root / "sessions" / "workspace" / "one" / "session.v4.jsonl"
        path.parent.mkdir(parents=True)
        records = [{"type": "request/context", "seq": 1, "data": {"provider": "groq"}},
                   {"type": "assistant/message", "seq": 2, "data": {"turn": 1, "step": 1, "usage": {"inputTokens": 0, "outputTokens": 2}}},
                   {"type": "step/end", "seq": 3, "data": {"turn": 1, "step": 1}}]
        path.write_text("".join(json.dumps(row) + "\n" for row in records))
        rows = self.value.tails()
        actual = {row["key"]: row["value"] for row in rows if row["subjectId"] == "provider-groq"}
        self.assertEqual(actual["usage.inputTokens"], 0)
        self.assertIsNone(actual["usage.reasoningTokens"])

    def test_failed_or_cancelled_steps_never_claim_a_successful_artifact(self):
        self.value.new_process = False
        for index, reason in enumerate(["error", "aborted", "aborted"]):
            path = self.root / "sessions" / "workspace" / str(index) / "session.v4.jsonl"
            path.parent.mkdir(parents=True)
            records = [{"type": "request/context", "seq": 1, "data": {"provider": "groq"}},
                       {"type": "assistant/attempt", "seq": 2, "data": {"turn": 1, "step": 1, "stream": {}}},
                       {"type": "step/end", "seq": 3, "data": {"turn": 1, "step": 1}},
                       {"type": "turn/end", "seq": 4, "data": {"reason": {"kind": reason, "error": {"code": "QUOTA", "message": "PRIVATE ERROR"}}}}]
            if index == 2:
                records[1] = {"type": "assistant/message", "seq": 2, "data": {"turn": 1, "step": 1, "interrupted": True, "usage": {"inputTokens": 3, "outputTokens": 2}}}
            path.write_text("".join(json.dumps(row) + "\n" for row in records))
        self.value.tails()
        self.assertEqual(self.value.state["usage"]["groq"]["calls"], 3)
        self.assertEqual(self.value.state["usage"]["groq"]["successes"], 0)
        self.assertEqual(self.value.state["usage"]["groq"]["inputTokens"], 3)
        self.assertEqual({row["state"] for row in self.value.state["sessions"].values()}, {"failed", "cancelled"})

    def test_session_metadata_eviction_retains_dedup_cursor(self):
        self.value.new_process = False
        path = self.root / "sessions" / "workspace" / "original" / "session.v4.jsonl"
        path.parent.mkdir(parents=True)
        records = [{"type": "request/context", "seq": 1, "data": {"provider": "groq"}},
                   {"type": "assistant/message", "seq": 2, "data": {"turn": 1, "step": 1, "usage": {"inputTokens": 12}}},
                   {"type": "step/end", "seq": 3, "data": {"turn": 1, "step": 1}}]
        path.write_text("".join(json.dumps(row) + "\n" for row in records))
        self.value.tails()
        # Exercise the actual 513-entry pruning branch: 256 newer owner files
        # plus 256 retained recent metadata rows push this old owner out of the
        # bounded presentation set, while its primary offset must survive.
        os.utime(path, (1, 1))
        self.value.state["sessions"][str(path)]["seenAt"] = 0
        for index in range(256):
            fresh = self.root / "sessions" / "new" / str(index) / "session.v4.jsonl"
            fresh.parent.mkdir(parents=True)
            fresh.write_text("")
            key = "retained-" + str(index)
            self.value.state["sessions"][key] = {"id": self.value.public_id("session", key), "state": "unknown", "seq": -1, "seenAt": observer.time.time() - 1}
        self.value.tails()
        self.assertNotIn(str(path), self.value.state["sessions"])
        path.touch()
        self.value.tails()
        self.assertEqual(self.value.state["usage"]["groq"]["inputTokens"], 12)
        self.assertIn(str(path), self.value.state["cursors"])


if __name__ == "__main__":
    unittest.main()
