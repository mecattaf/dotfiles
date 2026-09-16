# cubs-iteration — ONE bounded Halogen coding iteration on the CUBS tree, run
# as the argv of a `build:CUBS-<n>` kit entry under a tally-kernel lease.
#
# Campaign: cubs-halogen-probe-1 (FRONT-12 bootstrap). Brief:
# ~/mecattaf/cubs-campaign/README.md. Doc: docs/local-ai/cubs-campaign.md.
# Lineage: pkgs/academic-ocr-drain/drain.sh (flock, receipt as the done
# marker, wait-with-deadline exit 69, transient drops never fed to the fuse,
# 3-consecutive-failure fuse exit 2) and pkgs/local-ai-monthly/lib/judge.sh
# (a campaign-private PI_CODING_AGENT_DIR).
#
# THE CHILD'S ENVIRONMENT IS EMPTY. The kernel's exec.run spawns this argv
# with env_clear and an empty env_allowlist (tally
# crates/tally-kernel/src/exec.rs:681-689): the process sees
# TALLY_EXECUTION_ID and TALLY_USAGE_SOURCE_PATH and nothing else — no HOME,
# and PATH is whatever /bin/sh left (MEASURED `env -i /bin/sh -c 'echo $PATH'`
# -> /no-such-path). So HOME is derived from the passwd entry below, every
# tool is a store path from runtimeInputs, and the two profile bins are
# appended LAST, for `nix` in a task's validation_cmd (home/tally-filler.nix's
# reasoning: pinning a second nix into a lease script would be this
# repository deciding which nix another tree's oracle runs).
#
# STDIN is the kit entry's static `stdin` (lake apps/uplink/src/uplink.mjs:623
# `stdin: entry.stdin ?? ""`; the kernel writes it after its start marker,
# exec.rs:747). A store kit cannot carry a day's task JSON, so the entry hands
# over a POINTER — {"worklist": <jsonl>, "id": "CUBS-<n>"} — and this script
# resolves the task line from the worklist. A full task object on stdin (the
# worklist line itself, as `--dry` self-tests use it) is accepted too.
#
# THE RECEIPT is ~/mecattaf/cubs-campaign/tools/receipt.schema.json's shape
# (the campaign owns the schema; this script owns the bytes), plus
# `execution_id` and `exit_code`. `censored` is true exactly on an item a
# blown fuse retired before it started, so `jq` over the receipts counts the
# unrun items without guessing. Per-attempt detail lives beside it in
# attempts.json. `observed_failure_mode` stays null for the morning review;
# the executable's own mechanical reading of a failure is in `notes`.
#
# THE GUARD is the campaign's tools/spec-diff-guard.sh when the task came from
# a worklist and that script exists (it is the campaign's grader: allowed
# paths, frozen spec.md, `git diff --check`, setup copies identical to the
# upstream checkout are not changes); otherwise the built-in guard in
# cubs-helpers.py, which implements the same path rules. Only files inside
# allowed_paths + new_files are ever staged and committed.
#
# EXIT CODES (also under --help):
#    0  pass (validated, committed, receipted) — or an idempotent no-op on a
#       task whose receipt already says pass
#    1  fail (setup, guard or validation red after the one repair; receipt
#       "fail")
#  124  timeout: a Pi process hit its wall-clock budget (receipt "timeout";
#       not a fail, not fuse fodder; no repair is attempted on a timed-out
#       first attempt, the budget WAS the point)
#    2  fuse (third consecutive fail IN THIS TASK'S PACKAGE, or a fuse that
#       was already blown; receipt "fuse"). The counter is per package,
#       <state>/fuse.d/<package>: a blown package retires only its own
#       remaining items, which are receipted `censored: true` and never seen
#       by Pi. <state>/fuse is the MASTER fuse and stops every package
#       (`echo 3 > <state>/fuse`); this script only reads it. Reset by
#       removing the file.
#   64  usage
#   65  the stdin JSON or the worklist line is malformed
#   69  outage (Halogen not ok/idle within 20 min, or dropped mid-run;
#       receipt "outage"; NEVER counts toward the fuse)
#   75  another cubs-iteration holds the state lock
#   78  campaign material missing (campaign dir, system prompt, models.json,
#       bundle, repo) — no receipt, the task stays runnable
#  143  cancelled: SIGTERM/SIGINT (the lease's rail) — WIP committed, receipt
#       "cancelled", within the kernel's 30 s checkpoint grace

# ---------------------------------------------------------------- usage
usage() {
  cat <<'EOF'
usage: cubs-iteration [--dry] [--help]   < task-or-pointer.json

Reads ONE JSON object on stdin:
  pointer   {"worklist": "<path>.jsonl", "id": "CUBS-<n>"}   (the kit's form)
  task      {"id","package","title","repo","bundle_path","setup_cmd",
             "validation_cmd","allowed_paths":[...],"new_files":[...],
             "thinking","prior_p_pass","predicted_failure"}    (a worklist line)

  --dry     validate stdin, print the plan as JSON, run nothing, write nothing
  --help    this text

Environment (only for hand runs and the self-test; the kernel clears it):
  CUBS_CAMPAIGN_DIR  default ~/mecattaf/cubs-campaign
  CUBS_STATE_DIR     default ~/.local/state/cubs-campaign
  CUBS_AGENCY_ROOT   default ~/agency        (the CUBS repos live under it)
  CUBS_HALOGEN_URL   default http://worker:8731
  CUBS_PI_TIMEOUT    seconds for the first Pi process, default 1200
  CUBS_PI_REPAIR_TIMEOUT  seconds for the repair process, default 900
  CUBS_PI_BIN, CUBS_HEALTH_DEADLINE, CUBS_HEALTH_INTERVAL,
  CUBS_VALIDATION_TIMEOUT             the self-test's seams
  TALLY_USAGE_SOURCE_PATH  where the one usage line lands (the kernel sets it)

Exit codes: 0 pass | 1 fail | 2 fuse | 64 usage | 65 bad stdin | 69 outage |
            75 lock held | 78 campaign material missing | 124 Pi timeout |
            143 cancelled

The fuse is per package: <state>/fuse.d/<package> counts consecutive failures
inside one work package and retires only that package at 3; every item it
retires gets a receipt with terminal_status "fuse", censored true and exit 2.
<state>/fuse is the master fuse (`echo 3 > <state>/fuse` stops every package);
this script only reads it. Remove a file to reset that fuse.
EOF
}

DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry) DRY=1 ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'cubs-iteration: unknown argument %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

# ---------------------------------------------------------------- environment
if [ -z "${HOME:-}" ]; then
  # The passwd entry, through the python3 this package carries (getent is
  # glibc's and not on the kernel's empty PATH).
  HOME="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  export HOME
