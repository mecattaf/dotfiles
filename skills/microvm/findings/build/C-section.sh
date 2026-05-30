#!/usr/bin/env bash
#
# ============================================================================
# AGENT C SECTION -- ISOLATION & KRUN
# ============================================================================
#
# Hardened replacements for the isolation / krun-annotation / doctor surface of
# the sandbox tool (Agent A spine). These splice over A's functions of the same
# name; interface deviations are called out in the structured summary.
#
# Functions provided here (each headed by a `# ---- <name>` comment):
#   Resource-cap constants + validation:
#     is_uint, require_uint, clamp, krun_cpus, krun_ram_mib
#   Centralized safe-flags / birth (isolation-relevant body):
#     apply_isolation_flags, apply_krun_annotations, apply_rlimits,
#     apply_ssh_agent, build_birth_argv
#   doctor capability probes + the gate:
#     _dr, probe_kvm, probe_podman, probe_runtime_registered,
#     probe_crun_libkrun, probe_libkrun_so, probe_smoke,
#     doctor_emit, json_escape, run_doctor, precheck
#
# Engine fact-base (sourced from STAGE2 per-repo findings on crun/libkrun):
#   * krun reads OCI annotations run.oci.krun.cpus / run.oci.krun.ram_mib.
#   * Annotation values are parsed as STRICT positive integers; a non-integer or
#     negative value is a FATAL EXIT_FAILURE inside crun -- so we validate in
#     bash BEFORE stamping.
#   * krun.ram_mib values <= 128 are SILENTLY IGNORED (LIBKRUN_MINIMUM_RAM_MIB);
#     we floor well above that.
#   * krun.cpus is hard-capped at 16 (LIBKRUN_MAX_VCPUS); we clamp to it.
#   * /dev/kvm is mandatory; krun auto-injects the device, so we must NOT pass
#     --device /dev/kvm ourselves -- only assert access in doctor.
#   * libkrun.so.1 + libkrunfw.so.<ABI=5> must both be loadable & ABI-matched.
#   * crun must be built with the +LIBKRUN feature; krun is a crun symlink.
#   * Guest==VMM==user is ONE security context -> keys never enter the guest;
#     ssh-agent is forwarded as a socket only.
#   * --network none must come from podman; libkrun's own default (TSI) is
#     fail-OPEN, so we never trust the engine default.
# ============================================================================

# ----------------------------------------------------------------------------
# Resource-clamp bounds (krun annotation knobs).
# ----------------------------------------------------------------------------
readonly KRUN_MIN_MIB=256          # floor strictly above krun's silent-ignore (<=128)
readonly KRUN_MAX_MIB=16384        # sane upper bound; krunvm uses the same ceiling
readonly KRUN_MIN_VCPU=1
readonly KRUN_MAX_VCPU=16          # LIBKRUN_MAX_VCPUS hard cap
readonly DEF_CPUS=1                # conservative accident-model default
readonly DEF_MEMORY=1024           # 1 GiB: above the floor, comfortable for a workload

# Accepted shared-library / ABI matrix for doctor (open question in the brief,
# resolved here with a sensible default + comment). libkrun is at soname major 1;
# libkrunfw ships ABI_VERSION=5 on current Fedora. We accept the current majors
# and ALSO accept an adjacent libkrunfw major so a Fedora bump does not red-line
# doctor spuriously -- the decisive proof of compatibility is the smoke test.
readonly LIBKRUN_SONAME="libkrun.so.1"
readonly LIBKRUNFW_SONAME_GLOB="libkrunfw.so.*"   # e.g. libkrunfw.so.5(.4.0)
readonly LIB_SEARCH_DIRS="/usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib /lib64 /lib"

# ----------------------------------------------------------------------------
# is_uint <value> -- 0 iff a NON-EMPTY base-10 unsigned integer with no sign,
# no leading +, no whitespace. Deliberately strict because krun fatals on a
# malformed annotation rather than degrading.
# ----------------------------------------------------------------------------
is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;   # empty or any non-digit -> reject
    *)           return 0 ;;
  esac
}

# ----------------------------------------------------------------------------
# require_uint <value> <flag-name> -- die EX_USAGE unless <value> is an unsigned
# integer. krun treats a bad krun.cpus/krun.ram_mib as fatal, so we never let a
# malformed value reach the engine.
# ----------------------------------------------------------------------------
require_uint() {
  is_uint "$1" || die "$EX_USAGE" "$2 must be a non-negative integer, got: '${1:-}'"
}

