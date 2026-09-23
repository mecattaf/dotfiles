/**
 * Seat capacity, review round 3 (2026-09-23): one pinned case per finding.
 *
 * - A severity-critical refusal's retry_at is the latest reset of EVERY
 *   refusing window (critical or exhausted), the same rule as the exhausted
 *   path, so a dispatcher does not re-ask a day early.
 * - A model-scoped limit that names two families ("Opus and Sonnet") binds a
 *   job of either; one that names no known family refuses model jobs
 *   `window-unknown` instead of being skipped.
 * - The publisher's seat grade reaches every window: an UNKNOWN reading has no
 *   headroom, a STALE one has no MEASURED window.
 */
import { describe, expect, it } from "vitest";
import { admitSeat, projectSeat } from "../src/capacity/project.ts";
import { CC_FIVE_HOUR_RESET, CC_OBSERVED, CC_WEEKLY_RESET, claudeSeat, plus, window } from "./seatCapacityFixtures.ts";

const job = (model: string | null, min_headroom_pct = 0) => ({ model, min_headroom_pct });
const OBSERVED = "2026-09-23T06:00:00.000Z";
const ASOF = plus(OBSERVED, 300);
const FIVE_RESET = "2026-09-23T08:49:59.526Z";
const WEEK_RESET = "2026-09-24T09:59:59.526Z";
const T0 = plus(CC_OBSERVED, 60);

describe("review round 3: a critical refusal waits for every refusing window", () => {
  const retry = (decision: ReturnType<typeof admitSeat>) => (decision.admit ? "admitted" : decision.retry_at);

  it("two critical windows: retry_at is the later reset", () => {
    const seat = claudeSeat({
      observed_at: OBSERVED,
      windows: [
        window({ kind: "five_hour", utilization_pct: 99, resets_at: FIVE_RESET, severity: "critical" }),
        window({ kind: "seven_day", utilization_pct: 100, resets_at: WEEK_RESET, severity: "critical" })
      ]
    });
    const decision = admitSeat("cc", seat, job(null), ASOF);
    expect(decision).toMatchObject({ admit: false, reason: "severity-critical" });
    expect(retry(decision)).toBe(WEEK_RESET);
  });

  it("a critical five-hour window and an exhausted weekly one: the weekly reset, as with no labels", () => {
    const windows = [
      window({ kind: "five_hour", utilization_pct: 60, resets_at: FIVE_RESET, severity: "critical" }),
      window({ kind: "seven_day", utilization_pct: 100, resets_at: WEEK_RESET, severity: "warning" })
    ];
    const labelled = admitSeat("cc", claudeSeat({ observed_at: OBSERVED, windows }), job(null), ASOF);
    expect(labelled).toMatchObject({ admit: false, reason: "severity-critical" });
    expect(retry(labelled)).toBe(WEEK_RESET);
    const plain = claudeSeat({ observed_at: OBSERVED, windows: windows.map((entry) => ({ ...entry, severity: null })) });
    expect(retry(admitSeat("cc", plain, job(null, 50), ASOF))).toBe(WEEK_RESET);
  });

  it("an exhausted window that opens on first use (no reset) makes retry_at null", () => {
    const seat = claudeSeat({
      observed_at: OBSERVED,
      windows: [
        window({ kind: "five_hour", utilization_pct: 100, resets_at: null }),
        window({ kind: "seven_day", utilization_pct: 90, resets_at: WEEK_RESET, severity: "critical" })
      ]
    });
    expect(retry(admitSeat("cc", seat, job(null), ASOF))).toBeNull();
  });

  it("a critical window alone still answers its own reset", () => {
    const seat = claudeSeat({
      observed_at: OBSERVED,
      windows: [
        window({ kind: "five_hour", utilization_pct: 10, resets_at: FIVE_RESET, severity: "critical" }),
        window({ kind: "seven_day", utilization_pct: 20, resets_at: WEEK_RESET })
      ]
    });
    expect(retry(admitSeat("cc", seat, job(null), ASOF))).toBe(FIVE_RESET);
  });

  it("at the retry instant the refusal is over for the refusing windows (it reads as a reset)", () => {
    const seat = claudeSeat({
      observed_at: OBSERVED,
      windows: [
        window({ kind: "five_hour", utilization_pct: 99, resets_at: FIVE_RESET, severity: "critical" }),
        window({ kind: "seven_day", utilization_pct: 100, resets_at: WEEK_RESET, severity: "critical" })
      ]
    });
    // Before the latest reset one window still refuses; at it both have reset
    // and the answer is `projected` (a new reading is needed), never critical.
    expect(admitSeat("cc", seat, job(null), plus(WEEK_RESET, -1))).toMatchObject({ admit: false });
    expect(admitSeat("cc", seat, job(null), WEEK_RESET)).not.toMatchObject({ reason: "severity-critical" });
  });
});

