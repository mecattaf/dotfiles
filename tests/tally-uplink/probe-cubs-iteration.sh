#!/usr/bin/env bash
# cubs-halogen-probe-1 (FRONT-12 bootstrap) — the oracle for `cubs-iteration`
# and for the `build:CUBS-<n>` kit entries in home/tally-uplink.nix.
#
# WHAT IT PROVES, out of the TREE only: no network, no socket, no lake, no
# switch, no unit, nothing under ~/.local/state, nothing under ~/agency. The
# executable is built from this checkout; Pi and Halogen are STUBS in a scratch
# directory (a shell script that emits a `pi --mode json` event stream and
# performs a scripted edit; a `python3 -m http.server` answering /health and
# /v1/models); the CUBS repos are two throwaway git repositories. Every clause
# reads a file the real run would write — receipt.json, the usage line, the
# branch — never the script's own narration.
#
#   C1  --help rc 0; a malformed stdin rc 65; an unknown flag rc 64.
#   C2  the BUILT executable, under `env -i` with only the two variables
#       exec.run exports, reads the kit's own stdin pointer and prints a plan
#       (--dry, rc 0) — the shape the kernel will run it in.
#   C3  PASS: receipt terminal_status pass, a commit "T1: …" on
#       campaign/cubs-halogen-probe-1/T1 (never pushed), one usage line at
#       TALLY_USAGE_SOURCE_PATH carrying the execution id, fuse 0, a ledger
#       line; a second invocation is an idempotent rc 0 that runs no Pi.
#   C4  FAIL + the ONE repair: a1 and a2 event logs, a repair prompt carrying
#       the diff and the transcript, receipt fail with repair_count 1, fuse 1.
#   C5  THE FUSE: two more fails -> the third exits 2 with receipt fuse; a
#       passable task then exits 2 `fuse_blown_before_start`; removing
#       <state>/fuse lets it pass and resets the count to 0.
#   C6  THE GUARD: an edit to spec/**/spec.md fails the task by name even
#       though the validation command would pass.
#   C7  OUTAGE: Halogen busy past the deadline -> rc 69, receipt outage, the
#       fuse untouched.
#   C8  SIGTERM (the lease's rail): with Pi mid-run, TERM -> rc 143 inside
#       25 s, receipt cancelled, the WIP committed on the task branch; the
#       retry reuses the worktree and base and passes.
#   C8b THE RECEIPT SCHEMA: a tracked-file-only edit (nothing untracked) and a
#       stray untracked file both leave a TERMINAL receipt (not pending) with
#       stray_files a single JSON array, and each validates against the
#       campaign's tools/receipt.schema.json (stdlib validator, below).
#   C9  the events summariser: usage summed over message_end, tool counts,
#       isError, repeated identical calls, from the stub's stream.
#   C10 THE KIT: the pinned lake's own readKit resolves build:CUBS-1..200 and
#       their scope()/eval() cells; argv[0] is an executable store path; stdin
#       is a JSON pointer {worklist, id} naming the item; LOCAL-SMOKE and the
#       claude:headless refusal are unchanged (FT-3's K2 still holds).
#   C11 `nix build .#checks.x86_64-linux.tally-uplink-topology` -> rc 0.
#
# Usage: bash tests/tally-uplink/probe-cubs-iteration.sh [repo-path]
# rc 0 = every clause passed. rc 1 = a clause failed. rc 2 = the probe could not run.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }
for tool in nix jq git python3 curl; do
  command -v "$tool" >/dev/null || { echo "FAIL: no $tool on PATH"; exit 2; }
done

fails=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

scratch="$(mktemp -d)" || exit 2
HTTP_PID=""
trap '[ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null; rm -rf "$scratch"' EXIT

# ---- the executable, built from THIS checkout with the coordinator's pkgs.
bin="$(nix build --no-link --print-out-paths --impure --expr \
  "let f = builtins.getFlake \"path:${repo}\"; pkgs = f.nixosConfigurations.coordinator.pkgs;
   in pkgs.callPackage ./pkgs/cubs-iteration { pi = pkgs.llm-agents.pi; }" 2>/dev/null)/bin/cubs-iteration"
[ -x "$bin" ] || { echo "FAIL: cannot build pkgs/cubs-iteration"; exit 2; }
echo "built $bin"

# ---- C1
if "$bin" --help >/dev/null 2>&1; then ok "C1 --help rc 0"; else bad "C1 --help"; fi
echo 'not json' | "$bin" --dry >/dev/null 2>&1; rc=$?
[ "$rc" = 65 ] && ok "C1 malformed stdin rc 65" || bad "C1 malformed stdin rc $rc (want 65)"
echo '{}' | "$bin" --bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && ok "C1 unknown flag rc 64" || bad "C1 unknown flag rc $rc (want 64)"