# ----------------------------------------------------------------------------
# clamp <value> <min> <max> -- print value bounded to [min,max]. Pure arithmetic;
# caller must have validated <value> as an integer first (we re-guard anyway).
# ----------------------------------------------------------------------------
clamp() {
  local v="$1" lo="$2" hi="$3"
  is_uint "$v" || v="$lo"
  (( v < lo )) && v="$lo"
  (( v > hi )) && v="$hi"
  printf '%s' "$v"
}

# ----------------------------------------------------------------------------
# krun_cpus <requested> -- validate + clamp the vCPU count for run.oci.krun.cpus.
# Warns (to stderr, via warn) when clamping so the operator knows the request
# was adjusted. Returns the value on stdout.
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# krun_ram_mib <requested> -- validate + clamp guest RAM for run.oci.krun.ram_mib.
# A value <= 128 would be SILENTLY IGNORED by krun (it would fall back to the OCI
# memory limit or 1024), so we hard-floor at KRUN_MIN_MIB and warn -- the cap the
# operator asked for would otherwise not stick.
# ----------------------------------------------------------------------------
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
# Centralized SAFE-FLAGS. These helpers each APPEND to a caller-named array via
# a nameref so build_birth_argv stays readable and every isolation decision has
# one auditable home. Each flag below reaches a REAL engine arg (no metadata-only
# no-ops -- the ERA fail-open lesson).
# ============================================================================

# ----------------------------------------------------------------------------
# apply_isolation_flags <argv-array-name>
#   The non-negotiable safe-by-default posture applied to EVERY birth:
#     --security-opt no-new-privileges  (block setuid privilege escalation)
#     --cap-drop ALL                    (drop every Linux capability)
#     --read-only                       (rootfs is immutable; only the worktree
#                                        bind below is writable)
#   SELinux STAYS ON: we deliberately never pass `--security-opt label=disable`.
#   We rely on podman's default --read-only-tmpfs=true so /tmp,/run,/var/tmp get
#   small writable tmpfs mounts -- workloads need a scratch /tmp, and a tmpfs is
#   discarded with the VM, so it does not widen the host blast radius.
# ----------------------------------------------------------------------------
apply_isolation_flags() {
  local -n _argv="$1"
  _argv+=(--security-opt no-new-privileges)
  _argv+=(--cap-drop ALL)
  _argv+=(--read-only)
  # --read-only-tmpfs is podman's default-true; state it explicitly so behaviour
  # is pinned regardless of host containers.conf overrides (open-question call:
  # /tmp IS writable, via discarded tmpfs).
  _argv+=(--read-only-tmpfs=true)
}

# ----------------------------------------------------------------------------
# apply_krun_annotations <argv-array-name> <cpus> <ram_mib>
#   Stamp the krun resource annotations. crun-krun reads run.oci.krun.* OCI
#   annotations; podman passes them through verbatim. Values MUST already be
#   validated integers (krun fatals otherwise) -- callers route through
#   krun_cpus/krun_ram_mib. These are the REAL enforcing knobs
#   (krun_set_vm_config(num_vcpus, ram_mib)), not advisory metadata.
# ----------------------------------------------------------------------------
apply_krun_annotations() {
  local -n _argv="$1"
  local cpus="$2" mem="$3"
  _argv+=(--annotation "run.oci.krun.cpus=${cpus}")
  _argv+=(--annotation "run.oci.krun.ram_mib=${mem}")
}

# ----------------------------------------------------------------------------
# apply_rlimits <argv-array-name>
#   A SECOND cap layer beyond the krun vCPU/RAM annotations. cpu/ram caps alone
#   do not stop an fd or process-table blowup (the libkrun lesson: caps cover
#   cpu/ram, rlimits cover the rest). These map onto podman --ulimit, which crun
#   sets as POSIX rlimits on the guest init before exec.
#     nofile  -- open file descriptors (soft:hard)
#     nproc   -- processes/threads (fork-bomb backstop)
#   Conservative ceilings sized for a build/run workload, not a server farm.
# ----------------------------------------------------------------------------
apply_rlimits() {
  local -n _argv="$1"
  _argv+=(--ulimit "nofile=4096:8192")
  _argv+=(--ulimit "nproc=1024:2048")
}

