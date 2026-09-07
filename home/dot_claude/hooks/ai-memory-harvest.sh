#!/usr/bin/env bash
# home/dot_claude/hooks/ai-memory-harvest.sh — SessionEnd -> the harvest verb.
#
# UNIT: MEM-2 (dotfiles#339). CARD: /home/tom/sept7/plan/UNITS-2026-09-06.json.
# SPEC: MECHANISM-2026-09-07 §6b ("harvest on close"); DECISIONS D-E07, D-E13.
# EXEMPLAR: the SessionStart block in home/dot_claude/settings.json, which is
# the only other hook this repository declares.
#
# WHAT CLAUDE CODE GIVES IT. The hook payload arrives on stdin as one JSON
# object — session_id, transcript_path, cwd, hook_event_name, reason — and the
# session process WAITS for this script before it exits (MEASURED 2026-09-07: a
# SessionEnd hook sleeping 15 s made `claude -p 'reply with the single word ok'`
# take 17 s wall). Three properties follow from that wait and none is optional:
#
#   * it exits 0 on every path, including the ones that failed. A hook that can
#     exit non-zero is a hook that can wedge a session end;
#   * every path that spends anything runs the harvest under `timeout`, and that
#     timeout is SMALLER than the hook timeout declared in settings.json, so the
#     script always ends by its own hand and always reaches its own last line;
#   * it appends exactly ONE line to <harvest dir>/hook.log naming the session,
#     whatever happened — created, updated, unchanged, skipped, failed, timeout.
#     One session end, one line: the log is a ledger, not a transcript.
#
# WHAT IT NEVER DOES. It never runs `drain` and it never reads or writes the
# journal — `harvest` is the only verb, and the harvest store is the only thing
# written (D-E13 (3): the store is AI_MEMORY_HARVEST_DIR, else
# $XDG_STATE_HOME/tally-rewrite/harvest, else ~/.local/state/tally-rewrite/
# harvest per D-E07; branch (a)'s live ~/.local/state/tally is never on any
# path here, and the string that would name it appears nowhere in this file at
# all -- the flake check asserts exactly that).
#
# WHAT IT ENQUEUES. With the harvest note on disk, the same run writes one
# validated enqueue row per unresolved unit of the distillation, under
# <harvest dir>/enqueue/<eventId>.enqueue.json — the verb's own `--enqueue`
# (FIX-E08, dotfiles#348). A harvest that changed nothing writes no rows, so a
# hook that fires twice does not enqueue the same units twice.
#
# It never runs on a child or subagent session: a transcript under a
# `subagents/` directory is refused here by name, and every other non-root
# session is refused by ai_memory.py's own root proof, surfaced as a logged skip.

set -u

started=$(date +%s)

# --------------------------------------------------------------------------
# The payload. `timeout` guards the read itself: a hook that blocks on a stdin
# that never closes has wedged the session end before it has done anything.
# --------------------------------------------------------------------------
payload=$(timeout 5 cat 2>/dev/null || true)

fields=$(
  printf '%s' "$payload" | python3 -c '
import json, sys

try:
    payload = json.loads(sys.stdin.read() or "{}")
except Exception:
    payload = {}
if not isinstance(payload, dict):
    payload = {}
for key in ("session_id", "transcript_path", "cwd"):
    value = payload.get(key)
    print(str(value).replace("\n", " ").strip() if isinstance(value, str) else "")
' 2>/dev/null || true
)

session_id=$(printf '%s\n' "$fields" | sed -n '1p')
transcript_path=$(printf '%s\n' "$fields" | sed -n '2p')
session_cwd=$(printf '%s\n' "$fields" | sed -n '3p')

# --------------------------------------------------------------------------
# The store, which is also where this script's own log lives: one override
# moves both, so a test never has to point them apart (D-E13 (3)).
# --------------------------------------------------------------------------
harvest_dir=${AI_MEMORY_HARVEST_DIR:-}
if [ -z "$harvest_dir" ]; then
  harvest_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tally-rewrite/harvest"
fi
mkdir -p "$harvest_dir" 2>/dev/null || true
hook_log="$harvest_dir/hook.log"

# One line, one session end. `detail` is collapsed to a single line because a
# multi-line log entry would make "the log carries one line per session" false.
log_line() {
  status=$1
  detail=$(printf '%s' "${2:-}" | tr '\n\t' '  ' | tr -s ' ' | cut -c1-400)
  elapsed=$(( $(date +%s) - started ))
  printf '%s session=%s status=%s elapsed=%ss %s\n' \
    "$(date -Is)" "${session_id:-unknown}" "$status" "$elapsed" "$detail" \
    >>"$hook_log" 2>/dev/null || true
}

if [ -z "$session_id" ]; then
  log_line skipped "the SessionEnd payload carried no session_id"
  exit 0