# ---- the scratch estate: campaign, agency, state, halogen.
campaign="$scratch/campaign"; agency="$scratch/agency"; state="$scratch/state"; halogen_dir="$scratch/halogen"
mkdir -p "$campaign/skill" "$campaign/pi" "$campaign/bundles" "$campaign/worklists" "$agency" "$state" "$halogen_dir/v1"
printf '# campaign system prompt (stub)\nYour prose is not evidence.\n' >"$campaign/skill/system-prompt.md"
jq -n '{providers: {halogen: {api: "openai-completions", baseUrl: "http://stub/v1", models: [{id: "halogen-qwen3.8-flash-next"}]}}}' >"$campaign/pi/models.json"
jq -n '{compaction: {reserveTokens: 32768, keepRecentTokens: 20000}}' >"$campaign/pi/settings.json"
git -C "$campaign" init -q && git -C "$campaign" -c user.name=t -c user.email=t@t add -A && git -C "$campaign" -c user.name=t -c user.email=t@t commit -q -m init

mkrepo() { # name, file, content
  mkdir -p "$agency/$1/$(dirname "$2")"
  printf '%s\n' "$3" >"$agency/$1/$2"
  git -C "$agency/$1" init -q
  git -C "$agency/$1" -c user.name=t -c user.email=t@t add -A
  git -C "$agency/$1" -c user.name=t -c user.email=t@t commit -q -m init
}
mkrepo demo src/hello.txt "placeholder"
mkrepo spec specs/D01/spec.md "# D01 frozen"

for t in T1 T2 T3 T4 T5 T6 T7 T8 T9 T10 T11 CUBS-90 CUBS-91; do printf '# bundle %s\n\nDo the task. Validation: see worklist.\n' "$t" >"$campaign/bundles/$t.md"; done
wl="$campaign/worklists/current.jsonl"
task_line() { # id repo validation_cmd allowed [package]
  jq -cn --arg id "$1" --arg repo "$2" --arg v "$3" --argjson allowed "$4" --arg b "$campaign/bundles/$1.md" --arg pkg "${5:-WP-stub}" \
    '{id: $id, package: $pkg, title: ("stub task " + $id), repo: $repo, bundle_path: $b, validation_cmd: $v,
      allowed_paths: $allowed, new_files: [], thinking: "low", prior_p_pass: 0.5, predicted_failure: "none"}'
}
{
  task_line T1 demo 'grep -q hello src/hello.txt' '["src/**"]'
  task_line T2 demo 'false' '["src/**"]'
  task_line T3 demo 'false' '["src/**"]'
  task_line T4 demo 'false' '["src/**"]'
  task_line T5 spec 'true' '["specs/**"]'
  task_line T6 demo 'grep -q hello src/hello.txt' '["src/**"]'
  task_line T7 demo 'grep -q hello src/hello.txt' '["src/**"]'
  task_line T8 demo 'true' '["src/**"]'
  task_line T9 demo 'grep -q hello src/hello.txt' '["src/**"]'
  task_line T10 demo 'grep -q hello src/hello.txt' '["src/**"]'
  task_line T11 demo 'true' '["src/**"]'
  task_line CUBS-90 demo 'grep -q hello src/hello.txt' '["src/**"]' WP1
  task_line CUBS-91 demo 'grep -q hello src/hello.txt' '["src/**"]' WP1
} >"$wl"

# the stub Pi: writes a session file (so the fresh-process rotation is real),
# performs the scripted edit in its cwd, emits an event stream.
stub_pi="$scratch/pi"
cat >"$stub_pi" <<'EOF'
#!/usr/bin/env bash
set -u
sid=""; sdir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id) sid="$2"; shift ;;
    --session-dir) sdir="$2"; shift ;;
  esac
  shift
done
mkdir -p "$sdir"; printf '{"type":"session","id":"%s"}\n' "$sid" >"$sdir/2026-09-16T00-00-00_$sid.jsonl"
# what the harness handed this process on fd 0, and whether settings.json was reachable
printf '%s\n' "$(readlink /proc/self/fd/0)" >"$sdir/stdin-of-$sid"
[ -r "${PI_CODING_AGENT_DIR:-/nonexistent}/settings.json" ] && printf 'yes\n' >"$sdir/settings-of-$sid"
case "${STUB_PI_ACTION:-edit}" in
  edit) mkdir -p src; printf 'hello\n' >>src/hello.txt ;;
  edit-no-newline) mkdir -p src; printf 'hello' >src/hello.txt ;;
  edit-plus-stray) mkdir -p src; printf 'hello\n' >>src/hello.txt; printf 'junk\n' >junk.txt ;;
  sleep) sleep 30 ;;
  edit-spec) printf 'changed\n' >>specs/D01/spec.md ;;
  edit-then-sleep) mkdir -p src; printf 'hello\n' >>src/hello.txt; sleep 60 ;;
  none) : ;;
