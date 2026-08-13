#!/usr/bin/env python3
"""Local-model print orchestration: markdown in, typeset PDF out.

The calling session hands over ONLY a markdown file (plus an optional
intent hint and --print). Every typesetting decision — profile, one-page
enforcement, duplex, filename, title — is made by the request-scoped NPU
utility model (`utility-model` wrapper, FastFlowLM qwen3:4b), then executed
by print-paper.py. FastFlowLM has no grammar enforcement, so the JSON is
validated here with one corrective retry and a deterministic fallback.

Usage:
    print-auto.py INPUT.md [--intent brief|document|form|specimen]
                  [--print] [--output-dir DIR]
"""

import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PRINT_PAPER = SCRIPT_DIR / "print-paper.py"

PROFILES = {"garamond", "baskerville", "source-serif", "times"}
SIDES = {"duplex", "one-sided"}

SYSTEM = (
    "You are the typesetting controller for a local print pipeline. Decide "
    "how to render the given Markdown document as an A4 PDF. Output ONLY a "
    "JSON object, no prose, no code fences, exactly these keys: "
    '{"profile": "garamond"|"baskerville"|"source-serif"|"times", '
    '"require_one_page": true|false, "sides": "duplex"|"one-sided", '
    '"filename": "<kebab-case>.pdf", "title": "<short title>"}. '
    "Rules: source-serif = contemporary editorial default (decision briefs, "
    "plans, technical docs); garamond = literary/reflective/essayistic; "
    "baskerville = formal/ceremonial; times = academic papers. "
    "require_one_page only for clearly single-page artifacts (a short form, "
    "a specimen sheet, a one-page checklist). one-sided only for "
    "forms/worksheets meant to be scanned or posted; otherwise duplex. "
    "/no_think"
)


def doc_digest(text: str, intent: str | None) -> str:
    lines = text.splitlines()
    words = len(text.split())
    checkboxes = len(re.findall(r"^\s*[-*]\s*\[[ xX]?\]", text, re.M))
    head = "\n".join(lines[:60])
    parts = [f"Words: {words}. Markdown checkboxes: {checkboxes}."]
    if intent:
        parts.append(f"Caller intent hint: {intent}.")
    parts.append("Document (first lines):\n\n" + head)
    return "\n".join(parts)


def ask_utility(user_content: str) -> dict:
    req = {
        "model": "utility",
        "temperature": 0,
        "max_tokens": 300,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_content},
        ],
    }
    out = subprocess.run(
        ["utility-model"], input=json.dumps(req).encode(),
        capture_output=True, timeout=600)
    if out.returncode != 0:
        raise RuntimeError(f"utility-model failed: {out.stderr.decode()[:400]}")
    resp = json.loads(out.stdout)
    return resp["choices"][0]["message"]["content"]


def validate(raw: str) -> dict | str:
    """Return the decision dict, or a string describing what was wrong."""
    try:
        d = json.loads(raw.strip())
    except json.JSONDecodeError as e:
        return f"not valid JSON: {e}"
    missing = {"profile", "require_one_page", "sides", "filename", "title"} - set(d)
    if missing:
        return f"missing keys: {sorted(missing)}"
    if d["profile"] not in PROFILES:
        return f"profile must be one of {sorted(PROFILES)}"
    if d["sides"] not in SIDES:
        return f"sides must be one of {sorted(SIDES)}"
    if not isinstance(d["require_one_page"], bool):
        return "require_one_page must be a boolean"
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.pdf", str(d["filename"])):
        return "filename must be kebab-case ending in .pdf"
    return d


def decide(text: str, intent: str | None, source: Path) -> tuple[dict, str]:
    """Returns (decision, provenance) where provenance is npu|npu-retry|fallback."""
    digest = doc_digest(text, intent)
    raw = ask_utility(digest)
    d = validate(raw)
    if isinstance(d, dict):
        return d, "npu"
    raw2 = ask_utility(
        digest + f"\n\nYour previous output was rejected ({d}). "
        "Output only the corrected JSON object.")
    d2 = validate(raw2)
    if isinstance(d2, dict):
        return d2, "npu-retry"
    fallback = {
        "profile": "source-serif",
        "require_one_page": False,
        "sides": "duplex",
        "filename": re.sub(r"[^a-z0-9]+", "-", source.stem.lower()).strip("-") + ".pdf",
        "title": source.stem,
    }
    print(f"print-auto: NPU decision invalid twice ({d2}); using fallback",
          file=sys.stderr)
    return fallback, "fallback"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path)
    ap.add_argument("--intent", choices=["brief", "document", "form", "specimen"])
    ap.add_argument("--print", dest="do_print", action="store_true")
    ap.add_argument("--output-dir", type=Path)
    args = ap.parse_args()

    text = args.input.read_text()
    decision, provenance = decide(text, args.intent, args.input)

    # Every print is a job directory under ~/Paper/jobs — the same tree the
    # scanner's inbound batches land in, and the future reunion point for
    # annotated pages coming back through the loop. The ordering session
    # hands over a markdown file from anywhere (scratchpad included); it is
    # archived here as source.md so working trees stay unpolluted.
    if args.output_dir:
        jobdir = args.output_dir
    else:
        now = datetime.datetime.now()
        slug = re.sub(r"[^a-z0-9]+", "-", args.input.stem.lower()).strip("-")
        jobdir = (Path.home() / "Paper" / "jobs" /
                  f"{now:%Y-%m-%d}-print-{slug}-{now:%H%M%S}")
    jobdir.mkdir(parents=True, exist_ok=True)
    source = jobdir / "source.md"
    if args.input.resolve() != source.resolve():
        shutil.copy2(args.input, source)
    outpath = jobdir / decision["filename"]

    cmd = [sys.executable, str(PRINT_PAPER), str(source),
           "--profile", decision["profile"], "-o", str(outpath)]
    if decision["require_one_page"]:
        cmd.append("--require-one-page")
    if decision["sides"] == "one-sided":
        cmd += ["--sides", "one-sided"]
    if args.do_print:
        cmd.append("--print")
    rc = subprocess.run(cmd).returncode
    if rc == 0:
        receipt = {"decision": decision, "provenance": provenance,
                   "source": str(source), "original_input": str(args.input),
                   "pdf": str(outpath), "printed": args.do_print}
        (jobdir / "decision.json").write_text(
            json.dumps(receipt, indent=2) + "\n")
        print(f"print-auto: {provenance} decision -> {outpath}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
