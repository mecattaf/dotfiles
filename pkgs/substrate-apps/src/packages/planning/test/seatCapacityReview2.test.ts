/**
 * Seat capacity, review round 2 (2026-09-23): one pinned case per finding.
 *
 * - The staleness edges are inclusive of their later side, so the instant
 *   `nextTransitionAt` names is an instant at which the answer has changed,
 *   and nothing changes strictly before it (two fast-check properties).
 * - A model-scoped limit is matched by model family: a job named by its model
 *   id (`claude-fable-5-1`) meets the `Fable` row.
 * - A third party's seat is never admitted, whatever `dispatchable` says.
 * - A publisher's PROJECTED seat grade stays PROJECTED and never admits.
 * - A snapshot whose `published_at` is dated beyond the skew tolerance is
 *   refused whole.
 * - The mutants that survived the round 2 mutation pass (plan expiry at the
 *   instant, the latest reset as retry, the Halogen plan cap, the ESTIMATED
 *   refusal, the non-binding window).
 */
import { Option, Schema } from "effect";
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import {
  admitSeat,
  classifyStaleness,
  nextTransitionAt,
  projectSeat,
  projectSeatReading
} from "../src/capacity/project.ts";
import { ingestSnapshot, type StoredSeat } from "../src/capacity/ledger.ts";
import { CapacityWindow, type SeatCapacity } from "../src/schema/seatCapacity.ts";
import {
  CC_FIVE_HOUR_RESET,
  CC_OBSERVED,
  CC_WEEKLY_RESET,
  claudeSeat,
  halogenSeat,
  plus,
  snapshot,
  window
} from "./seatCapacityFixtures.ts";

const decodeWindow = Schema.decodeUnknownSync(CapacityWindow);
const ms = (instant: string): number => Date.parse(instant);
const iso = (value: number): string => new Date(value).toISOString();
const job = (model: string | null, min_headroom_pct = 0) => ({ model, min_headroom_pct });
/** One minute after cc's reading. */
const T0 = plus(CC_OBSERVED, 60);
const MEASURED_EDGE = iso(ms(CC_OBSERVED) + 1200 * 1000);
const UNKNOWN_EDGE = iso(ms(CC_OBSERVED) + 7200 * 1000);

describe("review round 2: the staleness edges are where the answer changes", () => {
  it("classifies each edge as its later side, like a reset", () => {
    expect(classifyStaleness(CC_OBSERVED, iso(ms(MEASURED_EDGE) - 1)).grade).toBe("MEASURED");
    expect(classifyStaleness(CC_OBSERVED, MEASURED_EDGE).grade).toBe("STALE");
    expect(classifyStaleness(CC_OBSERVED, iso(ms(UNKNOWN_EDGE) - 1)).grade).toBe("STALE");
    expect(classifyStaleness(CC_OBSERVED, UNKNOWN_EDGE).grade).toBe("UNKNOWN");
  });

  it("a Halogen seat: each advertised transition is a change, and nothing is skipped", () => {
    const seat = halogenSeat(0);
    const first = Option.getOrThrow(nextTransitionAt([seat], T0));
    expect(first).toBe(MEASURED_EDGE);
    expect(projectSeat(seat, T0).reading.grade).toBe("MEASURED");
    expect(projectSeat(seat, first).reading.grade).toBe("STALE");
    const second = Option.getOrThrow(nextTransitionAt([seat], first));
    expect(second).toBe(UNKNOWN_EDGE);
    expect(projectSeat(seat, iso(ms(second) - 1)).reading.grade).toBe("STALE");
    expect(projectSeat(seat, second).reading.grade).toBe("UNKNOWN");
    // From the UNKNOWN edge on nothing is ahead, and nothing changes again.
    expect(Option.getOrNull(nextTransitionAt([seat], second))).toBeNull();
    expect(projectSeat(seat, plus(second, 30 * 86400)).reading.grade).toBe("UNKNOWN");
  });

  it("a Claude seat at observed + 7200 s is UNKNOWN, not STALE with six-day-old numbers", () => {
    const seat = claudeSeat({ seat: "cc2" });
    const atEdge = projectSeat(seat, UNKNOWN_EDGE);
    expect(atEdge.reading.grade).toBe("UNKNOWN");
    expect(atEdge.headroom_pct).toBeNull();
    const before = projectSeat(seat, iso(ms(UNKNOWN_EDGE) - 1));
    expect(before.reading.grade).toBe("STALE");
    expect(Option.getOrThrow(nextTransitionAt([seat], iso(ms(UNKNOWN_EDGE) - 1)))).toBe(UNKNOWN_EDGE);
  });

  it("an admission is never a zero-length yes: at the MEASURED edge it refuses STALE", () => {
    const justBefore = admitSeat("cc", claudeSeat(), job("Opus"), iso(ms(MEASURED_EDGE) - 1));
    expect(justBefore).toMatchObject({ admit: true, until: MEASURED_EDGE });
    expect(admitSeat("cc", claudeSeat(), job("Opus"), MEASURED_EDGE)).toMatchObject({
      admit: false,
      reason: "stale"
    });
    expect(admitSeat("gpu-worker", halogenSeat(0), job(null), MEASURED_EDGE)).toMatchObject({
      admit: false,
      reason: "stale"
    });
  });

  it("the clock-skew refusal ends at observed_at - 120 s, and that is a transition", () => {
    const early = plus(CC_OBSERVED, -600);
    expect(admitSeat("cc", claudeSeat(), job("Opus"), early)).toMatchObject({ reason: "clock-skew" });
    const next = Option.getOrThrow(nextTransitionAt([claudeSeat()], early));
    expect(next).toBe(plus(CC_OBSERVED, -120));
    expect(admitSeat("cc", claudeSeat(), job("Opus"), next).admit).toBe(true);
  });
});

