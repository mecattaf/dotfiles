#!/usr/bin/env python3
"""memory-sweep-sample: a bounded, hand-run trial of a memory writer.

N markdown files from ~/notes plus N chat jsonl from ~/archives/*-mirror are
run once through TencentDB-Agent-Memory's MemoryCore (the published image by
digest, podman, SQLite, embeddings off) behind the Hy-Memory writer served by
`hy-memory-serve`. Everything the command writes lands under one run directory
(default ~/.local/state/memory-sweep/<run-id>/). Nothing is scheduled; nothing
is written into ~/notes, ~/archives, /mnt/nas or ~/rawa; inputs are opened
read-only. See docs/local-ai/memory-sweep-sample.md and DECISIONS.md 2026-10-17.

Verbs:
  plan            sample and print the N + N files; no model, no container
  run             the whole experiment (--dry-run stops after the payloads)
  report <run-id> re-render report.md from what the run directory holds
  clean <run-id>  delete that run directory (and only that)

Stdlib only. The chat normaliser is the drain skill's ai_memory.py, imported
from MEMORY_SWEEP_AI_MEMORY; there is no second jsonl parser here.
"""

from __future__ import annotations

import argparse
import atexit
import hashlib
import importlib.util
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

DEFAULT_SEED = 20261017
NOTE_CHUNK_CHARS = 8000
MESSAGE_CHARS = 8192
MAX_NOTE_CHUNKS = 6
NOTE_MIN_BYTES = 200
NOTE_MAX_BYTES = 512 * 1024
CHAT_MAX_BYTES = 20 * 1024 * 1024
BATCH_MESSAGES = 100

NOTES_SCOPE_ALL = (
    "journal",
    "references/continuity",
    "references/knowledge",
    "references/devlogs",
    "references/archive",
    "references/personal",
)
NOTES_SCOPE_OWN = ("journal", "references/continuity", "references/personal")
# Any path with one of these parts is never sampled, whatever the scope.
EXCLUDED_PARTS = frozenset({".git", "crm", "dotfiles", "learnings", "deferred", "estate", "subagents"})

QUICKSTART_SYSTEM_PROMPT = (
    "Extract explicit user facts and preferences from the conversation. Write "
    "each memory as a concise, self-contained statement. Do not infer or invent "
    "information. Return only a JSON object with a 'memories' list of strings."
)
PROBE_DIALOGUE = [
    {"role": "user", "content": "I moved my notes to a plain markdown folder last spring and I prefer to read them on paper."},
    {"role": "assistant", "content": "Noted: markdown notes since spring, read on paper."},
]

EXIT_REFUSED = 2


class Refused(SystemExit):
    def __init__(self, message: str) -> None:
        print(f"memory-sweep-sample: REFUSING: {message}", file=sys.stderr)
        super().__init__(EXIT_REFUSED)


# ── small helpers ──────────────────────────────────────────────────────────


def utc_stamp(now: datetime | None = None) -> str:
    now = now or datetime.now(timezone.utc)
    return now.strftime("%Y%m%dT%H%M%SZ")


