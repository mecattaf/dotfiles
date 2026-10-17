"""Unit tests for pkgs/memory-sweep/memory_sweep.py: pure functions and the
process-level guards. No network, no podman, no GPU, no model. Runs under
`nix build .#checks.x86_64-linux.memory-sweep` and, outside nix, under
`runtime-test -- python3 -m unittest discover -s tests/memory-sweep`."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("MEMORY_SWEEP_SCRIPT", REPO_ROOT / "pkgs/memory-sweep/memory_sweep.py"))
ENGINE = Path(os.environ.get("MEMORY_SWEEP_AI_MEMORY", REPO_ROOT / "home/dot_claude/skills/drain/scripts/ai_memory.py"))
SERVE = Path(os.environ.get("MEMORY_SWEEP_SERVE", REPO_ROOT / "pkgs/memory-sweep/hy-memory-serve.sh"))
TEMPLATE = Path(os.environ.get("MEMORY_SWEEP_TEMPLATE", REPO_ROOT / "pkgs/memory-sweep/tdai-gateway.template.yaml"))
FIXTURES = Path(__file__).parent / "fixtures"
NOTES = FIXTURES / "notes"
ARCHIVES = FIXTURES / "archives"

os.environ["MEMORY_SWEEP_AI_MEMORY"] = str(ENGINE)

spec = importlib.util.spec_from_file_location("memory_sweep", SCRIPT)
assert spec is not None and spec.loader is not None
sweep = importlib.util.module_from_spec(spec)
sys.modules["memory_sweep"] = sweep
spec.loader.exec_module(sweep)


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def run_cli(*argv: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    full_env = dict(os.environ)
    full_env.update(env or {})
    return subprocess.run([sys.executable, str(SCRIPT), *argv], capture_output=True, text=True, env=full_env, check=False)


class SamplingTests(unittest.TestCase):
    def test_sample_excludes_sensitive(self) -> None:
        population = sweep.eligible_notes(NOTES, "all")
        rel = {str(p.relative_to(NOTES)) for p in population}
        self.assertTrue(rel, "fixture population is empty")
        for forbidden in ("estate", "learnings", "deferred", "big.md", "tiny.md", ".env"):
            self.assertFalse(any(forbidden in r for r in rel), f"{forbidden} leaked into {rel}")
        for seed in range(25):
            for path in sweep.sample(population, 3, seed):
                text = path.read_text()
                self.assertNotIn("SECRET_", text)

    def test_sample_is_deterministic(self) -> None:
        population = sweep.eligible_notes(NOTES, "all")
        first = sweep.sample(population, 3, 7)
        second = sweep.sample(population, 3, 7)
        self.assertEqual(first, second)
        self.assertTrue(any(sweep.sample(population, 3, s) != first for s in range(1, 40)))

    def test_own_scope_is_a_subset(self) -> None:
        own = set(sweep.eligible_notes(NOTES, "own"))
        everything = set(sweep.eligible_notes(NOTES, "all"))
        self.assertTrue(own <= everything)
        self.assertTrue(all("knowledge" not in str(p) for p in own))

    def test_chats_skip_pi_and_subagents(self) -> None:
        population, skipped = sweep.eligible_chats(ARCHIVES)
        rel = [str(p.relative_to(ARCHIVES)) for p in population]
        self.assertEqual(len(rel), 3)
        self.assertFalse(any("subagents" in r or "pi-mirror" in r for r in rel))
        self.assertEqual(skipped["pi"], 1)
        self.assertEqual(skipped["subagents"], 1)
        sources = {sweep.chat_source(Path(r)) for r in rel}
        self.assertEqual(sources, {"claude-code", "codex"})


class PayloadTests(unittest.TestCase):
    def test_note_chunks_bounded(self) -> None:
        chunks = sweep.chunk_note(NOTES / "journal/2026-07-03-long-note.md", NOTES)
        self.assertGreaterEqual(len(chunks), 2)
        self.assertLessEqual(len(chunks), sweep.MAX_NOTE_CHUNKS)
        for chunk in chunks:
            self.assertLessEqual(len(chunk), sweep.NOTE_CHUNK_CHARS)
            self.assertTrue(chunk.startswith("Note journal/2026-07-03-long-note.md, modified "), chunk[:80])

    def test_claude_turns_via_normaliser(self) -> None:
        engine = sweep.load_engine()
        path = ARCHIVES / "claude-code-mirror/claude/projects/-synthetic/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl"
        rounds = sweep.chat_rounds(path, "claude-code", engine, max_turns=60)
        messages = [m for r in rounds for m in r]
        text = "\n".join(m["content"] for m in messages)
        self.assertNotIn("SECRET_", text)
        self.assertNotIn("<system-reminder>", text)
        self.assertIn("Read", text)  # the tool_use folded into the assistant turn
        self.assertTrue(all(len(m["content"]) <= sweep.MESSAGE_CHARS for m in messages))
        self.assertLessEqual(len(messages), 60)
        self.assertEqual(len(sweep.chat_rounds(path, "claude-code", engine, max_turns=2)[0]), 2)
        self.assertEqual(sum(len(r) for r in sweep.chat_rounds(path, "claude-code", engine, max_turns=2)), 2)

    def test_codex_turns_via_normaliser(self) -> None:
        engine = sweep.load_engine()
        path = next((ARCHIVES / "codex-mirror/sessions").rglob("*.jsonl"))
        rounds = sweep.chat_rounds(path, "codex", engine, max_turns=60)
        messages = [m for r in rounds for m in r]
        text = "\n".join(m["content"] for m in messages)
        self.assertNotIn("SECRET_", text)
        self.assertIn("never rawa", text.lower())
        self.assertEqual(messages[0]["role"], "user")

    def test_rounds_shape(self) -> None:
        engine = sweep.load_engine()
        for path in sweep.eligible_chats(ARCHIVES)[0]:
            source = sweep.chat_source(path.relative_to(ARCHIVES))
            for rnd in sweep.chat_rounds(path, source, engine, max_turns=60):
                self.assertIn(len(rnd), (1, 2))
                for message in rnd:
                    self.assertIn(message["role"], ("user", "assistant"))
                    self.assertIsInstance(message["timestamp"], str)
                if len(rnd) == 2:
                    self.assertEqual([m["role"] for m in rnd], ["user", "assistant"])

    def test_yaml_render(self) -> None:
        rendered = sweep.render_yaml(TEMPLATE.read_text(), "http://127.0.0.1:8081/v1", "hy-memory", "chat", 8420)
        for needle in ("promptMode: chat", "provider: none", "language: en", "baseUrl: http://127.0.0.1:8081/v1", "model: hy-memory", "apiKey: sk-local", "port: 8420"):
            self.assertIn(needle, rendered)
        self.assertNotIn("{{", rendered)
        hosts = {line.split("http://", 1)[1].split("/")[0].split(":")[0] for line in rendered.splitlines() if "http://" in line}
        self.assertEqual(hosts, {"127.0.0.1"})


class GuardTests(unittest.TestCase):
    def test_run_dir_guard(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_nas = Path(tmp) / "mnt-nas"
            fake_nas.mkdir()
            env = {"MEMORY_SWEEP_FORBIDDEN_ROOTS": str(fake_nas), "HOME": tmp, "XDG_STATE_HOME": str(Path(tmp) / "state")}
            cases = {
                "notes": NOTES / "journal" / "run",
                "nas": fake_nas / "run",
                "archives": ARCHIVES / "run",
            }
            for label, run_dir in cases.items():
                result = run_cli("run", "--dry-run", "--notes-root", str(NOTES), "--archives-root", str(ARCHIVES), "--run-dir", str(run_dir), env=env)
                self.assertEqual(result.returncode, 2, (label, result.stderr))
                self.assertIn("REFUSING", result.stderr)
                self.assertIn(str(run_dir), result.stderr)
                self.assertFalse(run_dir.exists(), label)

    def test_dry_run_writes_only_run_dir(self) -> None:
        before_notes = tree_digest(NOTES)
        before_archives = tree_digest(ARCHIVES)
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "state" / "memory-sweep" / "r1"
            env = {"MEMORY_SWEEP_FORBIDDEN_ROOTS": "", "HOME": tmp, "XDG_STATE_HOME": str(Path(tmp) / "state")}
            result = run_cli(
                "run", "--dry-run", "--notes-n", "3", "--chats-n", "3", "--seed", "3",
                "--notes-root", str(NOTES), "--archives-root", str(ARCHIVES), "--run-dir", str(run_dir), env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((run_dir / "plan.json").exists())
            payloads = sorted((run_dir / "payloads").glob("*.json"))
            self.assertEqual(len(payloads), 6, [p.name for p in payloads])
            plan = json.loads((run_dir / "plan.json").read_text())
            self.assertEqual(plan["skipped"]["pi"], 1)
            for payload in payloads:
                body = json.loads(payload.read_text())
                self.assertNotIn("SECRET_", json.dumps(body))
                for rnd in body["conversations"]:
                    for message in rnd:
                        self.assertLessEqual(len(message["content"]), sweep.MESSAGE_CHARS)
            self.assertEqual(sorted(p.name for p in run_dir.iterdir()), ["payloads", "plan.json"])
        self.assertEqual(tree_digest(NOTES), before_notes)
        self.assertEqual(tree_digest(ARCHIVES), before_archives)

    def test_plan_prints_without_model(self) -> None:
        result = run_cli("plan", "--notes-n", "2", "--chats-n", "2", "--notes-root", str(NOTES), "--archives-root", str(ARCHIVES))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("notes:", result.stdout)
        self.assertIn("chats:", result.stdout)
        self.assertNotIn("SECRET_", result.stdout)
        self.assertNotIn("estate", result.stdout)


class ReportTests(unittest.TestCase):
    def test_report_renders_without_model(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "seed-run"
            shutil.copytree(FIXTURES / "seed-run", run_dir)
            report = sweep.render_report(run_dir)
            self.assertIn("## Sample", report)
            self.assertIn("## Atoms", report)
            self.assertIn("MEASURED", report)
            self.assertIn("Total atoms 3", report)
            self.assertIn('"persona": 1', report)
            self.assertIn("Prompt tokens 1000", report)
            self.assertIn("note-01-first", report)
            self.assertIn("pi sessions: 1", report)


class ServeWrapperTests(unittest.TestCase):
    def run_serve(self, *argv: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        full = dict(os.environ)
        full.update(env)
        return subprocess.run(["bash", str(SERVE), *argv], capture_output=True, text=True, env=full, check=False)

    def test_serve_wrapper_refuses_hf(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "llama-server"
            # An absolute shebang: the Nix sandbox has no /usr/bin/env.
            fake.write_text(f"#!{shutil.which('bash')}\nprintf '%s\\n' \"$@\"\n")
            fake.chmod(0o755)
            model = Path(tmp) / "model.gguf"
            model.write_bytes(b"GGUF" * 64)
            (Path(tmp) / "chat_template.jinja").write_text("{{ messages }}")
            env = {"MEMORY_SWEEP_LLAMA_SERVER": str(fake), "MODEL": str(model), "HY_MEMORY_SKIP_MEMCHECK": "1"}

            for flag in ("-hf", "--hf-repo", "--hf-repo=x/y", "--hf-file"):
                result = self.run_serve(flag, "x", env=env)
                self.assertEqual(result.returncode, 2, (flag, result.stderr))
                self.assertIn("REFUSING", result.stderr)

            missing = self.run_serve(env=dict(env, MODEL=str(Path(tmp) / "absent.gguf")))
            self.assertEqual(missing.returncode, 2)
            self.assertIn("local-models-borrow", missing.stderr)

            ok = self.run_serve(env=env)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            argv = ok.stdout.splitlines()
            self.assertIn("--jinja", argv)
            self.assertIn('{"reasoning_effort":"no_think"}', argv)
            self.assertIn("32768", argv)
            self.assertIn("8081", argv)
            self.assertIn("127.0.0.1", argv)
            self.assertFalse(any(a.startswith("-hf") or a.startswith("--hf") for a in argv))

            helped = self.run_serve("--help", env=env)
            self.assertEqual(helped.returncode, 0)
            self.assertIn("usage:", helped.stdout)


if __name__ == "__main__":
    unittest.main()
