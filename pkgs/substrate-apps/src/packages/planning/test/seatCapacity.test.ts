/**
 * Seat capacity: schema, staleness, projection, admission and ingestion.
 *
 * The properties SCOUT.md section 3 asks to pin are here as fast-check
 * properties: projecting to t1 then t2 equals projecting to t2; a passed reset
 * never raises utilization; a model-scoped window never changes headroom_pct;
 * the next transition is always strictly after asOf. Every refusal the
 * admission predicate can give has a case, and a property checks that nothing
 * is ever admitted on a reading that is not MEASURED.
 */
import { Effect, Option, Schema } from "effect";
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import {
  admitSeat,
  classifyStaleness,
  headroomPct,
  nextTransitionAt,
  projectSeat,
  projectSeatReading,
  projectWindow
} from "../src/capacity/project.ts";
import {
  CapacityLedger,
  capacityLedgerInMemoryLayer,
  capacityLedgerLayer,
  ingestSnapshot,
  type StoredSeat
} from "../src/capacity/ledger.ts";
import { PlanningStore, makeInMemoryPlanningStore } from "../src/objects/storage.ts";
import {
  SeatCapacity,
  SeatCapacitySnapshot,
  CapacityWindow
} from "../src/schema/seatCapacity.ts";
import {
  CC_FIVE_HOUR_RESET,
  CC_OBSERVED,
  CC_WEEKLY_RESET,
  cc3Seat,
  claudeSeat,
  halogenSeat,
  plus,
  qwenSeat,
  snapshot,
  window
} from "./seatCapacityFixtures.ts";

const decodeWindow = Schema.decodeUnknownSync(CapacityWindow);
const decodeSeat = Schema.decodeUnknownSync(SeatCapacity);
const decodeSnapshot = Schema.decodeUnknownSync(SeatCapacitySnapshot);
const opus = { model: "Opus", min_headroom_pct: 0 } as const;
const fable = { model: "Fable", min_headroom_pct: 0 } as const;
/** One minute after cc's reading. */
const T0 = plus(CC_OBSERVED, 60);

describe("seat-capacity/2 schema", () => {
  it("decodes today's cc shape, with the Fable weekly-scoped row", () => {
    const seat = claudeSeat();
    expect(seat.windows.map((entry) => entry.kind)).toEqual(["five_hour", "seven_day", "model_scoped"]);
    expect(seat.windows[2]?.model).toBe("Fable");
  });

  it("refuses a model_scoped window without a model, and a model on another kind", () => {
    expect(() => decodeWindow(window({ kind: "model_scoped", model: null }))).toThrow();
    expect(() => decodeWindow(window({ kind: "seven_day", model: "Fable" }))).toThrow();
  });

  it("refuses minutes that do not match the kind", () => {
    expect(() => decodeWindow(window({ kind: "five_hour", minutes: 10080 }))).toThrow();
    expect(() => decodeWindow(window({ kind: "seven_day", minutes: 300 }))).toThrow();
  });

  it("refuses an instant without a zone designator, and a negative percentage", () => {
    expect(() => claudeSeat({ observed_at: "2026-09-23T04:52:18" })).toThrow();
    expect(() => claudeSeat({ observed_at: "yesterday" })).toThrow();
    expect(() => decodeWindow(window({ kind: "seven_day", utilization_pct: -1 }))).toThrow();
  });

  it("refuses a snapshot naming one seat twice, and a wrong version", () => {
    expect(() => snapshot([claudeSeat(), claudeSeat()])).toThrow();
    expect(() =>
      decodeSnapshot({ schema_version: "seat-capacity/1", host: "h", published_at: T0, seats: [] })
    ).toThrow();
  });
});

describe("staleness", () => {
  it("classifies at the 1200 s and 7200 s edges, each edge being its later side", () => {
    expect(classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, 1199)).grade).toBe("MEASURED");
    expect(classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, 1200)).grade).toBe("STALE");
    expect(classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, 7199)).grade).toBe("STALE");
    expect(classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, 7200)).grade).toBe("UNKNOWN");
  });

  it("treats small clock skew as age zero and flags large skew", () => {
    const small = classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, -60));
    expect(small).toMatchObject({ grade: "MEASURED", age_seconds: 0, skewed: false });
    expect(small.skew_seconds).toBeCloseTo(60, 3);
    expect(classifyStaleness(CC_OBSERVED, plus(CC_OBSERVED, -121)).skewed).toBe(true);
  });

  it("compares instants, not spellings", () => {
    // 06:52:18+02:00 is 04:52:18Z: zero age, although "06" > "04" as text.
    expect(classifyStaleness("2026-09-23T06:52:18+02:00", "2026-09-23T04:52:18Z").age_seconds).toBe(0);
  });
});

