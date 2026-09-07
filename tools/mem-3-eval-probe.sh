#!/usr/bin/env bash
# MEM-3 evaluator's own probe (procedure step 2b) — the floor beneath the card.
#
#   bash tools/mem-3-eval-probe.sh [<worktree root>]
#
# MEM-3's DOMINANT oracle asserts one happy harvest (two units -> two rows), one
# refusal driven through the validator's own seam, the store fence and the
# exemplar's shape. Nothing in it re-harvests a CHANGED session, hands the verb
# a unit sentence that is not plain ASCII, harvests a session with NO unresolved
# units, points the verb at a store it cannot write, or asks the validator what
# it does with a well-formed row saved under the wrong name. Those are the five
# things a mover, a hook firing on a busy session, or a full disk would meet
# first. Every case is hermetic: one scratch tree, the delivered engine and the
# delivered validator, and a before/after census of the live events dir to prove
# D-E07 held.
#
# Exit 0 when every case holds, 1 with the failing case on stderr otherwise.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENGINE="$ROOT/home/dot_claude/skills/drain/scripts/ai_memory.py"
CHECK="$ROOT/tools/enqueue-row-check.py"
TESTS="$ROOT/tests/ai-memory"
LIVE="$HOME/.local/state/tally/events"

for path in "$ENGINE" "$CHECK" "$TESTS/test_ai_memory.py"; do
  [ -e "$path" ] || { echo "probe: missing $path" >&2; exit 1; }
done

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/mem-3-eval-probe.XXXXXX")"
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT

# D-E07: census the live events dir BEFORE, read-only, so the probe can prove
# nothing it ran wrote there. Never a write, never the daemon.
BEFORE="$(ls -1 "$LIVE" 2>/dev/null | wc -l)"

AI_MEMORY_ENGINE="$ENGINE" \
AI_MEMORY_ENQUEUE_CHECK="$CHECK" \
MEM3_SCRATCH="$SCRATCH" \
MEM3_LIVE="$LIVE" \
python3 - "$TESTS" <<'PY'
import io, json, os, re, subprocess, sys, contextlib, tempfile, shutil
from pathlib import Path
from datetime import datetime
from unittest import mock

sys.path.insert(0, sys.argv[1])
import test_ai_memory as suite          # the delivered fixtures and helpers
memory = suite.memory

SCRATCH = Path(os.environ["MEM3_SCRATCH"])
CHECK = Path(os.environ["AI_MEMORY_ENQUEUE_CHECK"])
FAILS = []

