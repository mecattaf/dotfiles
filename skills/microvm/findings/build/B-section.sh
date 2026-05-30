#!/usr/bin/env bash
#
# B-section.sh -- Expert B (LIFECYCLE & CLEANUP) hardened functions.
#
# These functions are calibrated to splice into Agent A's spine (A-full.sh).
# They keep A's function NAMES and SIGNATURES wherever sensible so the
# integrator can drop them in. Where an interface had to change, it is called
# out explicitly in `deviations_from_A` in the structured summary.
#
# Domain: centralized BIRTH function + mandatory label set, three-layer
# teardown (--rm + trap-disarm-first + reap backstop), unconditionally-ephemeral
# `run` vs explicit `keep`, the reap verb, and worktree create + safety guards.
#
# Consumed from A's spine (unchanged): _log/trace/debug/info/warn/err/die,
# is_uint/clamp/require_uint/duration_to_secs, gen_id, podman_q, our_filter,
# resolve_managed, is_managed, container_state, precheck, reset_opts,
# parse_birth_args (PARSED_IMAGE), emit_kv, json_escape, and the constants
# (MANAGED_BY, LBL_*, WORKTREE_ROOT, SANDBOX_RUNTIME, EX_*, KRUN_* bounds,
# DEF_CPUS/DEF_MEMORY, OPT_* / EXTRA_* globals).
#
# NEW constant the integrator must add to A's constants block (see deviations):
#   readonly LBL_BASE="${LABEL_NS}.base"   # base git ref the worktree forked from
#
# Pass: bash -n.  set -euo pipefail is inherited from the spine.

# ============================================================================
# Worktree management.
#
# The tool CREATES the worktree (never accepts a pre-made one -> never orphans
# the agent from .git). Removal is path-safety-gated AND unpushed-commit-guarded
# so an accidental teardown can never silently destroy unpushed work.
# ============================================================================

# worktree_path <id> -> the canonical managed path for this sandbox.
# Unchanged from A.
worktree_path() { printf '%s/%s' "$WORKTREE_ROOT" "$1"; }

# base_marker_path <worktree> -> the SIDECAR file recording the fork-point.
# Kept *beside* the worktree (suffix ".base"), never inside it, so it can never
# show up in the worktree's `git status` and falsely trip the unpushed guard.
base_marker_path() { printf '%s.base' "$1"; }

# is_safe_cache_path <path> -- smolvm's guard. Returns 0 ONLY when it is safe to
# remove <path>: it must be a non-empty arg, an existing directory, NOT a
# symlink, strictly *inside* WORKTREE_ROOT, and NOT equal to WORKTREE_ROOT
# itself. Canonicalizes both sides with `pwd -P` so `..`/symlink trickery in the
# argument cannot escape the managed root. Hardened vs A: also rejects when the
# managed root cannot be resolved (fail closed), and treats a path *equal to or
# above* the root uniformly.
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
# already had history when we branched" -- the bug in a naive `git rev-list HEAD`
# test that would refuse to remove EVERY worktree.
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
# "Safe" means: present on the tracking upstream if one exists, otherwise present
# at the recorded base ref the worktree forked from. Conservative / fail-safe:
# if we cannot determine safety we assume work exists (return 0) so the guard
# errs toward PRESERVING data, never toward destroying it.
has_unpushed_commits() {
  local wt="$1"
  # Not a git worktree -> nothing git-tracked to lose. (Plain managed dirs are
  # guarded only by is_safe_cache_path.)
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
  #    Fail safe: if there is ANY commit at HEAD, treat as unpushed.
  if git -C "$wt" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    trace "guard: '$wt' has no upstream and no base ref -- treating HEAD as unpushed"
    return 0
  fi
  return 1
}