// --- the transition properties ------------------------------------------------

const BASE = Date.parse("2026-09-01T00:00:00Z");
const DAY = 86400 * 1000;
const offsetArb = fc.integer({ min: 0, max: 40 * DAY });
const instantArb = offsetArb.map((offset) => iso(BASE + offset));
const windowArb = fc
  .record({
    kind: fc.constantFrom("five_hour", "seven_day", "model_scoped"),
    utilization_pct: fc.option(fc.integer({ min: 0, max: 100 }), { nil: null }),
    resets_at: fc.option(instantArb, { nil: null }),
    binding: fc.boolean(),
    severity: fc.constantFrom(null, "normal", "warning", "critical"),
    grade: fc.constantFrom("MEASURED", "STALE", "ESTIMATED", "UNKNOWN", "PROJECTED"),
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
const seatArb = (sharp: boolean) =>
  fc
    .record({
      halogen: fc.boolean(),
      holders: fc.integer({ min: 0, max: 2 }),
      windows: fc.array(windowArb, { maxLength: 4 }),
      observed_at: instantArb,
      grade: sharp
        ? fc.constant("MEASURED")
        : fc.constantFrom("MEASURED", "STALE", "ESTIMATED", "UNKNOWN", "PROJECTED"),
      dispatchable: sharp ? fc.constant(true) : fc.boolean(),
      plan: sharp ? fc.constant(null) : fc.option(instantArb.map((expires_at) => ({ expires_at })), { nil: null })
    })
    .map(({ halogen, holders, ...raw }): SeatCapacity =>
      halogen
        ? claudeSeat({ ...raw, provider: "halogen", windows: [], slots: { capacity: 1, holders } })
        : claudeSeat(raw)
    );

const JOBS = [null, "Fable", "Opus", "claude-fable-5-1"].map((model) => job(model));

/** Everything a caller can act on at `asOf`, without the clock-derived age and prose. */
const observable = (seat: SeatCapacity, asOf: string) => {
  const projection = projectSeat(seat, asOf);
  return {
    reading: projection.reading,
    headroom_pct: projection.headroom_pct,
    lapses: projection.lapses,
    admission: JOBS.map((entry) => {
      const decision = admitSeat(seat.seat, seat, entry, asOf);
      return decision.admit
        ? { admit: true, until: decision.until, signal: decision.signal, headroom: decision.headroom_pct }
        : {
            admit: false,
            reason: decision.reason,
            retry_at: decision.retry_at,
            signal: decision.signal,
            raise_demand: decision.raise_demand
          };
    })
  };
};

/** An `asOf` that is often exactly on, or 1 ms either side of, one of the seat's edges. */
const asOfFor = (seat: SeatCapacity, random: string, pick: number, nudge: number): string => {
  const observed = ms(seat.observed_at);
  const candidates = [
    ms(random),
    observed - 120 * 1000,
    observed + 1200 * 1000,
    observed + 7200 * 1000,
    ...(seat.plan === null ? [] : [ms(seat.plan.expires_at)]),
    ...seat.windows.flatMap((entry) => (entry.resets_at === null ? [] : [ms(entry.resets_at)]))
  ];
  return iso((candidates[pick % candidates.length] ?? observed) + nudge);
};

describe("review round 2: transition properties", () => {
  it("nothing a caller can see changes strictly between asOf and nextTransitionAt", () => {
    fc.assert(
      fc.property(
        seatArb(false),
        instantArb,
        fc.nat(),
        fc.constantFrom(-1, 0, 1),
        fc.double({ min: 0, max: 1, noNaN: true }),
        (seat, random, pick, nudge, fraction) => {
          const asOf = asOfFor(seat, random, pick, nudge);
          const before = observable(seat, asOf);
          const next = nextTransitionAt([seat], asOf);
          const end = Option.isSome(next) ? ms(next.value) : ms(asOf) + 60 * DAY;
          if (end - ms(asOf) < 2) return;
          const last = iso(end - 1);
          const inside = iso(Math.min(end - 1, ms(asOf) + 1 + Math.floor(fraction * (end - ms(asOf) - 1))));
          expect(observable(seat, last)).toEqual(before);
          expect(observable(seat, inside)).toEqual(before);
        }
      ),
      { numRuns: 1500 }
    );
  });

  it("for a MEASURED, dispatchable seat with no plan, the answer at nextTransitionAt differs", () => {
    fc.assert(
      fc.property(
        seatArb(true),
        instantArb,
        fc.nat(),
        fc.constantFrom(-1, 0, 1),
        (seat, random, pick, nudge) => {
          const asOf = asOfFor(seat, random, pick, nudge);
          const next = nextTransitionAt([seat], asOf);
          if (Option.isNone(next)) return;
          expect(observable(seat, next.value)).not.toEqual(observable(seat, asOf));
        }
      ),
      { numRuns: 1500 }
    );
  });
});

// --- model families -----------------------------------------------------------

describe("review round 2: a model-scoped limit is matched by model family", () => {
  it("a Fable job named by its model id is refused while the Fable row is critical", () => {
    for (const model of ["fable", "Fable", "claude-fable-5-1", "claude-fable-5-1[1m]"]) {
      expect(admitSeat("cc", claudeSeat(), job(model), T0)).toMatchObject({
        admit: false,
        reason: "severity-critical"
      });
    }
  });

  it("an Opus job named by its model id still admits beside the critical Fable row", () => {
    for (const model of ["Opus", "claude-opus-5", "claude-opus-5[1m]", "claude-opus-5-5"]) {
      expect(admitSeat("cc", claudeSeat(), job(model), T0)).toMatchObject({
        admit: true,
        checked: [
          { kind: "five_hour", model: null },
          { kind: "seven_day", model: null }
        ]
      });
    }
  });

  it("a window published under the model id meets a job named by the alias", () => {
    const seat = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET }),
        window({ kind: "model_scoped", model: "claude-fable-5-1", utilization_pct: 100, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", seat, job("Fable"), T0)).toMatchObject({ admit: false, reason: "window-exhausted" });
  });

  it("a job model that names no known family refuses, even on a complete reading", () => {
    for (const model of ["gpt-5", "mystery", "claude-opus-fable"]) {
      expect(admitSeat("cc", claudeSeat(), job(model), T0)).toMatchObject({
        admit: false,
        reason: "window-unknown",
        raise_demand: true
      });
    }
  });

  it("a model no family knows is still checked against a window that names it verbatim", () => {
    const seat = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET }),
        window({ kind: "model_scoped", model: "Mythos", utilization_pct: 10, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", seat, job("mythos"), T0)).toMatchObject({
      admit: true,
      checked: [
        { kind: "five_hour", model: null },
        { kind: "seven_day", model: null },
        { kind: "model_scoped", model: "Mythos" }
      ]
    });
  });
});

