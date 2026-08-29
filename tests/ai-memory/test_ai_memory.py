from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path(
    os.environ.get(
        "AI_MEMORY_ENGINE",
        REPO_ROOT / "home/dot_claude/skills/drain/scripts/ai_memory.py",
    )
)
ENGINE_SPEC = importlib.util.spec_from_file_location("ai_memory", ENGINE)
if ENGINE_SPEC is None or ENGINE_SPEC.loader is None:
    raise RuntimeError(f"could not load AI-memory engine from {ENGINE}")
memory = importlib.util.module_from_spec(ENGINE_SPEC)
sys.modules["ai_memory"] = memory
ENGINE_SPEC.loader.exec_module(memory)

SKILL_ROOT = REPO_ROOT / "home/dot_claude/skills"
DRAIN_SKILL = Path(
    os.environ.get("AI_MEMORY_DRAIN_SKILL", SKILL_ROOT / "drain/SKILL.md")
)
HANDOFF_SKILL = Path(
    os.environ.get("AI_MEMORY_HANDOFF_SKILL", SKILL_ROOT / "handoff/SKILL.md")
)
PICKUP_SKILL = Path(
    os.environ.get("AI_MEMORY_PICKUP_SKILL", SKILL_ROOT / "pickup/SKILL.md")
)

FIXTURES = Path(__file__).parent / "fixtures"
CLAUDE_HOME = FIXTURES / "claude"
CODEX_HOME = FIXTURES / "codex"
CLAUDE_ROOT_ID = "11111111-1111-4111-8111-111111111111"
CLAUDE_CHILD_ID = "22222222-2222-4222-8222-222222222222"
CODEX_ROOT_ID = "019f0000-0000-7000-8000-a1b2c3d40001"
CODEX_SUBAGENT_ID = "019f0000-0000-7000-8000-bbbbbbbb0002"
CODEX_EXEC_ID = "019f0000-0000-7000-8000-cccccccc0003"


def result_data(
    *,
    title: str = "appliance seam",
    group: str = "memory drain",
    thread: str = "The session implemented a bounded local memory drain.",
) -> dict[str, object]:
    return {
        "title": title,
        "group": group,
        "thread": thread,
        "decisions": ["The user settled on explicit manual drains."],
        "candidate_ideas": ["A future backup workflow remains separate."],
        "constraints": ["No cloud or paid-model fallback is allowed."],
        "artifacts": ["modules/npu-llm.nix defines the local boundary."],
        "open_questions": ["A live NPU smoke test follows deployment."],
    }


class QueueInvoker:
    def __init__(self, *responses: object) -> None:
        self.responses = list(responses)
        self.requests: list[dict[str, object]] = []

    def __call__(self, request: dict[str, object]) -> str:
        self.requests.append(request)
        if not self.responses:
            raise AssertionError("unexpected utility-model invocation")
        response = self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        if isinstance(response, str):
            return response
        return json.dumps(response)


def copied_trace(source: Path, directory: Path) -> Path:
    target = directory / source.name
    shutil.copy2(source, target)
    target.chmod(target.stat().st_mode | 0o600)
    return target


def fixture_trace(home: Path, session_id: str) -> Path:
    matches = list(home.rglob(f"*{session_id}.jsonl"))
    if len(matches) != 1:
        raise AssertionError(f"fixture lookup for {session_id} returned {matches}")
    return matches[0]


