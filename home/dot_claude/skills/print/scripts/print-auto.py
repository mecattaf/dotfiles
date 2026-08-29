#!/usr/bin/env python3
"""Local print orchestration: markdown in, typeset PDF out.

The calling session hands over ONLY a markdown file (plus an optional
intent hint and --print). Every typesetting decision — profile, one-page
enforcement, duplex, filename, title — used to be made by the
request-scoped NPU utility model (`utility-model` wrapper), then executed
by print-paper.py. The model had no grammar enforcement, so the JSON was
validated here with one corrective retry and a deterministic fallback.

AUTO-CLASSIFICATION IS RETIRED (NPU decommissioned 2026-08-29). The NPU is
off on both Strix Halo boxes permanently and the `utility-model` wrapper is
no longer installed anywhere, so the classification call cannot succeed and
no configuration switch brings it back. That is deliberately NON-FATAL:
printing is the point of this script, so the retired classifier falls
straight through to the same deterministic default that always backed the
model (source-serif, duplex, no one-page enforcement, kebab-case filename
from the input stem), records provenance "retired" in decision.json, and
renders exactly as before. Everything downstream of the decision — the job
directory, the render-verify-submit gate, quiet hours — is unchanged.
Callers that want a specific profile or layout should drive print-paper.py
directly; see the skill's Manual rendering section. `--intent` is still
accepted so existing callers keep working, but nothing consumes it now.

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


UTILITY_RETIRED = "auto-classification retired (NPU decommissioned 2026-08-29)"


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
    """The deterministic decision that always backed the classifier, and is
    now the only decision this script makes."""
    return {
        "profile": "source-serif",
        "require_one_page": False,
        "sides": "duplex",
        "filename": re.sub(r"[^a-z0-9]+", "-", source.stem.lower()).strip("-") + ".pdf",
        "title": source.stem,
    }


def decide(text: str, intent: str | None, source: Path) -> tuple[dict, str]:
    """Returns (decision, provenance).

    Provenance is always "retired" since the 2026-08-29 NPU decommission;
    receipts already on disk under ~/Paper/jobs still carry npu / npu-retry
    / fallback from when a model made the call, so leave those values alone
    when reading old job directories.

    `text` and `intent` are still accepted so every call site and caller
    argument stays unchanged, but nothing reads them now — the classifier
    that consumed them is gone and is not coming back. A missing classifier
    is deliberately not fatal: rendering and printing are what this script
    is for, so it falls through to the deterministic default and says so
    once on stderr.
    """
    del text, intent
    print(f"print-auto: {UTILITY_RETIRED}; rendering with the deterministic "
          f"default (source-serif, duplex, no one-page enforcement). Drive "
          f"print-paper.py directly when the profile or layout matters.",
          file=sys.stderr)
    return default_decision(source), "retired"


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