esac
cat <<'EVENTS'
{"type":"session","version":3,"id":"stub","timestamp":"t","cwd":"."}
{"type":"agent_start"}
{"type":"tool_execution_start","toolCallId":"1","toolName":"read","args":{"path":"src/hello.txt"}}
{"type":"tool_execution_end","toolCallId":"1","toolName":"read","result":"x","isError":false}
{"type":"tool_execution_start","toolCallId":"2","toolName":"read","args":{"path":"src/hello.txt"}}
{"type":"tool_execution_end","toolCallId":"2","toolName":"read","result":"x","isError":false}
{"type":"tool_execution_start","toolCallId":"3","toolName":"bash","args":{"command":"false"}}
{"type":"tool_execution_end","toolCallId":"3","toolName":"bash","result":"x","isError":true}
{"type":"message_end","message":{"role":"assistant","content":[],"usage":{"input":100,"output":40,"cacheRead":10,"cacheWrite":0,"totalTokens":150},"stopReason":"toolUse"}}
{"type":"message_end","message":{"role":"assistant","content":[],"usage":{"input":200,"output":60,"cacheRead":0,"cacheWrite":0,"totalTokens":260},"stopReason":"stop"}}
{"type":"agent_end","messages":[]}
EVENTS
EOF
chmod +x "$stub_pi"

# the stub Halogen: /health and /v1/models as files.
set_health() { jq -n --argjson busy "$1" '{status: "ok", model: "halogen-qwen3.8-flash-next", busy: $busy, engine: {responds: true}, version: {api: "stub", engine: "stub"}}' >"$halogen_dir/health"; }
set_health false
printf '{"object":"list","data":[{"id":"halogen-qwen3.8-flash-next"}]}\n' >"$halogen_dir/v1/models"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
( cd "$halogen_dir" && exec python3 -m http.server --bind 127.0.0.1 "$port" >/dev/null 2>&1 ) &
HTTP_PID=$!
for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break; sleep 0.1; done
curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1 || { echo "FAIL: stub halogen did not come up"; exit 2; }

run() { # id [extra env...]; stdin = the kit's pointer form
  local id="$1"; shift
  jq -cn --arg wl "$wl" --arg id "$id" '{worklist: $wl, id: $id}' \
    | env -i HOME="$scratch/home" CUBS_CAMPAIGN_DIR="$campaign" CUBS_STATE_DIR="$state" CUBS_AGENCY_ROOT="$agency" \
        CUBS_HALOGEN_URL="http://127.0.0.1:$port" CUBS_PI_BIN="$stub_pi" CUBS_HEALTH_INTERVAL=1 CUBS_HEALTH_DEADLINE=3 \
        STUB_PI_ACTION="${STUB_PI_ACTION:-edit}" \
        TALLY_EXECUTION_ID="exec-$id" TALLY_USAGE_SOURCE_PATH="$state/usage/cubs-$id.jsonl" "$@" \
        "$bin" 2>>"$scratch/stderr.log"
}
mkdir -p "$scratch/home"
receipt() { jq -r "$2" "$state/tasks/$1/receipt.json" 2>/dev/null; }

# ---- C2: the kit's own stdin, env -i, --dry.
kit="$(nix eval --raw ".#nixosConfigurations.coordinator.config.home-manager.users.tom.services.tally-uplink.kit" 2>/dev/null)"
[ -e "$kit" ] || nix build --no-link ".#nixosConfigurations.coordinator.config.home-manager.users.tom.services.tally-uplink.kit" >/dev/null 2>&1
if [ -r "$kit" ]; then
  out="$(jq -r '.entries["build:CUBS-1"].stdin' "$kit" | env -i TALLY_EXECUTION_ID=e TALLY_USAGE_SOURCE_PATH=/dev/null "$bin" --dry 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && printf '%s' "$out" | jq -e '.dry == true and .id == "CUBS-1" or (.task.id == "CUBS-1")' >/dev/null 2>&1; then
    ok "C2 env -i --dry on the kit's stdin pointer: rc 0, id CUBS-1 ($(printf '%s' "$out" | jq -r 'if .resolved then "resolved" else "unresolved: " + .reason end'))"
  else
    bad "C2 env -i --dry rc $rc: $out"
  fi
