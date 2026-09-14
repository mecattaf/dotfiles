#!/usr/bin/env python3
"""paper-daemon — the print loop, owned end to end (dotfiles#384).

Tom's ruling (2026-09-12): "/print" is ONE file write. An agent puts a
Markdown file in ~/Paper/intake/ and walks away; everything after that is
this program's, and nobody else's:

    intake/<slug>.md
        │  render through print-auto.py (the utility-model classifier and
        │  print-paper.py's renderer — the one render path), front matter wins
        ├─► rejected/<id>/   rendered page count != target_pages (nothing sent)
        ├─► outbox/<id>/     00:00–06:00 quiet hours, unless `force: true`
        └─► submit
              │  queue must be the pinned driverless one; else repair once
              │  lp -t paper-<id>-<ts>, then watch THE PRINTER over IPP
              ├─► printed/<id>/receipt.json   printer says completed AND
              │                               job-impressions-completed == pages
              └─► failed/<id>/                anything else, with evidence, a
                                              failed unit and a client notify

Drop contract. Write `.<slug>.md.tmp`, then rename to `<slug>.md`. Dotfiles,
`*.tmp` and subdirectories are ignored (intake/.adopted-2026-09-09/ holds the
sources of the 2026-09-09 prints, parked so a watcher never reprints them).
There is deliberately NO age gate: rename(2) keeps the temp file's fresh
mtime and the path unit fires once, so "older than N seconds" would strand a
correct drop until the sweep. A size that is still changing between two
stats is waited out inside this run instead.

Optional front matter (a leading `---` block of `key: value` lines):
    target_pages: 10          exact page count; a mismatch is rejected
    sides: one-sided|duplex|short-edge
    profile: garamond|baskerville|source-serif|times
    force: true               print now even inside quiet hours

Why the receipt reads the printer and not cupsd. 2026-09-11 job 303: cupsd
logged "Job completed", 10 pages, and the Brother received nothing (the queue
had been rewritten to implicitclass:// by cups-browsed). 2026-09-12 job 304:
a raw queue with no PPD handed PDF to a printer that only takes urf/pwg —
ten blank sheets. CUPS "completed" means a backend returned; the printer's
own Get-Jobs `job-state completed` with `job-impressions-completed` is the
only statement about paper. MEASURED 2026-09-13 against 10.42.0.4: the
Brother rejects which-jobs=all (client-error-attributes-or-values-not-
supported), so completed and not-completed are asked separately; and it does
not support job-media-sheets-completed, so the receipt carries impressions
only, and says so.

Every external command is found on PATH (the Nix wrapper puts cups,
poppler-utils and the renderer's closure there), and every path and clock is
overridable through PAPER_* variables so tests/print/test_paper_daemon.py
drives the real program against stub lp/lpstat/lpoptions/ipptool/sudo/ssh
without a sheet of paper.

Usage:
    paper-daemon run            process intake/ (and outbox/ outside quiet hours)
    paper-daemon flush          submit outbox/ (refuses inside quiet hours)
    paper-daemon check-queue [--repair]
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

QUEUE = os.environ.get("PAPER_QUEUE", "Brother_HL_L2445DW")
DEVICE_URI = os.environ.get("PAPER_DEVICE_URI", "ipp://10.42.0.4:631/ipp/print")
PPD = Path(os.environ.get("PAPER_PPD", f"/etc/cups/ppd/{QUEUE}.ppd"))
URF_FILTER = 'cupsFilter2: "image/urf'
NOTIFY_HOST = os.environ.get("PAPER_NOTIFY_HOST", "tom@10.42.0.16")

HERE = Path(__file__).resolve().parent
PRINT_AUTO = Path(os.environ.get("PAPER_PRINT_AUTO", HERE / "scripts" / "print-auto.py"))
JOBS_TEST = Path(os.environ.get("PAPER_JOBS_TEST", HERE / "get-jobs.test"))
PRINTER_TEST = Path(os.environ.get("PAPER_PRINTER_TEST", HERE / "printer-state.test"))

# IPP job-state enum (RFC 8011 §5.3.7).
JOB_STATES = {3: "pending", 4: "pending-held", 5: "processing",
              6: "processing-stopped", 7: "canceled", 8: "aborted",
              9: "completed"}
PROFILES = {"garamond", "baskerville", "source-serif", "times"}
SIDES_LP = {"one-sided": "one-sided", "duplex": "two-sided-long-edge",
            "long-edge": "two-sided-long-edge",
            "short-edge": "two-sided-short-edge"}


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


def log(message: str) -> None:
    print(f"paper-daemon: {message}", file=sys.stderr, flush=True)


def now() -> dt.datetime:
    """The clock, or PAPER_NOW (ISO 8601) so quiet hours are testable."""
    fixed = os.environ.get("PAPER_NOW")
    return dt.datetime.fromisoformat(fixed) if fixed else dt.datetime.now()


def quiet_hours(at: dt.datetime) -> bool:
    return 0 <= at.hour < 6


def root() -> Path:
    return Path(os.environ.get("PAPER_ROOT", Path.home() / "Paper"))


def state_dir(name: str) -> Path:
    path = root() / name
    path.mkdir(parents=True, exist_ok=True)
    return path


def run(cmd: list[str], *, timeout: float = 60) -> subprocess.CompletedProcess[str]:
    """Run a command, never raising: a missing binary or a hang is an rc."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(cmd, 127, "", str(exc))
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"timed out after {timeout}s")