fi
export PATH="$PATH:/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin"
export LANG="${LANG:-C.UTF-8}"

expand_home() {
  # A LITERAL tilde is what a worklist line or the kit's pointer carries
  # ("~/mecattaf/cubs-campaign/..."); this is the one place it is expanded.
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#"~/"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

CAMPAIGN_DIR="$(expand_home "${CUBS_CAMPAIGN_DIR:-$HOME/mecattaf/cubs-campaign}")"
STATE="$(expand_home "${CUBS_STATE_DIR:-$HOME/.local/state/cubs-campaign}")"
AGENCY_ROOT="$(expand_home "${CUBS_AGENCY_ROOT:-$HOME/agency}")"
HALOGEN="${CUBS_HALOGEN_URL:-http://worker:8731}"
PI_TIMEOUT="${CUBS_PI_TIMEOUT:-1200}"
PI_REPAIR_TIMEOUT="${CUBS_PI_REPAIR_TIMEOUT:-900}"
# The self-test's seams (tests/tally-uplink/probe-cubs-iteration.sh): a stub
# Pi and shorter clocks. Under the kernel none of these exist in the
# environment, so the defaults are the campaign's numbers.
PI_BIN="${CUBS_PI_BIN:-pi}"
HEALTH_INTERVAL="${CUBS_HEALTH_INTERVAL:-10}"
HEALTH_DEADLINE="${CUBS_HEALTH_DEADLINE:-1200}"
VALIDATION_TIMEOUT="${CUBS_VALIDATION_TIMEOUT:-600}"

PROVIDER="halogen"
MODEL_ROW="halogen-qwen3.8-flash-next"
BRANCH_PREFIX="campaign/cubs-halogen-probe-1"
CAMPAIGN_NAME="cubs-halogen-probe-1"
SYSTEM_PROMPT="$CAMPAIGN_DIR/skill/system-prompt.md"
PI_AGENT_DIR="$CAMPAIGN_DIR/pi"
CAMPAIGN_GUARD="$CAMPAIGN_DIR/tools/spec-diff-guard.sh"
DIFF_PROMPT_BYTES=24000
TRANSCRIPT_PROMPT_BYTES=8000
GIT_IDENTITY=(-c user.name=cubs-iteration -c user.email=cubs-iteration@localhost)

CUBS_HELPERS="${CUBS_HELPERS:?cubs-iteration: CUBS_HELPERS (the python helper) is not set}"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_s() { date +%s; }
log() { printf '%s cubs-iteration[%s] %s\n' "$(now_iso)" "${TASK_ID:-?}" "$*" >&2; }

# Paths in a worklist line are absolute, `~/…`, or relative to the campaign
# repository (the kit's cwd) — "bundles/CUBS-1.md" is the day-01 shape.
campaign_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    "~"*) expand_home "$1" ;;
    *) printf '%s/%s' "$CAMPAIGN_DIR" "$1" ;;
  esac
}

# ---------------------------------------------------------------- stdin -> task
input="$(cat)"
if ! printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1; then
  printf 'cubs-iteration: stdin is not one JSON object\n' >&2
  exit 65
fi

if printf '%s' "$input" | jq -e 'has("worklist")' >/dev/null; then
  worklist="$(campaign_path "$(printf '%s' "$input" | jq -r '.worklist')")"
  want_id="$(printf '%s' "$input" | jq -r '.id // empty')"
  if [ -z "$want_id" ]; then
    printf 'cubs-iteration: pointer carries no id\n' >&2
    exit 65
  fi
  if [ ! -r "$worklist" ]; then
    if [ "$DRY" = 1 ]; then
      task="$(jq -cn --arg id "$want_id" --arg wl "$worklist" '{id: $id, _unresolved_worklist: $wl}')"
    else
      printf 'cubs-iteration: worklist %s is not readable\n' "$worklist" >&2
      exit 78
    fi
  else
    task="$(jq -c --arg id "$want_id" 'select(type == "object" and .id == $id)' "$worklist" 2>/dev/null | head -n 1 || true)"
    if [ -z "$task" ]; then
      printf 'cubs-iteration: %s carries no line with id %s\n' "$worklist" "$want_id" >&2
      exit 65
    fi
  fi
  TASK_SOURCE="$worklist"
else
  task="$(printf '%s' "$input" | jq -c .)"
  TASK_SOURCE="stdin"
fi

task_str() { printf '%s' "$task" | jq -r --arg k "$1" '.[$k] // empty'; }

TASK_ID="$(task_str id)"
if ! printf '%s' "$TASK_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'; then
  printf 'cubs-iteration: task id %s is not a plain token\n' "${TASK_ID:-<empty>}" >&2
  exit 65
fi

# A pointer to a worklist that does not exist yet: --dry reports the plan it
# CAN compute and says the rest is unresolved.
if printf '%s' "$task" | jq -e 'has("_unresolved_worklist")' >/dev/null; then
  jq -n --argjson task "$task" --arg state "$STATE" --arg campaign "$CAMPAIGN_DIR" \
    --arg agency "$AGENCY_ROOT" --arg halogen "$HALOGEN" \
    '{dry: true, resolved: false,
      reason: ("worklist " + $task._unresolved_worklist + " is not readable; the task line cannot be resolved yet"),
      id: $task.id, state_dir: $state, campaign_dir: $campaign, agency_root: $agency, halogen: $halogen}'
  exit 0
fi

# Required fields, and the shape of each.
missing="$(printf '%s' "$task" | jq -r '
  [ (if (.package|type) != "string" then "package" else empty end),
    (if (.title|type) != "string" then "title" else empty end),
    (if (.repo|type) != "string" or (.repo|test("^[A-Za-z0-9._-]+$")|not) then "repo" else empty end),
    (if (.bundle_path|type) != "string" then "bundle_path" else empty end),
    (if has("setup_cmd") and ((.setup_cmd|type) != "string" and (.setup_cmd|type) != "null") then "setup_cmd" else empty end),
    (if (.validation_cmd|type) != "string" or .validation_cmd == "" then "validation_cmd" else empty end),
    (if (.allowed_paths|type) != "array" or (.allowed_paths|length) == 0 then "allowed_paths" else empty end),
    (if has("new_files") and (.new_files|type) != "array" then "new_files" else empty end),
    (if has("thinking") and ((.thinking|type) != "string" or (.thinking as $t | ["off","minimal","low","medium","high","xhigh","max"] | index($t)) == null) then "thinking" else empty end),
    (if has("prior_p_pass") and (.prior_p_pass|type) != "number" then "prior_p_pass" else empty end)
  ] | join(",")')"
if [ -n "$missing" ]; then
  printf 'cubs-iteration: task %s: missing or malformed field(s): %s\n' "$TASK_ID" "$missing" >&2
  exit 65
fi

