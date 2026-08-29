#!/usr/bin/env python3
"""Request-scoped owner for the local FastFlowLM utility model.

The application-facing protocol is one OpenAI-compatible chat-completions
request on stdin and one response on stdout.  Callers may name only the stable
model ID ``utility``.  Nix supplies the concrete FastFlowLM tag and executable.

There is deliberately no long-running service here: each invocation takes the
NPU lock, starts its own loopback-only FLM child, performs one request, and
stops the child before returning.

Not installed anywhere since 2026-08-29 (NPU decommission).  Kept in-tree
because the ai-memory flake check imports this file by path as the module
under test.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import BinaryIO


STABLE_MODEL_ID = "utility"
MAX_REQUEST_BYTES = 2 * 1024 * 1024
MAX_RESPONSE_BYTES = 4 * 1024 * 1024


class UtilityModelError(RuntimeError):
    """A bounded, user-facing utility-model failure."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one request through the short-lived local utility model"
    )
    parser.add_argument(
        "--flm",
        required=True,
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
        default=600.0,
        help="Total lock, startup, and request timeout in seconds (default: 600)",
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


def runtime_lock_path() -> Path:
    configured = os.environ.get("XDG_RUNTIME_DIR")
    runtime_root = (
        Path(configured)
        if configured
        else Path(tempfile.gettempdir()) / f"ai-memory-{os.getuid()}"
    )
    lock_dir = runtime_root / "ai-memory"
    lock_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = lock_dir.lstat()
    if stat.S_ISLNK(info.st_mode) or info.st_uid != os.getuid():
        raise UtilityModelError(f"unsafe utility lock directory: {lock_dir}")
    os.chmod(lock_dir, 0o700)
    return lock_dir / "utility-model.lock"


def acquire_lock(path: Path, deadline: float) -> BinaryIO:
    flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    lock = os.fdopen(fd, "a+b", buffering=0)
    while True:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return lock
        except BlockingIOError:
            if time.monotonic() >= deadline:
                lock.close()
                raise UtilityModelError("timed out waiting for the local utility NPU")
            time.sleep(0.1)


def reserve_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def remaining_seconds(deadline: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise UtilityModelError("utility-model request timed out")
    return remaining


def read_bounded(response: BinaryIO) -> bytes:
    body = response.read(MAX_RESPONSE_BYTES + 1)
    if len(body) > MAX_RESPONSE_BYTES:
        raise UtilityModelError(
            f"utility response exceeds the {MAX_RESPONSE_BYTES}-byte limit"
        )
    return body


def wait_until_ready(
    process: subprocess.Popen[bytes],
    base_url: str,
    deadline: float,
    log: BinaryIO,
) -> None:
    last_error = "server has not accepted a request"
    while True:
        return_code = process.poll()
        if return_code is not None:
            raise UtilityModelError(
                f"FastFlowLM exited during startup ({return_code}): "
                f"{tail_log(log)}"
            )

        remaining = remaining_seconds(deadline)
        try:
            with urllib.request.urlopen(
                f"{base_url}/v1/models",
                timeout=min(1.0, remaining),
            ) as response:
                if response.status == 200:
                    read_bounded(response)
                    return
                last_error = f"health endpoint returned HTTP {response.status}"
        except (OSError, urllib.error.URLError) as exc:
            last_error = str(exc)

        if remaining <= 0.1:
            raise UtilityModelError(
                "timed out waiting for FastFlowLM readiness: "
                f"{last_error}; {tail_log(log)}"
            )
        time.sleep(min(0.1, remaining))


def send_request(
    request: dict[str, object],
    concrete_model: str,
    base_url: str,
    deadline: float,
) -> dict[str, object]:
    upstream_request = dict(request)
    upstream_request["model"] = concrete_model
    upstream_request["stream"] = False
    encoded = json.dumps(
        upstream_request,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    http_request = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=encoded,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(
            http_request,
            timeout=remaining_seconds(deadline),
        ) as response:
            raw_response = read_bounded(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read(2048).decode("utf-8", errors="replace")
        raise UtilityModelError(
            f"FastFlowLM returned HTTP {exc.code}: {detail}"
        ) from exc
    except (OSError, urllib.error.URLError) as exc:
        raise UtilityModelError(f"FastFlowLM request failed: {exc}") from exc

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
            f"FastFlowLM returned a malformed chat response: {exc}"
        ) from exc
    if not isinstance(result, dict) or not isinstance(content, str):
        raise UtilityModelError("FastFlowLM chat response has no textual content")

    # Keep the concrete deployment behind the stable boundary in both directions.
    result["model"] = STABLE_MODEL_ID
    return result


def tail_log(log: BinaryIO, limit: int = 2048) -> str:
    try:
        log.flush()
        log.seek(0, os.SEEK_END)
        size = log.tell()
        log.seek(max(0, size - limit))
        text = log.read(limit).decode("utf-8", errors="replace")
    except OSError:
        return "no FastFlowLM log available"
    compact = " ".join(text.split())
    return compact or "no FastFlowLM log output"


def stop_child(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    for child_signal, wait_seconds in (
        (signal.SIGINT, 8.0),
        (signal.SIGTERM, 3.0),
        (signal.SIGKILL, 1.0),
    ):
        try:
            os.killpg(process.pid, child_signal)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=wait_seconds)
            return
        except subprocess.TimeoutExpired:
            continue


def run_once(args: argparse.Namespace, request: dict[str, object]) -> dict[str, object]:
    if args.timeout <= 0:
        raise UtilityModelError("--timeout must be greater than zero")
    if args.context_tokens < 512:
        raise UtilityModelError("declared utility context must be at least 512 tokens")

    deadline = time.monotonic() + args.timeout
    lock = acquire_lock(runtime_lock_path(), deadline)
    process: subprocess.Popen[bytes] | None = None
    try:
        port = reserve_loopback_port()
        base_url = f"http://127.0.0.1:{port}"
        environment = os.environ.copy()
        environment["FLM_DISABLE_UPDATE_CHECK"] = "1"
        with tempfile.TemporaryFile(mode="w+b") as log:
            try:
                process = subprocess.Popen(
                    [
                        args.flm,
                        "serve",
                        args.concrete_model,
                        "--host",
                        "127.0.0.1",
                        "--port",
                        str(port),
                        "--ctx-len",
                        str(args.context_tokens),
                        "--cors",
                        "0",
                        "--quiet",
                    ],
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    env=environment,
                    start_new_session=True,
                )
            except OSError as exc:
                raise UtilityModelError(
                    f"could not start local FastFlowLM: {exc}"
                ) from exc

            try:
                wait_until_ready(process, base_url, deadline, log)
                return send_request(
                    request,
                    args.concrete_model,
                    base_url,
                    deadline,
                )
            finally:
                stop_child(process)
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()


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
