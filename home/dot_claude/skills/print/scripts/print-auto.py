#!/usr/bin/env python3
"""Local print orchestration: markdown in, typeset PDF out.

The calling session hands over ONLY a markdown file (plus an optional
intent hint and --print). Every typesetting decision — profile, one-page
enforcement, duplex, filename, title — is made by the request-scoped local
utility model (`utility-model` wrapper), then executed by print-paper.py.
The model has no grammar enforcement, so the JSON is validated here with
one corrective retry and a deterministic fallback.

The seam behind that wrapper MIGRATED on 2026-08-29: it used to be the
XDNA2 NPU running FastFlowLM, which is decommissioned permanently; it is
now the GPU roster, where llama-swap serves qwen3.6-35B-A3B behind the
stable id `utility`. The wrapper exists on the coordinator only, and its
first request after an idle unload cold-loads a ~40 GB model, so the
classification call is given a generous timeout.

Classification failure is NON-FATAL, and deliberately so: printing is the
point of this script. Anything at all going wrong at the seam — no wrapper
on this host, llama-swap unreachable, a timeout, two invalid answers —
falls through to the same deterministic default that has always backed the
model (source-serif, duplex, no one-page enforcement, kebab-case filename
from the input stem), records provenance "fallback" in decision.json with
the reason, says so once on stderr, and renders. Everything downstream of
the decision — the job directory, the render-verify-submit gate, quiet
hours — is untouched by which path produced it.

Usage:
    print-auto.py INPUT.md [--intent brief|document|form|specimen]
                  [--print] [--target-pages N] [--output-dir DIR]

Render-verify-submit gate (issue #227): this script ALWAYS renders first,
without submitting. If --print was passed, submission is a second, separate
subprocess call made only after the render is on disk. When --target-pages
is given, --print is refused (exit 3, nothing sent to CUPS) unless the
rendered page count matches exactly — so a session iterating toward a
length target can call this repeatedly with zero pages ever reaching the
printer, and the eventual physical print happens exactly once.
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

# llama-swap cold-loads the utility model on the first request after an idle
# unload; that alone can take minutes on a ~40 GB Vulkan backend.
UTILITY_TIMEOUT_SECONDS = 1200

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
    "forms/worksheets meant to be scanned or posted; otherwise duplex."
)


class ClassifierUnavailable(RuntimeError):
    """The utility seam could not answer. Never fatal — see decide()."""


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


def ask_utility(user_content: str) -> str:
    """One classification round trip through the GPU utility seam.

    Every way this can fail — the wrapper absent because we are not on the
    coordinator, llama-swap down or still cold-loading past the budget, a
    non-zero exit, an unparseable envelope — becomes one ClassifierUnavailable
    so decide() has a single thing to catch.
    """
    # `think: False` is the seam's flag, not the backend's; the wrapper
    # translates it for whatever engine is behind the stable id. Without it a
    # reasoning model burns the whole budget before emitting any JSON.
    req = {
        "model": "utility",
        "temperature": 0,
        "max_tokens": 300,
        "think": False,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_content},
        ],
    }
    try:
        out = subprocess.run(
            ["utility-model"], input=json.dumps(req).encode(),
            capture_output=True, timeout=UTILITY_TIMEOUT_SECONDS)
    except FileNotFoundError as exc:
        raise ClassifierUnavailable(
            "utility-model is not installed here; the GPU utility model "
            "(qwen3.6-35B-A3B through llama-swap) is served on the "
            "coordinator only") from exc
    except OSError as exc:
        raise ClassifierUnavailable(f"could not run utility-model: {exc}") from exc
    except subprocess.TimeoutExpired as exc:
        raise ClassifierUnavailable(
            f"utility-model did not answer within "
            f"{UTILITY_TIMEOUT_SECONDS}s") from exc
    if out.returncode != 0:
        raise ClassifierUnavailable(
            f"utility-model failed: {out.stderr.decode()[:400].strip()}")
    try:
        resp = json.loads(out.stdout)
        return resp["choices"][0]["message"]["content"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
        raise ClassifierUnavailable(
            f"utility-model returned a malformed response: {exc}") from exc


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


def pdf_page_count(path: Path) -> int | None:
    """Best-effort page count, mirroring print-paper.py's own pdfinfo/regex
    fallback, so the render-verify gate below works even before pdfinfo is
    on PATH."""
    pdfinfo = shutil.which("pdfinfo")
    if pdfinfo:
        out = subprocess.run([pdfinfo, str(path)], capture_output=True, text=True)
        if out.returncode == 0:
            match = re.search(r"^Pages:\s+(\d+)", out.stdout, re.M)
            if match:
                return int(match.group(1))
    payload = path.read_bytes()
    count = len(re.findall(rb"/Type\s*/Page\b", payload))
    return count or None


def default_decision(source: Path) -> dict:
    """The deterministic decision that backs the classifier whenever the
    utility seam cannot answer or answers invalidly."""
    return {
        "profile": "source-serif",
        "require_one_page": False,
        "sides": "duplex",
        "filename": re.sub(r"[^a-z0-9]+", "-", source.stem.lower()).strip("-") + ".pdf",
        "title": source.stem,
    }


def decide(text: str, intent: str | None, source: Path) -> tuple[dict, str]:
    """Returns (decision, provenance) where provenance is gpu|gpu-retry|fallback.

    Provenance named the engine before this script's seam moved to the GPU
    roster on 2026-08-29, so receipts already on disk under ~/Paper/jobs
    carry npu / npu-retry / retired instead; leave those values alone when
    reading old job directories.

    Nothing here is allowed to stop a print. The seam is reached inside one
    try block, and any ClassifierUnavailable — no wrapper on this host,
    llama-swap unreachable, timeout, malformed envelope — lands on the same
    deterministic default that two invalid model answers would.
    """
    digest = doc_digest(text, intent)
    try:
        raw = ask_utility(digest)
        d = validate(raw)
        if isinstance(d, dict):
            return d, "gpu"
        raw2 = ask_utility(
            digest + f"\n\nYour previous output was rejected ({d}). "
            "Output only the corrected JSON object.")
        d2 = validate(raw2)
        if isinstance(d2, dict):
            return d2, "gpu-retry"
        reason = f"utility decision invalid twice ({d2})"
    except ClassifierUnavailable as exc:
        reason = str(exc)
    print(f"print-auto: {reason}; using the deterministic fallback "
          f"(source-serif, duplex, no one-page enforcement). Drive "
          f"print-paper.py directly when the profile or layout matters.",
          file=sys.stderr)
    return default_decision(source), "fallback"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path)
    ap.add_argument("--intent", choices=["brief", "document", "form", "specimen"])
    ap.add_argument("--print", dest="do_print", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="print immediately even during quiet hours (00-06)")
    ap.add_argument("--output-dir", type=Path)
    ap.add_argument(
        "--target-pages", type=int, default=None,
        help=(
            "exact page count the user asked for (issue #227). When set, "
            "--print is refused unless the rendered PDF matches; the render "
            "itself always happens, so a session can call this repeatedly "
            "while iterating without --print and burn zero paper."
        ))
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

    # Quiet hours: physical printing sleeps between 00:00 and 06:00 so
    # overnight tally runs can queue their completion one-pagers without
    # waking the printer; a Persistent 06:05 user timer flushes
    # ~/Paper/outbox. --force ("/print force") bypasses the window.
    quiet = 0 <= datetime.datetime.now().hour < 6
    spool = args.do_print and quiet and not args.force
    sides_flag = "one-sided" if decision["sides"] == "one-sided" else "long-edge"

    # Render-verify-submit gate (issue #227): this invocation ALWAYS renders
    # without --print first — --print never reaches print-paper.py in the
    # same call that does the rendering. Submission, if it happens at all,
    # is a wholly separate subprocess call below, gated on the verified page
    # count. A session iterating toward a length target can therefore call
    # this repeatedly (with or without --print) and never put a page on the
    # printer until the render it inspected is the render it submits.
    render_cmd = [sys.executable, str(PRINT_PAPER), str(source),
                  "--profile", decision["profile"], "-o", str(outpath)]
    if decision["require_one_page"]:
        render_cmd.append("--require-one-page")
    if sides_flag == "one-sided":
        render_cmd += ["--sides", "one-sided"]
    rc = subprocess.run(render_cmd).returncode
    if rc != 0:
        return rc

    pages_rendered = pdf_page_count(outpath)
    if args.target_pages is None:
        length_check = "not_applicable"
    elif pages_rendered == args.target_pages:
        length_check = "pass"
    else:
        length_check = "fail"

    blocked = args.do_print and length_check == "fail"
    printed = False
    print_spooled = False

    if args.do_print and not blocked:
        if spool:
            outbox = Path.home() / "Paper" / "outbox"
            outbox.mkdir(parents=True, exist_ok=True)
            sides_lp = ("one-sided" if sides_flag == "one-sided"
                        else "two-sided-long-edge")
            entry = {"pdf": str(outpath), "sides": sides_lp,
                     "job_dir": str(jobdir),
                     "queued_at": datetime.datetime.now().isoformat(
                         timespec="seconds")}
            tmp = outbox / f".{jobdir.name}.tmp"
            tmp.write_text(json.dumps(entry, indent=2) + "\n")
            tmp.replace(outbox / f"{jobdir.name}.json")
            print_spooled = True
        else:
            # Submit the exact PDF that was just verified — a distinct
            # subprocess call that only ever submits, never renders, so
            # there is no window in which unrendered or unverified content
            # can be queued.
            submit_cmd = [sys.executable, str(PRINT_PAPER),
                          "--submit-only", str(outpath),
                          "--sides", sides_flag]
            submit_rc = subprocess.run(submit_cmd).returncode
            if submit_rc != 0:
                return submit_rc
            printed = True

    receipt = {"decision": decision, "provenance": provenance,
               "source": str(source), "original_input": str(args.input),
               "pdf": str(outpath),
               "pages_rendered": pages_rendered,
               "target_pages": args.target_pages,
               "length_check": length_check,
               "printed": printed,
               "print_spooled": print_spooled,
               "blocked": blocked}
    (jobdir / "decision.json").write_text(
        json.dumps(receipt, indent=2) + "\n")

    if blocked:
        print(f"print-auto: rendered {pages_rendered} page(s), target was "
              f"{args.target_pages} — NOT submitted. Revise the document and "
              f"re-run (with --print) once the render matches.",
              file=sys.stderr)
        return 3
    if print_spooled:
        print(f"print-auto: quiet hours — spooled for the 06:05 flush "
              f"({jobdir.name}); use --force to print now")
    print(f"print-auto: {provenance} decision -> {outpath} "
          f"({pages_rendered if pages_rendered is not None else 'unknown'} page(s), "
          f"length_check={length_check})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