PACKAGE="$(task_str package)"
TITLE="$(task_str title)"
REPO="$(task_str repo)"
BUNDLE="$(campaign_path "$(task_str bundle_path)")"
SETUP_CMD="$(printf '%s' "$task" | jq -r '.setup_cmd // empty')"
VALIDATION_CMD="$(task_str validation_cmd)"
THINKING="$(printf '%s' "$task" | jq -r '.thinking // "low"')"
ALLOWED_JSON="$(printf '%s' "$task" | jq -c '(.allowed_paths) + (.new_files // [])')"
NEW_FILES_N="$(printf '%s' "$task" | jq '.new_files // [] | length')"
PRIOR_P_PASS="$(printf '%s' "$task" | jq -c '.prior_p_pass // null')"
PREDICTED_FAILURE="$(printf '%s' "$task" | jq -c '.predicted_failure // null')"

TOOLS="read,bash,edit,grep,find,ls"
if [ "$NEW_FILES_N" -gt 0 ]; then TOOLS="$TOOLS,write"; fi

case "$TASK_ID" in
  CUBS-*) COMMIT_SUBJECT="$TASK_ID: $TITLE" ;;
  *) COMMIT_SUBJECT="CUBS-$TASK_ID: $TITLE" ;;
esac

REPO_DIR="$AGENCY_ROOT/$REPO"
WORKTREE="$STATE/worktrees/$TASK_ID"
BRANCH="$BRANCH_PREFIX/$TASK_ID"
TASK_DIR="$STATE/tasks/$TASK_ID"
RECEIPT="$TASK_DIR/receipt.json"
ATTEMPTS_FILE="$TASK_DIR/attempts.json"
SESSIONS="$STATE/sessions"
LOGS="$STATE/logs"
# THE FUSE IS KEYED BY PACKAGE (cubs-M02). Three consecutive failures inside
# one work package retire that package's remaining items and nothing else, so
# a bad WP1 cannot silence WP2, WP3 and WP7. <state>/fuse.d/<package> is the
# per-package counter this script increments and resets; <state>/fuse stays as
# the MASTER fuse, an operator file this script only ever READS, so the stop
# procedure `echo 3 > ~/.local/state/cubs-campaign/fuse` still halts every
# package (RETURN-CHECKLIST (g)).
FUSE="$STATE/fuse"
FUSE_DIR="$STATE/fuse.d"
FUSE_PKG="$FUSE_DIR/$(printf '%s' "${PACKAGE:-none}" | tr -c 'A-Za-z0-9._-' '_')"

pi_argv() {
  # $1 session id, $2 thinking. The prompt (last positional) is appended by
  # the caller, so this list is the FIXED part every receipt can quote.
  printf '%s\n' "$PI_BIN" -p --mode json --session-dir "$SESSIONS" --session-id "$1" \
    --provider "$PROVIDER" --model "$MODEL_ROW" --thinking "$2" \
    --no-extensions --no-skills --no-prompt-templates --no-context-files --no-approve \
    --tools "$TOOLS"
}

guard_kind() {
  if [ "$TASK_SOURCE" != stdin ] && [ -x "$CAMPAIGN_GUARD" ]; then
    printf 'campaign:%s' "$CAMPAIGN_GUARD"
  else
    printf 'builtin:cubs-helpers.py guard'
  fi
}

# ---------------------------------------------------------------- --dry
if [ "$DRY" = 1 ]; then
  receipt_status="absent"
  if [ -r "$RECEIPT" ]; then
    receipt_status="$(jq -r '.terminal_status // "unreadable"' "$RECEIPT" 2>/dev/null || echo unreadable)"
  fi
  fuse_count=0
  if [ -r "$FUSE_PKG" ]; then fuse_count="$(tr -dc 0-9 <"$FUSE_PKG")"; fi
  fuse_master_count=0
  if [ -r "$FUSE" ]; then fuse_master_count="$(tr -dc 0-9 <"$FUSE")"; fi
  argv_json="$(pi_argv "$TASK_ID-a1" "$THINKING" | jq -R . | jq -s '. + ["--system-prompt", "<contents of skill/system-prompt.md>", "--", "<contents of the bundle>"]')"
  jq -n --argjson task "$task" --arg source "$TASK_SOURCE" \
    --arg state "$STATE" --arg campaign "$CAMPAIGN_DIR" --arg halogen "$HALOGEN" \
    --arg repo_dir "$REPO_DIR" --arg worktree "$WORKTREE" --arg branch "$BRANCH" \
    --arg bundle "$BUNDLE" --arg sys "$SYSTEM_PROMPT" --arg agent_dir "$PI_AGENT_DIR" \
    --arg tools "$TOOLS" --arg subject "$COMMIT_SUBJECT" --argjson argv "$argv_json" \
    --arg receipt_status "$receipt_status" --argjson fuse "${fuse_count:-0}" \
    --argjson fuse_master "${fuse_master_count:-0}" --arg fuse_path "$FUSE_PKG" --arg fuse_master_path "$FUSE" \
    --argjson pi_timeout "$PI_TIMEOUT" --argjson h_int "$HEALTH_INTERVAL" --argjson h_dead "$HEALTH_DEADLINE" \
    --argjson v_timeout "$VALIDATION_TIMEOUT" --arg guard "$(guard_kind)" --arg setup "$SETUP_CMD" \
    --argjson repo_ok "$(git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 && echo true || echo false)" \
    --argjson bundle_ok "$([ -r "$BUNDLE" ] && echo true || echo false)" \
    --argjson sys_ok "$([ -r "$SYSTEM_PROMPT" ] && echo true || echo false)" \
    --argjson models_ok "$([ -r "$PI_AGENT_DIR/models.json" ] && echo true || echo false)" \
    --argjson settings_ok "$([ -r "$PI_AGENT_DIR/settings.json" ] && echo true || echo false)" \
    '{dry: true, resolved: true, task: $task, task_source: $source,
      plan: {
        repo_dir: $repo_dir, worktree: $worktree, branch: $branch,
        sessions: [($task.id + "-a1"), ($task.id + "-a2")],
        tools: $tools, thinking: ($task.thinking // "low"),
        pi_agent_dir: $agent_dir, system_prompt: $sys, bundle: $bundle,
        pi_argv: $argv, pi_timeout_seconds: $pi_timeout,
        setup_cmd: (if $setup == "" then null else $setup end),
        guard: $guard,
        validation_cmd: $task.validation_cmd, validation_timeout_seconds: $v_timeout,
        commit_subject: $subject, halogen: $halogen,
        health: {interval_seconds: $h_int, deadline_seconds: $h_dead, on_deadline: "exit 69, receipt outage"},
        repair: "one fresh Pi process (a2) fed bundle + diff + validation transcript, then fail closed",
        fuse: "3 consecutive fails IN THIS PACKAGE -> exit 2, receipt fuse, censored: true on every later item of the package; the master fuse stops every package"
      },
      preflight: {
        campaign_dir: $campaign, state_dir: $state,
        repo_present: $repo_ok, bundle_present: $bundle_ok,
        system_prompt_present: $sys_ok, models_json_present: $models_ok, settings_json_present: $settings_ok,
        receipt_status: $receipt_status,
        fuse_count: $fuse, fuse_path: $fuse_path,
        fuse_master_count: $fuse_master, fuse_master_path: $fuse_master_path
      }}'
  exit 0
