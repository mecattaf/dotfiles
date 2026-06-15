# The actual prompts used to fix the 25 scrutiny findings

> Companion: [`STAGE5-orchestration-scorecard.md`](STAGE5-orchestration-scorecard.md) — honest self-critique of the decomposition below (split, depth, redundancy, orthogonality, model-fit).

This is the full, verbatim text every agent in the code-fix run was given. Nothing is
hidden — a "workflow" is just a small script that calls agents with string prompts. The
orchestration shape was: **5 implement agents (run one after another) → 5 verify agents
(run at the same time) → 1 correct+lint agent.** You could get the identical result by
pasting these prompts into a single Claude session one at a time. The only thing the
workflow adds is running the 5 verifiers in parallel and passing results between steps.

Two variables are substituted into the prompts:
- `FILE` = `/var/home/tom/mecattaf/dotfiles/skills/microvm/sandbox.sh` (the one file being edited)
- `SCRUT` = `/var/home/tom/mecattaf/dotfiles/skills/microvm/findings/STAGE4-scrutiny.md` (the fix spec)
- `BRIEF` = `/var/home/tom/mecattaf/dotfiles/skills/microvm/findings/BUILD-BRIEF.md` (the disciplines)

---

## 1. The COMMON preamble

This block is prepended to all 5 implement prompts AND the final correct prompt. It is the
shared ground rules.

```
You are fixing a single-file bash tool: {FILE}
Ground truth for WHAT to fix: {SCRUT} (every finding there is already source-verified with exact citations and a prescribed fix — implement that prescription, do not re-derive or re-clone source).
Spec/disciplines to respect: {BRIEF} (threat model = accident not adversary; labels are the source of truth; every isolation flag must reach a real engine arg).

CRITICAL RULES:
- Line numbers in the scrutiny doc reference the ORIGINAL draft and have DRIFTED as earlier agents edited. LOCATE every fix by function name / surrounding content, NEVER by trusting the cited line number. Re-Read {FILE} fresh before editing.
- Implement EXACTLY the scrutiny's prescribed fix for each finding in your cluster. Do not add scope, do not "improve" unrelated code.
- The script mandates 'set -euo pipefail'. Keep every edit safe under it.
- After ALL your edits, run: bash -n {FILE}  — it MUST be clean. Report the result.
- Use the Edit tool for in-place changes. Be surgical.
```

---

## 2. The 5 implement prompts (run sequentially, each edits the same file)

Each implement agent got: `COMMON` + `"Your cluster: <title>\n<body>\n\nApply every fix in
this cluster now, then run bash -n and report."` Below is the per-cluster `<body>`.

### Cluster A — gen_id SIGPIPE (critical blocker)

```
Cluster A — findings #1 (CRITICAL) and #21 (low, audit-only).
#1: gen_id() is 'LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 10'. Under pipefail, head closes the pipe -> tr gets SIGPIPE -> exit 141 -> EVERY run/keep birth dies before launch. Fix: make it SIGPIPE-immune by BOUNDING the source first, e.g.  id=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 10)  (4096 bytes yields ~570 usable chars, far more than 10). Verify gen_id returns rc 0 and a 10-char id under 'set -euo pipefail'.
#21: confirm the OTHER '| head' sites (the podman --filter | head -n1 and podman --version | head -n1 lines) are SAFE — their producers emit tiny finite output, so no SIGPIPE risk. Do NOT change them; just confirm in your report.
```

### Cluster B — krun annotations + network + doctor (entangled blockers)

