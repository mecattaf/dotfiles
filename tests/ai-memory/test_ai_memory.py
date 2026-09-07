from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
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

ENQUEUE_CHECK = Path(
    os.environ.get(
        "AI_MEMORY_ENQUEUE_CHECK",
        REPO_ROOT / "tools/enqueue-row-check.py",
    )
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
        "resolved": False,
        "unresolved_units": ["Wire the harvest verb to a SessionEnd hook."],
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

    def test_the_written_rule_keeps_drain_manual_and_names_the_harvest_store(
        self,
    ) -> None:
        # R-c21: the prohibition on automatic runs stays for the journal and is
        # lifted for the separate harvest store. A session that reads only this
        # file must be able to tell which verb a hook may call and where it
        # writes — and must not be sent at branch (a)'s live state dir.
        drain = DRAIN_SKILL.read_text()
        self.assertIn("The user must request every drain", drain)
        self.assertIn('ai_memory.py" harvest', drain)
        self.assertIn("~/.local/state/tally-rewrite/harvest/<session_id>.md", drain)
        self.assertIn("never to the journal", drain)
        self.assertIn("unresolved_units", drain)
        self.assertNotIn("~/.local/state/tally/harvest", drain)

    def test_drain_skill_names_the_gpu_seam_the_distillation_now_runs_on(self) -> None:
        drain = DRAIN_SKILL.read_text()
        # The seam migrated on 2026-08-29 rather than retiring: a session
        # reading only the frontmatter description must learn which engine
        # answers, because the skills tree is hot-loaded through an
        # out-of-store symlink and the body may never be read.
        description = drain.split("---")[1]
        self.assertIn("GPU utility model", description)
        self.assertIn("llama-swap", description)
        self.assertIn("2026-08-29", description)
        self.assertNotIn("RETIRED", description)
        # The body must not claim the path is gone, and must not send a
        # session off to change a host's configuration and retry.
        self.assertIn("llama-swap", drain)
        self.assertIn("qwen3.6-35B-A3B", drain)
        self.assertIn("coordinator only", drain)
        self.assertNotIn("switch the coordinator configuration", drain)
        self.assertNotIn("distillation path is retired", drain)


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

    def test_default_invoker_forwards_through_the_installed_wrapper(self) -> None:
        # Since the 2026-08-29 GPU migration the default invoker's whole job is
        # to shell out to the `utility-model` wrapper, which forwards to
        # llama-swap. Prove the seam is wired end to end here: the stable id
        # goes out on stdin, the wrapper's stdout comes back as the response,
        # and a real note gets written from it.
        wrapper_dir = self.root / "bin"
        wrapper_dir.mkdir()
        recorded = self.root / "wrapper-request.json"
        wrapper = wrapper_dir / "utility-model"
        wrapper.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "request = json.load(sys.stdin)\n"
            f"open({str(recorded)!r}, 'a').write(json.dumps(request) + '\\n')\n"
            # The distilled JSON is embedded as a JSON *string* literal (which
            # is also a valid Python one), not as a Python expression: the
            # schema carries a boolean since the harvest verb landed, and
            # `false` is not Python.
            "json.dump({'model': 'utility', 'choices': [{'message': "
            "{'role': 'assistant', 'content': "
            f"{json.dumps(json.dumps(result_data()))}"
            "}}]}, sys.stdout)\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)

        trace = copied_trace(
            fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            self.root,
        )
        with mock.patch.dict(
            os.environ,
            {"PATH": f"{wrapper_dir}:{os.environ['PATH']}"},
        ):
            status, note_path = memory.drain_session(
                identity=memory.Identity("claude-code", CLAUDE_ROOT_ID),
                journal_dir=self.journal,
                trace_path=trace,
                now=datetime.fromisoformat("2026-08-29T10:00:00+02:00"),
            )
        self.assertEqual(status, "created")
        self.assertTrue(note_path.is_file())
        forwarded = [
            json.loads(line) for line in recorded.read_text().splitlines() if line
        ]
        self.assertTrue(forwarded)
        self.assertTrue(all(req["model"] == "utility" for req in forwarded))
        self.assertTrue(all(req["stream"] is False for req in forwarded))

    def test_absent_wrapper_fails_closed_naming_the_gpu_seam_not_the_npu(self) -> None:
        # The wrapper is installed on the coordinator alone, so an absent one
        # means "not this host" — it must say that, and it must fail closed
        # through the ordinary bounded MemoryError path: same exit semantics as
        # every other failure, no traceback, no partial note. It must not blame
        # the decommissioned NPU, which has nothing to do with this seam any
        # more, and must not send the session off to change a configuration.
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
        self.assertIn("llama-swap", message)
        self.assertIn("coordinator only", message)
        self.assertNotIn("NPU", message)
        self.assertNotIn("switch the coordinator configuration", message)
        self.assertFalse(list(self.journal.rglob("*.md")))

    def test_a_bounded_seam_failure_exits_one_through_main_without_a_traceback(
        self,
    ) -> None:
        stderr = io.StringIO()
        with mock.patch.object(
            memory,
            "current_identity",
            side_effect=memory.MemoryError(memory.UTILITY_UNAVAILABLE),
        ):
            with contextlib.redirect_stderr(stderr):
                status = memory.main(["drain"])
        self.assertEqual(status, 1)
        self.assertEqual(
            stderr.getvalue(),
            f"ai-memory: {memory.UTILITY_UNAVAILABLE}\n",
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


class HarvestTests(unittest.TestCase):
    """The second verb (MECHANISM-2026-09-07 §6b, D-E07, R-c21).

    Harvest shares drain's identity resolution, trace capture and utility-model
    path and writes to its own store. The journal stays what Tom chose to keep,
    so every case here proves the scratch journal directory is still empty.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.journal = self.root / "journal"
        self.journal.mkdir()
        self.harvest = self.root / "harvest"
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

    def journal_files(self) -> list[Path]:
        return [path for path in self.journal.rglob("*") if path.is_file()]

    def harvest_files(self) -> list[Path]:
        return sorted(path for path in self.harvest.rglob("*") if path.is_file())

    def test_harvest_writes_store_not_journal(self) -> None:
        identity = memory.Identity("claude-code", CLAUDE_ROOT_ID)
        trace = copied_trace(fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID), self.root)

        status, note_path = memory.harvest_session(
            identity=identity,
            harvest_dir=self.harvest,
            trace_path=trace,
            now=datetime.fromisoformat("2026-09-07T21:00:00+02:00"),
            invoker=QueueInvoker(result_data()),
        )

        self.assertEqual(status, "created")
        self.assertEqual(self.harvest_files(), [note_path])
        self.assertEqual(
            note_path,
            self.harvest / f"{CLAUDE_ROOT_ID}.md",
        )
        self.assertEqual(self.journal_files(), [])

        text = note_path.read_text()
        fields, _ = memory.parse_frontmatter(text)
        self.assertEqual(fields["source"], "claude-code")
        self.assertEqual(fields["session_id"], CLAUDE_ROOT_ID)
        self.assertIn("harvested_at", fields)
        self.assertNotIn("drained_at", fields)
        self.assertIn("## Unresolved units", text)
        self.assertNotIn("SECRET_", text)

        # A later harvest of the same session overwrites the one file (D-E07);
        # it never allocates a second, and it still never touches the journal.
        with trace.open("a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    {
                        "type": "user",
                        "sessionId": CLAUDE_ROOT_ID,
                        "isSidechain": False,
                        "timestamp": "2026-09-07T21:05:00+02:00",
                        "message": {
                            "role": "user",
                            "content": "One more root turn before the session ends.",
                        },
                    }
                )
                + "\n"
            )
        status, again = memory.harvest_session(
            identity=identity,
            harvest_dir=self.harvest,
            trace_path=trace,
            now=datetime.fromisoformat("2026-09-07T21:06:00+02:00"),
            invoker=QueueInvoker(result_data(title="a model-proposed rename")),
        )
        self.assertEqual(status, "updated")
        self.assertEqual(again, note_path)
        self.assertEqual(self.harvest_files(), [note_path])
        self.assertEqual(self.journal_files(), [])
        self.assertFalse(list(self.harvest.glob(".ai-memory-*.tmp")))

    def test_model_json_requires_resolved_fields(self) -> None:
        well_formed: dict[str, object] = {
            "title": "harvest verb",
            "group": "memory harvest",
            "thread": "The session added a harvest verb beside the drain.",
            "decisions": ["Harvest writes its own store, never the journal."],
            "candidate_ideas": ["A SessionEnd hook could call the verb."],
            "constraints": ["The drain stays a user-requested verb."],
            "artifacts": ["home/dot_claude/skills/drain/scripts/ai_memory.py"],
            "open_questions": ["Whether the hook lands in the same pull."],
            "resolved": False,
            "unresolved_units": [
                "Add the SessionEnd hook that calls harvest non-interactively."
            ],
        }

        for missing in ("resolved", "unresolved_units"):
            incomplete = {
                key: value for key, value in well_formed.items() if key != missing
            }
            with self.assertRaises(memory.ModelOutputError) as caught:
                memory.validate_model_result(incomplete)
            self.assertIn(missing, str(caught.exception))

        with self.assertRaisesRegex(memory.ModelOutputError, "resolved must be"):
            memory.validate_model_result(dict(well_formed, resolved="yes"))

        result = memory.validate_model_result(well_formed)
        self.assertIs(result.resolved, False)
        self.assertEqual(
            result.unresolved_units,
            ("Add the SessionEnd hook that calls harvest non-interactively.",),
        )

        _, note_path = memory.harvest_session(
            identity=memory.Identity("codex", CODEX_ROOT_ID),
            harvest_dir=self.harvest,
            trace_path=fixture_trace(CODEX_HOME, CODEX_ROOT_ID),
            now=datetime.fromisoformat("2026-09-07T21:10:00+02:00"),
            invoker=QueueInvoker(well_formed),
        )
        text = note_path.read_text()
        self.assertIn("resolved: false", text)
        self.assertIn(
            "## Unresolved units\n\n- Add the SessionEnd hook that calls "
            "harvest non-interactively.",
            text,
        )
        self.assertEqual(self.journal_files(), [])

    def test_a_resolved_session_renders_an_empty_unresolved_list(self) -> None:
        resolved = dict(result_data(), resolved=True, unresolved_units=[])
        _, note_path = memory.harvest_session(
            identity=memory.Identity("claude-code", CLAUDE_ROOT_ID),
            harvest_dir=self.harvest,
            trace_path=fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            now=datetime.fromisoformat("2026-09-07T21:20:00+02:00"),
            invoker=QueueInvoker(resolved),
        )
        text = note_path.read_text()
        self.assertIn("resolved: true", text)
        self.assertIn("## Unresolved units\n\n- None recorded.", text)
        with self.assertRaisesRegex(memory.ModelOutputError, "is not empty"):
            memory.validate_model_result(
                dict(result_data(), resolved=True, unresolved_units=["Still open."])
            )
        self.assertEqual(self.journal_files(), [])

    def test_the_drain_note_is_unchanged_by_the_two_new_fields(self) -> None:
        # R-c21 lifts the prohibition for the harvest store alone: a journal
        # note must render exactly the sections it always did, with no
        # resolution statement in its front matter.
        _, note_path = memory.drain_session(
            identity=memory.Identity("claude-code", CLAUDE_ROOT_ID),
            journal_dir=self.journal,
            trace_path=fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID),
            now=datetime.fromisoformat("2026-09-07T21:30:00+02:00"),
            invoker=QueueInvoker(result_data()),
        )
        text = note_path.read_text()
        fields, body = memory.parse_frontmatter(text)
        self.assertNotIn("resolved", fields)
        self.assertIn("drained_at", fields)
        self.assertNotIn("## Unresolved units", body)
        self.assertEqual(
            tuple(re.findall(r"(?m)^## (.+)$", body)),
            memory.SECTION_NAMES,
        )
        self.assertEqual(self.harvest_files(), [])

    def test_the_verb_is_callable_non_interactively_and_names_its_store(self) -> None:
        # What MEM-2's SessionEnd hook will call: no prompt, a bounded failure
        # on stderr with a non-zero exit, and a default store under the
        # rewrite's state dir, never branch (a)'s ~/.local/state/tally.
        with mock.patch.dict(
            os.environ,
            {"AI_MEMORY_HARVEST_DIR": "", "XDG_STATE_HOME": str(self.root / "state")},
        ):
            os.environ.pop("AI_MEMORY_HARVEST_DIR")
            default = memory.default_harvest_dir()
        self.assertEqual(default, self.root / "state/tally-rewrite/harvest")
        self.assertNotIn("/.local/state/tally/", f"{default}/")

        stderr = io.StringIO()
        with mock.patch.object(
            memory,
            "current_identity",
            side_effect=memory.MemoryError(
                "no current session identity found (expected CLAUDE_CODE_SESSION_ID"
                " or CODEX_THREAD_ID)"
            ),
        ):
            with contextlib.redirect_stderr(stderr):
                status = memory.main(["harvest"])
        self.assertEqual(status, 1)
        self.assertIn("no current session identity found", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        self.assertEqual(self.journal_files(), [])


class HarvestEnqueueTests(unittest.TestCase):
    """MEM-3: one unresolved unit becomes one row in the daemon's shape.

    The rows land under the harvest store's own `enqueue/` directory and are
    validated by `tools/enqueue-row-check.py` before they reach the disk.
    Crossing into `~/.local/state/tally/events/` is a separate act (D-E07), so
    every case here proves the scratch store is the only thing written.
    """

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.harvest = self.root / "harvest"
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.identity = memory.Identity("claude-code", CLAUDE_ROOT_ID)
        self.trace = copied_trace(fixture_trace(CLAUDE_HOME, CLAUDE_ROOT_ID), self.root)
        self.environment = mock.patch.dict(
            os.environ,
            {
                "XDG_RUNTIME_DIR": str(self.runtime),
                "AI_MEMORY_HARVEST_DIR": str(self.harvest),
                "AI_MEMORY_ENQUEUE_CHECK": str(ENQUEUE_CHECK),
            },
        )
        self.environment.start()
        os.environ.pop("ENQUEUE_ROW_CHECK_DROP_KEYS", None)

    def tearDown(self) -> None:
        self.environment.stop()
        self.temporary.cleanup()

    def run_harvest(self, *responses: object) -> tuple[int, str, str]:
        """`ai_memory.py harvest --enqueue`, the argv the mechanism names."""
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(
            memory, "current_identity", return_value=self.identity
        ), mock.patch.object(
            memory, "resolve_trace", return_value=self.trace
        ), mock.patch.object(
            memory, "invoke_utility", QueueInvoker(*responses)
        ):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = memory.main(["harvest", "--enqueue"])
        return status, stdout.getvalue(), stderr.getvalue()

    def rows(self) -> list[Path]:
        return sorted((self.harvest / "enqueue").glob("*.enqueue.json"))

    def hook_log(self) -> Path:
        return self.harvest / "hook.log"

    def test_harvest_enqueue_rows(self) -> None:
        units = [
            "Wire the harvest verb to a SessionEnd hook.",
            "Move a validated harvest row into the daemon's own events dir.",
        ]
        status, stdout, stderr = self.run_harvest(
            dict(result_data(), unresolved_units=units)
        )
        self.assertEqual(status, 0, stderr)
        self.assertIn("created:", stdout)
        self.assertEqual(stderr, "")

        rows = self.rows()
        self.assertEqual(len(rows), 2, [path.name for path in rows])
        self.assertFalse(list((self.harvest / "enqueue").glob(".ai-memory-*.tmp")))
        # Nothing was refused, so the store's ledger has nothing to say.
        self.assertFalse(self.hook_log().exists())

        documents: list[tuple[Path, dict[str, object]]] = []
        for path in rows:
            completed = subprocess.run(
                [sys.executable, str(ENQUEUE_CHECK), str(path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            documents.append((path, json.loads(path.read_text(encoding="utf-8"))))
        documents.sort(key=lambda item: item[1]["row"]["dedupKey"])

        self.assertEqual(
            [document["row"]["dedupKey"] for _, document in documents],
            [f"harvest:{CLAUDE_ROOT_ID}:1", f"harvest:{CLAUDE_ROOT_ID}:2"],
        )
        self.assertEqual(
            [document["row"]["description"] for _, document in documents], units
        )

        seen_ids = set()
        for path, document in documents:
            row = document["row"]
            self.assertEqual(path.name, f"{document['eventId']}.enqueue.json")
            self.assertEqual(document["schemaVersion"], 1)
            self.assertIs(document["acknowledged"], False)
            seen_ids.add(document["eventId"])
            self.assertEqual(row["rowVersion"], 5)
            self.assertEqual(row["priority"], "low")
            self.assertEqual(row["source"], "harvest")
            self.assertEqual(row["adapter"], "ai-memory")
            self.assertEqual(row["pool"], ["harvest"])
            self.assertEqual(row["sessionRef"], CLAUDE_ROOT_ID)
            # Nothing about a harvested row runs anything.
            self.assertEqual(row["argv"], [])
            self.assertIs(row["noEnqueue"], True)
            self.assertEqual(
                row["origin"], {"schemaVersion": 1, "source": "harvest"}
            )
            self.assertRegex(row["payloadHash"], r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(row["briefHash"], r"^sha256:[0-9a-f]{64}$")
            self.assertNotIn("/.local/state/tally/", f"{path}")
        self.assertEqual(len(seen_ids), 2)

        # A second harvest of an unchanged session enqueues nothing again.
        status, _, stderr = self.run_harvest(dict(result_data(), unresolved_units=units))
        self.assertEqual(status, 0, stderr)
        self.assertEqual(self.rows(), rows)

    def test_harvest_enqueue_without_the_override_finds_the_validator(self) -> None:
        """FIX-E08: the fallback path, with AI_MEMORY_ENQUEUE_CHECK UNSET.

        Every other green in this tree sets the override, which is exactly how
        the off-by-two `parents[3]` survived: nothing exercised the fallback. The
        engine's own file is stood up in a synthetic tree whose repository root
        holds `tools/enqueue-row-check.py`, so the walk-up is what has to find
        it — five levels up, the live checkout's own shape.
        """
        tree = self.root / "checkout"
        scripts = tree / "home/dot_claude/skills/drain/scripts"
        scripts.mkdir(parents=True)
        validator = tree / "tools/enqueue-row-check.py"
        validator.parent.mkdir(parents=True)
        validator.write_text(ENQUEUE_CHECK.read_text(encoding="utf-8"), encoding="utf-8")
        engine_copy = scripts / "ai_memory.py"
        engine_copy.write_text("# a stand-in for this engine's own file\n", encoding="utf-8")

        units = ["Prove the enqueue validator is found without the override."]
        with mock.patch.object(memory, "__file__", str(engine_copy)):
            os.environ.pop("AI_MEMORY_ENQUEUE_CHECK", None)
            self.assertEqual(memory.enqueue_check_path(), validator.resolve())
            status, stdout, stderr = self.run_harvest(
                dict(result_data(), unresolved_units=units)
            )
        self.assertEqual(status, 0, stderr)
        self.assertIn("created:", stdout)
        rows = self.rows()
        self.assertEqual(len(rows), 1, [path.name for path in rows])
        document = json.loads(rows[0].read_text(encoding="utf-8"))
        self.assertEqual(document["row"]["description"], units[0])

    def test_the_validator_search_names_itself_when_nothing_is_found(self) -> None:
        """No ancestor holds it: the failure names the search, not a level count."""
        orphan = self.root / "orphan/scripts/ai_memory.py"
        orphan.parent.mkdir(parents=True)
        orphan.write_text("# no tools/ above this\n", encoding="utf-8")
        os.environ.pop("AI_MEMORY_ENQUEUE_CHECK", None)
        with self.assertRaises(memory.MemoryError) as caught:
            memory.enqueue_check_path(orphan)
        message = str(caught.exception)
        self.assertIn("no tools/enqueue-row-check.py above", message)
        self.assertIn(str(orphan.resolve()), message)
        self.assertIn("AI_MEMORY_ENQUEUE_CHECK", message)

    def test_harvest_enqueue_refuses_malformed(self) -> None:
        # The seam belongs to the validator: it drops the named key from the
        # document it is handed, so the refusal is driven with a row the writer
        # built correctly rather than with a hand-forged file.
        with mock.patch.dict(os.environ, {"ENQUEUE_ROW_CHECK_DROP_KEYS": "eventId"}):
            status, _, stderr = self.run_harvest(result_data())

            self.assertEqual(status, 1)
            self.assertIn("enqueue refused 1 row", stderr)
            self.assertIn("eventId is missing", stderr)
            self.assertNotIn("Traceback", stderr)

            # No file is written — not the row, and not a temporary beside it.
            self.assertEqual(self.rows(), [])
            enqueue_dir = self.harvest / "enqueue"
            self.assertFalse(
                enqueue_dir.exists() and any(enqueue_dir.iterdir()),
                sorted(enqueue_dir.glob("*")) if enqueue_dir.exists() else [],
            )

            # The refusal is one line in the harvest store's own hook.log.
            lines = self.hook_log().read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1, lines)
            self.assertIn(f"session=claude-code:{CLAUDE_ROOT_ID}", lines[0])
            self.assertIn("enqueue=refused unit=1", lines[0])
            self.assertIn("eventId is missing", lines[0])

            # The note itself still stands: only the row was refused.
            self.assertTrue((self.harvest / f"{CLAUDE_ROOT_ID}.md").is_file())

            # And the validator's own argv refuses the same document, rc 1.
            document = memory.enqueue_row_document(
                identity=self.identity,
                unit="One unresolved unit, stated in one sentence.",
                ordinal=1,
                event_id="33333333-3333-4333-8333-333333333333",
                row_uuid="44444444-4444-4444-8444-444444444444",
            )
            probe = self.root / f"{document['eventId']}.enqueue.json"
            probe.write_text(json.dumps(document), encoding="utf-8")
            refused = subprocess.run(
                [sys.executable, str(ENQUEUE_CHECK), str(probe)],
                capture_output=True,
                text=True,
                env=dict(os.environ),
            )
        self.assertEqual(refused.returncode, 1, refused.stderr)
        self.assertIn("eventId is missing", refused.stderr)

        # The seam is the only thing that made it malformed.
        kept = subprocess.run(
            [sys.executable, str(ENQUEUE_CHECK), str(probe)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(kept.returncode, 0, kept.stderr)

    def test_the_row_store_is_the_harvest_store_not_the_live_events_dir(self) -> None:
        # D-E07: one override moves the notes, the rows and the ledger
        # together, and no default here can reach branch (a)'s live state dir.
        with mock.patch.dict(
            os.environ, {"XDG_STATE_HOME": str(self.root / "state")}
        ):
            os.environ.pop("AI_MEMORY_HARVEST_DIR")
            store = memory.default_harvest_dir()
        self.assertEqual(
            memory.enqueue_dir(store),
            self.root / "state/tally-rewrite/harvest/enqueue",
        )
        self.assertEqual(
            memory.hook_log_path(store),
            self.root / "state/tally-rewrite/harvest/hook.log",
        )
        self.assertNotIn("/.local/state/tally/", f"{memory.enqueue_dir(store)}/")

    def test_the_shape_is_the_live_daemons_and_a_real_row_passes(self) -> None:
        # The required keys are taken from a real row, so a real row passes.
        validator = memory.load_enqueue_validator()
        exemplar = {
            "schemaVersion": 1,
            "eventId": "fffe9574-e63d-440f-8198-212bad9d4ec0",
            "acknowledged": True,
            "guardrailDepth": 1,
            "row": {
                "rowVersion": 5,
                "uuid": "019ffbbe-bbb8-7093-bedb-8b8c2d887881",
                "description": "spec-build-driver steeringRecheck",
                "priority": "low",
                "source": "orchestrator",
                "adapter": "spec-build-driver",
                "pool": ["campaign-control"],
                "model": None,
                "cwd": None,
                "dedupKey": "flow:019ffbb8-837e-7b13-a0e1-bd899e1d927d:k:gate",
                "payloadHash": "sha256:" + "5a" * 32,
                "briefHash": "sha256:" + "41" * 32,
                "sessionRef": None,
                "jobTokenHash": "sha256:" + "00" * 32,
                "leaseEpoch": 12,
                "attempt": 1,
                "argv": ["spec-build-driver", "steeringRecheck"],
                "evidence": ["exit:0"],
                "parentUuid": "019ffbb8-837e-7b13-a0e1-bd899e1d927d",
                "consumptionEstimate": None,
                "runtimeMaxSec": 900,
                "noEnqueue": True,
                "credentials": {},
                "origin": {"schemaVersion": 1, "source": "orchestrator"},
                "ghOrigin": None,
                "relatedTrigger": None,
                "evidenceClass": None,
                "manifestHash": None,
            },
        }
        self.assertEqual(validator.validate_document(exemplar), [])

        for key in ("eventId", "schemaVersion", "row"):
            missing = {k: v for k, v in exemplar.items() if k != key}
            self.assertIn(f"{key} is missing", validator.validate_document(missing))
        for key in ("dedupKey", "argv", "noEnqueue", "origin", "priority"):
            row = {k: v for k, v in exemplar["row"].items() if k != key}
            self.assertIn(
                f"row.{key} is missing",
                validator.validate_document(dict(exemplar, row=row)),
            )


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