fi

# ---------------------------------------------------------------- state, lock
mkdir -p "$STATE" "$STATE/worktrees" "$STATE/tasks" "$SESSIONS" "$LOGS" "$TASK_DIR" "$FUSE_DIR"
exec 9>"$STATE/lock"
if ! flock -w 60 9; then
  log "another cubs-iteration holds $STATE/lock"
  exit 75
fi

# Idempotent on a pass: the receipt is the done marker (drain.sh l.112).
if [ -r "$RECEIPT" ] && [ "$(jq -r '.terminal_status // ""' "$RECEIPT" 2>/dev/null)" = "pass" ]; then
  log "receipt already says pass; nothing to do"
  exit 0
fi

STARTED_AT="$(now_iso)"
STARTED_S="$(now_s)"
EXECUTION_ID="${TALLY_EXECUTION_ID:-}"
USAGE_PATH="${TALLY_USAGE_SOURCE_PATH:-}"

# Everything the receipt names, filled in as the run goes.
MODEL_ID=""
HEALTH_VERSION=""
CAMPAIGN_SHA=""
SKILL_DIGEST=""
BUNDLE_DIGEST=""
BASE_SHA=""
COMMIT_SHA=""
DIFF_SHA=""
REPAIR_COUNT=0
# true only on an item this run never started because a fuse was already
# blown: an UNRUN item, retired by the fuse rather than judged by Halogen.
CENSORED=false
ATTEMPTS_JSON="[]"
VALIDATION_JSON="null"
GUARD_JSON="null"
GUARD_EXIT="null"
NOTES=""
CHILD_PID=""
FINISHING=0
LAST_SESSION=""
LAST_EVENTS=""
LAST_PI_RC=0
LAST_TRANSCRIPT=""

fuse_read() {
  # $1 a counter file; absent or unreadable reads as 0.
  if [ -r "$1" ]; then tr -dc 0-9 <"$1"; else printf 0; fi
}
fuse_write() {
  # $1 the count, $2 the counter file.
  mkdir -p "$(dirname "$2")" && printf '%s\n' "$1" >"$2.tmp" && mv -f "$2.tmp" "$2"
}

digest_file() { printf 'sha256:%s' "$(sha256sum "$1" | cut -d' ' -f1)"; }