describe("projection across reset boundaries", () => {
  it("a passed five-hour reset projects to 0 percent, resets_at null, PROJECTED", () => {
    const [fiveHour] = projectSeatReading(claudeSeat(), plus(CC_FIVE_HOUR_RESET, 1)).windows;
    expect(fiveHour).toMatchObject({
      kind: "five_hour",
      utilization_pct: 0,
      resets_at: null,
      severity: null,
      grade: "PROJECTED"
    });
  });

  it("one millisecond before the reset, nothing is projected", () => {
    const seat = claudeSeat({ observed_at: plus(CC_FIVE_HOUR_RESET, -600) });
    const [fiveHour] = projectSeatReading(seat, plus(CC_FIVE_HOUR_RESET, -0.001)).windows;
    expect(fiveHour).toMatchObject({ utilization_pct: 8, grade: "MEASURED" });
  });

  it("at exactly the reset instant the window has reset", () => {
    const seat = claudeSeat({ observed_at: plus(CC_WEEKLY_RESET, -600) });
    const weekly = projectSeatReading(seat, CC_WEEKLY_RESET).windows[1];
    expect(weekly?.grade).toBe("PROJECTED");
    expect(weekly?.resets_at).toBe(plus(CC_WEEKLY_RESET, 7 * 86400));
  });

  it("a passed weekly reset moves forward by whole weeks until it is in the future", () => {
    const asOf = plus(CC_WEEKLY_RESET, 10 * 86400);
    const weekly = projectSeatReading(claudeSeat(), asOf).windows[1];
    expect(weekly).toMatchObject({ kind: "seven_day", utilization_pct: 0, grade: "PROJECTED" });
    expect(weekly?.resets_at).toBe(plus(CC_WEEKLY_RESET, 14 * 86400));
  });

  it("cc3's 11.6-day-old reading keeps its resets visible, projected forward, and is UNKNOWN", () => {
    const asOf = "2026-09-23T04:52:18Z";
    const projected = projectSeat(cc3Seat(), asOf);
    expect(projected.reading.grade).toBe("UNKNOWN");
    for (const entry of projected.reading.windows) {
      expect(entry.grade).toBe("PROJECTED");
      if (entry.resets_at !== null) expect(Date.parse(entry.resets_at)).toBeGreaterThan(Date.parse(asOf));
    }
    expect(projected.reading.windows[1]?.resets_at).toBe("2026-09-26T11:00:00.199Z");
  });

  it("the STALE band keeps the numbers and flags them; beyond 7200 s utilization is dropped", () => {
    const stale = projectSeatReading(claudeSeat(), plus(CC_OBSERVED, 1800));
    expect(stale.grade).toBe("STALE");
    expect(stale.windows[1]).toMatchObject({ utilization_pct: 72, grade: "STALE" });
    const unknown = projectSeatReading(claudeSeat(), plus(CC_OBSERVED, 7300));
    expect(unknown.grade).toBe("UNKNOWN");
    expect(unknown.windows[1]).toMatchObject({ utilization_pct: null, grade: "UNKNOWN" });
    // ... and reset instants are still used once they pass.
    const later = projectSeatReading(claudeSeat(), plus(CC_WEEKLY_RESET, 60));
    expect(later.windows[1]).toMatchObject({ utilization_pct: 0, grade: "PROJECTED" });
  });

  it("a MEASURED seat with a window past its reset is PROJECTED at seat level", () => {
    const seat = claudeSeat({ observed_at: plus(CC_FIVE_HOUR_RESET, -300) });
    expect(projectSeatReading(seat, plus(CC_FIVE_HOUR_RESET, 60)).grade).toBe("PROJECTED");
  });

  it("reports headroom, lapses and the plan end", () => {
    const projected = projectSeat(claudeSeat(), T0);
    expect(projected.headroom_pct).toBe(28);
    expect(projected.lapses.map((lapse) => [lapse.kind, lapse.unused_pct])).toEqual([
      ["five_hour", 92],
      ["seven_day", 28],
      ["model_scoped", 0]
    ]);
    expect(projectSeat(qwenSeat(), T0).plan_lapses_at).toBe("2026-11-07T00:00:00Z");
    expect(projectSeat(qwenSeat(), T0).headroom_pct).toBeNull();
  });
});

