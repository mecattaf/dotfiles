#!/usr/bin/env bash
#
# D-section.sh -- Expert D (CLI/UX & DISPATCH) hardened functions for `sandbox`.
#
# These REPLACE the same-named functions in Agent A's spine (A-full.sh). They
# are calibrated to A's interfaces: same function names/signatures, same global
# variable names (OPT_*, EXTRA_*, PARSED_IMAGE, WORKLOAD_CMD, EX_* codes,
# DEF_*/KRUN_* bounds, the LBL_* label keys, podman_q). The integrator can
# splice each function over A's verbatim. Deviations from A are noted in the
# structured summary and inline with `# DEVIATION:`.
#
# Domain owned here:
#   - Leveled logging to a configurable fd (_log/trace/debug/info/warn/err/die)
#   - Self-documenting usage() that greps the script's OWN comment lines for both
#     verbs (# VERB:) and flags (# FLAG:) -> zero help/parser drift
#   - The shared birth-verb arg parser (parse_birth_args) with flags+env duality,
#     the -- separator passing everything after verbatim to the guest, and
#     bounds-safe option-argument consumption (no `$2` under set -u)
#   - Machine-readable output: --json / stable columns derived from podman ps
#     --format; diagnostics to stderr; stdout stays pipeable (emit_kv, json_escape)
#   - The stable distinct exit-code scheme (workload code forwarded verbatim;
#     distinct codes for precondition / not-found / launch / guard; never 255)
#   - base64 command-transport for arbitrary agent-written code (encode_workload)
#
# NOTE: This file is a DRAFT section, not a standalone runnable script. It assumes
# the surrounding constants from A's spine. The trailing `: "${VAR:=...}"` block
# only exists so `bash -n` can parse the file in isolation; the integrator drops
# it (the real definitions live in A's spine).

# ============================================================================
# Leveled logging (gh-runner-krunvm "Poor Man's Logging", ported to bash).
#
# ALL diagnostics go to a configurable fd (default stderr=2) so stdout stays
# pipeable / machine-readable. Levels: 0=warn/err only, 1=+info, 2=+debug,
# 3=+trace. The level/fd are env-overridable (SANDBOX_VERBOSE / SANDBOX_LOG_FD).
#
# DEVIATION from A: the level predicates use an explicit `if`/`return` instead of
# A's `[ ... ] && _log ... || true`. Under `set -e` the `&&...||true` form is
# only safe by luck; the `if` form is unambiguous and cannot accidentally
# propagate a non-zero status to a caller that is the last command in a function.
# ============================================================================

_log() {
  # _log <LVL> <message...>  -- timestamped, prog-tagged, to the log fd.
  local lvl="$1"; shift
  printf '[%s] [%s] [%s] %s\n' \
    "$PROG" "$lvl" "$(date +'%Y%m%dT%H%M%S')" "$*" >&"$SANDBOX_LOG_FD"
}
trace() { if [ "$SANDBOX_VERBOSE" -ge 3 ]; then _log TRC "$@"; fi; }
debug() { if [ "$SANDBOX_VERBOSE" -ge 2 ]; then _log DBG "$@"; fi; }
info()  { if [ "$SANDBOX_VERBOSE" -ge 1 ]; then _log NFO "$@"; fi; }
warn()  { _log WRN "$@"; }
err()   { _log ERR "$@"; }

# die <exit-code> <message...> -- log at ERR and exit with a DISTINCT code.
# The code is forwarded verbatim; callers use the EX_* constants so the scheme
# stays stable and greppable. Never collapses to 255 (the krunvm anti-pattern).
die() {
  local code="$1"; shift
  err "$@"
  exit "$code"
}

# ============================================================================
# Self-documenting usage(). Greps THIS script's own `# VERB:` and `# FLAG:`
# doc-comment lines and reformats them, so help can never drift from the
# dispatch table or the parser (the gh-runner-krunvm idiom, extended to flags).
#
# Contract for the integrator: keep the canonical `# VERB:` block (already in A's
# spine) AND add the `# FLAG:` block below near the parser. usage() renders both.
# It also accepts an optional verb name ($2) to scope verb help to one verb.
# ============================================================================