// --- owner, projected grade, published_at ---------------------------------------

describe("review round 2: a third party's seat is never admitted", () => {
  it("refuses a third-party seat that arrives dispatchable", () => {
    const seat = claudeSeat({ seat: "codex", owner: "third-party", dispatchable: true });
    expect(admitSeat("codex", seat, job(null), T0)).toMatchObject({
      admit: false,
      reason: "not-dispatchable",
      detail: expect.stringContaining("third-party")
    });
  });
});

describe("review round 2: a publisher's PROJECTED grade is never a measurement", () => {
  it("projectSeatReading keeps a stated PROJECTED seat PROJECTED while it is young", () => {
    expect(projectSeatReading(claudeSeat({ grade: "PROJECTED" }), T0).grade).toBe("PROJECTED");
    // Age still wins over it.
    expect(projectSeatReading(claudeSeat({ grade: "PROJECTED" }), plus(CC_OBSERVED, 1500)).grade).toBe("STALE");
  });

  it("refuses a Claude seat and a Halogen slot row stated PROJECTED, and raises demand", () => {
    expect(admitSeat("cc", claudeSeat({ grade: "PROJECTED" }), job("Opus"), T0)).toMatchObject({
      admit: false,
      reason: "projected",
      raise_demand: true
    });
    expect(admitSeat("gpu-worker", { ...halogenSeat(0), grade: "PROJECTED" }, job(null), T0)).toMatchObject({
      admit: false,
      reason: "projected",
      raise_demand: true
    });
  });
});

