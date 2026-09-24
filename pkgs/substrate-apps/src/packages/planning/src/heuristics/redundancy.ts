/**
 * Redundancy: spawn `k`, keep the first success.
 *
 * Volume II Part III section 7 calls this the strongest quantitative result in
 * the mapping, and it is asymmetric across lane types. On free lanes the case is
 * overwhelming, because what varies is not duration but outcome: with
 * independent per-attempt yield, `k` attempts deliver `1 - (1 - yhat)^k`, so a
 * local lane at yield 0.3 reaches 0.51 at two attempts and 0.66 at three, at
 * zero marginal cost. That turns local-first from true-but-weak into decisive:
 * redundancy is what makes low-yield free lanes economically sufficient rather
 * than merely admissible.
 *
 * Two corrections are in the code. Attempts on the same job with the same
 * machine are not independent, so the realised gain falls below the binomial
 * figure; the fix is decorrelation by diversity, and it must decorrelate over
 * the pair, drawing distinct herdr agent kinds as well as distinct makers, since
 * harness-level failure modes are exactly the kind that repeat identically.
 *
 * And the binding constraint on all of it is review. Redundancy is admissible
 * exactly where the merge gate is mechanical, because only a witnessed automatic
 * gate discards the losing attempts at zero human cost. Where the gate is Tom,
 * `k` attempts multiply the bottleneck by `k` and redundancy is strictly
 * harmful, so this module returns `None`.
 *
 * On metered lanes the arithmetic looks wrong until the failure's true cost is
 * priced: a failed metered attempt lands in the human's inbox and consumes the
 * drum's price, which dominates. The rule is not "never on metered lanes" but
 * "when the counterfactual is Tom's attention, price it at sigma".
 *
 * WHAT IS LEFT HERE. The diversity axis, and nothing else. The expansion itself
 * — `redundancyPlan`, `compositeYield` and the `distinctOn` helper — was
 * exported and imported by nothing: the release evaluator carries a
 * `redundancyDiversity` policy field and never calls the expansion, so the
 * theory above was stated and not run. FOLD-2L cleared it under
 * R-2026-09-06-21; wiring it in would be a behaviour change and is not this
 * unit's to make. The sketch's copy, its `docs/port-manifest.tsv` row and
 * `docs/dead-code.md` keep the record — including that the literal NUL byte
 * U-A5 filed as defect D1 sat inside `distinctOn` and left with it.
 */

/** How a redundant set was decorrelated. */
export type Diversity = "maker" | "harness" | "pair";
