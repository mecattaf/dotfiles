#!/usr/bin/env bash
# tools/mem-2-eval-probe.sh — MEM-2's MECHANICAL EVALUATOR's own probe (step 2b).
#
# Not the card's clauses — the floor beneath them. The DOMINANT oracle ends ONE
# scratch session and asserts ONE note, ONE log line, an empty journal and a
# fence. Nothing in it, and nothing in tests/ai-memory-hook/harvest-hook-test.sh
# (which drives a FAKE engine), ever puts a SECOND real session end through the
# same store, or fires a SessionEnd TWICE for the same session, or hands the
# hook a store it cannot write. Four hermetic cases, all against the delivered
# hook and the real ai_memory.py, in one scratch tree:
#
#   P1  two real root sessions ending into the SAME harvest store -> exactly two
#       notes, one per session, and the FIRST note's bytes are unchanged by the
#       second session. The store is per-session; nothing clobbers.
#   P2  the hook.log is a LEDGER: exactly one line per session end, two lines
#       after two ends, each naming its own session.
#   P3  D-E14 (2) end to end: session B is launched with
#       CLAUDE_CODE_CHILD_SESSION=1 in its environment — the state this seat's
#       own shell is in. A hook that trusted the variable would refuse a
#       perfectly good root session. Its note must exist all the same.
#   P4  a THIRD SessionEnd fired for session A (the payload replayed straight at
#       the hook) -> D-E13 (5)'s short-circuit under the hook: the log grows by
#       exactly one line, that line says `unchanged`, and NO second .md appears.
#   P5  the hook handed a harvest dir it cannot create -> still exits 0. A hook
#       that can exit non-zero is a hook that can wedge a session end, and the
#       unwritable store is the one path the offline suite never takes.
#
# Exit 0 all five hold; 1 a case failed; 2 usage/missing tool/missing credential.

set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo" || exit 2

hook_src="$repo/home/dot_claude/hooks/ai-memory-harvest.sh"
skill_src="$repo/home/dot_claude/skills/drain"
for p in "$hook_src" "$skill_src/scripts/ai_memory.py"; do
  [ -e "$p" ] || { printf 'ERROR missing %s\n' "$p"; exit 2; }
done
for t in claude python3 jq timeout; do
  command -v "$t" >/dev/null 2>&1 || { printf 'ERROR %s not on PATH\n' "$t"; exit 2; }
done
seat_cfg=${MEM2_SEAT_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}
[ -e "$seat_cfg/.credentials.json" ] || { printf 'ERROR no credential at %s\n' "$seat_cfg"; exit 2; }

failures=0
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures+1)); }
pass() { printf 'ok   %s\n' "$*"; }

work=$(mktemp -d "${TMPDIR:-/tmp}/mem-2-probe.XXXXXX")
trap '[ "${MEM2_KEEP:-0}" = 1 ] && printf "(kept %s)\n" "$work" || rm -rf "$work"' EXIT

cfg="$work/cfg"; harvest="$work/harvest"; journal="$work/journal"
xdgc="$work/xdg-config"; xdgs="$work/xdg-state"; runtime="$work/runtime"
mkdir -p "$cfg/hooks" "$cfg/skills" "$harvest" "$journal" "$xdgc/ai-memory" "$xdgs" "$runtime"
chmod 700 "$runtime"
cp "$hook_src" "$cfg/hooks/ai-memory-harvest.sh"
ln -s "$skill_src" "$cfg/skills/drain"
ln -s "$seat_cfg/.credentials.json" "$cfg/.credentials.json"
printf '{"schema":1,"journal_dir":"%s"}\n' "$journal" >"$xdgc/ai-memory/config.json"
python3 - "$repo/home/dot_claude/settings.json" "$cfg/settings.json" "$cfg/hooks/ai-memory-harvest.sh" <<'PY'
import json,sys
src,dst,hook=sys.argv[1],sys.argv[2],sys.argv[3]
raw=open(src,encoding="utf-8").read()
r=raw.replace("/home/tom/.claude/hooks/ai-memory-harvest.sh",hook)
json.loads(r); open(dst,"w",encoding="utf-8").write(r)
PY
[ $? -eq 0 ] || { printf 'ERROR could not render settings.json\n'; exit 2; }