class AdapterTests(unittest.TestCase):
    def test_current_identity_uses_only_explicit_agent_environment(self) -> None:
        self.assertEqual(
            memory.current_identity(
                environment={"CLAUDE_CODE_SESSION_ID": CLAUDE_ROOT_ID}
            ),
            memory.Identity("claude-code", CLAUDE_ROOT_ID),
        )
        self.assertEqual(
            memory.current_identity(environment={"CODEX_THREAD_ID": CODEX_ROOT_ID}),
            memory.Identity("codex", CODEX_ROOT_ID),
        )
        with self.assertRaisesRegex(memory.MemoryError, "both Claude and Codex"):
            memory.current_identity(
                environment={
                    "CLAUDE_CODE_SESSION_ID": CLAUDE_ROOT_ID,
                    "CODEX_THREAD_ID": CODEX_ROOT_ID,
                }
            )
        self.assertEqual(
            memory.current_identity(
                environment={
                    "CLAUDE_CODE_SESSION_ID": CLAUDE_ROOT_ID,
                    "CLAUDE_CODE_CHILD_SESSION": "1",
                    "CODEX_THREAD_ID": CODEX_ROOT_ID,
                }
            ),
            memory.Identity("codex", CODEX_ROOT_ID),
        )
        with self.assertRaisesRegex(memory.MemoryError, "root Claude"):
            memory.current_identity(
                "claude-code",
                {
                    "CLAUDE_CODE_SESSION_ID": CLAUDE_ROOT_ID,
                    "CLAUDE_CODE_CHILD_SESSION": "1",
                },
            )

    def test_claude_resolver_matches_identity_not_recency_or_child_path(self) -> None:
        resolved = memory.resolve_claude_trace(CLAUDE_HOME, CLAUDE_ROOT_ID)
        self.assertEqual(resolved.name, f"{CLAUDE_ROOT_ID}.jsonl")
        self.assertNotIn("33333333", str(resolved))
        with self.assertRaisesRegex(memory.MemoryError, "no root Claude"):
            memory.resolve_claude_trace(CLAUDE_HOME, CLAUDE_CHILD_ID)

    def test_codex_resolver_proves_root_metadata_and_rejects_other_kinds(self) -> None:
        resolved = memory.resolve_codex_trace(CODEX_HOME, CODEX_ROOT_ID)
        self.assertIn(CODEX_ROOT_ID, resolved.name)
        self.assertNotIn("deadbeef", str(resolved))
        with self.assertRaisesRegex(memory.MemoryError, "subagent trace"):
            memory.resolve_codex_trace(CODEX_HOME, CODEX_SUBAGENT_ID)
        with self.assertRaisesRegex(memory.MemoryError, "exec trace"):
            memory.resolve_codex_trace(CODEX_HOME, CODEX_EXEC_ID)

    def test_normalizers_drop_private_payloads_but_keep_bounded_evidence(self) -> None:
        _, claude_records = memory.load_jsonl_stably(
            fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID)
        )
        claude_turns, claude_visible = memory.normalize_trace(
            "claude-code", claude_records
        )
        claude_text = "\n".join(turn.content for turn in claude_turns)
        self.assertIn("Implement the memory drain", claude_text)
        self.assertIn("Read targeted /workspace/modules/npu-llm.nix", claude_text)
        self.assertIn("tool call completed successfully", claude_text)
        self.assertNotIn("SECRET_", claude_text)
        self.assertNotIn("ai-memory:handoff", claude_text)
        handoff = memory.latest_handoff(
            claude_visible,
            memory.Identity("claude-code", CLAUDE_ROOT_ID),
        )
        self.assertIsNotNone(handoff)
        assert handoff is not None
        self.assertIn("Verify the synthetic acceptance suite", handoff[1])

        _, codex_records = memory.load_jsonl_stably(
            fixture_trace(CODEX_HOME, CODEX_ROOT_ID)
        )
        codex_turns, codex_visible = memory.normalize_trace("codex", codex_records)
        codex_text = "\n".join(turn.content for turn in codex_turns)
        self.assertIn("Build an exact Codex adapter", codex_text)
        self.assertIn("command invoked: nix flake check", codex_text)
        self.assertIn("exit code 0", codex_text)
        self.assertNotIn("SECRET_", codex_text)
        self.assertNotIn("ai-memory:handoff", codex_text)
        self.assertIsNotNone(
            memory.latest_handoff(
                codex_visible,
                memory.Identity("codex", CODEX_ROOT_ID),
            )
        )

    def test_latest_well_formed_handoff_wins(self) -> None:
        identity = memory.Identity("codex", CODEX_ROOT_ID)
        valid = (
            '<!-- ai-memory:handoff {"version":1,"source":"codex",'
            f'"session_id":"{CODEX_ROOT_ID}"}} -->\n'
            "## Handoff\n\nKeep this block.\n"
            "<!-- /ai-memory:handoff -->"
        )
        invalid_later = (
            '<!-- ai-memory:handoff {"version":2,"source":"codex",'
            f'"session_id":"{CODEX_ROOT_ID}"}} -->\n'
            "## Handoff\n\nDo not keep this block.\n"
            "<!-- /ai-memory:handoff -->"
        )
        handoff = memory.latest_handoff([valid, invalid_later], identity)
        self.assertIsNotNone(handoff)
        assert handoff is not None
        self.assertEqual(handoff[1], "Keep this block.")


