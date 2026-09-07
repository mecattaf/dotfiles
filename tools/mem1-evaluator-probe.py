#!/usr/bin/env python3
"""MEM-1's mechanical evaluator's own probe (grading procedure step 2b).

Not the card's clauses — the floor beneath them. MEM-1's oracle calls
`harvest_session()` in-process with a stub invoker; nothing in it ever runs the
verb the way MEM-2's SessionEnd hook will run it: as a process, with a real
`utility-model` wrapper on PATH, a real `CLAUDE_CONFIG_DIR` to resolve the
trace out of, and a real state directory to land in. Six hermetic cases, each
in its own scratch tree, no network and no GPU:

  P1  the CLI writes exactly one file under AI_MEMORY_HARVEST_DIR, named for
      the session, and ZERO files under the scratch journal dir named by the
      ai-memory config AND zero under a scratch ~/.local/state/tally (branch
      (a)'s fenced live dir, which no code path here may reach).
  P2  a second run over an unchanged trace short-circuits to `unchanged` and
      invokes the utility model ZERO extra times (D-E13(5): a hook that fires
      twice must not pay for a second cold load). A third run, after the trace
      grows, re-invokes and overwrites the SAME file in place.
  P3  store recreation: rm -rf the harvest dir between two runs; the verb
      recreates it and leaves exactly one file, with no stale temp file.
  P4  two harvests of the same session at once: SessionLock serialises them,
      both exit 0, and exactly one note exists at the end.
  P5  a child session refuses non-interactively — rc non-zero, the reason on
      stderr, no traceback, and nothing written to either store.
  P6  with XDG_STATE_HOME and AI_MEMORY_HARVEST_DIR both unset the default
      store is <home>/.local/state/tally-rewrite/harvest and is NOT under
      <home>/.local/state/tally/ (D-E07's fence, measured on the default path
      rather than on the overridden one the unit tests exercise).

Usage: python3 tools/mem1-evaluator-probe.py [--engine PATH]
Exit 0 iff every case holds; 1 with the failing case named.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = REPO / "home/dot_claude/skills/drain/scripts/ai_memory.py"
FIXTURES = REPO / "tests/ai-memory/fixtures"
ROOT_ID = "11111111-1111-4111-8111-111111111111"
CHILD_ID = "22222222-2222-4222-8222-222222222222"

DISTILLED = {
    "title": "the evaluator's probe",
    "group": "memory harvest",
    "thread": "A probe ran the harvest verb as a process.",
    "decisions": ["The harvest store is not the journal."],
    "candidate_ideas": ["A SessionEnd hook calls this verb."],
    "constraints": ["Never write branch (a)'s live state dir."],
    "artifacts": ["tools/mem1-evaluator-probe.py"],
    "open_questions": ["Whether the hook lands in the same pull."],
    "resolved": False,
    "unresolved_units": ["Wire the SessionEnd hook that calls harvest."],
}

failures: list[str] = []


def check(case: str, condition: bool, detail: str) -> None:
    mark = "ok  " if condition else "FAIL"
    print(f"  [{mark}] {case}: {detail}")
    if not condition:
        failures.append(f"{case}: {detail}")


class Scratch:
    """One hermetic tree: a copied Claude config dir, a stub wrapper, a fence."""

    def __init__(self, stack: list[tempfile.TemporaryDirectory]) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        stack.append(self.tmp)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.claude = self.root / "claude-config"
        shutil.copytree(FIXTURES / "claude", self.claude)
        self.harvest = self.root / "state/tally-rewrite/harvest"
        self.journal = self.root / "journal"
        self.journal.mkdir(parents=True)
        # branch (a)'s live dir, created empty: nothing may ever land here.
        self.fenced = self.root / "home/.local/state/tally"
        self.fenced.mkdir(parents=True)
        self.runtime = self.root / "run"
        self.runtime.mkdir(mode=0o700)
        config = self.root / "config/ai-memory/config.json"
        config.parent.mkdir(parents=True)
        config.write_text(
            json.dumps({"schema": 1, "journal_dir": str(self.journal)}),
            encoding="utf-8",
        )
        self.calls = self.root / "wrapper-calls.jsonl"
        bindir = self.root / "bin"
        bindir.mkdir()
        wrapper = bindir / "utility-model"
        wrapper.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "json.load(sys.stdin)\n"
            f"open({str(self.calls)!r}, 'a').write('1\\n')\n"
            "json.dump({'model': 'utility', 'choices': [{'message': "
            "{'role': 'assistant', 'content': "
            f"{json.dumps(json.dumps(DISTILLED))}"
            "}}]}, sys.stdout)\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)
        self.bindir = bindir

    def env(self, **extra: str) -> dict[str, str]:
        env = dict(os.environ)
        env.pop("CODEX_THREAD_ID", None)
        env.pop("CLAUDE_CODE_CHILD_SESSION", None)
        env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.bindir}:{os.environ['PATH']}",
                "CLAUDE_CONFIG_DIR": str(self.claude),
                "CLAUDE_CODE_SESSION_ID": ROOT_ID,
                "AI_MEMORY_HARVEST_DIR": str(self.harvest),
                "XDG_CONFIG_HOME": str(self.root / "config"),
                "XDG_RUNTIME_DIR": str(self.runtime),
            }
        )
        env.update(extra)
        return env

    def invocations(self) -> int:
        return len(self.calls.read_text().splitlines()) if self.calls.is_file() else 0

    def harvest_files(self) -> list[Path]:
        if not self.harvest.exists():
            return []
        return sorted(p for p in self.harvest.rglob("*") if p.is_file())

    def journal_files(self) -> list[Path]:
        return sorted(p for p in self.journal.rglob("*") if p.is_file())

    def fenced_files(self) -> list[Path]:
        return sorted(p for p in self.fenced.rglob("*") if p.is_file())

    def trace(self) -> Path:
        return self.claude / "projects/-synthetic" / f"{ROOT_ID}.jsonl"

    def grow_trace(self, text: str, stamp: str) -> None:
        with self.trace().open("a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    {
                        "type": "user",
                        "sessionId": ROOT_ID,
                        "isSidechain": False,
                        "timestamp": stamp,
                        "message": {"role": "user", "content": text},
                    }
                )
                + "\n"
            )


def run(engine: Path, scratch: Scratch, *, env_extra: dict[str, str] | None = None):
    return subprocess.run(
        [sys.executable, str(engine), "harvest"],
        env=scratch.env(**(env_extra or {})),
        cwd=str(scratch.root),
        text=True,
        capture_output=True,
        timeout=120,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    args = parser.parse_args()
    engine = args.engine.resolve()
    print(f"engine: {engine}")
    stack: list[tempfile.TemporaryDirectory] = []

    # ---- P1 / P2 share one tree: the same session harvested three times. ----
    s = Scratch(stack)
    print("P1  the CLI writes the store and neither journal nor the fence")
    first = run(engine, s)
    check("P1", first.returncode == 0, f"rc={first.returncode} err={first.stderr[:200]!r}")
    files = s.harvest_files()
    check("P1", len(files) == 1, f"harvest files={[p.name for p in files]}")
    check(
        "P1",
        bool(files) and files[0].name == f"{ROOT_ID}.md",
        f"note named for the session: {files[0].name if files else '<none>'}",
    )
    check("P1", s.journal_files() == [], f"journal files={s.journal_files()}")
    check("P1", s.fenced_files() == [], f"~/.local/state/tally files={s.fenced_files()}")
    body = files[0].read_text() if files else ""
    check("P1", "harvested_at:" in body, "front matter says harvested_at")
    check("P1", "drained_at:" not in body, "front matter does not say drained_at")
    check("P1", "resolved: false" in body, "resolved rendered unquoted")
    check("P1", "## Unresolved units" in body, "the section is present")
    check("P1", first.stdout.startswith("created: "), f"stdout={first.stdout.strip()!r}")

    print("P2  an unchanged trace short-circuits without a second model call")
    calls_after_first = s.invocations()
    check("P2", calls_after_first >= 1, f"the first run called the model {calls_after_first}x")
    second = run(engine, s)
    check("P2", second.returncode == 0, f"rc={second.returncode} err={second.stderr[:200]!r}")
    check(
        "P2",
        second.stdout.startswith("unchanged: "),
        f"stdout={second.stdout.strip()!r}",
    )
    check(
        "P2",
        s.invocations() == calls_after_first,
        f"model invocations {calls_after_first} -> {s.invocations()} (must not grow)",
    )
    check("P2", len(s.harvest_files()) == 1, f"still one file: {len(s.harvest_files())}")
    s.grow_trace("One more root turn before the session ends.", "2026-09-07T21:05:00+02:00")
    third = run(engine, s)
    check("P2", third.returncode == 0, f"rc={third.returncode} err={third.stderr[:200]!r}")
    check("P2", third.stdout.startswith("updated: "), f"stdout={third.stdout.strip()!r}")
    check("P2", s.invocations() > calls_after_first, "a grown trace re-invokes the model")
    check(
        "P2",
        [p.name for p in s.harvest_files()] == [f"{ROOT_ID}.md"],
        f"overwritten in place: {[p.name for p in s.harvest_files()]}",
    )
    check("P2", s.journal_files() == [], "journal still empty after three runs")
    check("P2", s.fenced_files() == [], "the fence still empty after three runs")

    # ---- P3 store recreation ----
    print("P3  the store is recreated after it is removed")
    s3 = Scratch(stack)
    check("P3", run(engine, s3).returncode == 0, "first run rc 0")
    shutil.rmtree(s3.harvest, ignore_errors=True)
    check("P3", not s3.harvest.exists(), "store removed")
    again = run(engine, s3)
    check("P3", again.returncode == 0, f"rc={again.returncode} err={again.stderr[:200]!r}")
    check("P3", again.stdout.startswith("created: "), f"stdout={again.stdout.strip()!r}")
    check("P3", len(s3.harvest_files()) == 1, f"one file: {len(s3.harvest_files())}")
    check(
        "P3",
        list(s3.harvest.glob(".ai-memory-*.tmp")) == [],
        "no stale temp file left behind",
    )

    # ---- P4 two harvests at once ----
    print("P4  two concurrent harvests of one session serialise on the lock")
    s4 = Scratch(stack)
    with ThreadPoolExecutor(max_workers=2) as pool:
        both = [f.result() for f in [pool.submit(run, engine, s4) for _ in range(2)]]
    rcs = [p.returncode for p in both]
    check("P4", all(rc == 0 for rc in rcs), f"rcs={rcs} err={[p.stderr[:120] for p in both]}")
    check("P4", len(s4.harvest_files()) == 1, f"exactly one note: {len(s4.harvest_files())}")
    check(
        "P4",
        sorted(p.stdout.split(":")[0] for p in both) == ["created", "unchanged"],
        f"one wrote, one saw it unchanged: {[p.stdout.strip() for p in both]}",
    )
    check("P4", s4.journal_files() == [], "journal empty")

    # ---- P5 a child session refuses ----
    print("P5  a child session refuses with a reason and writes nothing")
    s5 = Scratch(stack)
    child = run(
        engine,
        s5,
        env_extra={"CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_SESSION_ID": CHILD_ID},
    )
    check("P5", child.returncode != 0, f"rc={child.returncode}")
    check("P5", "root" in child.stderr.lower(), f"stderr={child.stderr.strip()[:200]!r}")
    check("P5", "Traceback" not in child.stderr, "no traceback on stderr")
    check("P5", s5.harvest_files() == [], "harvest store empty")
    check("P5", s5.journal_files() == [], "journal empty")
    check("P5", s5.fenced_files() == [], "the fence empty")

    # ---- P6 the default store, unoverridden ----
    print("P6  the default store is the rewrite's dir, never branch (a)'s")
    s6 = Scratch(stack)
    env = s6.env()
    env.pop("AI_MEMORY_HARVEST_DIR")
    env.pop("XDG_STATE_HOME", None)
    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import importlib.util,sys;"
            f"spec=importlib.util.spec_from_file_location('m',{str(engine)!r});"
            "m=importlib.util.module_from_spec(spec);sys.modules['m']=m;"
            "spec.loader.exec_module(m);print(m.default_harvest_dir())",
        ],
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
    )
    default = probe.stdout.strip()
    check("P6", probe.returncode == 0, f"rc={probe.returncode} err={probe.stderr[:200]!r}")
    check(
        "P6",
        default == str(s6.home / ".local/state/tally-rewrite/harvest"),
        f"default store = {default}",
    )
    check("P6", "/.local/state/tally/" not in f"{default}/", "not under the fenced dir")

    for tmp in stack:
        tmp.cleanup()

    print()
    if failures:
        print(f"RED — {len(failures)} check(s) failed:")
        for line in failures:
            print(f"  - {line}")
        return 1
    print("GREEN — every case holds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
