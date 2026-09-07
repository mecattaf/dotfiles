#!/usr/bin/env bash
# tests/ai-memory-hook/harvest-hook-test.sh — the SessionEnd hook's own tests.
#
# UNIT: MEM-2 (dotfiles#339). SUBJECT:
# home/dot_claude/hooks/ai-memory-harvest.sh.
#
# These are the hook's CONTRACT tests and they never spend the utility model: a
# fake engine stands in for ai_memory.py so every branch — created, unchanged,
# refusal, timeout, crash, no payload, subagent transcript — is reachable in
# milliseconds and offline. The end-to-end proof that the real engine, a real
# `claude` session and a real model produce a real harvest note is the unit's
# DOMINANT oracle, `tools/mem-2-hook-oracle.sh`; it is not this file's job.
#
# What every case asserts, without exception: the hook exits 0, and it appends
# exactly one line to <harvest dir>/hook.log naming the session.
#
# Usage: bash tests/ai-memory-hook/harvest-hook-test.sh
# Exit: 0 every case passed; 1 a case failed (each failure is named on stdout).

set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
# MEM2_HOOK lets the flake check point at the store copy of the hook; from a
# checkout the default is the repository's own file and no caller sets it.
hook=${MEM2_HOOK:-$repo/home/dot_claude/hooks/ai-memory-harvest.sh}

if [ ! -f "$hook" ]; then
  printf 'FAIL the hook does not exist at %s\n' "$hook"
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/mem2-hook-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

failures=0
cases=0

fail() {
  printf 'FAIL %-28s %s\n' "$case_name" "$*"
  failures=$((failures + 1))
}

ok() { printf 'ok   %-28s %s\n' "$case_name" "$*"; }

# A fake ai_memory.py. FAKE_MODE selects the branch; FAKE_ENV_OUT records the
# environment the hook handed it, which is how the identity-export contract is
# asserted rather than assumed.
fake_engine="$work/fake_engine.py"
cat >"$fake_engine" <<'PYEOF'
import os
import sys
import time

record = os.environ.get("FAKE_ENV_OUT")
if record:
    with open(record, "w", encoding="utf-8") as handle:
        for key in (
            "CLAUDE_CODE_SESSION_ID",
            "CLAUDE_CONFIG_DIR",
            "AI_MEMORY_HARVEST_DIR",
            "CLAUDE_CODE_CHILD_SESSION",
            "CODEX_THREAD_ID",
        ):
            handle.write(f"{key}={os.environ.get(key, '<unset>')}\n")
        handle.write("ARGV=" + " ".join(sys.argv[1:]) + "\n")
        handle.write("CWD=" + os.getcwd() + "\n")

mode = os.environ.get("FAKE_MODE", "created")
note = os.path.join(
    os.environ.get("AI_MEMORY_HARVEST_DIR", "."),
    os.environ.get("CLAUDE_CODE_SESSION_ID", "unknown") + ".md",
)
if mode in ("created", "updated", "unchanged"):
    if mode != "unchanged":
        with open(note, "w", encoding="utf-8") as handle:
            handle.write("fake harvest note\n")
    print(f"{mode}: {note}")
    raise SystemExit(0)
if mode == "refusal":
    print(
        "ai-memory: drain is only available in a root Claude Code session",
        file=sys.stderr,
    )
    raise SystemExit(1)
if mode == "crash":
    print("Traceback (most recent call last):\nRuntimeError: boom", file=sys.stderr)
    raise SystemExit(3)
if mode == "hang":
    time.sleep(120)
    raise SystemExit(0)
raise SystemExit(9)
PYEOF

