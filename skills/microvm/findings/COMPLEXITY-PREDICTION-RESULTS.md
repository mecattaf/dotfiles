# Complexity Prediction — RESULTS (Sonnet experiment vs the committed meter)

Scoring of the predictions in [`COMPLEXITY-PREDICTION.md`](COMPLEXITY-PREDICTION.md) against a
real Sonnet-only re-run. Two **independent** Opus verifiers (semantic-probe lens +
comparative-diff lens) reached the **same verdict** with direct code/diff evidence — see
[`RESULTS-v1-semantic.md`](RESULTS-v1-semantic.md) and [`RESULTS-v2-comparative.md`](RESULTS-v2-comparative.md).

> **Timing caveat.** Wall-clock is NOT used as a difficulty signal this run — a wifi disconnect
> during the Sonnet pass inflated elapsed time independently of work done. Difficulty was judged
> by correctness (the verifiers), output-volume, and self-contained code evidence only.

## Setup

Sonnet agents re-implemented all 25 findings into `sandbox.sonnet.sh` from the **original draft**,
with the **same prompts verbatim** as the Opus run, sequential on one file, via a `TeamCreate` team
(5 Sonnet implementers `sonnet-impl-A…E`, then 2 Opus verifiers). Apples-to-apples vs the Opus
`sandbox.sh`.

**Structural tell (line counts):** draft **1566** → Sonnet **1682** → Opus **1844**. Opus added
~160 lines Sonnet did not — and those ~160 are almost entirely cluster B's doctor in-guest probes.
The deficit *is* the skipped invention.

## Scorecard

| Prediction | Committed | Actual (both verifiers) | Verdict |
|---|---|---|---|
| **Ranking** B ≫ D > C > E > A | B sole/hardest; A/E easiest | B the **only** failure, and total; A/E identical to Opus | **Top & bottom anchors CONFIRMED.** Middle (D>C) not exercised — both came out clean, so the relative order couldn't be stress-tested. |
| **A** P≈0.95 | near-certain pass | byte-identical to Opus gen_id | ✅ hit |
| **E** P≈0.85 | minor `:z`/`:Z` risk | correct; chose shared `:z` exactly as Opus | ✅ hit |
| **C** P≈0.60–0.70 | #5 shared-parser trap or #6 half-fix | **both dodged**: verb-aware keep guard, direct-argv transport | ❌ **too pessimistic** — Sonnet succeeded |
| **D** P≈0.60 | #11 or #7 likely wrong | **both subtle items correct** (#11 capture-and-check ×4, #7 ordering) | ❌ **too pessimistic** — Sonnet succeeded |
| **B** P≈0.35–0.50 | ≥1 lint-clean silent semantic error | **3 of 4 findings UNFIXED, near-untouched from baseline**; all `bash -n`-clean | ✅ failure direction right; **magnitude worse** (realized ≈0, not 0.35) |
| **Headline call** | Sonnet's B ships a lint-clean silent error | **YES — three**: surviving `run.oci.` prefix (#2), missing `krun.use_passt` (#3, `grep -c`=0), boot-only doctor (#4) | ✅✅✅ confirmed in strongest form |

## What the meter got right, and what it got wrong

**Right (the calls that matter most):**
- **WHICH cluster fails: B, decisively.** The single highest-stakes prediction. Correct.
- **The FAILURE CLASS: lint-clean silent semantic error.** All three B failures pass `bash -n`
  and would have shipped undetected — exactly the dangerous class the meter keys on.
- **The extremes (A/E trivial).** No falsifier from the easy side; the meter is not broken from below.

**Wrong:**
- **The middle band (C, D) was too pessimistic.** I conflated *"subtle"* with *"hard-for-Sonnet."*
  Sonnet handled subtle-but-**dictated-and-self-contained** fixes fine — including the three traps I
  specifically predicted it would hit (#5 shared-parser, #6 argv, #7 ordering, #11
  command-substitution). Being intricate is not what breaks a weaker model.

## The refined meter (what both verifiers independently converged on)

The discriminating axis was **not** subtlety or raw constraint-count. It was:

> **Invention-vs-transcription (axis 2) × cross-site consistency (axis 3), gated by
> lint-invisibility.** Sonnet fails where the correct answer must be *supplied from outside the
> given material* — designing the doctor probes and tolerance bands that don't exist in the draft,
> and applying external-system knowledge (crun's exact-key lookup) consistently across sites —
> AND where being wrong still passes `bash -n`. Where the prescription *dictates* the fix and
> correctness is checkable within bash (C, D, A, E), Sonnet is reliable even when the fix is subtle.

**The load corollary (the actionable one).** B failed even its *explicitly dictated* parts —
#2/#3 were literally "drop the `run.oci.` prefix" / "emit `krun.use_passt=1`," one-line edits, and
Sonnet skipped them too, leaving B near-baseline. That points at **cluster overload**: handed a
6-finding entangled cluster with 3 blockers, the weaker model ran out of attention and dropped the
structural work wholesale. This **empirically vindicates the scorecard's "split B" rebuild
recommendation**: B1 (dictated annotation fixes) + B2 (invent doctor probes) would very likely have
let Sonnet nail B1 and isolate the failure to B2.

## Practical takeaway (for choosing handholding)

- **Cheap/mechanical/dictated/local work → Sonnet unaided is fine.** Watching it is wasted attention.
  (A, C, D, E — 22 of 25 findings — landed perfectly on Sonnet.)
- **Spend Opus (or a diverse-lens verifier) only where the fix needs invention, external-system
  semantics, or cross-site consistency AND a wrong answer is lint-clean.** Here that was *only* B.
- **Don't hand a weaker model an overloaded entangled cluster — split it.** Load alone converted
  even one-line dictated edits into misses.
- **`bash -n` / "agent says done" proves nothing about this failure class.** The thing that caught
  it was a second model reading the code against the external semantics — diverse verification, not
  re-checking.