def write_json(path: Path, data: object) -> None:
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ── drop contract ────────────────────────────────────────────────────────────

class Rejected(Exception):
    """The drop itself is wrong; the agent revises and re-drops."""


def parse_front_matter(text: str) -> dict:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fields: dict = {}
    for line in lines[1:]:
        if line.strip() in ("---", "..."):
            break
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0] in " \t-":
            continue  # a YAML list item or continuation of some other key
        key, sep, value = line.partition(":")
        if not sep:
            raise Rejected(f"front matter line is not `key: value`: {line!r}")
        fields[key.strip()] = value.strip().strip("'\"")
    else:
        raise Rejected("front matter opened with --- but never closed")

    options: dict = {}
    for key, value in fields.items():
        if key == "target_pages":
            if not re.fullmatch(r"[1-9][0-9]*", value):
                raise Rejected(f"target_pages must be a positive integer, got {value!r}")
            options["target_pages"] = int(value)
        elif key == "sides":
            if value not in ("one-sided", "duplex", "short-edge"):
                raise Rejected(f"sides must be one-sided, duplex or short-edge, got {value!r}")
            options["sides"] = value
        elif key == "profile":
            if value not in PROFILES:
                raise Rejected(f"profile must be one of {sorted(PROFILES)}, got {value!r}")
            options["profile"] = value
        elif key == "force":
            if value.lower() not in ("true", "false", "yes", "no"):
                raise Rejected(f"force must be true or false, got {value!r}")
            options["force"] = value.lower() in ("true", "yes")
        # Any other key (title, date, ...) is the document's own metadata;
        # print-paper.py strips the whole block before rendering.
    return options


def ready_drops(intake: Path) -> list[Path]:
    return sorted(
        p for p in intake.iterdir()
        if p.is_file() and not p.name.startswith(".")
        and p.suffix == ".md" and not p.name.endswith(".tmp")
    )


def settled(path: Path) -> bool:
    """False if the file is still growing. Waits up to PAPER_SETTLE_MAX
    seconds inside this run rather than returning to wait for an event that
    will not come."""
    step = env_float("PAPER_SETTLE_SECONDS", 0.5)
    deadline = time.monotonic() + env_float("PAPER_SETTLE_MAX", 10)
    try:
        size = path.stat().st_size
        while True:
            time.sleep(step)
            again = path.stat().st_size
            if again == size:
                return True
            if time.monotonic() > deadline:
                return False
            size = again
    except FileNotFoundError:
        return False


def job_id(stem: str, at: dt.datetime) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-") or "document"
    taken = lambda name: any((root() / d / name).exists() for d in
                             ("work", "outbox", "printed", "rejected", "failed"))
    if not taken(slug):
        return slug
    candidate = f"{slug}-{at:%Y%m%d-%H%M%S}"
    n = 2
    while taken(candidate):
        candidate = f"{slug}-{at:%Y%m%d-%H%M%S}-{n}"
        n += 1
    return candidate