# FLAG: --cpus N            vCPUs -> krun.cpus annotation (integer, clamped)
# FLAG: --memory MiB        guest RAM -> krun.ram_mib annotation (integer, clamped)
# FLAG: --network none|loopback  default none; --publish is a no-op under none
# FLAG: --publish HOST:GUEST publish to localhost only (loopback network only)
# FLAG: --mount HOST:GUEST[:ro]  extra mount; defaults read-only
# FLAG: --env K=V           set a guest environment variable (repeatable)
# FLAG: --workdir DIR       guest working directory
# FLAG: --ssh-agent         forward $SSH_AUTH_SOCK; keys never enter the guest
# FLAG: -it                 allocate an interactive TTY
# FLAG: --timeout DUR       bound foreground runtime (e.g. 30s, 5m, 2h)
# FLAG: --json              machine-readable output (read/doctor/reap verbs)
# FLAG: --name N            sandbox name (required by keep; label-only selector)

usage() {
  # usage [exit-code] [verb]
  local code="${1:-0}" only_verb="${2:-}"

  # Header + verb table go to stderr so a bare `sandbox` piped somewhere never
  # pollutes a consumer's stdout with help text.
  {
    printf '%s %s -- disciplined podman+krun microVM sandbox (accident-model isolation)\n\n' \
      "$PROG" "$SANDBOX_VERSION"
    printf 'USAGE: %s <verb> [flags] [args] [-- workload...]\n\n' "$PROG"
    printf 'VERBS:\n'
    # Self-document: reformat the `# VERB:` doc-comments from this script.
    if [ -n "$only_verb" ]; then
      grep -E "^# VERB: ${only_verb}([[:space:]]|\$)" "$0" | sed -E 's/^# VERB: /  /'
    else
      grep -E '^# VERB: ' "$0" | sed -E 's/^# VERB: /  /'
    fi

    printf '\nCOMMON FLAGS (birth verbs run/keep; subset honoured by exec/start):\n'
    # Self-document the flags the same way -> zero parser/help drift.
    grep -E '^# FLAG: ' "$0" | sed -E 's/^# FLAG: /  /'

    cat <<EOF

ENVIRONMENT (flags win over env; env wins over built-in defaults):
  SANDBOX_ROOT         managed root (default ~/.local/share/sandbox)
  SANDBOX_RUNTIME      OCI runtime (default krun)
  SANDBOX_BASE_IMAGE   doctor smoke-test image
  SANDBOX_VERBOSE      0=warn/err 1=info 2=debug 3=trace (default 1)
  SANDBOX_LOG_FD       fd for diagnostics (default 2 = stderr)
  SANDBOX_CPUS         default --cpus    SANDBOX_MEMORY default --memory (MiB)
  SANDBOX_NETWORK      default --network (none|loopback)

EXIT CODES (stable & distinct; workload code forwarded verbatim, never 255):
  0                success / workload exited 0
  <n>             a propagated WORKLOAD exit code (run/keep/exec)
  ${EX_USAGE}              EX_USAGE        malformed invocation / bad flag
  ${EX_PRECONDITION}              EX_PRECONDITION doctor / per-verb precheck failed
  ${EX_LAUNCH}              EX_LAUNCH       engine failed to launch the sandbox
  ${EX_GUARD}              EX_GUARD        a safety guard refused (unpushed/unsafe path)
  ${EX_NOTFOUND}              EX_NOTFOUND     named sandbox not found in our labelled set
EOF
  } >&2
  exit "$code"
}