else
  bad "C2 the kit did not evaluate"
fi

# ---- C3: PASS.
STUB_PI_ACTION=edit run T1; rc=$?
[ "$rc" = 0 ] && ok "C3 T1 rc 0" || bad "C3 T1 rc $rc"
[ "$(receipt T1 .terminal_status)" = pass ] && ok "C3 receipt pass" || bad "C3 receipt: $(receipt T1 .terminal_status)"
subject="$(git -C "$agency/demo" log -1 --format=%s "campaign/cubs-halogen-probe-1/T1" 2>/dev/null)"
[ "$(receipt T1 .worktree_branch)" = "campaign/cubs-halogen-probe-1/T1" ] && ok "C3 receipt.worktree_branch" || bad "C3 worktree_branch $(receipt T1 .worktree_branch)"
[ "$subject" = "CUBS-T1: stub task T1" ] && ok "C3 commit on the task branch: $subject" || bad "C3 commit subject '$subject'"
[ "$(git -C "$agency/demo" rev-parse main 2>/dev/null || git -C "$agency/demo" rev-parse master)" = "$(receipt T1 .base_sha)" ] && ok "C3 base_sha is the repo HEAD" || bad "C3 base_sha"
[ "$(receipt T1 .commit_sha)" = "$(git -C "$agency/demo" rev-parse campaign/cubs-halogen-probe-1/T1)" ] && ok "C3 receipt.commit_sha = branch tip" || bad "C3 commit_sha"
if [ "$(wc -l <"$state/usage/cubs-T1.jsonl")" = 1 ] && [ "$(jq -r .execution_id "$state/usage/cubs-T1.jsonl")" = "exec-T1" ] \
   && [ "$(jq -r .usage.completion_tokens "$state/usage/cubs-T1.jsonl")" = 100 ]; then
  ok "C3 one usage line, execution_id exec-T1: $(cat "$state/usage/cubs-T1.jsonl")"
else
  bad "C3 usage line: $(cat "$state/usage/cubs-T1.jsonl" 2>&1)"
fi
[ "$(cat "$state/fuse")" = 0 ] && ok "C3 fuse 0" || bad "C3 fuse $(cat "$state/fuse" 2>&1)"
[ "$(wc -l <"$state/ledger.jsonl")" = 1 ] && ok "C3 one ledger line" || bad "C3 ledger lines $(wc -l <"$state/ledger.jsonl")"
# the campaign's tools/receipt.schema.json `required` list, plus the two this
# executable adds (execution_id, exit_code).
for f in schema_version task package provider model health_version campaign_sha skill_digest bundle_digest \
         worktree_branch tool_calls is_error_count repeated_identical_calls usage diff_sha256 commit_sha validation \
         repair_count terminal_status wall_seconds prior_p_pass predicted_failure started_at finished_at \
         bash_call_count stray_files reasoning_tokens attempts_path execution_id exit_code; do
  jq -e --arg f "$f" 'has($f)' "$state/tasks/T1/receipt.json" >/dev/null || bad "C3 receipt lacks required field $f"
done
for f in model health_version campaign_sha skill_digest bundle_digest diff_sha256 wall_seconds prior_p_pass predicted_failure; do
  v="$(receipt T1 ".$f")"; { [ -n "$v" ] && [ "$v" != null ]; } || bad "C3 receipt field $f is empty/null"
done
[ "$(receipt T1 .observed_failure_mode)" = null ] && ok "C3 observed_failure_mode left null for the review" || bad "C3 observed_failure_mode"
case "$(receipt T1 .skill_digest)" in sha256:????????????????????????????????????????????????????????????????) ok "C3 digests carry the sha256: prefix" ;; *) bad "C3 skill_digest $(receipt T1 .skill_digest)" ;; esac
[ "$(receipt T1 '.validation.guard_exit')" = 0 ] && ok "C3 validation.guard_exit 0" || bad "C3 guard_exit $(receipt T1 .validation.guard_exit)"
[ -s "$state/tasks/T1/attempts.json" ] && ok "C3 attempts.json beside the receipt" || bad "C3 attempts.json"
[ "$(receipt T1 .model)" = halogen-qwen3.8-flash-next ] && ok "C3 model read from /v1/models" || bad "C3 model $(receipt T1 .model)"
[ "$(cat "$state/sessions/stdin-of-T1-a1")" = /dev/null ] && ok "C3 Pi's stdin is /dev/null" || bad "C3 Pi stdin was $(cat "$state/sessions/stdin-of-T1-a1")"
[ -e "$state/sessions/settings-of-T1-a1" ] && ok "C3 PI_CODING_AGENT_DIR carries settings.json" || bad "C3 settings.json not reachable from PI_CODING_AGENT_DIR"
[ "$(receipt T1 '.tool_call_names.bash')" = 1 ] && [ "$(receipt T1 .bash_call_count)" = 1 ] && ok "C3 bash calls counted (tool_call_names.bash, bash_call_count)" || bad "C3 bash count $(receipt T1 .bash_call_count)"
[ "$(receipt T1 '.stray_files | length')" = 0 ] && ok "C3 stray_files empty on a clean pass" || bad "C3 stray_files $(receipt T1 .stray_files)"
a1_before="$(stat -c %Y "$state/logs/T1-a1.jsonl")"
sleep 1
STUB_PI_ACTION=none run T1; rc=$?
if [ "$rc" = 0 ] && [ "$(stat -c %Y "$state/logs/T1-a1.jsonl")" = "$a1_before" ]; then ok "C3 second run idempotent (rc 0, no Pi)"; else bad "C3 idempotency rc $rc"; fi