// --- properties ---------------------------------------------------------------

const BASE = Date.parse("2026-09-01T00:00:00Z");
const DAY = 86400 * 1000;
const instantArb = fc
  .integer({ min: 0, max: 40 * DAY })
  .map((offset) => new Date(BASE + offset).toISOString());
const utilizationArb = fc.option(fc.integer({ min: 0, max: 100 }), { nil: null });
const gradeArb = fc.constantFrom("MEASURED", "STALE", "ESTIMATED", "UNKNOWN", "PROJECTED");
const windowArb = fc
  .record({
    kind: fc.constantFrom("five_hour", "seven_day", "model_scoped"),
    utilization_pct: utilizationArb,
    resets_at: fc.option(instantArb, { nil: null }),
    binding: fc.boolean(),
    severity: fc.constantFrom(null, "normal", "warning", "critical"),
    grade: gradeArb,
    model: fc.constantFrom("Fable", "Opus")
  })
  .map((raw) =>
    decodeWindow(
      window({
        ...raw,
        model: raw.kind === "model_scoped" ? raw.model : null
      } as Parameters<typeof window>[0])
    )
  );
const seatArb = fc
  .record({
    windows: fc.array(windowArb, { maxLength: 4 }),
    observed_at: instantArb,
    grade: gradeArb,
    dispatchable: fc.boolean()
  })
  .map((raw) => claudeSeat(raw));

describe("projection properties", () => {
  it("projecting to t1 and then to t2 equals projecting straight to t2", () => {
    fc.assert(
      fc.property(seatArb, instantArb, instantArb, (seat, a, b) => {
        const [t1, t2] = Date.parse(a) <= Date.parse(b) ? [a, b] : [b, a];
        expect(projectSeatReading(projectSeatReading(seat, t1), t2)).toEqual(
          projectSeatReading(seat, t2)
        );
      }),
      { numRuns: 500 }
    );
  });

  it("a passed reset never raises utilization", () => {
    fc.assert(
      fc.property(windowArb, instantArb, instantArb, (entry, observed, asOf) => {
        const projected = projectWindow(entry, observed, asOf);
        if (projected.utilization_pct !== null && entry.utilization_pct !== null) {
          expect(projected.utilization_pct).toBeLessThanOrEqual(entry.utilization_pct);
        }
        if (projected.grade === "PROJECTED" && entry.grade !== "PROJECTED") {
          expect(projected.utilization_pct).toBe(0);
        }
      }),
      { numRuns: 500 }
    );
  });

  it("a model-scoped window never changes headroom_pct", () => {
    fc.assert(
      fc.property(seatArb, windowArb, instantArb, (seat, extra, asOf) => {
        const scoped = decodeWindow({ ...extra, kind: "model_scoped", minutes: 10080, model: "Fable" });
        const withScoped = { ...seat, windows: [...seat.windows, scoped] };
        expect(headroomPct(projectSeatReading(withScoped, asOf).windows)).toBe(
          headroomPct(projectSeatReading(seat, asOf).windows)
        );
      }),
      { numRuns: 300 }
    );
  });

  it("the next transition is always strictly after asOf", () => {
    fc.assert(
      fc.property(fc.array(seatArb, { maxLength: 3 }), instantArb, (seats, asOf) => {
        const next = nextTransitionAt(seats, asOf);
        if (Option.isSome(next)) expect(Date.parse(next.value)).toBeGreaterThan(Date.parse(asOf));
      }),
      { numRuns: 300 }
    );
  });

  it("fail-closed: nothing is admitted on a reading that is not MEASURED, dispatchable and under cap", () => {
    fc.assert(
      fc.property(
        seatArb,
        instantArb,
        fc.constantFrom("Fable", "Opus", null),
        fc.integer({ min: 0, max: 50 }),
        (seat, asOf, model, minimum) => {
          const decision = admitSeat(seat.seat, seat, { model, min_headroom_pct: minimum }, asOf);
          if (!decision.admit) return;
          expect(seat.dispatchable).toBe(true);
          expect(classifyStaleness(seat.observed_at, asOf).grade).toBe("MEASURED");
          const projected = projectSeatReading(seat, asOf);
          // The seat-level grade may be PROJECTED only because a window that
          // admission does not check (non-binding, or another model's) has
          // reset; the checked windows are asserted MEASURED below. A seat
          // the publisher itself graded PROJECTED never admits.
          expect(seat.grade).not.toBe("PROJECTED");
          expect(["MEASURED", "PROJECTED"]).toContain(projected.grade);
          // Every window admission checks: the binding seat windows and the
          // job model's scoped window. Matching `decision.checked` back by
          // kind alone picked a non-binding twin (review round 2: flaky).
          const checkedWindows = projected.windows.filter(
            (candidate) =>
              (candidate.binding && candidate.kind !== "model_scoped") ||
              (candidate.kind === "model_scoped" &&
                model !== null &&
                candidate.model?.toLowerCase() === model.toLowerCase())
          );
          expect(checkedWindows.length).toBe(decision.checked.length);
          for (const entry of checkedWindows) {
            expect(entry.grade).toBe("MEASURED");
            expect(100 - (entry.utilization_pct ?? 100)).toBeGreaterThan(minimum);
          }
          expect(Date.parse(decision.until)).toBeGreaterThan(Date.parse(asOf));
        }
      ),
      { numRuns: 1000 }
    );
  });
});