def settle_into(jobdir: Path, state: str) -> Path:
    dest = state_dir(state) / jobdir.name
    jobdir.rename(dest)
    return dest


# ── queue health ─────────────────────────────────────────────────────────────

def ipptool_json(uri: str, test: str, *defines: str) -> tuple[list, str]:
    """ipptool -j prints a JSON array then a status line; its exit code is 1
    for anything but plain successful-ok (the Brother answers
    successful-ok-ignored-or-substituted-attributes), so parse the body."""
    cmd = ["ipptool", "-j", "-T", "15"]
    for define in defines:
        cmd += ["-d", define]
    result = run(cmd + [uri, test], timeout=30)
    raw = result.stdout
    start = raw.find("[")
    if start < 0:
        return [], raw + result.stderr
    try:
        groups, _ = json.JSONDecoder().raw_decode(raw[start:])
    except json.JSONDecodeError:
        # ipptool -j does not separate jobs: with two or more jobs in one
        # Get-Jobs answer the second job's attributes continue the first
        # job's object with no comma or brace (seen 2026-09-14: job 299's
        # "job-impressions-completed": 2 followed directly by "job-id": 298).
        # Strict JSON then fails, no job matched, and a job the printer had
        # completed was failed at the deadline. Read it leniently instead.
        groups = lenient_ipp_groups(raw[start:])
    return groups if isinstance(groups, list) else [], raw + result.stderr


def lenient_ipp_groups(text: str) -> list:
    """One dict per group; a repeated job-id inside a group starts a new job."""
    groups: list = []
    cur: dict | None = None
    lines = iter(text.splitlines())
    for line in lines:
        s = line.strip().rstrip(",")
        if s == "{":
            cur = {}
            groups.append(cur)
            continue
        m = re.match(r'^"([^"]+)":\s*(.*)$', s)
        if cur is None or not m:
            continue
        key, value = m.group(1), m.group(2)
        if value == "[":
            items = []
            for item in lines:
                t = item.strip().rstrip(",")
                if t == "]":
                    break
                try:
                    items.append(json.loads(t))
                except ValueError:
                    items.append(t)
            parsed: object = items
        else:
            try:
                parsed = json.loads(value)
            except ValueError:
                parsed = value
        if key == "job-id" and "job-id" in cur:
            cur = {"group-tag": cur.get("group-tag")}
            groups.append(cur)
        cur[key] = parsed
    return groups


def queue_problems() -> tuple[list[str], dict]:
    """Every way the 2026-09-11/12 failures looked, as preconditions."""
    problems: list[str] = []
    evidence: dict = {}

    device = run(["lpstat", "-v", QUEUE])
    evidence["lpstat_v"] = (device.stdout + device.stderr).strip()
    if device.stdout.strip() != f"device for {QUEUE}: {DEVICE_URI}":
        problems.append(f"DeviceURI is not the pinned {DEVICE_URI}: {evidence['lpstat_v']!r}")

    # A raw queue (no PPD) has no driver options at all — job 304's shape.
    options = run(["lpoptions", "-p", QUEUE, "-l"])
    if options.returncode != 0 or not options.stdout.strip():
        problems.append("queue has no driver options (raw queue, no PPD)")

    # The PPD is 0640 root:lp. Read it directly if we can, else through
    # sudo -n (tom is NOPASSWD wheel); if neither can read it, the lpoptions
    # check above still stands and the gap is recorded, not guessed.
    ppd_text = None
    try:
        ppd_text = PPD.read_text(errors="replace")
    except FileNotFoundError:
        problems.append(f"{PPD} is missing")
    except PermissionError:
        viewed = run(["sudo", "-n", "cat", str(PPD)])
        if viewed.returncode == 0:
            ppd_text = viewed.stdout
        elif "No such file" in viewed.stderr:
            problems.append(f"{PPD} is missing")
        else:
            evidence["ppd"] = f"unreadable: {viewed.stderr.strip()}"
    if ppd_text is not None and URF_FILTER not in ppd_text:
        problems.append(f"{PPD} has no {URF_FILTER}\" filter")

    state = run(["lpstat", "-p", QUEUE])
    evidence["lpstat_p"] = (state.stdout + state.stderr).strip()
    if state.returncode != 0 or "disabled" in state.stdout:
        problems.append(f"CUPS queue not enabled: {evidence['lpstat_p']!r}")

    # Not the stock get-printer-attributes.test: its full dump is invalid
    # JSON from ipptool -j for this printer (see printer-state.test).
    groups, raw = ipptool_json(DEVICE_URI, str(PRINTER_TEST))
    printer = next((g for g in groups if "printer-state" in g), None)
    if printer is None:
        problems.append(f"printer at {DEVICE_URI} did not answer get-printer-attributes")
        evidence["printer"] = raw[-2000:]
    else:
        evidence["printer_state"] = printer.get("printer-state")
        evidence["printer_state_reasons"] = printer.get("printer-state-reasons")
        if printer.get("printer-state") == 5:
            problems.append(f"printer-state is stopped ({printer.get('printer-state-reasons')})")
    return problems, evidence