# create_worktree <id> -- create the per-sandbox worktree under the managed root.
# Inside a git repo: branch off HEAD into a managed worktree and RECORD the base
# commit (so removal can later distinguish new work from pre-existing history).
# Outside a repo: a plain managed directory (still rw-bound, still inside root).
# Prints the resulting absolute path on stdout; all diagnostics go to stderr.
create_worktree() {
  local id="$1" wt
  wt="$(worktree_path "$id")"
  mkdir -p "$WORKTREE_ROOT"

  # Refuse to clobber an existing path (id collision / leftover). gen_id is
  # random so this is near-impossible, but fail loud rather than reuse.
  if [ -e "$wt" ]; then
    die "$EX_GUARD" "worktree path already exists, refusing to reuse: $wt"
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch base
    branch="sandbox/${id}"
    base="$(git rev-parse HEAD 2>/dev/null || true)"
    if git worktree add -b "$branch" "$wt" HEAD >/dev/null 2>&1; then
      debug "created git worktree $wt on branch $branch (base ${base:-unknown})"
      # Record the fork point in a SIDECAR beside the worktree (never inside it,
      # so it cannot appear in the worktree's `git status`).
      [ -n "$base" ] && printf '%s\n' "$base" > "$(base_marker_path "$wt")" 2>/dev/null || true
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

# remove_worktree <worktree> <force 0|1> -- guarded teardown of a worktree.
# Returns 0 if removed (or already gone). Returns EX_GUARD if a guard refused
# (unsafe path, or unpushed work without --force). Order matters: the cheap
# path guard runs BEFORE the git data-loss guard, and git's own `worktree
# remove` is preferred so its administrative metadata stays consistent.
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

  # Prefer git's own removal so the repo's worktree registry is not left stale.
  if git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if ! git worktree remove --force "$wt" >/dev/null 2>&1; then
      # Detached/odd state: fall back to rm, then prune the dangling admin entry.
      rm -rf -- "$wt"
      git worktree prune >/dev/null 2>&1 || true
    fi
  else
    rm -rf -- "$wt"
  fi
  # Drop the sidecar base marker too (best-effort; it lives beside the worktree).
  rm -f -- "$(base_marker_path "$wt")" 2>/dev/null || true
  debug "removed worktree $wt"
  return 0
}

# ============================================================================
# Centralized BIRTH function. EVERY launch funnels through here -- there is no
# second code path that creates a container. It validates+clamps caps, stamps
# the mandatory label set, applies the safe-by-default isolation posture, creates
# the worktree, wires net/mounts/env/ssh-agent, base64-transports the workload,
# and assembles the full `podman run ...` argv into the global BIRTH_ARGV.
#
# Hardened vs A: ephemeral runs are given a DETERMINISTIC managed name
# (`sandbox-<id>`) so the trap layer can force-remove a half-born container even
# if podman is SIGKILLed before --rm fires (closing the orphan window A left
# open with an empty TRAP_CONTAINER); the base ref is stamped as a label; and the
# isolation-flag assembly is unchanged in spirit but documented as C's domain.
# ============================================================================

# Set by build_birth_argv for the trap / labels / reporting.
BIRTH_ID=""        # short random id (also the LBL_ID value)
BIRTH_NAME=""      # the container name we actually pass to podman (always set)
BIRTH_WORKTREE=""  # worktree path for trap rollback
declare -a BIRTH_ARGV

