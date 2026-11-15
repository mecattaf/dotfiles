#!/usr/bin/env python3
"""Local print orchestration: markdown in, typeset PDF out.

The calling session hands over ONLY a markdown file (plus an optional
intent hint). Every typesetting decision — profile, one-page
enforcement, duplex, filename, title — is made by the request-scoped local
utility model (`utility-model` wrapper), then executed by print-paper.py.
The model has no grammar enforcement, so the JSON is validated here with
one corrective retry and a deterministic fallback.

The seam behind that wrapper is the fleet's one inference server: the
local model server on the strix (http://strix-coordinator:8731), which answers the
stable id `utility` through the wrapper. The wrapper exists on the
fleet hosts through Nix. The server stays resident, but a request that lands while
its unit is still starting waits on that start, so the
classification call is given a generous timeout.

Classification failure is NON-FATAL, and deliberately so: printing is the
point of this script. Anything at all going wrong at the seam — no wrapper
on this host, the local model server unreachable, a timeout, two invalid answers —
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
script on every file dropped into the configured paper intake, reads decision.json, and
alone decides whether, when and how the PDF is submitted — so there is one
submitter and one receipt. --profile and --sides are the daemon's front-
matter overrides: they beat the classifier's answer, and decision.json
records which keys were overridden.

Layout gate (#673): every candidate render is measured from the PDF's own
text geometry. A heading alone on a page, a heading ending a page, a
near-empty page before a break, clipped or overlapping text, lost source
text, reading order or type below the readable floor is a hard defect:
decision.json carries quality_check fail, the run exits 3 and paper-daemon
rejects the job without printing. Candidates run standard, snug (same type
size, modest margins and leading), compact, dense, stopping at the first
clean fit; snug is also tried to save a duplex sheet or a short tail page.
Gufo then reviews the selected candidate's rendered page images with the
measured facts. Its review is recorded and can steer the choice between
clean candidates, but it can never pass a measured hard defect, and an
unavailable model leaves the mechanical gate in force.

Length gate (issue #227): with --target-pages, decision.json carries
length_check pass|fail and a miss exits 3. A render within --page-slack
pages of the target (default 2, Tom 2026-10-01) passes; --page-slack 0
asks for the exact count. The daemon rejects a fail
without printing; an agent iterating by hand burns zero paper either way.
"""

import argparse
import base64
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PRINT_PAPER = SCRIPT_DIR / "print-paper.py"

PROFILES = {"garamond", "baskerville", "source-serif", "times"}
SIDES = {"duplex", "one-sided"}

# A request that lands while the local model unit is still starting waits
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


def outline(text: str, *, max_headings: int = 80) -> str:
    """Whole-document structure, not just its opening (#673)."""
    lines = text.splitlines()
    headings = [line.strip() for line in lines if re.match(r"^#{1,6}\s+\S", line.strip())]
    tables, rows = [], 0
    for index, line in enumerate(lines):
        is_row = "|" in line and line.strip()
        if is_row:
            rows += 1
        if (not is_row or index == len(lines) - 1) and rows:
            if rows >= 3:
                tables.append(rows - 2)
            rows = 0
    items = len(re.findall(r"^\s*(?:[-*+]|\d+[.)])\s+", text, re.M))
    parts = [f"Headings ({len(headings)}): " + " / ".join(headings[:max_headings])
             + (" / ..." if len(headings) > max_headings else "")]
    parts.append(f"Tables: {len(tables)}" + (f", body rows {tables}" if tables else ""))
    parts.append(f"List items: {items}. Code fences: {text.count(chr(96) * 3) // 2}.")
    return "\n".join(parts)