# One case: run the hook with a payload and a fake-engine mode, then hand the
# scratch harvest dir and the captured stdout back to the caller's assertions.
run_hook() {
  local payload=$1 mode=$2
  shift 2
  store="$work/store.$cases"
  envout="$work/env.$cases"
  mkdir -p "$store"
  printf '%s' "$payload" | env \
    AI_MEMORY_ENGINE="$fake_engine" \
    AI_MEMORY_HARVEST_DIR="$store" \
    AI_MEMORY_HARVEST_HOOK_TIMEOUT="${HOOK_TIMEOUT:-30}" \
    FAKE_MODE="$mode" \
    FAKE_ENV_OUT="$envout" \
    "$@" \
    bash "$hook" >"$work/stdout.$cases" 2>"$work/stderr.$cases"
  hook_rc=$?
  log="$store/hook.log"
}

expect_exit_zero() {
  if [ "$hook_rc" -ne 0 ]; then
    fail "exited $hook_rc; a SessionEnd hook must exit 0 on every path"
    return 1
  fi
  return 0
}

expect_one_log_line() {
  local want_session=$1
  if [ ! -f "$log" ]; then
    fail "no hook.log was written to $store"
    return 1
  fi
  local lines
  lines=$(wc -l <"$log")
  if [ "$lines" -ne 1 ]; then
    fail "hook.log carries $lines lines, expected exactly 1"
    return 1
  fi
  if ! grep -q "session=$want_session" "$log"; then
    fail "hook.log line does not name session $want_session: $(cat "$log")"
    return 1
  fi
  return 0
}

expect_status() {
  local want=$1
  if ! grep -q " status=$want " "$log"; then
    fail "hook.log line is not status=$want: $(cat "$log")"
    return 1
  fi
  return 0
}

sid_a=11111111-2222-3333-4444-555555555555
sid_b=66666666-7777-8888-9999-aaaaaaaaaaaa

# ---------------------------------------------------------------------------
case_name="created"
cases=$((cases + 1))
mkdir -p "$work/cfg/projects/-slug"
: >"$work/cfg/projects/-slug/$sid_a.jsonl"
payload=$(
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionEnd","reason":"other"}' \
    "$sid_a" "$work/cfg/projects/-slug/$sid_a.jsonl" "$work"
)
run_hook "$payload" created
if expect_exit_zero && expect_one_log_line "$sid_a" && expect_status created; then
  if [ ! -f "$store/$sid_a.md" ]; then
    fail "the engine's note is not in the store"
  elif ! grep -q "^CLAUDE_CODE_SESSION_ID=$sid_a$" "$envout"; then
    fail "the hook did not export CLAUDE_CODE_SESSION_ID from the payload"
  elif ! grep -q "^AI_MEMORY_HARVEST_DIR=$store$" "$envout"; then
    fail "the hook did not point the engine at the harvest store"
  elif ! grep -q "^CLAUDE_CODE_CHILD_SESSION=<unset>$" "$envout"; then
    fail "the hook left CLAUDE_CODE_CHILD_SESSION set; it must be cleared"
  elif ! grep -q "^ARGV=harvest$" "$envout"; then
    fail "the hook ran '$(sed -n 's/^ARGV=//p' "$envout")', not 'harvest'"
  else
    ok "note written, identity exported, verb is harvest"
  fi
fi

# ---------------------------------------------------------------------------
# CLAUDE_CONFIG_DIR is derived from the transcript path when the hook does not
# inherit one, so a `claude` started with an explicit config dir stays
# harvestable.
case_name="config dir from transcript"
cases=$((cases + 1))
run_hook "$payload" created env -u CLAUDE_CONFIG_DIR
if expect_exit_zero && expect_one_log_line "$sid_a"; then
  if ! grep -q "^CLAUDE_CONFIG_DIR=$work/cfg$" "$envout"; then
    fail "derived $(sed -n 's/^CLAUDE_CONFIG_DIR=//p' "$envout"), expected $work/cfg"
  else
    ok "derived $work/cfg from the transcript path"
  fi
fi

# ---------------------------------------------------------------------------
# A session already harvested is not paid for twice (D-E13 (5)).
case_name="unchanged"
cases=$((cases + 1))
run_hook "$payload" unchanged
if expect_exit_zero && expect_one_log_line "$sid_a" && expect_status unchanged; then
  ok "the short-circuit is logged as itself"
fi

