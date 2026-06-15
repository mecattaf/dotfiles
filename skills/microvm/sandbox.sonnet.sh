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
# THIS IS A STAGE-3 DRAFT (integrated A spine + B/C/D expert sections).
# Not yet installed.

set -euo pipefail

# ============================================================================
# Constants / identity
# ============================================================================

readonly SANDBOX_VERSION="0.1.0-draft"
readonly MANAGED_BY="sandbox"          # value of the sandbox.managed-by label
readonly LABEL_NS="sandbox"            # label namespace prefix

# Label keys (the mandatory set + persistence/identity markers).
readonly LBL_MANAGED="${LABEL_NS}.managed-by"
readonly LBL_CREATED="${LABEL_NS}.created"
readonly LBL_ID="${LABEL_NS}.id"
readonly LBL_WORKTREE="${LABEL_NS}.worktree"
readonly LBL_PERSIST="${LABEL_NS}.persist"
readonly LBL_NAME="${LABEL_NS}.name"
readonly LBL_BASE="${LABEL_NS}.base"   # git fork-point the worktree branched from

# The single managed root the tool owns. Worktrees live ONLY under here, and
# `is_safe_cache_path` refuses to delete anything outside it.
SANDBOX_ROOT="${SANDBOX_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/sandbox}"
readonly SANDBOX_ROOT
readonly WORKTREE_ROOT="${SANDBOX_ROOT}/worktrees"

# Runtime handler. crun-krun is the Fedora package name; the OCI runtime that
# podman invokes is `krun`. We default to `krun` and let doctor verify it.
SANDBOX_RUNTIME="${SANDBOX_RUNTIME:-krun}"
readonly SANDBOX_RUNTIME

# Canonical base image used by doctor's smoke test (and as a sane default).
SANDBOX_BASE_IMAGE="${SANDBOX_BASE_IMAGE:-registry.fedoraproject.org/fedora-minimal:latest}"
readonly SANDBOX_BASE_IMAGE

# ============================================================================
# Exit-code scheme (stable, distinct, documented)
# ============================================================================
# 0          success / workload exited 0
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
# Resource-clamp bounds (krun annotation knobs).  [Expert C]
# krun FATALS on a malformed value and SILENTLY IGNORES ram_mib<=128, so we
# validate as integers in bash before stamping.
# ============================================================================
readonly KRUN_MIN_MIB=256          # floor strictly above krun's silent-ignore (<=128)
readonly KRUN_MAX_MIB=16384        # sane upper bound; krunvm uses the same ceiling
readonly KRUN_MIN_VCPU=1
readonly KRUN_MAX_VCPU=16          # LIBKRUN_MAX_VCPUS hard cap
readonly DEF_CPUS=1                # conservative accident-model default
readonly DEF_MEMORY=1024           # 1 GiB: above the floor, comfortable for a workload

# Accepted shared-library / ABI matrix for doctor (open question in the brief,
# resolved with a sensible default + comment). libkrun is at soname major 1;
# libkrunfw ships ABI_VERSION=5 on current Fedora. We accept the current majors
# and ALSO accept an adjacent libkrunfw major so a Fedora bump does not red-line
# doctor spuriously -- the decisive proof of compatibility is the smoke test.
readonly LIBKRUN_SONAME="libkrun.so.1"
readonly LIBKRUNFW_SONAME_GLOB="libkrunfw.so.*"   # e.g. libkrunfw.so.5(.4.0)
readonly LIB_SEARCH_DIRS="/usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib /lib64 /lib"

# ============================================================================
# Leveled logging (gh-runner-krunvm "Poor Man's Logging").  [Expert D]
# ALL diagnostics go to a configurable fd (default stderr=2) so stdout stays
# pipeable / machine-readable. Levels: 0=warn/err only, 1=+info, 2=+debug,
# 3=+trace. Level/fd are env-overridable. The level predicates use explicit
# `if` (not `&&...||true`) so they cannot leak a non-zero status under set -e.
# ============================================================================

SANDBOX_VERBOSE="${SANDBOX_VERBOSE:-1}"   # 0=warn/err 1=info 2=debug 3=trace
SANDBOX_LOG_FD="${SANDBOX_LOG_FD:-2}"     # fd to write diagnostics to
PROG="$(basename "$0")"

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
# Never collapses to 255 (the krunvm anti-pattern).
die() {
  local code="$1"; shift
  err "$@"
  exit "$code"
}

# ============================================================================
# Self-documenting usage(). Greps THIS script's own `# VERB:` and `# FLAG:`
# doc-comment lines and reformats them, so help can never drift from the
# dispatch table or the parser (gh-runner-krunvm idiom, extended to flags).
# BOTH the `# VERB:` block and the `# FLAG:` block below are load-bearing --
# usage() renders both; removing either renders an empty section.
# ============================================================================

# VERB: doctor   [--json]                                 verb-zero: probe host krun capability
# VERB: run      [flags] <image> [-- cmd...]              ephemeral one-shot (--rm always; foreground)
# VERB: keep     --name N [flags] <image> [-- cmd...]     PERSISTENT sandbox (survives exit; loud)
# VERB: start    [-it] <name>                             restart a stopped kept sandbox
# VERB: exec     [flags] <name> -- cmd...                 run a cmd in a RUNNING kept sandbox (no auto-start)
# VERB: logs     [-f] [-n N] <name>                       post-mortem stdout/stderr
# VERB: ls|list  [-a] [--json]                            list managed sandboxes (machine-readable; 'list' is an alias)
# VERB: inspect  [--json] <name>                          single-object config/status
# VERB: stop     [-f] [-t S] <name...>                    graceful stop of kept sandboxes
# VERB: rm|remove [-f] [--keep-worktree] <name...>        teardown kept sandbox + its worktree ('remove' is an alias)
# VERB: reap     [--until DUR] [--dry-run] [--json]       label-driven Layer-3 backstop
# VERB: version                                           print version string to stdout

