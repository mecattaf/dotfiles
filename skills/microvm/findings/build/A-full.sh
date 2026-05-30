#!/usr/bin/env bash
#
# sandbox -- a disciplined single-file wrapper over `podman run --runtime=krun`.
#
# Threat model: ACCIDENT, not adversary. We sandbox the WORKLOAD a coding agent
# writes/runs so its clumsy code cannot damage the host. No daemon, no state
# file, no login. Podman LABELS are the single source of truth.
#
# Engine: podman + crun-krun + libkrun + libkrunfw (official Fedora packages).
# Selection is EXCLUSIVELY by `--filter label=sandbox.managed-by=<us>` -- never
# by name substring. Every isolation flag reaches a real engine arg and is
# assertable by `doctor`.
#
# THIS IS A STAGE-3 DRAFT (Agent A spine). Not yet installed.

set -euo pipefail

# ============================================================================
# Constants / identity
# ============================================================================

readonly SANDBOX_VERSION="0.1.0-draft"
readonly MANAGED_BY="sandbox"          # value of the sandbox.managed-by label
readonly LABEL_NS="sandbox"            # label namespace prefix

# Label keys (the mandatory set + persistence markers).
readonly LBL_MANAGED="${LABEL_NS}.managed-by"
readonly LBL_CREATED="${LABEL_NS}.created"
readonly LBL_ID="${LABEL_NS}.id"
readonly LBL_WORKTREE="${LABEL_NS}.worktree"
readonly LBL_PERSIST="${LABEL_NS}.persist"
readonly LBL_NAME="${LABEL_NS}.name"

# The single managed root the tool owns. Worktrees live ONLY under here, and
# `is_safe_cache_path` refuses to delete anything outside it.
SANDBOX_ROOT="${SANDBOX_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/sandbox}"
readonly WORKTREE_ROOT="${SANDBOX_ROOT}/worktrees"

# Runtime handler. crun-krun is the Fedora package name; the OCI runtime that
# podman invokes is `krun`. We default to `krun` and let doctor verify it.
SANDBOX_RUNTIME="${SANDBOX_RUNTIME:-krun}"

# Canonical base image used by doctor's smoke test (and as a sane default).
SANDBOX_BASE_IMAGE="${SANDBOX_BASE_IMAGE:-registry.fedoraproject.org/fedora-minimal:latest}"

# ============================================================================
# Exit-code scheme (stable, distinct, documented)
# ============================================================================
# 0          success / workload exited 0
# 1          generic usage / argument error
# <n>        a propagated WORKLOAD exit code (run/keep/exec forward it verbatim)
# 64         EX_USAGE        -- malformed invocation
# 69         EX_PRECONDITION -- doctor / per-verb precheck failed (krun unusable)
# 70         EX_LAUNCH       -- the engine failed to launch the sandbox
# 71         EX_GUARD        -- a safety guard refused (unpushed commits, unsafe path)
# 72         EX_NOTFOUND     -- named sandbox not found among our labelled set
# These are deliberately NOT 255 (the krunvm collapse-everything anti-pattern).
readonly EX_USAGE=64
readonly EX_PRECONDITION=69
readonly EX_LAUNCH=70
readonly EX_GUARD=71
readonly EX_NOTFOUND=72

# ============================================================================
# Leveled logging (gh-runner-krunvm style). All diagnostics go to an fd
# (default stderr=2) so stdout stays pipeable / machine-readable.
# ============================================================================

SANDBOX_VERBOSE="${SANDBOX_VERBOSE:-1}"   # 0=warn/err 1=info 2=debug 3=trace
SANDBOX_LOG_FD="${SANDBOX_LOG_FD:-2}"     # fd to write diagnostics to
PROG="$(basename "$0")"

_log() {
  local lvl="$1"; shift
  printf '[%s] [%s] %s\n' "$PROG" "$lvl" "$*" >&"$SANDBOX_LOG_FD"
}
trace() { [ "$SANDBOX_VERBOSE" -ge 3 ] && _log TRC "$@" || true; }
debug() { [ "$SANDBOX_VERBOSE" -ge 2 ] && _log DBG "$@" || true; }
info()  { [ "$SANDBOX_VERBOSE" -ge 1 ] && _log NFO "$@" || true; }
warn()  { _log WRN "$@"; }
err()   { _log ERR "$@"; }

# die <exit-code> <message...>
die() {
  local code="$1"; shift
  err "$@"
  exit "$code"
}

# ============================================================================
# Self-documenting usage(). Greps this script's own option-comment lines so
# help can never drift from the parser (gh-runner-krunvm idiom). Verb help is
# emitted by grepping the `# VERB:` doc-comments below.
# ============================================================================

# VERB: doctor   [--json]                                 verb-zero: probe host krun capability
# VERB: run      [flags] <image> [-- cmd...]              ephemeral one-shot (--rm always; foreground)
# VERB: keep     --name N [flags] <image> [-- cmd...]     PERSISTENT sandbox (survives exit; loud)
# VERB: start    [-it] <name>                             restart a stopped kept sandbox
# VERB: exec     [flags] <name> -- cmd...                 run a cmd in a RUNNING kept sandbox (no auto-start)
# VERB: logs     [-f] [-n N] <name>                       post-mortem stdout/stderr
# VERB: ls       [-a] [--json]                            list managed sandboxes (machine-readable)
# VERB: inspect  [--json] <name>                          single-object config/status
# VERB: stop     [-f] [-t S] <name...>                    graceful stop of kept sandboxes
# VERB: rm       [-f] [--keep-worktree] <name...>         teardown kept sandbox + its worktree
# VERB: reap     [--until DUR] [--dry-run] [--json]       label-driven Layer-3 backstop