def ensure_queue(repairs: list) -> list[str]:
    """Check; on failure re-run the declared ensure-printers once and check
    again. Returns the problems that remain (empty = healthy)."""
    problems, evidence = queue_problems()
    if not problems:
        return []
    log("queue unhealthy, repairing: " + "; ".join(problems))
    cmd = ["sudo", "-n", "systemctl", "restart", "ensure-printers.service"]
    result = run(cmd, timeout=300)
    after, after_evidence = queue_problems()
    repairs.append({
        "at": now().isoformat(timespec="seconds"),
        "problems": problems,
        "evidence": evidence,
        "command": shlex.join(cmd),
        "rc": result.returncode,
        "output": (result.stdout + result.stderr).strip()[-2000:],
        "remaining": after,
        "after": after_evidence,
    })
    return after


# ── the printer's truth ──────────────────────────────────────────────────────

def printer_job(title: str) -> tuple[dict | None, dict]:
    dumps: dict = {}
    for which in ("not-completed", "completed"):
        groups, raw = ipptool_json(DEVICE_URI, str(JOBS_TEST), f"which={which}")
        dumps[which] = raw[-4000:]
        matches = [g for g in groups if g.get("group-tag") == "job-attributes-tag"
                   and isinstance(g.get("job-name"), str)
                   and (g["job-name"] == title
                        # a printer may truncate job-name; a long prefix of a
                        # timestamped title is still unique
                        or (len(g["job-name"]) >= 24 and title.startswith(g["job-name"])))]
        if matches:
            return max(matches, key=lambda g: g.get("job-id", 0)), dumps
    return None, dumps


def notify(summary: str, body: str) -> None:
    if not NOTIFY_HOST:
        return
    remote = ("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus "
              f"notify-send -u critical {shlex.quote(summary)} {shlex.quote(body)}")
    result = run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                  NOTIFY_HOST, remote], timeout=20)
    if result.returncode != 0:
        log(f"client notification failed (rc {result.returncode}): {result.stderr.strip()}")


def cancel_cups_job(cups_job: str) -> dict:
    cancel = run(["cancel", cups_job])
    return {"rc": cancel.returncode, "output": (cancel.stdout + cancel.stderr).strip()}


def crashed(jobdir: Path, what: str) -> bool:
    """An unexpected exception on one job (a malformed decision.json, a full
    disk) must neither strand work/<id>/ with no outcome directory nor abort
    the rest of the run: it becomes a failed/ entry with the traceback and a
    client notify, like any other failure. Called from an except block."""
    log(f"crashed on {jobdir.name} during {what}:\n{traceback.format_exc()}")
    if not jobdir.exists():
        return False  # it had already reached its outcome directory
    meta_path = jobdir / "job.json"
    try:
        meta = json.loads(meta_path.read_text())
    except Exception:  # noqa: BLE001
        meta = {"id": jobdir.name}
    try:
        return fail_job(jobdir, meta, f"paper-daemon crashed during {what}",
                        {"traceback": traceback.format_exc()[-8000:]})
    except Exception:  # noqa: BLE001
        log(f"could not even record the crash of {jobdir.name}:\n{traceback.format_exc()}")
        return False