# build_birth_argv <persist 0|1> <image>
build_birth_argv() {
  local persist="$1" image="$2"

  # --- validate + clamp resource caps (krun fatals on malformed values) -------
  # (Validation/clamping helpers and the krun annotation wiring are Expert C's
  #  domain; we call them here so birth stays the single funnel.)
  require_uint "$OPT_CPUS"   "--cpus"
  require_uint "$OPT_MEMORY" "--memory"
  local cpus mem
  cpus="$(clamp "$OPT_CPUS"   1                "$KRUN_MAX_VCPU")"
  mem="$(clamp  "$OPT_MEMORY" "$KRUN_MIN_MIB"  "$KRUN_MAX_MIB")"
  [ "$cpus" = "$OPT_CPUS" ]  || warn "--cpus clamped to $cpus (bounds 1..$KRUN_MAX_VCPU)"
  [ "$mem"  = "$OPT_MEMORY" ] || warn "--memory clamped to $mem MiB (bounds $KRUN_MIN_MIB..$KRUN_MAX_MIB)"

  # --- identity + worktree (the tool creates it) ------------------------------
  local id ts wt name base
  id="$(gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wt="$(create_worktree "$id")"
  base="$(_worktree_base_ref "$wt")"
  BIRTH_ID="$id"
  BIRTH_WORKTREE="$wt"

  # Determine the container name. keep uses the user --name; run gets a
  # deterministic managed name so the trap and reap can always address it.
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

  # --- safe-by-default isolation posture (Expert C owns the exact flag set) ----
  argv+=(--security-opt no-new-privileges)
  argv+=(--cap-drop ALL)
  argv+=(--read-only)              # rootfs read-only; the worktree is the only rw surface
  argv+=(--annotation "run.oci.krun.cpus=${cpus}")
  argv+=(--annotation "run.oci.krun.ram_mib=${mem}")

  # --- network posture --------------------------------------------------------
  case "$OPT_NETWORK" in
    none)
      argv+=(--network none)
      if [ "${#PUBLISH_PORTS[@]}" -gt 0 ]; then
        warn "--publish ignored: it is a no-op under --network none"
      fi
      ;;
    loopback)
      argv+=(--network pasta)
      local p
      for p in "${PUBLISH_PORTS[@]}"; do
        argv+=(--publish "127.0.0.1:${p}")   # never expose beyond host loopback
      done
      ;;
    *)
      die "$EX_USAGE" "--network must be 'none' or 'loopback', got: '$OPT_NETWORK'"
      ;;
  esac

  # --- the single rw mount: the tool-created worktree, relabelled :Z ----------
  local guest_workdir="${OPT_WORKDIR:-/workspace}"
  argv+=(--volume "${wt}:${guest_workdir}:Z")
  argv+=(--workdir "$guest_workdir")

  # --- extra mounts (read-only ergonomics; default ro unless :rw given) -------
  local m host rest guest ro
  for m in "${EXTRA_MOUNTS[@]}"; do
    host="${m%%:*}"
    rest="${m#*:}"
    guest="${rest%%:*}"
    ro="${rest#*:}"
    if [ "$ro" = "ro" ] || [ "$ro" = "$guest" ]; then
      argv+=(--volume "${host}:${guest}:ro")
    else
      argv+=(--volume "${host}:${guest}:${ro}")
    fi
  done

  # --- env --------------------------------------------------------------------
  local e
  for e in "${EXTRA_ENV[@]}"; do argv+=(--env "$e"); done

  # --- ssh-agent forwarding (Expert C's domain; keys never enter the guest) ---
  if [ "$OPT_SSH_AGENT" = 1 ]; then
    [ -n "${SSH_AUTH_SOCK:-}" ] || die "$EX_GUARD" "--ssh-agent given but \$SSH_AUTH_SOCK is unset"
    [ -S "${SSH_AUTH_SOCK}" ]   || die "$EX_GUARD" "\$SSH_AUTH_SOCK is not a socket: ${SSH_AUTH_SOCK}"
    argv+=(--volume "${SSH_AUTH_SOCK}:/run/ssh-agent.sock")
    argv+=(--env "SSH_AUTH_SOCK=/run/ssh-agent.sock")
  fi

  [ "$OPT_TTY" = 1 ] && argv+=(-it)

  # --- rlimits: a second cap layer beyond the krun annotations ----------------
  argv+=(--ulimit "nofile=1024:1024")
  argv+=(--ulimit "nproc=512:512")

  # --- image + workload (base64-transported to dodge shell-quoting bugs) ------
  #     Encode host-side, decode in-guest, hand to bash. (The precise in-guest
  #     wrapper is Expert D's domain; this is the spine's safe-transport shape.)
  argv+=("$image")
  if [ "${#WORKLOAD_CMD[@]}" -gt 0 ]; then
    local payload b64
    payload="$(printf '%s ' "${WORKLOAD_CMD[@]}")"; payload="${payload% }"
    b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    argv+=(/bin/sh -c "printf '%s' '${b64}' | base64 -d | bash")
  fi

  BIRTH_ARGV=("${argv[@]}")
}