def doc_digest(text: str, intent: str | None) -> str:
    lines = text.splitlines()
    words = len(text.split())
    checkboxes = len(re.findall(r"^\s*[-*]\s*\[[ xX]?\]", text, re.M))
    head = "\n".join(lines[:60])
    parts = [f"Words: {words}. Markdown checkboxes: {checkboxes}."]
    if intent:
        parts.append(f"Caller intent hint: {intent}.")
    parts.append("Structure:\n" + outline(text))
    parts.append("Document (first lines):\n\n" + head)
    return "\n".join(parts)


def ask_utility(user_content, *, system: str = SYSTEM, max_tokens: int = 300,
                timeout: float = UTILITY_TIMEOUT_SECONDS) -> str:
    """One classification round trip through the GPU utility seam.

    Every way this can fail — the wrapper absent because we are not on the
    strix, the local model server down or still starting past the budget, a
    non-zero exit, an unparseable envelope — becomes one ClassifierUnavailable
    so decide() has a single thing to catch.
    """
    # `think: False` is the seam's flag, not the backend's; the wrapper
    # translates it for whatever engine is behind the stable id. Without it a
    # reasoning model burns the whole budget before emitting any JSON.
    req = {
        "model": "utility",
        "temperature": 0,
        "max_tokens": max_tokens,
        "think": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user_content},
        ],
    }
    try:
        out = subprocess.run(
            ["utility-model"], input=json.dumps(req).encode(),
            capture_output=True, timeout=timeout)
    except FileNotFoundError as exc:
        raise ClassifierUnavailable(
            "utility-model is not installed here; the utility-model wrapper "
            "(which forwards to the local model server) is "
            "provided by the fleet profile") from exc
    except OSError as exc:
        raise ClassifierUnavailable(f"could not run utility-model: {exc}") from exc
    except subprocess.TimeoutExpired as exc:
        raise ClassifierUnavailable(
            f"utility-model did not answer within "
            f"{timeout:g}s") from exc
    if out.returncode != 0:
        raise ClassifierUnavailable(
            f"utility-model failed: {out.stderr.decode()[:400].strip()}")
    try:
        resp = json.loads(out.stdout)
        content = resp["choices"][0]["message"]["content"]
        if not isinstance(content, str):
            raise TypeError("message content is not text")
        return content
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
        raise ClassifierUnavailable(
            f"utility-model returned a malformed response: {exc}") from exc


def validate(raw: str) -> dict | str:
    """Return the decision dict, or a string describing what was wrong."""
    try:
        d = json.loads(raw.strip())
    except json.JSONDecodeError as e:
        return f"not valid JSON: {e}"
    if not isinstance(d, dict):
        return "decision must be a JSON object"
    missing = {"profile", "require_one_page", "sides", "filename", "title"} - set(d)
    if missing:
        return f"missing keys: {sorted(missing)}"
    if not isinstance(d["profile"], str) or d["profile"] not in PROFILES:
        return f"profile must be one of {sorted(PROFILES)}"
    if not isinstance(d["sides"], str) or d["sides"] not in SIDES:
        return f"sides must be one of {sorted(SIDES)}"
    if not isinstance(d["require_one_page"], bool):
        return "require_one_page must be a boolean"
    if not isinstance(d["filename"], str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}\.pdf", d["filename"]):
        return "filename must be kebab-case ending in .pdf"
    if not isinstance(d["title"], str) or len(d["title"]) > 500:
        return "title must be a string of at most 500 characters"
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


# --- Page review by Gufo (#673) --------------------------------------------

LAYOUTS = ("standard", "snug", "compact", "dense")
SAME_TYPE_LAYOUTS = ("standard", "snug")
REVIEW_DPI = 60
REVIEW_BATCH_PAGES = 6
# utility-model refuses requests over 2 MiB; base64 and the prompt fit in it.
REVIEW_BATCH_BYTES = 1_300_000
REVIEW_MAX_PAGES = 48
REVIEW_TIMEOUT_SECONDS = 300
REVIEW_BUDGET_SECONDS = 600