# FLAG: --cpus N            vCPUs -> krun.cpus annotation (integer, clamped)
# FLAG: --memory MiB        guest RAM -> krun.ram_mib annotation (integer, clamped)
# FLAG: --network none|loopback  default none; --publish is a no-op under none
# FLAG: --publish HOST:GUEST publish to localhost only (loopback network only)
# FLAG: --mount HOST:GUEST[:ro|:rw]  extra mount; defaults read-only
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
  {
    printf '%s %s -- disciplined podman+krun microVM sandbox (accident-model isolation)\n\n' \
      "$PROG" "$SANDBOX_VERSION"
    printf 'USAGE: %s <verb> [flags] [args] [-- workload...]\n\n' "$PROG"
    printf 'VERBS:\n'
    if [ -n "$only_verb" ]; then
      grep -E "^# VERB: ${only_verb}([[:space:]]|\$)" "$0" | sed -E 's/^# VERB: /  /'
    else
      grep -E '^# VERB: ' "$0" | sed -E 's/^# VERB: /  /'
    fi

    printf '\nCOMMON FLAGS (birth verbs run/keep; subset honoured by exec/start):\n'
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
# Validation / utility helpers.  [Expert D validators + Expert C clamp]
# ============================================================================

# is_uint <value> -> 0 if a non-negative base-10 integer.
is_uint() { [[ "${1-}" =~ ^[0-9]+$ ]]; }

# require_uint <value> <flag-name> -- die EX_USAGE if not a non-negative integer.
require_uint() {
  is_uint "${1-}" || die "$EX_USAGE" "$2 must be a non-negative integer, got: '${1-}'"
}

# clamp <value> <min> <max> -- print value bounded to [min,max]. Re-guards the
# value as an integer so a malformed input degrades to the floor rather than
# crashing the arithmetic context.
clamp() {
  local v="$1" lo="$2" hi="$3"
  is_uint "$v" || v="$lo"
  if (( v < lo )); then v="$lo"; fi
  if (( v > hi )); then v="$hi"; fi
  printf '%s' "$v"
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

# need_arg <count-remaining> <flag> -- guard against a flag at end-of-args.
# Validate-ONLY (prints nothing). Call as `need_arg "$#" --cpus` BEFORE reading
# "$2". Plucking the value through `x="$(need_arg ...)"` would SWALLOW the die()
# under set -e (command-substitution exit status is not checked in assignment),
# so the value must never be read through a subshell.
need_arg() {
  if [ "$1" -lt 2 ]; then
    die "$EX_USAGE" "$2 requires a value"
  fi
}

# Generate a short random id (worktree + label identity).
gen_id() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 10; }

# podman wrapper so the binary is overridable in tests and every call is logged.
PODMAN="${PODMAN:-podman}"
podman_q() { trace "podman $*"; "$PODMAN" "$@"; }

# ============================================================================
# Machine-readable output helpers.  [Expert D]
# stdout carries ONLY parseable data; human/diagnostic text goes to the log fd.
# ============================================================================

# emit_kv k v k v ...  -- stable, greppable `key<TAB>value` lines to stdout.
emit_kv() {
  while [ "$#" -ge 2 ]; do
    printf '%s\t%s\n' "$1" "$2"
    shift 2
  done
}

# json_escape <string> -- minimal RFC-8259 string-body escaping for our
# hand-rolled JSON (we control the key set; values are labels/messages/ids).
json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"     # backslash first
  s="${s//\"/\\\"}"     # quotes
  s="${s//	/\\t}"      # literal TAB -> \t
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# encode_script <script-string> -- base64-transport for a SINGLE opaque shell
# script string (a genuine '-c <script>' invocation, not a word list). The
# caller is responsible for passing a single string; word boundaries are NOT
# preserved by this function -- it runs the decoded bytes as a shell script.
# In-guest dependency: sh + coreutils base64 + bash must be present.
# fedora-minimal has all three; alpine/distroless may not.
encode_script() {
  local b64
  b64="$(printf '%s' "$1" | base64 | tr -d '\n')"
  printf '%s\n' '/bin/sh'
  printf '%s\n' '-c'
  printf '%s\n' "printf %s '${b64}' | base64 -d | bash -s"
}

# ============================================================================
# Label-scoped selection helpers (NEVER name substring).  [Expert A]
# ============================================================================

# our_filter: the mandatory managed-by filter every selection passes through.
our_filter() { printf '%s' "label=${LBL_MANAGED}=${MANAGED_BY}"; }

# resolve_managed <name>  -> prints the container id, or dies EX_NOTFOUND.
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
# doctor -- verb-zero capability probe.  [Expert C]
# Read-only. Each probe records a PASS/FAIL row with an ACTIONABLE remediation,
# ties the check to the guarantee it underwrites, and fails CLOSED with a
# distinct precondition exit code. Every other verb calls precheck() (a cheap
# subset) before doing work.
# ============================================================================

# Accumulators for PASS/FAIL rows (parallel arrays for portable JSON emission).
declare -a DOCTOR_NAMES=() DOCTOR_OK=() DOCTOR_MSG=()

# _dr <name> <ok 0|1> <message> -- record one check row.
_dr() {
  DOCTOR_NAMES+=("$1"); DOCTOR_OK+=("$2"); DOCTOR_MSG+=("$3")
}

# probe_kvm -- /dev/kvm present, readable AND writable (character device).
# Guarantee: krun cannot boot a microVM without rw /dev/kvm.
probe_kvm() {
  if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    _dr kvm 0 "/dev/kvm present, readable and writable"; return 0
  fi
  if [ -e /dev/kvm ]; then
    _dr kvm 1 "/dev/kvm not rw-accessible -- run: sudo usermod -aG kvm \"\$USER\" then re-login"
  else
    _dr kvm 1 "/dev/kvm missing -- enable KVM/nested virtualization on this host"
  fi
  return 1
}

# probe_podman -- podman binary present AND `podman info` succeeds.
probe_podman() {
  if command -v "$PODMAN" >/dev/null 2>&1 && podman_q info >/dev/null 2>&1; then
    local ver
    ver="$("$PODMAN" --version 2>/dev/null | head -n1)"
    _dr podman 0 "podman usable (${ver:-version unknown})"; return 0
  fi
  _dr podman 1 "podman not usable -- install podman and verify 'podman info' succeeds"
  return 1
}

# probe_runtime_registered -- the krun runtime is resolvable by podman.
# Accept ANY of: podman lists it under OCIRuntimes, a krun/crun-krun binary on
# PATH, or the configured runtime name being directly executable.
probe_runtime_registered() {
  local rt="$SANDBOX_RUNTIME"
  # shellcheck disable=SC2016  # this is a podman Go template, not a shell expansion.
  if podman_q info --format '{{range $k,$v := .Host.OCIRuntime.Runtimes}}{{$k}} {{end}}' 2>/dev/null \
        | tr ' ' '\n' | grep -qiE "^${rt}$|krun"; then
    _dr runtime 0 "runtime '${rt}' registered with podman"; return 0
  fi
  if command -v "$rt" >/dev/null 2>&1 || command -v krun >/dev/null 2>&1; then
    _dr runtime 0 "runtime '${rt}' resolvable on PATH (not in containers.conf -- still usable)"; return 0
  fi
  _dr runtime 1 "runtime '${rt}' not registered -- install crun-krun and add it to containers.conf [engine.runtimes]"
  return 1
}

# probe_crun_libkrun -- crun was built with the +LIBKRUN feature.
probe_crun_libkrun() {
  local out="" bin
  for bin in crun "$SANDBOX_RUNTIME" krun; do
    if command -v "$bin" >/dev/null 2>&1; then
      out="$("$bin" --version 2>/dev/null || true)"
      [ -n "$out" ] && break
    fi
  done
  if printf '%s' "$out" | grep -qiE '[+]?LIBKRUN'; then
    _dr crun_libkrun 0 "crun reports +LIBKRUN feature"; return 0
  fi
  if [ -z "$out" ]; then
    _dr crun_libkrun 1 "crun not found -- install crun (with the crun-krun handler)"
  else
    _dr crun_libkrun 1 "crun lacks +LIBKRUN in its feature string -- install the crun-krun package"
  fi
  return 1
}

# probe_libkrun_so -- libkrun.so.1 AND an ABI-matched libkrunfw are loadable.
# We prefer the loader's own view (ldconfig) then fall back to a directory scan.
# The exact soname matrix is an open question -- we accept libkrun major 1 + any
# installed libkrunfw major and let the smoke test be the final arbiter.
probe_libkrun_so() {
  local found_krun=0 found_fw=0 d

  if command -v ldconfig >/dev/null 2>&1; then
    local cache
    cache="$(ldconfig -p 2>/dev/null || true)"
    printf '%s' "$cache" | grep -q "$LIBKRUN_SONAME"  && found_krun=1
    printf '%s' "$cache" | grep -q 'libkrunfw\.so\.' && found_fw=1
  fi
  if [ "$found_krun" = 0 ] || [ "$found_fw" = 0 ]; then
    for d in $LIB_SEARCH_DIRS; do
      [ -e "${d}/${LIBKRUN_SONAME}" ] && found_krun=1
      # shellcheck disable=SC2086,SC2144
      ls ${d}/${LIBKRUNFW_SONAME_GLOB} >/dev/null 2>&1 && found_fw=1
    done
  fi

  if [ "$found_krun" = 1 ] && [ "$found_fw" = 1 ]; then
    _dr libkrun 0 "${LIBKRUN_SONAME} and libkrunfw present on the loader path"; return 0
  fi
  if [ "$found_krun" = 0 ] && [ "$found_fw" = 0 ]; then
    _dr libkrun 1 "${LIBKRUN_SONAME} and libkrunfw missing -- install libkrun and libkrunfw"
  elif [ "$found_krun" = 0 ]; then
    _dr libkrun 1 "${LIBKRUN_SONAME} missing -- install the libkrun package"
  else
    _dr libkrun 1 "libkrunfw missing -- install the libkrunfw package (ABI must match libkrun)"
  fi
  return 1
}

# probe_smoke -- the decisive end-to-end gate: a --rm --network none microVM
# running `true` under our runtime. The ONLY check that proves the whole stack
# boots a guest; also confirms --network none does not break a launch.
probe_smoke() {
  if podman_q run --rm --runtime "$SANDBOX_RUNTIME" --network none \
        --security-opt no-new-privileges --cap-drop ALL \
        "$SANDBOX_BASE_IMAGE" true >/dev/null 2>&1; then
    _dr smoke 0 "smoke microVM (--rm --network none true) booted and exited 0"; return 0
  fi
  _dr smoke 1 "smoke microVM failed to boot -- krun cannot launch (see the checks above)"
  return 1
}

# doctor_emit <table|json> -- render the accumulated rows. JSON is a single
# object with a checks array; the table goes to stderr so stdout stays clean.
doctor_emit() {
  local mode="$1" i n="${#DOCTOR_NAMES[@]}"
  if [ "$mode" = json ]; then
    printf '{"version":"%s","checks":[' "$SANDBOX_VERSION"
    for (( i=0; i<n; i++ )); do
      [ "$i" -gt 0 ] && printf ','
      printf '{"name":"%s","ok":%s,"message":"%s"}' \
        "${DOCTOR_NAMES[$i]}" \
        "$([ "${DOCTOR_OK[$i]}" = 0 ] && printf 'true' || printf 'false')" \
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

# run_doctor [--json] -- the full verbose verb-zero gate. Runs every probe,
# emits the report, exits EX_PRECONDITION if ANY hard gate failed.
run_doctor() {
  local mode=table
  [ "${1:-}" = "--json" ] && mode=json
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()

  local hard_ok=0
  probe_kvm                || hard_ok=1
  probe_podman             || hard_ok=1
  probe_crun_libkrun       || hard_ok=1
  probe_libkrun_so         || hard_ok=1
  probe_runtime_registered || hard_ok=1

  if [ "$hard_ok" = 0 ]; then
    probe_smoke || hard_ok=1
  else
    _dr smoke 1 "smoke microVM skipped -- a prior hard gate failed"
  fi

  doctor_emit "$mode"
  if [ "$hard_ok" != 0 ]; then
    [ "$mode" = table ] && err "doctor: host is NOT ready for krun sandboxes"
    exit "$EX_PRECONDITION"
  fi
  [ "$mode" = table ] && info "doctor: all gates passed -- host is ready"
  return 0
}

# precheck -- the cheap silent subset run at the top of every birth/lifecycle
# verb. Never boots the smoke container (too costly per-invocation). Owns the
# DOCTOR_* accumulators outright (resets before and clears after) so a verb
# leaves no stray rows. We intentionally do NOT save/restore prior rows --
# a "${arr[@]:-}" round-trip would inject a spurious empty element under set -u.
precheck() {
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()

  local ok=0
  probe_kvm                >/dev/null 2>&1 || ok=1
  probe_podman             >/dev/null 2>&1 || ok=1
  probe_runtime_registered >/dev/null 2>&1 || ok=1

  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()

  if [ "$ok" != 0 ]; then
    die "$EX_PRECONDITION" "precondition failed -- run '$PROG doctor' for details"
  fi
}

# precheck_podman_only -- #17: pure-cleanup verbs (reap, stop, rm, logs) and
# read-only verbs (ls, inspect) MUST NOT gate on KVM + krun-runtime because that
# would block backstop cleanup EXACTLY when krun/KVM are broken. Gate only on
# podman being usable; never on krun being available for cleanup paths.
precheck_podman_only() {
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()
  local ok=0
  probe_podman >/dev/null 2>&1 || ok=1
  DOCTOR_NAMES=(); DOCTOR_OK=(); DOCTOR_MSG=()
  if [ "$ok" != 0 ]; then
    die "$EX_PRECONDITION" "podman not usable -- run '$PROG doctor' for details"
  fi
}

# ============================================================================
# Resource caps: validate + clamp for the krun annotations.  [Expert C]
# ============================================================================

# krun_cpus <requested> -- validate + clamp the vCPU count. Warns on clamp.
krun_cpus() {
  local req="$1" out
  require_uint "$req" "--cpus"
  if [ "$req" -lt "$KRUN_MIN_VCPU" ]; then
    warn "--cpus must be >= ${KRUN_MIN_VCPU}; using ${KRUN_MIN_VCPU}"
  fi
  out="$(clamp "$req" "$KRUN_MIN_VCPU" "$KRUN_MAX_VCPU")"
  [ "$out" = "$req" ] || warn "--cpus clamped ${req} -> ${out} (krun caps vCPUs at ${KRUN_MAX_VCPU})"
  printf '%s' "$out"
}

# krun_ram_mib <requested> -- validate + clamp guest RAM. A value <=128 would be
# SILENTLY IGNORED by krun, so we hard-floor at KRUN_MIN_MIB and warn.
krun_ram_mib() {
  local req="$1" out
  require_uint "$req" "--memory"
  if [ "$req" -le 128 ]; then
    warn "--memory ${req} MiB would be silently ignored by krun (<=128); raising to ${KRUN_MIN_MIB}"
  fi
  out="$(clamp "$req" "$KRUN_MIN_MIB" "$KRUN_MAX_MIB")"
  [ "$out" = "$req" ] || warn "--memory clamped ${req} -> ${out} MiB (bounds ${KRUN_MIN_MIB}..${KRUN_MAX_MIB})"
  printf '%s' "$out"
}

# ============================================================================
# Centralized SAFE-FLAGS.  [Expert C]
# Each helper APPENDS to a caller-named array via a nameref so build_birth_argv
# stays readable and every isolation decision has one auditable home. Each flag
# reaches a REAL engine arg (no metadata-only no-ops -- the ERA fail-open lesson).
# ============================================================================

# apply_isolation_flags <argv-array-name>
#   no-new-privileges + cap-drop ALL + read-only rootfs. SELinux STAYS ON (we
#   never pass label=disable). --read-only-tmpfs=true (podman default, pinned)
#   gives workloads a scratch /tmp discarded with the VM.
apply_isolation_flags() {
  # shellcheck disable=SC2178  # _argv is an array nameref, not a string.
  local -n _argv="$1"
  _argv+=(--security-opt no-new-privileges)
  _argv+=(--cap-drop ALL)
  _argv+=(--read-only)
  _argv+=(--read-only-tmpfs=true)
}

# apply_krun_annotations <argv-array-name> <cpus> <ram_mib>
#   The REAL enforcing knobs (krun_set_vm_config). Values MUST be pre-validated.
apply_krun_annotations() {
  # shellcheck disable=SC2178  # _argv is an array nameref, not a string.
  local -n _argv="$1"
  local cpus="$2" mem="$3"
  _argv+=(--annotation "run.oci.krun.cpus=${cpus}")
  _argv+=(--annotation "run.oci.krun.ram_mib=${mem}")
}

# apply_rlimits <argv-array-name>
#   A second cap layer beyond cpu/ram (caps cover cpu/ram, rlimits cover the
#   rest). nofile = fd backstop, nproc = fork-bomb backstop.
apply_rlimits() {
  # shellcheck disable=SC2178  # _argv is an array nameref, not a string.
  local -n _argv="$1"
  _argv+=(--ulimit "nofile=4096:8192")
  _argv+=(--ulimit "nproc=1024:2048")
}

# apply_ssh_agent <argv-array-name>
#   Bind the host $SSH_AUTH_SOCK into the guest and set the env var. ONLY the
#   agent socket crosses; private keys NEVER enter the guest. Hard-fails
#   EX_GUARD if no usable agent, so --ssh-agent can never silently no-op.
apply_ssh_agent() {
  # shellcheck disable=SC2178  # _argv is an array nameref, not a string.
  local -n _argv="$1"
  local guest_sock="/run/ssh-agent.sock"
  [ -n "${SSH_AUTH_SOCK:-}" ] \
    || die "$EX_GUARD" "--ssh-agent given but \$SSH_AUTH_SOCK is unset (no agent to forward)"
  [ -S "${SSH_AUTH_SOCK}" ] \
    || die "$EX_GUARD" "--ssh-agent given but \$SSH_AUTH_SOCK is not a socket: ${SSH_AUTH_SOCK}"
  _argv+=(--volume "${SSH_AUTH_SOCK}:${guest_sock}:Z")
  _argv+=(--env "SSH_AUTH_SOCK=${guest_sock}")
  debug "ssh-agent: forwarding socket only (keys never enter the guest)"
}

# ============================================================================
# Worktree management.  [Expert B]
#
# The tool CREATES the worktree (never accepts a pre-made one -> never orphans
# the agent from .git). Removal is path-safety-gated AND unpushed-commit-guarded
# so an accidental teardown can never silently destroy unpushed work.
# ============================================================================

# worktree_path <id> -> the canonical managed path for this sandbox.
worktree_path() { printf '%s/%s' "$WORKTREE_ROOT" "$1"; }

# base_marker_path <worktree> -> the SIDECAR file recording the fork-point.
# Kept *beside* the worktree (suffix ".base"), never inside it, so it can never
# show up in the worktree's `git status` and falsely trip the unpushed guard.
base_marker_path() { printf '%s.base' "$1"; }

# parent_marker_path <worktree> -> the SIDECAR file recording the parent repo
# path for this worktree. Used by remove_worktree to delete the sandbox/<id>
# branch after the worktree is removed (#7: orphaned-branch leak fix).
parent_marker_path() { printf '%s.parent' "$1"; }

# is_safe_cache_path <path> -- smolvm's guard. Returns 0 ONLY when safe to remove
# <path>: non-empty arg, existing directory, NOT a symlink, strictly *inside*
# WORKTREE_ROOT, and NOT equal to WORKTREE_ROOT itself. Canonicalizes both sides
# with `pwd -P` so `..`/symlink trickery cannot escape the managed root. Fails
# closed if the managed root cannot be resolved.
is_safe_cache_path() {
  local p="${1:-}"
  [ -n "$p" ]    || { trace "guard: empty path";   return 1; }
  [ -d "$p" ]    || { trace "guard: not a dir: $p"; return 1; }
  [ ! -L "$p" ]  || { trace "guard: symlink: $p";   return 1; }

  local rp rroot
  rp="$(cd -P -- "$p" 2>/dev/null && pwd -P)"                || { trace "guard: unresolvable: $p"; return 1; }
  rroot="$(cd -P -- "$WORKTREE_ROOT" 2>/dev/null && pwd -P)" || { trace "guard: root unresolvable"; return 1; }

  [ -n "$rp" ] && [ -n "$rroot" ] || { trace "guard: empty canonical path"; return 1; }
  [ "$rp" != "$rroot" ]           || { trace "guard: is the managed root itself"; return 1; }
  case "$rp/" in
    "$rroot"/*) return 0 ;;
    *) trace "guard: '$rp' is outside managed root '$rroot'"; return 1 ;;
  esac
}

# _worktree_base_ref <worktree> -- print the commit this worktree forked from,
# read from the sidecar marker beside the worktree. Knowing the base is what lets
# has_unpushed_commits tell "the agent committed new work" apart from "HEAD
# already had history when we branched".
_worktree_base_ref() {
  local wt="$1" marker base=""
  marker="$(base_marker_path "$wt")"
  if [ -r "$marker" ]; then
    base="$(<"$marker")"
    base="${base%%[[:space:]]*}"
  fi
  printf '%s' "$base"
}

# has_unpushed_commits <worktree> -- returns 0 (true: there IS work to lose) when
# the worktree has uncommitted changes, OR commits beyond what is already safe.
# "Safe" means present on the tracking upstream if one exists, otherwise present
# at the recorded base ref. Conservative / fail-safe: if we cannot prove the
# work is saved we assume it exists so the guard errs toward PRESERVING data.
has_unpushed_commits() {
  local wt="$1"
  git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

  # 1) Uncommitted / untracked changes are unambiguously unsaved work.
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    trace "guard: '$wt' has uncommitted changes"
    return 0
  fi

  # 2) Commits not yet on an upstream tracking branch.
  local upstream
  if upstream="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
       && [ -n "$upstream" ]; then
    if [ -n "$(git -C "$wt" rev-list "${upstream}..HEAD" 2>/dev/null)" ]; then
      trace "guard: '$wt' has commits ahead of upstream $upstream"
      return 0
    fi
    return 1
  fi

  # 3) No upstream: compare against the recorded fork point, NOT HEAD-from-empty.
  local base
  base="$(_worktree_base_ref "$wt")"
  if [ -n "$base" ] && git -C "$wt" rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1; then
    if [ -n "$(git -C "$wt" rev-list "${base}..HEAD" 2>/dev/null)" ]; then
      trace "guard: '$wt' has commits ahead of base $base"
      return 0
    fi
    return 1
  fi

  # 4) No upstream and no usable base ref -> we cannot prove the work is saved.
  if git -C "$wt" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    trace "guard: '$wt' has no upstream and no base ref -- treating HEAD as unpushed"
    return 0
  fi
  return 1
}

# create_worktree <id> -- create the per-sandbox worktree under the managed root.
# Inside a git repo: branch off HEAD and RECORD the base commit (so removal can
# distinguish new work from pre-existing history). Outside a repo: a plain
# managed directory. Prints the absolute path on stdout; diagnostics to stderr.
create_worktree() {
  local id="$1" wt
  wt="$(worktree_path "$id")"
  mkdir -p "$WORKTREE_ROOT"

  if [ -e "$wt" ]; then
    die "$EX_GUARD" "worktree path already exists, refusing to reuse: $wt"
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch base parent_repo
    branch="sandbox/${id}"
    base="$(git rev-parse HEAD 2>/dev/null || true)"
    # #7: record the parent repo path so remove_worktree can delete the branch.
    parent_repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if git worktree add -b "$branch" "$wt" HEAD >/dev/null 2>&1; then
      debug "created git worktree $wt on branch $branch (base ${base:-unknown})"
      # #23: hard-fail birth if the sidecar write fails -- a silent failure here
      # turns every clean teardown into a -f-requiring guard refusal.
      if [ -n "$base" ]; then
        printf '%s\n' "$base" > "$(base_marker_path "$wt")" \
          || die "$EX_GUARD" "create_worktree: failed to write base marker $(base_marker_path "$wt")"
      fi
      # #7: record parent repo path beside the worktree; best-effort (no parent
      # path = branch leak, same as the pre-fix behaviour, not a birth blocker).
      if [ -n "$parent_repo" ]; then
        printf '%s\n' "$parent_repo" > "$(parent_marker_path "$wt")" 2>/dev/null || true
      fi
    else
      warn "git worktree add failed; using a plain managed directory at $wt"
      mkdir -p "$wt"
    fi
  else
    debug "not in a git repo; creating plain managed directory $wt"
    mkdir -p "$wt"
  fi
  printf '%s' "$wt"
}

# remove_worktree <worktree> <force 0|1> -- guarded teardown. Returns 0 if
# removed (or already gone), EX_GUARD if a guard refused (unsafe path, or
# unpushed work without --force). Cheap path guard runs BEFORE the git data-loss
# guard; git's own removal is preferred so admin metadata stays consistent.
remove_worktree() {
  local wt="${1:-}" force="${2:-0}"
  [ -n "$wt" ]  || return 0
  [ -e "$wt" ]  || { trace "worktree already gone: $wt"; return 0; }

  if ! is_safe_cache_path "$wt"; then
    warn "refusing to remove worktree outside managed root: $wt"
    return "$EX_GUARD"
  fi

  if has_unpushed_commits "$wt"; then
    if [ "$force" != 1 ]; then
      warn "worktree '$wt' has unpushed/uncommitted work -- refusing (use -f to override)"
      return "$EX_GUARD"
    fi
    warn "worktree '$wt' has unpushed work -- removing anyway (--force)"
  fi

  if git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Read the branch name and parent repo BEFORE removing the worktree (the
    # worktree's .git metadata disappears with the directory).
    local _branch _parent_repo
    _branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    _parent_repo=""
    local _parent_marker; _parent_marker="$(parent_marker_path "$wt")"
    if [ -r "$_parent_marker" ]; then
      _parent_repo="$(<"$_parent_marker")"
      _parent_repo="${_parent_repo%%[[:space:]]*}"
    fi

    if ! git worktree remove --force "$wt" >/dev/null 2>&1; then
      rm -rf -- "$wt"
      git worktree prune >/dev/null 2>&1 || true
    fi

    # #7: delete the sandbox/<id> branch in the parent repo now that the worktree
    # is gone (worktree removal MUST precede branch -D; the unpushed guard already
    # passed above so data-loss risk is accepted by the caller).
    if [ -n "$_parent_repo" ] && [ -n "$_branch" ]; then
      case "$_branch" in
        sandbox/*)
          git -C "$_parent_repo" branch -D "$_branch" >/dev/null 2>&1 || true ;;
      esac
    fi
  else
    rm -rf -- "$wt"
  fi
  rm -f -- "$(base_marker_path "$wt")" 2>/dev/null || true
  rm -f -- "$(parent_marker_path "$wt")" 2>/dev/null || true   # #7: clean up sidecar
  debug "removed worktree $wt"
  return 0
}

# ============================================================================
# Per-invocation option state + reset.  [Expert D]
# Flags+env duality lives HERE: reset_opts seeds every OPT_* from
# `${SANDBOX_*:-default}` so an env value is the default and a parsed flag (set
# later in parse_birth_args) WINS by overwriting it.
# ============================================================================

# Only the OPT_* the birth path (parse_birth_args + build_birth_argv + verb_run)
# actually consumes live here. The non-birth verbs (start/exec/logs/ls/inspect/
# stop/rm/reap) own their own locals, so we deliberately do NOT carry dead
# OPT_FORCE/OPT_ALL/OPT_TAIL/... global state.
declare -a EXTRA_MOUNTS EXTRA_ENV PUBLISH_PORTS WORKLOAD_CMD
OPT_CPUS="" OPT_MEMORY="" OPT_NETWORK="" OPT_WORKDIR=""
OPT_SSH_AGENT="" OPT_TTY="" OPT_TIMEOUT="" OPT_NAME=""

reset_opts() {
  EXTRA_MOUNTS=(); EXTRA_ENV=(); PUBLISH_PORTS=(); WORKLOAD_CMD=()
  OPT_CPUS="${SANDBOX_CPUS:-$DEF_CPUS}"
  OPT_MEMORY="${SANDBOX_MEMORY:-$DEF_MEMORY}"
  OPT_NETWORK="${SANDBOX_NETWORK:-none}"
  OPT_WORKDIR=""
  OPT_SSH_AGENT=0
  OPT_TTY=0
  OPT_TIMEOUT=""
  OPT_NAME=""
}

# ============================================================================
# Shared birth-verb argument parser (run + keep).  [Expert D]
# Grammar:  <flags...> <image> [-- workload...]
#   * Flags MUST precede the image (a positional after the image, before --, is
#     an error -- the workload goes after --).
#   * Everything after the first bare `--` is passed VERBATIM to the guest.
# Every option-argument is consumed through need_arg so a trailing flag with no
# value fails as EX_USAGE instead of crashing under `set -u`.
# ============================================================================
PARSED_IMAGE=""
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
# Centralized BIRTH function.  [Expert B structure + Expert C isolation]
# EVERY launch funnels through here -- there is no second code path that creates
# a container. It validates+clamps caps, stamps the mandatory label set, applies
# the safe-by-default isolation posture + krun annotations + rlimits, creates the
# worktree (the single rw :Z surface), wires net/mounts/env/ssh-agent, and
# base64-transports the workload, assembling the full argv into BIRTH_ARGV.
#
# Ephemeral runs are given a DETERMINISTIC managed name (`sandbox-<id>`) so the
# trap layer can force-remove a half-born container even if podman is SIGKILLed
# before --rm fires (closing the orphan window). The base ref is stamped as a
# label parallel to .worktree.
# ============================================================================

# Set by build_birth_argv for the trap / labels / reporting.
BIRTH_ID=""        # short random id (also the LBL_ID value)
BIRTH_NAME=""      # the container name we actually pass to podman (always set)
BIRTH_WORKTREE=""  # worktree path for trap rollback
declare -a BIRTH_ARGV

# build_birth_argv <persist 0|1> <image>
build_birth_argv() {
  local persist="$1" image="$2"

  # --- validate + clamp resource caps (integer-validated; krun fatals else) ---
  local cpus mem
  cpus="$(krun_cpus "$OPT_CPUS")"
  mem="$(krun_ram_mib "$OPT_MEMORY")"

  # --- identity + worktree (the tool creates it; it is the ONLY rw surface) ---
  local id ts wt name base
  id="$(gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wt="$(create_worktree "$id")"
  base="$(_worktree_base_ref "$wt")"
  BIRTH_ID="$id"
  BIRTH_WORKTREE="$wt"

  # keep uses the user --name; run gets a deterministic managed name so the trap
  # and reap can always address it.
  if [ "$persist" = 1 ]; then
    [ -n "$OPT_NAME" ] || die "$EX_USAGE" "keep requires --name"
    name="$OPT_NAME"
  else
    name="${MANAGED_BY}-${id}"
  fi
  BIRTH_NAME="$name"

  local -a argv=(run)

  # --- Layer 1 of teardown: ephemeral is unconditionally --rm; keep omits it --
  if [ "$persist" = 1 ]; then
    argv+=(--name "$name" -d)
  else
    argv+=(--name "$name" --rm)
  fi

  argv+=(--runtime "$SANDBOX_RUNTIME")

  # --- mandatory label set (the single source of truth) -----------------------
  argv+=(--label "${LBL_MANAGED}=${MANAGED_BY}")
  argv+=(--label "${LBL_CREATED}=${ts}")
  argv+=(--label "${LBL_ID}=${id}")
  argv+=(--label "${LBL_WORKTREE}=${wt}")
  argv+=(--label "${LBL_NAME}=${name}")
  [ -n "$base" ] && argv+=(--label "${LBL_BASE}=${base}")
  if [ "$persist" = 1 ]; then
    argv+=(--label "${LBL_PERSIST}=true")
  fi

  # --- safe-by-default isolation posture (centralized; SELinux stays on) ------
  apply_isolation_flags argv

  # --- krun resource annotations (the real enforcing knobs) -------------------
  apply_krun_annotations argv "$cpus" "$mem"

  # --- rlimits: a second cap layer beyond cpu/ram -----------------------------
  apply_rlimits argv

  # --- network posture (fail-CLOSED; never trust the engine default) ----------
  case "$OPT_NETWORK" in
    none)
      argv+=(--network none)
      if [ "${#PUBLISH_PORTS[@]}" -gt 0 ]; then
        warn "--publish ignored: it is a no-op under --network none (podman gotcha)"
      fi
      ;;
    loopback)
      # pasta/passt userspace networking; publish is forced to the host loopback
      # so a sandbox can serve localhost without exposing beyond it.
      argv+=(--network pasta)
      local p
      for p in "${PUBLISH_PORTS[@]}"; do
        case "$p" in
          *:*) argv+=(--publish "127.0.0.1:${p}") ;;
          *)   die "$EX_USAGE" "--publish expects HOST:GUEST, got: '$p'" ;;
        esac
      done
      ;;
    *)
      die "$EX_USAGE" "--network must be 'none' or 'loopback', got: '$OPT_NETWORK'"
      ;;
  esac

  # --- the single rw mount: the tool-created worktree, :Z private relabel -----
  local guest_workdir="${OPT_WORKDIR:-/workspace}"
  argv+=(--volume "${wt}:${guest_workdir}:Z")
  argv+=(--workdir "$guest_workdir")

  # --- extra mounts: READ-ONLY by default; rw only if explicitly :rw given ----
  #     Format HOST:GUEST[:MODE]. Dies on a malformed mount or a bad mode.
  local m host guest mode rest
  for m in "${EXTRA_MOUNTS[@]}"; do
    host="${m%%:*}"
    rest="${m#*:}"
    if [ "$rest" = "$m" ]; then
      die "$EX_USAGE" "--mount expects HOST:GUEST[:ro|:rw], got: '$m'"
    fi
    guest="${rest%%:*}"
    mode="${rest#*:}"
    [ "$mode" = "$rest" ] && mode=""   # no mode suffix present
    case "$mode" in
      rw|rw,Z|Z,rw) argv+=(--volume "${host}:${guest}:rw,z") ;;
      ro|ro,Z|Z,ro|'') argv+=(--volume "${host}:${guest}:ro,z") ;;
      *)            die "$EX_USAGE" "--mount mode must be ro or rw, got ':${mode}' in '$m'" ;;
    esac
  done

  # --- env (explicit K=V passthrough only; we never bulk-forward host env) ----
  local e
  for e in "${EXTRA_ENV[@]}"; do
    argv+=(--env "$e")
  done

  # --- ssh-agent forwarding (socket only; hard-fail if no agent) --------------
  if [ "$OPT_SSH_AGENT" = 1 ]; then
    apply_ssh_agent argv
  fi

  # --- interactive tty --------------------------------------------------------
  # -it is only valid for foreground launches; keep uses -d so -it would be
  # contradictory and dead. Only append it on the ephemeral (non-persist) path.
  [ "$OPT_TTY" = 1 ] && [ "$persist" = 0 ] && argv+=(-it)

  # --- image + workload --------------------------------------------------
  # Pass words DIRECTLY as podman trailing args: podman/krun preserves each
  # element of the argv array verbatim with no shell re-interpretation.
  # This is the correct transport for a word list (e.g. `-- echo hello world`).
  # Use encode_script only when the caller explicitly passes a single '-c SCRIPT'
  # string intended to be interpreted as a shell script.
  argv+=("$image")
  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    argv+=("${WORKLOAD_CMD[@]}")
  fi

  BIRTH_ARGV=("${argv[@]}")
}

# ============================================================================
# Three-layer teardown.  [Expert B]
#   Layer 1: --rm           -- clean exit (ephemeral; set on the run argv above)
#   Layer 2: signal/trap    -- crash / Ctrl-C path, trap-disarm-FIRST idiom
#   Layer 3: reap           -- label-driven backstop (below); also reconciles
#                              cheaply atop every birth verb
#
# State the trap rolls back. Set just before launch, cleared on clean success.
# ============================================================================
TRAP_CONTAINER=""   # container name/id to force-remove on abnormal exit
TRAP_WORKTREE=""    # worktree to guard-remove on abnormal exit
TRAP_PERSIST=0      # if 1, a *successfully born* kept sandbox -> never auto-destroy

# ephemeral_trap -- the cleanup handler. Trap-disarm-FIRST so a signal arriving
# mid-cleanup cannot re-enter and double-fire. Re-`exit $rc` after cleanup so a
# signal-derived 130/143 is faithfully surfaced (a bare `return` from an EXIT
# handler would lose it).
ephemeral_trap() {
  local rc=$?
  trap '' EXIT INT TERM            # disarm FIRST -- no re-entrant cleanup (#22: ERR arm dropped)

  if [ "$TRAP_PERSIST" = 1 ]; then
    exit "$rc"
  fi

  if [ -n "$TRAP_CONTAINER" ]; then
    debug "trap: force-removing container $TRAP_CONTAINER (rc=$rc)"
    podman_q rm -f -v "$TRAP_CONTAINER" >/dev/null 2>&1 || true
  fi
  if [ -n "$TRAP_WORKTREE" ]; then
    debug "trap: guard-removing worktree $TRAP_WORKTREE"
    # Unforced: a worktree holding unpushed work is PRESERVED across a crash.
    remove_worktree "$TRAP_WORKTREE" 0 >/dev/null 2>&1 || true
  fi
  exit "$rc"
}

arm_trap()    { trap ephemeral_trap EXIT INT TERM; }   # #22: ERR dropped; EXIT under set -e already covers the error path
disarm_trap() { trap - EXIT INT TERM; }

# ============================================================================
# Verb: run -- unconditionally ephemeral one-shot, foreground, exit-code-faithful.
# `--rm` is always on with no off-switch (a distinct WORD for persistence, never
# a flag that can be fat-fingered). Funnels through build_birth_argv(persist=0).
# ============================================================================
verb_run() {
  parse_birth_args run "$@"
  local image="$PARSED_IMAGE"
  [ -n "$image" ] || die "$EX_USAGE" "run requires an <image> (workload goes after --)"

  precheck
  reap_sweep_quiet          # Layer 3: cheap reconcile at the top of the invocation

  build_birth_argv 0 "$image"

  # Arm Layer 2 around the foreground launch. We KNOW the container name
  # (BIRTH_NAME) so the trap can force-remove a half-born container even if
  # podman is SIGKILLed before --rm fires -- the orphan window is closed.
  TRAP_PERSIST=0
  TRAP_CONTAINER="$BIRTH_NAME"
  TRAP_WORKTREE="$BIRTH_WORKTREE"
  arm_trap

  info "launching ephemeral sandbox ${BIRTH_ID} (image=$image, net=$OPT_NETWORK)"
  local rc=0
  # Optional foreground time-bound. `timeout` propagates the child's code; on a
  # timeout it exits 124 (distinct from a workload code, surfaced verbatim).
  if [ -n "$OPT_TIMEOUT" ]; then
    local tsecs; tsecs="$(duration_to_secs "$OPT_TIMEOUT")"
    trace "podman ${BIRTH_ARGV[*]} (timeout ${tsecs}s)"
    timeout --signal=TERM "$tsecs" "$PODMAN" "${BIRTH_ARGV[@]}" || rc=$?
  else
    podman_q "${BIRTH_ARGV[@]}" || rc=$?
  fi

  # Clean exit: --rm removed the container; tear down the worktree (guarded --
  # unpushed work is preserved). Disarm FIRST so the EXIT trap cannot re-run it.
  disarm_trap
  remove_worktree "$BIRTH_WORKTREE" 0 || true
  exit "$rc"          # propagate the workload's exit code verbatim
}

# ============================================================================
# Verb: keep -- PERSISTENT sandbox: omits --rm, stamps sandbox.persist=true.
# Loud by design. A PARTIAL birth (launch failure) still rolls back the worktree;
# a SUCCESSFUL birth flips TRAP_PERSIST so nothing is torn down.
# ============================================================================
verb_keep() {
  parse_birth_args keep "$@"
  local image="$PARSED_IMAGE"
  [ -n "$image" ]    || die "$EX_USAGE" "keep requires an <image>"
  [ -n "$OPT_NAME" ] || die "$EX_USAGE" "keep requires --name <name>"
  # keep is detached (-d); a foreground timeout is meaningless. Reject here
  # (not in the shared parse_birth_args, which verb_run also uses) so run
  # can still accept --timeout without being affected.
  [ -z "$OPT_TIMEOUT" ] \
    || die "$EX_USAGE" "keep: --timeout is not applicable to a detached sandbox (use 'reap --until' for age-based cleanup)"

  # #16: precheck (and reap_sweep_quiet) MUST fire before the name-collision
  # query to honour the verb-zero contract (precondition gates first).
  # Name uniqueness is enforced by podman itself; a concurrent keep that loses
  # the race is cleanly rolled back by podman with no manual lock needed.
  precheck
  reap_sweep_quiet

  # Refuse to collide with an existing managed sandbox of the same name.
  if podman_q ps -a -q --filter "$(our_filter)" \
        --filter "label=${LBL_NAME}=${OPT_NAME}" 2>/dev/null | grep -q .; then
    die "$EX_GUARD" "a managed sandbox named '${OPT_NAME}' already exists (rm it first)"
  fi

  build_birth_argv 1 "$image"

  # Until birth is confirmed, a failure should roll back BOTH the half-created
  # container and the worktree -> TRAP_PERSIST stays 0 for now.
  TRAP_PERSIST=0
  TRAP_CONTAINER="$BIRTH_NAME"
  TRAP_WORKTREE="$BIRTH_WORKTREE"
  arm_trap

  warn "PERSISTENT sandbox '${OPT_NAME}' will SURVIVE exit -- 'stop'/'rm'/'reap' to remove it"
  info "launching kept sandbox ${BIRTH_ID} name=${OPT_NAME} (image=$image)"

  local rc=0
  podman_q "${BIRTH_ARGV[@]}" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -ne 0 ]; then
    # Partial birth: disarm, then explicitly roll back (trap would too, but be
    # deterministic about the exit code we surface).
    disarm_trap
    podman_q rm -f -v "$BIRTH_NAME" >/dev/null 2>&1 || true
    remove_worktree "$BIRTH_WORKTREE" 0 || true
    die "$EX_LAUNCH" "keep: engine failed to launch '${OPT_NAME}' (rc=$rc)"
  fi

  # Born successfully: durable now. Disarm and clear rollback state.
  disarm_trap
  TRAP_PERSIST=1
  TRAP_CONTAINER=""
  TRAP_WORKTREE=""
  emit_kv id "$BIRTH_ID" name "$OPT_NAME" worktree "$BIRTH_WORKTREE"
  return 0
}

# ============================================================================
# Verb: start -- restart a stopped kept sandbox (prevents worktree orphaning).
# [Expert A]
# ============================================================================
verb_start() {
  local tty=0 name=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -it|-ti) tty=1 ;;
      -h|--help) usage 0 start ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "start: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "start requires <name>"
  precheck

  # #11: die() inside $(...) is swallowed; capture-and-check so EX_NOTFOUND is
  # surfaced rather than podman acting on an empty id.
  local id
  if ! id="$(resolve_managed "$name")"; then exit "$EX_NOTFOUND"; fi
  info "starting kept sandbox '$name' ($id)"
  if [ "$tty" = 1 ]; then
    # Interactive attach is only meaningful if the sandbox was originally kept
    # with -it (which sets Tty=true and OpenStdin=true at create time).
    # podman cannot override create-time tty/interactive on start -ai.
    local _tty _stdin
    _tty="$(podman_q inspect --format '{{.Config.Tty}}' "$id" 2>/dev/null || true)"
    _stdin="$(podman_q inspect --format '{{.Config.OpenStdin}}' "$id" 2>/dev/null || true)"
    if [ "$_tty" != "true" ] || [ "$_stdin" != "true" ]; then
      warn "start -it: sandbox '$name' was not born with 'keep ... -it' (Tty=${_tty:-?}, OpenStdin=${_stdin:-?}) -- interactive stdin will not be available; re-create with 'keep ... -it' if you need a TTY"
    fi
    podman_q start -ai "$id"
  else
    podman_q start "$id" >/dev/null
    emit_kv id "$id" name "$name" status started
  fi
}

# ============================================================================
# Verb: exec -- run a cmd in a RUNNING kept sandbox. Does NOT auto-start.
# [Expert A; workload transport: direct argv pass-through (no shell layer)]
# ============================================================================
verb_exec() {
  reset_opts
  local name="" workdir="" user="" tty=0 ssh_agent=0
  local -a envs=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workdir|-w) need_arg "$#" --workdir; workdir="$2"; shift ;;
      --env|-e)     need_arg "$#" --env;     envs+=("$2"); shift ;;
      --user)       need_arg "$#" --user;    user="$2"; shift ;;
      -it|-ti|-i|-t) tty=1 ;;
      --ssh-agent)  ssh_agent=1 ;;
      --timeout)    need_arg "$#" --timeout; OPT_TIMEOUT="$2"; shift ;;
      -h|--help)    usage 0 exec ;;
      --)           shift; WORKLOAD_CMD=("$@"); break ;;
      -*)           die "$EX_USAGE" "exec: unknown flag '$1'" ;;
      *)            if [ -z "$name" ]; then name="$1"; else die "$EX_USAGE" "exec: unexpected arg '$1'"; fi ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "exec requires <name> -- cmd..."
  precheck

  # #11: capture-and-check so die() inside $(...) is not swallowed.
  local id
  if ! id="$(resolve_managed "$name")"; then exit "$EX_NOTFOUND"; fi
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
    # podman exec cannot add mounts; the socket must already be present from
    # birth (apply_ssh_agent mounts it at /run/ssh-agent.sock with --ssh-agent).
    # Inspect the container's mounts to verify the birth marker is in place
    # before setting an env var that would otherwise point at an absent socket.
    local _agent_sock="/run/ssh-agent.sock"
    local _mounted
    _mounted="$(podman_q inspect --format \
      '{{range .Mounts}}{{if eq .Destination "'"${_agent_sock}"'"}}yes{{end}}{{end}}' \
      "$id" 2>/dev/null || true)"
    [ "$_mounted" = "yes" ] \
      || die "$EX_GUARD" "exec --ssh-agent: sandbox '$name' was not born with --ssh-agent (socket not mounted at ${_agent_sock})"
    eargv+=(--env "SSH_AUTH_SOCK=${_agent_sock}")
  fi
  eargv+=("$id")

  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    # Pass words directly: podman exec preserves each argv element verbatim.
    # No shell layer; metacharacters in agent-written args are not interpreted.
    eargv+=("${WORKLOAD_CMD[@]}")
  else
    [ "$tty" = 1 ] || die "$EX_USAGE" "exec needs a command (-- cmd...) unless -it"
    eargv+=(/bin/bash)
  fi

  local rc=0
  # Wire --timeout: exec is foreground, so a time-bound is meaningful.
  # timeout propagates the child's exit code; 124 on a timeout (distinct).
  if [ -n "$OPT_TIMEOUT" ]; then
    local tsecs; tsecs="$(duration_to_secs "$OPT_TIMEOUT")"
    timeout --signal=TERM "$tsecs" "$PODMAN" "${eargv[@]}" || rc=$?
  else
    podman_q "${eargv[@]}" || rc=$?
  fi
  exit "$rc"
}

# ============================================================================
# Verb: logs -- post-mortem stdout/stderr.  [Expert A]
# ============================================================================
verb_logs() {
  local follow=0 tail="" name=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--follow) follow=1 ;;
      -n|--tail) need_arg "$#" --tail; tail="$2"; shift ;;
      -h|--help) usage 0 logs ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "logs: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "logs requires <name>"
  # #17: logs is read-only/post-mortem; gate on podman only, not KVM/krun.
  precheck_podman_only

  # #11: capture-and-check so die() inside $(...) is not swallowed.
  local id
  if ! id="$(resolve_managed "$name")"; then exit "$EX_NOTFOUND"; fi
  local -a largv=(logs)
  [ "$follow" = 1 ] && largv+=(-f)
  [ -n "$tail" ] && { require_uint "$tail" "--tail"; largv+=(--tail "$tail"); }
  largv+=("$id")
  podman_q "${largv[@]}"
}

# ============================================================================
# Verb: ls -- list managed sandboxes. Machine-readable BY DEFAULT.  [Expert D]
# Selection EXCLUSIVELY by the managed-by label; header suppressed under --json.
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

  # #17: ls is read-only; gate on podman only (no KVM/krun requirement).
  precheck_podman_only

  local -a psargs=(ps --filter "$(our_filter)")
  [ "$all" = 1 ] && psargs+=(-a)

  if [ "$json" = 1 ]; then
    podman_q "${psargs[@]}" --format \
      '{"id":"{{.ID}}","name":"{{index .Labels "'"${LBL_NAME}"'"}}","status":"{{.Status}}","created":"{{index .Labels "'"${LBL_CREATED}"'"}}","worktree":"{{index .Labels "'"${LBL_WORKTREE}"'"}}","persist":"{{index .Labels "'"${LBL_PERSIST}"'"}}","ports":"{{.Ports}}"}'
  else
    printf 'ID\tNAME\tSTATUS\tPERSIST\tPORTS\tWORKTREE\tCREATED\n'
    podman_q "${psargs[@]}" --format \
      '{{.ID}}	{{index .Labels "'"${LBL_NAME}"'"}}	{{.Status}}	{{index .Labels "'"${LBL_PERSIST}"'"}}	{{.Ports}}	{{index .Labels "'"${LBL_WORKTREE}"'"}}	{{index .Labels "'"${LBL_CREATED}"'"}}'
  fi
}

# ============================================================================
# Verb: inspect -- single-object config/status. The --json compose contract.
# [Expert A]
# ============================================================================
verb_inspect() {
  local json=0 name=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      -h|--help) usage 0 inspect ;;
      --) shift; break ;;
      -*) die "$EX_USAGE" "inspect: unknown flag '$1'" ;;
      *) name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$EX_USAGE" "inspect requires <name>"
  # #17: inspect is read-only; gate on podman only (no KVM/krun requirement).
  precheck_podman_only

  # #11: capture-and-check so die() inside $(...) is not swallowed.
  local id
  if ! id="$(resolve_managed "$name")"; then exit "$EX_NOTFOUND"; fi
  if [ "$json" = 1 ]; then
    podman_q inspect "$id"
  else
    # shellcheck disable=SC2016  # podman Go template, not shell expansion.
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
# Verb: stop -- graceful stop of kept sandboxes; keeps worktree.  [Expert A]
# ============================================================================
verb_stop() {
  local force=0 timeout=10
  local -a names=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--force) force=1 ;;
      -t|--timeout) need_arg "$#" --timeout; timeout="$2"; shift ;;
      -h|--help) usage 0 stop ;;
      --) shift; names+=("$@"); break ;;
      -*) die "$EX_USAGE" "stop: unknown flag '$1'" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  [ "${#names[@]}" -gt 0 ] || die "$EX_USAGE" "stop requires <name...>"
  require_uint "$timeout" "--timeout"
  # #17: stop is pure-cleanup; gate on podman only, not KVM/krun.
  precheck_podman_only

  local n id wt rc=0
  for n in "${names[@]}"; do
    id="$(resolve_managed "$n")" || { rc=$?; continue; }
    # Warn (do not refuse) on unpushed work; stop preserves the worktree anyway.
    wt="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_WORKTREE}\" }}" "$id" 2>/dev/null || true)"
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
# [Expert A]
# ============================================================================
verb_rm() {
  local force=0 keep_wt=0
  local -a names=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--force) force=1 ;;
      --keep-worktree) keep_wt=1 ;;
      -h|--help) usage 0 rm ;;
      --) shift; names+=("$@"); break ;;
      -*) die "$EX_USAGE" "rm: unknown flag '$1'" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  [ "${#names[@]}" -gt 0 ] || die "$EX_USAGE" "rm requires <name...>"
  # #17: rm is pure-cleanup; gate on podman only, not KVM/krun.
  precheck_podman_only

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
# Verb: reap -- Layer-3 label-driven backstop.  [Expert B]
# Touches ONLY our labelled set; never host-global state (the arrakis
# anti-pattern). Runs verbosely as a verb and cheaply (silent) atop birth verbs.
# ============================================================================

# reap_core <dry-run 0|1> <until-secs ''|N> <emit 0|1>
# Removes managed containers that leaked (ephemeral + exited/dead) and, with an
# age cut (--until), aged NON-running kept sandboxes. Never kills a healthy
# running sandbox on a time sweep. Worktree teardown is always guarded and never
# forced. Rows for --dry-run/--json are TSV on stdout: `<verdict>\t<id>\t<status>\t<reason>`.
reap_core() {
  local dry="$1" until_secs="$2" emit="$3"
  local now reaped=0
  now="$(date -u +%s)"

  # Candidate set is EXCLUSIVELY our labelled containers (never name substring).
  local ids
  ids="$(podman_q ps -a -q --filter "$(our_filter)" 2>/dev/null || true)"
  if [ -z "$ids" ]; then
    [ "$emit" = 1 ] && [ "$dry" != 1 ] && info "reap: nothing managed found"
    return 0
  fi

  local id status persist created created_epoch age doomed reason wt
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    status="$(container_state "$id")"
    persist="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_PERSIST}\" }}" "$id" 2>/dev/null || true)"

    doomed=0; reason=""
    # #8: doom any non-live state for non-persistent containers so half-born
    # (created/initialized) ephemeral orphans are also reaped. 'dead' was
    # dead code (podman 4+ uses 'exited'); dropping it clarifies the intent.
    # Persistent containers are only reaped by the age cut below.
    case "$status" in
      running|paused|removing|stopping)
        # Live / transitional states: never time-killed here.
        :
        ;;
      *)
        [ "$persist" = true ] || { doomed=1; reason="ephemeral leak (${status})"; }
        ;;
    esac

    # Age cut against sandbox.created, for NON-running kept sandboxes only.
    if [ "$doomed" = 0 ] && [ -n "$until_secs" ] && [ "$persist" = true ] && [ "$status" != running ]; then
      created="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_CREATED}\" }}" "$id" 2>/dev/null || true)"
      if [ -n "$created" ]; then
        created_epoch="$(date -u -d "$created" +%s 2>/dev/null || echo 0)"
        if [ "$created_epoch" -gt 0 ]; then
          age=$(( now - created_epoch ))
          if [ "$age" -ge "$until_secs" ]; then
            doomed=1; reason="kept+aged ${age}s>=${until_secs}s"
          fi
        fi
      fi
    fi

    [ "$doomed" = 1 ] || continue

    wt="$(podman_q inspect --format "{{ index .Config.Labels \"${LBL_WORKTREE}\" }}" "$id" 2>/dev/null || true)"
    if [ "$dry" = 1 ]; then
      [ "$emit" = 1 ] && printf 'would-reap\t%s\t%s\t%s\n' "$id" "$status" "$reason"
      continue
    fi

    debug "reap: removing $id ($reason)"
    podman_q rm -f -v "$id" >/dev/null 2>&1 || true
    # #25: worktree teardown here is BEST-EFFORT under concurrency -- there is
    # no mutex; a concurrent reap on the same worktree may race remove_worktree
    # but podman rm -f is idempotent and git errors are swallowed. This is
    # intentional for the accident model. Named graduation signal: add a real
    # lock here if concurrency-safe allocation becomes a requirement.
    # Guarded, never forced: unpushed work survives a reap.
    if [ -n "$wt" ]; then
      remove_worktree "$wt" 0 >/dev/null 2>&1 || true
    fi
    [ "$emit" = 1 ] && printf 'reaped\t%s\t%s\t%s\n' "$id" "$status" "$reason"
    reaped=$(( reaped + 1 ))
  done <<EOF
$ids
EOF

  [ "$emit" = 1 ] && [ "$dry" != 1 ] && info "reap: removed ${reaped} sandbox(es)"
  return 0
}

# reap_sweep_quiet -- cheap reconcile at the top of birth verbs. No lock by
# design (no-lock concurrency: the sweep is idempotent and `podman rm -f` is
# safe to race; a missing/already-removed id is a no-op). This is a named
# graduation signal: the day we need concurrency-safe allocation, add a real
# mutex or leave bash. Runs only the ephemeral-leak path (no age cut).
reap_sweep_quiet() {
  reap_core 0 "" 0 >/dev/null 2>&1 || true
}

verb_reap() {
  local dry=0 json=0 until_dur="" until_secs=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --until)   need_arg "$#" --until; until_dur="$2"; shift ;;
      --dry-run) dry=1 ;;
      --json)    json=1 ;;
      -h|--help) usage 0 reap ;;
      *) die "$EX_USAGE" "reap: unexpected arg '$1'" ;;
    esac
    shift
  done
  [ -n "$until_dur" ] && until_secs="$(duration_to_secs "$until_dur")"

  # #17: reap is the backstop cleanup verb; gate on podman only so it is not
  # blocked exactly when krun/KVM are broken (when cleanup matters most).
  precheck_podman_only
  # Disarm any inherited trap before sweeping (avoid re-entrant double cleanup).
  disarm_trap

  if [ "$json" = 1 ]; then
    # Always compute the candidate list via a dry pass so JSON reports exactly
    # what was (or would be) acted on, then perform the real sweep if not dry.
    printf '{"dry_run":%s,"items":[' "$([ "$dry" = 1 ] && echo true || echo false)"
    local first=1 verdict cid cstatus creason
    while IFS=$'\t' read -r verdict cid cstatus creason; do
      [ -n "$cid" ] || continue
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"verdict":"%s","id":"%s","status":"%s","reason":"%s"}' \
        "$verdict" "$cid" "$cstatus" "$(json_escape "$creason")"
    done < <(reap_core 1 "$until_secs" 1)
    printf ']}\n'
    [ "$dry" = 1 ] || reap_core 0 "$until_secs" 0 || true
  else
    reap_core "$dry" "$until_secs" 1
  fi
}

# ============================================================================
# Top-level dispatch.  [Expert D]
# Forwards the FULL remaining argv to each verb (so a verb's own parser owns its
# flags). `version` prints to STDOUT (data a script may capture); help to stderr.
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

main "$@"