describe("nextTransitionAt", () => {
  it("picks the earliest of the staleness edges, resets and plan expiry", () => {
    expect(Option.getOrNull(nextTransitionAt([claudeSeat()], T0))).toBe(plus(CC_OBSERVED, 1200));
    expect(Option.getOrNull(nextTransitionAt([claudeSeat()], plus(CC_OBSERVED, 1200)))).toBe(
      plus(CC_OBSERVED, 7200)
    );
    expect(Option.getOrNull(nextTransitionAt([claudeSeat()], plus(CC_OBSERVED, 7200)))).toBe(
      new Date(Date.parse(CC_FIVE_HOUR_RESET)).toISOString()
    );
    expect(Option.getOrNull(nextTransitionAt([claudeSeat()], CC_FIVE_HOUR_RESET))).toBe(
      new Date(Date.parse(CC_WEEKLY_RESET)).toISOString()
    );
    // Past the weekly reset, the next is that reset moved a week on (the scoped
    // row resets a few hundred microseconds later, inside the same millisecond).
    expect(Option.getOrNull(nextTransitionAt([claudeSeat()], plus(CC_WEEKLY_RESET, 1)))).toBe(
      plus(CC_WEEKLY_RESET, 7 * 86400)
    );
    expect(Option.getOrNull(nextTransitionAt([qwenSeat()], plus(CC_OBSERVED, 7200)))).toBe(
      "2026-11-07T00:00:00.000Z"
    );
  });

  it("is none when nothing lies ahead", () => {
    expect(Option.isNone(nextTransitionAt([], T0))).toBe(true);
  });
});

