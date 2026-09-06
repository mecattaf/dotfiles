#!/usr/bin/env python3
"""Replay the declared seat feeders over 60 policy ticks.

The admission event is produced by U-B10's real ``tally-admit`` binary, built
offline by ``tools/feeder-fixture.sh`` into the fixture's temporary directory.
No freshness logic is duplicated here. The replay also checks every output
row's source timestamp, because an UNKNOWN row is refused by the meter decoder
before a kernel Decision can carry its age.
"""

import argparse
import json
import os
import stat
import subprocess
import sys
from datetime import datetime, timedelta, timezone

TICK_SECONDS = 60
TICK_MILLISECONDS = 60_000
PROBE_OFFSET_SECONDS = 5
START = datetime(2026, 9, 6, 0, 0, 0, tzinfo=timezone.utc)
PROBE_ROW = "codex"
FEEDER_PREFIX = "tally-seat-feeder-"
DECLARED_FEEDERS = [
    "tally-seat-feeder-claude",
    "tally-seat-feeder-codex",
    "tally-seat-feeder-pi-qwencloud",
]


def rfc3339(value):
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_time(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def read_json(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def read_bytes(path):
    with open(path, "rb") as stream:
        return stream.read()


def read_table(path, columns):
    rows = []
    with open(path, encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) != columns:
                raise ValueError(f"{path}:{number}: expected {columns} tab-separated cells")
            rows.append(cells)
    return rows


def fail(failures, message):
    failures.append(message)


def check_config(coordinator_path, worker_path, timers, failures):
    """Tie the replay table to the Home Manager objects evaluated by Nix."""
    coordinator = read_json(coordinator_path)
    worker = read_json(worker_path)
    coordinator_timers = coordinator.get("timers") or {}
    coordinator_services = coordinator.get("services") or {}
    worker_timers = worker.get("timers") or {}
    worker_services = worker.get("services") or {}

    actual = sorted(name for name in coordinator_timers if name.startswith(FEEDER_PREFIX))
    if actual != DECLARED_FEEDERS:
        fail(failures, f"C1 coordinator timers are {actual!r}, wanted {DECLARED_FEEDERS!r}")
    worker_actual = sorted(name for name in worker_timers if name.startswith(FEEDER_PREFIX))
    if worker_actual:
        fail(failures, f"C2 worker unexpectedly declares feeder timers {worker_actual!r}")
    worker_services_actual = sorted(
        name for name in worker_services if name.startswith(FEEDER_PREFIX)
    )
    if worker_services_actual:
        fail(failures, f"C2 worker unexpectedly declares services {worker_services_actual!r}")

    table_names = sorted(unit.removesuffix(".timer") for unit, *_rest in timers)
    if table_names != DECLARED_FEEDERS:
        fail(failures, f"C3 fixture timers are {table_names!r}, Nix has {DECLARED_FEEDERS!r}")

    for unit, instrument, row_csv, cadence, accuracy in timers:
        name = unit.removesuffix(".timer")
        timer = coordinator_timers.get(name)
        service = coordinator_services.get(name)
        if timer is None or service is None:
            fail(failures, f"C4 {unit} has no matching timer+service pair")
            continue
        timer_body = timer.get("Timer") or {}
        if timer_body.get("OnUnitActiveSec") != f"{cadence}s":
            fail(failures, f"C5 {unit} cadence differs from {cadence}s")
        if timer_body.get("AccuracySec") != f"{accuracy}s":
            fail(failures, f"C5 {unit} accuracy differs from {accuracy}s")
        if timer_body.get("Unit") != f"{name}.service":
            fail(failures, f"C5 {unit} activates the wrong service")
        if (timer.get("Install") or {}).get("WantedBy") != ["timers.target"]:
            fail(failures, f"C5 {unit} is not enabled on timers.target")

        service_unit = service.get("Unit") or {}
        if service_unit.get("X-TallyRows") != row_csv:
            fail(failures, f"C6 {unit} row list differs from {row_csv}")
        if service_unit.get("X-TallyTickSeconds") != str(TICK_SECONDS):
            fail(failures, f"C6 {unit} does not carry the policy tick")
        service_body = service.get("Service") or {}
        command = service_body.get("ExecStart") or []
        if isinstance(command, list):
            command = " ".join(command)
        if command != f"%h/.local/bin/tally-seat-feeder {instrument}":
            fail(failures, f"C7 {unit} runs {command!r}")
        environment = service_body.get("Environment") or []
        if "TALLY_REWRITE_METERS=%h/.local/state/tally-rewrite/meters" not in environment:
            fail(failures, f"C8 {unit} has no rewrite meters path")
        if ".local/state/tally/meters" in json.dumps(service, sort_keys=True):
            fail(failures, f"C8 {unit} names the pinned live meters path")

    expected_dir = "d %h/.local/state/tally-rewrite/meters 0700 - - -"
    if expected_dir not in (coordinator.get("tmpfiles") or []):
        fail(failures, "C9 Home Manager does not create the rewrite meters directory")


def feeder_environment(repo, workdir, when, target=None, overrides=None):
    environment = {
        **os.environ,
        "HOME": os.path.join(workdir, "home"),
        "TALLY_REWRITE_METERS": target or os.path.join(workdir, "meters"),
        "TALLY_STAMP_RECEIPT": os.path.join(
            repo, "tests", "seat-feeder", "inputs", "stamp-receipt-fixture.py"
        ),
        "TALLY_CODEX_SESSIONS": os.path.join(
            repo, "tests", "seat-feeder", "inputs", "codex-sessions"
        ),
        "TALLY_CLAUDE_SEATS": "cc cc2 cc3",
        "TALLY_FEEDER_NOW": rfc3339(when),
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    if overrides:
        environment.update(overrides)
    return environment


def run_feeder(repo, workdir, instrument, when, target=None, overrides=None):
    return subprocess.run(
        [
            sys.executable,
            os.path.join(repo, "home", "dot_local", "bin", "tally-seat-feeder"),
            instrument,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=feeder_environment(repo, workdir, when, target, overrides),
        check=False,
    )


def check_live_tree_refusal(repo, workdir, failures):
    """Exercise the non-goal without touching the user's real live tree."""
    fake_home = os.path.join(workdir, "home")
    live = os.path.join(fake_home, ".local", "state", "tally", "meters")
    os.makedirs(live, mode=0o700, exist_ok=True)
    sentinel = os.path.join(live, "PINNED")
    with open(sentinel, "w", encoding="utf-8") as stream:
        stream.write("unchanged\n")
    before = read_bytes(sentinel)

    direct = run_feeder(repo, workdir, "pi-qwencloud", START, target=live)
    if direct.returncode != 3:
        fail(failures, f"S1 direct live-tree target returned {direct.returncode}, wanted 3")

    redirect = os.path.join(workdir, "redirected-meters")
    os.symlink(live, redirect)
    linked = run_feeder(repo, workdir, "pi-qwencloud", START, target=redirect)
    if linked.returncode != 3:
        fail(failures, f"S2 symlinked live-tree target returned {linked.returncode}, wanted 3")

    if read_bytes(sentinel) != before or sorted(os.listdir(live)) != ["PINNED"]:
        fail(failures, "S3 the pinned-tree refusal changed its fixture sentinel")


def check_codex_read_boundary(repo, workdir, failures):
    """A rollout-looking symlink to auth data must not become an input."""
    boundary = os.path.join(workdir, "codex-boundary")
    sessions = os.path.join(boundary, "sessions")
    meters = os.path.join(boundary, "meters")
    os.makedirs(sessions, mode=0o700)
    os.makedirs(meters, mode=0o700)
    auth = os.path.join(boundary, "auth.json")
    with open(auth, "w", encoding="utf-8") as stream:
        json.dump(
            {
                "rate_limits": {
                    "primary": {
                        "used_percent": 99,
                        "window_minutes": 10080,
                        "resets_at": 1789197526,
                    }
                }
            },
            stream,
        )
    before = read_bytes(auth)
    os.symlink(auth, os.path.join(sessions, "rollout-auth-leak.jsonl"))

    process = run_feeder(
        repo,
        workdir,
        "codex",
        START,
        target=meters,
        overrides={"TALLY_CODEX_SESSIONS": sessions},
    )
    if process.returncode != 0:
        fail(failures, f"S4 Codex symlink-boundary fixture returned {process.returncode}")
        return
    payload = read_json(os.path.join(meters, "codex.json"))
    if row_grade(payload) != "UNKNOWN" or payload.get("utilization_pct") is not None:
        fail(failures, "S4 Codex reader followed a rollout symlink to auth data")
    if read_bytes(auth) != before:
        fail(failures, "S4 Codex boundary fixture changed auth data")


def row_observed_at(row):
    readings = row.get("readings")
    if isinstance(readings, list) and readings:
        last = readings[-1]
        if isinstance(last, dict) and last.get("taken_at"):
            return parse_time(last["taken_at"])
    return parse_time(row.get("observed_at") or row.get("updated_at"))


def row_grade(row):
    if row.get("grade") is not None:
        return row["grade"]
    capacity = row.get("capacity")
    if isinstance(capacity, dict):
        return capacity.get("grade")
    return None


def validate_seeded_rows(meters, rows, failures):
    expected_ids = sorted(row_id for row_id, *_rest in rows)
    actual_ids = sorted(
        name[:-5]
        for name in os.listdir(meters)
        if name.endswith(".json") and not name.startswith(".")
    )
    if actual_ids != expected_ids:
        fail(failures, f"R1 row files are {actual_ids!r}, wanted {expected_ids!r}")
        return

    by_id = {}
    for row_id, _instrument, owner, grade in rows:
        path = os.path.join(meters, row_id + ".json")
        payload = read_json(path)
        by_id[row_id] = payload
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode != 0o600:
            fail(failures, f"R2 {row_id}.json mode is {mode:o}, wanted 600")
        if payload.get("seat") != row_id or payload.get("owner") != owner:
            fail(failures, f"R3 {row_id}.json identity/owner differs")
        if row_grade(payload) != grade:
            fail(failures, f"R4 {row_id}.json grade differs from {grade}")
        if row_observed_at(payload) != START:
            fail(failures, f"R5 {row_id}.json did not preserve the source time")

    for row_id in ("cc", "cc2"):
        window = by_id.get(row_id, {}).get("window") or {}
        if window.get("kind") != "nested" or not window.get("primary") or not window.get("secondary"):
            fail(failures, f"R6 {row_id}.json is not a complete nested window")
    cc_reset = (((by_id.get("cc") or {}).get("window") or {}).get("primary") or {}).get(
        "resets_at"
    )
    cc2_reset = (((by_id.get("cc2") or {}).get("window") or {}).get("primary") or {}).get(
        "resets_at"
    )
    if not cc_reset or not cc2_reset or cc_reset == cc2_reset:
        fail(failures, "R7 cc and cc2 do not retain their separate reset clocks")

    codex = by_id.get("codex") or {}
    codex_window = codex.get("window") or {}
    if (
        codex.get("owner") != "third-party"
        or codex_window.get("kind") != "rolling"
        or codex_window.get("minutes") != 10080
        or not codex_window.get("resets_at")
    ):
        fail(failures, "R8 codex does not carry the third-party rolling window")

    pi = by_id.get("pi-qwencloud") or {}
    reason = ((pi.get("capacity") or {}).get("reason") or "")
    if "window" in pi:
        fail(failures, "R9 pi-qwencloud invented a window instead of leaving it UNKNOWN")
    if "TL-17" not in reason or "D-B17" not in reason:
        fail(failures, "R9 pi-qwencloud does not name its UNKNOWN reason")


def run_admit(binary, workdir, meters, row_id, when):
    environment = {**os.environ, "HOME": os.path.join(workdir, "home")}
    process = subprocess.run(
        [binary, row_id, "--meters", meters, "--now", rfc3339(when)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=False,
    )
    try:
        decision = json.loads(process.stdout.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        decision = None
    return process, decision


def replay(args):
    repo = os.path.abspath(args.repo)
    workdir = os.path.abspath(args.workdir)
    meters = os.path.join(workdir, "meters")
    os.makedirs(meters, mode=0o700, exist_ok=True)
    os.makedirs(os.path.join(workdir, "home"), mode=0o700, exist_ok=True)

    try:
        timers = read_table(os.path.join(repo, "tests", "seat-feeder", "timers.tsv"), 5)
        rows = read_table(os.path.join(repo, "tests", "seat-feeder", "rows.tsv"), 4)
    except (OSError, ValueError) as error:
        print(f"replay: fixture table error: {error}", file=sys.stderr)
        return 2

    failures = []
    check_config(args.coordinator_config, args.worker_config, timers, failures)
    check_live_tree_refusal(repo, workdir, failures)
    check_codex_read_boundary(repo, workdir, failures)

    # Seed every row independently of the timer table. Removing a timer then
    # leaves a real but ageing observation, which is precisely the mutation.
    instruments = []
    for _row_id, instrument, _owner, _grade in rows:
        if instrument not in instruments:
            instruments.append(instrument)
    for instrument in instruments:
        process = run_feeder(repo, workdir, instrument, START)
        if process.returncode != 0:
            print(
                f"replay: seed {instrument} returned {process.returncode}: "
                f"{process.stderr.decode('utf-8', 'replace').strip()}",
                file=sys.stderr,
            )
            return 2
    validate_seeded_rows(meters, rows, failures)

    fed = {}
    for unit, instrument, row_csv, cadence, accuracy in timers:
        try:
            cadence_value = int(cadence)
            int(accuracy)
        except ValueError:
            fail(failures, f"T0 {unit} has a non-integer cadence/accuracy")
            continue
        for row_id in row_csv.split(","):
            fed[row_id] = (unit, instrument, cadence_value)
    for row_id, *_rest in rows:
        if row_id not in fed:
            fail(failures, f"T1 no fixture timer feeds {row_id}")

    probes = 0
    row_age_checks = 0
    with open(args.log, "w", encoding="utf-8") as log:
        for tick in range(1, args.ticks + 1):
            tick_at = START + timedelta(seconds=TICK_SECONDS * tick)
            for unit, instrument, _row_csv, cadence, _accuracy in timers:
                try:
                    due = (TICK_SECONDS * tick) % int(cadence) == 0
                except ValueError:
                    continue
                if not due:
                    continue
                process = run_feeder(repo, workdir, instrument, tick_at)
                log.write(
                    json.dumps(
                        {
                            "at": rfc3339(tick_at),
                            "event": "timer",
                            "instrument": instrument,
                            "rc": process.returncode,
                            "tick": tick,
                            "unit": unit,
                        },
                        sort_keys=True,
                    )
                    + "\n"
                )
                if process.returncode != 0:
                    fail(
                        failures,
                        f"tick {tick}: {unit} returned {process.returncode}: "
                        f"{process.stderr.decode('utf-8', 'replace').strip()}",
                    )

            probe_at = tick_at + timedelta(seconds=PROBE_OFFSET_SECONDS)
            for row_id, _instrument, _owner, expected_grade in rows:
                path = os.path.join(meters, row_id + ".json")
                try:
                    payload = read_json(path)
                    observed = row_observed_at(payload)
                    grade = row_grade(payload)
                except (OSError, ValueError):
                    observed = None
                    grade = None
                age_ms = None
                if observed is not None:
                    age_ms = int((probe_at - observed).total_seconds() * 1000)
                log.write(
                    json.dumps(
                        {
                            "age_ms": age_ms,
                            "at": rfc3339(probe_at),
                            "event": "row-age",
                            "grade": grade,
                            "row": row_id,
                            "tick": tick,
                            "timer": fed.get(row_id, ("<none>", "", 0))[0],
                        },
                        sort_keys=True,
                    )
                    + "\n"
                )
                row_age_checks += 1
                if age_ms is None or age_ms > TICK_MILLISECONDS:
                    fail(failures, f"tick {tick} row {row_id}: age {age_ms}ms is past one tick")
                if grade != expected_grade:
                    fail(
                        failures,
                        f"tick {tick} row {row_id}: grade {grade!r}, wanted {expected_grade}",
                    )

            process, decision = run_admit(args.admit, workdir, meters, PROBE_ROW, probe_at)
            probes += 1
            if decision is None:
                fail(failures, f"tick {tick}: tally-admit returned non-JSON rc {process.returncode}")
                decision = {}
            observation = decision.get("observation") or {}
            event = {
                "age_ms": observation.get("ageMs"),
                "at": rfc3339(probe_at),
                "event": "admit",
                "rc": process.returncode,
                "reason": decision.get("reason"),
                "row": PROBE_ROW,
                "signal": decision.get("signal"),
                "tick": tick,
                "timer": fed.get(PROBE_ROW, ("<none>", "", 0))[0],
            }
            log.write(json.dumps(event, sort_keys=True) + "\n")
            if event["age_ms"] is None or event["age_ms"] > TICK_MILLISECONDS:
                fail(
                    failures,
                    f"tick {tick} admit {PROBE_ROW}: age {event['age_ms']}ms is past one tick "
                    f"({event['signal']} {event['reason']})",
                )
            if event["signal"] == "SLOW" and event["reason"] == "stale_observation":
                fail(failures, f"tick {tick} admit {PROBE_ROW}: SLOW stale_observation")

            # Even if config/table drift was already found, execute the first
            # probe: under the mutation it is the evidence that matters.
            if failures:
                break

    print(
        f"replay: {args.ticks} ticks requested, {probes} real tally-admit probes, "
        f"{row_age_checks} row-age checks, log {args.log}"
    )
    if failures:
        print(f"replay: RED ({len(failures)} assertion(s)); first failures:")
        for failure in failures[:12]:
            print("  " + failure)
        return 1
    print(
        "replay: every tally-admit probe read age <= 60000ms; every fed row "
        "was re-stamped within one policy tick"
    )
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--admit", required=True)
    parser.add_argument("--coordinator-config", required=True)
    parser.add_argument("--worker-config", required=True)
    parser.add_argument("--ticks", type=int, default=60)
    parser.add_argument("--log", required=True)
    args = parser.parse_args(argv)
    if args.ticks < 1:
        parser.error("--ticks must be positive")
    return replay(args)


if __name__ == "__main__":
    sys.exit(main())