class SkillBoundaryTests(unittest.TestCase):
    def test_shared_skills_keep_the_three_user_actions_separate(self) -> None:
        drain = DRAIN_SKILL.read_text()
        handoff = HANDOFF_SKILL.read_text()
        pickup = PICKUP_SKILL.read_text()

        self.assertIn('ai_memory.py" drain', drain)
        self.assertIn('ai_memory.py" identity', handoff)
        self.assertIn("<!-- ai-memory:handoff", handoff)
        self.assertNotIn('ai_memory.py" drain', handoff)
        self.assertNotIn("utility-model --", handoff)
        self.assertIn('ai_memory.py" pickup', pickup)
        self.assertNotIn('ai_memory.py" drain', pickup)
        self.assertIn("ai-memory:parent", pickup)

    def test_drain_skill_states_the_permanent_utility_model_retirement(self) -> None:
        drain = DRAIN_SKILL.read_text()
        self.assertIn("2026-08-29", drain)
        self.assertIn("decommission", drain.lower())
        # The retirement is permanent: the skill must not send a session off
        # to change a host's configuration and retry, and must not offer a
        # cloud or paid substitute for the model that is gone.
        self.assertNotIn("switch the coordinator configuration", drain)
        self.assertIn("no configuration switch", drain)
        self.assertIn("paid", drain)


class DrainTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.journal = self.root / "journal"
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.environment = mock.patch.dict(
            os.environ,
            {"XDG_RUNTIME_DIR": str(self.runtime)},
        )
        self.environment.start()

    def tearDown(self) -> None:
        self.environment.stop()
        self.temporary.cleanup()

    def test_create_noop_and_in_place_update_keep_stable_identity_fields(self) -> None:
        source = fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID)
        trace = copied_trace(source, self.root)
        identity = memory.Identity("claude-code", CLAUDE_ROOT_ID)
        first_invoker = QueueInvoker(result_data())
        first_now = datetime.fromisoformat("2026-07-22T22:10:00+02:00")

        status, note_path = memory.drain_session(
            identity=identity,
            journal_dir=self.journal,
            trace_path=trace,
            now=first_now,
            invoker=first_invoker,
        )

        self.assertEqual(status, "created")
        self.assertEqual(
            note_path.relative_to(self.journal).as_posix(),
            "2026/07/22/appliance-seam.md",
        )
        first_bytes = note_path.read_bytes()
        first_text = first_bytes.decode()
        fields, _ = memory.parse_frontmatter(first_text)
        self.assertEqual(fields["title"], "Appliance seam")
        self.assertEqual(fields["group"], "memory drain")
        self.assertEqual(fields["source"], "claude-code")
        self.assertEqual(fields["session_id"], CLAUDE_ROOT_ID)
        self.assertNotIn("parent_source", fields)
        self.assertIn("## Handoff", first_text)
        self.assertIn("Verify the synthetic acceptance suite", first_text)
        self.assertNotIn("SECRET_", first_text)
        self.assertLessEqual(len(first_bytes), memory.MAX_NOTE_BYTES)
        self.assertTrue(all(req["model"] == "utility" for req in first_invoker.requests))

        status, same_path = memory.drain_session(
            identity=identity,
            journal_dir=self.journal,
            trace_path=trace,
            now=datetime.fromisoformat("2026-07-23T09:00:00+02:00"),
            invoker=QueueInvoker(
                AssertionError("an unchanged drain must not invoke the utility model")
            ),
        )
        self.assertEqual(status, "unchanged")
        self.assertEqual(same_path, note_path)
        self.assertEqual(note_path.read_bytes(), first_bytes)

        appended = {
            "type": "user",
            "sessionId": CLAUDE_ROOT_ID,
            "isSidechain": False,
            "timestamp": "2026-07-23T08:59:00+02:00",
            "message": {
                "role": "user",
                "content": "The refreshed note must stay at its original path.",
            },
        }
        with trace.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(appended) + "\n")

        changed = result_data(
            title="a model-proposed rename",
            group="different cluster",
            thread="The session now includes the final in-place update requirement.",
        )
        status, updated_path = memory.drain_session(
            identity=identity,
            journal_dir=self.journal,
            trace_path=trace,
            now=datetime.fromisoformat("2026-07-23T09:01:00+02:00"),
            invoker=QueueInvoker(changed),
        )
        self.assertEqual(status, "updated")
        self.assertEqual(updated_path, note_path)
        updated_text = note_path.read_text()
        updated_fields, _ = memory.parse_frontmatter(updated_text)
        self.assertEqual(updated_fields["title"], "Appliance seam")
        self.assertEqual(updated_fields["group"], "memory drain")
        self.assertEqual(updated_fields["started_at"], fields["started_at"])
        self.assertNotEqual(updated_fields["source_digest"], fields["source_digest"])
        self.assertIn("final in-place update requirement", updated_text)
        self.assertFalse(list(note_path.parent.glob(".ai-memory-*.tmp")))

    def test_same_title_collision_gets_deterministic_session_suffix(self) -> None:
        first_trace = fixture_trace(CODEX_HOME, CODEX_ROOT_ID)
        first_identity = memory.Identity("codex", CODEX_ROOT_ID)
        now = datetime.fromisoformat("2026-07-22T22:10:00+02:00")
        _, first_path = memory.drain_session(
            identity=first_identity,
            journal_dir=self.journal,
            trace_path=first_trace,
            now=now,
            invoker=QueueInvoker(result_data()),
        )

        second_id = "019f0000-0000-7000-8000-feedface0002"
        second_trace = self.root / f"rollout-{second_id}.jsonl"
        second_trace.write_text(
            first_trace.read_text().replace(CODEX_ROOT_ID, second_id),
            encoding="utf-8",
        )
        _, second_path = memory.drain_session(
            identity=memory.Identity("codex", second_id),
            journal_dir=self.journal,
            trace_path=second_trace,
            now=now,
            invoker=QueueInvoker(result_data()),
        )

        self.assertEqual(first_path.name, "appliance-seam.md")
        self.assertEqual(second_path.name, "appliance-seam-feedface.md")
        self.assertNotEqual(first_path, second_path)

    def test_failures_leave_no_partial_or_damaged_note(self) -> None:
        trace = copied_trace(
            fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            self.root,
        )
        identity = memory.Identity("claude-code", CLAUDE_ROOT_ID)
        now = datetime.fromisoformat("2026-07-22T22:10:00+02:00")

        with self.assertRaisesRegex(memory.MemoryError, "NPU unavailable"):
            memory.drain_session(
                identity=identity,
                journal_dir=self.journal,
                trace_path=trace,
                now=now,
                invoker=QueueInvoker(memory.MemoryError("NPU unavailable")),
            )
        self.assertFalse(list(self.journal.rglob("*.md")))

        _, note_path = memory.drain_session(
            identity=identity,
            journal_dir=self.journal,
            trace_path=trace,
            now=now,
            invoker=QueueInvoker(result_data()),
        )
        original = note_path.read_bytes()
        with trace.open("a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    {
                        "type": "assistant",
                        "sessionId": CLAUDE_ROOT_ID,
                        "isSidechain": False,
                        "timestamp": "2026-07-22T22:11:00+02:00",
                        "message": {"role": "assistant", "content": "One more turn."},
                    }
                )
                + "\n"
            )

        with self.assertRaisesRegex(memory.ModelOutputError, "corrective retry"):
            memory.drain_session(
                identity=identity,
                journal_dir=self.journal,
                trace_path=trace,
                now=datetime.fromisoformat("2026-07-22T22:12:00+02:00"),
                invoker=QueueInvoker("not json", '{"still":"wrong"}'),
            )
        self.assertEqual(note_path.read_bytes(), original)
        self.assertFalse(list(note_path.parent.glob(".ai-memory-*.tmp")))

        with self.assertRaisesRegex(memory.MemoryError, "timed out"):
            memory.drain_session(
                identity=identity,
                journal_dir=self.journal,
                trace_path=trace,
                now=datetime.fromisoformat("2026-07-22T22:13:00+02:00"),
                invoker=QueueInvoker(memory.MemoryError("local utility-model timed out")),
            )
        self.assertEqual(note_path.read_bytes(), original)

    def test_pickup_loads_only_handoff_and_carries_lineage_across_date(self) -> None:
        predecessor = memory.Identity("claude-code", CLAUDE_ROOT_ID)
        _, predecessor_path = memory.drain_session(
            identity=predecessor,
            journal_dir=self.journal,
            trace_path=fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            now=datetime.fromisoformat("2026-07-22T23:58:00+02:00"),
            invoker=QueueInvoker(
                result_data(thread="PRIVATE_PREDECESSOR_SUMMARY_NOT_FOR_PICKUP")
            ),
        )
        pickup = memory.pickup_output(
            self.journal,
            f"{predecessor.source}:{predecessor.session_id}",
        )
        self.assertIn("ai-memory:parent", pickup)
        self.assertIn("Verify the synthetic acceptance suite", pickup)
        self.assertNotIn("PRIVATE_PREDECESSOR_SUMMARY_NOT_FOR_PICKUP", pickup)

        successor_id = "019f0000-0000-7000-8000-dddddddd0005"
        successor_trace = self.root / f"rollout-{successor_id}.jsonl"
        records = [
            {
                "timestamp": "2026-07-23T00:01:00+02:00",
                "type": "session_meta",
                "payload": {
                    "id": successor_id,
                    "thread_source": "user",
                    "source": "exec",
                    "originator": "codex_exec",
                },
            },
            {
                "timestamp": "2026-07-23T00:01:01+02:00",
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "output_text", "text": pickup}],
                },
            },
            {
                "timestamp": "2026-07-23T00:02:00+02:00",
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": "Continue with the inherited constraints.",
                        }
                    ],
                },
            },
        ]
        successor_trace.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )
        _, successor_path = memory.drain_session(
            identity=memory.Identity("codex", successor_id),
            journal_dir=self.journal,
            trace_path=successor_trace,
            now=datetime.fromisoformat("2026-07-23T00:05:00+02:00"),
            invoker=QueueInvoker(
                result_data(
                    title="continued verification",
                    group="wrong group",
                    thread="The successor continued from a bounded handoff.",
                )
            ),
        )

        fields, _ = memory.parse_frontmatter(successor_path.read_text())
        self.assertEqual(
            successor_path.relative_to(self.journal).parent.as_posix(),
            "2026/07/23",
        )
        self.assertNotEqual(successor_path, predecessor_path)
        self.assertEqual(fields["group"], "memory drain")
        self.assertEqual(fields["parent_source"], "claude-code")
        self.assertEqual(fields["parent_session_id"], CLAUDE_ROOT_ID)

        duplicate = self.journal / "duplicate-predecessor.md"
        shutil.copy2(predecessor_path, duplicate)
        with self.assertRaisesRegex(memory.MemoryError, "found 2 journal notes"):
            memory.pickup_output(
                self.journal,
                f"{predecessor.source}:{predecessor.session_id}",
            )

    def test_absent_utility_model_refuses_permanently_and_writes_nothing(self) -> None:
        # The NPU was decommissioned 2026-08-29 and `utility-model` is not
        # installed on any host any more, so the seam's own default invoker is
        # what a real /drain now hits. It must fail closed through the ordinary
        # bounded MemoryError path — same exit semantics as every other
        # failure, no traceback, no partial note — and it must not tell the
        # session that switching a configuration would bring the model back.
        trace = copied_trace(
            fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            self.root,
        )
        with mock.patch.object(memory.shutil, "which", return_value=None):
            with self.assertRaises(memory.MemoryError) as caught:
                memory.drain_session(
                    identity=memory.Identity("claude-code", CLAUDE_ROOT_ID),
                    journal_dir=self.journal,
                    trace_path=trace,
                    now=datetime.fromisoformat("2026-08-29T10:00:00+02:00"),
                )
        message = str(caught.exception)
        self.assertIn("decommissioned 2026-08-29", message)
        self.assertIn("no configuration switch restores it", message)
        self.assertNotIn("switch the coordinator configuration", message)
        self.assertFalse(list(self.journal.rglob("*.md")))

    def test_retired_seam_exits_one_through_main_without_a_traceback(self) -> None:
        stderr = io.StringIO()
        with mock.patch.object(
            memory,
            "current_identity",
            side_effect=memory.MemoryError(memory.UTILITY_DECOMMISSIONED),
        ):
            with contextlib.redirect_stderr(stderr):
                status = memory.main(["drain"])
        self.assertEqual(status, 1)
        self.assertEqual(
            stderr.getvalue(),
            f"ai-memory: {memory.UTILITY_DECOMMISSIONED}\n",
        )
        self.assertNotIn("Traceback", stderr.getvalue())

    def test_trace_provenance_is_rechecked_before_writing(self) -> None:
        with self.assertRaisesRegex(memory.MemoryError, "different thread identity"):
            memory.drain_session(
                identity=memory.Identity(
                    "codex", "019f0000-0000-7000-8000-eeeeeeee0006"
                ),
                journal_dir=self.journal,
                trace_path=fixture_trace(CODEX_HOME, CODEX_ROOT_ID),
                now=datetime.fromisoformat("2026-07-22T22:10:00+02:00"),
                invoker=QueueInvoker(result_data()),
            )
        self.assertFalse(list(self.journal.rglob("*.md")))


