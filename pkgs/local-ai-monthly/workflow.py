#!/usr/bin/env python3
"""Monthly local-AI community review.

Tally invokes this program as one opaque job.  Ordinary code owns repository
selection, Git intervals, bounded evidence, validation, rendering, and GitHub
publication.  Pi remains the agent harness and receives one atomic repository
slice at a time through the task-specific extension.ts tools.
"""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from jsonschema import Draft202012Validator


PACKAGE_ROOT = Path(__file__).resolve().parent
REGISTRY_REL = Path("pkgs/local-ai-monthly/sources.json")
TALLIES_REL = Path("docs/local-ai/tallies")
PROPOSALS_REL = Path("docs/local-ai/proposals")
STATE_BEGIN = "<!-- local-ai-monthly-state\n"
STATE_END = "\n-->"
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
HF_URL_RE = re.compile(
    r"https://huggingface\.co/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", re.IGNORECASE
)
REPORT_NAME_RE = re.compile(r"^\d{4}-\d{2}(?:-\d{2})?\.md$")
MAX_DIFF_BLOB_BYTES = 2_000_000
MAX_SINGLE_DIFF_CHARS = 250_000


class WorkflowError(RuntimeError):
    pass


class SourceError(WorkflowError):
    pass


class NeedsSplit(SourceError):
    pass