def fail_job(jobdir: Path, meta: dict, reason: str, extra: dict) -> bool:
    """Move the job to failed/ with its evidence, notify, and return False."""
    since = meta.get("submitted_at") or meta.get("dropped_at")
    evidence = dict(extra)
    evidence["reason"] = reason
    evidence["failed_at"] = now().isoformat(timespec="seconds")
    lpstat = run(["lpstat", "-W", "all", "-l", "-o", QUEUE])
    evidence["lpstat_l_o"] = (lpstat.stdout + lpstat.stderr)[-8000:]
    journal = run(["journalctl", "-u", "cups", "--no-pager", "-o", "short-iso",
                   "--since", since or "-1h"], timeout=30)
    (jobdir / "cups-journal.txt").write_text(journal.stdout + journal.stderr)
    write_json(jobdir / "failure.json", evidence)
    dest = settle_into(jobdir, "failed")
    log(f"FAILED {dest.name}: {reason} (evidence in {dest})")
    notify("print failed", f"{dest.name}: {reason}")
    return False


def submit(jobdir: Path) -> bool:
    meta = json.loads((jobdir / "job.json").read_text())
    decision = json.loads((jobdir / "decision.json").read_text())
    pdf = jobdir / decision["decision"]["filename"]
    pages = decision.get("pages_rendered")
    repairs: list = []

    remaining = ensure_queue(repairs)
    if remaining:
        return fail_job(jobdir, meta, "queue unhealthy after one repair: "
                            + "; ".join(remaining), {"repairs": repairs})
    if not isinstance(pages, int) or pages < 1:
        return fail_job(jobdir, meta, f"rendered page count unknown ({pages!r})",
                            {"repairs": repairs})

    sides = meta.get("options", {}).get("sides") or decision["decision"].get("sides", "duplex")
    submitted = now()
    title = f"paper-{jobdir.name}-{submitted:%Y%m%dT%H%M%S}"
    cmd = ["lp", "-d", QUEUE, "-n", "1", "-o", "media=A4",
           "-o", f"sides={SIDES_LP[sides]}", "-t", title, str(pdf)]
    lp = run(cmd)
    meta["submitted_at"] = submitted.isoformat(timespec="seconds")
    if lp.returncode != 0:
        return fail_job(jobdir, meta, f"lp exited {lp.returncode}: {lp.stderr.strip()}",
                            {"lp": shlex.join(cmd), "repairs": repairs})
    match = re.search(r"request id is (\S+)", lp.stdout)
    cups_job = match.group(1) if match else None
    log(f"submitted {jobdir.name} as {cups_job} ({pages} pages, {sides}); watching the printer")

    interval = env_float("PAPER_POLL_INTERVAL", 5)
    budget = env_float("PAPER_POLL_BASE_SECONDS", 120) + env_float("PAPER_POLL_PER_PAGE", 20) * pages
    deadline = time.monotonic() + budget
    seen = None
    dumps: dict = {}
    base = {"lp": shlex.join(cmd), "cups_job_id": cups_job, "title": title,
            "pages": pages, "repairs": repairs}
    while True:
        job, dumps = printer_job(title)
        if job is not None:
            seen = job
            state = job.get("job-state")
            if state == 9:
                break
            if state in (7, 8):
                return fail_job(jobdir, meta, f"printer reports job {JOB_STATES[state]} "
                                    f"({job.get('job-state-reasons')})",
                                    {**base, "printer_job": job, "ipp": dumps})
        cups_state = run(["lpstat", "-p", QUEUE])
        if "disabled" in cups_state.stdout:
            extra = {**base, "printer_job": seen, "ipp": dumps}
            reason = "CUPS stopped the queue while printing: " + cups_state.stdout.strip()
            if seen is None and cups_job:
                # Same rule as the deadline below, and more urgent: a stopped
                # queue keeps its held job, and the next ensure-printers run
                # (the daemon's own repair, a switch, or boot at 03:00)
                # re-enables the queue with `lpadmin -E` and prints it with
                # nobody watching and no receipt.
                extra["cancel"] = cancel_cups_job(cups_job)
                reason += "; the printer never listed the job, CUPS job cancelled"
            return fail_job(jobdir, meta, reason, extra)
        if time.monotonic() > deadline:
            extra = {**base, "printer_job": seen, "ipp": dumps, "budget_seconds": budget}
            if seen is None and cups_job:
                # The printer never saw it. Cancel the CUPS copy so a failed/
                # entry means "nothing will come out later" (a stranded job
                # otherwise prints whenever the printer next wakes, which may
                # be 03:00). A job the printer HAS accepted is left alone:
                # its sheets are already moving.
                extra["cancel"] = cancel_cups_job(cups_job)
                reason = f"printer never listed {title} within {budget:.0f}s; CUPS job cancelled"
            else:
                reason = (f"printer job {seen.get('job-id')} still "
                          f"{JOB_STATES.get(seen.get('job-state'), seen.get('job-state'))} "
                          f"after {budget:.0f}s")
            return fail_job(jobdir, meta, reason, extra)
        time.sleep(interval)

    impressions = seen.get("job-impressions-completed")
    if impressions != pages:
        return fail_job(jobdir, meta, f"printer completed with {impressions!r} impressions "
                            f"for {pages} rendered pages",
                            {**base, "printer_job": seen, "ipp": dumps})

    receipt = {
        "id": jobdir.name,
        "source": str(root() / "printed" / jobdir.name / "source.md"),
        "source_sha256": sha256(jobdir / "source.md"),
        "pdf": str(root() / "printed" / jobdir.name / pdf.name),
        "pdf_sha256": sha256(pdf),
        "pages": pages,
        "sides": SIDES_LP[sides],
        "queue": QUEUE,
        "device_uri": DEVICE_URI,
        "cups_job_id": cups_job,
        "job_name": title,
        "printer_job_id": seen.get("job-id"),
        "printer_job_state": JOB_STATES.get(seen.get("job-state")),
        "printer_job_state_reasons": seen.get("job-state-reasons"),
        # From the printer's own Get-Jobs, never from cupsd.
        "impressions_completed": impressions,
        # MEASURED 2026-09-13: the HL-L2445DW lists job-media-sheets-completed
        # as unsupported-attributes, so there is no printer-sourced sheet count.
        "media_sheets_completed": seen.get("job-media-sheets-completed"),
        "dropped_at": meta.get("dropped_at"),
        "submitted_at": meta["submitted_at"],
        "completed_at": now().isoformat(timespec="seconds"),
        "repairs": repairs,
    }
    write_json(jobdir / "receipt.json", receipt)
    dest = settle_into(jobdir, "printed")
    log(f"printed {dest.name}: printer job {receipt['printer_job_id']}, "
        f"{impressions} impressions — {dest / 'receipt.json'}")
    return True