# ============================================================================
# base64 command-transport (ERA's trick). Encode arbitrary agent-written code
# host-side, decode in-guest, hand to `bash` -- dodging every layer of shell
# quoting between host argv, podman, and the guest shell.
#
# encode_workload <word...>  -> prints the in-guest argv as NUL-free words on
# stdout, one per line, ready to be read into an array with `mapfile`. The caller
# appends these to the podman/exec argv after the image / container id.
#
# We DELIBERATELY transport the words joined with single spaces. Agent code that
# needs exact whitespace should pass a single quoted word; the base64 layer
# preserves whatever bytes are in the joined payload verbatim. The in-guest
# wrapper is POSIX `/bin/sh` (always present) which pipes the decoded bytes into
# `bash`, so the workload runs under bash without us shell-quoting it.
#
# DEVIATION from A: A used  `/bin/sh -c "echo ${b64} | base64 -d | exec bash -s"`.
# Two bugs: (1) `echo` is not portable for arbitrary data (mangles leading `-`,
# interprets backslashes under some shells); (2) `exec bash -s` after a pipe
# reads the script from the pipe but `-s` + a pipe is fragile and loses `$0`/argv
# framing. This version uses `printf %s` (byte-faithful) and `bash -s` reading
# stdin as the script, with no `exec`, no `echo`.
# ============================================================================
encode_workload() {
  local payload b64
  # Join the workload words with single spaces (a command line for bash -c).
  payload="$(printf '%s ' "$@")"
  payload="${payload% }"
  b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
  # Emit the in-guest argv, one word per line, for the caller's `mapfile`.
  printf '%s\n' '/bin/sh'
  printf '%s\n' '-c'
  printf '%s\n' "printf %s '${b64}' | base64 -d | bash -s"
}

# ============================================================================
# Machine-readable output helpers. stdout carries ONLY parseable data; all
# human/diagnostic text goes through the log fd (stderr by default).
# ============================================================================

# emit_kv k v k v ...  -- stable, greppable `key<TAB>value` lines to stdout.
# Used by single-object verbs (keep/start) for non-JSON machine output.
emit_kv() {
  while [ "$#" -ge 2 ]; do
    printf '%s\t%s\n' "$1" "$2"
    shift 2
  done
}

# json_escape <string>  -- minimal RFC-8259 string-body escaping for our
# hand-rolled JSON (we control the key set; values are labels/messages/ids).
json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"     # backslash first
  s="${s//\"/\\\"}"     # quotes
  s="${s//	/\\t}"      # literal TAB -> \t
  # Strip any other control chars (newlines etc.) defensively.
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# ============================================================================
# Validation / utility helpers (D owns the parser-facing validators).
# ============================================================================

# is_uint <value> -> 0 if a non-negative base-10 integer.
is_uint() { [[ "${1-}" =~ ^[0-9]+$ ]]; }

# clamp <value> <min> <max> -> prints the value pinned into [min,max].
clamp() {
  local v="$1" lo="$2" hi="$3"
  if (( v < lo )); then v="$lo"; fi
  if (( v > hi )); then v="$hi"; fi
  printf '%s' "$v"
}

# require_uint <value> <flag-name> -- die EX_USAGE if not a non-negative integer.
require_uint() {
  is_uint "${1-}" || die "$EX_USAGE" "$2 must be a non-negative integer, got: '${1-}'"
}

# need_arg <count-remaining> <flag>  -- guard against a flag at end-of-args.
# Call as `need_arg "$#" "$1"` from inside the parser loop BEFORE touching "$2".
# It only validates (and dies on a missing value); it does NOT print the value,
# so the caller reads "$2" directly. This avoids the subtle `set -e` trap where a
# `die` inside `x="$(need_arg ...)"` would be SWALLOWED (command-substitution
# exit status is not checked by `set -e` in an assignment) -- a real bug we hit
# and fixed: the value must never be plucked through a subshell.
need_arg() {
  if [ "$1" -lt 2 ]; then
    die "$EX_USAGE" "$2 requires a value"
  fi
}

# duration_to_secs <dur> -- parse 30s / 5m / 2h / 1d / bare-seconds -> seconds.
duration_to_secs() {
  local d="${1-}" n unit
  if [[ "$d" =~ ^([0-9]+)([smhd]?)$ ]]; then
    n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]:-s}"
    case "$unit" in
      s) printf '%s' "$n" ;;
      m) printf '%s' "$(( n * 60 ))" ;;
      h) printf '%s' "$(( n * 3600 ))" ;;
      d) printf '%s' "$(( n * 86400 ))" ;;
    esac
  else
    die "$EX_USAGE" "invalid duration: '$d' (use e.g. 30s, 5m, 2h, 1d)"
  fi
}

