# Complexity Prediction — a falsifiable hypothesis (NOT recovered design-time judgment)

> **Honesty label.** This file is a **fresh ex-post hypothesis**, constructed when asked, about
> which fix-clusters need an Opus-class model vs which a Sonnet-class model could do unaided.
> It was **NOT** running in my head when I built the original workflow — at design time there
> was no capability/model consideration whatsoever (see the RECTIFICATION in
> [`STAGE5-orchestration-scorecard.md`](STAGE5-orchestration-scorecard.md)). The predictions
> below are committed **before** the Sonnet experiment so the test is real and not hindsight.

## The meter — what the Opus/Sonnet boundary keys on (4 axes, by weight)

1. **Semantic-vs-syntactic correctness** — does a *wrong* fix still pass `bash -n`? If yes, the
   agent can't self-catch and a weaker model ships plausible-but-wrong. (The original
   `run.oci.` annotation bug is the proof: lint-clean and already slipped one pass.)
2. **Invention vs transcription** — dictated fix ("use `head -c 4096…`") → easy; must *design*
   the answer (doctor tolerance bands; faking a WARN state doctor lacks) → Opus-pull.
3. **Cross-site consistency** — "fix the pattern *everywhere* it's emitted" → weaker model fixes
   2 of 3 sites.
4. **Constraint-count on a single edit** — how many interacting requirements one fix must satisfy.

## Committed predictions

**Sonnet-failure-risk ranking (hardest → easiest): B ≫ D > C > E > A.**

| Cluster | P(fully-correct, Sonnet unaided) | Predicted Sonnet failure mode(s) |
|---|---|---|
| **B** krun blockers | **0.35–0.50** | ≥1 of: (i) leaves `run.oci.` on ≥1 of the 3 emission sites, or misses bare-key entirely; (ii) doctor probe asserts boot-only / hard-codes keys instead of routing through `apply_*`; (iii) tolerance band omitted or naive (exact `MemTotal` match → false-fail). **And it passes `bash -n` → ships silently.** |
| **D** lifecycle | 0.60 | mechanical 6 land; ≥1 of the 2 subtle ones wrong — #11 (`die()` swallowed in `$(...)` — command-substitution semantics) or #7 ordering (branch `-D` before worktree-remove). |
| **C** transport/flags | 0.60–0.70 | #5 timeout guard placed in the **shared** `parse_birth_args` (explicitly forbidden), or #6 argv only half-fixed. |
| **E** mounts/usage | 0.85 | localized/mechanical; minor risk on the `:z` vs `:Z` relabel nuance. |
| **A** gen_id | 0.95 | fully dictated; near-certain. |

**Trace-signal sub-prediction:** even the *Opus* agents show more visible iteration / self-
correction in B (and the subtle parts of D) than in A/E. Falsifier: if Opus sailed through B
with zero backtracking, the "B is hard" claim weakens.

**Aggregate prediction:** the Sonnet run produces a `bash -n`-clean file that *looks* complete
but contains **≥1 silent semantic error concentrated in B** (and possibly one subtle miss in D),
while A and E are ~indistinguishable from the Opus output.

## Test protocol (this experiment)

1. Fresh-copy the **original** `findings/build/sandbox.draft.sh` → `../sandbox.sonnet.sh`.
2. Re-run all 5 implement clusters with **Sonnet-only** agents (TeamCreate team), **same prompts
   verbatim** as the Opus run, **sequential** on the shared file.
3. **Two independent closing Opus verifiers** each: diff `sandbox.sonnet.sh` vs `sandbox.sh`
   (the Opus output) vs the `STAGE4-scrutiny.md` prescription, hunt the predicted failure modes,
   and return a per-cluster verdict + a per-prediction hit/miss.
4. Arbiter: **does Sonnet's B exhibit a lint-clean semantic error I predicted?** Score the full
   table: ranking correct? per-cluster P-bands roughly right? any *surprise* failures in A/E
   (which would falsify the meter from the easy side)?

Results are recorded in `COMPLEXITY-PREDICTION-RESULTS.md` after the run.
