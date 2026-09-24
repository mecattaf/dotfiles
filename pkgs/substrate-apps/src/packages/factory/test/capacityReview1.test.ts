/**
 * Capacity review round 1 (evals-2026-09-23/capacity/IMPL.md, "Fix round 1").
 *
 * Each case pins a defect the reviewers reproduced on the branch:
 *
 * - a request that lands after a due alarm and before its delivery must not
 *   cancel or replace that alarm (the Worker's post-request reconcile);
 * - a clock-less host must not ingest seats against the publisher's own
 *   `published_at`, on any door;
 * - an undecodable `capacity/seats` key must not take down routes that have
 *   nothing to do with seat capacity, nor the Worker's post-request step.
 */
import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  Factory,
  fakeCapacityLayer,
  loadFactoryInputs,
  makeFactory,
  makeFactoryHttpHandler,
  makeInMemoryPlanningStore,
  makeTableArtifactHasher,
  PlanningStore,
  StorageKey,
  constantPriceVectorLayer,
  type IFactory
} from "../src/index.ts";
import { reconcileRuntimeAlarm, type AlarmStorage } from "../../../apps/floor/src/alarm.ts";
import { CapacityReading } from "@substrate/planning/schema/capacity.ts";
import { PriceVector } from "@substrate/planning/schema/prices.ts";
import { FactoryError } from "@substrate/planning/schema/errors.ts";
import {
  CC_OBSERVED,
  claudeSeat,
  plus,
  snapshot
} from "../../planning/test/seatCapacityFixtures.ts";
import { artifactBytes, artifactDigest, emptyFactory, reading, releaseState, run } from "./fixtures.ts";
import { cloudReading } from "../../planning/test/fixtures.ts";

const encodeReading = Schema.encodeSync(CapacityReading);
const T0 = plus(CC_OBSERVED, 60);

const request = (path: string, method: "GET" | "POST", body?: unknown) =>
  new Request(`https://factory.invalid${path}`, {
    method,
    headers: {
      authorization: "Bearer test-token",
      ...(body === undefined ? {} : { "content-type": "application/json" })
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });

const handlerOver = (factory: IFactory, now?: () => string) =>
  makeFactoryHttpHandler({
    factory,
    token: "test-token",
    artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]]),
    ...(now === undefined ? {} : { now })
  });

const json = async (response: Response) => ({ status: response.status, body: await response.json() });

/** A Durable Object's alarm cell, as the Worker sees it through ctx.storage. */
const fakeStorage = (alarm: number | null) => {
  const log: Array<string> = [];
  const storage: AlarmStorage & { alarm: number | null; readonly log: Array<string> } = {
    alarm,
    log,
    getAlarm: async () => storage.alarm,
    setAlarm: async (at: number) => {
      storage.alarm = at;
      log.push(`set ${new Date(at).toISOString()}`);
    },
    deleteAlarm: async () => {
      storage.alarm = null;
      log.push("delete");
    }
  };
  return storage;
};