# ============================================================================
# Per-invocation option state + reset. Flags+env duality lives HERE: reset_opts
# seeds every OPT_* from `${SANDBOX_*:-default}` so an env value is the default
# and a parsed flag (set later in parse_birth_args) WINS by overwriting it.
#
# DEVIATION from A: A's reset_opts hard-coded the defaults (DEF_CPUS etc.) with
# no env duality. The brief mandates flags+env duality via ${VAR:-default} with
# flags winning; this is the single correct place to implement it (the parser
# overwrites these AFTER reset_opts runs).
# ============================================================================
reset_opts() {
  EXTRA_MOUNTS=(); EXTRA_ENV=(); PUBLISH_PORTS=(); WORKLOAD_CMD=()
  OPT_CPUS="${SANDBOX_CPUS:-$DEF_CPUS}"
  OPT_MEMORY="${SANDBOX_MEMORY:-$DEF_MEMORY}"
  OPT_NETWORK="${SANDBOX_NETWORK:-none}"
  OPT_WORKDIR=""
  OPT_SSH_AGENT=0
  OPT_TTY=0
  OPT_TIMEOUT=""
  OPT_JSON=0
  OPT_NAME=""
  OPT_FORCE=0
  OPT_KEEP_WORKTREE=0
  OPT_ALL=0
  OPT_FOLLOW=0
  OPT_TAIL=200
  OPT_DRYRUN=0
  OPT_UNTIL=""
}

# ============================================================================
# Shared birth-verb argument parser (run + keep). Populates OPT_* / EXTRA_* /
# PUBLISH_PORTS, sets PARSED_IMAGE and WORKLOAD_CMD.
#
# Grammar (enforced):  <flags...> <image> [-- workload...]
#   * Flags MUST precede the image (a positional after the image, before --, is
#     an error -- the workload goes after --).
#   * Everything after the first bare `--` is passed VERBATIM to the guest and is
#     NOT re-parsed (so a workload may itself contain `--flags`).
#
# Every option-argument is consumed through need_arg so a trailing flag with no
# value fails as EX_USAGE instead of crashing under `set -u`.
# ============================================================================
parse_birth_args() {
  local verb="$1"; shift
  reset_opts
  PARSED_IMAGE=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cpus)      need_arg "$#" --cpus;    OPT_CPUS="$2"; shift ;;
      --memory)    need_arg "$#" --memory;  OPT_MEMORY="$2"; shift ;;
      --network)   need_arg "$#" --network; OPT_NETWORK="$2"; shift ;;
      --publish|-p) need_arg "$#" --publish; PUBLISH_PORTS+=("$2"); shift ;;
      --mount|-v)  need_arg "$#" --mount;   EXTRA_MOUNTS+=("$2"); shift ;;
      --env|-e)    need_arg "$#" --env;     EXTRA_ENV+=("$2"); shift ;;
      --workdir|-w) need_arg "$#" --workdir; OPT_WORKDIR="$2"; shift ;;
      --ssh-agent) OPT_SSH_AGENT=1 ;;
      -it|-ti|-i|-t) OPT_TTY=1 ;;
      --timeout)   need_arg "$#" --timeout; OPT_TIMEOUT="$2"; shift ;;
      --json)      OPT_JSON=1 ;;
      --name)      need_arg "$#" --name;    OPT_NAME="$2"; shift ;;
      -h|--help)   usage 0 "$verb" ;;
      --)          shift; WORKLOAD_CMD=("$@"); break ;;
      --*=*)
        # Support --flag=value form by splitting and re-dispatching once.
        local _k="${1%%=*}" _val="${1#*=}"
        set -- "$_k" "$_val" "${@:2}"
        continue
        ;;
      -*)          die "$EX_USAGE" "$verb: unknown flag '$1' (try '$PROG $verb --help')" ;;
      *)
        if [ -z "$PARSED_IMAGE" ]; then
          PARSED_IMAGE="$1"
        else
          die "$EX_USAGE" "$verb: unexpected positional '$1' (workload goes after --)"
        fi
        ;;
    esac
    shift
  done
}