def iso_mtime(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def slug(text: str, limit: int = 48) -> str:
    text = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return text[:limit] or "x"


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def state_root() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "memory-sweep"


def default_forbidden_roots() -> list[Path]:
    raw = os.environ.get("MEMORY_SWEEP_FORBIDDEN_ROOTS")
    if raw is not None:
        return [Path(p) for p in raw.split(":") if p]
    home = Path.home()
    return [Path("/mnt/nas"), home / "rawa", home / "mecattaf" / "dotfiles"]


def is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def guard_run_dir(run_dir: Path, notes_root: Path, archives_root: Path, forbidden: list[Path]) -> None:
    """D8: the run directory may not live inside any input or protected tree."""
    for root in [notes_root, archives_root, *forbidden]:
        if root.exists() and is_within(run_dir, root):
            raise Refused(f"run directory {run_dir} resolves inside protected tree {root}")
    for name, root in (("--notes-root", notes_root), ("--archives-root", archives_root)):
        if run_dir.exists() and is_within(root, run_dir):
            raise Refused(f"{name} {root} resolves inside the run directory {run_dir}")


def load_engine() -> Any:
    location = os.environ.get("MEMORY_SWEEP_AI_MEMORY")
    if not location:
        raise Refused("MEMORY_SWEEP_AI_MEMORY is not set (the ai_memory.py normaliser)")
    spec = importlib.util.spec_from_file_location("ai_memory", location)
    if spec is None or spec.loader is None:
        raise Refused(f"could not load the normaliser from {location}")
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("ai_memory", module)
    spec.loader.exec_module(module)
    return module


# ── sampling (D7) ──────────────────────────────────────────────────────────


def path_excluded(relative: Path) -> bool:
    parts = relative.parts
    if any(part in EXCLUDED_PARTS for part in parts):
        return True
    if any(".env" in part for part in parts):
        return True
    return False


def eligible_notes(notes_root: Path, scope: str) -> list[Path]:
    roots = NOTES_SCOPE_OWN if scope == "own" else NOTES_SCOPE_ALL
    found: list[Path] = []
    for sub in roots:
        base = notes_root / sub
        if not base.is_dir():
            continue
        for path in base.rglob("*.md"):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(notes_root)
            if path_excluded(relative):
                continue
            size = path.stat().st_size
            if size < NOTE_MIN_BYTES or size > NOTE_MAX_BYTES:
                continue
            found.append(path)
    return sorted(set(found), key=lambda p: str(p.relative_to(notes_root)))


def chat_source(relative: Path) -> str | None:
    parts = relative.parts
    if parts and parts[0] == "codex-mirror":
        return "codex"
    if parts and parts[0] == "claude-code-mirror":
        return "claude-code"
    return None


def eligible_chats(archives_root: Path) -> tuple[list[Path], dict[str, int]]:
    skipped = {"pi": 0, "subagents": 0, "oversize": 0, "other": 0}
    found: list[Path] = []
    claude = archives_root / "claude-code-mirror"
    if claude.is_dir():
        for path in claude.glob("*/projects/*/*.jsonl"):
            if path.is_file():
                found.append(path)
        skipped["subagents"] = sum(1 for _ in claude.glob("*/projects/*/subagents/*.jsonl"))
    codex = archives_root / "codex-mirror" / "sessions"
    if codex.is_dir():
        found.extend(p for p in codex.rglob("*.jsonl") if p.is_file())
    pi = archives_root / "pi-mirror"
    if pi.is_dir():
        skipped["pi"] = sum(1 for _ in pi.rglob("*.jsonl"))
    kept: list[Path] = []
    for path in found:
        relative = path.relative_to(archives_root)
        if path_excluded(relative) or chat_source(relative) is None:
            skipped["other"] += 1
            continue
        if path.stat().st_size > CHAT_MAX_BYTES:
            skipped["oversize"] += 1
            continue
        kept.append(path)
    return sorted(set(kept), key=lambda p: str(p.relative_to(archives_root))), skipped


def sample(population: list[Path], n: int, seed: int) -> list[Path]:
    if n <= 0 or not population:
        return []
    rng = random.Random(seed)
    chosen = rng.sample(population, min(n, len(population)))
    return sorted(chosen, key=str)


def describe(path: Path, root: Path) -> dict[str, Any]:
    return {
        "relpath": str(path.relative_to(root)),
        "bytes": path.stat().st_size,
        "mtime": iso_mtime(path),
        "sha256": sha256_file(path),
    }


# ── payloads (D5, D6) ──────────────────────────────────────────────────────


def chunk_note(path: Path, notes_root: Path, limit: int = NOTE_CHUNK_CHARS, max_chunks: int = MAX_NOTE_CHUNKS) -> list[str]:
    """Paragraph-bounded chunks of at most `limit` chars, each headed by one line."""
    header = f"Note {path.relative_to(notes_root)}, modified {iso_mtime(path)[:10]}\n\n"
    body = path.read_text(encoding="utf-8", errors="replace")
    budget = limit - len(header)
    paragraphs = re.split(r"\n\s*\n", body)
    chunks: list[str] = []
    current = ""
    for paragraph in paragraphs:
        paragraph = paragraph.strip("\n")
        if not paragraph.strip():
            continue
        while len(paragraph) > budget:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(paragraph[:budget])
            paragraph = paragraph[budget:]
        candidate = paragraph if not current else current + "\n\n" + paragraph
        if len(candidate) > budget:
            chunks.append(current)
            current = paragraph
        else:
            current = candidate
    if current:
        chunks.append(current)
    return [header + chunk for chunk in chunks[:max_chunks]]


def note_session(path: Path, notes_root: Path, index: int) -> dict[str, Any]:
    stamp = iso_mtime(path)
    chunks = chunk_note(path, notes_root)
    conversations = [[{"role": "user", "content": chunk, "timestamp": stamp}] for chunk in chunks]
    return {
        "sessionKey": f"note-{index:02d}-{slug(str(path.relative_to(notes_root)))}",
        "kind": "note",
        "source": "notes",
        "relpath": str(path.relative_to(notes_root)),
        "conversations": conversations,
        "stats": {"rounds": len(conversations), "messages": len(conversations), "chars": sum(len(c) for c in chunks)},
    }


def merge_turns(turns: list[Any]) -> list[dict[str, str]]:
    merged: list[dict[str, str]] = []
    for turn in turns:
        role = turn.role if turn.role in ("user", "assistant") else "assistant"
        content = turn.content.strip()
        if not content:
            continue
        if merged and merged[-1]["role"] == role:
            merged[-1]["content"] = (merged[-1]["content"] + "\n\n" + content)[:MESSAGE_CHARS]
            continue
        merged.append({"role": role, "content": content[:MESSAGE_CHARS], "timestamp": turn.timestamp or ""})
    return merged


def chat_rounds(path: Path, source: str, engine: Any, max_turns: int) -> list[list[dict[str, str]]]:
    _, records = engine.load_jsonl_stably(path)
    turns, _ = engine.normalize_trace(source, list(records))
    messages = merge_turns(turns)[:max_turns]
    rounds: list[list[dict[str, str]]] = []
    i = 0
    while i < len(messages):
        if messages[i]["role"] == "user" and i + 1 < len(messages) and messages[i + 1]["role"] == "assistant":
            rounds.append([messages[i], messages[i + 1]])
            i += 2
        else:
            rounds.append([messages[i]])
            i += 1
    return rounds


def chat_session(path: Path, archives_root: Path, index: int, engine: Any, max_turns: int) -> dict[str, Any]:
    relative = path.relative_to(archives_root)
    source = chat_source(relative) or "claude-code"
    rounds = chat_rounds(path, source, engine, max_turns)
    messages = sum(len(r) for r in rounds)
    return {
        "sessionKey": f"chat-{index:02d}-{slug(path.stem)}",
        "kind": "chat",
        "source": source,
        "relpath": str(relative),
        "conversations": rounds,
        "stats": {"rounds": len(rounds), "messages": messages, "chars": sum(len(m["content"]) for r in rounds for m in r)},
    }


# ── config rendering ───────────────────────────────────────────────────────


def render_yaml(template: str, llm_url: str, model: str, prompt_mode: str, core_port: int) -> str:
    return (
        template.replace("{{LLM_URL}}", llm_url)
        .replace("{{MODEL}}", model)
        .replace("{{PROMPT_MODE}}", prompt_mode)
        .replace("{{CORE_PORT}}", str(core_port))
    )


# ── HTTP ───────────────────────────────────────────────────────────────────


def http_json(method: str, url: str, body: Any | None = None, headers: dict[str, str] | None = None, timeout: float = 60) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8", errors="replace")
            status = response.status
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        status = exc.code
    try:
        return status, json.loads(raw) if raw else None
    except json.JSONDecodeError:
        return status, raw


def http_text(url: str, timeout: float = 30) -> tuple[int, str]:
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, OSError, TimeoutError):
        return 0, ""