def case(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'} {name}{(' :: ' + detail) if detail else ''}")
    if not ok:
        FAILS.append(name)

def scratch_dir(name):
    d = SCRATCH / name
    d.mkdir(parents=True, exist_ok=True)
    return d

def harvest(store, units, trace, identity, responses=None, extra_env=None):
    """`ai_memory.py harvest --enqueue` against a scratch store."""
    runtime = SCRATCH / "runtime"; runtime.mkdir(exist_ok=True)
    env = {"XDG_RUNTIME_DIR": str(runtime),
           "AI_MEMORY_HARVEST_DIR": str(store),
           "AI_MEMORY_ENQUEUE_CHECK": str(CHECK)}
    env.update(extra_env or {})
    data = responses if responses is not None else [dict(suite.result_data(), unresolved_units=units)]
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.dict(os.environ, env), \
         mock.patch.object(memory, "current_identity", return_value=identity), \
         mock.patch.object(memory, "resolve_trace", return_value=trace), \
         mock.patch.object(memory, "invoke_utility", suite.QueueInvoker(*data)):
        os.environ.pop("ENQUEUE_ROW_CHECK_DROP_KEYS", None)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = memory.main(["harvest", "--enqueue"])
    return rc, out.getvalue(), err.getvalue()

def rows(store):
    return sorted((store / "enqueue").glob("*.enqueue.json"))

def docs(store):
    return [json.loads(p.read_text(encoding="utf-8")) for p in rows(store)]

ident = memory.Identity("claude-code", suite.CLAUDE_ROOT_ID)

# ---------------------------------------------------------------- P1
# A CHANGED session re-harvested. The card proves the `unchanged` path enqueues
# nothing again; it never asks what a session that DID change does. dedupKey is
# harvest:<session>:<n> and n restarts at 1, so a mover folding on dedupKey meets
# two different eventIds claiming the same key. MEASURE it, do not assume it.
p1 = SCRATCH / "p1"
trace1 = suite.copied_trace(suite.fixture_trace(suite.CLAUDE_HOME, suite.CLAUDE_ROOT_ID), scratch_dir("t1"))
rc1, out1, err1 = harvest(p1, ["Unit one, first harvest.", "Unit two, first harvest."], trace1, ident)
first = {d["row"]["dedupKey"]: d["eventId"] for d in docs(p1)}
# make the session change: append a real turn to the trace, so the digest moves
trace2 = suite.copied_trace(suite.fixture_trace(suite.CLAUDE_HOME, suite.CLAUDE_ROOT_ID), scratch_dir("t2"))
lines = trace1.read_text(encoding="utf-8").splitlines()
extra = json.loads(lines[-1])
trace2.write_text("\n".join(lines + [json.dumps(extra)]) + "\n", encoding="utf-8")
rc2, out2, err2 = harvest(p1, ["Unit one, SECOND harvest."], trace2, ident)
after = docs(p1)
keys = [d["row"]["dedupKey"] for d in after]
dupes = sorted({k for k in keys if keys.count(k) > 1})
case("P1 changed re-harvest is accepted (rc 0, note updated)",
     rc1 == 0 and rc2 == 0 and "updated" in out2, f"rc1={rc1} rc2={rc2} out2={out2.strip()!r}")
case("P1 every row still validates after the second harvest",
     all(subprocess.run([sys.executable, str(CHECK), str(p)]).returncode == 0 for p in rows(p1)))
case("P1 MEASURED: dedupKeys duplicated across harvests of one session",
     True, f"rows={len(after)} keys={keys} duplicated={dupes}")
case("P1 every eventId is unique and names its own file",
     len({d['eventId'] for d in after}) == len(after)
     and all((p1/'enqueue'/f"{d['eventId']}.enqueue.json").is_file() for d in after))

# ---------------------------------------------------------------- P2
# A unit sentence that is not plain ASCII, carries a newline and a quote, and is
# long. payloadHash/briefHash are taken over canonical bytes with
# ensure_ascii=False; a row is written with separators=(",",":"). If any of that
# is wrong the row stops being JSON, or stops validating, or the hash is not a
# sha256:<hex>.
p2 = SCRATCH / "p2"
nasty = "Wire the ‘harvest’ hook — naïve \"quotes\", a\nnewline, 中文, and " + ("x" * 400)
trace3 = suite.copied_trace(suite.fixture_trace(suite.CLAUDE_HOME, suite.CLAUDE_ROOT_ID), scratch_dir("t3"))
rc3, _, err3 = harvest(p2, [nasty], trace3, ident)
d2 = docs(p2)
case("P2 a non-ASCII multi-line unit yields exactly one valid row",
     rc3 == 0 and len(d2) == 1
     and subprocess.run([sys.executable, str(CHECK), str(rows(p2)[0])]).returncode == 0,
     f"rc={rc3} rows={len(d2)} err={err3.strip()[:120]!r}")
if d2:
    r = d2[0]["row"]
    # MEASURED: the engine collapses interior whitespace in a unit sentence
    # before it renders the note, and the row carries the SAME sentence the note
    # carries — which is the invariant that matters, since a mover reading the
    # row and a human reading the note must not disagree. Every non-ASCII
    # codepoint survives; only the newline became a space.
    note = (p2 / f"{suite.CLAUDE_ROOT_ID}.md").read_text(encoding="utf-8")
    case("P2 the row's description is the note's sentence, non-ASCII intact",
         r["description"] == " ".join(nasty.split())
         and r["description"] in note
         and "中文" in r["description"] and "naïve" in r["description"],
         f"len={len(r['description'])} newline_collapsed={chr(10) not in r['description']}")
    case("P2 both hashes are sha256:<hex> over the canonical bytes",
         bool(re.match(r"^sha256:[0-9a-f]{64}$", r["payloadHash"]))
         and bool(re.match(r"^sha256:[0-9a-f]{64}$", r["briefHash"])))

# ---------------------------------------------------------------- P3
# A harvest whose distillation names NO unresolved units. The card only ever
# feeds two. Nothing should be written, and no empty enqueue/ should be left
# behind for a mover to trip over.
p3 = SCRATCH / "p3"
trace4 = suite.copied_trace(suite.fixture_trace(suite.CLAUDE_HOME, suite.CLAUDE_ROOT_ID), scratch_dir("t4"))
rc4, out4, err4 = harvest(p3, [], trace4, ident,
                          responses=[dict(suite.result_data(), unresolved_units=[])])
case("P3 zero unresolved units: rc 0, note written, no rows, no hook.log",
     rc4 == 0 and rows(p3) == [] and not (p3 / "hook.log").exists()
     and (p3 / f"{suite.CLAUDE_ROOT_ID}.md").is_file(),
     f"rc={rc4} err={err4.strip()[:120]!r}")

# ---------------------------------------------------------------- P4
# The store the verb cannot write. A SessionEnd hook meets this on a full disk
# or a store owned by another uid. The bar is a BOUNDED reason on stderr, never
# a traceback, and never a half-written row.
p4 = SCRATCH / "p4"
p4.mkdir()
trace5 = suite.copied_trace(suite.fixture_trace(suite.CLAUDE_HOME, suite.CLAUDE_ROOT_ID), scratch_dir("t5"))
os.chmod(p4, 0o500)
try:
    rc5, out5, err5 = harvest(p4, ["One unit into a read-only store."], trace5, ident)
finally:
    os.chmod(p4, 0o700)
case("P4 an unwritable harvest store fails bounded, with no traceback",
     rc5 != 0 and "Traceback" not in err5 and err5.strip() != "",
     f"rc={rc5} err={err5.strip()[:160]!r}")
case("P4 nothing was left behind in the unwritable store",
     list(p4.iterdir()) == [], f"left={[p.name for p in p4.iterdir()]}")

# ---------------------------------------------------------------- P5
# The validator's own file-name clause, which no test in the suite exercises:
# a row that is perfectly shaped but saved under a name that is not
# <eventId>.enqueue.json must be refused, because the daemon keys its events by
# file name. And a directory handed to the checker must not crash it.
p5 = SCRATCH / "p5"; p5.mkdir()
good = memory.enqueue_row_document(
    identity=ident, unit="A well-formed row saved under a lying name.", ordinal=1,
    event_id="55555555-5555-4555-8555-555555555555",
    row_uuid="22222222-2222-4222-8222-222222222222")
right = p5 / f"{good['eventId']}.enqueue.json"
right.write_text(json.dumps(good), encoding="utf-8")
wrong = p5 / "not-the-event-id.enqueue.json"
wrong.write_text(json.dumps(good), encoding="utf-8")
ok_run = subprocess.run([sys.executable, str(CHECK), str(right)], capture_output=True, text=True)
bad_run = subprocess.run([sys.executable, str(CHECK), str(wrong)], capture_output=True, text=True)
dir_run = subprocess.run([sys.executable, str(CHECK), str(p5)], capture_output=True, text=True)
trunc = p5 / "33333333-3333-4333-8333-333333333333.enqueue.json"
trunc.write_text(json.dumps(good)[:-20], encoding="utf-8")
cut_run = subprocess.run([sys.executable, str(CHECK), str(trunc)], capture_output=True, text=True)
case("P5 the right name passes and the lying name is refused rc 1",
     ok_run.returncode == 0 and bad_run.returncode == 1
     and "file name must be" in bad_run.stderr,
     f"ok={ok_run.returncode} bad={bad_run.returncode} {bad_run.stderr.strip()[:100]!r}")
case("P5 a directory and a truncated row are refused, not crashed",
     dir_run.returncode == 1 and cut_run.returncode == 1
     and "Traceback" not in dir_run.stderr and "Traceback" not in cut_run.stderr,
     f"dir={dir_run.returncode} truncated={cut_run.returncode}")

# ---------------------------------------------------------------- P6
# Every scratch store this probe wrote, held against the fence: not one path
# under ~/.local/state/tally/.
live = os.environ["MEM3_LIVE"]
written = [str(p) for store in (p1, p2, p3, p4, p5) for p in store.rglob("*")]
case("P6 D-E07: no path this probe wrote is under the live events dir",
     all(not p.startswith(live) for p in written) and all(p.startswith(str(SCRATCH)) for p in written),
     f"{len(written)} paths, all under {SCRATCH}")

print(f"\n{len(FAILS)} failing case(s)" + (f": {FAILS}" if FAILS else ""))
sys.exit(1 if FAILS else 0)
PY
RC=$?

AFTER="$(ls -1 "$LIVE" 2>/dev/null | wc -l)"
echo "D-E07 census of $LIVE: before=$BEFORE after=$AFTER"
[ "$BEFORE" = "$AFTER" ] || { echo "probe: the live events dir CHANGED during this run" >&2; RC=1; }
exit "$RC"
