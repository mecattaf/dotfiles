"""Security/provenance/cursor checks; fake sources never touch live runtime."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

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

    def test_stale_publication_retains_original_last_good_without_fresh_timestamp(self):
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 2.0, at="2000-01-01T00:00:00Z", ttl=60)
        result = observer.refresh_rows([row], "2026-11-15T21:00:00Z")[0]
        self.assertIsNone(result["value"])
        self.assertEqual(result["errorCode"], "stale")
        self.assertEqual(result["lastGood"], {"value": 2.0, "observedAt": "2000-01-01T00:00:00Z"})
        self.assertEqual(result["observedAt"], "2000-01-01T00:00:00Z")

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

    def test_retained_private_cache_cannot_inject_new_public_fields_or_strings(self):
        row = observer.public_observation("host-nas", "host.pressure", "host.load1", 1.0)
        row["privateSecret"] = "must never publish"
        self.value.accept("metrics", {"rows": [row], "error": None})
        with self.assertRaises(ValueError):
            self.value.publish()
        self.assertFalse((self.root / "state/public/status.json").exists())


if __name__ == "__main__":
    unittest.main()