class CompactionTests(unittest.TestCase):
    def test_long_sessions_map_reduce_without_silent_truncation(self) -> None:
        turns = [
            memory.Turn(
                "user" if index % 2 == 0 else "assistant",
                f"SEGMENT_{index} " + ("x" * 13_000),
            )
            for index in range(4)
        ]
        invoker = QueueInvoker(*(result_data() for _ in range(5)))
        result = memory.compact_turns(turns, invoker)
        self.assertEqual(result.group, "memory drain")
        self.assertGreater(len(invoker.requests), 2)
        map_prompts = "\n".join(
            request["messages"][1]["content"]
            for request in invoker.requests
            if "Compaction mode: map chunk" in request["messages"][1]["content"]
        )
        for index in range(4):
            self.assertIn(f"SEGMENT_{index}", map_prompts)
        self.assertTrue(
            all(request.get("model") == "utility" for request in invoker.requests)
        )

    def test_one_turn_larger_than_context_is_rejected_not_truncated(self) -> None:
        oversized = memory.Turn("user", "x" * memory.TURN_CHUNK_BYTES)
        with self.assertRaisesRegex(memory.MemoryError, "refused to truncate"):
            memory.pack_turns([oversized])

    def test_model_schema_gets_one_bounded_corrective_retry(self) -> None:
        invoker = QueueInvoker("not JSON", result_data())
        result = memory.request_model_result("synthetic evidence", invoker)
        self.assertEqual(result.title, "Appliance seam")
        self.assertEqual(len(invoker.requests), 2)
        self.assertTrue(all(request["model"] == "utility" for request in invoker.requests))
        with self.assertRaisesRegex(memory.ModelOutputError, "exactly two plain words"):
            memory.validate_model_result(result_data(group="one 2"))


if __name__ == "__main__":
    unittest.main()
