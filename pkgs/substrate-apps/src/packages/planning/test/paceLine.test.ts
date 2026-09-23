/**
 * The pace line, the regime ratio, and the harm Regime B does to the naive rule.
 */
import fc from "fast-check";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { fitsPaceLine, paceLine, REGIME_A_THRESHOLD } from "../src/heuristics/paceLine.ts";
import { EnvelopeReading } from "../src/schema/capacity.ts";

const decodeEnvelope = Schema.decodeUnknownSync(EnvelopeReading);

const envelope = (fields: {
  readonly outerRemaining: number;
  readonly windowsRemaining: number;
  readonly innerCap: number;
  readonly windowsPerEnvelope?: number;
}) =>
  decodeEnvelope({
    outerRemaining: fields.outerRemaining,
    windowsRemaining: fields.windowsRemaining,
    innerCap: fields.innerCap,
    windowsPerEnvelope: fields.windowsPerEnvelope ?? 235
  });

describe("pace line", () => {
  it("computes the pacing target as outer budget over windows remaining", () => {
    const pace = paceLine(
      envelope({ outerRemaining: 1000, windowsRemaining: 100, innerCap: 500 }),
      1
    );
    expect(pace.target).toBeCloseTo(10);
  });

  it("caps the usable window budget at the inner cap under Regime A", () => {
    // Regime A: the whole envelope is roughly the inner cap times the window
    // count, so the inner window genuinely binds.
    const pace = paceLine(
      envelope({
        outerRemaining: 235 * 100,
        windowsRemaining: 235,
        innerCap: 100,
        windowsPerEnvelope: 235
      }),
      3
    );
    expect(pace.regime).toBe("A");
    expect(pace.usableWindowBudget).toBeLessThanOrEqual(100);
    expect(pace.tightnessRatio).toBeGreaterThanOrEqual(REGIME_A_THRESHOLD);
  });

  it("holds the window well under its cap under Regime B", () => {
    // The failure the pace line exists to prevent: spending the inner window to
    // zero every time exhausts a loose envelope long before it resets.
    const pace = paceLine(
      envelope({ outerRemaining: 2350, windowsRemaining: 235, innerCap: 500 }),
      1
    );
    expect(pace.regime).toBe("B");
    expect(pace.usableWindowBudget).toBeCloseTo(10);
    expect(pace.usableWindowBudget).toBeLessThan(500);
  });

  it("reports runway in windows rather than tokens left in the window", () => {
    const pace = paceLine(
      envelope({ outerRemaining: 2350, windowsRemaining: 235, innerCap: 500 }),
      1
    );
    expect(pace.windowsOfRunway).toBeCloseTo(235);
  });

  it("clamps a burst allowance below one rather than tightening the pace", () => {
    const loose = paceLine(
      envelope({ outerRemaining: 1000, windowsRemaining: 100, innerCap: 500 }),
      0.1
    );
    expect(loose.usableWindowBudget).toBeCloseTo(10);
  });

  it("never exceeds the smaller of the inner cap and the burst-scaled target", () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0, max: 1e6, noNaN: true }),
        fc.integer({ min: 1, max: 500 }),
        fc.double({ min: 0.001, max: 1e5, noNaN: true }),
        fc.double({ min: 1, max: 3, noNaN: true }),
        (outerRemaining, windowsRemaining, innerCap, kappa) => {
          const pace = paceLine(
            envelope({ outerRemaining, windowsRemaining, innerCap }),
            kappa
          );
          const bound = Math.min(innerCap, kappa * (outerRemaining / windowsRemaining));
          return pace.usableWindowBudget <= bound + 1e-9;
        }
      ),
      { numRuns: 300 }
    );
  });

  it("admits a request only while the window budget covers what is already spent", () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0, max: 100, noNaN: true }),
        fc.double({ min: 0, max: 100, noNaN: true }),
        (spent, requested) => {
          const pace = paceLine(
            envelope({ outerRemaining: 1000, windowsRemaining: 10, innerCap: 50 }),
            1
          );
          return (
            fitsPaceLine(pace, spent, requested) ===
            spent + requested <= pace.usableWindowBudget
          );
        }
      ),
      { numRuns: 300 }
    );
  });
});
