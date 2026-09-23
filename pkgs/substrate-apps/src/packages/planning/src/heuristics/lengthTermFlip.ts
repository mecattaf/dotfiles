/**
 * The attended/unattended inversion of the length term.
 *
 * Volume II Part III section 2: Smith's rule solves weighted flow time by
 * short-first; longest-processing-time first minimises makespan on parallel
 * machines. The factory needs both, at different regimes. Attended, the
 * objective is weighted completion time — clear work in process, shorten cycle
 * time — and short-first is right. Unattended, the objective becomes makespan
 * over a fixed horizon, and short-first is precisely wrong: it strands the long
 * jobs at the end, where one long lane runs alone past the horizon.
 *
 * Section 4 supplies the condition under which this starts to pay. A greedy list
 * schedule is within about thirty percent of the best possible makespan, and an
 * unloaded batch has thirty percent to spare; sequencing quality is not worth
 * optimising until the batch is loaded. When filler does saturate, the batch
 * becomes a tight makespan instance, the four-thirds bound stops being slack,
 * and longest-first starts paying. Section 7 reaches the same inversion from
 * stochastic premises: for exponential processing times, shortest-expected-first
 * minimises expected total completion and longest-expected-first minimises
 * expected makespan.
 *
 * The regime is a flag set by the operator or by herdr presence. It is not a
 * clock, and this package has no way to read one.
 */
import type { Regime } from "../schema/capacity.ts";
import type { Estimate } from "../schema/estimate.ts";

/** How the length term enters the sort. */
interface LengthTerm {
  /**
   * The multiplier applied to a candidate's density.
   *
   * Attended it decreases with estimated length; unattended it increases. It is
   * strictly positive, so it re-orders within a level without ever overriding
   * the level hierarchy or turning a positive density negative.
   */
  readonly multiplier: number;
  /** Which rule produced it, for the release journal. */
  readonly rule: "SPT" | "LPT";
}

/**
 * The exponent that reproduces the linear preference.
 *
 * One is the default because it is the weakest form that still points the way
 * the theory points: attended, the term falls off as the reciprocal of the
 * length ratio; unattended, it grows in proportion to it. It is a starting
 * value for Tom to move, not a constant the theory supplies.
 */
export const DEFAULT_LENGTH_EXPONENT = 1;

/**
 * Computes the length term for one candidate under one regime.
 *
 * The multiplier is scale-free: it compares this candidate's estimated service
 * interval against a reference interval supplied by the caller, normally the
 * class median from the estimate table's main effects, so the term does not
 * depend on the units the estimate is denominated in and does not collapse to a
 * constant by comparing an item against itself.
 *
 * The `timeWeighted` argument exists because the density this multiplies is not
 * always length-neutral. On a priced position row the bid-price denominator is
 * `pi_slot * tau`, so the density already carries a reciprocal of length and is
 * already short-first; inverting it for the unattended objective means
 * cancelling that reciprocal before adding a length preference, which is what
 * the squared form does. On a metered lane the denominator is budget and carries
 * no length at all, so the plain form is correct.
 *
 * How strongly length should tell is not something the theory fixes. Smith's
 * rule and the makespan argument each say which *direction* the term points;
 * neither says that the preference should be linear in the length ratio rather
 * than square-rooted or cubed. The shipped code hardcoded a square in the
 * time-weighted unattended case, and a square is two decisions stacked: one to
 * cancel the denominator's reciprocal, which the theory does require, and one to
 * make the surviving preference linear, which it does not. So the exponent is a
 * parameter Tom sets as data. The cancellation is not: it is added on top of the
 * exponent exactly where the denominator carries a service-time term, because
 * cancelling a reciprocal that is there is arithmetic and not taste.
 *
 * @param regime - Attended or unattended; a flag, never a clock.
 * @param estimate - The candidate's shrunk estimate.
 * @param referenceSeconds - The class scale to compare against. A non-positive
 *   reference yields a neutral multiplier rather than a division by zero.
 * @param timeWeighted - Whether the density's denominator already carries a
 *   service-time term, which is true exactly when a position row is priced above
 *   zero.
 * @param exponent - How steeply the length preference grows. One reproduces the
 *   linear form; a non-positive value is clamped to zero, which makes the term
 *   neutral and turns the flip off rather than inverting it.
 * @returns The multiplier and the rule that produced it.
 */
export const lengthTerm = (
  regime: Regime,
  estimate: Estimate,
  referenceSeconds: number,
  timeWeighted: boolean,
  exponent: number = DEFAULT_LENGTH_EXPONENT
): LengthTerm => {
  const steepness = Math.max(0, exponent);
  if (referenceSeconds <= 0) {
    return { multiplier: 1, rule: regime === "attended" ? "SPT" : "LPT" };
  }
  const scaled = 1 + estimate.p80Seconds / referenceSeconds;
  if (regime === "attended") {
    // Smith's rule: weight over processing time, so short-first.
    return { multiplier: Math.pow(scaled, -steepness), rule: "SPT" };
  }
  // Makespan over a fixed horizon: long jobs must start early or strand. Where
  // the denominator already divided by length, one power cancels that division
  // and the exponent is what expresses the surviving long-first preference.
  return {
    multiplier: Math.pow(scaled, steepness + (timeWeighted ? 1 : 0)),
    rule: "LPT"
  };
};

/**
 * Applies the length term to a density.
 *
 * @param density - The value density from `valueDensity`.
 * @param term - The length term for the same candidate.
 * @returns The sort key. Infinite densities stay infinite, which keeps a
 *   zero-priced free lane saturated under either regime.
 */
export const applyLengthTerm = (density: number, term: LengthTerm): number =>
  Number.isFinite(density) ? density * term.multiplier : density;