# ---- C4: FAIL + one repair.
STUB_PI_ACTION=edit run T2; rc=$?
[ "$rc" = 1 ] && ok "C4 T2 rc 1" || bad "C4 T2 rc $rc"
[ "$(receipt T2 .terminal_status)" = fail ] && ok "C4 receipt fail" || bad "C4 receipt $(receipt T2 .terminal_status)"
[ "$(receipt T2 .repair_count)" = 1 ] && ok "C4 repair_count 1" || bad "C4 repair_count $(receipt T2 .repair_count)"
[ -s "$state/logs/T2-a1.jsonl" ] && [ -s "$state/logs/T2-a2.jsonl" ] && ok "C4 a1 and a2 event logs" || bad "C4 event logs"
if grep -q '## Repair' "$state/tasks/T2/repair-prompt.md" && grep -q '^+hello' "$state/tasks/T2/repair-prompt.md" && grep -q 'Validation command' "$state/tasks/T2/repair-prompt.md"; then
  ok "C4 repair prompt carries the diff and the transcript"
else
  bad "C4 repair prompt"
fi
[ "$(jq 'length' "$state/tasks/T2/attempts.json")" = 2 ] && ok "C4 two attempts in attempts.json" || bad "C4 attempts"
[ "$(receipt T2 '.sessions | join(",")')" = "T2-a1,T2-a2" ] && ok "C4 sessions T2-a1,T2-a2" || bad "C4 sessions $(receipt T2 .sessions)"
[ "$(receipt T2 .validation.exit)" = 1 ] && ok "C4 validation exit 1 recorded" || bad "C4 validation $(receipt T2 .validation)"
[ "$(cat "$state/fuse")" = 1 ] && ok "C4 fuse 1" || bad "C4 fuse $(cat "$state/fuse")"
[ "$(receipt T2 .commit_sha)" = null ] && ok "C4 commit_sha null on fail" || bad "C4 commit on fail: $(receipt T2 .commit_sha)"

# ---- C5: the fuse.
STUB_PI_ACTION=edit run T3; rc=$?
[ "$rc" = 1 ] && [ "$(cat "$state/fuse")" = 2 ] && ok "C5 T3 rc 1, fuse 2" || bad "C5 T3 rc $rc fuse $(cat "$state/fuse")"
STUB_PI_ACTION=edit run T4; rc=$?
[ "$rc" = 2 ] && [ "$(receipt T4 .terminal_status)" = fuse ] && ok "C5 T4 rc 2, receipt fuse" || bad "C5 T4 rc $rc $(receipt T4 .terminal_status)"
STUB_PI_ACTION=edit run T7; rc=$?
if [ "$rc" = 2 ] && [ "$(receipt T7 .terminal_status)" = fuse ] && receipt T7 .notes | grep -q fuse_blown_before_start && [ ! -e "$state/logs/T7-a1.jsonl" ]; then
  ok "C5 T7 refused before start (rc 2, no Pi run)"
else
  bad "C5 T7 rc $rc $(receipt T7 .notes)"
fi
rm -f "$state/fuse"
STUB_PI_ACTION=edit run T7; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$state/fuse")" = 0 ] && [ "$(receipt T7 .terminal_status)" = pass ] && ok "C5 fuse removed -> T7 passes, fuse 0" || bad "C5 after reset rc $rc"

# ---- C6: the guard.
STUB_PI_ACTION=edit-spec run T5; rc=$?
if [ "$rc" = 1 ] && receipt T5 .notes | grep -q 'spec.md is never modified'; then
  ok "C6 spec/**/spec.md edit fails by name: $(receipt T5 .notes)"