describe("the Worker's reconcile never drops a due, undelivered alarm", () => {
  const T = "2026-09-23T06:00:00.000Z";
  const armedAt = async (readings: ReadonlyArray<ReturnType<typeof reading>>) => {
    const factory = await emptyFactory();
    for (const entry of readings) {
      await run(factory.observeCapacity(entry, "2026-09-23T05:00:00.000Z"));
    }
    expect((await run(factory.stateView)).alarm_at).toBe(T);
    return factory;
  };

  it("a GET 20 ms after T, before delivery, leaves the alarm at T; its delivery wakes the object", async () => {
    const factory = await armedAt([reading({ seq: 1, nextWindowAt: T })]);
    const storage = fakeStorage(Date.parse(T));
    await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(T) + 20, path: "request" });
    expect(storage.alarm).toBe(Date.parse(T));
    expect(storage.log).toEqual([]);
    // The runtime delivers the alarm (and clears it) 30 ms after T.
    storage.alarm = null;
    const firedAt = new Date(Date.parse(T) + 30).toISOString();
    await run(factory.alarm(firedAt));
    await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(firedAt), path: "alarm" });
    expect((await run(factory.stateView)).alarm_fired_at).toBe(firedAt);
    expect(storage.alarm).toBeNull();
  });

  it("with a later transition held, the due alarm is not replaced by the later one", async () => {
    const later = "2026-09-23T07:00:00.000Z";
    const factory = await armedAt([reading({ seq: 1, nextWindowAt: T })]);
    // A second executor's row carries the later transition.
    await run(factory.observeCapacity(cloudReading({ seq: 1, nextWindowAt: later }), "2026-09-23T05:00:00.000Z"));
    const storage = fakeStorage(Date.parse(T));
    await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(T) + 20, path: "request" });
    expect(storage.alarm).toBe(Date.parse(T));
    storage.alarm = null;
    const firedAt = new Date(Date.parse(T) + 30).toISOString();
    await run(factory.alarm(firedAt));
    await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(firedAt), path: "alarm" });
    expect(storage.alarm).toBe(Date.parse(later));
  });

  it("an alarm not yet due is still moved or cleared as before", async () => {
    const factory = await armedAt([reading({ seq: 1, nextWindowAt: T })]);
    const early = fakeStorage(Date.parse("2026-09-23T08:00:00.000Z"));
    await reconcileRuntimeAlarm({ storage: early, factory, nowMs: Date.parse(T) - 60_000, path: "request" });
    expect(early.alarm).toBe(Date.parse(T));
    const empty = await emptyFactory();
    const stray = fakeStorage(Date.parse(T));
    await reconcileRuntimeAlarm({ storage: stray, factory: empty, nowMs: Date.parse(T) - 60_000, path: "request" });
    expect(stray.log).toEqual(["delete"]);
  });

  it("on the alarm path a stored instant at or before now is replaced, never kept", async () => {
    const factory = await armedAt([reading({ seq: 1, nextWindowAt: T })]);
    const firedAt = new Date(Date.parse(T) + 30).toISOString();
    await run(factory.alarm(firedAt));
    const storage = fakeStorage(Date.parse(T));
    await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(firedAt), path: "alarm" });
    expect(storage.log).toEqual(["delete"]);
  });

  it("a failing rearm on the request path is contained; on the alarm path it is raised", async () => {
    const broken = {
      rearm: () =>
        Effect.fail(
          new FactoryError({ reason: "PersistenceFailed", operation: "Factory.rearm", subject: "capacity/seats" })
        )
    } as unknown as IFactory;
    const storage = fakeStorage(null);
    const outcome = await reconcileRuntimeAlarm({ storage, factory: broken, nowMs: Date.parse(T), path: "request" });
    expect(outcome).toMatchObject({ action: "failed" });
    await expect(
      reconcileRuntimeAlarm({ storage, factory: broken, nowMs: Date.parse(T), path: "alarm" })
    ).rejects.toBeDefined();
  });
});