# ============================================================================
# Three-layer teardown.
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

# ephemeral_trap -- the cleanup handler. Trap-disarm-FIRST (gh-runner idiom) so a
# signal arriving mid-cleanup cannot re-enter and double-fire. Preserves the
# triggering exit code: for the EXIT trap, re-`exit $rc` after cleanup so the
# script's status is faithful (a bare `return` from an EXIT handler would lose a
# signal-derived 130/143).
ephemeral_trap() {
  local rc=$?
  trap '' EXIT INT TERM ERR        # disarm FIRST -- no re-entrant cleanup

  if [ "$TRAP_PERSIST" = 1 ]; then
    # A fully-born kept sandbox is intentionally durable; touch nothing.
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

arm_trap()    { trap ephemeral_trap EXIT INT TERM ERR; }
disarm_trap() { trap - EXIT INT TERM ERR; }

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

  # Arm Layer 2 around the foreground launch. We now KNOW the container name
  # (BIRTH_NAME) so the trap can force-remove a half-born container even if
  # podman is SIGKILLed before --rm fires -- the orphan window is closed.
  TRAP_PERSIST=0
  TRAP_CONTAINER="$BIRTH_NAME"
  TRAP_WORKTREE="$BIRTH_WORKTREE"
  arm_trap

  info "launching ephemeral sandbox ${BIRTH_ID} (image=$image, net=$OPT_NETWORK)"
  local rc=0
  podman_q "${BIRTH_ARGV[@]}" || rc=$?

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

  # Refuse to collide with an existing managed sandbox of the same name.
  if podman_q ps -a -q --filter "$(our_filter)" \
        --filter "label=${LBL_NAME}=${OPT_NAME}" 2>/dev/null | grep -q .; then
    die "$EX_GUARD" "a managed sandbox named '${OPT_NAME}' already exists (rm it first)"
  fi

  precheck
  reap_sweep_quiet

  build_birth_argv 1 "$image"

  # Until the sandbox is confirmed born, a failure should roll back BOTH the
  # half-created container and the worktree -> TRAP_PERSIST stays 0 for now.
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
# Verb: reap -- Layer-3 label-driven backstop. Touches ONLY our labelled set;
# never host-global state (the arrakis anti-pattern). Runs verbosely as a verb
# and cheaply (silent) at the top of every birth verb.
# ============================================================================

# reap_core <dry-run 0|1> <until-secs ''|N> <emit 0|1> [out-fd]
# Removes managed containers that leaked (ephemeral + exited/dead) and, with an
# age cut (--until), aged NON-running kept sandboxes. Never kills a healthy
# running sandbox on a time sweep. Worktree teardown is always guarded and never
# forced (a crashed sandbox's unpushed work is preserved). Candidate rows for
# --dry-run / --json are emitted as TSV on stdout: `<verdict>\t<id>\t<status>\t<reason>`.
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
    case "$status" in
      exited|dead|stopped)
        if [ "$persist" = true ]; then
          # An exited kept sandbox is only reaped under an age cut (below).
          :
        else
          doomed=1; reason="ephemeral leak (${status})"
        fi
        ;;
      running|created|paused|*)
        # Healthy / transitional: never force-killed by a time sweep.
        :
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
  while [ $# -gt 0 ]; do
    case "$1" in
      --until)   until_dur="${2:-}"; shift ;;
      --dry-run) dry=1 ;;
      --json)    json=1 ;;
      -h|--help) usage 0 ;;
      *) die "$EX_USAGE" "reap: unexpected arg '$1'" ;;
    esac
    shift
  done
  [ -n "$until_dur" ] && until_secs="$(duration_to_secs "$until_dur")"

  precheck
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
