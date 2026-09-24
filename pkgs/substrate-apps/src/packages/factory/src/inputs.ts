/**
 * Host-neutral input Layers used to compose the Factory.
 *
 * Capacity arrives two ways and both cross `FactoryCapacityFeed`: authored
 * readings and seat snapshots (`fakeCapacityLayer`, the hermetic bench) and the
 * seats the capacity ledger holds in the object's own store
 * (`ledgerCapacityFeedLayer`, backed by Durable Object storage in the Worker and
 * by the in-memory store in tests).
 */
import { Context, Effect, Layer } from "effect";
import {
  CapacityLedger,
  capacityLedgerLayer
} from "@substrate/planning/capacity/ledger.ts";
import { PlanningStore } from "@substrate/planning/objects/storage.ts";
import type { CapacityReading } from "@substrate/planning/schema/capacity.ts";
import {
  SEAT_CAPACITY_SCHEMA_VERSION,
  type SeatCapacitySnapshot
} from "@substrate/planning/schema/seatCapacity.ts";
import type { PriceVector } from "@substrate/planning/schema/prices.ts";
import { Factory } from "@substrate/planning/objects/factory.ts";
import { FactoryError } from "@substrate/planning/schema/errors.ts";

interface IFactoryCapacityFeed {
  readonly readings: Effect.Effect<ReadonlyArray<CapacityReading>>;
  /** Per-seat capacity snapshots (`seat-capacity/2`). */
  readonly seats: Effect.Effect<ReadonlyArray<SeatCapacitySnapshot>>;
}

/** A capacity source; production and test sources cross the same interface. */
export class FactoryCapacityFeed extends Context.Service<
  FactoryCapacityFeed,
  IFactoryCapacityFeed
>()("@substrate/factory/FactoryCapacityFeed") {}

interface IFactoryPriceSource {
  readonly prices: PriceVector;
}

/** The immutable price vector used for every evaluation in one composition. */
export class FactoryPriceSource extends Context.Service<
  FactoryPriceSource,
  IFactoryPriceSource
>()("@substrate/factory/FactoryPriceSource") {}

/** Provides authored fake readings and seat snapshots without a live capacity plane. */
export const fakeCapacityLayer = (
  readings: ReadonlyArray<CapacityReading>,
  seats: ReadonlyArray<SeatCapacitySnapshot> = []
): Layer.Layer<FactoryCapacityFeed> =>
  Layer.succeed(FactoryCapacityFeed)(
    FactoryCapacityFeed.of({ readings: Effect.succeed(readings), seats: Effect.succeed(seats) })
  );

/**
 * The real capacity feed: the seats the capacity ledger holds, one snapshot per
 * publishing host, read from whichever `PlanningStore` is provided.
 *
 * Readings are not replayed from here: the kernel's readings are the Factory's
 * own stored state and arrive by `POST /capacity`. A store that cannot be read
 * yields no seats, which the admission predicate answers `unknown-seat`, so a
 * storage failure can only ever refuse work, never admit it.
 */
const ledgerCapacityFeedLayer: Layer.Layer<FactoryCapacityFeed, never, CapacityLedger> =
  Layer.effect(
    FactoryCapacityFeed,
    Effect.gen(function* () {
      const ledger = yield* CapacityLedger;
      const seats = ledger.latest.pipe(
        Effect.map((held) => {
          const byHost = new Map<string, Array<(typeof held)[number]>>();
          for (const entry of held) byHost.set(entry.host, [...(byHost.get(entry.host) ?? []), entry]);
          return [...byHost].map(
            ([host, entries]): SeatCapacitySnapshot => ({
              schema_version: SEAT_CAPACITY_SCHEMA_VERSION,
              host,
              published_at: entries
                .map((entry) => entry.published_at)
                .reduce((latest, next) => (Date.parse(next) > Date.parse(latest) ? next : latest)),
              seats: entries.map((entry) => entry.seat)
            })
          );
        }),
        Effect.orElseSucceed((): ReadonlyArray<SeatCapacitySnapshot> => [])
      );
      return FactoryCapacityFeed.of({ readings: Effect.succeed([]), seats });
    })
  );

/** The real capacity feed over the provided store, ledger included. */
export const storedCapacityLayer: Layer.Layer<FactoryCapacityFeed, never, PlanningStore> =
  ledgerCapacityFeedLayer.pipe(Layer.provide(capacityLedgerLayer));

/** Provides one constant, authored price vector. */
export const constantPriceVectorLayer = (
  prices: PriceVector
): Layer.Layer<FactoryPriceSource> =>
  Layer.succeed(FactoryPriceSource)(FactoryPriceSource.of({ prices }));

/**
 * Wires the service to its constant price vector and fake/read-only capacity
 * source. The production Worker supplies different Layers; the state machine is
 * unchanged.
 *
 * @param receivedAt the receiving clock for seat snapshots. Required when the
 *   feed carries any: a snapshot's own `published_at` is never the receipt
 *   time, so without a clock seats are refused `NoClock`. Re-feeding what the
 *   ledger already holds is a no-op (idempotent).
 */
export const loadFactoryInputs = (receivedAt?: string) =>
  Effect.gen(function* () {
    const factory = yield* Factory;
    const capacity = yield* FactoryCapacityFeed;
    const price = yield* FactoryPriceSource;
    const current = yield* factory.releaseState;
    yield* factory.restore({ ...current, prices: price.prices });
    const readings = yield* capacity.readings;
    for (const reading of readings) yield* factory.observeCapacity(reading, receivedAt);
    const seats = yield* capacity.seats;
    if (seats.length > 0) {
      if (receivedAt === undefined) {
        return yield* Effect.fail(
          new FactoryError({ reason: "NoClock", operation: "loadFactoryInputs", subject: "capacity/seats" })
        );
      }
      for (const snapshot of seats) yield* factory.observeSeats(snapshot, receivedAt);
    }
    return yield* factory.stateView;
  });