# ----------------------------------------------------------------------------
# apply_ssh_agent <argv-array-name>
#   ssh-agent forwarding: bind the host's $SSH_AUTH_SOCK INTO the guest and set
#   the env var to the in-guest path. ONLY the agent socket crosses the boundary
#   -- private keys NEVER enter the guest (guest==VMM==user is one security
#   context, so a key copied in is as exposed as on the host). HARD-FAILS
#   (EX_GUARD) if no usable agent, so --ssh-agent can never silently no-op.
#   The socket is bound rw (:Z private SELinux relabel) because ssh-agent needs a
#   bidirectional connection; it is a socket, not a data mount.
# ----------------------------------------------------------------------------
apply_ssh_agent() {
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

# ----------------------------------------------------------------------------
# build_birth_argv <persist 0|1> <image>
#   THE centralized birth assembler (isolation-owned body). Funnels every launch
#   through one path: validate+clamp caps, stamp the mandatory label set, apply
#   the safe-by-default isolation posture + krun annotations + rlimits, create
#   the worktree (the single rw :Z surface), wire net/mounts/env/ssh-agent, and
#   base64-transport the workload command. Populates the global BIRTH_ARGV array
#   plus BIRTH_ID / BIRTH_WORKTREE for the trap layer.
#
#   Interface note: identical name/signature/globals to A's build_birth_argv so
#   the integrator can splice 1:1. Differences vs A are listed in the summary.
# ----------------------------------------------------------------------------
build_birth_argv() {
  local persist="$1" image="$2"

  # --- validate + clamp resource caps (integer-validated; krun fatals else) ---
  local cpus mem
  cpus="$(krun_cpus "$OPT_CPUS")"
  mem="$(krun_ram_mib "$OPT_MEMORY")"

  # --- identity + worktree (the tool creates it; it is the ONLY rw surface) ---
  local id ts wt guest_workdir
  id="$(gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wt="$(create_worktree "$id")"
  BIRTH_ID="$id"
  BIRTH_WORKTREE="$wt"

  local -a argv=(run)

  # Ephemeral default vs persistence. run is unconditionally --rm; keep omits it.
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

  # --- safe-by-default isolation posture (centralized; SELinux stays on) ---
  apply_isolation_flags argv

  # --- krun resource annotations (the real enforcing knobs) ---
  apply_krun_annotations argv "$cpus" "$mem"

  # --- rlimits: a second cap layer beyond cpu/ram ---
  apply_rlimits argv

  # --- network posture (fail-CLOSED; never trust the engine default) ---
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

  # --- the single rw mount: the tool-created worktree, :Z private relabel ---
  guest_workdir="${OPT_WORKDIR:-/workspace}"
  argv+=(--volume "${wt}:${guest_workdir}:Z")
  argv+=(--workdir "$guest_workdir")

  # --- extra mounts: READ-ONLY by default; rw only if explicitly :rw given ---
  #     Format HOST:GUEST[:MODE]. Anything that is not an explicit rw mode is
  #     forced to :ro (accident-model ergonomics -- the safe default is ro).
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
      rw|rw,Z|Z,rw) argv+=(--volume "${host}:${guest}:rw") ;;
      ro|'')        argv+=(--volume "${host}:${guest}:ro") ;;
      *)            die "$EX_USAGE" "--mount mode must be ro or rw, got ':${mode}' in '$m'" ;;
    esac
  done

  # --- env (explicit K=V passthrough only; we never bulk-forward host env) ---
  local e
  for e in "${EXTRA_ENV[@]}"; do
    argv+=(--env "$e")
  done

  # --- ssh-agent forwarding (socket only; hard-fail if no agent) ---
  if [ "$OPT_SSH_AGENT" = 1 ]; then
    apply_ssh_agent argv
  fi

  # --- interactive tty ---
  [ "$OPT_TTY" = 1 ] && argv+=(-it)

  # --- image + workload (base64-transported to dodge shell-quoting bugs) ---
  #     ERA lesson: encode the command host-side, decode in-guest, hand to bash,
  #     so arbitrary agent-written code crosses the boundary without any
  #     host-side shell-quoting hazard. The guest wrapper is minimal: decode the
  #     payload and `exec bash -c` it.
  #
  #     Two intent shapes, disambiguated by element count after `--`:
  #       * ONE element  -> treat it as a SHELL SCRIPT body (the "run this code"
  #         case a coding agent uses: `-- 'for i in 1 2; do ...; done'`). Encoded
  #         verbatim; bash -c runs it as a program.
  #       * MULTIPLE elements -> treat them as an ARGV; %q-quote each and join so
  #         `bash -c` reconstructs exactly the command (`-- echo "a b"` runs as
  #         one `echo` with arg `a b`).
  argv+=("$image")
  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    local payload b64 w
    if [ "${#WORKLOAD_CMD[@]}" -eq 1 ]; then
      payload="${WORKLOAD_CMD[0]}"
    else
      payload=""
      for w in "${WORKLOAD_CMD[@]}"; do
        payload+="$(printf '%q' "$w") "
      done
      payload="${payload% }"
    fi
    b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    argv+=(/bin/sh -c "exec bash -c \"\$(printf %s '${b64}' | base64 -d)\"")
  fi

  BIRTH_ARGV=("${argv[@]}")
}