run_session() {  # $1 = out file, $2.. = extra env assignments
  local out=$1; shift
  env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID -u CODEX_THREAD_ID \
      -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_BRIDGE_SESSION_ID \
      -u CLAUDE_PID -u CLAUDE_EFFORT -u AI_MEMORY_ENGINE \
      -u CLAUDE_CODE_CHILD_SESSION \
      "$@" \
      CLAUDE_CONFIG_DIR="$cfg" AI_MEMORY_HARVEST_DIR="$harvest" \
      XDG_CONFIG_HOME="$xdgc" XDG_STATE_HOME="$xdgs" XDG_RUNTIME_DIR="$runtime" \
      timeout 900 claude -p 'reply with the single word ok' --model haiku \
      --permission-mode bypassPermissions --output-format json \
      </dev/null >"$out" 2>"$out.err"
}

printf '== session A (plain root session)\n'
run_session "$work/a.json"; rc_a=$?
sid_a=$(jq -r '.session_id // empty' "$work/a.json" 2>/dev/null)
printf 'A rc=%s session=%s\n' "$rc_a" "${sid_a:-none}"
[ "$rc_a" -eq 0 ] && [ -n "$sid_a" ] || { fail "session A did not complete: $(head -c 300 "$work/a.json.err")"; printf '\nFAIL mem-2-eval-probe\n'; exit 1; }
sha_a_before=$(sha256sum "$harvest/$sid_a.md" 2>/dev/null | cut -d' ' -f1)
lines_after_a=$(wc -l <"$harvest/hook.log" 2>/dev/null || echo 0)

printf '\n== session B (CLAUDE_CODE_CHILD_SESSION=1 in its environment, D-E14 (2))\n'
run_session "$work/b.json" CLAUDE_CODE_CHILD_SESSION=1; rc_b=$?
sid_b=$(jq -r '.session_id // empty' "$work/b.json" 2>/dev/null)
printf 'B rc=%s session=%s\n' "$rc_b" "${sid_b:-none}"
[ "$rc_b" -eq 0 ] && [ -n "$sid_b" ] || { fail "session B did not complete: $(head -c 300 "$work/b.json.err")"; printf '\nFAIL mem-2-eval-probe\n'; exit 1; }

printf '\n== the cases\n'
mapfile -t notes < <(find "$harvest" -maxdepth 1 -name '*.md' -type f -printf '%f\n' | sort)
if [ "${#notes[@]}" -ne 2 ]; then
  fail "P1 expected two notes in the shared store, found ${#notes[@]}: ${notes[*]:-none}"
elif ! [ -f "$harvest/$sid_a.md" ] || ! [ -f "$harvest/$sid_b.md" ]; then
  fail "P1 the two notes are not $sid_a.md and $sid_b.md: ${notes[*]}"
else
  sha_a_after=$(sha256sum "$harvest/$sid_a.md" | cut -d' ' -f1)
  if [ "$sha_a_before" != "$sha_a_after" ]; then
    fail "P1 session B rewrote session A's note ($sha_a_before -> $sha_a_after)"
  else
    pass "P1 two sessions, two notes, A's bytes untouched by B"
  fi
fi

lines=$(wc -l <"$harvest/hook.log")
if [ "$lines" -ne 2 ]; then
  fail "P2 hook.log carries $lines lines after two session ends, expected 2: $(tr '\n' '|' <"$harvest/hook.log")"
elif ! grep -q "session=$sid_a" "$harvest/hook.log" || ! grep -q "session=$sid_b" "$harvest/hook.log"; then
  fail "P2 hook.log does not name both sessions: $(tr '\n' '|' <"$harvest/hook.log")"
else
  pass "P2 hook.log is a ledger: one line per session end, each naming its own session ($lines_after_a -> $lines)"