REVIEW_SYSTEM = (
    "You review rendered A4 pages of a document before it is printed. Each "
    "image is one page; the measured facts and outline give the structure. "
    "Fail a page that a careful reader would find badly laid out: a heading "
    "with no content after it, a nearly empty page that is not the last, "
    "clipped or overlapping text, a giant or dense table that is hard to "
    "read, awkward breaks. Do not fail an ordinary partly filled last page "
    "or an intentionally sparse form. Judge only what you see. Output ONLY a "
    'JSON object: {"pages": [{"page": <number>, "verdict": "pass"|"fail", '
    '"issues": ["<short issue>", ...]}]}, one entry per page shown.'
)


def validate_review(raw: str, expected: list[int]) -> list[dict] | str:
    try:
        data = json.loads(raw.strip())
    except json.JSONDecodeError as exc:
        return f"not valid JSON: {exc}"
    if not isinstance(data, dict) or not isinstance(data.get("pages"), list):
        return 'review must be an object with a "pages" array'
    pages = []
    for entry in data["pages"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("page"), int) \
                or isinstance(entry.get("page"), bool):
            return "each page entry needs an integer page"
        if entry.get("verdict") not in ("pass", "fail"):
            return "verdict must be pass or fail"
        issues = entry.get("issues", [])
        if not isinstance(issues, list) or not all(isinstance(i, str) for i in issues):
            return "issues must be a list of strings"
        pages.append({"page": entry["page"], "verdict": entry["verdict"],
                      "issues": [i[:300] for i in issues[:8]]})
    if sorted(p["page"] for p in pages) != expected:
        return f"the review must cover exactly pages {expected}"
    return pages


def page_images(pdf: Path, pages: int, workdir: Path) -> list[tuple[int, bytes]]:
    executable = shutil.which("pdftoppm")
    if not executable:
        raise ClassifierUnavailable("pdftoppm is unavailable; no page images to review")
    last = min(pages, REVIEW_MAX_PAGES)
    result = subprocess.run([executable, "-r", str(REVIEW_DPI), "-gray", "-png",
                             "-f", "1", "-l", str(last), str(pdf), str(workdir / "page")],
                            capture_output=True, timeout=300)
    if result.returncode:
        raise ClassifierUnavailable(f"pdftoppm failed: {result.stderr.decode()[:300]}")
    images = []
    for path in sorted(workdir.glob("page-*.png")):
        number = int(re.search(r"(\d+)\.png$", path.name)[1])
        images.append((number, path.read_bytes()))
    return images


