/**
 * Seat capacity through the host-neutral surface: the ingestion routes, the
 * projection and admission reads, the capacity feed Layers, and the Worker's
 * alarm clamp.
 */
import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  Factory,
  FactoryCapacityFeed,
  fakeCapacityLayer,
  loadFactoryInputs,
  makeFactory,
  makeFactoryHttpHandler,
  makeInMemoryPlanningStore,
  makeTableArtifactHasher,
  PlanningStore,
  storedCapacityLayer,
  constantPriceVectorLayer
} from "../src/index.ts";
import { alarmToSet, ALARM_FLOOR_MS } from "../../../apps/floor/src/alarm.ts";
import { CapacityReading } from "@substrate/planning/schema/capacity.ts";
import { PriceVector } from "@substrate/planning/schema/prices.ts";
import {
  CC_OBSERVED,
  cc3Seat,
  claudeSeat,
  halogenSeat,
  plus,
  qwenSeat,
  snapshot
} from "../../planning/test/seatCapacityFixtures.ts";
import { artifactBytes, artifactDigest, emptyFactory, reading, releaseState, run } from "./fixtures.ts";

const encodeReading = Schema.encodeSync(CapacityReading);
const T0 = plus(CC_OBSERVED, 60);
/** Today's fleet, as the pusher would publish it. */
const today = () => snapshot([claudeSeat(), cc3Seat(), qwenSeat(), halogenSeat(0)]);

const request = (path: string, method: "GET" | "POST", body?: unknown, authenticated = true) =>
  new Request(`https://factory.invalid${path}`, {
    method,
    headers: {
      ...(authenticated ? { authorization: "Bearer test-token" } : {}),
      ...(body === undefined ? {} : { "content-type": "application/json" })
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });

const handlerAt = async (clock: { now: string } | undefined) => {
  const factory = await emptyFactory();
  const handler = makeFactoryHttpHandler({
    factory,
    token: "test-token",
    artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]]),
    ...(clock === undefined ? {} : { now: () => clock.now })
  });
  return { factory, handler };
};

const json = async (response: Response) => ({ status: response.status, body: await response.json() });

describe("POST /capacity/seats", () => {
  it("requires the bearer", async () => {
    const { handler } = await handlerAt({ now: T0 });
    expect((await handler(request("/capacity/seats", "POST", today(), false))).status).toBe(401);
  });

  it("refuses without a host clock rather than accepting against none", async () => {
    const { handler } = await handlerAt(undefined);
    expect(await json(await handler(request("/capacity/seats", "POST", today())))).toEqual({
      status: 501,
      body: { error: "NoClock", subject: "/capacity/seats" }
    });
  });

  it("validates the snapshot against the schema", async () => {
    const { handler } = await handlerAt({ now: T0 });
    const broken = { ...today(), seats: [{ ...claudeSeat(), observed_at: "2026-09-23 04:52" }] };
    expect((await handler(request("/capacity/seats", "POST", broken))).status).toBe(400);
    const badVersion = { ...today(), schema_version: "seat-capacity/1" };
    expect((await handler(request("/capacity/seats", "POST", badVersion))).status).toBe(400);
  });

  it("is idempotent, monotonic, and refuses a reading dated in the future", async () => {
    const clock = { now: T0 };
    const { handler } = await handlerAt(clock);
    const first = await json(await handler(request("/capacity/seats", "POST", today())));
    expect(first.status).toBe(200);
    expect(first.body.changed).toBe(true);
    const again = await json(await handler(request("/capacity/seats", "POST", { snapshot: today() })));
    expect(again.body).toEqual({
      results: ["cc", "cc3", "pi-qwencloud", "gpu-worker"].map((seat) => ({ seat, outcome: "duplicate" })),
      changed: false
    });
    const older = snapshot([claudeSeat({ observed_at: plus(CC_OBSERVED, -300) })], plus(T0, 10));
    expect((await json(await handler(request("/capacity/seats", "POST", older)))).body.results).toEqual([
      { seat: "cc", outcome: "older" }
    ]);
    const future = snapshot([claudeSeat({ observed_at: plus(T0, 900) })], plus(T0, 900));
    expect((await json(await handler(request("/capacity/seats", "POST", future)))).body.results).toEqual([
      { seat: "cc", outcome: "future" }
    ]);
  });
});

describe("POST /capacity with seats attached", () => {
  it("keeps today's uplink body working and folds attached seats in", async () => {
    const { handler, factory } = await handlerAt({ now: T0 });
    const plain = await json(await handler(request("/capacity", "POST", encodeReading(reading({})))));
    expect(plain.body).toEqual({ accepted: true });
    const withSeats = { ...encodeReading(reading({})), seats: today() };
    const attached = await json(await handler(request("/capacity", "POST", withSeats)));
    expect(attached.body.accepted).toBe(false);
    expect(attached.body.seats.changed).toBe(true);
    const state = await run(factory.stateView);
    expect(state.seat_readings).toHaveLength(4);
    expect(state.latest_readings.coordinator).not.toHaveProperty("seats");
  });

  it("never sets alarm_at at or before the host clock", async () => {
    const { handler, factory } = await handlerAt({ now: T0 });
    const past = encodeReading(reading({ nextWindowAt: "2026-09-12T11:00:00Z" }));
    await handler(request("/capacity", "POST", past));
    expect((await run(factory.stateView)).alarm_at).toBeNull();
  });
});

