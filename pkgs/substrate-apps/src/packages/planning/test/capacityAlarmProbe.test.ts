/**
 * Capacity scout probes (eval/2026-09-23-capacity-scout).
 *
 * Two properties the capacity design depends on, pinned as they are TODAY:
 *
 *  1. A reading whose `next_window_at` is already in the past (the live cc3
 *     row carries resets_at 2026-09-11 while being republished every 30 s)
 *     leaves `alarm_at` at that past instant after the alarm fires. The Worker's
 *     `#reconcileAlarm` then calls `setAlarm(past)` again, which the runtime
 *     fires at once: a wake loop that only a newer reading can end.
 *  2. `minimumNextWindow` compares instants as strings. Two spellings of
 *     instants with different UTC offsets order wrongly.
 *
 * The scout committed them asserting the defective behaviour; the capacity
 * branch (eval/2026-09-23-capacity) fixed both and flipped them: the alarm is
 * recomputed strictly after the instant that fired, and instants are compared
 * with Date.parse.
 */
import { Effect } from "effect";
import { describe, expect, it } from "vitest";
import { Factory, factoryTestLayer } from "../src/objects/index.ts";
import { cloudReading, reading, releaseState } from "./fixtures.ts";

const empty = releaseState([], { plans: [] });
const run = <A, E>(program: Effect.Effect<A, E, Factory>) =>
  Effect.runPromise(
    program.pipe(Effect.provide(factoryTestLayer(empty))) as Effect.Effect<A, E, never>
  );

describe("capacity scout probes", () => {
  it("drops a past next_window_at from alarm_at once the alarm fires (no re-arm loop)", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const past = "2026-09-12T11:00:00.199042+00:00";
        yield* factory.observeCapacity(reading({ seq: 1, nextWindowAt: past }));
        expect((yield* factory.stateView).alarm_at).toBe(past);
        yield* factory.alarm("2026-09-23T04:50:00.000Z");
        // Spent: nothing lies after the instant that fired, so there is no alarm.
        expect((yield* factory.stateView).alarm_at).toBeNull();
        // And with a clock passed in, a past instant is never taken at all.
        yield* factory.observeCapacity(reading({ seq: 2, nextWindowAt: past }), "2026-09-23T04:51:00.000Z");
        expect((yield* factory.stateView).alarm_at).toBeNull();
      })
    ));

  it("orders instants with different offsets as instants, not as strings", () =>
    run(
      Effect.gen(function* () {
        const factory = yield* Factory;
        // 09:00+02:00 is 07:00Z, which is EARLIER than 08:00Z.
        yield* factory.observeCapacity(reading({ seq: 1, nextWindowAt: "2026-09-23T09:00:00+02:00" }));
        yield* factory.observeCapacity(cloudReading({ seq: 1, nextWindowAt: "2026-09-23T08:00:00Z" }));
        const alarmAt = (yield* factory.stateView).alarm_at;
        // The earlier instant wins, in its own spelling, although "09" > "08" as text.
        expect(alarmAt).toBe("2026-09-23T09:00:00+02:00");
        expect(Date.parse(alarmAt ?? "")).toBeLessThan(Date.parse("2026-09-23T08:00:00Z"));
      })
    ));
});