```
Cluster B — findings #2, #3, #4 (all BLOCKERS) plus #12, #13, #18. These share the bare-key annotation theme; fix the PATTERN.
#2 (BLOCKER): krun annotations are emitted with a wrong 'run.oci.' prefix (run.oci.krun.cpus / run.oci.krun.ram_mib). crun does an EXACT-key map lookup of the BARE keys 'krun.cpus' / 'krun.ram_mib' (find_string_map_value, no prefix stripping) so the caps SILENTLY NO-OP. Fix EVERYWHERE krun annotations are emitted: emit bare '--annotation krun.cpus=N' / '--annotation krun.ram_mib=N'. (Note: podman passes annotations verbatim — it does NOT rewrite the prefix; a verifier who claimed otherwise was wrong.)
#3 (BLOCKER): the '--network loopback' branch enables podman --network pasta but NEVER stamps the 'krun.use_passt' annotation. krun gates networking EXCLUSIVELY on krun.use_passt; without it the guest gets NO NIC at all -> loopback/--publish is metadata-only. Fix: in the loopback branch also emit '--annotation krun.use_passt=1' (bare key). IMPORTANT: krun port-publish under passt has TSI caveats (krun_set_port_map can return -ENOTSUP), so DO NOT advertise --publish as proven — add a code comment that --publish reachability is runtime-unverified, and ensure doctor (finding #4) gains a passt-path smoke probe.
#4 (BLOCKER): doctor's smoke test only confirms a microVM boots; it asserts NOTHING bound in-guest, which is why #2/#3 could ship. Add doctor probes that go through the SAME apply_* code path (not hard-coded keys) and assert IN-GUEST: (a) nproc and MemTotal reflect the clamp — use ram_mib >= 512 for the probe since <=128 is silently ignored by krun; (b) a read-only rootfs rejects a write: sh -c 'touch /nope 2>&1; test ! -e /nope'; (c) the passt path from #3 boots with a NIC present. Tolerance-band the cpu/mem asserts.
#12: doctor misattributes image-absence / offline-registry as a krun-stack failure. Fix: guard the pull ('podman image exists IMG || podman pull IMG') or use a guaranteed-local image, and emit a remediation that distinguishes image-absence from a real krun failure.
#13: comments calling --cap-drop / no-new-privileges / --ulimit in-guest protections are misleading — crun-krun does NOT propagate them into the guest; they constrain the HOST VMM process only. Fix the comments to say so (do not remove the flags).
#18: probe_runtime_registered uses an unanchored case-insensitive grep that passes on any krun-ish substring. Tighten to an exact-name match (grep -qx) against the OCI runtime list; downgrade 'binary on PATH but not registered in containers.conf' to a WARN.
```

### Cluster C — command transport + exec/keep flags (highs)

```
Cluster C — findings #5, #6 (HIGH) plus #14, #15, #19, #20.
#6 (HIGH): encode_workload's base64 transport does NOT preserve argv boundaries — it joins words then pipes to 'bash -s' as a script, so 'echo a;rm' would EXECUTE rm. Fix: for the common case pass the workload words straight as podman TRAILING ARGS (podman preserves argv with no shell); reserve base64 ONLY for a genuinely-opaque explicit '-c <script>' form, documented as such. Fix the misleading 'dodges every layer of shell quoting' comment. This function is used in both verb_run and verb_exec launch paths — update both call sites consistently.
#5 (HIGH): --timeout is parsed but DEAD on keep and exec. Wire it into verb_exec's foreground launch (timeout --signal=TERM "$tsecs" podman exec ...). For DETACHED keep, reject --timeout with EX_USAGE via a verb-aware guard inside verb_keep (NOT inside the shared parse_birth_args, which verb_run also uses).
#14: exec --ssh-agent only sets SSH_AUTH_SOCK env but never mounts the socket (podman exec cannot add mounts) -> dangling env. Fix: require the sandbox was born with --ssh-agent (inspect a birth marker/mount) and EX_GUARD otherwise, or drop the exec --ssh-agent flag entirely. Do not set an env pointing at an absent socket.
#15: keep accepts -it but launches -d; the -it is dead/contradictory. Fix: on the persist path do not append -it when -d is set (or reject -it at parse time for keep, pointing the user at 'start -it').
#19: the base64/-c path requires sh + base64 + bash in-guest (fedora-minimal has them; alpine/distroless may not). Add a short code comment documenting this in-guest dependency.
#20: start -ai on a sandbox kept WITHOUT -it cannot restore interactive stdin (podman can't override create-time tty). Fix: have start inspect Tty/OpenStdin and warn actionably, and/or add a comment that 'start -it' only yields interactivity if 'keep ... -it' was used at birth.
```

### Cluster D — lifecycle / teardown / reap / traps / gating