describe("a clock-less host never ingests seats", () => {
  const far = "2099-01-01T00:00:00Z";
  const poisoned = () => snapshot([claudeSeat({ observed_at: far })], far);

  it("POST /capacity with seats and no clock is refused 501 NoClock, and nothing is folded in", async () => {
    const factory = await emptyFactory();
    const handler = handlerOver(factory);
    const body = { ...encodeReading(reading({})), seats: poisoned() };
    expect(await json(await handler(request("/capacity", "POST", body)))).toEqual({
      status: 501,
      body: { error: "NoClock", subject: "/capacity" }
    });
    const state = await run(factory.stateView);
    expect(state.seat_readings).toEqual([]);
    expect(state.latest_readings).toEqual({});
  });

  it("POST /capacity without seats still works without a clock", async () => {
    const handler = handlerOver(await emptyFactory());
    expect(await json(await handler(request("/capacity", "POST", encodeReading(reading({})))))).toEqual({
      status: 200,
      body: { accepted: true }
    });
  });

  it("with a clock, the future-dated seat is refused and an honest one is then accepted", async () => {
    const handler = handlerOver(await emptyFactory(), () => T0);
    const first = await json(
      await handler(request("/capacity", "POST", { ...encodeReading(reading({ seq: 1 })), seats: poisoned() }))
    );
    expect(first.body.seats.results).toEqual([{ seat: "cc", outcome: "future" }]);
    const honest = await json(
      await handler(
        request("/capacity", "POST", { ...encodeReading(reading({ seq: 2 })), seats: snapshot([claudeSeat()], T0) })
      )
    );
    expect(honest.body.seats.results).toEqual([{ seat: "cc", outcome: "accepted" }]);
  });

  it("Factory.observeCapacity refuses seats without asOf, and takes them with one", async () => {
    const factory = await emptyFactory();
    const withSeats = { ...reading({ seq: 1 }), seats: poisoned() };
    const failure = await Effect.runPromise(Effect.flip(factory.observeCapacity(withSeats)));
    expect(failure).toMatchObject({ _tag: "FactoryError", reason: "NoClock", operation: "Factory.observeCapacity" });
    expect((await run(factory.stateView)).seat_readings).toEqual([]);
    expect(await run(factory.observeCapacity({ ...reading({ seq: 1 }), seats: snapshot([claudeSeat()], T0) }, T0))).toBe(
      true
    );
  });

  it("the bench loads authored seats only against an explicit clock", async () => {
    const prices = Schema.decodeUnknownSync(PriceVector)({ hash: "7".repeat(64), rows: [], drum: 1, stage: [] });
    const load = async (clock: string | undefined) => {
      const factory = await emptyFactory();
      return Effect.runPromise(
        Effect.flip(
          loadFactoryInputs(clock).pipe(
            Effect.provideService(Factory, Factory.of(factory)),
            Effect.provide(fakeCapacityLayer([reading({})], [poisoned()])),
            Effect.provide(constantPriceVectorLayer(prices))
          )
        )
      );
    };
    expect(await load(undefined)).toMatchObject({ reason: "NoClock" });
  });
});

describe("an undecodable capacity/seats key is contained to the capacity routes", () => {
  const brokenFactory = async () => {
    const store = await run(makeInMemoryPlanningStore);
    // What a future seat-capacity/3 row, or any schema tightening, looks like here.
    await run(
      store.put(StorageKey("capacity/seats"), [
        { seat: { seat: "cc", provider: "gemini" }, host: "coordinator" }
      ])
    );
    return run(
      makeFactory(releaseState([], { plans: [] })).pipe(Effect.provideService(PlanningStore, store))
    );
  };

  it("a plain kernel reading is accepted, GET /state answers with a marker, and rearm resolves", async () => {
    const factory = await brokenFactory();
    const handler = handlerOver(factory, () => T0);
    expect(await json(await handler(request("/capacity", "POST", encodeReading(reading({})))))).toEqual({
      status: 200,
      body: { accepted: true }
    });
    const state = await json(await handler(request("/state", "GET")));
    expect(state.status).toBe(200);
    expect(state.body.seat_readings).toEqual([]);
    expect(state.body.seat_readings_error).toMatch(/capacity\/seats/);
    expect(Option.isOption(await run(factory.rearm(T0)))).toBe(true);
    const storage = fakeStorage(null);
    expect(
      await reconcileRuntimeAlarm({ storage, factory, nowMs: Date.parse(T0), path: "request" })
    ).not.toMatchObject({ action: "failed" });
  });

  it("the capacity reads say PersistenceFailed rather than answering from nothing", async () => {
    const handler = handlerOver(await brokenFactory(), () => T0);
    expect((await json(await handler(request("/capacity", "GET")))).body).toMatchObject({
      error: "PersistenceFailed"
    });
    expect((await json(await handler(request("/capacity/admit?seat=cc", "GET")))).body).toMatchObject({
      error: "PersistenceFailed"
    });
  });

  it("the next accepted push replaces the unreadable value, and says so", async () => {
    const factory = await brokenFactory();
    const handler = handlerOver(factory, () => T0);
    const pushed = await json(await handler(request("/capacity/seats", "POST", snapshot([claudeSeat()], T0))));
    expect(pushed).toMatchObject({
      status: 200,
      body: { results: [{ seat: "cc", outcome: "accepted" }], changed: true, discarded_unreadable: true }
    });
    const state = await run(factory.stateView);
    expect(state.seat_readings.map((entry) => entry.seat.seat)).toEqual(["cc"]);
    expect(state.seat_readings_error).toBeNull();
    expect((await json(await handler(request("/capacity/admit?seat=cc", "GET")))).body).toMatchObject({ admit: true });
  });
});