# ============================================================================
# Read-verb output: ls. Machine-readable BY DEFAULT (stable TSV columns), with
# --json deferring straight to podman's own template engine. Selection is
# EXCLUSIVELY by the managed-by label (our_filter); diagnostics to stderr.
#
# DEVIATION from A: behaviour-preserving, but the per-flag loop now uses the same
# bounds-safe / -h handling as the other verbs, and the header row is suppressed
# under --json (a header would corrupt a JSON-lines consumer).
# ============================================================================
verb_ls() {
  local all=0 json=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -a|--all)  all=1 ;;
      --json)    json=1 ;;
      -h|--help) usage 0 ls ;;
      --)        shift; break ;;
      *)         die "$EX_USAGE" "ls: unexpected arg '$1'" ;;
    esac
    shift
  done

  local -a psargs=(ps --filter "$(our_filter)")
  [ "$all" = 1 ] && psargs+=(-a)

  if [ "$json" = 1 ]; then
    # podman emits one JSON object per line; already machine-readable.
    podman_q "${psargs[@]}" --format \
      '{"id":"{{.ID}}","name":"{{index .Labels "'"${LBL_NAME}"'"}}","status":"{{.Status}}","created":"{{index .Labels "'"${LBL_CREATED}"'"}}","worktree":"{{index .Labels "'"${LBL_WORKTREE}"'"}}","persist":"{{index .Labels "'"${LBL_PERSIST}"'"}}","ports":"{{.Ports}}"}'
  else
    printf 'ID\tNAME\tSTATUS\tPERSIST\tPORTS\tWORKTREE\tCREATED\n'
    podman_q "${psargs[@]}" --format \
      '{{.ID}}	{{index .Labels "'"${LBL_NAME}"'"}}	{{.Status}}	{{index .Labels "'"${LBL_PERSIST}"'"}}	{{.Ports}}	{{index .Labels "'"${LBL_WORKTREE}"'"}}	{{index .Labels "'"${LBL_CREATED}"'"}}'
  fi
}

# ============================================================================
# Top-level dispatch. Forwards the FULL remaining argv to each verb (so a verb's
# own parser owns its flags), routes --version/--help to stdout/stderr correctly,
# and never collapses an unknown verb to a generic 255.
#
# DEVIATION from A: A's `doctor) run_doctor "${1:-}"` dropped all but the first
# arg and could pass an empty string as a spurious "argument"; here doctor gets
# the full "$@" and parses --json itself. `version` prints to STDOUT (it is data
# a script may capture), while help goes to stderr.
# ============================================================================
main() {
  [ "$#" -ge 1 ] || usage "$EX_USAGE"
  local verb="$1"; shift
  case "$verb" in
    doctor)        run_doctor "$@" ;;
    run)           verb_run "$@" ;;
    keep)          verb_keep "$@" ;;
    start)         verb_start "$@" ;;
    exec)          verb_exec "$@" ;;
    logs)          verb_logs "$@" ;;
    ls|list)       verb_ls "$@" ;;
    inspect)       verb_inspect "$@" ;;
    stop)          verb_stop "$@" ;;
    rm|remove)     verb_rm "$@" ;;
    reap)          verb_reap "$@" ;;
    -h|--help|help) usage 0 ;;
    --version|version) printf '%s %s\n' "$PROG" "$SANDBOX_VERSION" ;;
    *)             die "$EX_USAGE" "unknown verb: '$verb' (try '$PROG --help')" ;;
  esac
}

# ----------------------------------------------------------------------------
# Standalone-parse scaffolding ONLY (the integrator deletes this block; the real
# definitions live in A's spine). Present so `bash -n` can parse this section in
# isolation without tripping `set -u` on the spine's constants.
# ----------------------------------------------------------------------------
: "${PROG:=sandbox}"
: "${SANDBOX_VERSION:=0.0.0}"
: "${SANDBOX_VERBOSE:=1}"
: "${SANDBOX_LOG_FD:=2}"
: "${DEF_CPUS:=1}"
: "${DEF_MEMORY:=1024}"
: "${EX_USAGE:=64}"
: "${EX_PRECONDITION:=69}"
: "${EX_LAUNCH:=70}"
: "${EX_GUARD:=71}"
: "${EX_NOTFOUND:=72}"
