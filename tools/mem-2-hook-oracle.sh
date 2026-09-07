#!/usr/bin/env bash
# tools/mem-2-hook-oracle.sh — MEM-2 SESSIONEND-HOOK, the DOMINANT oracle.
#
# UNIT: MEM-2 (dotfiles#339). CARD: /home/tom/sept7/plan/UNITS-2026-09-06.json.
# SPEC: MECHANISM-2026-09-07 §6b; DECISIONS D-E07, D-E13.
#
# WHAT IT ASSERTS, in the manifest's own words. A scratch CLAUDE_CONFIG_DIR
# carrying the RENDERED settings.json and the hook script, with the harvest
# store pointed at a scratch directory:
#
#   * `claude -p 'reply with the single word ok' --model haiku
#     --permission-mode bypassPermissions --output-format json` completes;
#   * afterwards EXACTLY ONE <session_id>.md exists in the scratch harvest dir,
#     it is the session that just ended, and its front matter says
#     `harvested_at` — the harvest store's own variant, never a journal note
#     (D-E13 (2));
#   * the scratch journal dir is EMPTY: a hook never writes the journal;
#   * the hook.log carries ONE line, and it names the session;
#   * `nix flake check --offline --no-build` is green.
#
# It also asserts the fence: nothing this run does may land in branch (a)'s
# ~/.local/state/tally/, and no note for this session may appear in the live
# rewrite store either. XDG_STATE_HOME is pointed at the scratch tree so even a
# hook that ignored AI_MEMORY_HARVEST_DIR could not reach the real one.
#
# COST. One `claude -p` turn on haiku, and one utility-model distillation of a
# twelve-line trace on the already-loaded local model. Nothing else is spent.
#
# CREDENTIALS. The scratch config dir gets the seat's `.credentials.json` as a
# SYMLINK. The oracle never opens it, never copies its bytes and never prints
# it; `claude` follows the link exactly as it would in the seat's own dir.
#
# HOW TO RUN IT.
#
#   bash tools/mem-2-hook-oracle.sh
#
# MEM2_SEAT_CONFIG_DIR names the config dir whose credential is borrowed
# (default: $CLAUDE_CONFIG_DIR, else ~/.claude). MEM2_KEEP=1 keeps the scratch
# tree for inspection.
#
# Exit: 0 every clause holds; 1 a clause failed (each failure is named on
# stdout); 2 usage, a missing tool, or a missing credential.

set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo" || exit 2

hook_src="$repo/home/dot_claude/hooks/ai-memory-harvest.sh"
settings_src="$repo/home/dot_claude/settings.json"
skill_src="$repo/home/dot_claude/skills/drain"
hook_test="$repo/tests/ai-memory-hook/harvest-hook-test.sh"

for path in "$hook_src" "$settings_src" "$skill_src/scripts/ai_memory.py" "$hook_test"; do
  if [ ! -e "$path" ]; then
    printf 'ERROR the oracle needs %s and it is not there\n' "$path"
    exit 2
  fi
done

for tool in claude python3 jq nix timeout; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'ERROR %s is not on PATH\n' "$tool"
    exit 2
  fi
done

seat_cfg=${MEM2_SEAT_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}
if [ ! -e "$seat_cfg/.credentials.json" ]; then
  printf 'ERROR no credential to borrow at %s/.credentials.json; set MEM2_SEAT_CONFIG_DIR\n' \
    "$seat_cfg"
  exit 2
fi

