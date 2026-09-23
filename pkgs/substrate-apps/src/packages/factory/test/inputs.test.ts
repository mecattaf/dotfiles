import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  Factory,
  FactoryCapacityFeed,
  FactoryPriceSource,
  constantPriceVectorLayer,
  fakeCapacityLayer,
  loadFactoryInputs
} from "../src/index.ts";
import { PriceVector } from "@substrate/planning/schema/prices.ts";
import { factoryFor, item, reading } from "./fixtures.ts";

const decodePrices = Schema.decodeUnknownSync(PriceVector);

describe("the in-memory composition Layers", () => {
  it("wires a constant PriceVector and fake capacity readings into the service", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const prices = decodePrices({
      hash: "9".repeat(64),
      rows: [{ row: "gpu-coordinator", price: 0 }],
      drum: 1,
      stage: [{ family: "build", holdingCost: 0 }]
    });
    const capacity = reading({ nextWindowAt: "2026-09-06T17:00:00Z" });
    const state = await Effect.runPromise(
      loadFactoryInputs().pipe(
        Effect.provideService(Factory, Factory.of(factory)),
        Effect.provide(fakeCapacityLayer([capacity])),
        Effect.provide(constantPriceVectorLayer(prices))
      )
    );
    expect(state.price_hash).toBe("9".repeat(64));
    expect(state.latest_readings.coordinator?.seq).toBe(1);
    expect(state.alarm_at).toBe("2026-09-06T17:00:00Z");
  });

  it("exposes the two test inputs as distinct Effect services", async () => {
    const capacity = reading({});
    const prices = decodePrices({
      hash: "8".repeat(64),
      rows: [],
      drum: 1,
      stage: []
    });
    const values = await Effect.runPromise(
      Effect.gen(function* () {
        const feed = yield* FactoryCapacityFeed;
        const price = yield* FactoryPriceSource;
        return [(yield* feed.readings).length, price.prices.hash] as const;
      }).pipe(
        Effect.provide(fakeCapacityLayer([capacity])),
        Effect.provide(constantPriceVectorLayer(prices))
      )
    );
    expect(values).toEqual([1, "8".repeat(64)]);
  });
});