# The files the task may touch, as the worktree holds them now: changed
# tracked files plus untracked files (honouring .gitignore), filtered to
# allowed_paths + new_files. Setup copies and build products never enter it.
touched_files() {
  {
    git -C "$WORKTREE" diff --name-only HEAD 2>/dev/null
    git -C "$WORKTREE" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
}
# Untracked, non-ignored files outside allowed_paths + new_files at close:
# the guard fails on them; the receipt lists them so the review sees what
# the model tried to create.
stray_files() {
  # exactly ONE JSON array, always: the guard exits 1 on any violation (a stray,
  # or "empty diff" when nothing is untracked), which under pipefail made the
  # old `|| echo '[]'` append a second value and broke `jq --argjson stray`.
  local out
  out="$(git -C "$WORKTREE" ls-files --others --exclude-standard 2>/dev/null \
    | (cd "$WORKTREE" && python3 "$CUBS_HELPERS" guard "$REPO" "$ALLOWED_JSON" "$REPO_DIR") 2>/dev/null \
    | jq -c '.stray // []' 2>/dev/null)" || true
  printf '%s' "${out:-[]}"
}
allowed_files() {
  # from the worktree: the helper compares relative paths against upstream.
  touched_files | (cd "$WORKTREE" && python3 "$CUBS_HELPERS" guard "$REPO" "$ALLOWED_JSON" "$REPO_DIR") 2>/dev/null \
    | jq -r '.changed[]' 2>/dev/null || true
}
# The diff the receipt and the repair prompt read: HEAD vs the working tree,
# restricted to the allowed files, new files included.
worktree_diff() {
  local files
  files="$(allowed_files)"
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" | xargs -d '\n' git -C "$WORKTREE" add -N -- 2>/dev/null || true
  printf '%s\n' "$files" | xargs -d '\n' git -C "$WORKTREE" diff --no-color HEAD -- 2>/dev/null || true
}
# sha256 of the current allowed diff; empty when the diff is empty (the
# schema spells that null).
diff_now() {
  local d
  d="$(worktree_diff | sha256sum | cut -d' ' -f1)"
  [ "$d" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] && d=""
  printf '%s' "$d"
}
stage_allowed() {
  local files
  files="$(allowed_files)"
  [ -n "$files" ] || return 1
  printf '%s\n' "$files" | xargs -d '\n' git -C "$WORKTREE" add -- 2>/dev/null
  ! git -C "$WORKTREE" diff --cached --quiet
}

# ---------------------------------------------------------------- the receipt
# $1 terminal_status, $2 exit code (recorded, not applied). The shape is the
# campaign's tools/receipt.schema.json.
# An item a blown fuse censored never reached the preflight, so it has no
# campaign sha and no digests: those three are null, never the empty string
# the schema patterns reject (the probe validates a censored receipt).
write_receipt() {
  local status="$1" code="$2" finished wall diff_sha sessions
  finished="$(now_iso)"
  wall=$(( $(now_s) - STARTED_S ))
  # The diff the task produced: fixed by `diff_now` before a commit moves
  # HEAD; otherwise read live (a cancel, a fail, an outage mid-run).
  diff_sha="$DIFF_SHA"
  if [ -z "$diff_sha" ] && [ -n "$BASE_SHA" ] && [ -e "$WORKTREE/.git" ]; then
    diff_sha="$(diff_now)"
  fi
  sessions="$(printf '%s' "$ATTEMPTS_JSON" | jq -c '[.[].session]')"
  local stray='[]'
  if [ -n "$BASE_SHA" ] && [ -e "$WORKTREE/.git" ]; then stray="$(stray_files)"; fi
  printf '%s\n' "$ATTEMPTS_JSON" | jq . >"$ATTEMPTS_FILE.tmp" && mv -f "$ATTEMPTS_FILE.tmp" "$ATTEMPTS_FILE"
  local tmp="$RECEIPT.tmp"
  jq -n \
    --arg task "$TASK_ID" --arg package "$PACKAGE" --arg repo "$REPO" \
    --arg provider "$PROVIDER" --arg model "$MODEL_ID" --arg health_version "$HEALTH_VERSION" \
    --arg campaign_sha "$CAMPAIGN_SHA" --arg skill_digest "$SKILL_DIGEST" --arg bundle_digest "$BUNDLE_DIGEST" \
    --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg base_sha "$BASE_SHA" \
    --argjson attempts "$ATTEMPTS_JSON" --argjson sessions "$sessions" \
    --arg diff_sha "$diff_sha" --arg commit_sha "$COMMIT_SHA" \
    --argjson validation "$VALIDATION_JSON" --argjson guard_exit "$GUARD_EXIT" --arg cmd "$VALIDATION_CMD" \
    --argjson repair_count "$REPAIR_COUNT" \
    --arg status "$status" --argjson wall "$wall" --argjson censored "$CENSORED" \
    --argjson prior "$PRIOR_P_PASS" --argjson predicted "$PREDICTED_FAILURE" \
    --arg notes "$NOTES" \
    --arg execution_id "$EXECUTION_ID" --argjson stray "$stray" --arg attempts_path "$ATTEMPTS_FILE" \
    --arg started "$STARTED_AT" --arg finished "$finished" --argjson code "$code" \
    '{
      schema_version: 1,
      task: $task, package: $package,
      provider: $provider, model: $model,
      health_version: (if $health_version == "" then null else $health_version end),
      campaign_sha: (if $campaign_sha == "" then null else $campaign_sha end),
      skill_digest: (if $skill_digest == "" then null else $skill_digest end),
      bundle_digest: (if $bundle_digest == "" then null else $bundle_digest end),
      worktree_branch: $branch, worktree_path: $worktree, repo: $repo, base_sha: $base_sha,
      tool_calls: ([$attempts[].events.tool_calls // 0] | add // 0),
      is_error_count: ([$attempts[].events.tool_errors // 0] | add // 0),
      repeated_identical_calls: ([$attempts[].events.repeated_identical_calls // 0] | add // 0),
      tool_call_names: ([$attempts[].events.tools_by_name // {}] | reduce .[] as $h ({}; . as $acc | $h | to_entries | reduce .[] as $e ($acc; .[$e.key] = ((.[$e.key] // 0) + $e.value)))),
      bash_call_count: ([$attempts[].events.tools_by_name.bash // 0] | add // 0),
      stray_files: $stray,
      reasoning_tokens: (if ([$attempts[].events.usage.reasoning_tokens | select(. != null)] | length) > 0
                         then ([$attempts[].events.usage.reasoning_tokens // 0] | add) else null end),
      attempts_path: $attempts_path,
      usage: {
        prompt_tokens: ([$attempts[].events.usage.prompt_tokens // 0] | add // 0),
        completion_tokens: ([$attempts[].events.usage.completion_tokens // 0] | add // 0),
        reasoning_tokens: (if ([$attempts[].events.usage.reasoning_tokens | select(. != null)] | length) > 0
                           then ([$attempts[].events.usage.reasoning_tokens // 0] | add) else null end),
        message_end_events: ([$attempts[].events.message_ends // 0] | add // 0)
      },
      diff_sha256: (if $diff_sha == "" then null else $diff_sha end),
      commit_sha: (if $commit_sha == "" then null else $commit_sha end),
      validation: (if $validation == null
                   then {cmd: $cmd, exit: null, transcript_digest: null, seconds: null, guard_exit: $guard_exit}
                   else ($validation + {guard_exit: $guard_exit}) end),
      repair_count: $repair_count,
      terminal_status: $status, wall_seconds: $wall, censored: $censored,
      prior_p_pass: $prior, predicted_failure: $predicted,
      observed_failure_mode: null,
      started_at: $started, finished_at: (if $status == "pending" then null else $finished end),
      sessions: $sessions,
      notes: $notes,
      execution_id: (if $execution_id == "" then null else $execution_id end),
      exit_code: $code
    }' >"$tmp" && mv -f "$tmp" "$RECEIPT"
  [ "$status" = pending ] && return 0
  jq -c . "$RECEIPT" >>"$STATE/ledger.jsonl" 2>/dev/null || true
  # The one usage line the kernel's witness_record points at (home/tally-
  # uplink.nix, the usage_source join): {task, model, usage, seconds} plus
  # the execution id, so the artifact names the execution back.
  if [ -n "$USAGE_PATH" ]; then
    mkdir -p "$(dirname "$USAGE_PATH")"
    jq -c --arg eid "$EXECUTION_ID" --arg status "$status" \
      '{kind: "halogen-usage/1", execution_id: $eid, task: .task, model: .model,
        usage: {prompt_tokens: .usage.prompt_tokens, completion_tokens: .usage.completion_tokens, reasoning_tokens: .usage.reasoning_tokens},
        seconds: .wall_seconds, terminal_status: $status}' "$RECEIPT" >>"$USAGE_PATH" || true
  fi
  log "receipt $status (exit $code) -> $RECEIPT"
}

finish() {
  # $1 terminal_status, $2 exit code
  FINISHING=1
  write_receipt "$1" "$2"
  exit "$2"
}

# ---------------------------------------------------------------- SIGTERM
# The lease's rail: SIGTERM, 30 s checkpoint grace, SIGKILL (tally
# docs/executor.md). Everything below finishes inside 25 s: the child gets 5 s
# to leave, the WIP commit and the receipt are milliseconds.
# shellcheck disable=SC2329  # invoked by the trap below
on_term() {
  trap '' TERM INT
  [ "$FINISHING" = 1 ] && exit 143
  FINISHING=1
  log "SIGTERM: cancelling under the lease"
  if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    local i=0
    while [ "$i" -lt 10 ] && kill -0 "$CHILD_PID" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
    kill -KILL "$CHILD_PID" 2>/dev/null || true
  fi
  if [ -n "$BASE_SHA" ] && [ -e "$WORKTREE/.git" ] && { DIFF_SHA="$(diff_now)"; stage_allowed; }; then
    if git -C "$WORKTREE" "${GIT_IDENTITY[@]}" commit -q -m "$COMMIT_SUBJECT [WIP, cancelled under lease]" >/dev/null 2>&1; then
      COMMIT_SHA="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || true)"
      # Kept reachable under a private ref namespace; the retry resets the
      # branch to its base with the WIP back in the working tree.
      git -C "$WORKTREE" update-ref "refs/cubs-wip/$TASK_ID/$(now_s)" "$COMMIT_SHA" 2>/dev/null || true
    fi
  fi
  NOTES="${NOTES:-cancelled under the lease (SIGTERM)}"
  write_receipt cancelled 143
  exit 143
}
trap on_term TERM INT

# ---------------------------------------------------------------- fuse gate
# The master fuse first (Tom's stop switch, any package), then this task's own
# package counter. Either one blown and the item never runs: no Pi, receipt
# "fuse", `censored: true`, exit 2. The item stays re-runnable once the
# counter is removed.
fuse_master="$(fuse_read "$FUSE")"
if [ "${fuse_master:-0}" -ge 3 ]; then
  CENSORED=true
  NOTES="fuse_blown_before_start (master fuse, consecutive_failures=$fuse_master; remove $FUSE to reset)"
  log "$NOTES"
  finish fuse 2
fi
fuse_now="$(fuse_read "$FUSE_PKG")"
if [ "${fuse_now:-0}" -ge 3 ]; then
  CENSORED=true
  NOTES="fuse_blown_before_start (package $PACKAGE, consecutive_failures=$fuse_now; remove $FUSE_PKG to reset)"
  log "$NOTES"
  finish fuse 2
fi

# ---------------------------------------------------------------- preflight
preflight_fail() { log "$*"; exit 78; }
[ -d "$CAMPAIGN_DIR" ] || preflight_fail "campaign dir $CAMPAIGN_DIR is missing"
[ -r "$SYSTEM_PROMPT" ] || preflight_fail "system prompt $SYSTEM_PROMPT is missing"
[ -r "$PI_AGENT_DIR/models.json" ] || preflight_fail "campaign-private $PI_AGENT_DIR/models.json is missing"
# settings.json carries compaction.reserveTokens / keepRecentTokens (pi
# docs/settings.md), which models.json cannot; both ship in the campaign repo.
[ -r "$PI_AGENT_DIR/settings.json" ] || preflight_fail "campaign-private $PI_AGENT_DIR/settings.json is missing"
[ -r "$BUNDLE" ] || preflight_fail "bundle $BUNDLE is missing"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || preflight_fail "$REPO_DIR is not a git repository"
if ! jq -e --arg p "$PROVIDER" --arg m "$MODEL_ROW" '.providers[$p].models | any(.id == $m)' \
  "$PI_AGENT_DIR/models.json" >/dev/null 2>&1; then
  preflight_fail "$PI_AGENT_DIR/models.json does not declare provider $PROVIDER with model $MODEL_ROW"
fi

CAMPAIGN_SHA="$(git -C "$CAMPAIGN_DIR" rev-parse HEAD 2>/dev/null || echo "0000000")"
SKILL_DIGEST="$(digest_file "$SYSTEM_PROMPT")"
BUNDLE_DIGEST="$(digest_file "$BUNDLE")"
write_receipt pending 0

# ---------------------------------------------------------------- halogen
health_ok() {
  curl -fsS --max-time 5 "$HALOGEN/health" 2>/dev/null \
    | jq -e '.status == "ok" and .busy == false and ((.engine.responds) // true)' >/dev/null 2>&1
}
health_reachable() {
  curl -fsS --max-time 5 "$HALOGEN/health" 2>/dev/null | jq -e '.status == "ok"' >/dev/null 2>&1
}
wait_for_halogen() {
  local deadline
  deadline=$(( $(now_s) + HEALTH_DEADLINE ))
  until health_ok; do
    if [ "$(now_s)" -ge "$deadline" ]; then
      return 1
    fi
    sleep "$HEALTH_INTERVAL"
  done
}
log "waiting for $HALOGEN/health status ok, busy false (up to ${HEALTH_DEADLINE}s)"
if ! wait_for_halogen; then
  NOTES="outage_before_start: $HALOGEN not ok/idle within ${HEALTH_DEADLINE}s"
  log "$NOTES"
  finish outage 69
fi
MODEL_ID="$(curl -fsS --max-time 5 "$HALOGEN/v1/models" 2>/dev/null | jq -r '.data[0].id // empty' || true)"
# /health.version is an object on Halogen ({api, engine, match}); the schema
# wants a string.
HEALTH_VERSION="$(curl -fsS --max-time 5 "$HALOGEN/health" 2>/dev/null \
  | jq -r '.version | if type == "object" then ("api " + (.api|tostring) + " engine " + (.engine|tostring)) elif . == null then "" else tostring end' 2>/dev/null || true)"
[ -n "$MODEL_ID" ] || MODEL_ID="$MODEL_ROW"
log "halogen ready: model $MODEL_ID version ${HEALTH_VERSION:-?}"

# ---------------------------------------------------------------- worktree
# From the repo's CURRENT HEAD, on the task's own branch. A retry (after an
# outage or a cancel) reuses the worktree: BASE_SHA is persisted at first
# creation, and a WIP commit the cancel left on the branch is moved back into
# the working tree (`reset --mixed` to the base) so HEAD is the base again and
# every diff, guard and commit reads from one point.
git -C "$REPO_DIR" worktree prune >/dev/null 2>&1 || true
if [ -f "$TASK_DIR/base_sha" ] && [ -d "$WORKTREE" ] && git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1; then
  BASE_SHA="$(cat "$TASK_DIR/base_sha")"
  if [ "$(git -C "$WORKTREE" rev-parse HEAD)" != "$BASE_SHA" ]; then
    git -C "$WORKTREE" update-ref "refs/cubs-wip/$TASK_ID/$(now_s)" HEAD 2>/dev/null || true
    git -C "$WORKTREE" reset -q --mixed "$BASE_SHA"
  fi
  log "reusing worktree $WORKTREE (base $BASE_SHA)"
else
  rm -rf "$WORKTREE"
  BASE_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"
  if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO_DIR" worktree add -q "$WORKTREE" "$BRANCH"
    git -C "$WORKTREE" reset -q --hard "$BASE_SHA"
  else
    git -C "$REPO_DIR" worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE_SHA"
  fi
  printf '%s\n' "$BASE_SHA" >"$TASK_DIR/base_sha"
  log "worktree $WORKTREE on $BRANCH from $BASE_SHA"
fi

# ---------------------------------------------------------------- setup
# The task's optional setup_cmd (e.g. WP2's linter copy), idempotent by the
# campaign's contract, run inside the worktree before every Pi process.
run_setup() {
  [ -n "$SETUP_CMD" ] || return 0
  local rc=0 transcript="$LOGS/$TASK_ID-setup.log"
  log "setup: $SETUP_CMD"
  (
    cd "$WORKTREE" || exit 78
    timeout --foreground --kill-after=10 "$VALIDATION_TIMEOUT" bash -c "$SETUP_CMD" </dev/null >>"$transcript" 2>&1
  ) &
  CHILD_PID=$!
  wait "$CHILD_PID" || rc=$?
  CHILD_PID=""
  return "$rc"
}

# ---------------------------------------------------------------- one Pi run
session_exists() {
  # pi names a session <timestamp>_<id>.jsonl under --session-dir; a plain
  # glob, because the store bash carries no `compgen` (MEASURED: "compgen:
  # command not found" under pkgs.bash 5.3).
  local f
  for f in "$SESSIONS"/*_"$1".jsonl; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# $1 attempt tag (a1|a2), $2 prompt file. Streams JSON events to
# logs/<id>-<tag>.jsonl. Leaves LAST_SESSION, LAST_EVENTS, LAST_PI_RC.
#
# STDIN IS /dev/null. `pi -p` reads a non-TTY stdin to EOF as part of the
# prompt (MEASURED in the campaign smoke): the task JSON arrived on THIS
# process's stdin and was read in full above, so Pi gets nothing. THE
# TIMEOUT is per attempt (20 min first, 15 min repair) with `-k 30`: a
# dropped Halogen connection leaves Pi's own auto-retry hanging
# indefinitely, and the lease's SIGKILL is not the rail this script should
# lean on.
run_pi() {
  local tag="$1" prompt_file="$2" sid rc budget="$PI_TIMEOUT"
  [ "$tag" = a2 ] && budget="$PI_REPAIR_TIMEOUT"
  sid="$TASK_ID-$tag"
  # ONE FRESH PROCESS: `--session-id` resumes a session that already exists in
  # --session-dir, so a retry rotates the id rather than silently continuing
  # yesterday's transcript.
  local n=1
  while session_exists "$sid"; do
    n=$((n + 1)); sid="$TASK_ID-$tag-r$n"
  done
  local out="$LOGS/$TASK_ID-$tag.jsonl" err="$LOGS/$TASK_ID-$tag.stderr"
  [ "$n" -gt 1 ] && { out="$LOGS/$TASK_ID-$tag-r$n.jsonl"; err="$LOGS/$TASK_ID-$tag-r$n.stderr"; }
  local -a argv
  mapfile -t argv < <(pi_argv "$sid" "$THINKING")
  log "pi $tag session $sid thinking $THINKING tools $TOOLS budget ${budget}s -> $out"
  (
    cd "$WORKTREE" || exit 78
    PI_CODING_AGENT_DIR="$PI_AGENT_DIR" PI_TELEMETRY=0 PI_OFFLINE=1 \
      timeout --foreground --kill-after=30 "$budget" \
      "${argv[@]}" --system-prompt "$(cat "$SYSTEM_PROMPT")" -- "$(cat "$prompt_file")" \
      <  /dev/null >"$out" 2>"$err"
  ) &
  CHILD_PID=$!
  wait "$CHILD_PID" && rc=0 || rc=$?
  CHILD_PID=""
  LAST_SESSION="$sid"; LAST_EVENTS="$out"; LAST_PI_RC="$rc"
  return 0
}

# ---------------------------------------------------------------- guard
# Sets GUARD_JSON and GUARD_EXIT; returns the guard's exit. Both guard kinds
# already read untracked files (ls-files --others / git status), and both
# are followed by the trailing-newline gate: `git diff --check` does not
# report a missing final newline, and a Flash-Next `edit` drops it often
# enough (campaign smoke) to be a gate rather than a note.
newline_violations() {
  local f
  while IFS= read -r f; do
    [ -s "$WORKTREE/$f" ] || continue
    if [ "$(tail -c 1 "$WORKTREE/$f" | od -An -c | tr -d ' ')" != '\n' ]; then
      printf '%s: no trailing newline\n' "$f"
    fi
  done < <(allowed_files)
}
run_guard() {
  local rc=0 out nl
  case "$(guard_kind)" in
    campaign:*)
      out="$(cd "$WORKTREE" && bash "$CAMPAIGN_GUARD" --task "$TASK_ID" --worklist "$TASK_SOURCE" --upstream "$REPO_DIR" 2>&1)" || rc=$?
      GUARD_JSON="$(jq -cn --arg out "$out" --argjson rc "$rc" --arg g "$CAMPAIGN_GUARD" \
        '{ok: ($rc == 0), guard: $g, exit: $rc, output: $out}')"
      ;;
    *)
      out="$(touched_files | (cd "$WORKTREE" && python3 "$CUBS_HELPERS" guard "$REPO" "$ALLOWED_JSON" "$REPO_DIR"))" || rc=$?
      GUARD_JSON="$(printf '%s' "$out" | jq -c --argjson rc "$rc" '. + {guard: "builtin", exit: $rc}' 2>/dev/null \
        || jq -cn --arg out "$out" --argjson rc "$rc" '{ok: false, guard: "builtin", exit: $rc, output: $out, violations: ["guard did not answer"]}')"
      ;;
  esac
  if [ "$rc" = 0 ]; then
    nl="$(newline_violations)"
    if [ -n "$nl" ]; then
      rc=1
      GUARD_JSON="$(printf '%s' "$GUARD_JSON" | jq -c --arg nl "$nl" '. + {ok: false, exit: 1, newline: ($nl | split("\n") | map(select(. != "")))}')"
    fi
  fi
  GUARD_EXIT="$rc"
  return "$rc"
}
guard_text() {
  printf '%s' "$GUARD_JSON" | jq -r '[(.output // (.violations // [] | join("; "))), ((.newline // []) | join("; "))] | map(select(. != "")) | join("; ") | if . == "" then "guard failed" else . end' 2>/dev/null
}

# ---------------------------------------------------------------- validation
# $1 attempt number. Runs task.validation_cmd inside the worktree under a 10
# minute timeout; transcript to logs/<id>-v<n>.log.
run_validation() {
  local n="$1" rc=0 t0 secs transcript
  transcript="$LOGS/$TASK_ID-v$n.log"
  t0="$(now_s)"
  log "validation $n: $VALIDATION_CMD"
  (
    cd "$WORKTREE" || exit 78
    timeout --foreground --kill-after=10 "$VALIDATION_TIMEOUT" bash -c "$VALIDATION_CMD" </dev/null >"$transcript" 2>&1
  ) &
  CHILD_PID=$!
  wait "$CHILD_PID" || rc=$?
  CHILD_PID=""
  secs=$(( $(now_s) - t0 ))
  VALIDATION_JSON="$(jq -cn --arg cmd "$VALIDATION_CMD" --argjson exit "$rc" \
    --arg digest "$(digest_file "$transcript")" --argjson seconds "$secs" --arg transcript "$transcript" \
    '{cmd: $cmd, exit: $exit, transcript_digest: $digest, seconds: $seconds, transcript_path: $transcript}')"
  LAST_TRANSCRIPT="$transcript"
  return "$rc"
}

record_attempt() {
  # $1 tag
  local events
  events="$(python3 "$CUBS_HELPERS" events "$LAST_EVENTS" 2>/dev/null || echo '{}')"
  ATTEMPTS_JSON="$(jq -cn --argjson prev "$ATTEMPTS_JSON" --arg tag "$1" --arg session "$LAST_SESSION" \
    --argjson pi_exit "$LAST_PI_RC" --arg log "$LAST_EVENTS" --argjson events "$events" \
    --argjson guard "$GUARD_JSON" --argjson validation "$VALIDATION_JSON" \
    '$prev + [{attempt: $tag, session: $session, pi_exit: $pi_exit, events_log: $log, events: $events, guard: $guard, validation: $validation}]')"
}

# A failed attempt with Halogen gone is an outage, never a fail (drain.sh's
# daemon-drop rule, #157): the receipt says outage and the fuse is untouched.
outage_if_halogen_gone() {
  if ! health_reachable; then
    NOTES="outage_mid_run: $HALOGEN unreachable after attempt"
    log "$NOTES"
    finish outage 69
  fi
}

# This task RAN and lost: its package counter moves, no other package's does,
# and the receipt is never `censored` (it was judged, not retired).
fail_or_fuse() {
  local consecutive
  consecutive=$(( $(fuse_read "$FUSE_PKG") + 1 ))
  fuse_write "$consecutive" "$FUSE_PKG"
  log "FAIL ($NOTES); consecutive failures in package $PACKAGE: $consecutive"
  if [ "$consecutive" -ge 3 ]; then
    NOTES="$NOTES; fuse blown for package $PACKAGE at $consecutive consecutive failures (remove $FUSE_PKG to reset; $FUSE is the master fuse for every package)"
    finish fuse 2
  fi
  finish fail 1
}

# ---------------------------------------------------------------- attempt 1
if ! run_setup; then
  NOTES="setup_failed: $SETUP_CMD (see $LOGS/$TASK_ID-setup.log)"
  fail_or_fuse
fi
run_pi a1 "$BUNDLE"
GUARD_JSON="null"; VALIDATION_JSON="null"
guard_ok=0; run_guard && guard_ok=1
val_ok=0
if [ "$guard_ok" = 1 ]; then
  run_validation 1 && val_ok=1
fi
record_attempt a1

# A Pi process that hit its budget: receipt "timeout", exit 124, the fuse
# untouched, no repair (the budget was the point; the lease has no room for
# a second 15 min process after a 20 min one anyway).
timeout_if_pi_expired() {
  if [ "$LAST_PI_RC" = 124 ]; then
    NOTES="pi_timeout: attempt $1 exceeded its budget (exit 124)"
    log "$NOTES"
    finish timeout 124
  fi
}

if [ "$guard_ok" = 1 ] && [ "$val_ok" = 1 ]; then
  pass=1
else
  pass=0
  if [ "$LAST_PI_RC" -ne 0 ]; then outage_if_halogen_gone; timeout_if_pi_expired a1; fi
  # ------------------------------------------------------------ the ONE repair
  # A fresh Pi process fed the bundle, the diff and the validation transcript
  # (never the first process's narration), then fail closed.
  REPAIR_COUNT=1
  repair_prompt="$TASK_DIR/repair-prompt.md"
  worktree_diff >"$TASK_DIR/diff-a1.patch"
  {
    cat "$BUNDLE"
    printf '\n\n## Repair\n\n'
    printf 'A previous attempt at this task produced the diff below, and the gate did not pass. '
    printf 'Fix the work in place so that the validation command passes. Do not restart from scratch.\n\n'
    printf '### Diff guard\n\n```\n%s\n```\n\n' "$(guard_text)"
    printf '### Diff against the base commit (truncated to %s bytes)\n\n```diff\n' "$DIFF_PROMPT_BYTES"
    head -c "$DIFF_PROMPT_BYTES" "$TASK_DIR/diff-a1.patch"
    printf '\n```\n\n'
    if [ -n "$LAST_TRANSCRIPT" ] && [ -r "$LAST_TRANSCRIPT" ]; then
      printf '### Validation command\n\n    %s\n\n### Validation transcript (last %s bytes)\n\n```\n' "$VALIDATION_CMD" "$TRANSCRIPT_PROMPT_BYTES"
      tail -c "$TRANSCRIPT_PROMPT_BYTES" "$LAST_TRANSCRIPT"
      printf '\n```\n'
    else
      printf '### Validation\n\nThe validation command was not run because the diff guard failed.\n'
    fi
  } >"$repair_prompt"
  if ! run_setup; then
    NOTES="setup_failed before repair: $SETUP_CMD"
    fail_or_fuse
  fi
  run_pi a2 "$repair_prompt"
  GUARD_JSON="null"; VALIDATION_JSON="null"
  guard_ok=0; run_guard && guard_ok=1
  val_ok=0
  if [ "$guard_ok" = 1 ]; then
    run_validation 2 && val_ok=1
  fi
  record_attempt a2
  if [ "$guard_ok" = 1 ] && [ "$val_ok" = 1 ]; then
    pass=1
  elif [ "$LAST_PI_RC" -ne 0 ]; then
    outage_if_halogen_gone
    timeout_if_pi_expired a2
  fi
fi

# ---------------------------------------------------------------- verdict
if [ "$pass" = 1 ]; then
  DIFF_SHA="$(diff_now)"
  if stage_allowed && git -C "$WORKTREE" "${GIT_IDENTITY[@]}" commit -q -m "$COMMIT_SUBJECT" -m "campaign: $CAMPAIGN_NAME
bundle_digest: $BUNDLE_DIGEST
skill_digest: $SKILL_DIGEST
model: $MODEL_ID
repair_count: $REPAIR_COUNT
execution_id: ${EXECUTION_ID:-none}" >/dev/null 2>&1; then
    COMMIT_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"
  else
    NOTES="validation passed but nothing inside allowed_paths could be committed"
    log "$NOTES"
    fail_or_fuse
  fi
  fuse_write 0 "$FUSE_PKG"
  log "PASS: committed $COMMIT_SHA on $BRANCH (never pushed)"
  finish pass 0
fi

# fail, and maybe the fuse
if [ "$guard_ok" != 1 ]; then
  NOTES="diff_guard: $(guard_text)"
elif [ "$(printf '%s' "$ATTEMPTS_JSON" | jq -r '.[-1].events.stop_reason // ""')" = "length" ]; then
  NOTES="validation_failed after finish_reason=length (exit $(printf '%s' "$VALIDATION_JSON" | jq -r .exit))"
elif [ "$LAST_PI_RC" -ne 0 ]; then
  NOTES="pi_exit_$LAST_PI_RC then validation_failed (exit $(printf '%s' "$VALIDATION_JSON" | jq -r .exit))"
else
  NOTES="validation_failed (exit $(printf '%s' "$VALIDATION_JSON" | jq -r .exit))"
fi
fail_or_fuse
