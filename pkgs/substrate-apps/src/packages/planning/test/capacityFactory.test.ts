/**
 * The Factory with its capacity ledger: seat ingestion, the alarm at the next
 * transition, and no alarm ever at or before the instant it is computed for.
 */
import { Effect, Option } from "effect";
import { describe, expect, it } from "vitest";
import { Factory, factoryTestLayer } from "../src/objects/index.ts";
import { reading, releaseState } from "./fixtures.ts";
import {
  CC_FIVE_HOUR_RESET,
  CC_OBSERVED,
  cc3Seat,
  claudeSeat,
  plus,
  snapshot
} from "./seatCapacityFixtures.ts";

const empty = releaseState([], { plans: [] });
const run = <A, E>(program: Effect.Effect<A, E, Factory>) =>
  Effect.runPromise(
    program.pipe(Effect.provide(factoryTestLayer(empty))) as Effect.Effect<A, E, never>
  );
const T0 = plus(CC_OBSERVED, 60);
const opus = { model: "Opus", min_headroom_pct: 0 } as const;

describe("the Factory's capacity ledger", () => {
  it("ingests a pushed snapshot, projects it and sets the alarm at the next transition", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const report = yield* factory.observeSeats(snapshot([claudeSeat()]), T0);
        expect(report.changed).toBe(true);
        const state = yield* factory.stateView;
        expect(state.alarm_at).toBe(plus(CC_OBSERVED, 1200));
        expect(state.seat_readings.map((entry) => entry.seat.seat)).toEqual(["cc"]);
        const view = yield* factory.capacityAt(T0);
        expect(view.seats[0]?.headroom_pct).toBe(28);
        expect(view.next_transition_at).toBe(plus(CC_OBSERVED, 1200));
        expect((yield* factory.admitSeat("cc", opus, T0)).admit).toBe(true);
        expect((yield* factory.admitSeat("cc", opus, plus(CC_OBSERVED, 1500))).admit).toBe(false);
      })
    ));

  it("a repeated push changes nothing and does not move the alarm", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const pushed = snapshot([claudeSeat()]);
        yield* factory.observeSeats(pushed, T0);
        const before = yield* factory.stateView;
        const again = yield* factory.observeSeats(pushed, plus(T0, 600));
        expect(again).toEqual({ results: [{ seat: "cc", outcome: "duplicate" }], changed: false });
        expect(yield* factory.stateView).toEqual(before);
      })
    ));

  it("seats riding on a reading are folded in even when the reading's seq is a repeat", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        expect(yield* factory.observeCapacity(reading({ seq: 1 }), T0)).toBe(true);
        const withSeats = { ...reading({ seq: 1 }), seats: snapshot([claudeSeat()]) };
        expect(yield* factory.observeCapacity(withSeats, T0)).toBe(false);
        const state = yield* factory.stateView;
        expect(state.seat_readings.map((entry) => entry.seat.seat)).toEqual(["cc"]);
        expect(state.alarm_at).toBe(plus(CC_OBSERVED, 1200));
        // The reading is kept without its seats: they are the ledger's.
        expect(state.latest_readings.coordinator).not.toHaveProperty("seats");
      })
    ));

  it("firing the alarm repeatedly walks strictly forward through the transitions (no wake loop)", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        // cc3's resets are 11 days in the past; cc's are ahead.
        yield* factory.observeSeats(snapshot([claudeSeat(), cc3Seat()]), T0);
        const fired: Array<string> = [];
        let at = (yield* factory.stateView).alarm_at;
        for (let step = 0; step < 12 && at !== null; step += 1) {
          fired.push(at);
          yield* factory.alarm(at);
          const next = (yield* factory.stateView).alarm_at;
          if (next !== null) expect(Date.parse(next)).toBeGreaterThan(Date.parse(at));
          at = next;
        }
        expect(fired.slice(0, 3)).toEqual([
          plus(CC_OBSERVED, 1200),
          plus(CC_OBSERVED, 7200),
          new Date(Date.parse(CC_FIVE_HOUR_RESET)).toISOString()
        ]);
        expect(new Set(fired).size).toBe(fired.length);
      })
    ));

  it("rearm recomputes a stored alarm that has fallen into the past", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const past = "2026-09-12T11:00:00Z";
        yield* factory.observeCapacity(reading({ seq: 1, nextWindowAt: past }));
        expect((yield* factory.stateView).alarm_at).toBe(past);
        yield* factory.observeSeats(snapshot([claudeSeat()]), T0);
        const rearmed = yield* factory.rearm(T0);
        expect(Option.getOrNull(rearmed)).toBe(plus(CC_OBSERVED, 1200));
        expect((yield* factory.stateView).alarm_at).toBe(plus(CC_OBSERVED, 1200));
      })
    ));

  it("with a clock, observeCapacity never takes an instant at or before it", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.observeCapacity(reading({ seq: 1, nextWindowAt: T0 }), T0);
        expect((yield* factory.stateView).alarm_at).toBeNull();
        yield* factory.observeCapacity(reading({ seq: 2, nextWindowAt: plus(T0, 1) }), T0);
        expect((yield* factory.stateView).alarm_at).toBe(plus(T0, 1));
      })
    ));
});