failures=0
fail() {
  printf 'FAIL %s\n' "$*"
  failures=$((failures + 1))
}
pass() { printf 'ok   %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. The hook's own contract tests. Offline, no model, no session: every branch
#    of the hook against a fake engine. A hook that fails these has no business
#    being handed a real session end.
# ---------------------------------------------------------------------------
printf '== the hook contract tests\n'
if ! bash "$hook_test"; then
  printf '\nFAIL mem-2-hook-oracle: the hook contract tests are red\n'
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. The scratch world.
# ---------------------------------------------------------------------------
work=$(mktemp -d "${TMPDIR:-/tmp}/mem-2-oracle.XXXXXX")
cleanup() {
  if [ "${MEM2_KEEP:-0}" = "1" ]; then
    printf '\n(scratch tree kept at %s)\n' "$work"
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

cfg="$work/cfg"
harvest="$work/harvest"
journal="$work/journal"
xdg_config="$work/xdg-config"
xdg_state="$work/xdg-state"
runtime="$work/runtime"
mkdir -p "$cfg/hooks" "$cfg/skills" "$harvest" "$journal" \
  "$xdg_config/ai-memory" "$xdg_state" "$runtime"
chmod 700 "$runtime"

# The hook script, as delivered.
cp "$hook_src" "$cfg/hooks/ai-memory-harvest.sh"

# The engine, found the way the hook finds it: under the config dir's own
# skills tree. This is THIS worktree's ai_memory.py, not the installed one.
ln -s "$skill_src" "$cfg/skills/drain"

# The credential, as a link. Never read here.
ln -s "$seat_cfg/.credentials.json" "$cfg/.credentials.json"

# A journal config pointing at the scratch journal dir, so "the journal stayed
# empty" is a statement about a real, configured, writable journal.
printf '{"schema":1,"journal_dir":"%s"}\n' "$journal" \
  >"$xdg_config/ai-memory/config.json"

# The RENDERED settings.json: the repository's own file with the MEM-2 hook path
# resolved to the scratch copy. Nothing else is rewritten. The SessionStart
# block is left byte-identical -- it is this unit's non-goal, and it fails here
# exactly as it fails on the live box, where ~/.claude/hooks/herdr-agent-state.sh
# is absent (MEASURED 2026-09-07). A SessionStart hook that cannot run does not
# stop a session.
#
# A settings.json carrying NO SessionEnd block is rendered anyway, verbatim.
# That is the mutation hint's case, and the mutation must be observed the way it
# is written -- "no harvest file after the session ends" -- not short-circuited
# into a usage error before the session has even run.
python3 - "$settings_src" "$cfg/settings.json" "$cfg/hooks/ai-memory-harvest.sh" <<'PYEOF'
import json
import sys

source, target, hook = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(source, encoding="utf-8").read()
rendered = raw.replace("/home/tom/.claude/hooks/ai-memory-harvest.sh", hook)
json.loads(rendered)
open(target, "w", encoding="utf-8").write(rendered)
if rendered == raw:
    print(
        "note: settings.json names no ai-memory-harvest.sh hook; rendered verbatim",
        file=sys.stderr,
    )
PYEOF
if [ $? -ne 0 ]; then
  printf 'ERROR the repository settings.json could not be rendered as JSON\n'
  exit 2
fi

if python3 -c '
import json, sys
settings = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if "SessionEnd" in settings.get("hooks", {}) else 1)
' "$cfg/settings.json"; then
  printf 'rendered settings.json carries a SessionEnd block\n'
else
  printf 'rendered settings.json carries NO SessionEnd block\n'
fi

printf '\n== the scratch session\n'
printf 'config dir  %s\n' "$cfg"
printf 'harvest dir %s\n' "$harvest"
printf 'journal dir %s\n' "$journal"

# The live stores, as they stand before the run: the fence is asserted against
# these, not against an assumption that they are absent.
live_state="${XDG_STATE_HOME:-$HOME/.local/state}"
live_harvest="$live_state/tally-rewrite/harvest"

# ---------------------------------------------------------------------------
# 2. The session. Every identity variable this shell carries is scrubbed: the
#    scratch session is a ROOT session and must not inherit the identity, the
#    child-session flag or the messaging bus of whatever launched the oracle.
# ---------------------------------------------------------------------------
out="$work/claude-out.json"
err="$work/claude-err.txt"
start=$(date +%s)
env \
  -u CLAUDE_CODE_CHILD_SESSION \
  -u CLAUDE_CODE_SESSION_ID \
  -u CLAUDE_SESSION_ID \
  -u CODEX_THREAD_ID \
  -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT \
  -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN \
  -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_PID \
  -u CLAUDE_EFFORT \
  -u AI_MEMORY_ENGINE \
  CLAUDE_CONFIG_DIR="$cfg" \
  AI_MEMORY_HARVEST_DIR="$harvest" \
  XDG_CONFIG_HOME="$xdg_config" \
  XDG_STATE_HOME="$xdg_state" \
  XDG_RUNTIME_DIR="$runtime" \
  timeout 900 claude -p 'reply with the single word ok' \
  --model haiku --permission-mode bypassPermissions --output-format json \
  </dev/null >"$out" 2>"$err"
claude_rc=$?
elapsed=$(( $(date +%s) - start ))
printf 'claude -p rc=%s wall=%ss\n' "$claude_rc" "$elapsed"

if [ "$claude_rc" -ne 0 ]; then
  fail "claude -p did not complete (rc=$claude_rc); stderr: $(head -c 400 "$err")"
  printf '\nFAIL mem-2-hook-oracle: %d clause(s) failed\n' "$failures"
  exit 1
fi

session_id=$(jq -r '.session_id // empty' "$out" 2>/dev/null)
if [ -z "$session_id" ]; then
  fail "claude -p emitted no session_id in --output-format json"
  printf '\nFAIL mem-2-hook-oracle: %d clause(s) failed\n' "$failures"
  exit 1
fi
pass "claude -p completed and reported session $session_id"

# ---------------------------------------------------------------------------
# 3. The clauses.
# ---------------------------------------------------------------------------
printf '\n== the clauses\n'

notes=()
while IFS= read -r note; do
  notes+=("$note")
done < <(find "$harvest" -maxdepth 1 -name '*.md' -type f | sort)

if [ "${#notes[@]}" -ne 1 ]; then
  fail "expected exactly one .md in $harvest, found ${#notes[@]}: ${notes[*]:-none}"
else
  note=${notes[0]}
  if [ "$(basename "$note")" != "$session_id.md" ]; then
    fail "the note is $(basename "$note"), not $session_id.md"
  else
    pass "exactly one harvest note, and it is $session_id.md"
  fi
  if ! grep -q "^session_id: \"$session_id\"$" "$note"; then
    fail "the note's front matter does not name session $session_id"
  elif ! grep -q '^harvested_at: ' "$note"; then
    fail "the note says no harvested_at: it is not a harvest-store note (D-E13 (2))"
  elif grep -q '^drained_at: ' "$note"; then
    fail "the note says drained_at: the hook produced a journal note"
  elif ! grep -q '^source: "claude-code"$' "$note"; then
    fail "the note's source is not claude-code"
  else
    pass "the note is the harvest store's own variant (harvested_at, no drained_at)"
  fi
fi

journal_entries=$(find "$journal" -mindepth 1 | wc -l)
if [ "$journal_entries" -ne 0 ]; then
  fail "the scratch journal dir is not empty ($journal_entries entries); a hook never writes the journal"
else
  pass "the scratch journal dir is empty"
fi

hook_log="$harvest/hook.log"
if [ ! -f "$hook_log" ]; then
  fail "no hook.log in $harvest"
else
  log_lines=$(wc -l <"$hook_log")
  if [ "$log_lines" -ne 1 ]; then
    fail "hook.log carries $log_lines lines, expected exactly 1: $(tr '\n' '|' <"$hook_log")"
  elif ! grep -q "session=$session_id" "$hook_log"; then
    fail "the hook.log line does not name the session: $(cat "$hook_log")"
  elif ! grep -qE ' status=(created|updated) ' "$hook_log"; then
    fail "the hook.log line does not report a written note: $(cat "$hook_log")"
  else
    pass "hook.log carries one line naming the session: $(cat "$hook_log")"
  fi
fi

# The fence. Nothing under branch (a)'s live state dir, and no note for this
# session in the live rewrite store either.
if [ -e "$xdg_state/tally" ]; then
  fail "the run created $xdg_state/tally; branch (a)'s state dir is fenced"
elif [ -e "$live_harvest/$session_id.md" ]; then
  fail "a note for this session landed in the live store at $live_harvest"
else
  pass "nothing reached the live state dirs"
fi

printf '\n== nix flake check --offline --no-build\n'
if ! nix flake check --offline --no-build 2>&1 | tail -3; then
  fail "nix flake check --offline --no-build is not green"
else
  pass "nix flake check --offline --no-build is green"
fi

if [ "$failures" -ne 0 ]; then
  printf '\nFAIL mem-2-hook-oracle: %d clause(s) failed\n' "$failures"
  exit 1
fi
printf '\nPASS mem-2-hook-oracle: session %s ended and one harvest note exists\n' "$session_id"