describe("the admission predicate", () => {
  it("today's cc: refuses Fable (its scoped row is 100 percent critical), admits Opus", () => {
    const seat = claudeSeat();
    expect(admitSeat("cc", seat, fable, T0)).toMatchObject({
      admit: false,
      reason: "severity-critical",
      // Normalised like every other instant admission answers (review round 3).
      retry_at: "2026-09-23T09:59:59.526Z"
    });
    expect(admitSeat("cc", seat, opus, T0)).toEqual({
      admit: true,
      seat: "cc",
      until: plus(CC_OBSERVED, 1200),
      headroom_pct: 28,
      signal: "GO",
      checked: [
        { kind: "five_hour", model: null },
        { kind: "seven_day", model: null }
      ]
    });
  });

  it("a model-scoped row at 100 percent without the critical label still refuses its model", () => {
    const seat = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET }),
        window({ kind: "model_scoped", model: "Fable", utilization_pct: 100, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", seat, { model: "fable", min_headroom_pct: 0 }, T0)).toMatchObject({
      admit: false,
      reason: "window-exhausted"
    });
    expect(admitSeat("cc", seat, opus, T0).admit).toBe(true);
  });

  it("five-hour at 100 percent with weekly at 70 percent refuses (the substrate gap)", () => {
    const seat = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 100, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 70, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", seat, opus, T0)).toMatchObject({
      admit: false,
      reason: "window-exhausted",
      retry_at: new Date(Date.parse(CC_FIVE_HOUR_RESET)).toISOString()
    });
  });

  it("honours the job's minimum headroom", () => {
    expect(admitSeat("cc", claudeSeat(), { model: null, min_headroom_pct: 30 }, T0)).toMatchObject({
      admit: false,
      reason: "window-exhausted"
    });
    expect(admitSeat("cc", claudeSeat(), { model: null, min_headroom_pct: 20 }, T0).admit).toBe(true);
  });

  it("the admission holds until the earliest reset among the windows checked", () => {
    const seat = claudeSeat({ observed_at: plus(CC_FIVE_HOUR_RESET, -300) });
    const decision = admitSeat("cc", seat, opus, plus(CC_FIVE_HOUR_RESET, -200));
    expect(decision).toMatchObject({ admit: true, until: new Date(Date.parse(CC_FIVE_HOUR_RESET)).toISOString() });
  });

  it("refuses STALE with a SLOW signal and raises demand", () => {
    expect(admitSeat("cc", claudeSeat(), opus, plus(CC_OBSERVED, 1500))).toMatchObject({
      admit: false,
      reason: "stale",
      signal: "SLOW",
      raise_demand: true
    });
  });

  it("refuses a reading older than 7200 s outright", () => {
    expect(admitSeat("cc", claudeSeat(), opus, plus(CC_OBSERVED, 8000))).toMatchObject({
      admit: false,
      reason: "unknown",
      signal: "STOP",
      raise_demand: true
    });
  });

  it("refuses a window projected past its reset until a new reading arrives", () => {
    const seat = claudeSeat({ observed_at: plus(CC_FIVE_HOUR_RESET, -300) });
    expect(admitSeat("cc", seat, opus, plus(CC_FIVE_HOUR_RESET, 60))).toMatchObject({
      admit: false,
      reason: "projected",
      raise_demand: true
    });
  });

  it("refuses an unknown seat, an evicted seat and an expired plan", () => {
    expect(admitSeat("cc4", undefined, opus, T0)).toMatchObject({ reason: "unknown-seat" });
    expect(admitSeat("cc3", cc3Seat(), opus, T0)).toMatchObject({
      reason: "not-dispatchable",
      detail: "evicted"
    });
    const qwen = { ...qwenSeat(), observed_at: "2026-11-07T00:00:00Z" };
    expect(admitSeat("pi-qwencloud", qwen, opus, "2026-11-07T00:10:00Z")).toMatchObject({
      reason: "plan-expired"
    });
  });

  it("refuses a binding window with no utilization (UNKNOWN is never headroom)", () => {
    expect(admitSeat("pi-qwencloud", qwenSeat(), opus, T0)).toMatchObject({
      admit: false,
      reason: "window-unknown"
    });
  });

  it("refuses a metered seat that publishes no binding window", () => {
    const seat = claudeSeat({ windows: [window({ kind: "model_scoped", utilization_pct: 1 })] });
    expect(admitSeat("cc", seat, fable, T0)).toMatchObject({ reason: "no-binding-window" });
  });

  it("clock skew: a reading slightly ahead admits, one far ahead refuses", () => {
    expect(admitSeat("cc", claudeSeat(), opus, plus(CC_OBSERVED, -60)).admit).toBe(true);
    expect(admitSeat("cc", claudeSeat(), opus, plus(CC_OBSERVED, -600))).toMatchObject({
      admit: false,
      reason: "clock-skew"
    });
  });

  it("refuses an asOf that is not an instant", () => {
    expect(admitSeat("cc", claudeSeat(), opus, "soon")).toMatchObject({ reason: "invalid-as-of" });
  });

  it("a provider warning admits with a SLOW signal; the publisher's STALE grade refuses", () => {
    const warned = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 80, resets_at: CC_FIVE_HOUR_RESET, severity: "warning" }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", warned, opus, T0)).toMatchObject({ admit: true, signal: "SLOW" });
    expect(admitSeat("cc", claudeSeat({ grade: "STALE" }), opus, T0)).toMatchObject({ reason: "stale" });
  });

  it("a Halogen row admits on a free slot and refuses when every slot is held", () => {
    expect(admitSeat("gpu-worker", halogenSeat(0), { model: null, min_headroom_pct: 0 }, T0)).toMatchObject({
      admit: true,
      until: plus(CC_OBSERVED, 1200)
    });
    expect(admitSeat("gpu-worker", halogenSeat(1), { model: null, min_headroom_pct: 0 }, T0)).toMatchObject({
      reason: "slots-full"
    });
  });
});