def review_candidate(pdf: Path, measurement: dict, text: str, sides: str) -> dict:
    """Ask Gufo about actual page images. Never fatal and never a pass for a
    measured hard defect: the caller only asks about mechanically clean PDFs."""
    pages = measurement.get("pages") or 0
    facts = {key: measurement.get(key) for key in ("pages", "type", "page_facts", "advisories")}
    facts["sides"] = sides
    context = ("Measured layout facts:\n" + json.dumps(facts) + "\n\nOutline:\n" + outline(text))
    review = {"status": "reviewed", "model": "utility", "pages": [], "batches": 0}
    started = time.monotonic()
    try:
        with tempfile.TemporaryDirectory(prefix="print-review-") as raw:
            images = page_images(pdf, pages, Path(raw))
            batches: list[list[tuple[int, bytes]]] = [[]]
            size = 0
            for number, data in images:
                encoded = math.ceil(len(data) / 3) * 4
                if batches[-1] and (len(batches[-1]) >= REVIEW_BATCH_PAGES
                                    or size + encoded > REVIEW_BATCH_BYTES):
                    batches.append([])
                    size = 0
                batches[-1].append((number, data))
                size += encoded
            for batch in batches:
                if not batch:
                    continue
                if time.monotonic() - started > REVIEW_BUDGET_SECONDS:
                    review["status"] = "partial"
                    review["reason"] = f"review budget of {REVIEW_BUDGET_SECONDS}s spent"
                    break
                expected = [number for number, _ in batch]
                content = [{"type": "text", "text": context + f"\n\nPages shown: {expected}."}]
                for number, data in batch:
                    content.append({"type": "text", "text": f"Page {number}:"})
                    content.append({"type": "image_url", "image_url": {
                        "url": "data:image/png;base64," + base64.b64encode(data).decode()}})
                kwargs = {"system": REVIEW_SYSTEM, "max_tokens": 200 + 120 * len(batch),
                          "timeout": REVIEW_TIMEOUT_SECONDS}
                answer = validate_review(ask_utility(content, **kwargs), expected)
                if isinstance(answer, str):
                    content[0] = {"type": "text", "text": content[0]["text"]
                                  + f"\n\nYour previous output was rejected ({answer}). "
                                  "Output only the corrected JSON object."}
                    answer = validate_review(ask_utility(content, **kwargs), expected)
                review["batches"] += 1
                if isinstance(answer, str):
                    review["status"] = "invalid"
                    review["reason"] = f"page review invalid twice ({answer})"
                    break
                review["pages"].extend(answer)
            if pages > REVIEW_MAX_PAGES and review["status"] == "reviewed":
                review["status"] = "partial"
                review["reason"] = f"only the first {REVIEW_MAX_PAGES} pages were reviewed"
    except ClassifierUnavailable as exc:
        review["status"] = "unavailable"
        review["reason"] = str(exc)
    except (OSError, subprocess.TimeoutExpired) as exc:
        review["status"] = "unavailable"
        review["reason"] = f"page images could not be made: {exc}"
    failed = [p for p in review["pages"] if p["verdict"] == "fail"]
    review["verdict"] = ("concerns" if failed else
                         "pass" if review["status"] == "reviewed" else "degraded")
    review["failed_pages"] = [p["page"] for p in failed]
    return review


def sheets(pages: int | None, sides: str) -> int | None:
    if pages is None:
        return None
    return math.ceil(pages / 2) if sides == "duplex" else pages


def default_decision(source: Path) -> dict:
    """The deterministic decision that backs the classifier whenever the
    utility seam cannot answer or answers invalidly."""
    return {
        "profile": "source-serif",
        "require_one_page": False,
        "sides": "duplex",
        "filename": (re.sub(r"[^a-z0-9]+", "-", source.stem.lower()).strip("-")[:120] or "document") + ".pdf",
        "title": source.stem,
    }


