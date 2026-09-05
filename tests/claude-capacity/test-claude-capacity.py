#!/usr/bin/env python3
"""Hermetic tests for home/dot_local/bin/claude-capacity (the capacity oracle).

NO NETWORK IS REQUIRED OR USED. Every case drives the script through its cache:
a temp XDG_RUNTIME_DIR holds a seeded reading, and a temp HOME holds a
credentials file whose token is deliberately invalid — so any code path that
does reach the network fails, which is exactly the failure the stale-fallback
and unknown paths are supposed to survive. That makes this runnable inside a
nix build sandbox (`nix build .#checks.<sys>.claude-capacity`) and on a plane.

What is pinned here is the CONTRACT the tally admission hook depends on
(DECISION-R2-1): exit 0 = headroom/admit, 1 = no headroom/defer, 2 = cannot
determine. A regression in those three numbers silently changes whether the
fleet dispatches, so they are asserted rather than assumed.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
SCRIPT = os.environ.get("CLAUDE_CAPACITY") or os.path.join(
    os.path.dirname(HERE), os.pardir, "home", "dot_local", "bin", "claude-capacity")
SCRIPT = os.path.realpath(SCRIPT)

FULL = {
    "five_hour":        {"utilization": 4.0,  "resets_at": "2026-09-02T08:39:59+00:00"},
    "seven_day":        {"utilization": 24.0, "resets_at": "2026-09-02T09:59:59+00:00"},
    "seven_day_opus":   {"utilization": 95.0, "resets_at": "2026-09-05T00:00:00+00:00"},
    "seven_day_sonnet": {"utilization": 12.0, "resets_at": "2026-09-05T00:00:00+00:00"},
}


def make_env():
    runtime = tempfile.mkdtemp(prefix="cap-runtime-")
    home = tempfile.mkdtemp(prefix="cap-home-")
    os.makedirs(os.path.join(home, ".claude"), exist_ok=True)
    # A syntactically valid, semantically dead token: never expired (so the
    # script proceeds past load_token) and never accepted (so any real request
    # fails). Nothing here is a credential.
    with open(os.path.join(home, ".claude", ".credentials.json"), "w", encoding="utf-8") as fh:
        json.dump({"claudeAiOauth": {
            "accessToken": "sk-ant-oat-TEST-NOT-A-REAL-TOKEN",
            "expiresAt": int((time.time() + 86400) * 1000),
        }}, fh)
    env = dict(os.environ, XDG_RUNTIME_DIR=runtime, HOME=home)
    return env, os.path.join(runtime, "claude-capacity-cache.json")


def seed(cache, age_seconds, data):
    with open(cache, "w", encoding="utf-8") as fh:
        json.dump({"fetched_at": time.time() - age_seconds, "data": data}, fh)


def run(env, *args):
    proc = subprocess.run([sys.executable, SCRIPT, *args],
                          capture_output=True, text=True, env=env, timeout=60)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


RESULTS = []


def case(name, got, want_rc, want_sub=""):
    rc, out = got
    ok = rc == want_rc and want_sub in out
    RESULTS.append((ok, name, f"want rc={want_rc} sub={want_sub!r}; got rc={rc} out={out!r}"))


def main():
    env, cache = make_env()

    # --- fresh cache: the measured paths -----------------------------------
    seed(cache, 5, FULL)
    case("--check any: worst window (opus 95%) drives the verdict -> defer",
         run(env, "--check"), 1, "seven_day_opus")
    case("--check five_hour 4% -> headroom (exit 0)",
         run(env, "--check", "--window", "five_hour"), 0, "headroom")
    case("--check seven_day 24% -> headroom (exit 0)",
         run(env, "--check", "--window", "seven_day"), 0, "headroom")
    case("--check seven_day_opus 95% >= 90 -> defer (exit 1)",
         run(env, "--check", "--window", "seven_day_opus"), 1, "defer")
    case("--check seven_day_sonnet 12% -> headroom: admission is model-aware",
         run(env, "--check", "--window", "seven_day_sonnet"), 0, "headroom")
    case("--threshold raises the bar: opus 95% < 99 -> headroom",
         run(env, "--check", "--window", "seven_day_opus", "--threshold", "99"), 0, "headroom")
    case("--threshold lowers the bar: five_hour 4% >= 1 -> defer",
         run(env, "--check", "--window", "five_hour", "--threshold", "1"), 1, "defer")
    case("--json emits ok:true", run(env, "--json"), 0, '"ok": true')
    case("waybar text carries the worst window", run(env), 0, "95%")
    case("waybar percentage is capped and present", run(env), 0, '"percentage": 95')

    # --- a reading in hand needs no token ----------------------------------
    # Regression guard: `claude` rewriting ~/.claude/.credentials.json, or any
    # momentary unreadability, must NOT turn a five-second-old measurement into
    # "cannot determine" and defer the queue. The cache is consulted first.
    nocreds_fresh = dict(env, HOME=tempfile.mkdtemp(prefix="cap-nocreds-"))
    case("fresh cache + no credentials at all -> still a measured verdict",
         run(nocreds_fresh, "--check", "--window", "five_hour"), 0, "headroom")
    case("fresh cache + no credentials -> waybar still shows the number",
         run(nocreds_fresh), 0, "95%")

    # --- stale cache: the API is down, an old reading beats "unknown" ------
    seed(cache, 600, FULL)
    case("stale but within grace -> served, marked stale, still exit 0",
         run(env, "--check", "--window", "five_hour"), 0, "stale reading, 10m old")
    case("stale waybar -> stale line in tooltip",
         run(env), 0, "stale: API unreachable")

    # --- unknowns: every one of these must be exit 2, never 0 --------------
    seed(cache, 100000, FULL)
    case("beyond the stale grace -> cannot determine (exit 2)",
         run(env, "--check"), 2, "unknown:")
    seed(cache, 5, {"five_hour": {"utilization": 4.0, "resets_at": None}})
    case("named window absent from the API answer -> exit 2, never 'headroom'",
         run(env, "--check", "--window", "seven_day_opus"), 2, "not reported")
    seed(cache, 5, {})
    case("API reports no windows at all -> exit 2, not a free pass",
         run(env, "--check"), 2, "no usage windows reported")
    with open(cache, "w", encoding="utf-8") as fh:
        fh.write("{ this is not json")
    case("corrupt cache is a miss, not a crash", run(env, "--check"), 2, "unknown:")
    os.unlink(cache)
    case("no cache and no usable token -> exit 2", run(env, "--check"), 2, "unknown:")

    # --- waybar's contract: it must NEVER exit nonzero ---------------------
    case("waybar mode exits 0 even with nothing to report", run(env), 0, "")
    case("waybar mode exits 0 with a corrupt runtime dir",
         run(dict(env, XDG_RUNTIME_DIR="/nonexistent/nope")), 0, "")

    # --- no-creds ----------------------------------------------------------
    nocreds = dict(env, HOME=tempfile.mkdtemp(prefix="cap-nohome-"),
                   XDG_RUNTIME_DIR=tempfile.mkdtemp(prefix="cap-noruntime-"))
    case("missing credentials -> --check exit 2", run(nocreds, "--check"), 2, "credentials file missing")
    case("missing credentials -> waybar still exit 0 with the critical class",
         run(nocreds), 0, '"critical"')

    failed = 0
    for ok, name, detail in RESULTS:
        print(("PASS  " if ok else "FAIL  ") + name)
        if not ok:
            print("        " + detail)
            failed += 1
    print(f"\n{len(RESULTS) - failed}/{len(RESULTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
