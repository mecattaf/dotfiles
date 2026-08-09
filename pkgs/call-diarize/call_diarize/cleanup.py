"""Candidate-bounded semantic cleanup through the managed llama-swap endpoint."""

from __future__ import annotations

import json
import socket
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable

from .pipeline import lexical_duplicate_target, load_json, write_json_exclusive


MODELS = {
    "gemma": "gemma4-26b-a4b-it",
    "qwen": "qwen3.6-35b-a3b",
}
ALLOWED_ACTIONS = {"keep", "duplicate", "unavailable"}
SYSTEM_PROMPT = """You make conservative, source-bounded transcript cleanup decisions.
Return one JSON object only. Never merge candidates, rewrite text, invent timestamps,
or alter the fixed speaker. Real speech and normal stutters must be kept. Mark a row
duplicate only when it clearly repeats a nearby earlier source; uncertainty means keep.
Rows already marked unavailable remain unavailable. Every candidate must receive exactly
one decision in input order.

Required shape:
{"shard_id":"000","decisions":[{"source_id":"near-...","action":"keep","duplicate_of":null,"reason":""}]}

action is exactly keep, duplicate, or unavailable. duplicate_of is an earlier source_id
only for duplicate; otherwise it is null. Do not add prose or Markdown fences."""


def _models_url(endpoint: str) -> str:
    marker = "/v1/chat/completions"
    if marker in endpoint:
        return endpoint.split(marker, 1)[0] + "/v1/models"
    return endpoint.rstrip("/") + "/v1/models"


def _http_json(
    url: str,
    payload: dict[str, Any] | None,
    timeout: int,
) -> dict[str, Any]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url, data=body, headers=headers, method="GET" if body is None else "POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            value = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:2000]
        raise RuntimeError(f"llama-swap HTTP {exc.code} from {url}: {detail}") from exc
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        raise RuntimeError(f"llama-swap request failed for {url}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"llama-swap returned a non-object from {url}")
    return value


def preflight_models(endpoint: str, timeout: int = 10) -> list[str]:
    response = _http_json(_models_url(endpoint), None, timeout)
    advertised = sorted(
        item["id"]
        for item in response.get("data", [])
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    )
    missing = sorted(set(MODELS.values()) - set(advertised))
    if missing:
        raise RuntimeError(
            f"llama-swap does not advertise required cleanup models: {missing}"
        )
    return advertised


def extract_json_object(text: str, expected_ids: set[str]) -> dict[str, Any]:
    decoder = json.JSONDecoder()
    candidates: list[tuple[int, int, dict[str, Any]]] = []
    for offset, character in enumerate(text):
        if character != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[offset:])
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict) or "decisions" not in value:
            continue
        accounted = {
            item.get("source_id")
            for item in value.get("decisions", [])
            if isinstance(item, dict) and isinstance(item.get("source_id"), str)
        }
        candidates.append((len(accounted & expected_ids), offset, value))
    if not candidates:
        raise ValueError("response contained no JSON object with decisions")
    return max(candidates, key=lambda candidate: (candidate[0], candidate[1]))[2]


def validate_decisions(
    value: dict[str, Any],
    shard: dict[str, Any],
    global_order: dict[str, int],
) -> list[dict[str, Any]]:
    shard_id = str(shard["shard_id"])
    if str(value.get("shard_id", "")).zfill(len(shard_id)) != shard_id:
        raise ValueError(
            f"wrong shard_id {value.get('shard_id')!r}; expected {shard_id}"
        )
    expected = [str(candidate["source_id"]) for candidate in shard["candidates"]]
    decisions = value.get("decisions")
    if not isinstance(decisions, list) or len(decisions) != len(expected):
        raise ValueError(
            f"expected {len(expected)} decisions, got {len(decisions or [])}"
        )
    actual = [
        item.get("source_id") if isinstance(item, dict) else None for item in decisions
    ]
    if actual != expected:
        raise ValueError(
            "decision IDs are missing, duplicated, invented, or out of order"
        )
    normalized: list[dict[str, Any]] = []
    for item, source_id in zip(decisions, expected, strict=True):
        action = item.get("action")
        if action not in ALLOWED_ACTIONS:
            raise ValueError(f"invalid action for {source_id}: {action!r}")
        duplicate_of = item.get("duplicate_of")
        if action == "duplicate":
            if not isinstance(duplicate_of, str) or duplicate_of not in global_order:
                raise ValueError(
                    f"invalid duplicate target for {source_id}: {duplicate_of!r}"
                )
            if global_order[duplicate_of] >= global_order[source_id]:
                raise ValueError(f"duplicate target is not earlier for {source_id}")
        elif duplicate_of is not None:
            raise ValueError(f"non-duplicate decision has duplicate_of for {source_id}")
        normalized.append(
            {
                "source_id": source_id,
                "action": action,
                "duplicate_of": duplicate_of,
                "reason": str(item.get("reason") or "")[:500],
            }
        )
    return normalized


def _candidate_payload(shard: dict[str, Any]) -> dict[str, Any]:
    return {
        "shard_id": shard["shard_id"],
        "candidate_count": shard["candidate_count"],
        "previous_context": shard.get("previous_context"),
        "candidates": [
            {
                "source_id": candidate["source_id"],
                "speaker_fixed_by_channel": candidate["speaker"],
                "track": candidate["track"],
                "start": candidate["start"],
                "end": candidate["end"],
                "kind": candidate["kind"],
                "text": candidate["text"],
            }
            for candidate in shard["candidates"]
        ],
    }