# ---------------------------------------------------------------------------
# The engine's own refusal — the drain's root-session rule — is a logged skip,
# never a failure and never a non-zero exit.
case_name="engine refusal is a skip"
cases=$((cases + 1))
run_hook "$payload" refusal
if expect_exit_zero && expect_one_log_line "$sid_a" && expect_status skipped; then
  if ! grep -q "root Claude Code session" "$log"; then
    fail "the refusal's reason is not in the log line: $(cat "$log")"
  elif [ -f "$store/$sid_a.md" ]; then
    fail "a refused harvest still wrote a note"
  else
    ok "refusal surfaced as a skip with its reason"
  fi
fi

# ---------------------------------------------------------------------------
# A subagent transcript is refused by name, before python is started at all.
case_name="subagent transcript"
cases=$((cases + 1))
sub_payload=$(
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionEnd","reason":"other"}' \
    "$sid_b" "$work/cfg/projects/-slug/subagents/$sid_b.jsonl" "$work"
)
run_hook "$sub_payload" created
if expect_exit_zero && expect_one_log_line "$sid_b" && expect_status skipped; then
  if [ -f "$envout" ]; then
    fail "the engine was started for a subagent session"
  elif [ -f "$store/$sid_b.md" ]; then
    fail "a subagent session was harvested"
  else
    ok "child session refused without spending anything"
  fi
fi

# ---------------------------------------------------------------------------
# An engine that crashes is a logged failure and still a clean session end.
case_name="engine crash"
cases=$((cases + 1))
run_hook "$payload" crash
if expect_exit_zero && expect_one_log_line "$sid_a" && expect_status failed; then
  ok "a crashing engine cannot wedge the session end"
fi

# ---------------------------------------------------------------------------
# The hook's own timeout fires before settings.json's, so the log line is
# always reached. Two seconds against a 120 s sleep.
case_name="engine hang"
cases=$((cases + 1))
HOOK_TIMEOUT=2 run_hook "$payload" hang
unset HOOK_TIMEOUT
if expect_exit_zero && expect_one_log_line "$sid_a" && expect_status timeout; then
  ok "the harvest was cut off by the hook's own timeout"
fi

# ---------------------------------------------------------------------------
case_name="empty payload"
cases=$((cases + 1))
run_hook '' created
if expect_exit_zero; then
  if [ ! -f "$log" ]; then
    fail "no hook.log line for a payload-less invocation"
  elif ! grep -q " status=skipped " "$log"; then
    fail "an empty payload is not logged as a skip: $(cat "$log")"
  else
    ok "no session_id is a logged skip"
  fi
fi

# ---------------------------------------------------------------------------
case_name="malformed payload"
cases=$((cases + 1))
run_hook 'not json at all' created
if expect_exit_zero; then
  if [ ! -f "$log" ] || ! grep -q " status=skipped " "$log"; then
    fail "malformed JSON is not a logged skip"
  else
    ok "malformed JSON is a logged skip"
  fi
fi

# ---------------------------------------------------------------------------
# The hook must never reach the journal and never reach branch (a)'s live state
# dir. `harvest` being the only verb is asserted above from the engine's own
# ARGV; this is the static half — no executable line even names the other store.
# (The engine PATH legitimately contains `drain`: ai_memory.py ships inside the
# drain skill. The verb is what matters, and the verb is asserted from ARGV.)
case_name="never the journal"
cases=$((cases + 1))
if grep -nE 'journal|state/tally/|[^-]tally/' "$hook" \
  | grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null; then
  fail "an executable line names the journal or branch (a)'s ~/.local/state/tally/"
elif grep -nE 'ai_memory\.py" +drain|\$engine" +drain' "$hook" >/dev/null; then
  fail "an executable line runs the drain verb"
else
  ok "harvest is the only verb and the store is the only writable path"
fi

printf '\n%d case(s), %d failure(s)\n' "$cases" "$failures"
if [ "$failures" -ne 0 ]; then
  printf 'FAIL harvest-hook-test\n'
  exit 1
fi
printf 'PASS harvest-hook-test\n'