describe("review round 2: a published_at dated in the future is refused", () => {
  const empty: ReadonlyMap<string, StoredSeat> = new Map();

  it("refuses the whole snapshot, every seat `future`, and changes nothing", () => {
    const skewed = ingestSnapshot(
      empty,
      snapshot([claudeSeat(), halogenSeat(0)], "2099-01-01T00:00:00Z"),
      T0
    );
    expect(skewed.report).toEqual({
      results: [
        { seat: "cc", outcome: "future" },
        { seat: "gpu-worker", outcome: "future" }
      ],
      changed: false
    });
    expect(skewed.next.size).toBe(0);
  });

  it("accepts a published_at within the skew tolerance, refuses one just beyond it", () => {
    expect(ingestSnapshot(empty, snapshot([claudeSeat()], plus(T0, 120)), T0).report.changed).toBe(true);
    expect(ingestSnapshot(empty, snapshot([claudeSeat()], plus(T0, 121)), T0).report.results).toEqual([
      { seat: "cc", outcome: "future" }
    ]);
  });

  it("a later eviction on the same observed_at lands after a skewed publish was refused", () => {
    const first = ingestSnapshot(empty, snapshot([claudeSeat()], plus(T0, 5)), plus(T0, 5));
    const skewed = ingestSnapshot(first.next, snapshot([claudeSeat({ stale_reason: "x" })], "2099-01-01T00:00:00Z"), plus(T0, 10));
    expect(skewed.report.changed).toBe(false);
    const evicted = claudeSeat({ dispatchable: false, dispatchable_reason: "evicted" });
    const second = ingestSnapshot(skewed.next, snapshot([evicted], plus(T0, 30)), plus(T0, 30));
    expect(second.report.results).toEqual([{ seat: "cc", outcome: "accepted" }]);
    expect(admitSeat("cc", second.next.get("cc")?.seat, job(null), plus(T0, 60))).toMatchObject({
      admit: false,
      reason: "not-dispatchable"
    });
  });
});

// --- the fail-closed property's counterexample -----------------------------------

describe("review round 2: a non-binding window is not checked", () => {
  const seat = claudeSeat({
    windows: [
      window({ kind: "five_hour", binding: false, utilization_pct: null, resets_at: null }),
      window({ kind: "five_hour", utilization_pct: 0, resets_at: CC_FIVE_HOUR_RESET }),
      window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET })
    ]
  });

  it("the seeded counterexample admits: the non-binding UNKNOWN five-hour window is ignored", () => {
    expect(admitSeat("cc", seat, job(null), T0)).toMatchObject({ admit: true, headroom_pct: 28 });
  });

  it("a non-binding exhausted five-hour window does not refuse", () => {
    const exhausted = claudeSeat({
      windows: [
        window({ kind: "five_hour", binding: false, utilization_pct: 100, severity: "critical", resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", exhausted, job(null), T0)).toMatchObject({
      admit: true,
      checked: [{ kind: "seven_day", model: null }]
    });
  });
});

// --- the round 2 mutation survivors ---------------------------------------------

describe("review round 2: pinned against the surviving mutants", () => {
  it("M05: admission at exactly the plan's end refuses", () => {
    const expires = plus(CC_OBSERVED, 300);
    const seat = claudeSeat({ plan: { expires_at: expires } });
    expect(admitSeat("cc", seat, job(null), plus(expires, -0.001)).admit).toBe(true);
    expect(admitSeat("cc", seat, job(null), expires)).toMatchObject({ admit: false, reason: "plan-expired" });
  });

  it("M11: retry_at is the latest reset among the exhausted windows", () => {
    const seat = claudeSeat({
      windows: [
        window({ kind: "five_hour", utilization_pct: 100, resets_at: CC_FIVE_HOUR_RESET }),
        window({ kind: "seven_day", utilization_pct: 100, resets_at: CC_WEEKLY_RESET })
      ]
    });
    expect(admitSeat("cc", seat, job(null), T0)).toMatchObject({
      admit: false,
      reason: "window-exhausted",
      retry_at: iso(ms(CC_WEEKLY_RESET))
    });
  });

  it("M16: a Halogen admission holds no later than the plan's end", () => {
    const expires = plus(CC_OBSERVED, 600);
    const seat = { ...halogenSeat(0), plan: { expires_at: expires } };
    expect(admitSeat("gpu-worker", seat, job(null), T0)).toMatchObject({ admit: true, until: iso(ms(expires)) });
  });

  it("N17: an ESTIMATED seat refuses even when its windows say MEASURED", () => {
    expect(admitSeat("cc", claudeSeat({ grade: "ESTIMATED" }), job(null), T0)).toMatchObject({
      admit: false,
      reason: "estimated"
    });
  });
});