describe("review round 3: a model limit shared by two families binds both", () => {
  const shared = (model: string, extra: Record<string, unknown> = {}) =>
    claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 40, resets_at: CC_WEEKLY_RESET }),
        window({
          kind: "model_scoped",
          model,
          utilization_pct: 100,
          severity: "critical",
          resets_at: CC_WEEKLY_RESET,
          ...extra
        })
      ],
      model_windows_complete: true
    });

  it("'Opus and Sonnet' at 100 percent refuses a Sonnet job and an Opus job", () => {
    for (const model of ["claude-sonnet-4-5", "claude-opus-5-5", "Opus", "sonnet"]) {
      expect(admitSeat("cc", shared("Opus and Sonnet"), job(model), T0)).toMatchObject({
        admit: false,
        reason: "severity-critical"
      });
    }
  });

  it("the shared limit does not bind a third family, and is checked for the ones it names", () => {
    expect(admitSeat("cc", shared("Opus and Sonnet"), job("claude-fable-5-1"), T0)).toMatchObject({
      admit: true,
      checked: [
        { kind: "five_hour", model: null },
        { kind: "seven_day", model: null }
      ]
    });
    expect(
      admitSeat("cc", shared("Opus and Sonnet", { utilization_pct: 10, severity: "normal" }), job("opus"), T0)
    ).toMatchObject({
      admit: true,
      checked: [
        { kind: "five_hour", model: null },
        { kind: "seven_day", model: null },
        { kind: "model_scoped", model: "Opus and Sonnet" }
      ]
    });
  });

  it("a limit under a name no family covers refuses every model job window-unknown", () => {
    for (const model of ["claude-opus-5-5", "fable"]) {
      expect(admitSeat("cc", shared("Mythos"), job(model), T0)).toMatchObject({
        admit: false,
        reason: "window-unknown",
        raise_demand: true
      });
    }
    // Even an otherwise harmless one: it cannot be ruled out for the job.
    expect(
      admitSeat("cc", shared("Mythos", { utilization_pct: 1, severity: "normal" }), job("opus"), T0)
    ).toMatchObject({ admit: false, reason: "window-unknown" });
  });

  it("the unplaceable limit is still checked for the job that names it verbatim, and a job for no model admits", () => {
    expect(admitSeat("cc", shared("Mythos"), job("mythos"), T0)).toMatchObject({
      admit: false,
      reason: "severity-critical"
    });
    expect(admitSeat("cc", shared("Mythos"), job(null), T0)).toMatchObject({ admit: true });
  });
});

describe("review round 3: the publisher's seat grade reaches every window", () => {
  const seatWindows = (view: ReturnType<typeof projectSeat>) =>
    view.reading.windows.filter((entry) => entry.kind !== "model_scoped");

  it("a seat graded UNKNOWN reports no headroom and no utilization", () => {
    const view = projectSeat(claudeSeat({ grade: "UNKNOWN", stale_reason: "the reader failed" }), T0);
    expect(view.reading.grade).toBe("UNKNOWN");
    expect(view.headroom_pct).toBeNull();
    expect(view.reading.windows.map((entry) => [entry.grade, entry.utilization_pct])).toEqual([
      ["UNKNOWN", null],
      ["UNKNOWN", null],
      ["UNKNOWN", null]
    ]);
    // The reset instants are kept: they are still the plan's calendar.
    expect(view.reading.windows.map((entry) => entry.resets_at)).toEqual(claudeSeat().windows.map((entry) => entry.resets_at));
  });

  it("a seat graded STALE has no MEASURED window; its utilization is kept, as for age", () => {
    const view = projectSeat(claudeSeat({ grade: "STALE", stale_reason: "read failed" }), T0);
    expect(view.reading.grade).toBe("STALE");
    expect(seatWindows(view).map((entry) => entry.grade)).toEqual(["STALE", "STALE"]);
    expect(view.headroom_pct).toBe(28);
  });

  it("a seat graded ESTIMATED has ESTIMATED windows", () => {
    const view = projectSeat(claudeSeat({ grade: "ESTIMATED" }), T0);
    expect(seatWindows(view).map((entry) => entry.grade)).toEqual(["ESTIMATED", "ESTIMATED"]);
  });

  it("a MEASURED or publisher-PROJECTED seat leaves young windows MEASURED", () => {
    expect(seatWindows(projectSeat(claudeSeat(), T0)).map((entry) => entry.grade)).toEqual(["MEASURED", "MEASURED"]);
    const projected = projectSeat(claudeSeat({ grade: "PROJECTED" }), T0);
    expect(projected.reading.grade).toBe("PROJECTED");
    expect(seatWindows(projected).map((entry) => entry.grade)).toEqual(["MEASURED", "MEASURED"]);
  });

  it("a window projected past its reset stays PROJECTED whatever the seat grade", () => {
    const view = projectSeat(claudeSeat({ grade: "UNKNOWN" }), plus(CC_FIVE_HOUR_RESET, 1));
    expect(view.reading.windows[0]).toMatchObject({ kind: "five_hour", grade: "PROJECTED", utilization_pct: 0 });
  });

  it("admission of those seats is unchanged: UNKNOWN and STALE still refuse with their reasons", () => {
    expect(admitSeat("cc", claudeSeat({ grade: "UNKNOWN" }), job(null), T0)).toMatchObject({ reason: "unknown" });
    expect(admitSeat("cc", claudeSeat({ grade: "STALE" }), job(null), T0)).toMatchObject({ reason: "stale" });
  });
});