def wait_for(url: str, seconds: float, label: str, alive: Callable[[], bool] | None = None) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if alive is not None and not alive():
            print(f"memory-sweep-sample: {label} exited before it answered {url}", file=sys.stderr)
            return False
        status, _ = http_text(url, timeout=5)
        if 200 <= status < 300:
            return True
        time.sleep(2)
    return False


def parse_metrics(text: str) -> dict[str, float]:
    wanted = {"llamacpp:prompt_tokens_total": "prompt_tokens", "llamacpp:tokens_predicted_total": "generated_tokens"}
    out: dict[str, float] = {}
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[0] in wanted:
            try:
                out[wanted[parts[0]]] = float(parts[1])
            except ValueError:
                pass
    return out


# ── the run ────────────────────────────────────────────────────────────────


class Teardown:
    def __init__(self) -> None:
        self.steps: list[Callable[[], None]] = []
        self.done = False
        atexit.register(self.run)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, self._signal)

    def add(self, step: Callable[[], None]) -> None:
        self.steps.append(step)

    def _signal(self, signum: int, _frame: Any) -> None:
        print(f"memory-sweep-sample: signal {signum}, tearing down", file=sys.stderr)
        self.run()
        sys.exit(128 + signum)

    def run(self) -> None:
        if self.done:
            return
        self.done = True
        for step in reversed(self.steps):
            try:
                step()
            except Exception as exc:  # noqa: BLE001 - teardown never raises
                print(f"memory-sweep-sample: teardown step failed: {exc}", file=sys.stderr)


