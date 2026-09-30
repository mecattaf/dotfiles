/**
 * 2026-09-30, the overnight provider run: a credit-metered seat (the Qwen token
 * plan's weekly credits, the OpenRouter key under a soft dollar cap, the free
 * model's daily request quota) admits on the reading's own counter, graded
 * MEASURED-CREDIT; an ESTIMATED reading with no counter still never admits.
 */
import { describe, expect, it } from "vitest";
import {
  admitSeat,
  CREDIT_MIN_HEADROOM_PCT,
  creditFreePct,
  displayGrade,
  MEASURED_CREDIT,
  projectSeatReading
} from "../src/capacity/project.ts";
import { decodeSeatCapacity, type SeatCapacity } from "../src/schema/seatCapacity.ts";

const NOW = "2026-09-30T20:00:00Z";
const job = { model: null, min_headroom_pct: 5 };

const seat = (over: Record<string, unknown>): SeatCapacity =>
  decodeSeatCapacity({
    seat: "s",
    provider: "openrouter",
    owner: "tom",
    dispatchable: true,
    dispatchable_reason: null,
    plan: null,
    slots: null,
    windows: [],
    observed_at: "2026-09-30T19:58:00Z",
    source: { kind: "seats-oracle", detail: null },
    grade: "MEASURED",
    stale_reason: null,
    ...over
  });

const qwen = (credits: Record<string, unknown> | undefined, over: Record<string, unknown> = {}) =>
  seat({
    seat: "pi-qwencloud",
    provider: "qwen",
    grade: "ESTIMATED",
    slots: { capacity: 4, holders: 0 },
    windows: [
      {
        kind: "seven_day",
        model: null,
        binding: true,
        minutes: 10080,
        utilization_pct: 15.3,
        resets_at: "2026-10-03T10:22:17Z",
        severity: null,
        grade: "ESTIMATED"
      }
    ],
    ...(credits === undefined ? {} : { credits }),
    ...over
  });

const planCredits = { unit: "credits", used: 1534, limit: 10000, resets_at: "2026-10-03T10:22:17Z", basis: "plan-ratio" };

describe("credit-metered admission", () => {
  it("admits an ESTIMATED Qwen reading that carries its plan-ratio counter, graded MEASURED-CREDIT", () => {
    const d = admitSeat("pi-qwencloud", qwen(planCredits), job, NOW);
    expect(d.admit).toBe(true);
    if (!d.admit) return;
    expect(d.grade).toBe(MEASURED_CREDIT);
    expect(d.headroom_pct).toBeCloseTo(84.66, 2);
    // Good until the reading ages past MEASURED (observed + 1200 s), before the weekly reset.
    expect(d.until).toBe("2026-09-30T20:18:00.000Z");
  });

  it("keeps the estimated refusal for an ESTIMATED reading with no counter", () => {
    const d = admitSeat("pi-qwencloud", qwen(undefined), job, NOW);
    expect(d).toMatchObject({ admit: false, reason: "estimated" });
  });

  it("refuses a counter at or under the 5 percent floor, retrying at its reset", () => {
    const d = admitSeat("pi-qwencloud", qwen({ ...planCredits, used: 9_600 }), job, NOW);
    expect(d).toMatchObject({ admit: false, reason: "credits-exhausted", retry_at: "2026-10-03T10:22:17.000Z" });
    // The floor holds even when the job asks for less headroom.
    const lax = admitSeat("pi-qwencloud", qwen({ ...planCredits, used: 9_600 }), { model: null, min_headroom_pct: 0 }, NOW);
    expect(lax).toMatchObject({ admit: false, reason: "credits-exhausted" });
    expect(CREDIT_MIN_HEADROOM_PCT).toBe(5);
  });

  it("the OpenRouter soft cap: $11.50 of $12 is spent, with no reset to wait for", () => {
    const or = seat({ seat: "openrouter", credits: { unit: "usd", used: 11.5, limit: 12, resets_at: null, basis: "provider" } });
    expect(admitSeat("openrouter", or, job, NOW)).toMatchObject({ admit: false, reason: "credits-exhausted", retry_at: null });
    const fresh = seat({ seat: "openrouter", credits: { unit: "usd", used: 0, limit: 12, resets_at: null, basis: "provider" } });
    expect(admitSeat("openrouter", fresh, job, NOW)).toMatchObject({ admit: true, headroom_pct: 100, grade: MEASURED_CREDIT });
  });

  it("a MEASURED seat that publishes no window and no counter is still refused no-binding-window", () => {
    expect(admitSeat("openrouter", seat({}), job, NOW)).toMatchObject({ admit: false, reason: "no-binding-window" });
  });

  it("counts slots on a credit seat: four Qwen agents at most", () => {
    const full = qwen(planCredits, { slots: { capacity: 4, holders: 4 } });
    expect(admitSeat("pi-qwencloud", full, job, NOW)).toMatchObject({ admit: false, reason: "slots-full" });
  });

  it("the free model's daily quota: its reset passed since the reading needs a new reading", () => {
    const free = seat({
      seat: "openrouter-free",
      credits: { unit: "requests", used: 1000, limit: 1000, resets_at: "2026-09-30T19:59:00Z", basis: "provider" }
    });
    expect(admitSeat("openrouter-free", free, job, NOW)).toMatchObject({ admit: false, reason: "projected", raise_demand: true });
    const spent = seat({
      seat: "openrouter-free",
      credits: { unit: "requests", used: 990, limit: 1000, resets_at: "2026-10-01T00:00:00Z", basis: "provider" }
    });
    expect(admitSeat("openrouter-free", spent, job, NOW)).toMatchObject({ admit: false, reason: "credits-exhausted", retry_at: "2026-10-01T00:00:00.000Z" });
  });

  it("age, dispatch and ownership rules still come first", () => {
    const stale = qwen(planCredits, { observed_at: "2026-09-30T19:30:00Z" });
    expect(admitSeat("pi-qwencloud", stale, job, NOW)).toMatchObject({ admit: false, reason: "stale" });
    const unauth = qwen(planCredits, { dispatchable: false, dispatchable_reason: "auth-failed" });
    expect(admitSeat("pi-qwencloud", unauth, job, NOW)).toMatchObject({ admit: false, reason: "not-dispatchable", detail: "auth-failed" });
    const broken = seat({ credits: { unit: "usd", used: 0, limit: 0, resets_at: null, basis: "provider" } });
    expect(admitSeat("s", broken, job, NOW)).toMatchObject({ admit: false, reason: "credits-invalid" });
  });

  it("the view grade says MEASURED-CREDIT only for a fresh reading with a counter", () => {
    expect(displayGrade(projectSeatReading(qwen(planCredits), NOW), NOW)).toBe(MEASURED_CREDIT);
    expect(displayGrade(projectSeatReading(qwen(undefined), NOW), NOW)).toBe("ESTIMATED");
    expect(displayGrade(projectSeatReading(qwen(planCredits, { observed_at: "2026-09-30T19:30:00Z" }), NOW), NOW)).toBe("STALE");
    expect(creditFreePct({ unit: "usd", used: 3, limit: 12, resets_at: null, basis: "provider" })).toBe(75);
  });

  it("the counter survives decoding and projection (the floor stores and re-serves it)", () => {
    const projected = projectSeatReading(qwen(planCredits), NOW);
    expect(projected.credits).toEqual(planCredits);
    expect(() => seat({ credits: { unit: "usd", used: -1, limit: 12, resets_at: null, basis: "provider" } })).toThrow();
    expect(() => seat({ credits: { unit: "usd", used: 1, limit: 12, resets_at: null, basis: "guess" } })).toThrow();
  });
});
