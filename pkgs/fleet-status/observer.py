#!/usr/bin/env python3
"""One passive NAS observation owner, extending the existing fleet collector.

No inference, dashboard server, transcript archive, clock-driven agent work,
port discovery or model wake. Public records are constructed from a reviewed
field whitelist, never made safe by redacting arbitrary source objects.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import secrets
import signal
import subprocess
import threading
import time
import urllib.request
import urllib.error
import email.utils
from functools import wraps

from incremental import tail_jsonl

ROOT = Path(__file__).resolve().parent
CONTRACT = json.loads((ROOT / "public-contract.json").read_text())
SOURCES = CONTRACT["sources"]
PROVIDERS = CONTRACT["providers"]
UTC = dt.timezone.utc
STOP = threading.Event()


class SourceError(RuntimeError):
    def __init__(self, code, retry_after=None):
        super().__init__(code)
        self.retry_after = retry_after


def metadata_json(request, timeout, cap):
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(cap + 1)
            if len(raw) > cap:
                raise SourceError("budget-truncated")
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        retry_after = None
        value = exc.headers.get("Retry-After")
        if value:
            try:
                seconds = float(value)
                if math.isfinite(seconds) and seconds >= 0:
                    retry_after = time.time() + seconds
            except ValueError:
                try:
                    retry_after = email.utils.parsedate_to_datetime(value).timestamp()
                except (TypeError, ValueError, OverflowError):
                    pass
        raise SourceError("source-failed", retry_after) from None


def synchronized(function):
    @wraps(function)
    def wrapped(self, *args, **kwargs):
        with self.lock:
            return function(self, *args, **kwargs)
    return wrapped


def stamp(value=None):
    return (value or dt.datetime.now(UTC)).astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def instant(value):
    try:
        if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
            return dt.datetime.fromtimestamp(value / 1000 if value > 10 ** 11 else value, UTC)
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.astimezone(UTC) if parsed.tzinfo else None
    except (ValueError, TypeError, OverflowError):
        return None


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(path.name + ".new")
    with temporary.open("w") as stream:
        os.chmod(temporary, 0o600)
        json.dump(value, stream, separators=(",", ":"), allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def command(argv, timeout=15, cap=2 * 1024 * 1024, as_json=True):
    """Only fixed argv from source configuration; never shell text."""
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        raw, _ = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.communicate()
        raise RuntimeError("source-timeout") from None
    if child.returncode:
        raise RuntimeError("source-failed")
    if len(raw) > cap:
        raise RuntimeError("budget-truncated")
    return json.loads(raw) if as_json else raw.decode("utf-8", errors="replace")


def public_observation(subject, source, key, value, *, at=None, unit=None, scope=None, grade="measured", error=None, ttl=180):
    if source not in SOURCES or key not in SOURCES[source]:
        raise ValueError("unreviewed public field")
    if isinstance(value, (dict, list)):
        raise ValueError("structured public value requires an explicit new contract")
    if finite(value):
        pass
    elif isinstance(value, bool) or value is None:
        pass
    elif isinstance(value, str):
        if key.endswith("At"):
            if instant(value) is None:
                raise ValueError("invalid public timestamp")
        elif key == "quota.bucketId":
            if not re.fullmatch(r"quota-[a-z]+-[1-9][0-9]?-[a-z0-9-]+", value):
                raise ValueError("invalid public bucket")
        elif value not in CONTRACT["stringDomains"].get(key, []) and not (key == "provider.name" and value in PROVIDERS.values()):
            raise ValueError("unreviewed public string")
    else:
        raise ValueError("invalid public primitive")
    if error not in [None, *CONTRACT["errorCodes"]] or scope not in [None, *CONTRACT["scopes"]]:
        raise ValueError("unreviewed public provenance")
    observed = instant(at) if at else dt.datetime.now(UTC)
    row = {"subjectId": subject, "sourceId": source, "key": key, "grade": grade if value is not None else "unknown",
           "value": value, "observedAt": stamp(observed) if observed else None,
           "lastAttemptAt": stamp(), "expiresAt": stamp(observed + dt.timedelta(seconds=ttl)) if observed else None,
           "errorCode": error}
    if unit:
        row["unit"] = unit
    if scope:
        row["scope"] = scope
    return row


def refresh_rows(rows, attempted, error=None):
    """Refresh publication provenance without rejuvenating source timestamps."""
    result = []
    now = dt.datetime.now(UTC)
    for original in rows:
        row = dict(original)
        row["lastAttemptAt"] = attempted
        expires = instant(row.get("expiresAt"))
        if error or (expires and expires < now):
            if row.get("value") is not None and row.get("observedAt"):
                row["lastGood"] = {"value": row["value"], "observedAt": row["observedAt"]}
            row.update(value=None, grade="unknown", errorCode=error or "stale")
        elif row["grade"] == "measured" and row["observedAt"] != attempted:
            row["grade"] = "cached"
        result.append(row)
    return result


def expire_at_reset(rows, reset):
    boundary = instant(reset)
    if boundary:
        for row in rows:
            expires = instant(row.get("expiresAt"))
            if expires and boundary < expires:
                row["expiresAt"] = stamp(boundary)
    return rows


def validate_public(value):
    """Revalidate retained caches too: private state is not a public schema."""
    ids = set()
    labels = {"fleet": ["Fleet"], "host": ["NAS", "Strix coordinator", "Zenbook", "Strix worker"],
              "instance": ["DSH instance"], "session": ["DSH session"], "invocation": ["Supervised run"],
              "provider": list(PROVIDERS.values()), "account": [label + " account " + str(slot) for label in PROVIDERS.values() for slot in range(1, 100)],
              "quota-bucket": [label + " quota" for label in PROVIDERS.values()]}
    for subject in value["subjects"]:
        kind = subject.get("kind")
        pattern = CONTRACT["subjectPatterns"].get(kind, {}).get("id")
        if not pattern or not re.fullmatch(pattern, subject.get("id", "")) or subject.get("label") not in labels.get(kind, []):
            raise ValueError("unreviewed public identity")
        if set(subject) - {"id", "kind", "label", "relations", "declaredMode"}:
            raise ValueError("unreviewed public identity fields")
        if subject["id"] in ids:
            raise ValueError("duplicate public identity")
        ids.add(subject["id"])
    for subject in value["subjects"]:
        for relation in subject["relations"]:
            if set(relation) != {"kind", "targetId"} or relation["kind"] != "part-of" or relation["targetId"] not in ids:
                raise ValueError("unreviewed public relation")
    for row in value["observations"]:
        if set(row) - {"subjectId", "sourceId", "key", "grade", "value", "observedAt", "lastAttemptAt", "expiresAt", "errorCode", "lastGood", "unit", "scope"}:
            raise ValueError("unreviewed public observation fields")
        if row["subjectId"] not in ids:
            raise ValueError("unknown public subject")
        public_observation(row["subjectId"], row["sourceId"], row["key"], row["value"], error=row["errorCode"], scope=row.get("scope"))
        if row.get("lastGood"):
            good = row["lastGood"]
            if set(good) != {"value", "observedAt"} or instant(good["observedAt"]) is None:
                raise ValueError("invalid last-good projection")
            public_observation(row["subjectId"], row["sourceId"], row["key"], good["value"])
        for key in ["observedAt", "lastAttemptAt", "expiresAt"]:
            if row[key] is not None and instant(row[key]) is None:
                raise ValueError("invalid public source timestamp")
    for row in value["events"]:
        if set(row) - {"id", "subjectId", "sourceId", "type", "at", "summary", "severity", "metrics"} or row["subjectId"] not in ids or row["sourceId"] not in SOURCES:
            raise ValueError("invalid public event")
        if not re.fullmatch("event-[a-f0-9]{24}", row["id"]) or row["summary"] != CONTRACT["eventSummaries"].get(row["type"]):
            raise ValueError("unreviewed public event text")
    return value


class Observer:
    def __init__(self, config, directory):
        self.config, self.directory = config, Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.directory, 0o700)
        try:
            self.state = json.loads((self.directory / "state.json").read_text())
        except FileNotFoundError:
            self.state = {"sequence": 0, "salt": secrets.token_hex(32), "cursors": {}, "sessions": {}, "usage": {}, "events": [], "enrolledAt": stamp()}
        self.lock = threading.RLock()
        self.cache = self.state.setdefault("cache", {})
        self.results = queue.Queue(maxsize=1024)
        self.futures = {}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)
        self.publisher_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.publisher_future = None
        self.subjects = {}
        self.new_process = True
        self.journal_child = None
        self.journal_thread = None
        self.add_subject("fleet", "fleet", "Fleet")
        for name, label in [("nas", "NAS"), ("strix-coordinator", "Strix coordinator"), ("client", "Zenbook"), ("strix-worker", "Strix worker")]:
            self.add_subject("host-" + name, "host", label, "fleet", "dormant" if name == "strix-worker" else None)
        for lane, label in PROVIDERS.items():
            self.add_subject("provider-" + lane, "provider", label)

    def public_id(self, kind, private):
        digest = hashlib.sha256((self.state["salt"] + str(private)).encode()).hexdigest()[:24]
        return kind + "-" + digest

    def add_subject(self, ident, kind, label, parent=None, declared=None):
        row = {"id": ident, "kind": kind, "label": label, "relations": [] if parent is None else [{"kind": "part-of", "targetId": parent}]}
        if declared:
            row["declaredMode"] = declared
        with self.lock:
            self.subjects[ident] = row
        return ident

    def event(self, subject, source, kind, at, identity, metrics=None):
        ident = self.public_id("event", identity)
        if any(row["id"] == ident for row in self.state["events"]):
            return
        row = {"id": ident, "subjectId": subject, "sourceId": source, "type": kind,
               "at": at, "summary": CONTRACT["eventSummaries"][kind], "severity": "info"}
        if metrics:
            row["metrics"] = metrics
        self.state["events"].append(row)
        self.state["events"] = self.state["events"][-200:]

    def hosts(self):
        report = command(self.config["fleetCommand"], timeout=20)
        rows = []
        names = {"nas": "NAS", "strix-coordinator": "Strix coordinator", "client": "Zenbook", "strix-worker": "Strix worker"}
        for node in report.get("nodes", []):
            name = node.get("name")
            if name not in names or name == "strix-worker":
                continue
            subject = self.add_subject("host-" + name, "host", names[name], "fleet")
            reachability = node.get("reachability")
            if reachability not in CONTRACT["stringDomains"]["host.reachability"]:
                continue
            at = (node.get("report") or {}).get("observed_at", report.get("observed_at"))
            rows.append(public_observation(subject, "fleet.snapshot", "host.reachability", reachability, at=at, ttl=900))
            pressure = ((node.get("report") or {}).get("sections") or {}).get("pressure", {})
            memory = pressure.get("memory", {})
            for source_key, key in [("total", "host.memoryTotalBytes"), ("available", "host.memoryAvailableBytes"), ("swap_used", "host.swapUsedBytes")]:
                value = (memory.get("value") or {}).get(source_key)
                rows.append(public_observation(subject, "host.pressure", key, value if finite(value) else None, at=memory.get("observed_at"), unit="bytes", scope="host-total", ttl=900))
            load = pressure.get("load", {})
            values = load.get("value")
            for index, key in enumerate(["host.load1", "host.load5", "host.load15"]):
                value = values[index] if isinstance(values, list) and len(values) > index else None
                rows.append(public_observation(subject, "host.pressure", key, value if finite(value) else None, at=load.get("observed_at"), scope="host-total", ttl=900))
        self.add_subject("host-strix-worker", "host", "Strix worker", "fleet", "dormant")
        return rows

    def instances(self):
        report = command(self.config["dshdCommand"], timeout=15)
        rows = []
        for item in report.get("instances", [])[:1024]:
            ident = self.public_id("instance", item.get("name"))
            self.add_subject(ident, "instance", "DSH instance", "host-nas")
            for raw, key in [(item.get("state"), "instance.state"), (item.get("transport"), "instance.transport")]:
                value = raw if raw in CONTRACT["stringDomains"][key] else "unknown"
                rows.append(public_observation(ident, "agent.instances", key, value, ttl=180, scope="this-instance"))
            enabled = item.get("enabled")
            rows.append(public_observation(ident, "agent.instances", "instance.enabled", enabled if isinstance(enabled, bool) else None, ttl=180, scope="this-instance"))
        if self.config.get("systemctlCommand"):
            raw = command(self.config["systemctlCommand"], timeout=12, as_json=False)
            fields = {"CPUUsageNSec": ("instance.cpuUsageNSec", "nanoseconds"), "MemoryCurrent": ("instance.memoryCurrentBytes", "bytes"), "MemoryPeak": ("instance.memoryPeakBytes", "bytes"), "TasksCurrent": ("instance.tasksCurrent", "count"), "IOReadBytes": ("instance.ioReadBytes", "bytes"), "IOWriteBytes": ("instance.ioWriteBytes", "bytes"), "NRestarts": ("instance.restartCount", "count")}
            for block in raw.split("\n\n")[:1024]:
                values = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
                unit = values.get("Id", "")
                if not unit.startswith("dshd@") or not unit.endswith(".service"):
                    continue
                ident = self.public_id("instance", unit[5:-8])
                self.add_subject(ident, "instance", "DSH instance", "host-nas")
                for raw_key, (key, measure) in fields.items():
                    value = values.get(raw_key, "")
                    parsed = int(value) if value.isdigit() and int(value) < 2 ** 63 else None
                    rows.append(public_observation(ident, "agent.instances", key, parsed, unit=measure, scope="this-instance", ttl=180))
        return rows

    def journal(self):
        """One owned lifecycle subscription; only reviewed envelope fields leave it."""
        backoff = 5
        while not STOP.is_set():
            argv = list(self.config.get("journalCommand", []))
            if not argv:
                return
            with self.lock:
                cursor = self.state.get("journalCursor")
            argv += ["--after-cursor=" + cursor] if cursor else ["--since=now"]
            try:
                child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
                self.journal_child = child
                for line in iter(lambda: child.stdout.readline(65537), b""):
                    if STOP.is_set():
                        break
                    if len(line) > 65536 or not line.endswith(b"\n"):
                        self.results.put({"gap": True})
                        continue
                    try:
                        record = json.loads(line)
                    except (ValueError, UnicodeDecodeError):
                        continue
                    # Do not queue MESSAGE, argv, labels, tools or credentials.
                    selected = {key: record.get(key) for key in ["MESSAGE_ID", "USER_UNIT", "UNIT", "_SYSTEMD_USER_UNIT", "_SYSTEMD_INVOCATION_ID", "USER_INVOCATION_ID", "__REALTIME_TIMESTAMP", "__CURSOR"]}
                    try:
                        self.results.put_nowait(selected)
                    except queue.Full:
                        with self.lock:
                            self.state["journalGap"] = True
                status = child.wait(timeout=3)
                with self.lock:
                    self.state["journalError"] = "source-failed" if status else "source-unavailable"
                    if status and cursor:
                        # A rotated/invalid cursor must not wedge observation
                        # forever. Resume from now, explicitly retaining the
                        # coverage gap rather than replaying old executions.
                        self.state.pop("journalCursor", None)
                        self.state["journalGap"] = True
            except (OSError, subprocess.TimeoutExpired):
                with self.lock:
                    self.state["journalError"] = "source-failed"
            finally:
                child = self.journal_child
                if child and child.poll() is None:
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                self.journal_child = None
            if STOP.wait(backoff):
                break
            backoff = min(300, backoff * 2)

    @synchronized
    def drain_journal(self):
        while True:
            try:
                record = self.results.get_nowait()
            except queue.Empty:
                return
            if record.get("gap"):
                self.state["journalGap"] = True
                continue
            cursor = record.get("__CURSOR")
            if isinstance(cursor, str) and len(cursor) <= 512:
                self.state["journalCursor"] = cursor
            message = record.get("MESSAGE_ID")
            types = {"39f53479d3a045ac8e11786248231fbf": "run.started", "9d1aaa27d60140bd96365438aad20286": "run.ended", "be02cf6855d2428ba40df7e9d022f03d": "run.ended", "d9b373ed55a64feb8242e02dbe79a49c": "run.ended"}
            kind = types.get(message)
            unit = record.get("USER_UNIT") or record.get("UNIT") or record.get("_SYSTEMD_USER_UNIT") or ""
            if kind is None or not isinstance(unit, str) or not unit.startswith("dshd@") or not unit.endswith(".service"):
                continue
            invocation = record.get("USER_INVOCATION_ID") or record.get("_SYSTEMD_INVOCATION_ID")
            if not isinstance(invocation, str):
                self.state["journalGap"] = True
                continue
            try:
                at = stamp(dt.datetime.fromtimestamp(int(record["__REALTIME_TIMESTAMP"]) / 1_000_000, UTC))
            except (ValueError, TypeError, OverflowError):
                continue
            parent = self.add_subject(self.public_id("instance", unit[5:-8]), "instance", "DSH instance", "host-nas")
            subject = self.add_subject(self.public_id("invocation", invocation), "invocation", "Supervised run", parent)
            self.event(subject, "agent.lifecycle", kind, at, cursor or invocation + kind)
            self.state.update(journalLastSuccess=at, journalError=None)

    def metrics(self):
        rows = []
        for host, argv in self.config.get("metricsCommands", {}).items():
            if host not in ["nas", "strix-coordinator", "client"]:
                continue
            report = command(argv, timeout=8)
            subject = "host-" + host
            memory = report.get("memory", {})
            for raw, key in [("MemTotal", "host.memoryTotalBytes"), ("MemAvailable", "host.memoryAvailableBytes")]:
                value = memory.get(raw)
                rows.append(public_observation(subject, "host.pressure", key, value if finite(value) else None, at=report.get("at"), unit="bytes", scope="host-total"))
            for index, key in enumerate(["host.load1", "host.load5", "host.load15"]):
                values = report.get("load", [])
                value = values[index] if len(values) > index else None
                rows.append(public_observation(subject, "host.pressure", key, value if finite(value) else None, at=report.get("at"), scope="host-total"))
            gpu = report.get("gpu", {})
            if host == "strix-coordinator":
                value = gpu.get("gpu_busy_percent")
                rows.append(public_observation(subject, "inference.gpu", "gpu.utilizationPercent", value if finite(value) and 0 <= value <= 100 else None, at=report.get("at"), unit="percent", scope="host-total"))
                for suffix, key in [("used", "gpu.allocatedBytes"), ("total", "gpu.capacityBytes")]:
                    components = [gpu.get("mem_info_gtt_" + suffix), gpu.get("mem_info_vram_" + suffix)]
                    value = sum(components) if all(finite(number) for number in components) else None
                    rows.append(public_observation(subject, "inference.gpu", key, value, at=report.get("at"), unit="bytes", scope="host-total"))
                rows.append(public_observation(subject, "inference.gpu", "gpu.memoryAccountingKind", "shared-apu", at=report.get("at"), scope="host-total"))
        return rows

    def seats(self):
        # One slow acquisition owner. seats itself coalesces/cache-owns real
        # accounts and distinguishes provider observations from soft budgets.
        report = command(self.config["seatsCommand"], timeout=45)
        generated = instant(report.get("generated_at")) or dt.datetime.now(UTC)
        rows = []
        identity = {"cc": ("claude", 1), "cc2": ("claude", 2), "codex": ("codex", 1), "openrouter": ("openrouter", 1), "openrouter-free": ("openrouter", 1)}
        for seat in report.get("seats", []):
            if seat.get("id") not in identity:
                continue
            lane, slot = identity[seat["id"]]
            account = self.add_subject(f"account-{lane}-{slot}", "account", f"{PROVIDERS[lane]} account {slot}", "provider-" + lane)
            age = (seat.get("source") or {}).get("reading_age_seconds")
            measured_at = generated - dt.timedelta(seconds=age) if finite(age) and age >= 0 else None
            if not seat.get("windows") and lane in ["claude", "codex"]:
                bucket = self.add_subject(f"quota-{lane}-{slot}-other", "quota-bucket", PROVIDERS[lane] + " quota", account)
                rows.append(public_observation(bucket, "compute.subscriptions", "subscription.utilizationPercent", None, unit="percent", scope="provider-reported", error="unauthenticated" if seat.get("state") == "unauth" else "source-unavailable"))
            for index, window in enumerate(seat.get("windows", [])[:8]):
                start_index = len(rows)
                # No mutable model/window label crosses the boundary.
                minutes = window.get("minutes")
                kind = "weekly" if minutes == 10080 else "five-hour" if minutes == 300 else "daily" if minutes == 1440 else "other"
                bucket = self.add_subject(f"quota-{lane}-{slot}-{kind}-{index}", "quota-bucket", PROVIDERS[lane] + " quota", account)
                value = window.get("used_pct")
                valid = measured_at is not None and seat.get("grade") in ["MEASURED", "CACHED"] and finite(value) and 0 <= value <= 100
                rows.append(public_observation(bucket, "compute.subscriptions", "subscription.utilizationPercent", value if valid else None, at=stamp(measured_at) if measured_at else None, unit="percent", scope="provider-reported", error=None if valid else "source-unavailable", ttl=3600))
                rows.append(public_observation(bucket, "compute.subscriptions", "subscription.windowKind", kind, at=stamp(measured_at) if measured_at else None, scope="provider-reported", ttl=3600))
                resets = window.get("resets_at")
                rows.append(public_observation(bucket, "compute.subscriptions", "subscription.resetsAt", stamp(instant(resets)) if instant(resets) else None, at=stamp(measured_at) if measured_at else None, scope="provider-reported", ttl=3600))
                expire_at_reset(rows[start_index:], resets)
            # OpenRouter free account counter is a provider quota, distinct
            # from its local paid soft spending cap.
            if seat.get("id") == "openrouter-free":
                budget = seat.get("credits") or {}
                bucket = self.add_subject(f"quota-{lane}-{slot}-daily", "quota-bucket", PROVIDERS[lane] + " quota", account)
                for source_key, key in [("remaining", "quota.remaining"), ("limit", "quota.limit")]:
                    value = budget.get(source_key)
                    rows.append(public_observation(bucket, "compute.quota-headers", key, value if measured_at and finite(value) else None, at=stamp(measured_at) if measured_at else None, unit="requests", scope="provider-reported", ttl=3600))
                expire_at_reset(rows[-2:], budget.get("resets_at"))
        return rows

    def antigravity_quota(self, slot, argv):
        # Official standalone /usage is handled by the CLI without a model
        # turn. Only the configured Gemini pool is projected; no login or
        # credit fallback is permitted by the fixed argv in the module.
        if str(slot) not in ["1", "2", "3"]:
            raise RuntimeError("source-failed")
        text = command(argv, timeout=18, cap=16384, as_json=False)
        readings = []
        for line in text.splitlines():
            fields = line.split("\t")
            if len(fields) != 4 or fields[:2] != ["Gemini Models", "Weekly Limit Remaining"]:
                continue
            match = re.fullmatch(r"(100|[0-9]{1,2})(?:\.([0-9]+))?%", fields[2])
            reset = instant(fields[3])
            if not match or reset is None or reset <= dt.datetime.now(UTC):
                raise RuntimeError("source-failed")
            remaining = float(fields[2][:-1])
            if not 0 <= remaining <= 100:
                raise RuntimeError("source-failed")
            readings.append((remaining, stamp(reset)))
        if len(readings) != 1:
            raise RuntimeError("source-failed")
        remaining, reset = readings[0]
        account = self.add_subject(f"account-antigravity-{slot}", "account", f"{PROVIDERS['antigravity']} account {slot}", "provider-antigravity")
        bucket = self.add_subject(f"quota-antigravity-{slot}-gemini-weekly", "quota-bucket", PROVIDERS["antigravity"] + " quota", account)
        rows = [public_observation(bucket, "compute.subscriptions", key, value, unit=unit, scope="provider-reported", ttl=3600)
                for key, value, unit in [("subscription.utilizationPercent", 100 - remaining, "percent"), ("subscription.windowKind", "weekly", None), ("subscription.resetsAt", reset, None)]]
        return expire_at_reset(rows, reset)

    def zen_ledger(self, row):
        # Supplemental native receipt view, never added to DSH provider totals.
        # ACP currently reports no usage_steps: missing counters stay unknown.
        slot, invocation, steps = str(row.get("slot")), row.get("invocation_id"), row.get("usage_steps")
        at = instant(row.get("ts"))
        if row.get("lane") != "zen" or slot not in ["1", "2", "3", "4"] or not isinstance(invocation, str) or not 1 <= len(invocation) <= 256 or not isinstance(steps, list) or not steps or len(steps) > 1024 or at is None:
            return
        ident = hashlib.sha256(invocation.encode()).hexdigest()
        seen = self.state.setdefault("ledgerSeen", {})
        floor = instant(self.state.get("ledgerFloorAt"))
        if ident in seen or (floor and at <= floor):
            return
        totals = {}
        for step in steps:
            if not isinstance(step, dict):
                continue
            cache = step.get("cache") if isinstance(step.get("cache"), dict) else {}
            for key, value in [("inputTokens", step.get("input")), ("outputTokens", step.get("output")), ("reasoningTokens", step.get("reasoning")), ("cacheReadTokens", cache.get("read")), ("cacheWriteTokens", cache.get("write"))]:
                if finite(value) and value >= 0:
                    totals[key] = totals.get(key, 0) + value
        if not totals:
            return
        counts = self.state.setdefault("ledgerUsage", {}).setdefault(slot, {})
        for key, value in totals.items():
            counts[key] = counts.get(key, 0) + value
        counts["at"] = stamp(at)
        seen[ident] = stamp(at)
        if len(seen) > 4096:
            ordered = sorted(seen, key=seen.get)
            dropped = ordered[:-4096]
            self.state["ledgerFloorAt"] = max(seen[key] for key in dropped)
            for key in dropped:
                del seen[key]

    def cloudflare_quota(self):
        settings = self.config.get("cloudflareQuota")
        if not settings:
            return []
        account = Path(settings["accountFile"]).read_text().strip()
        token = Path(settings["tokenFile"]).read_text().strip()
        now = dt.datetime.now(UTC)
        query = "query($account: String!, $start: Time!, $end: Time!) { viewer { accounts(filter: {accountTag: $account}) { aiInferenceAdaptiveGroups(limit: 100, filter: {datetime_geq: $start, datetime_lt: $end}) { sum { totalNeurons } } } } }"
        payload = {"query": query, "variables": {"account": account, "start": stamp(now.replace(hour=0, minute=0, second=0, microsecond=0)), "end": stamp(now)}}
        request = urllib.request.Request("https://api.cloudflare.com/client/v4/graphql", data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        result = metadata_json(request, timeout=12, cap=1024 * 1024)
        if result.get("errors"):
            raise RuntimeError("source-failed")
        accounts = (result.get("data") or {}).get("viewer", {}).get("accounts", [])
        if len(accounts) != 1 or "aiInferenceAdaptiveGroups" not in accounts[0]:
            raise RuntimeError("source-unavailable")
        values = [group.get("sum", {}).get("totalNeurons") for group in accounts[0]["aiInferenceAdaptiveGroups"]]
        if not all(finite(value) and value >= 0 for value in values):
            raise RuntimeError("source-unavailable")
        usage = sum(values)
        account_subject = self.add_subject("account-cloudflare-1", "account", PROVIDERS["cloudflare"] + " account 1", "provider-cloudflare")
        bucket = self.add_subject("quota-cloudflare-1-neurons", "quota-bucket", PROVIDERS["cloudflare"] + " quota", account_subject)
        # The configured included allocation is declared, while its remainder
        # is computed against measured account analytics (which may lag).
        limit = settings["includedDailyNeurons"]
        reset = stamp(now.replace(hour=0, minute=0, second=0, microsecond=0) + dt.timedelta(days=1))
        return expire_at_reset([
            public_observation(bucket, "compute.quota-headers", "quota.limit", limit, unit="neurons", grade="declared", scope="shared-quota-bucket", ttl=7200),
            public_observation(bucket, "compute.quota-headers", "quota.remaining", max(0, limit - usage), unit="neurons", grade="computed", scope="shared-quota-bucket", ttl=7200),
            public_observation(bucket, "compute.quota-headers", "quota.resetAt", reset, scope="shared-quota-bucket", ttl=7200),
        ], reset)

    def vercel_quota(self):
        settings = self.config.get("vercelQuota")
        if not settings:
            return []
        token = Path(settings["tokenFile"]).read_text().strip()
        request = urllib.request.Request("https://ai-gateway.vercel.sh/v1/credits", headers={"Authorization": "Bearer " + token})
        result = metadata_json(request, timeout=12, cap=65536)
        balance = float(result["balance"])
        if not finite(balance) or balance < 0:
            raise RuntimeError("source-unavailable")
        account = self.add_subject("account-vercel-1", "account", PROVIDERS["vercel"] + " account 1", "provider-vercel")
        bucket = self.add_subject("quota-vercel-1-usd", "quota-bucket", PROVIDERS["vercel"] + " quota", account)
        return [public_observation(bucket, "compute.quota-headers", "quota.remaining", balance, unit="usd", scope="provider-reported", ttl=7200)]

    def lane(self, provider):
        if not isinstance(provider, str):
            return None
        if provider.startswith("antigravity-cli-"):
            return "antigravity"
        if provider.startswith("zen-cli-") or provider in ["opencode", "opencode-zen-free"]:
            return "zen"
        return {"gemini": "google", "cloudflare-workers-ai": "cloudflare", "vercel-ai-gateway": "vercel"}.get(provider, provider if provider in PROVIDERS else None)

    @synchronized
    def tails(self):
        sessions = self.state["sessions"]
        cursors = self.state["cursors"]
        directory = Path(self.config["dshSessions"])
        files = sorted(directory.glob("*/*/session.v4.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:256]
        truncated = len(files) >= 256
        remaining = 8 * 1024 * 1024
        for path in files:
            if remaining <= 0:
                truncated = True
                break
            private_key = str(path)
            new = private_key not in cursors
            enroll_end = self.new_process and new
            floor_gap = False
            if new and self.state.get("cursorFloorAt"):
                # Bounded cursor eviction must never turn an old owner into
                # new work. Its immutable session header is cheap metadata;
                # source modification time can change when someone touches it.
                try:
                    with path.open("rb") as stream:
                        header = json.loads(stream.readline(8192))
                    created = instant(header.get("createdAt")) if header.get("type") == "session" else None
                except (OSError, ValueError, UnicodeDecodeError):
                    created = None
                floor = instant(self.state["cursorFloorAt"])
                if created is None or created <= floor:
                    enroll_end = True
                    floor_gap = True
            records, gap, more = tail_jsonl(path, cursors, enroll_at_end=enroll_end, byte_budget=512 * 1024)
            cursors[private_key]["lastSeenAt"] = time.time()
            remaining -= cursors[private_key].get("lastReadBytes", 0)
            truncated = truncated or more or gap or floor_gap
            session = sessions.setdefault(private_key, {"id": self.public_id("session", private_key), "seq": -1, "state": "unknown"})
            session["seenAt"] = time.time()
            subject = self.add_subject(session["id"], "session", "DSH session", "host-nas")
            for record in records:
                kind, data = record.get("type"), record.get("data")
                if not isinstance(data, dict):
                    continue
                at = stamp(instant(record.get("time"))) if instant(record.get("time")) else stamp()
                if kind == "request/context":
                    session["lane"] = self.lane(data.get("provider"))
                    session["requestPending"] = True
                    session.pop("pendingUsage", None)
                    session.pop("pendingStep", None)
                    session.pop("pendingResponse", None)
                elif kind == "assistant/message":
                    # The persisted journal keeps usage here, whereas stdout
                    # repeats it on step_end. Retain numeric metadata only and
                    # join it to one canonical completion, never count twice.
                    session["pendingResponse"] = data.get("interrupted") is not True
                    session["pendingUsage"] = {key: value for key, value in (data.get("usage") or {}).items() if key in ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "reasoningTokens"] and finite(value) and value >= 0}
                    session["pendingStep"] = [data.get("turn"), data.get("step")]
                elif kind in ["turn/start", "turn/end"]:
                    reason = (data.get("reason") or {}).get("kind")
                    state = "active" if kind == "turn/start" else "completed" if reason == "completed" else "failed" if reason == "error" else "cancelled" if reason in ["aborted", "cancelled", "canceled"] else "unknown"
                    session.update(state=state, at=at)
                    self.event(subject, "agent.sessions", "session.status", at, private_key + ":" + str(record.get("seq")))
                elif kind == "step/end" and isinstance(record.get("seq"), int) and record["seq"] > session.get("seq", -1):
                    session["seq"] = record["seq"]
                    pending = session.pop("pendingUsage", {})
                    pending_step = session.pop("pendingStep", None)
                    responded = session.pop("pendingResponse", False)
                    attempted = session.pop("requestPending", False)
                    usage = data.get("usage") or (pending if pending_step == [data.get("turn"), data.get("step")] else {})
                    lane = session.get("lane")
                    if lane and (attempted or responded):
                        counts = self.state["usage"].setdefault(lane, {"calls": 0, "successes": 0, "refusals": 0, "errors": 0, "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "reasoningTokens": 0, "seenTokens": []})
                        counts["calls"] += 1
                        counts["successes"] += int(responded)
                        counts["at"] = at
                        # step/end is canonical. assistant/message repeats
                        # the SAME usage and is deliberately never counted.
                        for key in ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "reasoningTokens"]:
                            value = usage.get(key)
                            if finite(value) and value >= 0:
                                counts[key] += value
                                if key not in counts.setdefault("seenTokens", []):
                                    counts["seenTokens"].append(key)
                        self.event(subject, "agent.spans", "model.span", at, private_key + ":" + str(record["seq"]))
        # Receipt/lane headers supplement remaining quota. Do not add token
        # totals again to the canonical DSH completion aggregate.
        meter = Path(self.config["laneMeter"])
        meter_gap = False
        if meter.exists():
            records, gap, more = tail_jsonl(meter, cursors, enroll_at_end=self.new_process, byte_budget=512 * 1024)
            meter_gap = gap or more
            headers = self.state.setdefault("headers", {})
            for row in records:
                self.zen_ledger(row)
                lane = self.lane(row.get("lane"))
                if lane and isinstance(row.get("rl"), dict):
                    approved = {}
                    for key in ["x-ratelimit-limit-requests", "x-ratelimit-remaining-requests", "x-ratelimit-limit-tokens", "x-ratelimit-remaining-tokens"]:
                        try:
                            value = float(row["rl"][key])
                            if math.isfinite(value) and value >= 0:
                                approved[key] = value
                        except (KeyError, TypeError, ValueError):
                            pass
                    if approved:
                        headers[lane] = {"values": approved, "at": row.get("ts")}
        self.new_process = False
        if len(sessions) > 512:
            retained = sorted(sessions, key=lambda key: sessions[key].get("seenAt", 0), reverse=True)[:512]
            for key in list(sessions):
                if key not in retained:
                    del sessions[key]
                    # Keep owner offsets when evicting presentation metadata.
                    # Re-reading an evicted session must not re-add its tokens.
        if len(cursors) > 4096:
            keep = set(sessions) | {key for key in cursors if not key.endswith("session.v4.jsonl")}
            keep.update(sorted(cursors, key=lambda key: cursors[key].get("lastSeenAt", 0), reverse=True)[:4096 - len(keep)])
            for key in list(cursors):
                if key not in keep:
                    del cursors[key]
            # Header timestamps have millisecond precision. Preserve finer
            # precision here so same-second eviction cannot classify an old
            # owner as new work and count it again.
            self.state["cursorFloorAt"] = dt.datetime.now(UTC).isoformat(timespec="microseconds")
        rows = []
        for item in sessions.values():
            self.add_subject(item["id"], "session", "DSH session", "host-nas")
            rows.append(public_observation(item["id"], "agent.sessions", "session.state", item["state"], at=item.get("at"), ttl=180))
        for lane, counts in self.state["usage"].items():
            subject = "provider-" + lane
            for key in ["calls", "successes", "refusals", "errors"]:
                value = counts[key] if key in ["calls", "successes"] else None
                rows.append(public_observation(subject, "compute.call-history", "provider." + key, value, unit="count", scope="this-observer-only", grade="computed", error=None if value is not None else "not-instrumented", ttl=180))
            for key in ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "reasoningTokens"]:
                # A missing instrumented counter remains unknown, not zero.
                value = counts[key] if key in counts.get("seenTokens", []) else None
                rows.append(public_observation(subject, "compute.tokens", "usage." + key, value, unit="tokens", scope="this-observer-only", grade="computed", error="not-instrumented" if value is None else None, ttl=180))
            rows.append(public_observation(subject, "compute.call-history", "provider.lastResultAt", counts.get("at"), scope="this-observer-only", ttl=180))
        for lane, record in self.state.get("headers", {}).items():
            account = self.add_subject(f"account-{lane}-1", "account", PROVIDERS[lane] + " account 1", "provider-" + lane)
            for metric in ["requests", "tokens"]:
                bucket = self.add_subject(f"quota-{lane}-1-{metric}", "quota-bucket", PROVIDERS[lane] + " quota", account)
                for suffix, key in [("limit", "quota.limit"), ("remaining", "quota.remaining")]:
                    value = record["values"].get(f"x-ratelimit-{suffix}-{metric}")
                    if value is not None:
                        rows.append(public_observation(bucket, "compute.quota-headers", key, value, at=record.get("at"), unit=metric, scope="shared-quota-bucket", ttl=60))
        for slot, counts in self.state.get("ledgerUsage", {}).items():
            account = self.add_subject(f"account-zen-{slot}", "account", f"{PROVIDERS['zen']} account {slot}", "provider-zen")
            for key in ["inputTokens", "outputTokens", "reasoningTokens", "cacheReadTokens", "cacheWriteTokens"]:
                value = counts.get(key)
                rows.append(public_observation(account, "compute.tokens", "usage." + key, value, unit="tokens", scope="provider-reported", grade="computed", error="not-instrumented" if value is None else None, ttl=180))
        self.state["tailTruncated"] = {"sessions": truncated, "meter": meter_gap}
        return rows

    def acquire(self, name, function):
        try:
            return {"rows": function(), "error": None}
        except Exception as exc:
            safe = "source-timeout" if isinstance(exc, TimeoutError) else str(exc) if isinstance(exc, RuntimeError) and str(exc) in CONTRACT["errorCodes"] else "source-failed"
            return {"rows": None, "error": safe, "retryAfterAt": exc.retry_after if isinstance(exc, SourceError) else None}

    @synchronized
    def accept(self, name, result):
        if result.get("rows") is not None and (len(result["rows"]) > 4096 or len(json.dumps(result["rows"], separators=(",", ":"))) > 512 * 1024):
            result = {"rows": None, "error": "budget-truncated"}
        cache = self.cache.setdefault(name, {"rows": [], "failures": 0})
        cache["lastAttemptAt"] = stamp()
        if result["error"]:
            cache["error"] = result["error"]
            cache["failures"] += 1
        else:
            cache.update(rows=result["rows"], error=None, failures=0, lastSuccessAt=stamp())
        interval = self.config["intervals"][name]
        cache["nextAt"] = max(time.time() + min(3600, interval * 2 ** min(cache["failures"], 5)), result.get("retryAfterAt") or 0)
        if name == "cloudflareQuota" and not result["error"]:
            for row in result["rows"]:
                reset = instant(row["value"]) if row["key"] == "quota.resetAt" else None
                if reset:
                    cache["nextAt"] = min(cache["nextAt"], reset.timestamp() + 15)

    @synchronized
    def prune_metadata(self):
        # Run only between acquisitions: an in-flight source may have registered
        # new identities whose observations have not reached its cache yet.
        referenced = {row["subjectId"] for cache in self.cache.values() for row in cache.get("rows", [])}
        referenced.update(row["subjectId"] for row in self.state["events"])
        referenced.update(subject["id"] for subject in self.subjects.values() if subject["kind"] in ["fleet", "host", "provider", "account", "quota-bucket"])
        for _ in range(4):
            referenced.update(relation["targetId"] for ident in list(referenced) for relation in self.subjects.get(ident, {}).get("relations", []))
        self.subjects = {ident: subject for ident, subject in self.subjects.items() if ident in referenced}

    @synchronized
    def snapshot(self):
        observations = []
        coverage = {key: {"sourceId": key, "state": "disabled-by-policy" if key.startswith("optional.") or key in ["storage.smart", "host.temperatures"] else "not-configured", "lastAttemptAt": None, "lastSuccessAt": None, "errorCode": "not-instrumented"} for key in SOURCES}
        memberships = {"hosts": ["fleet.snapshot", "host.pressure"], "metrics": ["host.pressure", "inference.gpu"], "instances": ["agent.instances"], "seats": ["compute.subscriptions", "compute.quota-headers"], "cloudflareQuota": ["compute.quota-headers"], "vercelQuota": ["compute.quota-headers"], "tails": ["agent.sessions", "agent.spans", "compute.call-history", "compute.tokens", "compute.quota-headers"]}
        memberships.update({"antigravity" + str(slot): ["compute.subscriptions"] for slot in self.config.get("antigravityQuotaCommands", {})})
        acquired = {}
        for name, cache in self.cache.items():
            if name not in memberships:
                continue
            rows = refresh_rows(cache.get("rows", []), cache.get("lastAttemptAt"), cache.get("error"))
            observations.extend(rows)
            for source in memberships[name]:
                acquired.setdefault(source, []).append((cache, rows))
                truncated = self.state.get("tailTruncated", {})
                if name == "tails" and (truncated.get("meter") if source == "compute.quota-headers" else truncated.get("sessions")):
                    coverage[source].update(truncated=True, errorCode="budget-truncated")
        for source, groups in acquired.items():
            error = next((cache.get("error") for cache, _ in groups if cache.get("error")), None)
            source_rows = [row for _, rows in groups for row in rows if row["sourceId"] == source]
            reporting = bool(source_rows)
            if source == "compute.tokens":
                reporting = any(row.get("value") is not None for row in source_rows)
            elif source == "agent.spans":
                reporting = reporting or any(event.get("sourceId") == source for event in self.state.get("events", []))
            coverage[source].update(state="unavailable" if error else "reporting" if reporting else "not-configured",
                                    lastAttemptAt=max((cache.get("lastAttemptAt") or "" for cache, _ in groups), default="") or None,
                                    lastSuccessAt=max((cache.get("lastSuccessAt") or "" for cache, _ in groups), default="") or None,
                                    errorCode=error or coverage[source].get("errorCode") if coverage[source].get("truncated") else error or (None if reporting else "not-instrumented"))
        if self.config.get("journalCommand"):
            coverage["agent.lifecycle"] = {"sourceId": "agent.lifecycle", "state": "reporting" if self.state.get("journalLastSuccess") and not self.state.get("journalError") else "unavailable", "lastAttemptAt": stamp(), "lastSuccessAt": self.state.get("journalLastSuccess"), "errorCode": self.state.get("journalError") or ("cursor-gap" if self.state.get("journalGap") else None if self.state.get("journalLastSuccess") else "initial-enrollment")}
            if self.state.get("journalGap"):
                coverage["agent.lifecycle"].update(truncated=True, gapFrom=self.state["enrolledAt"])
        # Every provider remains visible even before any ordinary call emits
        # headers. No periodic inference or catalogue ping fills these gaps.
        for lane in PROVIDERS:
            subject = "provider-" + lane
            if not any(row["subjectId"] == subject and row["sourceId"] == "compute.tokens" for row in observations):
                observations.append(public_observation(subject, "compute.tokens", "usage.inputTokens", None, error="not-instrumented", scope="this-observer-only"))
        subjects = dict(self.subjects)
        # Cache rows survive restarts. Restore only fixed public subject records
        # persisted by this observer, never derive labels from source titles.
        for item in self.state.get("subjects", []):
            subjects.setdefault(item["id"], item)
        # The outbound publisher may have committed a higher sequence before
        # a local state restore. Never reuse a remotely committed sequence.
        try:
            remote = json.loads((self.directory / "publisher.json").read_text()).get("remoteSequence", 0)
        except FileNotFoundError:
            remote = 0
        self.state["sequence"] = max(self.state["sequence"], remote) + 1
        # Coalesced fast sources replace the corresponding broad cached fact;
        # one logical subject/source/key never appears twice in a snapshot.
        unique = {}
        for row in observations:
            key = (row["subjectId"], row["sourceId"], row["key"])
            previous = unique.get(key)
            if previous is None or (row.get("observedAt") or "") >= (previous.get("observedAt") or ""):
                unique[key] = row
        observations = list(unique.values())
        referenced = {row["subjectId"] for row in observations} | {row["subjectId"] for row in self.state["events"]}
        referenced.update("provider-" + lane for lane in PROVIDERS)
        referenced.update(["fleet", "host-nas", "host-strix-coordinator", "host-client", "host-strix-worker"])
        for _ in range(4):
            referenced.update(relation["targetId"] for ident in list(referenced) for relation in subjects.get(ident, {}).get("relations", []))
        subjects = {key: value for key, value in subjects.items() if key in referenced}
        result = {"schemaVersion": "fleet-observations/1", "snapshotId": "snapshot-" + str(self.state["sequence"]), "synthetic": False,
                  "publisher": {"id": "nas-observer", "sequence": self.state["sequence"], "expectedHeartbeatSeconds": 60},
                  "generatedAt": stamp(), "subjects": sorted(subjects.values(), key=lambda row: row["id"]), "observations": observations,
                  "events": self.state["events"], "coverage": list(coverage.values())}
        signals = sorted({(row["sourceId"], row["key"], row.get("unit", "")) for row in observations})
        descriptor = json.dumps({"subjects": result["subjects"], "sources": sorted(SOURCES), "signals": signals}, sort_keys=True, separators=(",", ":"))
        result["catalogRevision"] = hashlib.sha256(descriptor.encode()).hexdigest()
        if len(json.dumps(result)) > 1024 * 1024:
            raise RuntimeError("budget-truncated")
        self.state["subjects"] = result["subjects"]
        return validate_public(result)

    @synchronized
    def publish(self):
        value = self.snapshot()
        # Persist sequence/cursors before public replacement. A crash may skip
        # a sequence but can never reuse it for a different snapshot.
        atomic_json(self.directory / "state.json", self.state)
        atomic_json(self.directory / "public/status.json", value)
        return value

    def close(self):
        STOP.set()
        child = self.journal_child
        if child and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
        if self.journal_thread:
            self.journal_thread.join(timeout=5)
        self.pool.shutdown(wait=True, cancel_futures=True)
        self.publisher_pool.shutdown(wait=True, cancel_futures=True)

    def run(self, once=False):
        functions = {"hosts": self.hosts, "metrics": self.metrics, "instances": self.instances, "seats": self.seats, "tails": self.tails}
        for slot, argv in self.config.get("antigravityQuotaCommands", {}).items():
            functions["antigravity" + str(slot)] = lambda slot=slot, argv=argv: self.antigravity_quota(slot, argv)
        if self.config.get("cloudflareQuota"):
            functions["cloudflareQuota"] = self.cloudflare_quota
        if self.config.get("vercelQuota"):
            functions["vercelQuota"] = self.vercel_quota
        if once:
            for name, fn in functions.items():
                self.accept(name, self.acquire(name, fn))
            return self.publish()
        next_publish = 0
        if self.config.get("journalCommand"):
            self.journal_thread = threading.Thread(target=self.journal, name="fleet-lifecycle", daemon=True)
            self.journal_thread.start()
        try:
            while not STOP.is_set():
                self.drain_journal()
                for name, fn in functions.items():
                    if name in self.futures and self.futures[name].done():
                        self.accept(name, self.futures.pop(name).result())
                    if name not in self.futures and time.time() >= self.cache.get(name, {}).get("nextAt", 0):
                        self.futures[name] = self.pool.submit(self.acquire, name, fn)
                if not self.futures:
                    self.prune_metadata()
                if time.monotonic() >= next_publish:
                    self.publish()
                    if self.config.get("publishUrl") and (self.publisher_future is None or self.publisher_future.done()):
                        argv = [self.config["python"], str(ROOT / "publisher.py"), "--snapshot", str(self.directory / "public/status.json"), "--state-dir", str(self.directory), "--url", self.config["publishUrl"], "--token-file", self.config["publishTokenFile"]]
                        self.publisher_future = self.publisher_pool.submit(self.acquire, "publisher", lambda: command(argv, timeout=30))
                    next_publish = time.monotonic() + 60
                STOP.wait(2)
        finally:
            self.close()
            self.publish()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--state-dir", default=str(Path.home() / ".local/state/fleet-status"))
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    for sig in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(sig, lambda *_: STOP.set())
    observer = Observer(json.loads(Path(args.config).read_text()), args.state_dir)
    value = observer.run(args.once)
    if args.once:
        print(json.dumps({"snapshotId": value["snapshotId"], "subjects": len(value["subjects"]), "observations": len(value["observations"])}))


if __name__ == "__main__":
    main()