describe("ingestion", () => {
  const empty: ReadonlyMap<string, StoredSeat> = new Map();

  it("accepts a first reading and is idempotent on a repeat, receipt time included", () => {
    const pushed = snapshot([claudeSeat()]);
    const first = ingestSnapshot(empty, pushed, T0);
    expect(first.report).toEqual({ results: [{ seat: "cc", outcome: "accepted" }], changed: true });
    const second = ingestSnapshot(first.next, pushed, plus(T0, 300));
    expect(second.report).toEqual({ results: [{ seat: "cc", outcome: "duplicate" }], changed: false });
    expect(second.next).toEqual(first.next);
  });

  it("refuses an older observed_at, compared as an instant across offsets", () => {
    const held = ingestSnapshot(empty, snapshot([claudeSeat({ observed_at: "2026-09-23T04:52:19Z" })]), T0).next;
    // 06:52:18+02:00 is 04:52:18Z, one second OLDER, though it sorts later as text.
    const older = snapshot([claudeSeat({ observed_at: "2026-09-23T06:52:18+02:00" })], "2026-09-23T04:53:00Z");
    expect(ingestSnapshot(held, older, T0).report.results).toEqual([{ seat: "cc", outcome: "older" }]);
  });

  it("accepts a newer observed_at and a changed annotation only from a later publish", () => {
    const held = ingestSnapshot(empty, snapshot([claudeSeat()]), T0).next;
    const newer = snapshot([claudeSeat({ observed_at: plus(CC_OBSERVED, 120) })], plus(CC_OBSERVED, 130));
    expect(ingestSnapshot(held, newer, plus(T0, 120)).report.results[0]?.outcome).toBe("accepted");
    const evicted = claudeSeat({ dispatchable: false, dispatchable_reason: "evicted" });
    expect(
      ingestSnapshot(held, snapshot([evicted], "2026-09-23T04:52:30Z"), T0).report.results[0]?.outcome
    ).toBe("older");
    const republished = ingestSnapshot(held, snapshot([evicted], "2026-09-23T04:53:30Z"), T0);
    expect(republished.report.results[0]?.outcome).toBe("accepted");
    expect(republished.next.get("cc")?.seat.dispatchable).toBe(false);
  });

  it("refuses a reading dated beyond the skew tolerance, accepts one within it", () => {
    const ahead = (seconds: number) => snapshot([claudeSeat({ observed_at: plus(T0, seconds) })]);
    expect(ingestSnapshot(empty, ahead(600), T0).report.results[0]?.outcome).toBe("future");
    expect(ingestSnapshot(empty, ahead(60), T0).report.results[0]?.outcome).toBe("accepted");
  });

  it("folds each seat of a snapshot on its own", () => {
    const held = ingestSnapshot(empty, snapshot([claudeSeat()]), T0).next;
    const mixed = snapshot(
      [claudeSeat({ observed_at: plus(CC_OBSERVED, -600) }), halogenSeat(0)],
      plus(T0, 5)
    );
    expect(ingestSnapshot(held, mixed, T0).report).toEqual({
      results: [
        { seat: "cc", outcome: "older" },
        { seat: "gpu-worker", outcome: "accepted" }
      ],
      changed: true
    });
  });
});

const getLedger = Effect.gen(function* () {
  return yield* CapacityLedger;
});