fi

if [ ! -f "$harvest/$sid_b.md" ]; then
  fail "P3 session B, a ROOT session carrying CLAUDE_CODE_CHILD_SESSION=1, was refused"
elif ! grep -q "^harvested_at: " "$harvest/$sid_b.md"; then
  fail "P3 session B's note is not a harvest-store note"
else
  pass "P3 an inherited CLAUDE_CODE_CHILD_SESSION did not refuse a real root session"
fi

# P4 — replay session A's SessionEnd at the hook, exactly as Claude Code fires it.
slug=$(printf '%s' "$repo" | sed 's|/|-|g')
payload=$(python3 -c '
import json,sys
print(json.dumps({"session_id":sys.argv[1],"transcript_path":sys.argv[2],
                  "cwd":sys.argv[3],"hook_event_name":"SessionEnd","reason":"other"}))
' "$sid_a" "$cfg/projects/$slug/$sid_a.jsonl" "$repo")
printf '%s' "$payload" | env -u CLAUDE_CODE_CHILD_SESSION -u AI_MEMORY_ENGINE \
  CLAUDE_CONFIG_DIR="$cfg" AI_MEMORY_HARVEST_DIR="$harvest" \
  XDG_CONFIG_HOME="$xdgc" XDG_STATE_HOME="$xdgs" \
  bash "$cfg/hooks/ai-memory-harvest.sh"
replay_rc=$?
lines3=$(wc -l <"$harvest/hook.log")
notes3=$(find "$harvest" -maxdepth 1 -name '*.md' -type f | wc -l)
third=$(tail -1 "$harvest/hook.log")
if [ "$replay_rc" -ne 0 ]; then
  fail "P4 the replayed SessionEnd exited $replay_rc, not 0"
elif [ "$lines3" -ne 3 ]; then
  fail "P4 the log grew to $lines3 lines, expected 3"
elif [ "$notes3" -ne 2 ]; then
  fail "P4 the replay created a note: $notes3 .md files, expected 2"
elif ! printf '%s' "$third" | grep -q "session=$sid_a status=unchanged "; then
  fail "P4 the replayed end is not logged unchanged: $third"
else
  pass "P4 a second SessionEnd for one session is 'unchanged', one more line, no new note"
fi

# P5 — an unwritable store. The hook must still exit 0.
ro="$work/readonly"; mkdir -p "$ro"; chmod 500 "$ro"
printf '%s' "$payload" | env -u CLAUDE_CODE_CHILD_SESSION -u AI_MEMORY_ENGINE \
  CLAUDE_CONFIG_DIR="$cfg" AI_MEMORY_HARVEST_DIR="$ro/store" \
  XDG_CONFIG_HOME="$xdgc" XDG_STATE_HOME="$xdgs" \
  bash "$cfg/hooks/ai-memory-harvest.sh" >"$work/p5.out" 2>&1
ro_rc=$?
chmod 700 "$ro"
if [ "$ro_rc" -ne 0 ]; then
  fail "P5 an unwritable harvest store made the hook exit $ro_rc — it can wedge a session end"
elif [ -e "$ro/store" ]; then
  fail "P5 the hook wrote into a store it should not have been able to create"
else
  pass "P5 an unwritable store is survived: exit 0, nothing written"
fi

# the fence, once more, over everything the probe did.
if [ -e "$xdgs/tally" ]; then
  fail "FENCE the probe created $xdgs/tally"
else
  pass "FENCE nothing reached branch (a)'s state path"
fi

printf '\n-- hook.log --\n'; cat "$harvest/hook.log"
printf '\n-- %s.md front matter --\n' "$sid_a"; sed -n '1,12p' "$harvest/$sid_a.md" 2>/dev/null

if [ "$failures" -ne 0 ]; then
  printf '\nFAIL mem-2-eval-probe: %d case(s) failed\n' "$failures"; exit 1
fi
printf '\nPASS mem-2-eval-probe: 5 case(s), 0 failure(s)\n'