def decide(text: str, intent: str | None, source: Path) -> tuple[dict, str]:
    """Returns (decision, provenance) where provenance is gpu|gpu-retry|fallback.

    Receipts already on disk under the configured paper jobs directory may carry the provenance
    values of earlier engines (npu / npu-retry / retired); leave those values
    alone when reading old job directories.

    Nothing here is allowed to stop a print. The seam is reached inside one
    try block, and any ClassifierUnavailable — no wrapper on this host, the
    local model server unreachable, timeout, malformed envelope — lands on the
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
            "page count the user asked for (issue #227). decision.json "
            "records length_check pass|fail and a miss exits 3."
        ))
    ap.add_argument(
        "--page-slack", type=int, default=2,
        help="pages either side of --target-pages that still pass (default 2)")
    ap.add_argument("--profile", choices=sorted(PROFILES),
                    help="override the classifier's profile (front matter)")
    ap.add_argument("--sides", choices=sorted(SIDES),
                    help="override the classifier's sides (front matter)")
    args = ap.parse_args()
    if args.target_pages is not None and args.target_pages < 1:
        ap.error("--target-pages must be positive")
    if args.page_slack < 0:
        ap.error("--page-slack must be non-negative")

    text = args.input.read_text()
    decision, provenance = decide(text, args.intent, args.input)
    overridden = []
    for key in ("profile", "sides"):
        value = getattr(args, key)
        if value is not None and value != decision[key]:
            decision[key] = value
            overridden.append(key)

    # Every render is a job directory. paper-daemon passes its own work
    # directory; a hand run without --output-dir lands under the configured paper jobs directory as
    # it always has. The markdown is archived there as source.md so working
    # trees stay unpolluted.
    if args.output_dir:
        jobdir = args.output_dir.expanduser().resolve()
    else:
        import datetime
        now = datetime.datetime.now()
        slug = re.sub(r"[^a-z0-9]+", "-", args.input.stem.lower()).strip("-")
        jobdir = (Path(subprocess.check_output(["utility-path", "paper"], text=True).strip()) / "jobs" /
                  f"{now:%Y-%m-%d}-print-{slug}-{now:%H%M%S}")
    jobdir.mkdir(parents=True, exist_ok=True)
    source = jobdir / "source.md"
    if args.input.resolve() != source.resolve():
        shutil.copy2(args.input, source)
    outpath = jobdir / decision["filename"]

    # Classify once, then measure bounded layouts. The document bytes never
    # change: no model rewriting, omitted paragraphs or padding to hit a count.
    target = args.target_pages
    slack = args.page_slack
    if target is None and decision["require_one_page"]:
        target, slack = 1, 0
    sides = decision["sides"]
    candidates_dir = jobdir / "candidates"
    candidates_dir.mkdir(exist_ok=True)

    def render(layout: str) -> dict | int:
        pdf = candidates_dir / f"{layout}.pdf"
        measure = candidates_dir / f"{layout}.json"
        measure.unlink(missing_ok=True)
        command = [sys.executable, str(PRINT_PAPER), str(source),
                   "--profile", decision["profile"], "-o", str(pdf),
                   "--measure", str(measure)]
        if sides == "one-sided":
            command += ["--sides", "one-sided"]
        command += ["--layout", layout, "--force"]
        rc = subprocess.run(command).returncode
        if rc != 0:
            return rc
        pages = pdf_page_count(pdf)
        try:
            measured = json.loads(measure.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            # The mechanical gate is mandatory: no measurement, no print.
            measured = {"status": "unmeasured", "pages": pages, "advisories": [],
                        "defects": [{"kind": "unmeasured", "severity": "hard",
                                     "detail": f"no layout measurement: {exc}"}]}
        defects = measured.get("defects", [])
        return {"layout": layout, "pdf": pdf, "pages": pages, "sheets": sheets(pages, sides),
                "hard": [d for d in defects if d.get("severity") == "hard"],
                "soft": [d for d in defects if d.get("severity") != "hard"],
                "measurement": measured}

    def fits(candidate: dict) -> bool:
        return target is None or (candidate["pages"] is not None
                                  and candidate["pages"] <= target + slack)

    def length_ok(candidate: dict) -> bool:
        return target is None or (candidate["pages"] is not None
                                  and abs(candidate["pages"] - target) <= slack)

    def preferred(a: dict, b: dict) -> dict:
        """Save a duplex sheet (11 → 10 pages saves one; 12 → 11 does not),
        then fewer soft findings; otherwise keep the larger layout."""
        if length_ok(b) != length_ok(a):
            return b if length_ok(b) else a
        key = lambda c: (c["sheets"] if c["sheets"] is not None else math.inf, len(c["soft"]))
        return b if key(b) < key(a) else a

    attempts: list[dict] = []
    chosen: dict | None = None
    for layout in LAYOUTS:
        candidate = render(layout)
        if isinstance(candidate, int):
            return candidate
        attempts.append(candidate)
        clean = not candidate["hard"]
        if clean and fits(candidate):
            chosen = candidate if chosen is None else preferred(chosen, candidate)
            odd_duplex = (sides == "duplex" and candidate["pages"] is not None
                          and candidate["pages"] > 1 and candidate["pages"] % 2 == 1)
            # Only a same-type-size layout is tried for a soft improvement.
            if layout == "standard" and (candidate["soft"] or odd_duplex):
                continue
            break
        if chosen is not None:
            break
        # Otherwise the render is defective or over the upper bound: try the
        # next layout. A short source is clean and within the bound, so it is
        # never padded or blown up into an arbitrary number of pages.

    if chosen is None:
        clean = [c for c in attempts if not c["hard"]]
        # The fewest pages; among equals the later layout, as before #673.
        chosen = (min(reversed(clean), key=lambda c: c["pages"] or math.inf)
                  if clean else attempts[-1])
    quality_check = "fail" if chosen["hard"] else "pass"

    reviews: list[dict] = []
    if quality_check == "pass" and length_ok(chosen):
        review = review_candidate(chosen["pdf"], chosen["measurement"], text, sides)
        review["layout"] = chosen["layout"]
        reviews.append(review)
        if review["verdict"] == "concerns":
            for other in attempts:
                if other is chosen or other["hard"] or not fits(other) or not length_ok(other):
                    continue
                second = review_candidate(other["pdf"], other["measurement"], text, sides)
                second["layout"] = other["layout"]
                reviews.append(second)
                if second["verdict"] == "pass":
                    chosen = other
                break
            if chosen["layout"] == review["layout"]:
                print(f"print-auto: Gufo raised concerns on page(s) {review['failed_pages']} "
                      "of a mechanically clean render; recorded in decision.json",
                      file=sys.stderr)
        elif review["verdict"] == "degraded":
            print(f"print-auto: page review {review['status']} ({review.get('reason')}); "
                  "the mechanical layout gate still applies", file=sys.stderr)

    shutil.copyfile(chosen["pdf"], outpath)
    pages_rendered = chosen["pages"]
    if target is None:
        length_check = "not_applicable"
    elif length_ok(chosen):
        length_check = "pass"
    else:
        length_check = "fail"
    final_review = next((r for r in reversed(reviews) if r["layout"] == chosen["layout"]), None)
    candidates = [{"layout": c["layout"], "pages": c["pages"], "sheets": c["sheets"],
                   "defects": c["hard"] + c["soft"],
                   "page_facts": c["measurement"].get("page_facts", []),
                   "type": c["measurement"].get("type")} for c in attempts]

    receipt = {"decision": decision, "provenance": provenance,
               "renderer": {"name": "weasyprint", "version": os.environ.get("PAPER_RENDERER_VERSION")},
               "overridden": overridden,
               "source": str(source), "original_input": str(args.input),
               "pdf": str(outpath),
               "pages_rendered": pages_rendered,
               "target_pages": target,
               "page_slack": slack,
               "render_attempts": [{"layout": c["layout"], "pages": c["pages"]}
                                   for c in attempts],
               "layout": chosen["layout"],
               "length_check": length_check,
               "quality_check": quality_check,
               "quality": {"defects": chosen["hard"], "soft": chosen["soft"],
                           "advisories": chosen["measurement"].get("advisories", [])},
               "candidates": candidates,
               "page_reviews": reviews,
               "page_review": (final_review or {"status": "not_run",
                                                "reason": "no mechanically clean render "
                                                          "within the page target"})}
    (jobdir / "decision.json").write_text(
        json.dumps(receipt, indent=2) + "\n")

    print(f"print-auto: {provenance} decision -> {outpath} "
          f"({pages_rendered if pages_rendered is not None else 'unknown'} page(s), "
          f"length_check={length_check}, quality_check={quality_check}, "
          f"layout={chosen['layout']})")
    if quality_check == "fail":
        print("print-auto: layout defects block printing: " + "; ".join(
            f"{d['kind']}" + (f" (page {d['page']})" if "page" in d else "")
            for d in chosen["hard"]) + f" after {len(attempts)} layout(s).", file=sys.stderr)
        return 3
    if length_check == "fail":
        print(f"print-auto: rendered {pages_rendered} page(s), target was "
              f"{target} ±{slack} after {len(attempts)} layout(s). Revise the document.", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