def _content(response: dict[str, Any]) -> str:
    try:
        content = response["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ValueError("response lacks choices[0].message.content") from exc
    if not isinstance(content, str):
        raise ValueError("response content is not text")
    return content


def run_model_shard(
    label: str,
    model: str,
    shard: dict[str, Any],
    raw_root: Path,
    endpoint: str,
    global_order: dict[str, int],
    timeout: int,
    retries: int = 3,
) -> list[dict[str, Any]]:
    output_dir = raw_root / "cleanup" / label
    final_path = output_dir / f"shard-{shard['shard_id']}.json"
    if final_path.exists():
        cached = load_json(final_path)
        if cached.get("model") != model:
            raise RuntimeError(f"cached cleanup model mismatch: {final_path}")
        return validate_decisions(cached["result"], shard, global_order)

    candidate_payload = _candidate_payload(shard)
    expected_ids = {str(item["source_id"]) for item in shard["candidates"]}
    correction = ""
    errors: list[str] = []
    for attempt in range(1, retries + 1):
        user_text = json.dumps(
            candidate_payload, ensure_ascii=False, separators=(",", ":")
        )
        if correction:
            user_text += f"\nYour prior response was rejected: {correction}. Return a complete corrected object."
        request_payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_text},
            ],
            "temperature": 0,
            "top_p": 1,
            "seed": 0,
            "max_tokens": 4096,
            "response_format": {"type": "json_object"},
            "chat_template_kwargs": {"enable_thinking": False},
        }
        started = time.monotonic()
        try:
            response = _http_json(endpoint, request_payload, timeout)
            parsed = extract_json_object(_content(response), expected_ids)
            decisions = validate_decisions(parsed, shard, global_order)
            evidence = {
                "model": model,
                "shard_id": shard["shard_id"],
                "candidate_ids": [item["source_id"] for item in shard["candidates"]],
                "attempt": attempt,
                "elapsed_seconds": round(time.monotonic() - started, 3),
                "request": request_payload,
                "response": response,
                "result": {"shard_id": shard["shard_id"], "decisions": decisions},
            }
            write_json_exclusive(final_path, evidence)
            return decisions
        except Exception as exc:
            correction = str(exc)
            errors.append(correction)
            attempt_path = (
                output_dir / f"shard-{shard['shard_id']}.attempt-{attempt:02d}.json"
            )
            write_json_exclusive(
                attempt_path,
                {
                    "model": model,
                    "shard_id": shard["shard_id"],
                    "attempt": attempt,
                    "elapsed_seconds": round(time.monotonic() - started, 3),
                    "error": correction,
                },
            )
    raise RuntimeError(
        f"{model} failed cleanup shard {shard['shard_id']} after {retries} attempts: "
        + " | ".join(errors)
    )


def run_both_models(
    shards: Iterable[dict[str, Any]],
    rows: list[dict[str, Any]],
    raw_root: Path,
    endpoint: str,
    timeout: int,
) -> dict[str, dict[str, dict[str, Any]]]:
    global_order = {str(row["source_id"]): index for index, row in enumerate(rows)}
    decisions_by_model: dict[str, dict[str, dict[str, Any]]] = {}
    for label, model in MODELS.items():
        by_id: dict[str, dict[str, Any]] = {}
        for shard in shards:
            print(
                f"cleanup {label} shard {shard['shard_id']} "
                f"({shard['candidate_count']} candidates)",
                flush=True,
            )
            for decision in run_model_shard(
                label,
                model,
                shard,
                raw_root,
                endpoint,
                global_order,
                timeout,
            ):
                by_id[decision["source_id"]] = decision
        if set(by_id) != set(global_order):
            raise RuntimeError(f"{model} did not account for every source candidate")
        decisions_by_model[label] = by_id
    return decisions_by_model


def reduce_consensus(
    rows: list[dict[str, Any]],
    decisions: dict[str, dict[str, dict[str, Any]]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Keep by default; drop only two-model duplicate consensus plus lexical proof."""

    kept: list[dict[str, Any]] = []
    dropped: list[dict[str, Any]] = []
    disagreements: list[dict[str, Any]] = []
    for row in rows:
        source_id = str(row["source_id"])
        gemma = decisions["gemma"][source_id]
        qwen = decisions["qwen"][source_id]
        signatures = {
            (gemma["action"], gemma.get("duplicate_of")),
            (qwen["action"], qwen.get("duplicate_of")),
        }
        if len(signatures) > 1:
            disagreements.append(
                {
                    "source_id": source_id,
                    "start": row["start"],
                    "end": row["end"],
                    "speaker": row["speaker"],
                    "text": row["text"],
                    "gemma": gemma,
                    "qwen": qwen,
                }
            )

        lexical_target = lexical_duplicate_target(row, kept)
        consensus_duplicate = (
            row.get("kind") == "speech"
            and gemma["action"] == "duplicate"
            and qwen["action"] == "duplicate"
            and lexical_target is not None
        )
        if consensus_duplicate:
            dropped.append(
                {
                    **row,
                    "duplicate_of": lexical_target,
                    "drop_rule": "two-model consensus plus deterministic lexical match",
                    "model_decisions": {"gemma": gemma, "qwen": qwen},
                }
            )
        else:
            kept.append(
                {
                    **row,
                    "cleanup_decisions": {"gemma": gemma, "qwen": qwen},
                }
            )
    return kept, dropped, disagreements