# ── intake ───────────────────────────────────────────────────────────────────

def process(drop: Path) -> bool:
    at = now()
    jid = job_id(drop.stem, at)
    jobdir = state_dir("work") / jid
    jobdir.mkdir()
    source = jobdir / "source.md"
    # Moving the drop out of intake/ first is what makes processing
    # at-most-once: a crash from here on leaves work/<id>/, never a file the
    # next sweep would print again.
    drop.rename(source)
    meta = {"id": jid, "original_name": drop.name,
            "dropped_at": at.isoformat(timespec="seconds"), "options": {}}
    try:
        write_json(jobdir / "job.json", meta)
        return process_job(jobdir, source, meta, at)
    except Exception:  # noqa: BLE001 — becomes failed/, never a stranded work/
        return crashed(jobdir, "processing")


def process_job(jobdir: Path, source: Path, meta: dict, at: dt.datetime) -> bool:
    try:
        meta["options"] = parse_front_matter(source.read_text(errors="replace"))
    except Rejected as exc:
        write_json(jobdir / "reason.json", {"reason": str(exc)})
        dest = settle_into(jobdir, "rejected")
        log(f"rejected {dest.name}: {exc}")
        return True
    write_json(jobdir / "job.json", meta)
    options = meta["options"]

    cmd = [sys.executable, str(PRINT_AUTO), str(source), "--output-dir", str(jobdir)]
    if "target_pages" in options:
        cmd += ["--target-pages", str(options["target_pages"])]
    if "profile" in options:
        cmd += ["--profile", options["profile"]]
    if "sides" in options:
        cmd += ["--sides", "one-sided" if options["sides"] == "one-sided" else "duplex"]
    render = run(cmd, timeout=1800)
    (jobdir / "render.log").write_text(render.stdout + render.stderr)
    decision_path = jobdir / "decision.json"
    if not decision_path.exists():
        return fail_job(jobdir, meta, f"render failed (print-auto rc {render.returncode})",
                            {"render_command": shlex.join(cmd),
                             "render_output": (render.stdout + render.stderr)[-4000:]})
    decision = json.loads(decision_path.read_text())

    if decision.get("length_check") == "fail":
        write_json(jobdir / "reason.json", {
            "reason": "rendered page count does not match target_pages",
            "pages_rendered": decision.get("pages_rendered"),
            "target_pages": decision.get("target_pages"),
        })
        dest = settle_into(jobdir, "rejected")
        log(f"rejected {dest.name}: rendered {decision.get('pages_rendered')} pages, "
            f"target {decision.get('target_pages')}; nothing was sent")
        return True

    if quiet_hours(at) and not options.get("force"):
        dest = settle_into(jobdir, "outbox")
        log(f"quiet hours: {dest.name} waits in outbox/ for the 06:05 flush")
        return True
    return submit(jobdir)