usage() {
  local code="${1:-0}"
  cat >&2 <<EOF
$PROG $SANDBOX_VERSION -- disciplined podman+krun microVM sandbox (accident-model isolation)

USAGE: $PROG <verb> [flags] [args]

VERBS:
EOF
  # Self-document: reformat the `# VERB:` doc-comments above.
  grep -E '^# VERB: ' "$0" | sed -E 's/^# VERB: /  /' >&2

  cat >&2 <<EOF

COMMON FLAGS (birth verbs run/keep):
  --cpus N             vCPUs            -> krun.cpus annotation (integer, clamped 1..${KRUN_MAX_VCPU})
  --memory MiB         guest RAM        -> krun.ram_mib annotation (integer, clamped ${KRUN_MIN_MIB}..${KRUN_MAX_MIB})
  --network none|loopback   default none; --publish is a no-op under none
  --publish HOST:GUEST publish to localhost (loopback only)
  --mount HOST:GUEST[:ro]   extra mount; read-only ergonomics
  --env K=V            set guest env var
  --workdir DIR        guest working directory
  --ssh-agent          forward \$SSH_AUTH_SOCK (keys never enter the guest)
  -it                  allocate an interactive TTY
  --timeout DUR        bound foreground runtime (e.g. 30s, 5m)
  --json               machine-readable output (read verbs)

ENVIRONMENT:
  SANDBOX_ROOT         managed root (default ~/.local/share/sandbox)
  SANDBOX_RUNTIME      OCI runtime (default krun)
  SANDBOX_BASE_IMAGE   doctor smoke-test image
  SANDBOX_VERBOSE      0=quiet 1=info 2=debug 3=trace (default 1)

EXIT CODES: 0 ok | <n> workload code | $EX_USAGE usage | $EX_PRECONDITION precondition |
            $EX_LAUNCH launch | $EX_GUARD guard-refused | $EX_NOTFOUND not-found
EOF
  exit "$code"
}

# ============================================================================
# Resource-clamp bounds (krun annotation knobs). krun FATALS on a malformed
# value and SILENTLY IGNORES ram_mib<=128, so we validate as integers in bash.
# ============================================================================
readonly KRUN_MIN_MIB=256       # floor above krun's silent-ignore <=128
readonly KRUN_MAX_MIB=16384
readonly KRUN_MAX_VCPU=16
readonly DEF_CPUS=1
readonly DEF_MEMORY=1024

# ============================================================================
# Small validation / utility helpers
# ============================================================================

# is_uint <value> -> 0 if a non-negative base-10 integer
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# clamp <value> <min> <max>
clamp() {
  local v="$1" lo="$2" hi="$3"
  (( v < lo )) && v="$lo"
  (( v > hi )) && v="$hi"
  printf '%s' "$v"
}

# require_uint <value> <flag-name> -- die EX_USAGE if not an integer
require_uint() {
  is_uint "$1" || die "$EX_USAGE" "$2 must be a non-negative integer, got: '$1'"
}

# parse a duration like 30s / 5m / 2h / 90 (bare == seconds) into seconds.
duration_to_secs() {
  local d="$1" n unit
  if [[ "$d" =~ ^([0-9]+)([smhd]?)$ ]]; then
    n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]:-s}"
    case "$unit" in
      s) printf '%s' "$n" ;;
      m) printf '%s' $(( n * 60 )) ;;
      h) printf '%s' $(( n * 3600 )) ;;
      d) printf '%s' $(( n * 86400 )) ;;
    esac
  else
    die "$EX_USAGE" "invalid duration: '$d' (use e.g. 30s, 5m, 2h)"
  fi
}

# Generate a short random id (worktree + label identity).
gen_id() { LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 10; }

# podman wrapper so the binary is overridable in tests and every call is logged.
PODMAN="${PODMAN:-podman}"
podman_q() { trace "podman $*"; "$PODMAN" "$@"; }

# ============================================================================
# Label-scoped selection helpers (NEVER name substring).
# ============================================================================

# our_filter: the mandatory managed-by filter every selection passes through.
our_filter() { printf '%s' "label=${LBL_MANAGED}=${MANAGED_BY}"; }

# resolve_managed <name>  -> prints the container id, or fails EX_NOTFOUND.
# Matches by the sandbox.name label AND the managed-by label (AND-combined),
# so we can only ever resolve sandboxes we ourselves stamped.
resolve_managed() {
  local name="$1" id
  id="$(podman_q ps -a -q \
        --filter "$(our_filter)" \
        --filter "label=${LBL_NAME}=${name}" 2>/dev/null | head -n1)"
  if [ -z "$id" ]; then
    die "$EX_NOTFOUND" "no managed sandbox named '$name' (selection is label-only)"
  fi
  printf '%s' "$id"
}

