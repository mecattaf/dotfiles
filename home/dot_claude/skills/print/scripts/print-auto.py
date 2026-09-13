#!/usr/bin/env python3
"""Local print orchestration: markdown in, typeset PDF out.

The calling session hands over ONLY a markdown file (plus an optional
intent hint). Every typesetting decision — profile, one-page
enforcement, duplex, filename, title — is made by the request-scoped local
utility model (`utility-model` wrapper), then executed by print-paper.py.
The model has no grammar enforcement, so the JSON is validated here with
one corrective retry and a deterministic fallback.

The seam behind that wrapper is the fleet's one inference server: the
Halogen Flash server on the worker (http://worker:8731), which answers the
stable id `utility` through the wrapper. The wrapper exists on the
coordinator only. The server stays resident, but a request that lands while
the worker's unit is still starting waits on that start, so the
classification call is given a generous timeout.

Classification failure is NON-FATAL, and deliberately so: printing is the
point of this script. Anything at all going wrong at the seam — no wrapper
on this host, the Halogen server unreachable, a timeout, two invalid answers —
falls through to the same deterministic default that has always backed the
model (source-serif, duplex, no one-page enforcement, kebab-case filename
from the input stem), records provenance "fallback" in decision.json with
the reason, says so once on stderr, and renders. Everything downstream of
the decision — the job directory, the length gate, and everything
paper-daemon does afterwards — is untouched by which path produced it.

Usage:
    print-auto.py INPUT.md [--intent brief|document|form|specimen]
                  [--target-pages N] [--profile P] [--sides one-sided|duplex]
                  [--output-dir DIR]

Render only (dotfiles#384). This script never reaches CUPS. Physical
printing belongs to paper-daemon (pkgs/paper-daemon), which calls this
script on every file dropped into ~/Paper/intake/, reads decision.json, and
alone decides whether, when and how the PDF is submitted — so there is one
submitter and one receipt. --profile and --sides are the daemon's front-
matter overrides: they beat the classifier's answer, and decision.json
records which keys were overridden.

Length gate (issue #227): with --target-pages, decision.json carries
length_check pass|fail and a mismatch exits 3. The daemon rejects a fail
without printing; an agent iterating by hand burns zero paper either way.
"""

import argparse
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

# A request that lands while the worker's Halogen unit is still starting waits
# on that start, and a long document is a long generation.
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
    coordinator, the Halogen server down or still starting past the budget, a
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
            "utility-model is not installed here; the utility-model wrapper "
            "(which forwards to the Halogen server on the worker) is "
            "installed on the coordinator only") from exc
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

    Receipts already on disk under ~/Paper/jobs may carry the provenance
    values of earlier engines (npu / npu-retry / retired); leave those values
    alone when reading old job directories.

    Nothing here is allowed to stop a print. The seam is reached inside one
    try block, and any ClassifierUnavailable — no wrapper on this host, the
    Halogen server unreachable, timeout, malformed envelope — lands on the
    same deterministic default that two invalid model answers would.
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
    ap.add_argument("--output-dir", type=Path)
    ap.add_argument(
        "--target-pages", type=int, default=None,
        help=(
            "exact page count the user asked for (issue #227). decision.json "
            "records length_check pass|fail and a mismatch exits 3."
        ))
    ap.add_argument("--profile", choices=sorted(PROFILES),
                    help="override the classifier's profile (front matter)")
    ap.add_argument("--sides", choices=sorted(SIDES),
                    help="override the classifier's sides (front matter)")
    args = ap.parse_args()

    text = args.input.read_text()
    decision, provenance = decide(text, args.intent, args.input)
    overridden = []
    for key in ("profile", "sides"):
        value = getattr(args, key)
        if value is not None and value != decision[key]:
            decision[key] = value
            overridden.append(key)

    # Every render is a job directory. paper-daemon passes its own work
    # directory; a hand run without --output-dir lands under ~/Paper/jobs as
    # it always has. The markdown is archived there as source.md so working
    # trees stay unpolluted.
    if args.output_dir:
        jobdir = args.output_dir.expanduser().resolve()
    else:
        import datetime
        now = datetime.datetime.now()
        slug = re.sub(r"[^a-z0-9]+", "-", args.input.stem.lower()).strip("-")
        jobdir = (Path.home() / "Paper" / "jobs" /
                  f"{now:%Y-%m-%d}-print-{slug}-{now:%H%M%S}")
    jobdir.mkdir(parents=True, exist_ok=True)
    source = jobdir / "source.md"
    if args.input.resolve() != source.resolve():
        shutil.copy2(args.input, source)
    outpath = jobdir / decision["filename"]

    render_cmd = [sys.executable, str(PRINT_PAPER), str(source),
                  "--profile", decision["profile"], "-o", str(outpath)]
    if decision["require_one_page"]:
        render_cmd.append("--require-one-page")
    if decision["sides"] == "one-sided":
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

    receipt = {"decision": decision, "provenance": provenance,
               "overridden": overridden,
               "source": str(source), "original_input": str(args.input),
               "pdf": str(outpath),
               "pages_rendered": pages_rendered,
               "target_pages": args.target_pages,
               "length_check": length_check}
    (jobdir / "decision.json").write_text(
        json.dumps(receipt, indent=2) + "\n")

    print(f"print-auto: {provenance} decision -> {outpath} "
          f"({pages_rendered if pages_rendered is not None else 'unknown'} page(s), "
          f"length_check={length_check})")
    if length_check == "fail":
        print(f"print-auto: rendered {pages_rendered} page(s), target was "
              f"{args.target_pages}. Revise the document.", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