fi

case "/$transcript_path/" in
  */subagents/*)
    log_line skipped "child session: transcript is under a subagents directory"
    exit 0
    ;;
esac

# --------------------------------------------------------------------------
# Where the session's own traces are. The hook inherits CLAUDE_CONFIG_DIR from
# the session that is ending; when it does not, the transcript path names the
# same directory three levels up (<config>/projects/<slug>/<id>.jsonl), which
# keeps a `claude` launched with an explicit config dir harvestable.
# --------------------------------------------------------------------------
config_dir=${CLAUDE_CONFIG_DIR:-}
if [ -z "$config_dir" ] && [ -n "$transcript_path" ]; then
  candidate=$(dirname "$(dirname "$(dirname "$transcript_path")")")
  if [ -d "$candidate/projects" ]; then
    config_dir=$candidate
  fi
fi
[ -n "$config_dir" ] || config_dir="$HOME/.claude"

engine=${AI_MEMORY_ENGINE:-}
if [ -z "$engine" ] || [ ! -f "$engine" ]; then
  engine=""
  for candidate in \
    "$config_dir/skills/drain/scripts/ai_memory.py" \
    "$HOME/.agents/skills/drain/scripts/ai_memory.py" \
    "$HOME/.claude/skills/drain/scripts/ai_memory.py"; do
    if [ -f "$candidate" ]; then
      engine=$candidate
      break
    fi
  done
fi

if [ -z "$engine" ]; then
  log_line skipped "no ai_memory.py engine found from $config_dir"
  exit 0
fi

# --------------------------------------------------------------------------
# The harvest. Its own timeout is the one that fires: settings.json declares a
# larger hook timeout, so Claude Code never has to kill this script, and the log
# line below is always written.
#
# CLAUDE_CODE_CHILD_SESSION is CLEARED rather than trusted. Claude Code sets it
# on subprocesses of a tool call, so any session started from inside another
# session's Bash tool inherits it — and every hook of that session would then
# refuse a perfectly good root session (MEASURED 2026-09-07). The proof of
# rootness that matters is structural and ai_memory.py already makes it: the
# trace must carry a non-sidechain user/assistant record under this session_id,
# and traces under `subagents/` are excluded by name. That proof stands whatever
# the environment says, and a session that fails it is refused below.
# --------------------------------------------------------------------------
harvest_timeout=${AI_MEMORY_HARVEST_HOOK_TIMEOUT:-420}

# The enqueue leg (FIX-E08). `harvest` alone wrote the note and stopped there,
# so the close -> row -> floor leg was unwired: nothing scheduled or hooked ever
# called the verb's own `--enqueue`. It is passed here by default, and the rows
# land under <harvest dir>/enqueue/ — inside the store this script already owns,
# never beside it and never in branch (a)'s. AI_MEMORY_HARVEST_ENQUEUE=0 is the
# one opt-out (a host whose validator is missing, say); it changes what the verb
# writes, never whether this script exits 0 or logs its one line.
harvest_argv=(harvest)
if [ "${AI_MEMORY_HARVEST_ENQUEUE:-1}" != "0" ]; then
  harvest_argv+=(--enqueue)
fi

if [ -n "$session_cwd" ] && [ -d "$session_cwd" ]; then
  cd "$session_cwd" 2>/dev/null || cd "$HOME" 2>/dev/null || true
else
  cd "$HOME" 2>/dev/null || true
fi

# errexit is never on in this script; rc is captured and every branch below
# ends in `exit 0`.
output=$(
  env \
    -u CLAUDE_CODE_CHILD_SESSION \
    -u CLAUDE_SESSION_ID \
    -u CODEX_THREAD_ID \
    CLAUDE_CODE_SESSION_ID="$session_id" \
    CLAUDE_CONFIG_DIR="$config_dir" \
    AI_MEMORY_HARVEST_DIR="$harvest_dir" \
    timeout -k 5 "$harvest_timeout" python3 "$engine" "${harvest_argv[@]}" 2>&1
)
rc=$?

case "$rc" in
  0)
    # ai_memory.py prints "created: <path>", "updated: <path>" or
    # "unchanged: <path>"; the word before the colon IS the status.
    status=${output%%:*}
    case "$status" in
      created | updated | unchanged) ;;
      *) status=harvested ;;
    esac
    log_line "$status" "$output"
    ;;
  124 | 137)
    log_line timeout "the harvest did not finish within ${harvest_timeout}s"
    ;;
  1)
    # ai_memory.py's own refusals — a non-root session, an unresolvable trace,
    # no utility model on this host — all exit 1 with `ai-memory: <reason>`.
    log_line skipped "$output"
    ;;
  *)
    log_line failed "exit $rc: $output"
    ;;
esac

exit 0