class PiTaskError(WorkflowError):
    def __init__(self, message: str, trace: Mapping[str, Any]):
        super().__init__(message)
        self.trace = trace


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def json_digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_command(
    argv: Sequence[str],
    *,
    cwd: Path | None = None,
    timeout: int = 300,
    check: bool = True,
    env: Mapping[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        list(argv),
        cwd=cwd,
        env=dict(env) if env is not None else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if check and completed.returncode != 0:
        command = " ".join(argv)
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise WorkflowError(
            f"command failed ({completed.returncode}): {command}\n{detail}"
        )
    return completed


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkflowError(f"cannot read JSON {path}: {exc}") from exc


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    temporary.write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def safe_remove_tree(path: Path, root: Path) -> None:
    resolved = path.resolve()
    resolved_root = root.resolve()
    if resolved.parent != resolved_root:
        raise WorkflowError(f"refusing to remove non-child path: {resolved}")
    if path.exists():
        shutil.rmtree(path)


def clone_repository(
    url: str,
    destination: Path,
    *,
    timeout: int,
    branch: str | None = None,
    no_checkout: bool = False,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    argv = ["git", "clone", "--filter=blob:none", "--no-tags"]
    if branch:
        argv.extend(["--branch", branch, "--single-branch"])
    if no_checkout:
        argv.append("--no-checkout")
    argv.extend([url, str(destination)])
    errors: list[str] = []
    for attempt in range(2):
        safe_remove_tree(destination, destination.parent)
        completed = run_command(argv, timeout=timeout, check=False)
        if completed.returncode == 0:
            return
        errors.append(completed.stderr.strip() or completed.stdout.strip())
        if attempt == 0:
            print(f"clone retry: {url}", flush=True)
    raise WorkflowError(f"clone failed twice: {url}\n" + "\n".join(errors))


def validate_registry(registry: Any) -> Mapping[str, Any]:
    if not isinstance(registry, Mapping) or registry.get("schema_version") != 1:
        raise WorkflowError("source registry must be a schema_version 1 object")
    sources = registry.get("sources")
    if not isinstance(sources, list) or not sources:
        raise WorkflowError("source registry has no sources")
    seen: set[str] = set()
    for source in sources:
        if not isinstance(source, Mapping):
            raise WorkflowError("source registry row is not an object")
        slug = source.get("slug")
        baseline = source.get("baseline")
        if not isinstance(slug, str) or not slug or slug in seen:
            raise WorkflowError(f"invalid or duplicate source slug: {slug!r}")
        if not isinstance(baseline, str) or not SHA1_RE.fullmatch(baseline):
            raise WorkflowError(f"source {slug} has an invalid baseline SHA")
        if not isinstance(source.get("url"), str):
            raise WorkflowError(f"source {slug} has no URL")
        seen.add(slug)
    return registry


def parse_embedded_state(markdown: str) -> Mapping[str, Any] | None:
    start = markdown.rfind(STATE_BEGIN)
    if start < 0:
        return None
    content_start = start + len(STATE_BEGIN)
    end = markdown.find(STATE_END, content_start)
    if end < 0:
        raise WorkflowError("monthly tally contains an unterminated state block")
    try:
        state = json.loads(markdown[content_start:end])
    except json.JSONDecodeError as exc:
        raise WorkflowError(f"monthly tally state is invalid JSON: {exc}") from exc
    if not isinstance(state, Mapping) or state.get("schema_version") != 1:
        raise WorkflowError("monthly tally state has the wrong schema")
    return state


def strip_embedded_state(markdown: str) -> str:
    start = markdown.rfind(STATE_BEGIN)
    if start < 0:
        return markdown
    end = markdown.find(STATE_END, start + len(STATE_BEGIN))
    return markdown[:start].rstrip() + "\n" if end >= 0 else markdown


def latest_tally(
    dotfiles: Path, max_chars: int
) -> tuple[Path | None, str, Mapping[str, Any] | None]:
    directory = dotfiles / TALLIES_REL
    candidates = (
        sorted(
            path
            for path in directory.glob("*.md")
            if REPORT_NAME_RE.fullmatch(path.name)
        )
        if directory.is_dir()
        else []
    )
    if not candidates:
        return None, "", None
    path = candidates[-1]
    markdown = path.read_text(encoding="utf-8")
    if len(markdown) > max_chars:
        raise WorkflowError(f"accepted tally exceeds baseline_rationale_chars: {path}")
    return path, strip_embedded_state(markdown), parse_embedded_state(markdown)


def accepted_pins(
    registry: Mapping[str, Any], state: Mapping[str, Any] | None
) -> dict[str, str]:
    pins = {source["slug"]: source["baseline"] for source in registry["sources"]}
    if state is None:
        return pins
    rows = state.get("source_pins")
    if not isinstance(rows, Mapping):
        raise WorkflowError("monthly tally state has no source_pins object")
    for slug, sha in rows.items():
        if slug in pins:
            if not isinstance(sha, str) or not SHA1_RE.fullmatch(sha):
                raise WorkflowError(
                    f"monthly tally state has an invalid pin for {slug}"
                )
            pins[slug] = sha
    return pins


def evaluate_catalog(dotfiles: Path, timeout: int) -> Mapping[str, Any]:
    reference = f"path:{dotfiles}#lib.localModelCatalog"
    completed = run_command(["nix", "eval", "--json", reference], timeout=timeout)
    try:
        catalog = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise WorkflowError(f"Nix catalog output is invalid JSON: {exc}") from exc
    if not isinstance(catalog, Mapping) or not isinstance(
        catalog.get("deployments"), Mapping
    ):
        raise WorkflowError("lib.localModelCatalog is missing deployments")
    if not catalog["deployments"]:
        raise WorkflowError("the accepted local model catalog is empty")
    return catalog


def match_path(path: str, pattern: str) -> bool:
    if pattern == "**":
        return True
    if pattern.endswith("/**"):
        prefix = pattern[:-3].rstrip("/")
        if path == prefix or path.startswith(prefix + "/"):
            return True
    pure = PurePosixPath(path)
    return pure.match(pattern) or fnmatch.fnmatchcase(path, pattern)


def relevant_paths(source: Mapping[str, Any], paths: Sequence[str]) -> list[str]:
    watched = source.get("watched_paths", ["**"])
    ignored = source.get("ignore_paths", [])
    evidence_patterns = source.get("evidence_paths")
    selected: list[str] = []
    for path in paths:
        if not any(match_path(path, pattern) for pattern in watched):
            continue
        if any(match_path(path, pattern) for pattern in ignored):
            continue
        if evidence_patterns and not any(
            match_path(path, pattern) for pattern in evidence_patterns
        ):
            continue
        selected.append(path)
    return sorted(set(selected))


def git(
    repo: Path, *args: str, timeout: int = 300, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return run_command(["git", "-C", str(repo), *args], timeout=timeout, check=check)


def remote_head(repo: Path, timeout: int) -> str:
    for ref in ("refs/remotes/origin/HEAD", "origin/main", "origin/master", "HEAD"):
        completed = git(repo, "rev-parse", ref, timeout=timeout, check=False)
        sha = completed.stdout.strip()
        if completed.returncode == 0 and SHA1_RE.fullmatch(sha):
            return sha
    raise SourceError("cannot resolve the source repository default-branch head")


def changed_paths(repo: Path, baseline: str, head: str, timeout: int) -> list[str]:
    completed = git(repo, "diff", "--name-only", "-z", baseline, head, timeout=timeout)
    return sorted({path for path in completed.stdout.split("\0") if path})


def commit_log(
    repo: Path, baseline: str, head: str, limit: int, timeout: int
) -> list[Mapping[str, str]]:
    completed = git(
        repo,
        "log",
        f"--max-count={limit}",
        "--format=%H%x1f%cI%x1f%s",
        f"{baseline}..{head}",
        timeout=timeout,
    )
    rows: list[Mapping[str, str]] = []
    for line in completed.stdout.splitlines():
        parts = line.split("\x1f", 2)
        if len(parts) == 3:
            rows.append(
                {"sha": parts[0], "committed_at": parts[1], "subject": parts[2][:500]}
            )
    return rows


def blob_size(repo: Path, revision: str, path: str, timeout: int) -> int:
    completed = git(
        repo, "cat-file", "-s", f"{revision}:{path}", timeout=timeout, check=False
    )
    if completed.returncode != 0:
        return 0
    try:
        return int(completed.stdout.strip())
    except ValueError:
        return 0


def file_diff(repo: Path, baseline: str, head: str, path: str, timeout: int) -> str:
    if (
        max(
            blob_size(repo, baseline, path, timeout),
            blob_size(repo, head, path, timeout),
        )
        > MAX_DIFF_BLOB_BYTES
    ):
        raise NeedsSplit(
            f"changed evidence blob exceeds {MAX_DIFF_BLOB_BYTES} bytes: {path}"
        )
    completed = git(
        repo,
        "diff",
        "--no-ext-diff",
        "--unified=20",
        baseline,
        head,
        "--",
        path,
        timeout=timeout,
    )
    if len(completed.stdout) > MAX_SINGLE_DIFF_CHARS:
        raise NeedsSplit(
            f"changed evidence diff exceeds {MAX_SINGLE_DIFF_CHARS} characters: {path}"
        )
    return completed.stdout or f"Binary or metadata-only change: {path}\n"


def chunk_text(text: str, limit: int) -> list[str]:
    chunks: list[str] = []
    current = ""
    for line in text.splitlines(keepends=True):
        while len(line) > limit:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(line[:limit])
            line = line[limit:]
        if current and len(current) + len(line) > limit:
            chunks.append(current)
            current = ""
        current += line
    if current or not chunks:
        chunks.append(current)
    return chunks


def partition_key(mode: str, path: str) -> str:
    parts = path.split("/")
    if mode == "files":
        return path
    if mode == "campaign" and len(parts) >= 4 and parts[:2] == ["data", "raw"]:
        return "/".join(parts[:4])
    if mode == "campaign":
        return "summary"
    if mode == "top-level":
        return parts[0] if len(parts) > 1 else "root"
    return "all"


def github_base_url(url: str) -> str | None:
    match = re.fullmatch(
        r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?", url.rstrip("/")
    )
    return f"https://github.com/{match.group(1)}/{match.group(2)}" if match else None


def evidence_slices(
    source: Mapping[str, Any],
    repo: Path,
    baseline: str,
    head: str,
    paths: Sequence[str],
    limits: Mapping[str, Any],
) -> list[Mapping[str, Any]]:
    mode = str(source.get("partition", "top-level"))
    grouped: dict[str, list[str]] = {}
    for path in paths:
        grouped.setdefault(partition_key(mode, path), []).append(path)
    result: list[Mapping[str, Any]] = []
    max_files = int(limits["evidence_files"])
    excerpt_chars = int(limits["excerpt_chars"])
    total_chars = int(limits["total_evidence_chars"])
    timeout = int(limits["git_timeout_seconds"])
    web = github_base_url(str(source["url"]))
    compare_url = f"{web}/compare/{baseline}...{head}" if web else str(source["url"])

    for group_name, group_paths in sorted(grouped.items()):
        for file_offset in range(0, len(group_paths), max_files):
            batch = group_paths[file_offset : file_offset + max_files]
            atoms: list[Mapping[str, Any]] = []
            for path in batch:
                diff = file_diff(repo, baseline, head, path, timeout)
                chunks = chunk_text(diff, excerpt_chars)
                for index, content in enumerate(chunks, 1):
                    atoms.append(
                        {
                            "path": path,
                            "part": index,
                            "parts": len(chunks),
                            "url": compare_url,
                            "content": content,
                        }
                    )
            packed: list[list[Mapping[str, Any]]] = []
            current: list[Mapping[str, Any]] = []
            current_chars = 0
            for atom in atoms:
                size = len(str(atom["content"]))
                if current and current_chars + size > total_chars:
                    packed.append(current)
                    current = []
                    current_chars = 0
                current.append(atom)
                current_chars += size
            if current:
                packed.append(current)
            for slice_index, atoms_slice in enumerate(packed, 1):
                evidence = [
                    dict(atom, id=f"E{index:03d}")
                    for index, atom in enumerate(atoms_slice, 1)
                ]
                suffix = f"-{file_offset // max_files + 1:02d}-{slice_index:02d}"
                result.append(
                    {
                        "partition": group_name + suffix,
                        "files": sorted({str(atom["path"]) for atom in atoms_slice}),
                        "evidence": evidence,
                    }
                )
    return result


def packages_at(repo: Path, revision: str, timeout: int) -> set[str]:
    completed = git(
        repo,
        "ls-tree",
        "-r",
        "--name-only",
        revision,
        "--",
        "packages",
        timeout=timeout,
    )
    packages: set[str] = set()
    for path in completed.stdout.splitlines():
        parts = path.split("/")
        if len(parts) >= 2:
            packages.add(parts[1])
    return packages


def llm_agents_observation(
    repo: Path,
    baseline: str,
    head: str,
    paths: Sequence[str],
    allowlist: Sequence[str],
    timeout: int,
) -> Mapping[str, Any]:
    before = packages_at(repo, baseline, timeout)
    after = packages_at(repo, head, timeout)
    changed = sorted(
        {
            path.split("/")[1]
            for path in paths
            if path.startswith("packages/") and "/" in path
        }
    )
    allowed_changed = sorted(set(changed).intersection(allowlist))
    added = sorted(after - before)
    removed = sorted(before - after)
    documentation_changed = any(not path.startswith("packages/") for path in paths)
    mechanical = (
        not added and not removed and not allowed_changed and not documentation_changed
    )
    if mechanical:
        for path in paths:
            diff = file_diff(repo, baseline, head, path, timeout)
            changed_lines = [
                line[1:].strip()
                for line in diff.splitlines()
                if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
            ]
            if any(
                line
                and not re.search(
                    r"\b(version|rev|hash|npmDepsHash|cargoHash|vendorHash|pnpmDepsHash)\s*=",
                    line,
                )
                for line in changed_lines
            ):
                mechanical = False
                break
    return {
        "packages_added": added,
        "packages_removed": removed,
        "packages_changed": changed,
        "allowlisted_packages_changed": allowed_changed,
        "mechanical_non_allowlist_version_churn_only": mechanical,
    }


def hf_repositories(evidence: Sequence[Mapping[str, Any]]) -> list[str]:
    repositories: set[str] = set()
    for row in evidence:
        for match in HF_URL_RE.finditer(str(row.get("content", ""))):
            repositories.add(f"{match.group(1)}/{match.group(2)}")
    return sorted(repositories)


def prepare_source(
    source: Mapping[str, Any],
    baseline: str,
    source_root: Path,
    registry: Mapping[str, Any],
    baseline_context: Mapping[str, Any],
    run_id: str,
) -> dict[str, Any]:
    limits = registry["limits"]
    timeout = int(limits["git_timeout_seconds"])
    destination = source_root / re.sub(r"[^A-Za-z0-9_.-]+", "-", str(source["slug"]))
    result: dict[str, Any] = {
        "slug": source["slug"],
        "url": source["url"],
        "baseline_sha": baseline,
        "observed_head_sha": None,
        "commit_count": 0,
        "changed_paths": [],
        "relevant_paths": [],
        "status": "failed",
        "tasks": [],
        "error": None,
    }
    try:
        clone_repository(
            str(source["url"]), destination, timeout=timeout, no_checkout=True
        )
        head = remote_head(destination, timeout)
        result["observed_head_sha"] = head
        exists = git(
            destination,
            "cat-file",
            "-e",
            f"{baseline}^{{commit}}",
            timeout=timeout,
            check=False,
        )
        if exists.returncode != 0:
            raise SourceError(f"accepted baseline is not present: {baseline}")
        ancestor = git(
            destination,
            "merge-base",
            "--is-ancestor",
            baseline,
            head,
            timeout=timeout,
            check=False,
        )
        if ancestor.returncode != 0:
            raise SourceError("accepted baseline is not an ancestor of observed HEAD")
        count = int(
            git(
                destination,
                "rev-list",
                "--count",
                f"{baseline}..{head}",
                timeout=timeout,
            ).stdout
        )
        result["commit_count"] = count
        if head == baseline:
            result["status"] = "no-delta"
            return result
        changed = changed_paths(destination, baseline, head, timeout)
        relevant = relevant_paths(source, changed)
        result["changed_paths"] = changed
        result["relevant_paths"] = relevant
        if not relevant:
            result["status"] = "irrelevant-only"
            return result
        observation: Mapping[str, Any] = {}
        if source.get("processor") == "llm-agents-nix":
            observation = llm_agents_observation(
                destination,
                baseline,
                head,
                relevant,
                registry.get("llm_agents_allowlist", []),
                timeout,
            )
            if observation.get("mechanical_non_allowlist_version_churn_only"):
                result["status"] = "irrelevant-only"
                result["deterministic_observation"] = observation
                return result
        logs = commit_log(
            destination, baseline, head, int(limits["commit_log"]), timeout
        )
        slices = evidence_slices(source, destination, baseline, head, relevant, limits)
        if not slices:
            raise SourceError("relevant paths produced no evidence slices")
        for index, prepared in enumerate(slices, 1):
            evidence = prepared["evidence"]
            task_id = f"{run_id}:{source['slug']}:{index:03d}"
            bundle = {
                "schema_version": 1,
                "task_id": task_id,
                "task": "monthly-local-ai-repository-delta",
                "source": {
                    "slug": source["slug"],
                    "url": source["url"],
                    "baseline_sha": baseline,
                    "observed_head_sha": head,
                    "comparison_kind": "incremental-git-interval",
                    "commit_count": count,
                },
                "scope": {
                    "partition": prepared["partition"],
                    "files": prepared["files"],
                },
                "repository_delta": {
                    "commits": logs,
                    "changed_path_count": len(changed),
                },
                "deterministic_observation": observation,
                "baseline_context": baseline_context,
                "evidence": evidence,
                "allowed_hf_repositories": hf_repositories(evidence),
                "tool_quotas": {
                    "hf_inspections": min(
                        int(limits["hf_inspections"]), len(hf_repositories(evidence))
                    )
                },
                "guardrails": {
                    "model_blob_downloads": "forbidden",
                    "roster_mutation": "proposal-only",
                    "deployment_gate_mutation": "forbidden",
                },
            }
            result["tasks"].append({"bundle": bundle, "status": "prepared"})
        result["status"] = "prepared"
    except (WorkflowError, ValueError) as exc:
        result["error"] = str(exc)
        result["status"] = "needs-split" if isinstance(exc, NeedsSplit) else "failed"
    return result


def discover_models(origin: str, timeout: int = 15) -> list[str]:
    base = origin.rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3]
    request = Request(f"{base}/v1/models", headers={"Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise WorkflowError(
            f"cannot discover llama-swap models at {origin}: {exc}"
        ) from exc
    rows = payload.get("data") if isinstance(payload, Mapping) else None
    models = sorted(
        {
            row.get("id")
            for row in rows or []
            if isinstance(row, Mapping) and isinstance(row.get("id"), str)
        }
    )
    if not models:
        raise WorkflowError("llama-swap advertises zero models")
    return models


def resolve_model(
    catalog: Mapping[str, Any],
    inference: Mapping[str, Any],
    available: Sequence[str],
    explicit: str | None,
) -> tuple[str, str]:
    available_set = set(available)
    if explicit:
        if explicit not in available_set:
            raise WorkflowError(
                f"explicit model is not advertised by llama-swap: {explicit}"
            )
        return explicit, "explicit"
    classes = inference.get("classes")
    preferred = inference.get("model_class")
    fallbacks = inference.get("fallback_classes", [])
    if not isinstance(classes, Mapping) or not isinstance(preferred, str):
        raise WorkflowError("inference model-class policy is invalid")
    deployments = catalog["deployments"]
    for class_name in [preferred] + list(fallbacks):
        config = classes.get(class_name)
        if not isinstance(config, Mapping):
            raise WorkflowError(f"unknown inference class: {class_name}")
        role_order = config.get("role_order")
        ram_order = config.get("ram_order")
        if not isinstance(role_order, list) or ram_order not in (
            "ascending",
            "descending",
        ):
            raise WorkflowError(f"invalid inference class: {class_name}")
        rank = {role: index for index, role in enumerate(role_order)}
        candidates: list[tuple[int, int, str]] = []
        for deployment in deployments.values():
            if not isinstance(deployment, Mapping):
                continue
            model = deployment.get("model")
            role = deployment.get("role")
            if (
                deployment.get("status") != "canonical"
                or model not in available_set
                or role not in rank
            ):
                continue
            ram = deployment.get("ramTierGb", 0)
            ram_value = ram if isinstance(ram, int) else 0
            candidates.append(
                (
                    rank[role],
                    ram_value if ram_order == "ascending" else -ram_value,
                    model,
                )
            )
        if candidates:
            return sorted(candidates)[0][2], class_name
    raise WorkflowError(
        "no loaded canonical model satisfies the configured class chain"
    )


def validation_errors(
    envelope: Any,
    bundle: Mapping[str, Any],
    schema: Mapping[str, Any],
    stable_ids: set[str],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(envelope, Mapping):
        return ["submission envelope is not an object"]
    brief = envelope.get("brief")
    inspections = envelope.get("hf_inspections")
    if not isinstance(brief, Mapping):
        return ["submission envelope has no brief object"]
    if not isinstance(inspections, list):
        return ["submission envelope has no hf_inspections array"]
    validator = Draft202012Validator(schema)
    for error in sorted(
        validator.iter_errors(brief), key=lambda row: list(row.absolute_path)
    ):
        location = ".".join(str(part) for part in error.absolute_path) or "$"
        errors.append(f"schema {location}: {error.message}")
    if errors:
        return errors

    source = bundle["source"]
    expected_source = {
        "slug": source["slug"],
        "baseline_sha": source["baseline_sha"],
        "observed_head_sha": source["observed_head_sha"],
        "comparison_kind": source["comparison_kind"],
        "commit_count": source["commit_count"],
    }
    if brief["task_id"] != bundle["task_id"]:
        errors.append("task_id does not match bundle")
    if brief["source"] != expected_source:
        errors.append("source identity does not exactly match bundle")
    expected_evidence = [row["id"] for row in bundle["evidence"]]
    if brief["scope"]["partition"] != bundle["scope"]["partition"]:
        errors.append("scope.partition does not match bundle")
    if brief["scope"]["inspected_evidence_ids"] != expected_evidence:
        errors.append(
            "scope.inspected_evidence_ids must preserve every bundle evidence ID in order"
        )
    if brief["scope"]["omitted_evidence_ids"]:
        errors.append("scope.omitted_evidence_ids must be empty")
    if brief["decision"]["next_baseline_sha"] != source["observed_head_sha"]:
        errors.append("decision.next_baseline_sha must equal observed HEAD")

    inspection_by_id: dict[str, Mapping[str, Any]] = {}
    for inspection in inspections:
        if not isinstance(inspection, Mapping) or not isinstance(
            inspection.get("id"), str
        ):
            errors.append("HF inspection row is malformed")
            continue
        if inspection["id"] in inspection_by_id:
            errors.append(f"duplicate HF inspection ID: {inspection['id']}")
        inspection_by_id[inspection["id"]] = inspection
    allowed_ids = set(expected_evidence).union(inspection_by_id)
    finding_by_id: dict[str, Mapping[str, Any]] = {}
    for finding in brief["findings"]:
        finding_id = finding["id"]
        if finding_id in finding_by_id:
            errors.append(f"duplicate finding ID: {finding_id}")
        if not set(finding["evidence_ids"]).issubset(allowed_ids):
            errors.append(f"finding {finding_id} cites unknown evidence")
        if finding["kind"] == "inference":
            if not finding["derived_from"]:
                errors.append(f"inference {finding_id} has no derived_from findings")
            for parent in finding["derived_from"]:
                row = finding_by_id.get(parent)
                if row is None or row.get("kind") not in ("claim", "measurement"):
                    errors.append(
                        f"inference {finding_id} has an invalid parent: {parent}"
                    )
        elif finding["derived_from"]:
            errors.append(f"non-inference {finding_id} must have empty derived_from")
        finding_by_id[finding_id] = finding

    for index, proposal in enumerate(brief["roster_proposals"], 1):
        prefix = f"proposal {index} ({proposal['stable_model_id']})"
        evidence_ids = set(proposal["evidence_ids"])
        if not evidence_ids.intersection(expected_evidence):
            errors.append(f"{prefix} lacks primary GitHub evidence")
        if not evidence_ids.issubset(allowed_ids):
            errors.append(f"{prefix} cites unknown evidence")
        relationship = proposal["relationship"]
        targets = proposal["comparison_targets"]
        if (
            relationship
            in ("additional-option", "technical-upgrade", "strict-supersession")
            and not targets
        ):
            errors.append(f"{prefix} requires a comparison target")
        unknown_targets = set(targets) - stable_ids
        if unknown_targets:
            errors.append(
                f"{prefix} names unknown comparison targets: {sorted(unknown_targets)}"
            )
        if (
            relationship in ("technical-upgrade", "strict-supersession")
            and not proposal["improvement_axes"]
        ):
            errors.append(f"{prefix} requires improvement_axes")

        inspection_id = proposal["hf_inspection_id"]
        inspection = (
            inspection_by_id.get(inspection_id)
            if isinstance(inspection_id, str)
            else None
        )
        artifact = proposal["artifact"]
        if isinstance(inspection_id, str) and inspection is None:
            errors.append(
                f"{prefix} references an unknown HF inspection: {inspection_id}"
            )
        if proposal["action"] in ("add", "update", "retire") and inspection is None:
            errors.append(
                f"{prefix} action {proposal['action']} requires an HF inspection"
            )
        if inspection is not None:
            if artifact["hf_url"] != inspection.get("hf_url"):
                errors.append(f"{prefix} HF URL differs from inspection")
            if artifact["revision"] != inspection.get("revision"):
                errors.append(f"{prefix} HF revision differs from inspection")
            inspected_files = {
                row.get("path"): (row.get("bytes"), row.get("sha256"))
                for row in inspection.get("files", [])
                if isinstance(row, Mapping)
            }
            proposed_files = {
                row.get("path"): (row.get("bytes"), row.get("sha256"))
                for row in artifact["files"]
            }
            if proposed_files != inspected_files:
                errors.append(f"{prefix} files differ from HF inspection")
        if proposal["action"] != "investigate":
            required = [
                "hf_url",
                "revision",
                "runtime_repo",
                "runtime_commit",
                "backend",
            ]
            missing = [field for field in required if not artifact.get(field)]
            if not artifact["files"]:
                missing.append("files")
            if not artifact["hosts"]:
                missing.append("hosts")
            if missing:
                errors.append(
                    f"{prefix} lacks complete deployment provenance: {sorted(set(missing))}"
                )
            if artifact.get("revision") and not SHA1_RE.fullmatch(artifact["revision"]):
                errors.append(f"{prefix} HF revision is not immutable")
            if artifact.get("runtime_commit") and not SHA1_RE.fullmatch(
                artifact["runtime_commit"]
            ):
                errors.append(f"{prefix} runtime commit is not immutable")
            for row in artifact["files"]:
                if not isinstance(row.get("bytes"), int) or not SHA256_RE.fullmatch(
                    str(row.get("sha256", ""))
                ):
                    errors.append(f"{prefix} has incomplete file provenance")
                    break
        null_fields = [
            field
            for field in (
                "hf_url",
                "revision",
                "runtime_repo",
                "runtime_commit",
                "backend",
            )
            if artifact.get(field) is None
        ]
        unresolved = set(proposal["unresolved_fields"])
        if not set(null_fields).issubset(unresolved):
            errors.append(
                f"{prefix} does not name every null artifact field as unresolved"
            )
    return errors


def invoke_pi(
    bundle: Mapping[str, Any],
    *,
    task_dir: Path,
    pi_program: str,
    provider: str,
    model: str,
    llama_swap_url: str,
    timeout: int,
    schema: Mapping[str, Any],
    stable_ids: set[str],
) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    skill_path = PACKAGE_ROOT / "skill" / "SKILL.md"
    extension_path = PACKAGE_ROOT / "extension.ts"
    lineage = {
        "bundle_sha256": json_digest(bundle),
        "skill_sha256": file_digest(skill_path),
        "extension_sha256": file_digest(extension_path),
        "schema_sha256": json_digest(schema),
    }
    repair_context: Mapping[str, Any] | None = None
    traces: list[Mapping[str, Any]] = []
    for attempt in range(1, 3):
        attempt_dir = task_dir / f"attempt-{attempt}"
        attempt_dir.mkdir(parents=True, exist_ok=False)
        attempt_bundle = copy.deepcopy(bundle)
        if repair_context is not None:
            attempt_bundle["repair_context"] = repair_context
        bundle_path = attempt_dir / "bundle.json"
        output_path = attempt_dir / "submission.json"
        bundle_path.write_text(
            json.dumps(attempt_bundle, indent=2) + "\n", encoding="utf-8"
        )
        agent_dir = attempt_dir / "pi-state"
        agent_dir.mkdir()
        stdout_path = attempt_dir / "pi.jsonl"
        stderr_path = attempt_dir / "pi.stderr"
        env = os.environ.copy()
        env.update(
            {
                "LLAMA_SWAP_URL": llama_swap_url,
                "LOCAL_AI_MONTHLY_BUNDLE": str(bundle_path),
                "LOCAL_AI_MONTHLY_OUTPUT": str(output_path),
                "PI_CODING_AGENT_DIR": str(agent_dir),
                "NO_COLOR": "1",
            }
        )
        command = [
            pi_program,
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-context-files",
            "--no-session",
            "--no-approve",
            "--print",
            "--mode",
            "json",
            "--provider",
            provider,
            "--model",
            model,
            "--skill",
            str(skill_path),
            "--extension",
            str(extension_path),
            "--no-builtin-tools",
            "--tools",
            "local_ai_inspect_hf,local_ai_submit_review",
            "Execute the loaded monthly local-AI review skill for the prepared task.",
        ]
        return_code = 124
        with (
            stdout_path.open("w", encoding="utf-8") as stdout,
            stderr_path.open("w", encoding="utf-8") as stderr,
        ):
            try:
                completed = subprocess.run(
                    command,
                    cwd=attempt_dir,
                    env=env,
                    text=True,
                    stdout=stdout,
                    stderr=stderr,
                    timeout=timeout,
                    check=False,
                )
                return_code = completed.returncode
            except subprocess.TimeoutExpired:
                pass
        errors: list[str] = []
        envelope: Any = None
        if return_code != 0:
            errors.append(f"Pi exited {return_code}")
        if not output_path.is_file():
            errors.append("Pi did not call local_ai_submit_review")
        else:
            try:
                envelope = load_json(output_path)
                errors.extend(
                    validation_errors(envelope, attempt_bundle, schema, stable_ids)
                )
            except WorkflowError as exc:
                errors.append(str(exc))
        trace = {
            "attempt": attempt,
            "model_id": model,
            "input_sha256": json_digest(attempt_bundle),
            "return_code": return_code,
            "stdout_sha256": file_digest(stdout_path),
            "stderr_sha256": file_digest(stderr_path),
            "errors": errors,
        }
        traces.append(trace)
        print(
            f"pi task={bundle['task_id']} attempt={attempt} model={model} status={'ok' if not errors else 'repair'}",
            flush=True,
        )
        if not errors and isinstance(envelope, Mapping):
            inspection_ids = [
                row["id"]
                for row in envelope["hf_inspections"]
                if isinstance(row, Mapping) and isinstance(row.get("id"), str)
            ]
            return envelope, {
                **lineage,
                "attempts": traces,
                "tool_outcome": {
                    "submitted": True,
                    "hf_inspection_ids": inspection_ids,
                },
                "output_sha256": json_digest(envelope),
            }
        repair_context = {
            "instruction": "Repair only these contract violations and submit a complete replacement review.",
            "validation_errors": errors,
            "previous_candidate": envelope.get("brief")
            if isinstance(envelope, Mapping)
            else None,
        }
    flattened = "; ".join(error for trace in traces for error in trace["errors"])
    raise PiTaskError(
        f"Pi contract failed after one repair: {flattened}",
        {
            **lineage,
            "attempts": traces,
            "tool_outcome": {"submitted": False, "hf_inspection_ids": []},
        },
    )


def markdown_cell(value: Any) -> str:
    return (
        str(value if value not in (None, "") else "—")
        .replace("|", "\\|")
        .replace("\n", " ")
    )


def evidence_links(task: Mapping[str, Any], ids: Sequence[str]) -> str:
    evidence = {row["id"]: row["url"] for row in task["bundle"]["evidence"]}
    envelope = task.get("envelope", {})
    for row in (
        envelope.get("hf_inspections", []) if isinstance(envelope, Mapping) else []
    ):
        if isinstance(row, Mapping):
            evidence[row.get("id")] = f"{row.get('hf_url')}/tree/{row.get('revision')}"
    links = [
        f"[{identifier}]({evidence[identifier]})"
        for identifier in ids
        if identifier in evidence
    ]
    return ", ".join(links) or "—"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:100] or "candidate"


def proposal_cards(
    period: str, sources: Sequence[Mapping[str, Any]], model_id: str
) -> list[Mapping[str, Any]]:
    cards: list[Mapping[str, Any]] = []
    seen_by_id: dict[str, tuple[str, str]] = {}
    seen_by_path: dict[str, str] = {}
    for source in sources:
        for task in source.get("tasks", []):
            envelope = task.get("envelope")
            if not isinstance(envelope, Mapping):
                continue
            brief = envelope["brief"]
            inspections = {row["id"]: row for row in envelope["hf_inspections"]}
            for proposal in brief["roster_proposals"]:
                inspection_id = proposal["hf_inspection_id"]
                if proposal["action"] == "retire" or not isinstance(inspection_id, str):
                    continue
                inspection = inspections.get(inspection_id)
                if not isinstance(inspection, Mapping):
                    continue
                stable_id = proposal["stable_model_id"]
                identity = (str(inspection["repository"]), str(inspection["revision"]))
                if stable_id in seen_by_id and seen_by_id[stable_id] != identity:
                    raise WorkflowError(
                        f"conflicting proposal cards for {stable_id}: "
                        f"{seen_by_id[stable_id]} and {identity}"
                    )
                path_slug = slugify(stable_id)
                if path_slug in seen_by_path and seen_by_path[path_slug] != stable_id:
                    raise WorkflowError(
                        f"proposal card path collision: {seen_by_path[path_slug]} and {stable_id}"
                    )
                if stable_id in seen_by_id:
                    continue
                seen_by_id[stable_id] = identity
                seen_by_path[path_slug] = stable_id
                source_evidence = [
                    row
                    for row in task["bundle"]["evidence"]
                    if row["id"] in proposal["evidence_ids"]
                ]
                card = {
                    "schema_version": 1,
                    "status": "proposal-only",
                    "period": period,
                    "stable_model_id": proposal["stable_model_id"],
                    "action": proposal["action"],
                    "relationship": proposal["relationship"],
                    "comparison_targets": proposal["comparison_targets"],
                    "improvement_axes": proposal["improvement_axes"],
                    "reason": proposal["reason"],
                    "artifact": {
                        "repository": inspection["repository"],
                        "hf_url": inspection["hf_url"],
                        "revision": inspection["revision"],
                        "files": inspection["files"],
                        "card_data": inspection["card_data"],
                    },
                    "runtime": {
                        "repository": proposal["artifact"]["runtime_repo"],
                        "commit": proposal["artifact"]["runtime_commit"],
                        "backend": proposal["artifact"]["backend"],
                        "hosts": proposal["artifact"]["hosts"],
                    },
                    "unresolved_fields": proposal["unresolved_fields"],
                    "observed_by": {
                        "source": source["slug"],
                        "task_id": brief["task_id"],
                        "model_id": model_id,
                    },
                    "evidence": [
                        {"id": row["id"], "url": row["url"], "path": row["path"]}
                        for row in source_evidence
                    ]
                    + [
                        {
                            "id": inspection["id"],
                            "url": f"{inspection['hf_url']}/tree/{inspection['revision']}",
                            "path": "Hugging Face metadata API",
                        }
                    ],
                }
                cards.append(card)
    return cards


def render_card(card: Mapping[str, Any]) -> str:
    artifact = card["artifact"]
    runtime = card["runtime"]
    lines = [
        f"# Proposed model card — `{card['stable_model_id']}`",
        "",
        "> Proposal only. This file does not register, download, install, or activate a model.",
        "",
        f"- Relationship: `{card['relationship']}`",
        f"- Proposed action: `{card['action']}`",
        f"- Comparison targets: {', '.join(f'`{row}`' for row in card['comparison_targets']) or 'none'}",
        f"- Improvement axes: {', '.join(card['improvement_axes']) or 'none established'}",
        f"- Originating source: `{card['observed_by']['source']}`",
        "",
        "## Why it entered the review",
        "",
        str(card["reason"]),
        "",
        "## Immutable artifact metadata",
        "",
        f"- Repository: [{artifact['repository']}]({artifact['hf_url']}/tree/{artifact['revision']})",
        f"- Revision: `{artifact['revision']}`",
        "",
        "| File | Bytes | LFS SHA-256 | Nix SRI |",
        "|---|---:|---|---|",
    ]
    for row in artifact["files"]:
        lines.append(
            f"| `{markdown_cell(row['path'])}` | {markdown_cell(row['bytes'])} | `{markdown_cell(row['sha256'])}` | `{markdown_cell(row['nix_sri'])}` |"
        )
    lines.extend(
        [
            "",
            "## Proposed deployment tuple",
            "",
            f"- Runtime: {f'[{runtime["repository"]}]({runtime["repository"]})' if runtime['repository'] else 'unresolved'}",
            f"- Runtime commit: `{markdown_cell(runtime['commit'])}`",
            f"- Backend: `{markdown_cell(runtime['backend'])}`",
            f"- Hosts: {', '.join(f'`{host}`' for host in runtime['hosts']) or 'unresolved'}",
            "",
            "## Evidence and gaps",
            "",
        ]
    )
    for row in card["evidence"]:
        lines.append(f"- [{row['id']}]({row['url']}) — `{row['path']}`")
    unresolved = card["unresolved_fields"]
    lines.append(
        f"- Unresolved: {', '.join(f'`{row}`' for row in unresolved) if unresolved else 'none recorded'}"
    )
    lines.extend(
        [
            "",
            "Promotion requires human review and a separate edit to the typed catalog. The global download gate remains independent.",
            "",
        ]
    )
    state = canonical_json(card)
    lines.extend(["<!-- local-ai-model-proposal", state, "-->", ""])
    return "\n".join(lines)


def render_report(
    *,
    period: str,
    cutoff: str,
    sources: Sequence[Mapping[str, Any]],
    pins: Mapping[str, str],
    baseline_tally: Path | None,
    catalog: Mapping[str, Any],
    model_class: str,
    model_id: str,
    cards: Sequence[Mapping[str, Any]],
    workflow_commit: str,
) -> str:
    completed_tasks = [
        task
        for source in sources
        for task in source.get("tasks", [])
        if isinstance(task.get("envelope"), Mapping)
    ]
    findings = [
        (source, task, finding)
        for source in sources
        for task in source.get("tasks", [])
        if isinstance(task.get("envelope"), Mapping)
        for finding in task["envelope"]["brief"]["findings"]
    ]
    proposals = [
        (source, task, proposal)
        for source in sources
        for task in source.get("tasks", [])
        if isinstance(task.get("envelope"), Mapping)
        for proposal in task["envelope"]["brief"]["roster_proposals"]
    ]
    failures = [
        source for source in sources if source["status"] in ("failed", "needs-split")
    ]
    changed_sources = [
        source
        for source in sources
        if source.get("observed_head_sha") != source["baseline_sha"]
    ]
    card_paths = {
        card[
            "stable_model_id"
        ]: f"../proposals/{period}/{slugify(card['stable_model_id'])}.md"
        for card in cards
    }
    lines = [
        f"# Local-AI tally — {period}",
        "",
        f"Cutoff: {cutoff}. Compared against {f'[`{baseline_tally.name}`]({baseline_tally.name})' if baseline_tally else 'the registry anchor'} and the typed local-model catalog.",
        "",
        "## Executive briefing",
        "",
        f"- {len(changed_sources)} of {len(sources)} enabled community sources moved; {len(completed_tasks)} bounded evidence slices required model judgment.",
        f"- {len(findings)} evidence-bound findings and {len(proposals)} roster proposals were recorded.",
        f"- {len(cards)} mechanically verified proposal card(s) accompany this briefing.",
        f"- Pi used the abstract `{model_class}` class, resolved for this run to `{model_id}` through llama-swap.",
        "- No model blob was requested or downloaded. The workflow did not edit the typed roster, llama-swap configuration, installed services, or `downloadAllModels` gate.",
        "",
        "## Findings",
        "",
    ]
    if not findings:
        lines.append("No evidence slice produced a substantive finding this month.")
    for source, task, finding in findings:
        lines.append(
            f"- **{finding['change_class']} · {source['slug']}:** {finding['summary']} "
            f"({evidence_links(task, finding['evidence_ids'])})"
        )
    lines.extend(["", "## Roster comparison", ""])
    if not proposals:
        lines.append(
            "No roster change was proposed; every accepted deployment remains unchanged."
        )
    else:
        lines.extend(
            [
                "| Candidate | Relationship | Action | Compared with | Improvement axes | Reason | Evidence |",
                "|---|---|---|---|---|---|---|",
            ]
        )
        for _source, task, proposal in proposals:
            candidate = proposal["stable_model_id"]
            candidate_text = (
                f"[`{candidate}`]({card_paths[candidate]})"
                if candidate in card_paths
                else f"`{candidate}`"
            )
            lines.append(
                "| "
                + " | ".join(
                    [
                        candidate_text,
                        markdown_cell(proposal["relationship"]),
                        markdown_cell(proposal["action"]),
                        markdown_cell(", ".join(proposal["comparison_targets"])),
                        markdown_cell(", ".join(proposal["improvement_axes"])),
                        markdown_cell(proposal["reason"]),
                        evidence_links(task, proposal["evidence_ids"]),
                    ]
                )
                + " |"
            )
    canonical = sorted(
        stable_id
        for stable_id, deployment in catalog["deployments"].items()
        if isinstance(deployment, Mapping) and deployment.get("status") == "canonical"
    )
    targeted = {
        target
        for _, _, proposal in proposals
        for target in proposal["comparison_targets"]
    }
    unchanged = [stable_id for stable_id in canonical if stable_id not in targeted]
    lines.extend(
        [
            "",
            "### Unchanged accepted rows",
            "",
            ", ".join(f"`{row}`" for row in unchanged)
            if unchanged
            else "Every accepted row is named in a proposal.",
            "",
            "## Source ledger",
            "",
            "| Source | Previous pin | Observed HEAD | Result | Next accepted pin |",
            "|---|---|---|---|---|",
        ]
    )
    for source in sources:
        lines.append(
            f"| `{source['slug']}` | `{source['baseline_sha'][:12]}` | "
            f"`{str(source.get('observed_head_sha') or 'unavailable')[:12]}` | {source['status']} | "
            f"`{pins[source['slug']][:12]}` |"
        )
    lines.extend(["", "## Failures and unresolved scope", ""])
    if not failures:
        lines.append(
            "No source interval failed or exceeded its deterministic evidence bounds."
        )
    else:
        for source in failures:
            lines.append(
                f"- `{source['slug']}` retained `{source['baseline_sha']}`: {source['error']}"
            )
    lines.extend(
        [
            "",
            "## Procedure and safety",
            "",
            "Git selection, ancestry checks, path filtering, evidence partitioning, Hugging Face metadata resolution, schema validation, pin advancement, Markdown rendering, and PR publication were deterministic. Pi judged only significance, local relevance, and the relationship to the accepted roster. Tally retains the execution trace and proof on the coordinator.",
            "",
            f"Workflow commit: `{workflow_commit}`.",
            "",
        ]
    )
    state = {
        "schema_version": 1,
        "period": period,
        "accepted_through": cutoff,
        "source_pins": dict(sorted(pins.items())),
        "catalog_sha256": json_digest(catalog),
        "workflow_commit": workflow_commit,
    }
    lines.extend(
        [STATE_BEGIN.rstrip("\n"), canonical_json(state), STATE_END.lstrip("\n"), ""]
    )
    return "\n".join(lines)


def publish_markdown(
    dotfiles: Path,
    period: str,
    report: str,
    cards: Sequence[Mapping[str, Any]],
    base_branch: str,
) -> tuple[str, list[Path]]:
    report_path = dotfiles / TALLIES_REL / f"{period}.md"
    if report_path.exists():
        raise WorkflowError(
            f"monthly briefing already exists on the base branch: {report_path}"
        )
    paths = [report_path]
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report, encoding="utf-8")
    for card in cards:
        path = (
            dotfiles / PROPOSALS_REL / period / f"{slugify(card['stable_model_id'])}.md"
        )
        if path.exists():
            raise WorkflowError(f"proposal card path already exists: {path}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_card(card), encoding="utf-8")
        paths.append(path)

    relative = [path.relative_to(dotfiles) for path in paths]
    branch = f"automation/local-ai-tally-{period}"
    git(dotfiles, "switch", "-c", branch)
    git(dotfiles, "add", "--", *(str(path) for path in relative))
    staged = set(git(dotfiles, "diff", "--cached", "--name-only").stdout.splitlines())
    expected = {str(path) for path in relative}
    if staged != expected or any(not path.endswith(".md") for path in staged):
        raise WorkflowError(
            f"publication scope violation: staged={sorted(staged)}, expected={sorted(expected)}"
        )
    git(dotfiles, "commit", "-m", f"docs(local-ai): add {period} monthly tally")
    git(dotfiles, "push", "--set-upstream", "origin", branch, timeout=600)
    body = (
        "Automated monthly local-AI community review.\n\n"
        "This draft contains a human briefing and proposal-only model cards. "
        "It does not register or download models and does not alter the deployment gate."
    )
    completed = run_command(
        [
            "gh",
            "pr",
            "create",
            "--draft",
            "--base",
            base_branch,
            "--head",
            branch,
            "--title",
            f"docs(local-ai): {period} monthly community tally",
            "--body",
            body,
        ],
        cwd=dotfiles,
        timeout=300,
    )
    return completed.stdout.strip(), relative


def default_runtime_base() -> Path:
    candidate = os.environ.get("XDG_RUNTIME_DIR")
    if candidate:
        return Path(candidate) / "local-ai-monthly"
    return Path(f"/run/user/{os.getuid()}") / "local-ai-monthly"


def default_state_dir() -> Path:
    candidate = os.environ.get("XDG_STATE_HOME")
    if candidate:
        return Path(candidate) / "local-ai-monthly"
    return Path.home() / ".local" / "state" / "local-ai-monthly"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dotfiles-url", default="https://github.com/mecattaf/dotfiles.git"
    )
    parser.add_argument("--base-branch", default="main")
    parser.add_argument(
        "--period", help="YYYY-MM; defaults to the current Europe/Paris month"
    )
    parser.add_argument("--runtime-base", type=Path, default=default_runtime_base())
    parser.add_argument("--state-dir", type=Path, default=default_state_dir())
    parser.add_argument("--pi", default="pi")
    parser.add_argument("--model", help="manual concrete-model override")
    parser.add_argument(
        "--source", action="append", default=[], help="limit to one source slug"
    )
    parser.add_argument(
        "--prepare-only", action="store_true", help="stop after deterministic bundles"
    )
    parser.add_argument(
        "--publish", action="store_true", help="push a branch and create the draft PR"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    now = datetime.now(ZoneInfo("Europe/Paris"))
    period = args.period or now.strftime("%Y-%m")
    if not re.fullmatch(r"\d{4}-\d{2}", period):
        raise WorkflowError("period must be YYYY-MM")
    args.runtime_base.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix=f"{period}-", dir=args.runtime_base))
    run_id = run_dir.name
    witness_path = args.state_dir / "last-run.json"
    started_at = datetime.now(timezone.utc).isoformat()
    witness: dict[str, Any] = {
        "schema_version": 1,
        "run_id": run_id,
        "period": period,
        "started_at": started_at,
        "status": "running",
        "no_model_blobs": True,
    }
    write_json_atomic(witness_path, witness)
    try:
        dotfiles = run_dir / "dotfiles"
        clone_repository(
            args.dotfiles_url,
            dotfiles,
            timeout=300,
            branch=args.base_branch,
        )
        workflow_commit = git(dotfiles, "rev-parse", "HEAD").stdout.strip()
        registry = validate_registry(load_json(dotfiles / REGISTRY_REL))
        limits = registry["limits"]
        tally_path, rationale, prior_state = latest_tally(
            dotfiles, int(limits["baseline_rationale_chars"])
        )
        pins = accepted_pins(registry, prior_state)
        catalog = evaluate_catalog(dotfiles, 600)
        baseline_context = {
            "catalog": catalog,
            "catalog_sha256": json_digest(catalog),
            "accepted_tally": str(tally_path.relative_to(dotfiles))
            if tally_path
            else None,
            "accepted_rationale_markdown": rationale,
        }
        selected_sources = [
            source for source in registry["sources"] if source.get("enabled")
        ]
        if args.source:
            wanted = set(args.source)
            selected_sources = [
                source for source in selected_sources if source["slug"] in wanted
            ]
            missing = wanted - {source["slug"] for source in selected_sources}
            if missing:
                raise WorkflowError(
                    f"unknown or disabled source filter: {sorted(missing)}"
                )
        source_root = run_dir / "sources"
        results = [
            prepare_source(
                source,
                pins[source["slug"]],
                source_root,
                registry,
                baseline_context,
                run_id,
            )
            for source in selected_sources
        ]
        task_count = sum(len(source["tasks"]) for source in results)
        print(
            f"prepared sources={len(results)} tasks={task_count} run_dir={run_dir}",
            flush=True,
        )
        if args.prepare_only:
            witness.update(
                {
                    "status": "prepared",
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                    "workflow_commit": workflow_commit,
                    "sources": [
                        {"slug": row["slug"], "status": row["status"]}
                        for row in results
                    ],
                    "task_count": task_count,
                }
            )
            write_json_atomic(witness_path, witness)
            return 0

        failed_preparation = {"failed", "needs-split"}
        if results and all(
            source["status"] in failed_preparation for source in results
        ):
            raise WorkflowError(
                "every selected source failed deterministic preparation"
            )

        schema = load_json(PACKAGE_ROOT / "schema" / "brief.schema.json")
        available = (
            discover_models(str(registry["inference"]["url"])) if task_count else []
        )
        if task_count:
            model_id, model_class = resolve_model(
                catalog, registry["inference"], available, args.model
            )
        else:
            model_id, model_class = (
                "not-invoked",
                str(registry["inference"]["model_class"]),
            )
        stable_ids = set(catalog["deployments"])
        pi_program = shutil.which(args.pi) or args.pi
        successful_tasks = 0
        model_failures = 0
        for source in results:
            if source["status"] != "prepared":
                continue
            source_failed = False
            for index, task in enumerate(source["tasks"], 1):
                task_dir = (
                    run_dir / "pi" / slugify(source["slug"]) / f"task-{index:03d}"
                )
                task_dir.mkdir(parents=True, exist_ok=False)
                try:
                    envelope, trace = invoke_pi(
                        task["bundle"],
                        task_dir=task_dir,
                        pi_program=pi_program,
                        provider=str(registry["inference"]["provider"]),
                        model=model_id,
                        llama_swap_url=str(registry["inference"]["url"]),
                        timeout=int(limits["model_timeout_seconds"]),
                        schema=schema,
                        stable_ids=stable_ids,
                    )
                    task.update(
                        {"status": "complete", "envelope": envelope, "trace": trace}
                    )
                    successful_tasks += 1
                except WorkflowError as exc:
                    task.update(
                        {
                            "status": "failed",
                            "error": str(exc),
                            "trace": getattr(exc, "trace", None),
                        }
                    )
                    source_failed = True
                    model_failures += 1
            source["status"] = "failed" if source_failed else "complete"
            if source_failed:
                source["error"] = "one or more Pi evidence slices failed validation"
        if task_count and successful_tasks == 0:
            raise WorkflowError(
                "every prepared Pi task failed; refusing to publish an empty synthesis"
            )

        next_pins = dict(pins)
        for source in results:
            if source["status"] in ("complete", "no-delta", "irrelevant-only"):
                next_pins[source["slug"]] = source["observed_head_sha"]
        cards = proposal_cards(period, results, model_id)
        cutoff = now.isoformat()
        report = render_report(
            period=period,
            cutoff=cutoff,
            sources=results,
            pins=next_pins,
            baseline_tally=tally_path,
            catalog=catalog,
            model_class=model_class,
            model_id=model_id,
            cards=cards,
            workflow_commit=workflow_commit,
        )
        artifact_dir = run_dir / "artifacts"
        artifact_dir.mkdir()
        preview_report = artifact_dir / f"{period}.md"
        preview_report.write_text(report, encoding="utf-8")
        for card in cards:
            card_path = (
                artifact_dir / "proposals" / f"{slugify(card['stable_model_id'])}.md"
            )
            card_path.parent.mkdir(parents=True, exist_ok=True)
            card_path.write_text(render_card(card), encoding="utf-8")
        pr_url = None
        published_paths: list[Path] = []
        if args.publish:
            pr_url, published_paths = publish_markdown(
                dotfiles, period, report, cards, args.base_branch
            )
            print(f"draft PR: {pr_url}", flush=True)
        witness.update(
            {
                "status": "complete",
                "completed_at": datetime.now(timezone.utc).isoformat(),
                "workflow_commit": workflow_commit,
                "model_class": model_class,
                "model_id": model_id,
                "sources": [
                    {
                        "slug": source["slug"],
                        "status": source["status"],
                        "accepted_pin": next_pins[source["slug"]],
                    }
                    for source in results
                ],
                "task_count": task_count,
                "successful_tasks": successful_tasks,
                "model_failures": model_failures,
                "report_sha256": hashlib.sha256(report.encode("utf-8")).hexdigest(),
                "proposal_card_count": len(cards),
                "published_paths": [str(path) for path in published_paths],
                "pr_url": pr_url,
                "traces": [
                    {
                        "task_id": task["bundle"]["task_id"],
                        "status": task["status"],
                        "trace": task.get("trace"),
                        "error": task.get("error"),
                    }
                    for source in results
                    for task in source.get("tasks", [])
                ],
            }
        )
        write_json_atomic(witness_path, witness)
        print(f"witness: {witness_path}", flush=True)
        print(f"preview: {preview_report}", flush=True)
        return 0
    except Exception as exc:
        witness.update(
            {
                "status": "failed",
                "completed_at": datetime.now(timezone.utc).isoformat(),
                "error": str(exc),
            }
        )
        write_json_atomic(witness_path, witness)
        print(f"local-ai-monthly: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
