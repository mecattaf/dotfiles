/**
 * The lane duration cap as a robustness parameter.
 *
 * Volume II Part III section 3 gives the deterministic argument. Graham's
 * refined bound says any list schedule satisfies
 * `Cmax <= C* + (1 - 1/m) * p_max`, so with eight lanes and a bounded job
 * ceiling the additive error is small and well inside parameter error. That
 * bound has exactly one enemy and it is a configuration value: a twelve-hour
 * ceiling permits a twelve-hour `p_max` and makes the bound vacuous. Capping
 * lane duration at a class-specific p99 is a scheduling act with a provable
 * payoff, and it is currently unset.
 *
 * Section 7 gives the learning-augmented reading, which is the sharper one. The
 * plant is semi-clairvoyant: p80 estimates are predictions, not truths, which
 * places it in the setting where algorithms trade consistency against
 * robustness. The lane cap is the robustness parameter, bounding the damage a
 * wrong prediction does. Left at a ceiling that never binds, the plant runs the
 * consistent-but-not-robust end of the tradeoff by default. Setting the cap at
 * the class p99 is what makes the p80 estimate safe to trust.
 *
 * Section 9 lists it among the load-bearing and cheap.
 */
import type { Estimate } from "../schema/estimate.ts";

/** A lane cap, with what set it. */
interface RuntimeCap {
  /** The cap in seconds. */
  readonly seconds: number;
  /**
   * Where it came from.
   *
   * `classP99` is the intended source. `floor` means the class estimate was
   * degenerate and the declared floor applied. `hostCeiling` means the class p99
   * exceeded what the host permits, which is a signal that the class is
   * mis-specified rather than that the host is too small.
   */
  readonly source: "classP99" | "floor" | "hostCeiling";
}

/**
 * Derives the lane cap from a class's estimate.
 *
 * @param estimate - The class's shrunk estimate.
 * @param floorSeconds - The shortest cap worth setting; a cap below the class
 *   median would kill ordinary work.
 * @param hostCeilingSeconds - The longest the host will permit under any
 *   circumstances.
 * @returns The cap and its source. A cap is always finite: an unbounded cap is
 *   the condition this module exists to remove.
 */
export const runtimeCap = (
  estimate: Estimate,
  floorSeconds: number,
  hostCeilingSeconds: number
): RuntimeCap => {
  const p99 = estimate.p99Seconds;
  if (p99 <= floorSeconds) return { seconds: floorSeconds, source: "floor" };
  if (p99 >= hostCeilingSeconds) return { seconds: hostCeilingSeconds, source: "hostCeiling" };
  return { seconds: p99, source: "classP99" };
};
