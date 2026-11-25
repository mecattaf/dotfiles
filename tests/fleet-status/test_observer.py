"""Security/provenance/cursor checks; fake sources never touch live runtime."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

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
        config = {"dshSessions": str(self.root / "sessions"), "laneMeter": str(self.root / "meter.jsonl"), "intervals": {"hosts": 300, "metrics": 60, "seats": 600, "tails": 10}}
        self.value = observer.Observer(config, self.root / "state")
        self.addCleanup(self.value.pool.shutdown, wait=True)
        self.addCleanup(self.value.publisher_pool.shutdown, wait=True)

    def test_config_without_dsh_sources_reports_no_error_and_no_instances(self):
        value = observer.Observer({"laneMeter": str(self.root / "meter.jsonl"), "intervals": {"hosts": 300, "metrics": 60, "seats": 600, "tails": 10}}, self.root / "state2")
        self.addCleanup(value.pool.shutdown, wait=True)
        self.addCleanup(value.publisher_pool.shutdown, wait=True)
        result = value.acquire("tails", value.tails)
        self.assertIsNone(result["error"])
        value.accept("tails", result)
        snapshot = value.publish()
        coverage = {row["sourceId"]: row for row in snapshot["coverage"]}
        for source in ["agent.instances", "agent.lifecycle", "agent.sessions"]:
            self.assertEqual(coverage[source]["state"], "not-configured")
        self.assertFalse(any(subject["kind"] == "instance" for subject in snapshot["subjects"]))
        self.assertEqual(snapshot["events"], [])

    def test_restored_state_drops_retired_instance_rows_and_lifecycle_events(self):
        parent = self.value.add_subject(self.value.public_id("instance", "private-floor"), "instance", "DSH instance", "host-nas")
        run = self.value.add_subject(self.value.public_id("invocation", "private-run"), "invocation", "Supervised run", parent)
        self.value.event(run, "agent.lifecycle", "run.started", "2026-11-25T23:00:00Z", "private-run-started")
        row = observer.public_observation(parent, "agent.instances", "instance.state", "running", ttl=180, scope="this-instance")
        self.value.cache["instances"] = {"rows": [row], "failures": 0, "error": None}
        self.value.publish()
        again = observer.Observer(self.value.config, self.root / "state")
        self.addCleanup(again.pool.shutdown, wait=True)
        self.addCleanup(again.publisher_pool.shutdown, wait=True)
        self.assertNotIn("instances", again.cache)
        snapshot = again.publish()
        self.assertEqual(snapshot["events"], [])
        self.assertFalse(any(subject["kind"] in ["instance", "invocation"] for subject in snapshot["subjects"]))

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

    # hc panel: terminal counts of the NAS core, never a client call without an answering socket.
    HC_REPORT = {"hidden_finished": 0, "terminals": [
        {"address": "t1", "name": "st1", "cwd": "/private/home", "state": "live"},
        {"address": "t2", "name": "st2", "cwd": "/private/home", "state": "live", "status": "working"},
        {"address": "t3", "name": "done", "cwd": "/private/home", "state": "finished", "exit_code": 0, "reason": "exited"},
        {"address": "nas/t9", "name": "remote", "state": "live"}]}

    def hc_observer(self, socket_path):
        config = {"laneMeter": str(self.root / "meter.jsonl"), "hcCommand": ["env", "-i", "herdr-core", "ls", "--all", "--json"], "hcSocket": str(socket_path),
                  "intervals": {"hosts": 300, "metrics": 60, "seats": 600, "tails": 10, "hc": 60}}
        value = observer.Observer(config, self.root / "state-hc")
        self.addCleanup(value.pool.shutdown, wait=True)
        self.addCleanup(value.publisher_pool.shutdown, wait=True)
        return value

    def socket_dir(self):
        # AF_UNIX paths are limited to 108 bytes: keep them short.
        directory = tempfile.TemporaryDirectory(prefix="fs", dir="/tmp" if os.access("/tmp", os.W_OK) else None)
        self.addCleanup(directory.cleanup)
        return Path(directory.name)

    def listening(self, path):
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        server.listen(8)
        self.addCleanup(server.close)
        return server

    def test_hc_counts_live_and_finished_local_terminals(self):
        path = self.socket_dir() / "default.sock"
        self.listening(path)
        value = self.hc_observer(path)
        with patch.object(observer, "command", return_value=self.HC_REPORT) as call:
            result = value.acquire("hc", value.hc)
        self.assertIsNone(result["error"])
        self.assertEqual(call.call_args.args, (value.config["hcCommand"],))
        self.assertEqual(call.call_args.kwargs["timeout"], 10)
        rows = {row["key"]: row for row in result["rows"]}
        self.assertEqual(rows["runtime.runningCount"]["value"], 2)
        self.assertEqual(rows["runtime.workloadCount"]["value"], 3)
        for row in rows.values():
            self.assertEqual((row["subjectId"], row["sourceId"], row["unit"], row["scope"]), ("host-nas", "runtime.containers", "count", "host-total"))
        value.accept("hc", result)
        snapshot = value.publish()
        coverage = {row["sourceId"]: row for row in snapshot["coverage"]}
        self.assertEqual(coverage["runtime.containers"]["state"], "reporting")
        self.assertNotIn("private", json.dumps(snapshot))

    def test_hc_never_runs_without_an_answering_socket(self):
        directory = self.socket_dir()
        stale = directory / "stale.sock"
        self.listening(stale).close()
        for path in [directory / "missing.sock", stale]:
            with self.subTest(path=path.name):
                value = self.hc_observer(path)
                with patch.object(observer, "command", Mock(return_value=self.HC_REPORT)) as call:
                    result = value.acquire("hc", value.hc)
                self.assertEqual(result["error"], "source-unavailable")
                call.assert_not_called()
                value.accept("hc", result)
                coverage = {row["sourceId"]: row for row in value.publish()["coverage"]}
                self.assertEqual(coverage["runtime.containers"]["state"], "unavailable")

    def test_config_without_hc_keeps_runtime_containers_not_configured(self):
        self.assertNotIn("hcCommand", self.value.config)
        coverage = {row["sourceId"]: row for row in self.value.publish()["coverage"]}
        self.assertEqual(coverage["runtime.containers"]["state"], "not-configured")

    def test_hc_refuses_a_malformed_report(self):
        path = self.socket_dir() / "default.sock"
        self.listening(path)
        value = self.hc_observer(path)
        for report in [{"terminals": "x"}, [], {"hidden_finished": 0}]:
            with self.subTest(report=report), patch.object(observer, "command", return_value=report):
                self.assertEqual(value.acquire("hc", value.hc)["error"], "source-failed")


if __name__ == "__main__":
    unittest.main()