def do_plan(args: argparse.Namespace, run_dir: Path | None) -> dict[str, Any]:
    notes_root = Path(args.notes_root).expanduser()
    archives_root = Path(args.archives_root).expanduser()
    notes_population = eligible_notes(notes_root, args.notes_scope)
    chats_population, skipped = eligible_chats(archives_root)
    notes = sample(notes_population, args.notes_n, args.seed)
    chats = sample(chats_population, args.chats_n, args.seed + 1)
    plan = {
        "seed": args.seed,
        "notes_root": str(notes_root),
        "archives_root": str(archives_root),
        "notes_scope": args.notes_scope,
        "eligible": {"notes": len(notes_population), "chats": len(chats_population)},
        "skipped": skipped,
        "notes": [describe(p, notes_root) for p in notes],
        "chats": [dict(describe(p, archives_root), source=chat_source(p.relative_to(archives_root))) for p in chats],
        "created": utc_stamp(),
    }
    if run_dir is not None:
        write_json(run_dir / "plan.json", plan)
    return plan


def print_plan(plan: dict[str, Any]) -> None:
    print(f"seed {plan['seed']}; eligible notes {plan['eligible']['notes']}, chats {plan['eligible']['chats']}; skipped {plan['skipped']}")
    print("notes:")
    for row in plan["notes"]:
        print(f"  {row['bytes']:>8} B  {row['relpath']}")
    print("chats:")
    for row in plan["chats"]:
        print(f"  {row['bytes']:>8} B  {row['source']:<11} {row['relpath']}")


def build_payloads(args: argparse.Namespace, plan: dict[str, Any], run_dir: Path) -> list[Path]:
    notes_root = Path(plan["notes_root"])
    archives_root = Path(plan["archives_root"])
    engine = load_engine() if plan["chats"] else None
    payload_dir = run_dir / "payloads"
    payload_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    index = 0
    for row in plan["notes"]:
        index += 1
        session = note_session(notes_root / row["relpath"], notes_root, index)
        target = payload_dir / f"{index:02d}-note-{slug(Path(row['relpath']).stem)}.json"
        write_json(target, session)
        written.append(target)
    for row in plan["chats"]:
        index += 1
        path = archives_root / row["relpath"]
        try:
            session = chat_session(path, archives_root, index, engine, args.max_turns)
        except Exception as exc:  # noqa: BLE001 - one bad trace must not stop the sample
            session = {
                "sessionKey": f"chat-{index:02d}-unusable",
                "kind": "chat",
                "source": row.get("source"),
                "relpath": row["relpath"],
                "conversations": [],
                "stats": {"rounds": 0, "messages": 0, "chars": 0},
                "error": str(exc),
            }
        target = payload_dir / f"{index:02d}-chat-{slug(Path(row['relpath']).stem)}.json"
        write_json(target, session)
        written.append(target)
    return written


def start_server(args: argparse.Namespace, run_dir: Path, teardown: Teardown) -> subprocess.Popen[bytes]:
    serve = os.environ.get("MEMORY_SWEEP_SERVE")
    if not serve or not Path(serve).exists():
        raise Refused("MEMORY_SWEEP_SERVE (hy-memory-serve.sh) is not set or missing; pass --no-serve with a reachable --llm-url")
    port = urllib.request.urlparse(args.llm_url).port or 8081
    log = (run_dir / "llama-server.log").open("ab")
    env = dict(os.environ, PORT=str(port))
    child = subprocess.Popen(["bash", serve], stdout=log, stderr=subprocess.STDOUT, env=env)

    def stop() -> None:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=60)
            except subprocess.TimeoutExpired:
                child.kill()
        log.close()

    teardown.add(stop)
    return child


def start_core(args: argparse.Namespace, run_dir: Path, teardown: Teardown) -> None:
    image = os.environ.get("MEMORY_SWEEP_CORE_IMAGE")
    if not image:
        raise Refused("MEMORY_SWEEP_CORE_IMAGE is not set")
    template_path = os.environ.get("MEMORY_SWEEP_TEMPLATE")
    if not template_path or not Path(template_path).exists():
        raise Refused("MEMORY_SWEEP_TEMPLATE (tdai-gateway.template.yaml) is not set or missing")
    rendered = render_yaml(Path(template_path).read_text(), args.llm_url, args.model, args.prompt_mode, args.core_port)
    config = run_dir / "tdai-gateway.yaml"
    config.write_text(rendered)
    data_dir = run_dir / "core-data"
    data_dir.mkdir(parents=True, exist_ok=True)
    print(f"memory-sweep-sample: starting MemoryCore from {image} (the first run pulls about 248 MB by digest)")
    log = (run_dir / "core.log").open("ab")
    command = [
        "podman", "run", "--rm", "--name", "memory-sweep-core", "--network=host",
        "-v", f"{data_dir}:/data/tdai-memory",
        "-v", f"{config}:/data/config/tdai-gateway.yaml:ro",
        "-e", "TDAI_GATEWAY_CONFIG=/data/config/tdai-gateway.yaml",
        "-e", f"TDAI_GATEWAY_PORT={args.core_port}",
        "-e", "TDAI_GATEWAY_HOST=127.0.0.1",
        "-e", "TDAI_GATEWAY_API_KEY=",
        "-e", "TDAI_DATA_DIR=/data/tdai-memory",
        "-e", "STORE_MODE=sqlite",
        image,
    ]
    (run_dir / "core.cmd").write_text(" ".join(command) + "\n")
    child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)

    def stop() -> None:
        subprocess.run(["podman", "stop", "-t", "20", "memory-sweep-core"], check=False, capture_output=True)
        if child.poll() is None:
            try:
                child.wait(timeout=60)
            except subprocess.TimeoutExpired:
                child.kill()
        log.close()

    teardown.add(stop)
    if not wait_for(f"http://127.0.0.1:{args.core_port}/health", 120, "MemoryCore", alive=lambda: child.poll() is None):
        raise Refused(f"MemoryCore did not answer /health on 127.0.0.1:{args.core_port} within 120 s; see {run_dir / 'core.log'}")