# is_managed <name-or-id> -> 0 if it bears our managed-by label.
is_managed() {
  local ref="$1" got
  got="$(podman_q inspect --format \
        "{{ index .Config.Labels \"${LBL_MANAGED}\" }}" "$ref" 2>/dev/null || true)"
  [ "$got" = "$MANAGED_BY" ]
}

# container_state <id> -> running|exited|created|...
container_state() {
  podman_q inspect --format '{{.State.Status}}' "$1" 2>/dev/null || printf 'unknown'
}

# ============================================================================
# doctor -- verb-zero capability probe. Read-only. Fails CLOSED with a distinct
# precondition exit code and an actionable message. Every other verb calls
# precheck() (a cheap subset) before doing work.
# ============================================================================

# A single check row. Accumulates PASS/FAIL into globals for --json emission.
declare -a DOCTOR_NAMES=() DOCTOR_OK=() DOCTOR_MSG=()
_dr() {  # _dr <name> <ok 0|1> <message>
  DOCTOR_NAMES+=("$1"); DOCTOR_OK+=("$2"); DOCTOR_MSG+=("$3")
}

# Individual probes. Each returns 0/1 and records a row + actionable fix.

probe_kvm() {
  if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    _dr kvm 0 "/dev/kvm present and accessible"; return 0
  fi
  if [ -e /dev/kvm ]; then
    _dr kvm 1 "/dev/kvm not accessible -- run: sudo usermod -aG kvm \"\$USER\" and re-login"
  else
    _dr kvm 1 "/dev/kvm missing -- nested virt / KVM not available on this host"
  fi
  return 1
}

probe_podman() {
  if command -v "$PODMAN" >/dev/null 2>&1 && podman_q info >/dev/null 2>&1; then
    _dr podman 0 "podman present ($("$PODMAN" --version 2>/dev/null | head -n1))"; return 0
  fi
  _dr podman 1 "podman not usable -- install podman and verify 'podman info'"
  return 1
}

probe_runtime_registered() {
  # The runtime must be known to podman (configured in containers.conf or on PATH).
  if podman_q info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null | grep -qi "krun" \
     || command -v "crun-krun" >/dev/null 2>&1 \
     || command -v "$SANDBOX_RUNTIME" >/dev/null 2>&1; then
    _dr runtime 0 "krun runtime '$SANDBOX_RUNTIME' resolvable"; return 0
  fi
  _dr runtime 1 "runtime '$SANDBOX_RUNTIME' not registered -- install crun-krun and configure podman"
  return 1
}

probe_crun_libkrun() {
  # crun must report +LIBKRUN in its feature string.
  local v=""
  if command -v crun >/dev/null 2>&1; then
    v="$(crun --version 2>/dev/null || true)"
  fi
  if printf '%s' "$v" | grep -qi 'LIBKRUN'; then
    _dr crun_libkrun 0 "crun built with +LIBKRUN"; return 0
  fi
  _dr crun_libkrun 1 "crun lacks +LIBKRUN -- install the crun-krun handler package"
  return 1
}

probe_libkrun_so() {
  # libkrun.so.1 + an ABI-compatible libkrunfw must be loadable.
  # We accept presence on the loader path; an exact soname matrix is an open
  # question handed to the build -- we accept libkrun.so.1 and any libkrunfw.so.*.
  local found_krun=0 found_fw=0 d
  for d in /usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib; do
    [ -e "$d/libkrun.so.1" ] && found_krun=1
    # shellcheck disable=SC2144
    ls "$d"/libkrunfw.so.* >/dev/null 2>&1 && found_fw=1
  done
  if [ "$found_krun" = 1 ] && [ "$found_fw" = 1 ]; then
    _dr libkrun 0 "libkrun.so.1 and libkrunfw present"; return 0
  fi
  _dr libkrun 1 "libkrun.so.1 / libkrunfw not found -- install libkrun + libkrunfw"
  return 1
}

probe_smoke() {
  # The decisive end-to-end gate: a --rm --network none `true` under our runtime.
  # Read-only in spirit (nothing persists). Skipped if a prior hard gate failed.
  if podman_q run --rm --runtime "$SANDBOX_RUNTIME" --network none \
        "$SANDBOX_BASE_IMAGE" true >/dev/null 2>&1; then
    _dr smoke 0 "smoke run (--rm --network none true) succeeded"; return 0
  fi
  _dr smoke 1 "smoke run failed -- krun cannot launch a microVM (see prior checks)"
  return 1
}

# Emit accumulated doctor rows. JSON when $1=json, else a PASS/FAIL table.
doctor_emit() {
  local mode="$1" i n="${#DOCTOR_NAMES[@]}"
  if [ "$mode" = json ]; then
    printf '{"version":"%s","checks":[' "$SANDBOX_VERSION"
    for (( i=0; i<n; i++ )); do
      [ "$i" -gt 0 ] && printf ','
      printf '{"name":"%s","ok":%s,"message":"%s"}' \
        "${DOCTOR_NAMES[$i]}" \
        "$([ "${DOCTOR_OK[$i]}" = 0 ] && echo true || echo false)" \
        "$(json_escape "${DOCTOR_MSG[$i]}")"
    done
    printf ']}\n'
  else
    for (( i=0; i<n; i++ )); do
      if [ "${DOCTOR_OK[$i]}" = 0 ]; then
        printf '  PASS  %-14s %s\n' "${DOCTOR_NAMES[$i]}" "${DOCTOR_MSG[$i]}" >&2
      else
        printf '  FAIL  %-14s %s\n' "${DOCTOR_NAMES[$i]}" "${DOCTOR_MSG[$i]}" >&2
      fi
    done
  fi
}

# json_escape: minimal escaping for embedding strings in our hand-rolled JSON.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# run_doctor [--json] -- the full verbose gate. Exits EX_PRECONDITION on any fail.
run_doctor() {
  local mode=table
  [ "${1:-}" = "--json" ] && mode=json
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()

  local hard_ok=0
  probe_kvm           || hard_ok=1
  probe_podman        || hard_ok=1
  probe_crun_libkrun  || hard_ok=1
  probe_libkrun_so    || hard_ok=1
  probe_runtime_registered || hard_ok=1
  # Only attempt the (expensive) smoke run if hard gates passed.
  if [ "$hard_ok" = 0 ]; then
    probe_smoke || hard_ok=1
  else
    _dr smoke 1 "smoke run skipped -- a prior gate failed"
  fi

  doctor_emit "$mode"
  if [ "$hard_ok" != 0 ]; then
    [ "$mode" = table ] && err "doctor: host is NOT ready for krun sandboxes"
    exit "$EX_PRECONDITION"
  fi
  [ "$mode" = table ] && info "doctor: all gates passed"
  return 0
}

# precheck -- the cheap subset run silently at the top of birth/lifecycle verbs.
# Does NOT run the smoke container (too expensive for every invocation).
precheck() {
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()
  local ok=0
  probe_kvm    >/dev/null 2>&1 || ok=1
  probe_podman >/dev/null 2>&1 || ok=1
  probe_runtime_registered >/dev/null 2>&1 || ok=1
  if [ "$ok" != 0 ]; then
    die "$EX_PRECONDITION" "precondition failed -- run '$PROG doctor' for details"
  fi
}

# ============================================================================
# Worktree management. The tool CREATES the worktree (never accepts a pre-made
# one). Removal is path-safety-gated AND unpushed-commit-guarded.
# ============================================================================

# worktree_path <id> -> the canonical managed path for this sandbox.
worktree_path() { printf '%s/%s' "$WORKTREE_ROOT" "$1"; }

# is_safe_cache_path <path> -- smolvm's guard, verbatim in spirit.
# Refuses unless: non-empty arg, strictly inside WORKTREE_ROOT, not equal to the
# root, not a symlink, exists as a directory. Returns 0 only when safe to remove.
is_safe_cache_path() {
  local p="${1:-}"
  [ -n "$p" ]                                  || { trace "guard: empty path"; return 1; }
  [ -d "$p" ]                                  || { trace "guard: not a dir";  return 1; }
  [ ! -L "$p" ]                                || { trace "guard: symlink";    return 1; }
  # Canonicalize and confirm strict containment within WORKTREE_ROOT.
  local rp rroot
  rp="$(cd -P -- "$p" 2>/dev/null && pwd -P)"   || return 1
  rroot="$(cd -P -- "$WORKTREE_ROOT" 2>/dev/null && pwd -P)" || return 1
  [ "$rp" != "$rroot" ]                        || { trace "guard: is root";    return 1; }
  case "$rp/" in
    "$rroot"/*) : ;;
    *) trace "guard: outside managed root"; return 1 ;;
  esac
  return 0
}

# has_unpushed_commits <worktree> -- 0 if the worktree has commits/changes that
# are not pushed to an upstream OR uncommitted changes. Conservative: if we
# cannot determine upstream state, we treat it as unpushed (fail-safe).
has_unpushed_commits() {
  local wt="$1"
  git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  # Uncommitted changes?
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    return 0
  fi
  # Commits not on an upstream? If no upstream is set, any local commits count.
  local upstream
  if upstream="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    [ -n "$(git -C "$wt" rev-list "${upstream}..HEAD" 2>/dev/null)" ] && return 0
  else
    # No upstream: any commit beyond the base ref is potentially unpushed.
    [ -n "$(git -C "$wt" rev-list HEAD 2>/dev/null | head -n1)" ] && return 0
  fi
  return 1
}

# create_worktree <id> -- create the per-sandbox worktree. If invoked inside a
# git repo, branch off HEAD into a managed worktree; otherwise create a plain
# managed directory (still rw-bound, still inside the managed root).
# Prints the resulting absolute path on stdout.
create_worktree() {
  local id="$1" wt
  wt="$(worktree_path "$id")"
  mkdir -p "$WORKTREE_ROOT"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch="sandbox/${id}"
    if git worktree add -b "$branch" "$wt" HEAD >/dev/null 2>&1; then
      debug "created git worktree $wt on branch $branch"
    else
      # Fall back to a plain dir if worktree add fails (e.g. detached/odd state).
      warn "git worktree add failed; using a plain managed directory"
      mkdir -p "$wt"
    fi
  else
    debug "not in a git repo; creating plain managed directory $wt"
    mkdir -p "$wt"
  fi
  printf '%s' "$wt"
}

# remove_worktree <worktree> <force 0|1> -- guarded teardown of a worktree.
# Returns 0 if removed (or already gone), EX_GUARD if a guard refused.
remove_worktree() {
  local wt="$1" force="${2:-0}"
  [ -n "$wt" ] || return 0
  [ -e "$wt" ] || { trace "worktree already gone: $wt"; return 0; }

  if ! is_safe_cache_path "$wt"; then
    warn "refusing to remove worktree outside managed root: $wt"
    return "$EX_GUARD"
  fi
  if has_unpushed_commits "$wt"; then
    if [ "$force" != 1 ]; then
      warn "worktree '$wt' has unpushed/uncommitted commits -- refusing (use -f to override)"
      return "$EX_GUARD"
    fi
    warn "worktree '$wt' has unpushed commits -- removing anyway (--force)"
  fi
  # Prefer git's own worktree removal so its administrative files stay consistent.
  if git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf -- "$wt"
  else
    rm -rf -- "$wt"
  fi
  debug "removed worktree $wt"
  return 0
}

# ============================================================================
# Centralized birth function. EVERY launch funnels through here. There is no
# second code path that creates a container. It stamps the mandatory label set
# and the safe-by-default isolation flags, then assembles the engine argv.
#
# It populates the global array BIRTH_ARGV with the full `podman run ...` args
# (excluding the leading `podman`) so callers can exec or capture as needed.
# ============================================================================

# Cross-cutting option state, reset per invocation by reset_opts().
declare -a EXTRA_MOUNTS EXTRA_ENV PUBLISH_PORTS WORKLOAD_CMD
OPT_CPUS="" OPT_MEMORY="" OPT_NETWORK="" OPT_WORKDIR=""
OPT_SSH_AGENT="" OPT_TTY="" OPT_TIMEOUT="" OPT_JSON="" OPT_NAME=""
OPT_FORCE="" OPT_KEEP_WORKTREE="" OPT_ALL="" OPT_FOLLOW="" OPT_TAIL=""
OPT_DRYRUN="" OPT_UNTIL=""

reset_opts() {
  EXTRA_MOUNTS=(); EXTRA_ENV=(); PUBLISH_PORTS=(); WORKLOAD_CMD=()
  OPT_CPUS="$DEF_CPUS"; OPT_MEMORY="$DEF_MEMORY"; OPT_NETWORK="none"
  OPT_WORKDIR=""; OPT_SSH_AGENT=0; OPT_TTY=0; OPT_TIMEOUT=""
  OPT_JSON=0; OPT_NAME=""; OPT_FORCE=0; OPT_KEEP_WORKTREE=0
  OPT_ALL=0; OPT_FOLLOW=0; OPT_TAIL=200; OPT_DRYRUN=0; OPT_UNTIL=""
}

declare -a BIRTH_ARGV
BIRTH_ID=""        # set by build_birth_argv for the trap/labels
BIRTH_WORKTREE=""  # set by build_birth_argv for trap rollback

# build_birth_argv <persist 0|1> <image>
# Assembles BIRTH_ARGV. Validates+clamps caps, stamps labels, applies the safe
# isolation posture, creates the worktree, wires ssh-agent / mounts / env / net.
build_birth_argv() {
  local persist="$1" image="$2"

  # --- validate + clamp resource caps (integer-validated; krun fatals else) ---
  require_uint "$OPT_CPUS" "--cpus"
  require_uint "$OPT_MEMORY" "--memory"
  local cpus mem
  cpus="$(clamp "$OPT_CPUS" 1 "$KRUN_MAX_VCPU")"
  mem="$(clamp "$OPT_MEMORY" "$KRUN_MIN_MIB" "$KRUN_MAX_MIB")"
  [ "$cpus" = "$OPT_CPUS" ] || warn "--cpus clamped to $cpus (bounds 1..$KRUN_MAX_VCPU)"
  [ "$mem" = "$OPT_MEMORY" ] || warn "--memory clamped to $mem MiB (bounds $KRUN_MIN_MIB..$KRUN_MAX_MIB)"

  # --- identity + worktree (the tool creates it) ---
  local id ts wt
  id="$(gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wt="$(create_worktree "$id")"
  BIRTH_ID="$id"
  BIRTH_WORKTREE="$wt"

  local -a argv=(run)

  # Ephemeral default vs persistence. run is unconditionally --rm; only keep omits it.
  if [ "$persist" = 1 ]; then
    [ -n "$OPT_NAME" ] || die "$EX_USAGE" "keep requires --name"
    argv+=(--name "$OPT_NAME" -d)
  else
    argv+=(--rm)
  fi

  argv+=(--runtime "$SANDBOX_RUNTIME")

  # --- mandatory label set (single source of truth) ---
  argv+=(--label "${LBL_MANAGED}=${MANAGED_BY}")
  argv+=(--label "${LBL_CREATED}=${ts}")
  argv+=(--label "${LBL_ID}=${id}")
  argv+=(--label "${LBL_WORKTREE}=${wt}")
  if [ "$persist" = 1 ]; then
    argv+=(--label "${LBL_PERSIST}=true")
    argv+=(--label "${LBL_NAME}=${OPT_NAME}")
  fi

  # --- safe-by-default isolation posture ---
  argv+=(--security-opt no-new-privileges)
  argv+=(--cap-drop ALL)
  # SELinux STAYS ON: we never pass label=disable. The worktree gets :Z (private
  # relabel) because we created it under our managed root -- never a shared dir.
  argv+=(--read-only)            # rootfs read-only; the worktree is the only rw surface

  # --- krun resource annotations (the real enforcing knobs) ---
  argv+=(--annotation "run.oci.krun.cpus=${cpus}")
  argv+=(--annotation "run.oci.krun.ram_mib=${mem}")

  # --- network posture ---
  case "$OPT_NETWORK" in
    none)
      argv+=(--network none)
      if [ "${#PUBLISH_PORTS[@]}" -gt 0 ]; then
        warn "--publish ignored: no-op under --network none (podman gotcha)"
      fi
      ;;
    loopback)
      # pasta/passt-backed userspace networking; publish binds to localhost only.
      argv+=(--network pasta)
      local p
      for p in "${PUBLISH_PORTS[@]}"; do
        # Force localhost binding so we never expose beyond the host loopback.
        argv+=(--publish "127.0.0.1:${p}")
      done
      ;;
    *)
      die "$EX_USAGE" "--network must be 'none' or 'loopback', got: '$OPT_NETWORK'"
      ;;
  esac

  # --- the single rw mount: the tool-created worktree, relabelled :Z ---
  local guest_workdir="${OPT_WORKDIR:-/workspace}"
  argv+=(--volume "${wt}:${guest_workdir}:Z")
  argv+=(--workdir "$guest_workdir")

  # --- extra mounts (read-only ergonomics; :ro honored, default ro) ---
  local m host guest ro
  for m in "${EXTRA_MOUNTS[@]}"; do
    host="${m%%:*}"
    local rest="${m#*:}"
    guest="${rest%%:*}"
    ro="${rest#*:}"
    if [ "$ro" = "ro" ] || [ "$ro" = "$guest" ]; then
      # default extra mounts to read-only unless explicitly something else
      argv+=(--volume "${host}:${guest}:ro")
    else
      argv+=(--volume "${host}:${guest}:${ro}")
    fi
  done

  # --- env ---
  local e
  for e in "${EXTRA_ENV[@]}"; do
    argv+=(--env "$e")
  done

  # --- ssh-agent forwarding: bind the socket, set the env var. Keys never
  #     enter the guest (only the agent socket is forwarded). ---
  if [ "$OPT_SSH_AGENT" = 1 ]; then
    [ -n "${SSH_AUTH_SOCK:-}" ] || die "$EX_GUARD" "--ssh-agent given but \$SSH_AUTH_SOCK is unset"
    [ -S "${SSH_AUTH_SOCK}" ]   || die "$EX_GUARD" "\$SSH_AUTH_SOCK is not a socket: ${SSH_AUTH_SOCK}"
    argv+=(--volume "${SSH_AUTH_SOCK}:/run/ssh-agent.sock")
    argv+=(--env "SSH_AUTH_SOCK=/run/ssh-agent.sock")
  fi

  # --- tty ---
  [ "$OPT_TTY" = 1 ] && argv+=(-it)

  # --- rlimits: a second cap layer beyond the krun annotations ---
  argv+=(--ulimit "nofile=1024:1024")
  argv+=(--ulimit "nproc=512:512")

  # --- image + workload (base64-transported to dodge shell-quoting bugs) ---
  argv+=("$image")
  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    local payload
    payload="$(printf '%s ' "${WORKLOAD_CMD[@]}")"
    payload="${payload% }"
    local b64
    b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    # Decode in-guest and hand to bash -c. Avoids host-side quoting hazards.
    argv+=(/bin/sh -c "echo ${b64} | base64 -d | exec bash -s")
    # Note: the precise in-guest decode wrapper is refined by Agent D; this is
    # the spine's safe transport contract (encode host-side, decode in-guest).
  fi

  BIRTH_ARGV=("${argv[@]}")
}

# ============================================================================
# Three-layer teardown.
#   Layer 1: --rm (clean exit) -- set on the run argv above for ephemeral.
#   Layer 2: trap on ERR/EXIT/INT/TERM -- rolls back a partially-born ephemeral
#            sandbox (and its worktree) using the trap-disarm-first idiom.
#   Layer 3: reap -- the label-driven backstop verb (below).
# ============================================================================

# State the trap rolls back. Set just before launch, cleared after clean exit.
TRAP_CONTAINER=""   # container id/name to force-remove on abnormal exit
TRAP_WORKTREE=""    # worktree to guard-remove on abnormal exit (ephemeral only)
TRAP_PERSIST=0      # if 1 (keep), the trap does NOT tear down on signal

ephemeral_trap() {
  local rc=$?
  # Trap-disarm-FIRST to prevent re-entrant double cleanup (gh-runner lesson).
  trap '' EXIT INT TERM ERR
  if [ "$TRAP_PERSIST" = 1 ]; then
    # Kept sandboxes are intentionally durable; never auto-destroy them.
    return 0
  fi
  if [ -n "$TRAP_CONTAINER" ]; then
    debug "trap: force-removing ephemeral container $TRAP_CONTAINER"
    podman_q rm -f -v "$TRAP_CONTAINER" >/dev/null 2>&1 || true
  fi
  if [ -n "$TRAP_WORKTREE" ]; then
    debug "trap: tearing down ephemeral worktree $TRAP_WORKTREE"
    # On crash we keep the worktree if it holds unpushed work (data-loss guard),
    # so use the guarded remover without force.
    remove_worktree "$TRAP_WORKTREE" 0 || true
  fi
  return "$rc"
}

arm_trap() { trap ephemeral_trap EXIT INT TERM ERR; }
disarm_trap() { trap - EXIT INT TERM ERR; }

# ============================================================================
# Verb: run -- unconditionally ephemeral one-shot, foreground, exit-code-faithful
# ============================================================================
verb_run() {
  local image=""
  parse_birth_args run "$@"
  image="$PARSED_IMAGE"
  [ -n "$image" ] || die "$EX_USAGE" "run requires an <image>"

  precheck
  reap_sweep_quiet   # cheap reconcile at the top of the invocation (Layer 3)

  build_birth_argv 0 "$image"

  # Arm Layer-2 teardown around the foreground launch. For --rm runs podman
  # removes the container on clean exit (Layer 1); the trap covers crash/signal.
  TRAP_PERSIST=0
  TRAP_WORKTREE="$BIRTH_WORKTREE"
  TRAP_CONTAINER=""   # name unknown for ephemeral; --rm + reap cover the id
  arm_trap

  info "launching ephemeral sandbox ${BIRTH_ID} (image=$image, net=$OPT_NETWORK)"
  local rc=0
  # Foreground, blocking. Propagate the workload exit code verbatim.
  podman_q "${BIRTH_ARGV[@]}" || rc=$?

  # Clean exit: --rm already removed the container; tear down the worktree
  # (guarded -- unpushed work is preserved). Disarm first.
  disarm_trap
  remove_worktree "$BIRTH_WORKTREE" 0 || true
  exit "$rc"
}

# ============================================================================
# Verb: keep -- PERSISTENT sandbox (omits --rm, stamps persist label). Loud.
# ============================================================================
verb_keep() {
  parse_birth_args keep "$@"
  local image="$PARSED_IMAGE"
  [ -n "$image" ] || die "$EX_USAGE" "keep requires an <image>"
  [ -n "$OPT_NAME" ] || die "$EX_USAGE" "keep requires --name <name>"

  precheck
  reap_sweep_quiet

  build_birth_argv 1 "$image"

  # For keep, the trap must NOT destroy the sandbox -- it is meant to survive.
  # But a partial birth (launch failure) should still roll back the worktree.
  TRAP_PERSIST=0
  TRAP_CONTAINER="$OPT_NAME"
  TRAP_WORKTREE="$BIRTH_WORKTREE"
  arm_trap

  warn "PERSISTENT sandbox '${OPT_NAME}' will SURVIVE exit -- you must 'stop'/'rm'/'reap' it"
  info "launching kept sandbox ${BIRTH_ID} name=${OPT_NAME} (image=$image)"

  local rc=0
  podman_q "${BIRTH_ARGV[@]}" || rc=$?

  if [ "$rc" -ne 0 ]; then
    # Launch failed -> roll back the worktree (trap fires too, but be explicit).
    disarm_trap
    remove_worktree "$BIRTH_WORKTREE" 0 || true
    die "$EX_LAUNCH" "keep: engine failed to launch '${OPT_NAME}' (rc=$rc)"
  fi

  # Successful birth: the sandbox + worktree are now durable. Disarm; do NOT
  # remove anything. Report the id so compose tooling can read it.
  disarm_trap
  TRAP_WORKTREE=""
  emit_kv id "$BIRTH_ID" name "$OPT_NAME" worktree "$BIRTH_WORKTREE"
  return 0
}

# ============================================================================
# Verb: start -- restart a stopped kept sandbox (prevents worktree orphaning)
# ============================================================================
verb_start() {
  local tty=0 name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -it|-ti) tty=1 ;;
      -h|--help) usage 0 ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "start: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "start requires <name>"
  precheck

  local id; id="$(resolve_managed "$name")"
  info "starting kept sandbox '$name' ($id)"
  if [ "$tty" = 1 ]; then
    podman_q start -ai "$id"
  else
    podman_q start "$id" >/dev/null
    emit_kv id "$id" name "$name" status started
  fi
}

# ============================================================================
# Verb: exec -- run a cmd in a RUNNING kept sandbox. Does NOT auto-start.
# ============================================================================
verb_exec() {
  reset_opts
  local name="" workdir="" user="" tty=0 ssh_agent=0
  local -a envs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --workdir) workdir="$2"; shift ;;
      --env)     envs+=("$2"); shift ;;
      --user)    user="$2"; shift ;;
      -it|-ti)   tty=1 ;;
      --ssh-agent) ssh_agent=1 ;;
      --timeout) OPT_TIMEOUT="$2"; shift ;;
      -h|--help) usage 0 ;;
      --) shift; WORKLOAD_CMD=("$@"); break ;;
      -*) die "$EX_USAGE" "exec: unknown flag '$1'" ;;
      *) [ -z "$name" ] && name="$1" || die "$EX_USAGE" "exec: unexpected arg '$1'" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "exec requires <name> -- cmd..."
  precheck

  local id; id="$(resolve_managed "$name")"
  local state; state="$(container_state "$id")"
  if [ "$state" != running ]; then
    # Deliberate divergence from msb's resolve_and_start: fail CLOSED.
    die "$EX_GUARD" "sandbox '$name' is '$state', not running -- run '$PROG start $name' first"
  fi

  local -a eargv=(exec)
  [ "$tty" = 1 ] && eargv+=(-it)
  [ -n "$workdir" ] && eargv+=(--workdir "$workdir")
  [ -n "$user" ] && eargv+=(--user "$user")
  local e
  for e in "${envs[@]}"; do eargv+=(--env "$e"); done
  if [ "$ssh_agent" = 1 ]; then
    eargv+=(--env "SSH_AUTH_SOCK=/run/ssh-agent.sock")
  fi
  eargv+=("$id")

  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    # base64 transport for arbitrary agent-written code (dodges quoting bugs).
    local payload b64
    payload="$(printf '%s ' "${WORKLOAD_CMD[@]}")"; payload="${payload% }"
    b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    eargv+=(/bin/sh -c "echo ${b64} | base64 -d | exec bash -s")
  else
    [ "$tty" = 1 ] || die "$EX_USAGE" "exec needs a command (-- cmd...) unless -it"
    eargv+=(/bin/bash)
  fi

  local rc=0
  podman_q "${eargv[@]}" || rc=$?
  exit "$rc"
}

# ============================================================================
# Verb: logs -- post-mortem stdout/stderr (the only post-mortem for an --rm crash
#               that was a kept sandbox; ephemeral --rm leaves nothing).
# ============================================================================
verb_logs() {
  local follow=0 tail="" name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--follow) follow=1 ;;
      -n|--tail) tail="$2"; shift ;;
      -h|--help) usage 0 ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "logs: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "logs requires <name>"
  precheck

  local id; id="$(resolve_managed "$name")"
  local -a largv=(logs)
  [ "$follow" = 1 ] && largv+=(-f)
  [ -n "$tail" ] && { require_uint "$tail" "--tail"; largv+=(--tail "$tail"); }
  largv+=("$id")
  podman_q "${largv[@]}"
}

# ============================================================================
# Verb: ls -- list managed sandboxes. Machine-readable (stable columns) BY
#             DEFAULT. Selection EXCLUSIVELY by the managed-by label.
# ============================================================================
verb_ls() {
  local all=0 json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -a|--all) all=1 ;;
      --json) json=1 ;;
      -h|--help) usage 0 ;;
      *) die "$EX_USAGE" "ls: unexpected arg '$1'" ;;
    esac
    shift
  done

  local -a psargs=(ps --filter "$(our_filter)")
  [ "$all" = 1 ] && psargs+=(-a)

  if [ "$json" = 1 ]; then
    # Hand straight to podman's own JSON; it is already machine-readable.
    podman_q "${psargs[@]}" \
      --format '{"id":"{{.ID}}","name":"{{index .Labels "'"${LBL_NAME}"'"}}","status":"{{.Status}}","created":"{{index .Labels "'"${LBL_CREATED}"'"}}","worktree":"{{index .Labels "'"${LBL_WORKTREE}"'"}}","persist":"{{index .Labels "'"${LBL_PERSIST}"'"}}","ports":"{{.Ports}}"}'
  else
    # Stable, parseable columns (TSV-ish) -- the default machine-readable form.
    printf 'ID\tNAME\tSTATUS\tPERSIST\tPORTS\tWORKTREE\tCREATED\n'
    podman_q "${psargs[@]}" \
      --format '{{.ID}}\t{{index .Labels "'"${LBL_NAME}"'"}}\t{{.Status}}\t{{index .Labels "'"${LBL_PERSIST}"'"}}\t{{.Ports}}\t{{index .Labels "'"${LBL_WORKTREE}"'"}}\t{{index .Labels "'"${LBL_CREATED}"'"}}'
  fi
}

# ============================================================================
# Verb: inspect -- single-object config/status. The --json compose contract.
# ============================================================================
verb_inspect() {
  local json=0 name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      -h|--help) usage 0 ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "inspect: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "inspect requires <name>"

  local id; id="$(resolve_managed "$name")"
  if [ "$json" = 1 ]; then
    podman_q inspect "$id"
  else
    podman_q inspect --format \
      'id:        {{.Id}}
name:      {{index .Config.Labels "'"${LBL_NAME}"'"}}
status:    {{.State.Status}}
runtime:   {{.OCIRuntime}}
created:   {{index .Config.Labels "'"${LBL_CREATED}"'"}}
worktree:  {{index .Config.Labels "'"${LBL_WORKTREE}"'"}}
persist:   {{index .Config.Labels "'"${LBL_PERSIST}"'"}}
network:   {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}
ports:     {{.NetworkSettings.Ports}}' "$id"
  fi
}

# ============================================================================
# Verb: stop -- graceful stop of kept sandboxes; keeps worktree.
# ============================================================================
verb_stop() {
  local force=0 timeout=10
  local -a names=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force) force=1 ;;
      -t|--timeout) timeout="$2"; shift ;;
      -h|--help) usage 0 ;;
      --) shift; names+=("$@"); break ;;
      -*) die "$EX_USAGE" "stop: unknown flag '$1'" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  [ "${#names[@]}" -gt 0 ] || die "$EX_USAGE" "stop requires <name...>"
  require_uint "$timeout" "--timeout"
  precheck

  local n id rc=0
  for n in "${names[@]}"; do
    id="$(resolve_managed "$n")" || { rc=$?; continue; }
    # Warn (do not refuse) on unpushed work; stop preserves the worktree anyway.
    local wt; wt="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_WORKTREE}\" }}" "$id" 2>/dev/null || true)"
    if [ -n "$wt" ] && has_unpushed_commits "$wt"; then
      warn "sandbox '$n' worktree has unpushed commits (preserved; stop keeps worktrees)"
    fi
    if [ "$force" = 1 ]; then
      podman_q kill "$id" >/dev/null 2>&1 || true
    else
      podman_q stop -t "$timeout" "$id" >/dev/null 2>&1 || true
    fi
    info "stopped '$n'"
  done
  return "$rc"
}

# ============================================================================
# Verb: rm -- teardown kept sandbox + its worktree (path+commit guarded).
# ============================================================================
verb_rm() {
  local force=0 keep_wt=0
  local -a names=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force) force=1 ;;
      --keep-worktree) keep_wt=1 ;;
      -h|--help) usage 0 ;;
      --) shift; names+=("$@"); break ;;
      -*) die "$EX_USAGE" "rm: unknown flag '$1'" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  [ "${#names[@]}" -gt 0 ] || die "$EX_USAGE" "rm requires <name...>"
  precheck

  local n id wt rc=0
  for n in "${names[@]}"; do
    id="$(resolve_managed "$n")" || { rc=$?; continue; }
    wt="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_WORKTREE}\" }}" "$id" 2>/dev/null || true)"

    # Remove the container first (so a held mount cannot block worktree rm).
    if [ "$force" = 1 ]; then
      podman_q rm -f -v "$id" >/dev/null 2>&1 || true
    else
      if [ "$(container_state "$id")" = running ]; then
        die "$EX_GUARD" "sandbox '$n' is running -- use -f to force, or 'stop' it first"
      fi
      podman_q rm -v "$id" >/dev/null 2>&1 || true
    fi

    if [ "$keep_wt" = 1 ]; then
      info "removed '$n' (worktree preserved: $wt)"
      continue
    fi
    if [ -n "$wt" ]; then
      if ! remove_worktree "$wt" "$force"; then
        rc="$EX_GUARD"
        warn "sandbox '$n' removed but worktree retained (guard refused): $wt"
        continue
      fi
    fi
    info "removed '$n' and its worktree"
  done
  return "$rc"
}

# ============================================================================
# Verb: reap -- Layer-3 label-driven backstop. Touches ONLY our labelled set.
# Runs directly (verbose) and also cheaply at the top of every birth verb.
# ============================================================================

# reap_core <dry-run 0|1> <until-secs ''|N> <emit 0|1> -- the shared sweep.
# Removes managed containers that are exited/dead (and, with an age cut, older
# kept-but-abandoned ones). Never touches a healthy running sandbox. Never
# touches host-global state.
reap_core() {
  local dry="$1" until_secs="$2" emit="$3"
  local now reaped=0
  now="$(date -u +%s)"

  # Candidate set: ALL managed containers (we decide per-container below).
  local ids id status created created_epoch persist age
  ids="$(podman_q ps -a -q --filter "$(our_filter)" 2>/dev/null || true)"
  [ -n "$ids" ] || { [ "$emit" = 1 ] && info "reap: nothing managed found"; return 0; }

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    status="$(container_state "$id")"
    persist="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_PERSIST}\" }}" "$id" 2>/dev/null || true)"

    local doomed=0 reason=""
    case "$status" in
      exited|dead|stopped)
        # An exited EPHEMERAL leak, or an exited kept sandbox: ephemeral leaks
        # are always reaped; kept ones only when an age cut is requested.
        if [ "$persist" = true ]; then
          if [ -n "$until_secs" ]; then doomed=1; reason="kept+exited+aged"; fi
        else
          doomed=1; reason="ephemeral leak (exited)"
        fi
        ;;
      running|created)
        # Healthy: only an age cut on a persistent sandbox could doom it, and we
        # deliberately do NOT kill healthy running sandboxes on a time sweep.
        :
        ;;
    esac

    # Age cut (against the sandbox.created label) for aged kept sandboxes.
    if [ "$doomed" = 0 ] && [ -n "$until_secs" ] && [ "$persist" = true ] && [ "$status" != running ]; then
      created="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_CREATED}\" }}" "$id" 2>/dev/null || true)"
      if [ -n "$created" ]; then
        created_epoch="$(date -u -d "$created" +%s 2>/dev/null || echo 0)"
        age=$(( now - created_epoch ))
        if [ "$created_epoch" -gt 0 ] && [ "$age" -ge "$until_secs" ]; then
          doomed=1; reason="kept aged ${age}s"
        fi
      fi
    fi

    [ "$doomed" = 1 ] || continue

    local wt
    wt="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_WORKTREE}\" }}" "$id" 2>/dev/null || true)"
    if [ "$dry" = 1 ]; then
      [ "$emit" = 1 ] && printf 'would-reap\t%s\t%s\t%s\n' "$id" "$status" "$reason"
      continue
    fi
    debug "reap: removing $id ($reason)"
    podman_q rm -f -v "$id" >/dev/null 2>&1 || true
    # Worktree teardown is guarded (path + unpushed commits). reap never forces.
    [ -n "$wt" ] && { remove_worktree "$wt" 0 || true; }
    reaped=$(( reaped + 1 ))
  done <<EOF
$ids
EOF

  [ "$emit" = 1 ] && info "reap: removed $reaped sandbox(es)"
  return 0
}

# reap_sweep_quiet -- the cheap reconcile at the top of birth verbs. Disarms the
# EXIT trap first (gh-runner lesson) so a concurrent teardown can't double-fire.
# No lock by design (no-lock concurrency: idempotent, podman rm -f is safe to
# race). This is a named graduation signal if it ever needs a real mutex.
reap_sweep_quiet() {
  reap_core 0 "" 0 || true
}

verb_reap() {
  local dry=0 json=0 until_dur="" until_secs=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --until) until_dur="$2"; shift ;;
      --dry-run) dry=1 ;;
      --json) json=1 ;;
      -h|--help) usage 0 ;;
      *) die "$EX_USAGE" "reap: unexpected arg '$1'" ;;
    esac
    shift
  done
  [ -n "$until_dur" ] && until_secs="$(duration_to_secs "$until_dur")"

  # Disarm any inherited trap before the sweep (avoid re-entrant double cleanup).
  disarm_trap

  if [ "$json" = 1 ]; then
    # For --json + --dry-run, emit a small JSON array of candidates.
    printf '{"dry_run":%s,"candidates":[' "$([ "$dry" = 1 ] && echo true || echo false)"
    local first=1 line
    while IFS=$'\t' read -r _tag cid cstatus creason; do
      [ -n "$cid" ] || continue
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"id":"%s","status":"%s","reason":"%s"}' \
        "$cid" "$cstatus" "$(json_escape "$creason")"
    done < <(reap_core 1 "$until_secs" 1 2>/dev/null)
    printf ']}\n'
    # In non-dry JSON mode, actually perform the sweep after reporting.
    [ "$dry" = 1 ] || reap_core 0 "$until_secs" 0 || true
  else
    reap_core "$dry" "$until_secs" 1
  fi
}

# ============================================================================
# Output helpers for machine-readable single-object emission.
# ============================================================================

# emit_kv k v k v ... -- stable key:value lines to stdout (human + greppable).
emit_kv() {
  while [ $# -ge 2 ]; do
    printf '%s\t%s\n' "$1" "$2"
    shift 2
  done
}

# ============================================================================
# Birth-verb argument parser (shared by run + keep). Populates the OPT_* globals
# and EXTRA_* arrays, sets PARSED_IMAGE and WORKLOAD_CMD. Flags precede the image;
# everything after `--` is the workload command.
# ============================================================================
PARSED_IMAGE=""
parse_birth_args() {
  local verb="$1"; shift
  reset_opts
  PARSED_IMAGE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --cpus)     OPT_CPUS="$2"; shift ;;
      --memory)   OPT_MEMORY="$2"; shift ;;
      --network)  OPT_NETWORK="$2"; shift ;;
      --publish)  PUBLISH_PORTS+=("$2"); shift ;;
      --mount)    EXTRA_MOUNTS+=("$2"); shift ;;
      --env)      EXTRA_ENV+=("$2"); shift ;;
      --workdir)  OPT_WORKDIR="$2"; shift ;;
      --ssh-agent) OPT_SSH_AGENT=1 ;;
      -it|-ti)    OPT_TTY=1 ;;
      --timeout)  OPT_TIMEOUT="$2"; shift ;;
      --json)     OPT_JSON=1 ;;
      --name)     OPT_NAME="$2"; shift ;;
      -h|--help)  usage 0 ;;
      --)         shift; WORKLOAD_CMD=("$@"); break ;;
      -*)         die "$EX_USAGE" "$verb: unknown flag '$1'" ;;
      *)
        if [ -z "$PARSED_IMAGE" ]; then
          PARSED_IMAGE="$1"
        else
          die "$EX_USAGE" "$verb: unexpected positional arg '$1' (workload goes after --)"
        fi
        ;;
    esac
    shift
  done
}

# ============================================================================
# Top-level dispatch.
# ============================================================================
main() {
  [ $# -ge 1 ] || usage "$EX_USAGE"
  local verb="$1"; shift
  case "$verb" in
    doctor)  run_doctor "${1:-}" ;;
    run)     verb_run "$@" ;;
    keep)    verb_keep "$@" ;;
    start)   verb_start "$@" ;;
    exec)    verb_exec "$@" ;;
    logs)    verb_logs "$@" ;;
    ls|list) verb_ls "$@" ;;
    inspect) verb_inspect "$@" ;;
    stop)    verb_stop "$@" ;;
    rm|remove) verb_rm "$@" ;;
    reap)    verb_reap "$@" ;;
    -h|--help|help) usage 0 ;;
    --version|version) printf '%s %s\n' "$PROG" "$SANDBOX_VERSION" ;;
    *) die "$EX_USAGE" "unknown verb: '$verb' (try '$PROG --help')" ;;
  esac
}

main "$@"
