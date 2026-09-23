/**
 * The pace line and the regime ratio.
 *
 * The thesis's Appendix C.1 corrects chapter 9. Whether "spend the window before
 * it perishes" is right depends on the tightness ratio
 * `r = C_out / (N * C_in)`. Under Regime A, near one, the inner window truly
 * perishes. Under Regime B, far below one — the usual case for a nested-limit
 * subscription — the inner window is a rate limiter and not inventory, and
 * sweeping every window to zero exhausts the envelope early and buys a long
 * stretch at zero capacity.
 *
 * So the pacing target is the pace line `pi_t = B_out(t) / N_rem(t)`, with usable
 * window budget `min(C_in, kappa * pi_t)` and `kappa` between one and three for
 * deliberate bursts. `r` is one division; this module computes it rather than
 * branching on a guess.
 *
 * Volume II Part III section 1 supplies the formal name for what the two limits
 * are together: a partially renewable resource in the sense of Boettcher and
 * Drexl, whose capacity is declared over designated subsets of periods. That
 * formulation carries both constraints without choosing between the regimes.
 *
 * Local GPU wall-clock is unconditionally perishable regardless of regime, which
 * is why durable rows never enter the pace line.
 */
import type { EnvelopeReading } from "../schema/capacity.ts";

/** The pace line, computed from one envelope reading. */
export interface PaceLine {
  /** `pi_t = B_out(t) / N_rem(t)`: the per-window pacing target. */
  readonly target: number;
  /** `min(C_in, kappa * pi_t)`: what may actually be spent in this window. */
  readonly usableWindowBudget: number;
  /** `r = C_out / (N * C_in)`: which horizon binds. */
  readonly tightnessRatio: number;
  /**
   * Which regime the measured ratio puts the plant in.
   *
   * Under `A` the inner window binds and unused inner capacity truly evaporates.
   * Under `B` the outer envelope binds and the inner window is a rate limiter.
   */
  readonly regime: "A" | "B";
  /**
   * Days of runway is the dashboard number under Regime B, expressed here as
   * windows of runway because the engine counts windows and never days.
   */
  readonly windowsOfRunway: number;
}

/**
 * The threshold separating the two regimes.
 *
 * Nested-limit subscriptions are almost always Regime B by a wide margin, so the
 * threshold is set well above the ambiguous middle: a ratio at or above it means
 * the inner window is genuinely the binding constraint.
 */
export const REGIME_A_THRESHOLD = 0.9;

/**
 * Computes the pace line from one envelope reading.
 *
 * @param envelope - Outer budget remaining, windows remaining, the inner cap and
 *   the envelope's window count. All counts, no clock.
 * @param kappa - The burst allowance, between one and three. Values below one
 *   are clamped up, because a pace line stricter than the pace is not a pace.
 * @returns The target, the usable window budget, the measured ratio, the regime
 *   and the runway in windows.
 */
export const paceLine = (envelope: EnvelopeReading, kappa: number): PaceLine => {
  const burst = Math.max(1, kappa);
  const windowsRemaining = Math.max(1, envelope.windowsRemaining);
  const target = envelope.outerRemaining / windowsRemaining;
  const usableWindowBudget = Math.min(envelope.innerCap, burst * target);

  const denominator = envelope.windowsPerEnvelope * envelope.innerCap;
  // The whole envelope, reconstructed from what remains and how much is left of
  // it, so the ratio is measured rather than configured.
  const outerTotal = envelope.outerRemaining * (envelope.windowsPerEnvelope / windowsRemaining);
  const tightnessRatio = denominator > 0 ? Math.min(1, outerTotal / denominator) : 1;

  const burnPerWindow = usableWindowBudget > 0 ? usableWindowBudget : target;
  const windowsOfRunway =
    burnPerWindow > 0 ? envelope.outerRemaining / burnPerWindow : Number.POSITIVE_INFINITY;

  return {
    target,
    usableWindowBudget,
    tightnessRatio,
    regime: tightnessRatio >= REGIME_A_THRESHOLD ? "A" : "B",
    windowsOfRunway
  };
};

/**
 * Whether a metered consumption fits under the pace line.
 *
 * @param pace - The computed pace line.
 * @param alreadySpent - Metered weight already committed in this window.
 * @param requested - The candidate's consumption at the p80 protection level.
 * @returns Whether the candidate fits. This test can only defer: it never
 *   increases what the kernel's own oracle would allow.
 */
export const fitsPaceLine = (
  pace: PaceLine,
  alreadySpent: number,
  requested: number
): boolean => alreadySpent + requested <= pace.usableWindowBudget;