else
  bad "C6 guard rc $rc: $(receipt T5 .notes)"
fi
[ "$(receipt T5 .validation.exit)" = null ] && [ "$(receipt T5 .validation.guard_exit)" = 1 ] && ok "C6 validation never ran behind a red guard (exit null, guard_exit 1)" || bad "C6 validation $(receipt T5 .validation)"

# ---- C6b: the trailing-newline gate.
rm -f "$state/fuse"  # each guard clause stands alone: three in a row would blow the fuse
STUB_PI_ACTION=edit-no-newline run T9; rc=$?
if [ "$rc" = 1 ] && receipt T9 .notes | grep -q 'no trailing newline'; then
  ok "C6 a touched file without a final newline fails the gate: $(receipt T9 .notes)"
else
  bad "C6 newline gate rc $rc: $(receipt T9 .notes)"
fi

# ---- C6c: stray files are listed, and the guard fails on them.
rm -f "$state/fuse"  # each guard clause stands alone: three in a row would blow the fuse
STUB_PI_ACTION=edit-plus-stray run T10; rc=$?
if [ "$rc" = 1 ] && [ "$(receipt T10 '.stray_files | join(",")')" = "junk.txt" ] && receipt T10 .notes | grep -q 'junk.txt: outside allowed_paths'; then
  ok "C6 stray untracked file fails the guard and is listed: $(receipt T10 -c .stray_files 2>/dev/null || receipt T10 '.stray_files | join(",")')"
else
  bad "C6 stray rc $rc stray_files=$(receipt T10 '.stray_files | join(",")') notes=$(receipt T10 .notes)"
fi

# ---- C6d: a Pi process that hits its budget is "timeout", not fail, not fuse.
fuse_before="$(cat "$state/fuse")"
STUB_PI_ACTION=sleep run T11 CUBS_PI_TIMEOUT=2; rc=$?
if [ "$rc" = 124 ] && [ "$(receipt T11 .terminal_status)" = timeout ] && [ "$(cat "$state/fuse")" = "$fuse_before" ] && [ ! -e "$state/logs/T11-a2.jsonl" ]; then
  ok "C6 Pi over budget -> rc 124, receipt timeout, fuse untouched ($fuse_before), no repair"
else
  bad "C6 timeout rc $rc status $(receipt T11 .terminal_status) fuse $(cat "$state/fuse")"
fi

# ---- C7: outage.
fuse_before="$(cat "$state/fuse")"
set_health true
STUB_PI_ACTION=edit run T8; rc=$?
set_health false
[ "$rc" = 69 ] && [ "$(receipt T8 .terminal_status)" = outage ] && ok "C7 busy Halogen -> rc 69, receipt outage" || bad "C7 rc $rc $(receipt T8 .terminal_status)"
[ "$(cat "$state/fuse")" = "$fuse_before" ] && ok "C7 fuse untouched ($fuse_before)" || bad "C7 fuse moved"
[ ! -e "$state/logs/T8-a1.jsonl" ] && ok "C7 no Pi run during the outage" || bad "C7 Pi ran"
STUB_PI_ACTION=edit run T8; rc=$?
[ "$rc" = 0 ] && ok "C7 T8 retries to pass once Halogen is idle" || bad "C7 retry rc $rc"

# ---- C8: SIGTERM.
STUB_PI_ACTION=edit-then-sleep run T6 & runner=$!
for _ in $(seq 1 100); do [ -e "$state/logs/T6-a1.jsonl" ] && [ -e "$agency/demo/.git" ] && break; sleep 0.1; done
sleep 0.5
t0=$(date +%s%N)
# the script itself, not the subshell around the pipeline: the kernel signals
# the process group; here the executable is named by its own path.
pkill -TERM -f "$bin" || bad "C8 no cubs-iteration process to signal"
wait "$runner"; rc=$?
elapsed_ms=$(( ($(date +%s%N) - t0) / 1000000 ))
if [ "$rc" = 143 ] && [ "$elapsed_ms" -le 25000 ]; then ok "C8 TERM -> rc 143 in ${elapsed_ms} ms"; else bad "C8 TERM rc $rc in ${elapsed_ms} ms"; fi
[ "$(receipt T6 .terminal_status)" = cancelled ] && ok "C8 receipt cancelled" || bad "C8 receipt $(receipt T6 .terminal_status)"
wip="$(git -C "$agency/demo" log -1 --format=%s campaign/cubs-halogen-probe-1/T6 2>/dev/null)"
case "$wip" in *"WIP, cancelled under lease"*) ok "C8 WIP committed: $wip" ;; *) bad "C8 WIP commit '$wip'" ;; esac
base_before="$(cat "$state/tasks/T6/base_sha")"
STUB_PI_ACTION=edit run T6; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$state/tasks/T6/base_sha")" = "$base_before" ] && [ "$(receipt T6 .terminal_status)" = pass ] \
   && [ "$(receipt T6 '.sessions[0]')" = "T6-a1-r2" ] \
   && [ "$(git -C "$agency/demo" rev-parse "campaign/cubs-halogen-probe-1/T6~1")" = "$base_before" ]; then
  ok "C8 retry reuses worktree and base, rotates the session id (T6-a1-r2), passes with ONE commit above the base"