def probe_writer(args: argparse.Namespace, run_dir: Path) -> dict[str, Any]:
    body = {
        "model": args.model,
        "temperature": 0.0,
        "max_tokens": 512,
        "messages": [{"role": "system", "content": QUICKSTART_SYSTEM_PROMPT}, *PROBE_DIALOGUE],
        "chat_template_kwargs": {"reasoning_effort": "no_think"},
    }
    started = time.monotonic()
    status, response = http_json("POST", f"{args.llm_url}/chat/completions", body, timeout=600)
    elapsed = time.monotonic() - started
    content = ""
    parsed: Any = None
    if isinstance(response, dict):
        try:
            content = response["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            content = ""
    stripped = re.sub(r"^```(?:json)?\s*|\s*```$", "", content.strip())
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        parsed = None
    probe = {
        "status": status,
        "seconds": round(elapsed, 2),
        "content": content,
        "json_object_with_memories": isinstance(parsed, dict) and isinstance(parsed.get("memories"), list),
        "response": response,
    }
    write_json(run_dir / "probe.json", probe)
    return probe


def seed_session(args: argparse.Namespace, session: dict[str, Any]) -> tuple[int, Any, float]:
    body = {
        "data": {"sessions": [{"sessionKey": session["sessionKey"], "conversations": session["conversations"]}]},
        "session_key": session["sessionKey"],
        "strict_round_role": False,
        "auto_fill_timestamps": True,
        "config_override": {
            "promptMode": args.prompt_mode,
            "pipeline": {"everyNConversations": 1, "l1IdleTimeoutSeconds": 15, "l2DelayAfterL1Seconds": 5},
        },
    }
    started = time.monotonic()
    status, response = http_json(
        "POST", f"http://127.0.0.1:{args.core_port}/seed", body,
        headers={"x-tdai-service-id": "default"}, timeout=1800,
    )
    return status, response, time.monotonic() - started


def live_session(args: argparse.Namespace, session: dict[str, Any]) -> tuple[int, Any, float]:
    base = f"http://127.0.0.1:{args.core_port}"
    headers = {"x-tdai-service-id": "default"}
    messages = [
        {"role": m["role"], "content": m["content"][:MESSAGE_CHARS], **({"timestamp": m["timestamp"]} if m.get("timestamp") else {})}
        for r in session["conversations"] for m in r
    ]
    started = time.monotonic()
    responses: list[Any] = []
    status = 0
    for start in range(0, len(messages), BATCH_MESSAGES):
        status, response = http_json(
            "POST", f"{base}/v3/conversation/add",
            {"session_id": session["sessionKey"], "messages": messages[start:start + BATCH_MESSAGES]},
            headers=headers, timeout=300,
        )
        responses.append(response)
        if status >= 400:
            break
    end_status, end_response = http_json("POST", f"{base}/session/end", {"session_key": session["sessionKey"]}, headers=headers, timeout=300)
    responses.append({"session_end": [end_status, end_response]})
    deadline = time.monotonic() + args.wait_seconds
    while time.monotonic() < deadline:
        _, state = http_json("GET", f"{base}/v2/pipeline/status", headers=headers, timeout=30)
        responses.append({"pipeline_status": state})
        if isinstance(state, dict):
            l1 = (state.get("data") or state).get("l1") if isinstance(state.get("data") or state, dict) else None
            if isinstance(l1, dict) and l1.get("idle") and not l1.get("running") and not l1.get("queued"):
                break
        time.sleep(5)
    return status, responses, time.monotonic() - started


def collect_atoms(run_dir: Path) -> list[dict[str, Any]]:
    atoms: list[dict[str, Any]] = []
    for records in sorted((run_dir / "core-data").glob("seed-*/records/*.jsonl")) + sorted((run_dir / "core-data").glob("records/*.jsonl")):
        for line in records.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                record["_file"] = str(records.relative_to(run_dir))
                atoms.append(record)
    return atoms


def atom_fields(record: dict[str, Any]) -> tuple[str, str, Any, str]:
    """Field names are read generically; the record shape is MemoryCore's (INFERRED)."""
    kind = str(record.get("type") or record.get("memory_type") or record.get("category") or "unknown")
    content = str(record.get("content") or record.get("text") or record.get("memory") or "")
    priority = record.get("priority", record.get("score"))
    session = str(record.get("session_id") or record.get("sessionKey") or record.get("session_key") or "")
    return kind, content, priority, session


def render_report(run_dir: Path) -> str:
    plan = json.loads((run_dir / "plan.json").read_text()) if (run_dir / "plan.json").exists() else {}
    payloads = [json.loads(p.read_text()) for p in sorted((run_dir / "payloads").glob("*.json"))] if (run_dir / "payloads").exists() else []
    results = json.loads((run_dir / "results.json").read_text()) if (run_dir / "results.json").exists() else {}
    probe = json.loads((run_dir / "probe.json").read_text()) if (run_dir / "probe.json").exists() else {}
    atoms = collect_atoms(run_dir)
    scenes = sorted((run_dir / "core-data").glob("seed-*/scene_blocks/*.md")) + sorted((run_dir / "core-data").glob("scene_blocks/*.md")) if (run_dir / "core-data").exists() else []
    lines: list[str] = []
    lines.append(f"# memory-sweep-sample report: {run_dir.name}")
    lines.append("")
    lines.append("Every number below is MEASURED in this run directory unless marked. Atom field names are read generically from MemoryCore's records (INFERRED shape).")
    lines.append("")
    lines.append("## Sample")
    lines.append("")
    lines.append(f"Seed {plan.get('seed')}; scope {plan.get('notes_scope')}; eligible notes {plan.get('eligible', {}).get('notes')}, chats {plan.get('eligible', {}).get('chats')}; skipped {plan.get('skipped')}.")
    lines.append("")
    lines.append("| # | kind | source | path | bytes | sha256 |")
    lines.append("|---|---|---|---|---|---|")
    index = 0
    for row in plan.get("notes", []):
        index += 1
        lines.append(f"| {index} | note | notes | `{row['relpath']}` | {row['bytes']} | `{row['sha256'][:12]}` |")
    for row in plan.get("chats", []):
        index += 1
        lines.append(f"| {index} | chat | {row.get('source')} | `{row['relpath']}` | {row['bytes']} | `{row['sha256'][:12]}` |")
    lines.append("")
    lines.append("## Writer probe")
    lines.append("")
    if probe:
        lines.append(f"HTTP {probe.get('status')}, {probe.get('seconds')} s, JSON object with a memories list: {probe.get('json_object_with_memories')}.")
        lines.append("")
        lines.append("```")
        lines.append(str(probe.get("content", ""))[:1500])
        lines.append("```")
    else:
        lines.append("No probe recorded (plan or dry-run only).")
    lines.append("")
    lines.append("## Per source")
    lines.append("")
    lines.append("| session | kind | rounds | messages | chars | transport | status | seconds | atoms |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    by_session: dict[str, list[dict[str, Any]]] = {}
    for atom in atoms:
        _, _, _, session = atom_fields(atom)
        by_session.setdefault(session, []).append(atom)
    total_chars = 0
    total_seconds = 0.0
    for payload in payloads:
        key = payload["sessionKey"]
        stats = payload.get("stats", {})
        total_chars += stats.get("chars", 0)
        result = results.get(key, {})
        total_seconds += float(result.get("seconds", 0) or 0)
        count = len(by_session.get(key, []))
        if count == 0 and len(by_session) == 1 and "" in by_session:
            count = "n/a"
        lines.append(
            f"| `{key}` | {payload.get('kind')} | {stats.get('rounds', 0)} | {stats.get('messages', 0)} | {stats.get('chars', 0)} | "
            f"{result.get('transport', '')} | {result.get('status', '')} | {round(float(result.get('seconds', 0) or 0), 1)} | {count} |"
        )
        if payload.get("error"):
            lines.append(f"| | | | | | | unusable: {payload['error'][:80]} | | |")
    lines.append("")
    lines.append("## Atoms")
    lines.append("")
    kinds: dict[str, int] = {}
    for atom in atoms:
        kind, _, _, _ = atom_fields(atom)
        kinds[kind] = kinds.get(kind, 0) + 1
    per_thousand = (len(atoms) * 1000 / total_chars) if total_chars else 0
    lines.append(f"Total atoms {len(atoms)}; by type {json.dumps(kinds, sort_keys=True)}; input chars {total_chars}; atoms per 1,000 input chars {per_thousand:.2f}; seed wall time {total_seconds:.1f} s.")
    lines.append("")
    lines.append("| type | priority | session | content |")
    lines.append("|---|---|---|---|")
    for atom in atoms[:200]:
        kind, content, priority, session = atom_fields(atom)
        content = content.replace("|", "\\|").replace("\n", " ")[:300]
        lines.append(f"| {kind} | {priority if priority is not None else ''} | `{session}` | {content} |")
    if len(atoms) > 200:
        lines.append(f"| ... | | | {len(atoms) - 200} more in core-data |")
    lines.append("")
    lines.append("## Scenes (L2) and persona (L3)")
    lines.append("")
    if scenes:
        for scene in scenes:
            lines.append(f"- `{scene.relative_to(run_dir)}`")
    else:
        lines.append("None written in this run (L2/L3 are observed, not relied on).")
    lines.append("")
    lines.append("## Writer tokens")
    lines.append("")
    metrics = results.get("_metrics", {})
    if metrics:
        before, after = metrics.get("before", {}), metrics.get("after", {})
        prompt = after.get("prompt_tokens", 0) - before.get("prompt_tokens", 0)
        generated = after.get("generated_tokens", 0) - before.get("generated_tokens", 0)
        lines.append(f"Prompt tokens {prompt:.0f}, generated tokens {generated:.0f} (delta of llama-server /metrics across the seed calls); per 1,000 input chars: {(prompt * 1000 / total_chars) if total_chars else 0:.0f} prompt, {(generated * 1000 / total_chars) if total_chars else 0:.0f} generated.")
    else:
        lines.append("No /metrics recorded.")
    lines.append("")
    lines.append("## Versions")
    lines.append("")
    versions = results.get("_versions", {})
    lines.append(f"- llama-server: `{versions.get('llama_server', os.environ.get('MEMORY_SWEEP_LLAMA_SERVER', ''))}`")
    lines.append(f"- MemoryCore image: `{versions.get('core_image', os.environ.get('MEMORY_SWEEP_CORE_IMAGE', ''))}`")
    lines.append(f"- transport: {versions.get('transport', '')}; prompt mode: {versions.get('prompt_mode', '')}")
    lines.append("")
    lines.append("## What was skipped and why")
    lines.append("")
    skipped = plan.get("skipped", {})
    lines.append(f"- pi sessions: {skipped.get('pi', 0)} (the normaliser supports Claude Code and Codex only)")
    lines.append(f"- subagent transcripts: {skipped.get('subagents', 0)} (never sampled)")
    lines.append(f"- chat files over 20 MB: {skipped.get('oversize', 0)}")
    lines.append("- notes under references/learnings, references/deferred, references/personal/estate, crm, any .env, files over 512 KB or under 200 bytes: excluded before sampling")
    lines.append("- the live ~/.claude*/projects and ~/.codex/sessions trees: never read")
    lines.append("")
    return "\n".join(lines) + "\n"


def do_run(args: argparse.Namespace) -> int:
    notes_root = Path(args.notes_root).expanduser()
    archives_root = Path(args.archives_root).expanduser()
    run_dir = Path(args.run_dir).expanduser() if args.run_dir else state_root() / utc_stamp()
    guard_run_dir(run_dir, notes_root, archives_root, default_forbidden_roots())
    run_dir.mkdir(parents=True, exist_ok=True)
    plan = do_plan(args, run_dir)
    print_plan(plan)
    payloads = build_payloads(args, plan, run_dir)
    print(f"memory-sweep-sample: {len(payloads)} payloads under {run_dir / 'payloads'}")
    if args.dry_run:
        print(f"memory-sweep-sample: dry run; nothing sent, nothing started; run directory {run_dir}")
        return 0

    if shutil.which("podman") is None:
        raise Refused("podman is not on PATH")
    teardown = Teardown()
    results: dict[str, Any] = {}
    budget_end = time.monotonic() + args.budget_seconds

    server_child = None
    if args.serve:
        server_child = start_server(args, run_dir, teardown)
        alive = lambda: server_child.poll() is None  # noqa: E731
    else:
        alive = None
    health = f"{args.llm_url}".rsplit("/v1", 1)[0] + "/health"
    if not wait_for(health, 600, "llama-server", alive=alive):
        raise Refused(f"the writer did not answer {health} within 600 s; see {run_dir / 'llama-server.log'}")
    probe = probe_writer(args, run_dir)
    print(f"memory-sweep-sample: writer probe HTTP {probe['status']}, memories list: {probe['json_object_with_memories']}")
    metrics_url = f"{args.llm_url}".rsplit("/v1", 1)[0] + "/metrics"
    before = parse_metrics(http_text(metrics_url)[1])

    start_core(args, run_dir, teardown)
    transport = args.transport
    for path in payloads:
        session = json.loads(path.read_text())
        key = session["sessionKey"]
        if not session["conversations"]:
            results[key] = {"transport": transport, "status": "skipped", "seconds": 0, "note": session.get("error", "empty")}
            continue
        if time.monotonic() > budget_end:
            results[key] = {"transport": transport, "status": "budget", "seconds": 0}
            continue
        if transport == "seed":
            status, response, seconds = seed_session(args, session)
            if status == 404 and not results:
                print("memory-sweep-sample: POST /seed answered 404; falling back to --transport live", file=sys.stderr)
                transport = "live"
                status, response, seconds = live_session(args, session)
        else:
            status, response, seconds = live_session(args, session)
        results[key] = {"transport": transport, "status": status, "seconds": round(seconds, 2), "response": response}
        print(f"memory-sweep-sample: {key}: HTTP {status} in {seconds:.1f} s")
        write_json(run_dir / "results.json", results)

    after = parse_metrics(http_text(metrics_url)[1])
    results["_metrics"] = {"before": before, "after": after}
    results["_versions"] = {
        "llama_server": os.environ.get("MEMORY_SWEEP_LLAMA_SERVER", ""),
        "core_image": os.environ.get("MEMORY_SWEEP_CORE_IMAGE", ""),
        "transport": transport,
        "prompt_mode": args.prompt_mode,
    }
    write_json(run_dir / "results.json", results)
    teardown.run()
    report = render_report(run_dir)
    report_path = run_dir / "report.md"
    report_path.write_text(report)
    with report_path.open("rb") as handle:
        os.fsync(handle.fileno())
    print(f"memory-sweep-sample: report at {report_path}")
    print("\n".join(report.splitlines()[:40]))
    return 0


def resolve_run(run_id: str) -> Path:
    run_dir = state_root() / run_id
    if not run_dir.is_dir() or not is_within(run_dir, state_root()) or run_dir.resolve() == state_root().resolve():
        raise Refused(f"no run directory named {run_id} under {state_root()}")
    return run_dir


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="memory-sweep-sample", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="verb", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--notes-n", type=int, default=5)
        p.add_argument("--chats-n", type=int, default=5)
        p.add_argument("--seed", type=int, default=DEFAULT_SEED)
        p.add_argument("--notes-scope", choices=("all", "own"), default="all")
        p.add_argument("--notes-root", default=str(Path.home() / "notes"))
        p.add_argument("--archives-root", default=str(Path.home() / "archives"))

    plan_p = sub.add_parser("plan", help="sample and print; no model, no container")
    common(plan_p)

    run_p = sub.add_parser("run", help="the whole experiment")
    common(run_p)
    run_p.add_argument("--run-dir", default=None, help="default ~/.local/state/memory-sweep/<utc-stamp>")
    run_p.add_argument("--llm-url", default="http://127.0.0.1:8081/v1")
    run_p.add_argument("--model", default="hy-memory")
    serve = run_p.add_mutually_exclusive_group()
    serve.add_argument("--serve", dest="serve", action="store_true", default=True)
    serve.add_argument("--no-serve", dest="serve", action="store_false")
    run_p.add_argument("--core-port", type=int, default=8420)
    run_p.add_argument("--prompt-mode", choices=("chat", "code"), default="chat")
    run_p.add_argument("--transport", choices=("seed", "live"), default="seed")
    run_p.add_argument("--max-turns", type=int, default=60)
    run_p.add_argument("--wait-seconds", type=int, default=600, help="live transport: how long to wait for l1.idle")
    run_p.add_argument("--budget-seconds", type=int, default=3600)
    run_p.add_argument("--dry-run", action="store_true", help="write plan and payloads only")

    report_p = sub.add_parser("report", help="re-render report.md")
    report_p.add_argument("run_id")
    clean_p = sub.add_parser("clean", help="delete one run directory")
    clean_p.add_argument("run_id")

    args = parser.parse_args(argv)
    if args.verb == "plan":
        print_plan(do_plan(args, None))
        return 0
    if args.verb == "run":
        return do_run(args)
    if args.verb == "report":
        run_dir = resolve_run(args.run_id)
        text = render_report(run_dir)
        (run_dir / "report.md").write_text(text)
        print(text)
        return 0
    if args.verb == "clean":
        run_dir = resolve_run(args.run_id)
        shutil.rmtree(run_dir)
        print(f"memory-sweep-sample: removed {run_dir}")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
