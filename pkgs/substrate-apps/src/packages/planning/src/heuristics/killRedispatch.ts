/**
 * Kill and re-dispatch past a multiple of the class median.
 *
 * Volume II Part III section 7. For exponential processing times on parallel
 * machines the classical results hold, but the factory's own measurement is a
 * squared coefficient of variation around four, markedly heavier tailed than
 * exponential. That almost certainly means a decreasing hazard rate, so a job
 * that has run three times its class median is more likely, not less, to run
 * long still. Under decreasing hazard the Gittins index rule dominates
 * shortest-expected-first, and its prescription is clear: the right action on a
 * job well past its class median is often to kill and re-dispatch rather than to
 * wait.
 *
 * So the yield hook fires on elapsed multiples of the class median rather than
 * on an absolute ceiling. That is the whole content of this module.
 *
 * The division of labour is deliberate. This module decides; the kernel's
 * cooperative yield hook acts. tally never infers a safe checkpoint from process
 * state, so what crosses the wire is a request to checkpoint and exit, and the
 * holder chooses when.
 *
 * WHAT IS LEFT HERE. The default multiple, which the release evaluator reads,
 * and nothing else. `yieldDecision` and `licensesEscalation` were exported and
 * imported by nothing — no caller, no test, no tool — and FOLD-2L cleared them
 * under R-2026-09-06-21. See `docs/dead-code.md`.
 */

/**
 * The default multiple.
 *
 * Three class medians is the figure Volume II Part III section 7 uses when it
 * states the decreasing-hazard argument. It is a parameter and belongs in the
 * plan's policy data; this constant is the fallback when none is declared.
 */
export const DEFAULT_MEDIAN_MULTIPLE = 3;