else
  bad "C8 retry rc $rc session $(receipt T6 '.sessions[0]') parent $(git -C "$agency/demo" rev-parse "campaign/cubs-halogen-probe-1/T6~1")"
fi
[ "$(git -C "$agency/demo" for-each-ref 'refs/cubs-wip/T6/' | wc -l)" -ge 1 ] && ok "C8 the WIP stays reachable under refs/cubs-wip/T6/" || bad "C8 refs/cubs-wip"

# ---- C8b: terminal receipts validate against the campaign's receipt schema.
schema="${CUBS_RECEIPT_SCHEMA:-/home/tom/mecattaf/cubs-campaign/tools/receipt.schema.json}"
validate_receipt() { # receipt.json -> rc 0 valid; prints the violations otherwise
  python3 - "$schema" "$1" <<'PY'
import json, re, sys
schema = json.load(open(sys.argv[1])); doc = json.load(open(sys.argv[2])); errs = []
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}
def is_type(v, t):
    if t == "integer": return isinstance(v, int) and not isinstance(v, bool)
    if t == "number": return isinstance(v, (int, float)) and not isinstance(v, bool)
    return isinstance(v, TYPES[t])
def check(s, v, path):
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(is_type(v, t) for t in ts): errs.append(f"{path}: type {type(v).__name__} not in {ts}"); return
    if "const" in s and v != s["const"]: errs.append(f"{path}: != const {s['const']!r}")
    if "enum" in s and v not in s["enum"]: errs.append(f"{path}: {v!r} not in enum")
    if isinstance(v, str) and "pattern" in s and not re.search(s["pattern"], v): errs.append(f"{path}: {v!r} !~ {s['pattern']}")
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if "minimum" in s and v < s["minimum"]: errs.append(f"{path}: {v} < minimum")
        if "maximum" in s and v > s["maximum"]: errs.append(f"{path}: {v} > maximum")
    if isinstance(v, dict):
        for r in s.get("required", []):
            if r not in v: errs.append(f"{path}: missing required {r}")
        props = s.get("properties", {}); ap = s.get("additionalProperties", True)
        for k, x in v.items():
            if k in props: check(props[k], x, f"{path}.{k}")
            elif ap is False: errs.append(f"{path}: additional property {k}")
            elif isinstance(ap, dict): check(ap, x, f"{path}.{k}")
    if isinstance(v, list) and "items" in s:
        for i, x in enumerate(v): check(s["items"], x, f"{path}[{i}]")
check(schema, doc, "$")
print("; ".join(errs)); sys.exit(1 if errs else 0)
PY
}
if [ -r "$schema" ]; then
  rm -f "$state/fuse"
  STUB_PI_ACTION=edit run CUBS-90; rc=$?
  st="$(receipt CUBS-90 .terminal_status)"
  if [ "$rc" = 0 ] && [ "$st" = pass ] && [ "$(receipt CUBS-90 '.stray_files | tojson')" = "[]" ] \
     && [ "$(receipt CUBS-90 .finished_at)" != null ]; then
    ok "C8b tracked-file-only edit -> rc 0, terminal receipt pass, stray_files []"
  else
    bad "C8b tracked-only rc $rc status $st stray $(receipt CUBS-90 '.stray_files | tojson')"
  fi
  v="$(validate_receipt "$state/tasks/CUBS-90/receipt.json" 2>&1)" && ok "C8b CUBS-90 receipt validates against receipt.schema.json" || bad "C8b CUBS-90 schema: $v"
  rm -f "$state/fuse"
  STUB_PI_ACTION=edit-plus-stray run CUBS-91; rc=$?
  st="$(receipt CUBS-91 .terminal_status)"
  if [ "$rc" = 1 ] && [ "$st" = fail ] && [ "$(receipt CUBS-91 '.stray_files | tojson')" = '["junk.txt"]' ] \
     && [ "$(receipt CUBS-91 .finished_at)" != null ]; then
    ok "C8b stray untracked file -> rc 1, terminal receipt fail, stray_files [\"junk.txt\"]"
  else
    bad "C8b stray rc $rc status $st stray $(receipt CUBS-91 '.stray_files | tojson')"
  fi
  v="$(validate_receipt "$state/tasks/CUBS-91/receipt.json" 2>&1)" && ok "C8b CUBS-91 receipt validates against receipt.schema.json" || bad "C8b CUBS-91 schema: $v"
  rm -f "$state/fuse"