# ============================================================================
# doctor -- verb-zero capability probe. Read-only. Each probe records a PASS/FAIL
# row with an ACTIONABLE remediation, ties the check to the guarantee it
# underwrites, and fails CLOSED with a distinct precondition exit code.
# ============================================================================

# Accumulators for PASS/FAIL rows (parallel arrays for portable JSON emission).
declare -a DOCTOR_NAMES=() DOCTOR_OK=() DOCTOR_MSG=()

# ---- _dr <name> <ok 0|1> <message> -- record one check row.
_dr() {
  DOCTOR_NAMES+=("$1"); DOCTOR_OK+=("$2"); DOCTOR_MSG+=("$3")
}

# ---- probe_kvm -- /dev/kvm present, readable AND writable.
# Guarantee: krun cannot boot a microVM without rw /dev/kvm; it dies at exec
# time with "`/dev/kvm` unavailable" if it is missing or inaccessible.
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

# ---- probe_podman -- podman binary present AND `podman info` succeeds.
# Guarantee: every verb shells out to podman; an unusable podman fails everything.
probe_podman() {
  if command -v "$PODMAN" >/dev/null 2>&1 && podman_q info >/dev/null 2>&1; then
    local ver
    ver="$("$PODMAN" --version 2>/dev/null | head -n1)"
    _dr podman 0 "podman usable (${ver:-version unknown})"; return 0
  fi
  _dr podman 1 "podman not usable -- install podman and verify 'podman info' succeeds"
  return 1
}

# ---- probe_runtime_registered -- the krun runtime is resolvable by podman.
# Guarantee: `--runtime $SANDBOX_RUNTIME` must resolve, or every launch fails.
# We accept ANY of: podman lists it under OCIRuntimes, a krun/crun-krun binary on
# PATH, or the configured runtime name being directly executable.
probe_runtime_registered() {
  local rt="$SANDBOX_RUNTIME"
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

# ---- probe_crun_libkrun -- crun was built with the +LIBKRUN feature.
# Guarantee: krun mode is crun dlopen-ing libkrun; a crun without +LIBKRUN cannot
# enter krun mode at all. crun prints its feature string (e.g. "+SYSTEMD +LIBKRUN
# ...") in `crun --version`.
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

# ---- probe_libkrun_so -- libkrun.so.1 AND an ABI-matched libkrunfw are loadable.
# Guarantee: crun's krun handler dlopens libkrun.so.1, which in turn dlopens
# libkrunfw.so.<ABI>; a missing or ABI-mismatched pair breaks the runtime
# cryptically at launch. We search the standard lib dirs (and honor an
# overriding ldconfig view when available). The exact soname matrix is an open
# question -- we accept libkrun major 1 + any installed libkrunfw major and let
# the smoke test be the final arbiter.
probe_libkrun_so() {
  local found_krun=0 found_fw=0 d

  # Prefer the loader's own view if ldconfig is available (catches non-standard
  # dirs configured in /etc/ld.so.conf.d). Fall back to a directory scan.
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

# ---- probe_smoke -- the decisive end-to-end gate: a --rm --network none microVM
# running `true` under our runtime. This is the ONLY check that proves the whole
# stack actually boots a guest; it also confirms --network none does not break a
# launch. Expensive, so doctor runs it only after the cheap gates pass, and
# precheck() never runs it.
probe_smoke() {
  if podman_q run --rm --runtime "$SANDBOX_RUNTIME" --network none \
        --security-opt no-new-privileges --cap-drop ALL \
        "$SANDBOX_BASE_IMAGE" true >/dev/null 2>&1; then
    _dr smoke 0 "smoke microVM (--rm --network none true) booted and exited 0"; return 0
  fi
  _dr smoke 1 "smoke microVM failed to boot -- krun cannot launch (see the checks above)"
  return 1
}

# ---- json_escape <string> -- minimal escaping for our hand-rolled JSON.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ---- doctor_emit <table|json> -- render the accumulated rows. JSON is a single
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

# ---- run_doctor [--json] -- the full verbose verb-zero gate. Runs every probe,
# emits the report, and exits EX_PRECONDITION if ANY hard gate failed. The smoke
# test only runs when the cheap gates pass (it cannot succeed otherwise, and a
# failed-launch message would be noise).
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

# ---- precheck -- the cheap silent subset run at the top of every birth/lifecycle
# verb. Never boots the smoke container (too costly per-invocation); just asserts
# the host fundamentals so a launch fails fast with an actionable pointer rather
# than a cryptic krun error. precheck owns the DOCTOR_* accumulators outright
# (verbs never read them afterward); it resets before and clears after so a verb
# invocation leaves no stray rows behind. We intentionally do NOT save/restore
# prior rows -- a "${arr[@]:-}" round-trip would inject a spurious empty element
# into a non-empty array under set -u.
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
