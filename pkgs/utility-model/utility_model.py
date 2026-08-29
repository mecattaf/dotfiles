#!/usr/bin/env python3
"""Request-scoped owner for the local utility model.

The application-facing protocol is one OpenAI-compatible chat-completions
request on stdin and one response on stdout.  Callers may name only the stable
model ID ``utility``.  Nix supplies the llama-swap endpoint and the concrete
served model ID.

Installed on the coordinator only, GPU-backed via llama-swap since 2026-08-29.
Until that date the seam owned a FastFlowLM child on the XDNA2 NPU: it took an
NPU lock, spawned a loopback-only server, waited for health, ran one request,
and killed the child.  That NPU is decommissioned permanently, and Tom's ruling
moved the seam rather than retiring it, so this file now forwards one request to
the coordinator's llama-swap endpoint and rewrites ``utility`` to the concrete
served ID on the way out and back.

No lock and no child process survive that move.  llama-swap already serializes
per-model loads, cold-loads on demand, and TTL-unloads when idle, so the only
thing left here is the bounded request itself.  It can still take minutes: a
cold load of a ~40 GB Vulkan model is exactly what llama-swap's own 900s
healthCheckTimeout (modules/llama-swap.nix) is sized for, and callers already
tolerated FLM's start-wait, so the default timeout below is generous on purpose.

The ai-memory flake check imports this file by path as the module under test,
independently of which hosts install the wrapper.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import BinaryIO


STABLE_MODEL_ID = "utility"
MAX_REQUEST_BYTES = 2 * 1024 * 1024
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
DEFAULT_ENDPOINT = "http://localhost:9292"
CHAT_COMPLETIONS_PATH = "/v1/chat/completions"
# Cold-loading the served model can consume llama-swap's whole 900s health
# window before a single token is generated; leave room for the generation too.
DEFAULT_TIMEOUT_SECONDS = 1200.0


class UtilityModelError(RuntimeError):
    """A bounded, user-facing utility-model failure."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one request through the local utility model"
    )
    parser.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--concrete-model",
        required=True,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--context-tokens",
        required=True,
        type=int,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=(
            "Total request timeout in seconds, cold load included "
            f"(default: {DEFAULT_TIMEOUT_SECONDS:.0f})"
        ),
    )
    return parser.parse_args(argv)


def load_request(stream: BinaryIO) -> dict[str, object]:
    raw = stream.read(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        raise UtilityModelError(
            f"utility request exceeds the {MAX_REQUEST_BYTES}-byte limit"
        )
    try:
        request = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise UtilityModelError(f"utility request is not valid JSON: {exc}") from exc
    if not isinstance(request, dict):
        raise UtilityModelError("utility request must be a JSON object")
    if request.get("model") != STABLE_MODEL_ID:
        raise UtilityModelError(
            f'utility request must use model "{STABLE_MODEL_ID}"'
        )
    messages = request.get("messages")
    if not isinstance(messages, list) or not messages:
        raise UtilityModelError("utility request requires a non-empty messages array")
    if request.get("stream") not in (None, False):
        raise UtilityModelError("streaming utility requests are not supported")
    return request


def normalize_endpoint(endpoint: str) -> str:
    parsed = urllib.parse.urlsplit(endpoint)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise UtilityModelError(
            f"utility endpoint must be an http(s) URL, got: {endpoint}"
        )
    return endpoint.rstrip("/")


def read_bounded(response: BinaryIO) -> bytes:
    body = response.read(MAX_RESPONSE_BYTES + 1)
    if len(body) > MAX_RESPONSE_BYTES:
        raise UtilityModelError(
            f"utility response exceeds the {MAX_RESPONSE_BYTES}-byte limit"
        )
    return body


def send_request(
    request: dict[str, object],
    concrete_model: str,
    endpoint: str,
    timeout: float,
) -> dict[str, object]:
    upstream_request = dict(request)
    upstream_request["model"] = concrete_model
    upstream_request["stream"] = False
    # Every consumer asks for a non-reasoning answer with FastFlowLM's `think`
    # flag. llama.cpp takes that instruction through the chat template instead,
    # and IGNORES the bare flag: measured 2026-08-29 against the served model,
    # `think: false` still spent the whole token budget on reasoning_content and
    # returned empty content, which is a silent failure for both the drain's
    # JSON and print's classifier. Translate it here — the seam is the one place
    # that knows the concrete backend, and consumers keep naming one flag.
    if upstream_request.pop("think", None) is False:
        template_kwargs = dict(upstream_request.get("chat_template_kwargs") or {})
        template_kwargs.setdefault("enable_thinking", False)
        upstream_request["chat_template_kwargs"] = template_kwargs
    encoded = json.dumps(
        upstream_request,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    http_request = urllib.request.Request(
        f"{endpoint}{CHAT_COMPLETIONS_PATH}",
        data=encoded,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(http_request, timeout=timeout) as response:
            raw_response = read_bounded(response)
    except urllib.error.HTTPError as exc:
        detail = " ".join(exc.read(2048).decode("utf-8", errors="replace").split())
        raise UtilityModelError(
            f"llama-swap returned HTTP {exc.code} for model "
            f"{concrete_model}: {detail}"
        ) from exc
    except urllib.error.URLError as exc:
        raise UtilityModelError(
            f"llama-swap at {endpoint} did not answer: {exc.reason}"
        ) from exc
    except TimeoutError as exc:
        raise UtilityModelError(
            f"llama-swap at {endpoint} did not answer within {timeout:g}s; "
            f"a cold load of {concrete_model} can take minutes"
        ) from exc
    except OSError as exc:
        raise UtilityModelError(
            f"utility request to {endpoint} failed: {exc}"
        ) from exc

    try:
        result = json.loads(raw_response)
        content = result["choices"][0]["message"]["content"]
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        KeyError,
        IndexError,
        TypeError,
    ) as exc:
        raise UtilityModelError(
            f"llama-swap returned a malformed chat response: {exc}"
        ) from exc
    if not isinstance(result, dict) or not isinstance(content, str):
        raise UtilityModelError("llama-swap chat response has no textual content")

    # Keep the concrete deployment behind the stable boundary in both directions.
    result["model"] = STABLE_MODEL_ID
    return result


def run_once(args: argparse.Namespace, request: dict[str, object]) -> dict[str, object]:
    if args.timeout <= 0:
        raise UtilityModelError("--timeout must be greater than zero")
    if args.context_tokens < 512:
        raise UtilityModelError("declared utility context must be at least 512 tokens")
    endpoint = normalize_endpoint(args.endpoint)
    return send_request(request, args.concrete_model, endpoint, args.timeout)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        request = load_request(sys.stdin.buffer)
        result = run_once(args, request)
        json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    except UtilityModelError as exc:
        print(f"utility-model: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