else
  bad "C8b cannot read the receipt schema at $schema"
fi

# ---- C9: the events summariser over the stub's stream.
ev="$(jq -c '.[0].events' "$state/tasks/T1/attempts.json")"
if printf '%s' "$ev" | jq -e '.tool_calls == 3 and .tool_errors == 1 and .repeated_identical_calls == 1 and .usage.prompt_tokens == 310 and .usage.completion_tokens == 100 and .stop_reason == "stop" and .agent_end == true' >/dev/null; then
  ok "C9 events: $ev"
else
  bad "C9 events: $ev"
fi

# ---- C10: the kit, through the pinned lake's own readKit.
lake="$(nix eval --raw --impure --expr "(builtins.getFlake \"path:${repo}\").inputs.tally-lake.outPath" 2>/dev/null)"
node="$(nix eval --raw ".#nixosConfigurations.coordinator.config.home-manager.users.tom.services.tally-uplink.node" 2>/dev/null)/bin/node"
if [ -r "$kit" ] && [ -r "$lake/apps/uplink/src/kit.mjs" ] && [ -x "$node" ]; then
  out="$("$node" --input-type=module -e "
    import { readKit } from '${lake}/apps/uplink/src/kit.mjs'
    import { accessSync, constants } from 'node:fs'
    const kit = readKit(process.argv[1])
    for (let n = 1; n <= 200; n++) {
      const id = 'CUBS-' + n
      const w = kit.resolve('build:' + id)
      for (const f of ['argv', 'cwd', 'env_allowlist', 'usage_source', 'stdin']) if (w[f] === undefined) throw new Error(id + ' missing ' + f)
      if (!w.argv[0].startsWith('/nix/store/') || !w.argv[0].endsWith('/bin/cubs-iteration')) throw new Error(id + ' argv0 ' + w.argv[0])
      accessSync(w.argv[0], constants.X_OK)
      if (w.env_allowlist.length !== 0) throw new Error(id + ' env_allowlist not empty')
      if (w.usage_source.kind !== 'halogen-usage/1' || !w.usage_source.path_glob.includes('/uplink/usage/cubs-*.jsonl')) throw new Error(id + ' usage_source ' + JSON.stringify(w.usage_source))
      const p = JSON.parse(w.stdin)
      if (p.id !== id || !p.worklist.endsWith('/mecattaf/cubs-campaign/worklists/current.jsonl')) throw new Error(id + ' stdin ' + w.stdin)
      if (w.cwd !== '/home/tom/mecattaf/cubs-campaign') throw new Error(id + ' cwd ' + w.cwd)
      for (const cell of ['scope(build:' + id + ')', 'eval(build:' + id + ')']) {
        const e = kit.resolve(cell)
        if (e.argv.join(' ') !== '/bin/sh -c true') throw new Error(cell + ' is not the noop')
      }
    }
    kit.resolve('build:LOCAL-SMOKE')
    let refused = ''
    try { kit.resolve('claude:headless') } catch (e) { refused = e.message }
    if (!refused) throw new Error('claude:headless resolved')
    let extra = ''
    try { kit.resolve('build:CUBS-201') } catch (e) { extra = e.message }
    if (!extra) throw new Error('build:CUBS-201 resolved; N is 200')
    console.log('REFS=' + kit.refs().length + ' ARGV0=' + kit.resolve('build:CUBS-1').argv[0])
  " "$kit" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then ok "C10 readKit(pinned lake): 200 CUBS items x 3 cells, LOCAL-SMOKE kept, claude:headless and CUBS-201 refused — $out"; else bad "C10 readKit: $out"; fi
else
  bad "C10 cannot resolve kit ($kit), lake ($lake) or node ($node)"
fi

# ---- C11: the topology check.
if nix build .#checks.x86_64-linux.tally-uplink-topology --no-link >/dev/null 2>&1; then
  ok "C11 nix build .#checks.x86_64-linux.tally-uplink-topology"
else
  bad "C11 tally-uplink-topology did not build"
fi

if [ "$fails" -eq 0 ]; then
  echo "PROBE cubs-iteration: PASS"
  exit 0
fi
echo "PROBE cubs-iteration: FAIL ($fails clause(s)); stderr at $scratch/stderr.log:"
tail -n 40 "$scratch/stderr.log"
exit 1