```
Cluster D — findings #7, #8, #11 (medium) plus #16, #17, #22, #23, #25.
#7: create_worktree creates branch 'sandbox/<id>' in the parent repo that NO teardown layer ever deletes -> permanent orphaned-branch leak per run. Fix: record the parent repo path at create time (sidecar or label). On removal, AFTER 'git worktree remove --force', run 'git -C <parent> branch -D sandbox/<id>'. Worktree removal MUST precede branch -D; gate on the already-passed has_unpushed_commits check.
#8: reap misses half-born ephemeral orphans — it matches exited|dead|stopped but a created-but-not-started --rm container reports 'created'/'initialized' and is never reaped; 'dead' is dead code. Fix: for NON-persistent containers, doom any non-live state, e.g. case "$status" in running|paused|removing|stopping) : ;; *) [ "$persist" = true ] || doom ;; esac. Drop the bogus 'dead' token.
#11: resolve_managed calls die() inside $(...) — in a checked context (start/exec/logs/inspect) the die is swallowed, leaving an empty id so podman acts on an empty target. Fix: capture-and-check at each call site: if ! id="$(resolve_managed "$name")"; then exit "$?"; fi  — or add [ -n "$id" ] || die "$EX_NOTFOUND" after the call. Apply at all four call sites.
#16: verb_keep runs its podman-ps name-collision check BEFORE precheck — the verb-zero contract says precondition gates fire first. Fix: move precheck (and reap_sweep_quiet) above the collision query, matching verb_run; add a comment that name uniqueness is podman-enforced and the losing concurrent keep is cleanly rolled back.
#17: reap/stop/rm/logs gate on the FULL krun precheck (KVM + krun runtime), blocking backstop CLEANUP exactly when krun/KVM are broken. Fix: gate pure-cleanup verbs (reap, stop, rm, logs) on probe_podman ONLY; reserve the full krun precheck for guest-launching verbs (run/keep/start/exec). Give ls/inspect a podman-only gate too.
#22: the trap arms 'EXIT INT TERM ERR'; the ERR arm is not in the prior-art idiom and adds a re-entrancy surface (EXIT under set -e already covers the error path with correct $? propagation). Fix: drop ERR only -> trap ephemeral_trap EXIT INT TERM.
#23: has_unpushed_commits silently swallows a sidecar '.base' write failure, which can turn every clean teardown into a -f-requiring refusal. Fix: hard-fail birth if the sidecar write fails (or read LBL_BASE back from the container, since it is stamped at birth but never read back).
#25: concurrent reap worktree teardown is best-effort (relies on swallowed git errors, not a lock). Accept as-is for the accident model but add/keep a comment documenting it as best-effort under concurrency (the named graduation signal for a real lock).
```

### Cluster E — mounts / SELinux relabel + usage/dispatch + logging

```
Cluster E — findings #9, #10 (medium) plus #24.
#9: the rw extra-mount branch emits ':rw' with NO ':Z'/':z' relabel and discards any user-supplied Z -> functional break or weakened isolation on an SELinux-enforcing host. Fix: append a relabel to rw extra mounts — prefer ':z' (shared) for arbitrary user paths since ':Z' privately mutates the host source's SELinux context. Relabel ro mounts too. (The read-only-rootfs assertion itself is handled by doctor in cluster B #4 — don't duplicate it here.)
#10: usage()/dispatch drift — 'version', 'list', 'remove' are dispatched in main() but have no grepped '# VERB:' line, so the self-documenting help omits them (violates the zero-drift discipline). Fix: add a '# VERB: version' doc line and note the 'list'/'remove' aliases inline on the existing ls/rm '# VERB:' lines so usage() and dispatch agree.
#24: the timed-run branch invokes $PODMAN directly, bypassing the podman_q trace line (cosmetic, no functional impact). Fix: emit an equivalent trace line before the timeout call so both launch branches log identically.
```

---

## 3. The verify prompt (5 of these, one per cluster, run in parallel — read-only)

Each verifier got this template with its cluster's `<title>` and `<body>` (the same body
text as above) appended:

```
You are an ADVERSARIAL verifier. Re-Read {FILE} as it stands NOW and judge whether each finding in the cluster below is genuinely and correctly fixed per the scrutiny's prescription in {SCRUT}. Be skeptical: a fix that is present but wrong (e.g. still uses a 'run.oci.' prefix, or a doctor probe that asserts nothing in-guest) is NOT 'fixed'. Run 'bash -n {FILE}'. For each finding give status fixed|partial|missing|regressed with the EXACT current code as evidence, and if not fixed give the precise correction.

Cluster to verify: <title>
<body>
```

---

## 4. The correct + lint prompt (1 agent, runs last)

This got `COMMON` + the list of any findings the verifiers flagged as not-fully-fixed:

```
The implement pass is done; adversarial verifiers flagged the items below as NOT fully fixed. Apply each correction precisely in {FILE} (re-Read first; locate by content). Then run a FINAL 'bash -n {FILE}' and, IF the 'shellcheck' binary exists on PATH, run 'shellcheck -S warning {FILE}' and summarize (do not fail if shellcheck is absent — note it). Do a quick coherence sanity pass: every main() dispatch case still has a matching '# VERB:' line; the krun annotations are bare-key everywhere; gen_id is SIGPIPE-immune.

Items to correct:
<bullet list of "[status] #N (cluster X): <correction text>" — empty means "everything fixed, just do the final lint+sanity pass">
```

---

## How you'd do this without any workflow feature

1. Open one Claude session.
2. Paste prompt **2.A**, let it edit + `bash -n`. Then **2.B**, **2.C**, **2.D**, **2.E** — one at a time (sequential because they all touch the same file).
3. For each cluster, paste the matching **3** verify prompt and read the verdict.
4. Paste **4** with whatever the verifiers flagged.

Same result. The workflow just automated the sequencing and ran step 3's five checks
concurrently. The "intelligence" is entirely in the prompt text above — which is itself a
condensation of `STAGE4-scrutiny.md`, the source-verified finding list.