describe("GET /capacity and GET /capacity/admit", () => {
  const loaded = async () => {
    const clock = { now: T0 };
    const context = await handlerAt(clock);
    await context.handler(request("/capacity/seats", "POST", today()));
    return { ...context, clock };
  };

  it("projects every seat at the given asOf, defaulting to the host clock", async () => {
    const { handler, clock } = await loaded();
    const now = await json(await handler(request("/capacity", "GET")));
    expect(now.body.as_of).toBe(T0);
    expect(now.body.next_transition_at).toBe(plus(CC_OBSERVED, 1200));
    const headroom = Object.fromEntries(
      now.body.seats.map((seat: { reading: { seat: string }; headroom_pct: number | null }) => [
        seat.reading.seat,
        seat.headroom_pct
      ])
    );
    expect(headroom).toEqual({ cc: 28, cc3: 100, "gpu-worker": null, "pi-qwencloud": null });
    clock.now = plus(T0, 3600);
    const later = await json(await handler(request(`/capacity?asOf=${encodeURIComponent(T0)}`, "GET")));
    expect(later.body.as_of).toBe(T0);
  });

  it("answers the admission question per job class", async () => {
    const { handler } = await loaded();
    const ask = async (query: string) => (await json(await handler(request(`/capacity/admit?${query}`, "GET")))).body;
    expect(await ask("seat=cc&model=Opus")).toMatchObject({ admit: true, headroom_pct: 28 });
    expect(await ask("seat=cc&model=Fable")).toMatchObject({ admit: false, reason: "severity-critical" });
    expect(await ask("seat=cc&model=Opus&min_headroom_pct=30")).toMatchObject({
      admit: false,
      reason: "window-exhausted"
    });
    expect(await ask("seat=cc3&model=Opus")).toMatchObject({ admit: false, reason: "not-dispatchable" });
    expect(await ask("seat=nobody")).toMatchObject({ admit: false, reason: "unknown-seat" });
    expect(await ask(`seat=cc&model=Opus&asOf=${encodeURIComponent(plus(CC_OBSERVED, 2000))}`)).toMatchObject({
      admit: false,
      reason: "stale"
    });
  });

  it("refuses a malformed asOf, a missing seat and a malformed headroom", async () => {
    const { handler } = await loaded();
    expect((await handler(request("/capacity?asOf=tomorrow", "GET"))).status).toBe(400);
    expect((await handler(request("/capacity/admit", "GET"))).status).toBe(400);
    expect((await handler(request("/capacity/admit?seat=cc&min_headroom_pct=lots", "GET"))).status).toBe(400);
  });

  it("without a host clock, GET /capacity requires asOf", async () => {
    const { handler } = await handlerAt(undefined);
    expect((await handler(request("/capacity", "GET"))).status).toBe(400);
    expect((await handler(request(`/capacity?asOf=${encodeURIComponent(T0)}`, "GET"))).status).toBe(200);
  });
});

describe("the capacity feed Layers", () => {
  const prices = Schema.decodeUnknownSync(PriceVector)({
    hash: "7".repeat(64),
    rows: [],
    drum: 1,
    stage: []
  });

  it("the fake Layer carries seats built from today's shapes into the Factory", async () => {
    const factory = await emptyFactory();
    const state = await Effect.runPromise(
      loadFactoryInputs(T0).pipe(
        Effect.provideService(Factory, Factory.of(factory)),
        Effect.provide(fakeCapacityLayer([reading({})], [today()])),
        Effect.provide(constantPriceVectorLayer(prices))
      )
    );
    expect(state.seat_readings.map((entry) => entry.seat.seat)).toEqual([
      "cc",
      "cc3",
      "gpu-worker",
      "pi-qwencloud"
    ]);
  });

  it("the stored Layer reads back what the object persisted, from the same store", async () => {
    const store = await run(makeInMemoryPlanningStore);
    const factory = await run(
      makeFactory(releaseState([], { plans: [] })).pipe(Effect.provideService(PlanningStore, store))
    );
    await run(factory.observeSeats(today(), T0));
    await run(factory.observeSeats(snapshot([halogenSeat(1)], plus(T0, 1), "worker"), T0));
    const snapshots = await run(
      Effect.gen(function* () {
        const feed = yield* FactoryCapacityFeed;
        return yield* feed.seats;
      }).pipe(Effect.provide(storedCapacityLayer), Effect.provideService(PlanningStore, store))
    );
    expect(snapshots.map((entry) => [entry.host, entry.seats.map((seat) => seat.seat)])).toEqual([
      ["coordinator", ["cc", "cc3", "pi-qwencloud"]],
      ["worker", ["gpu-worker"]]
    ]);
    // Feeding them back is a no-op: ingestion is idempotent.
    const before = await run(factory.stateView);
    for (const entry of snapshots) {
      expect((await run(factory.observeSeats(entry, T0))).changed).toBe(false);
    }
    expect(await run(factory.stateView)).toEqual(before);
  });
});

describe("the Worker's alarm clamp", () => {
  it("never hands setAlarm an instant at or before now", () => {
    const now = Date.parse(T0);
    expect(alarmToSet(null, now)).toBeNull();
    expect(alarmToSet(Number.NaN, now)).toBeNull();
    expect(alarmToSet(now + 60_000, now)).toBe(now + 60_000);
    expect(alarmToSet(now, now)).toBe(now + ALARM_FLOOR_MS);
    expect(alarmToSet(Date.parse("2026-09-12T11:00:00Z"), now)).toBe(now + ALARM_FLOOR_MS);
  });
});
