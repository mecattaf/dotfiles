#!/usr/bin/env python3
"""Bounded Markdown/PDF exchange between the NAS print owner and compute.

The worker gets document bytes and render options only. It has no queue,
credentials, or receipt authority. Temporary compute files disappear when the
request ends. The NAS keeps the original source and validates the returned PDF
before its ordinary quiet-hours and printer-receipt gates.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import selectors
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MAX_SOURCE = 2 * 1024 * 1024
MAX_PDF = 64 * 1024 * 1024
MAX_RESPONSE = 90 * 1024 * 1024
MAX_LOG = 64 * 1024
TIMEOUT = 1800
HERE = Path(__file__).resolve().parent


def exchange(command: list[str], request: bytes, *, output_limit: int = MAX_RESPONSE) -> tuple[int, bytes, bytes]:
    """Drain both SSH pipes without unbounded capture or a pipe deadlock."""
    # stdin from a regular file avoids blocking on a large source before the
    # stdout/stderr readers are attached. No secret environment is serialized.
    with tempfile.TemporaryFile() as source:
        source.write(request)
        source.seek(0)
        with subprocess.Popen(command, stdin=source, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE) as proc:
            chunks: dict[str, bytearray] = {"out": bytearray(), "err": bytearray()}
            deadline = time.monotonic() + TIMEOUT
            try:
                with selectors.DefaultSelector() as streams:
                    streams.register(proc.stdout, selectors.EVENT_READ, "out")
                    streams.register(proc.stderr, selectors.EVENT_READ, "err")
                    while streams.get_map():
                        if time.monotonic() > deadline:
                            raise ValueError(f"compute render exceeded {TIMEOUT}s")
                        for key, _ in streams.select(timeout=1):
                            data = os.read(key.fileobj.fileno(), 65536)
                            if not data:
                                streams.unregister(key.fileobj)
                                continue
                            buf = chunks[key.data]
                            buf.extend(data)
                            if len(buf) > (output_limit if key.data == "out" else MAX_LOG):
                                raise ValueError("compute render exceeded its response/log limit")
                    rc = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
            except BaseException:
                proc.kill()
                proc.wait()
                raise
    return rc, bytes(chunks["out"]), bytes(chunks["err"])


def render_flags(args: argparse.Namespace) -> list[str]:
    flags: list[str] = []
    for key in ("target_pages", "page_slack", "profile", "sides"):
        value = getattr(args, key)
        if value is not None:
            flags += ["--" + key.replace("_", "-"), str(value)]
    return flags


def client(args: argparse.Namespace) -> int:
    with args.input.open("rb") as stream:
        source = stream.read(MAX_SOURCE + 1)
    if len(source) > MAX_SOURCE:
        raise ValueError(f"Markdown exceeds {MAX_SOURCE} bytes")
    host = os.environ.get("PAPER_RENDER_HOST", "strix-coordinator")
    if host not in ("strix-coordinator", "strix-worker"):
        raise ValueError("PAPER_RENDER_HOST must name a Strix compute host")
    program = os.environ.get("PAPER_RENDER_PROGRAM", "/run/current-system/sw/bin/paper-render")
    if not program.startswith("/") or "\x00" in program:
        raise ValueError("PAPER_RENDER_PROGRAM must be an absolute compute path")
    command = ["ssh", "-T", "-oBatchMode=yes", "-oStrictHostKeyChecking=yes",
               "-oForwardAgent=no", "-oIdentitiesOnly=yes", "-oConnectTimeout=10",
               "-i", "/run/agenix/ssh-user-key", "--", host,
               "exec " + shlex.quote(program)]
    request = {"version": 1, "source": source.decode("utf-8"),
               "flags": render_flags(args)}
    rc, output, error = exchange(command, json.dumps(request, ensure_ascii=False).encode("utf-8"))
    if rc != 0:
        raise ValueError(f"compute renderer exited {rc}: {error.decode(errors='replace')[-4000:]}")
    response = json.loads(output)
    if not isinstance(response, dict) or response.get("version") != 1:
        raise ValueError("invalid compute render protocol version")
    if response.get("returncode") not in (0, 3):
        raise ValueError("compute renderer returned an invalid render status")
    decision = response["decision"]
    if not isinstance(decision, dict) or not isinstance(decision.get("decision"), dict):
        raise ValueError("compute renderer returned no decision object")
    filename = decision["decision"].get("filename")
    if not isinstance(filename, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.pdf", filename):
        raise ValueError("compute renderer returned an invalid PDF filename")
    pdf = base64.b64decode(response["pdf_base64"], validate=True)
    if len(pdf) > MAX_PDF or not pdf.startswith(b"%PDF-"):
        raise ValueError("compute renderer returned an oversized or invalid PDF")
    if hashlib.sha256(pdf).hexdigest() != response["pdf_sha256"]:
        raise ValueError("compute PDF checksum differs from the response")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    pdf_path = args.output_dir / filename
    pdf_path.write_bytes(pdf)
    # Remote paths are temporary and are never queue destinations.
    decision["source"] = str(args.input.resolve())
    decision["original_input"] = str(args.input.resolve())
    decision["pdf"] = str(pdf_path.resolve())
    decision["render_host"] = host
    (args.output_dir / "decision.json").write_text(json.dumps(decision, indent=2) + "\n")
    print(str(response.get("log", ""))[-MAX_LOG:])
    return response["returncode"]


def worker() -> int:
    # Even UTF-8 source made entirely of control characters needs up to six
    # JSON bytes per source byte, plus the fixed options envelope.
    limit = MAX_SOURCE * 6 + 4096
    payload = sys.stdin.buffer.read(limit + 1)
    if len(payload) > limit:
        raise ValueError("render request exceeds its byte limit")
    request = json.loads(payload)
    if not isinstance(request, dict) or request.get("version") != 1:
        raise ValueError("invalid render request version")
    source = request.get("source")
    if not isinstance(source, str) or len(source.encode("utf-8")) > MAX_SOURCE:
        raise ValueError("render source must be bounded Markdown text")
    flags = request.get("flags", [])
    if not isinstance(flags, list) or any(not isinstance(f, str) for f in flags):
        raise ValueError("render flags must be strings")
    # Reuse the client parser, so a request can override only render options;
    # no remote filename, output directory or executable comes over the wire.
    options = parser().parse_args(["source.md", "--output-dir", "/unused", *flags])
    if any(flag in flags for flag in ("--worker", "--output-dir", "--input")):
        raise ValueError("request tried to override worker paths")
    with tempfile.TemporaryDirectory(prefix="paper-render-") as raw:
        job = Path(raw)
        source_path = job / "source.md"
        source_path.write_text(source)
        program = os.environ.get("PAPER_PRINT_AUTO", str(HERE / "scripts/print-auto.py"))
        rc, stdout, stderr = exchange([sys.executable, program, str(source_path),
                                      "--output-dir", str(job), *render_flags(options)],
                                     b"", output_limit=MAX_LOG)
        log = (stdout + stderr).decode(errors="replace")[-MAX_LOG:]
        if rc not in (0, 3):
            print(log, file=sys.stderr)
            return 1
        decision = json.loads((job / "decision.json").read_text())
        filename = decision["decision"]["filename"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.pdf", filename):
            raise ValueError("renderer produced an invalid PDF filename")
        pdf_path = job / filename
        if pdf_path.stat().st_size > MAX_PDF:
            raise ValueError("rendered PDF exceeds its byte limit")
        pdf = pdf_path.read_bytes()
        json.dump({"version": 1, "returncode": rc, "decision": decision,
                   "pdf_base64": base64.b64encode(pdf).decode("ascii"),
                   "pdf_sha256": hashlib.sha256(pdf).hexdigest(), "log": log}, sys.stdout)
        sys.stdout.write("\n")
    return 0


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", type=Path)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--target-pages", type=int)
    ap.add_argument("--page-slack", type=int)
    ap.add_argument("--profile", choices=("garamond", "baskerville", "source-serif", "times"))
    ap.add_argument("--sides", choices=("one-sided", "duplex"))
    return ap


def main() -> int:
    try:
        return worker() if sys.argv[1:] == ["--worker"] else client(parser().parse_args())
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as exc:
        print(f"paper-render: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