class Lock:
    def __enter__(self) -> "Lock":
        self.handle = open(state_dir(".") / ".paper-daemon.lock", "w")
        fcntl.flock(self.handle, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc: object) -> None:
        self.handle.close()


def flush_outbox() -> bool:
    ok = True
    for jobdir in sorted(p for p in state_dir("outbox").iterdir()
                         if p.is_dir() and not p.name.startswith(".")):
        if not (jobdir / "job.json").exists():
            log(f"ignoring {jobdir}: not a paper-daemon job (no job.json)")
            continue
        try:
            ok = submit(jobdir) and ok
        except Exception:  # noqa: BLE001 — one bad entry must not block the rest
            ok = crashed(jobdir, "submission from outbox/") and ok
    return ok


def cmd_run() -> int:
    ok = True
    with Lock():
        intake = state_dir("intake")
        # Re-scan until empty: a drop that lands while a long job is being
        # watched raises its path event while this service is still active.
        handled: set[str] = set()
        grace_used = False
        while True:
            drops = [d for d in ready_drops(intake) if d.name not in handled]
            if not drops:
                # The agent's `.tmp` write starts this run; its rename a few
                # milliseconds later is merged into the still-active start
                # and raises no further run. Look once more before exiting
                # so that rename is not left for the five-minute sweep.
                grace = env_float("PAPER_RESCAN_GRACE", 2)
                if grace_used or grace <= 0:
                    break
                grace_used = True
                time.sleep(grace)
                continue
            grace_used = False
            for drop in drops:
                handled.add(drop.name)
                if not settled(drop):
                    log(f"{drop.name} is still being written; the sweep will retry")
                    continue
                try:
                    ok = process(drop) and ok
                except Exception:  # noqa: BLE001 — before the move into work/
                    log(f"crashed on {drop.name}:\n{traceback.format_exc()}")
                    ok = False
        if not quiet_hours(now()):
            ok = flush_outbox() and ok
    return 0 if ok else 1


def cmd_flush() -> int:
    if quiet_hours(now()):
        log("quiet hours (00:00-06:00): leaving outbox/ untouched")
        return 0
    with Lock():
        return 0 if flush_outbox() else 1


def cmd_check_queue(repair: bool) -> int:
    if repair:
        repairs: list = []
        remaining = ensure_queue(repairs)
        print(json.dumps({"healthy": not remaining, "remaining": remaining,
                          "repairs": repairs}, indent=2))
        return 0 if not remaining else 1
    problems, evidence = queue_problems()
    print(json.dumps({"healthy": not problems, "problems": problems,
                      "evidence": evidence}, indent=2))
    return 0 if not problems else 1


def main() -> int:
    parser = argparse.ArgumentParser(prog="paper-daemon", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("run")
    sub.add_parser("flush")
    check = sub.add_parser("check-queue")
    check.add_argument("--repair", action="store_true")
    args = parser.parse_args()
    if args.command == "run":
        return cmd_run()
    if args.command == "flush":
        return cmd_flush()
    return cmd_check_queue(args.repair)


if __name__ == "__main__":
    sys.exit(main())