describe("the capacity ledger Layer", () => {
  it("persists through the store: a second ledger over the same store sees the reading", async () => {
    const program = Effect.gen(function* () {
      const store = yield* makeInMemoryPlanningStore;
      const build = getLedger.pipe(
        Effect.provide(capacityLedgerLayer),
        Effect.provideService(PlanningStore, store)
      );
      const first = yield* build;
      const report = yield* first.ingest(snapshot([claudeSeat(), cc3Seat()]), T0);
      const second = yield* build;
      const view = yield* second.at(T0);
      const admitted = yield* second.admit("cc", opus, T0);
      const refused = yield* second.admit("cc3", opus, T0);
      return { report, view, admitted, refused, latest: yield* second.latest };
    });
    const { report, view, admitted, refused, latest } = await Effect.runPromise(program);
    expect(report.changed).toBe(true);
    expect(latest.map((entry) => entry.seat.seat)).toEqual(["cc", "cc3"]);
    expect(view.seats.map((entry) => [entry.reading.seat, entry.headroom_pct])).toEqual([
      ["cc", 28],
      ["cc3", 100]
    ]);
    expect(view.next_transition_at).toBe(plus(CC_OBSERVED, 1200));
    expect(admitted.admit).toBe(true);
    expect(refused).toMatchObject({ admit: false, reason: "not-dispatchable" });
  });

  it("refuses to load a stored value that does not decode", async () => {
    const program = Effect.gen(function* () {
      const store = yield* makeInMemoryPlanningStore;
      yield* store.put("capacity/seats" as never, [{ seat: "garbage" }]);
      const ledger = yield* getLedger.pipe(
        Effect.provide(capacityLedgerLayer),
        Effect.provideService(PlanningStore, store)
      );
      return yield* Effect.flip(ledger.latest);
    });
    expect((await Effect.runPromise(program))._tag).toBe("PlanningStoreError");
  });

  it("the in-memory Layer answers admission for the tests' composition", async () => {
    const decision = await Effect.runPromise(
      Effect.gen(function* () {
        const ledger = yield* CapacityLedger;
        yield* ledger.ingest(snapshot([claudeSeat()]), T0);
        return yield* ledger.admit("cc", fable, T0);
      }).pipe(Effect.provide(capacityLedgerInMemoryLayer))
    );
    expect(decision).toMatchObject({ admit: false, reason: "severity-critical" });
  });

  it("decodes a seat round-trip through the store unchanged", () => {
    expect(decodeSeat(JSON.parse(JSON.stringify(claudeSeat())))).toEqual(claudeSeat());
  });
});

describe("review round 1: an unread model-scoped limit is UNKNOWN, never headroom", () => {
  // A Claude reading whose model-scoped rows could not be read (the pusher's
  // meter-row fallback): only the seat-wide windows, no completeness claim.
  const meterOnly = (overrides: Record<string, unknown> = {}) => {
    const base: Record<string, unknown> = { ...claudeSeat() };
    delete base["model_windows_complete"];
    return decodeSeat({
      ...base,
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET })
      ],
      ...overrides
    });
  };

  it("refuses a Fable job when the reading does not state its model limits", () => {
    const seat = meterOnly();
    expect(seat).not.toHaveProperty("model_windows_complete");
    expect(admitSeat("cc", seat, fable, T0)).toMatchObject({
      admit: false,
      reason: "window-unknown",
      raise_demand: true
    });
    expect(admitSeat("cc", meterOnly({ model_windows_complete: false }), opus, T0)).toMatchObject({
      admit: false,
      reason: "window-unknown"
    });
  });

  it("still admits a job for no model on the same reading", () => {
    expect(admitSeat("cc", meterOnly(), { model: null, min_headroom_pct: 0 }, T0).admit).toBe(true);
  });

  it("a reading that claims completeness admits a model with no scoped limit", () => {
    expect(admitSeat("cc", meterOnly({ model_windows_complete: true }), opus, T0).admit).toBe(true);
  });

  it("a carried-forward model row with no utilization refuses its model only", () => {
    const seat = meterOnly({
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET }),
        window({
          kind: "model_scoped",
          model: "Fable",
          utilization_pct: null,
          resets_at: CC_WEEKLY_RESET,
          severity: null,
          grade: "UNKNOWN"
        })
      ]
    });
    expect(admitSeat("cc", seat, fable, T0)).toMatchObject({ admit: false, reason: "window-unknown" });
    expect(admitSeat("cc", seat, { model: null, min_headroom_pct: 0 }, T0).admit).toBe(true);
  });

  it("the completeness claim survives the wire and the store", () => {
    expect(decodeSeat(JSON.parse(JSON.stringify(claudeSeat()))).model_windows_complete).toBe(true);
  });
});
