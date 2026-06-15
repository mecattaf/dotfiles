# RESULTS v1 — Semantic-Correctness Verdict (Opus verifier 1)

> READ-ONLY audit. Lens: **semantic correctness** — did Sonnet actually commit each
> predicted error in `sandbox.sonnet.sh`? Evidence is the literal code (located by
> content, not line number; lines cited as of this read).

## Lint state

- `bash -n sandbox.sonnet.sh` → **clean** (SONNET_CLEAN)
- `bash -n sandbox.sh` (Opus) → clean
- Sonnet's two B failures (below) are **both `bash -n`-clean silent semantic errors** —
  the dangerous "ships plausible-but-wrong" class the meter keys on. Confirmed.

## Per-prediction HIT / MISS / SURPRISE

| Pred | Predicted Sonnet failure | Actual code | Verdict |
|---|---|---|---|
| **B/#2** annotation prefix | leaves `run.oci.` on ≥1 site | `_argv+=(--annotation "run.oci.krun.cpus=${cpus}")` and `...ram_mib...` — **BOTH** sites still prefixed; never emitted bare | **HIT** (silent, lint-clean) |
| **B/#3** loopback `use_passt` | loopback branch omits `krun.use_passt` | `loopback)` emits `--network pasta` + `--publish 127.0.0.1:…` only; **no `krun.use_passt` anywhere in file** (grep: zero hits outside FLAG comments) | **HIT** (silent, lint-clean) |
| **B/#4** doctor in-guest probe | boot-only / hard-coded / missing | doctor = original 6 probes (kvm/podman/runtime/crun_libkrun/libkrun/smoke). `probe_smoke` still `--network none … true`, asserts only exit 0. **No nproc/MemTotal probe, no read-only-write probe, no passt probe, no tolerance band, no apply_* routing.** Opus added 3 (`probe_clamp`,`probe_readonly_rootfs`,`probe_passt`); Sonnet added 0 | **HIT** (the regression that lets B/#2,#3 ship) |
| **C/#5** timeout guard placement | guard lands in **shared** `parse_birth_args` | guard is in `verb_keep` AFTER `parse_birth_args keep` (`[ -z "$OPT_TIMEOUT" ] \|\| die EX_USAGE …`), verb-aware, NOT in shared parser. exec timeout wired (`timeout --signal=TERM "$tsecs" "$PODMAN" "${eargv[@]}"`) | **MISS** (correct) |
| **C/#6** argv transport | argv only half-fixed; `echo a;rm` still runs `rm` | `WORKLOAD_CMD` words passed DIRECTLY as podman trailing args (`argv+=("${WORKLOAD_CMD[@]}")` at both birth and exec). base64 helper renamed `encode_script`, reserved/documented for explicit `-c SCRIPT`. `-- echo 'a;rm'` → `a;rm` is one literal argv word; `rm` does **not** run | **MISS** (correct) |
| **D/#11** resolve_managed swallowed die | ≥1 call site unguarded | all 4 primary sites use `if ! id="$(resolve_managed …)"; then exit …; fi` (capture-and-check captures die's rc); 2 reap-loop sites guard `\|\| { rc=$?; continue; }` | **MISS** (correct) |
| **D/#7** branch leak ordering | `branch -D` before `worktree remove` | parent repo recorded at create (`.parent` sidecar); on removal `git worktree remove --force` runs FIRST, THEN `git -C "$_parent_repo" branch -D "$_branch"` gated `sandbox/*` | **MISS** (correct) |
| **D/#8** reap half-born | created/half-born not doomed; 'dead' kept | `case running\|paused\|removing\|stopping) :;; *) [persist] \|\| doom` — `*` catches `created`/`initialized`; bogus `dead` token dropped | **MISS** (correct) |
| **A/#1** gen_id SIGPIPE | (≈certain success) | `head -c 4096 /dev/urandom \| LC_ALL=C tr -dc 'a-z0-9' \| head -c 10` — source bounded first, SIGPIPE-immune | **MISS** (correct) |
| **E/#9** rw mount relabel | minor `:z`/`:Z` risk | rw → `:rw,z`, ro → `:ro,z` (shared `z` for arbitrary user paths); worktree + ssh-sock use private `:Z`. Exactly the prescribed nuance | **MISS** (correct) |
| **E/#10** VERB doc lines | (≈certain) | `# VERB: version`, `# VERB: ls\|list … 'list' is an alias`, `# VERB: rm\|remove … 'remove' is an alias` all present | **MISS** (correct) |

No SURPRISE failures. A and E are indistinguishable from the Opus output, as predicted.

## Per-cluster rating

| Cluster | Prediction | Outcome | Rating |
|---|---|---|---|
| **B** krun blockers | 0.35–0.50 fully-correct; ≥1 silent semantic error | **3 of 3 sub-modes failed** (#2 prefix both sites, #3 no use_passt, #4 boot-only doctor). All lint-clean. | **prediction CORRECT** (worse than the P-band midpoint — Sonnet got *every* B sub-item wrong, not just one) |
| **D** lifecycle | 0.60; subtle #11 or #7 likely wrong | all 8 correct incl. both subtle ones (#11 capture-and-check, #7 ordering) | **prediction WRONG (optimistic-for-failure)** — Sonnet nailed D entirely |
| **C** transport/flags | 0.60–0.70; #5 placement or #6 half-fix | both correct (#5 verb-aware guard, #6 direct argv) | **prediction WRONG (optimistic-for-failure)** — Sonnet nailed C |
| **E** mounts/usage | 0.85; minor `:z`/`:Z` risk | correct, incl. the `:z`-vs-`:Z` nuance | **prediction CORRECT** |
| **A** gen_id | 0.95; near-certain | correct | **prediction CORRECT** |

## `bash -n`-clean silent semantic errors (the headline class)

1. **B/#2** — `--annotation run.oci.krun.cpus=` / `run.oci.krun.ram_mib=` at both emission
   sites. crun's `find_annotation` is an exact-key map lookup of bare `krun.cpus`/`krun.ram_mib`
   with no prefix stripping → resource caps silently no-op (up to 16 vCPU / 1024 MiB on a big host
   regardless of `--cpus`/`--memory`).
2. **B/#3** — `--network loopback` emits `--network pasta` + `--publish` but never the
   bare `krun.use_passt=1` annotation (absent from the entire file) → guest gets NO NIC;
   `loopback`/`--publish` are metadata-only no-ops. The exact ERA fail-open the brief forbids.

Both are entangled with **B/#4**: Sonnet's doctor is boot-only (no in-guest clamp/passt/read-only
assertion, no tolerance band, no `apply_*` routing), so neither error is catchable by `doctor` —
they ship undetected. This is precisely the arbiter's question ("does Sonnet's B exhibit a
lint-clean semantic error I predicted?") answered **YES**, and concentrated entirely in B.

## Bottom line on the meter

The B-is-hardest claim and the "≥1 lint-clean silent semantic error concentrated in B" aggregate
prediction are **confirmed** — in fact Sonnet failed all three B sub-modes, beyond the predicted
floor. A and E confirmed easy with no surprises. The C and D bands were **too pessimistic**: Sonnet
got both clusters fully right, including the specifically-flagged subtle items (#5 shared-parser
trap, #6 argv, #7 ordering, #11 command-substitution semantics). The ranking's top (B≫…) and
bottom (…E>A) anchors hold; the middle (D>C) was not exercised because neither failed.
