/**
 * The capacity ledger: the latest reading per seat, kept in the object's own
 * store, and the questions the factory asks of it.
 *
 * This is the real capacity Layer. It persists through `PlanningStore`, so in
 * the Worker it is the Durable Object's SQLite storage and in tests it is the
 * in-memory store; nothing in this file selects either.
 *
 * INGESTION IS MONOTONIC AND IDEMPOTENT (`ingestSnapshot`, pure):
 *
 * - a seat reading older than the one held (by `observed_at`, compared as an
 *   instant) is refused as `older`;
 * - the same reading again is a `duplicate` and changes nothing, not even the
 *   receipt time, so a retried push is harmless;
 * - the same `observed_at` with different content (the publisher changed a
 *   local annotation such as `dispatchable`) is accepted only from a later
 *   `published_at`;
 * - a reading dated more than the skew tolerance ahead of the receiving clock
 *   is refused as `future`, because accepting it would make every honest
 *   reading after it look older until that moment passed;
 * - a snapshot whose `published_at` is that far ahead is refused whole, every
 *   seat `future`, for the same reason: `published_at` orders changes on the
 *   same `observed_at` (an eviction, an auth failure), and one skewed publish
 *   would otherwise lock every later annotation out.
 *
 * A HELD VALUE THAT NO LONGER DECODES never bricks the object. Reads of it
 * (`latest`, `at`, `admit`) fail `DecodeFailed`, which the Factory contains to
 * the capacity routes; the next push that is accepted replaces it
 * (`discarded_unreadable`), so a schema bump heals on the next push instead of
 * needing the object reset.
 */
import { Context, Effect, Layer, Option, Schema } from "effect";
import { PlanningStoreError } from "../schema/errors.ts";
import {
  Instant,
  SeatCapacity as SeatCapacitySchema,
  type SeatCapacity,
  type SeatCapacitySnapshot,
  type SeatJob
} from "../schema/seatCapacity.ts";
import {
  admitSeat,
  CLOCK_SKEW_TOLERANCE_S,
  nextTransitionAt,
  projectSeat,
  type AdmissionDecision,
  type SeatProjection
} from "./project.ts";
import {
  PlanningStore,
  planningStoreInMemoryLayer,
  StorageKey,
  type JsonValue
} from "../objects/storage.ts";

/** The key the ledger keeps its seats under. */
const CAPACITY_SEATS_KEY = StorageKey("capacity/seats");

/** One seat reading as held, with where and when it came from. */
export const StoredSeat = Schema.Struct({
  seat: SeatCapacitySchema,
  host: Schema.String,
  published_at: Instant,
  received_at: Instant
});
/** One seat reading as held. */
export type StoredSeat = typeof StoredSeat.Type;

const StoredSeats = Schema.Array(StoredSeat);
const decodeStoredSeats = Schema.decodeUnknownEffect(StoredSeats);
const encodeStoredSeats = Schema.encodeEffect(StoredSeats);

/** What happened to one seat of a pushed snapshot. */
type IngestOutcome = "accepted" | "duplicate" | "older" | "future";

/** The per-seat answer to a push. */
interface IngestResult {
  readonly seat: string;
  readonly outcome: IngestOutcome;
}

/** The whole answer to a push. */
export interface IngestReport {
  readonly results: ReadonlyArray<IngestResult>;
  readonly changed: boolean;
  /**
   * Present (true) when the held value could not be decoded (a schema bump, or
   * drift) and this push replaced it. The old readings are gone; the
   * monotonic check had nothing to compare this push against.
   */
  readonly discarded_unreadable?: true;
}

/** Key-sorted JSON, so equality does not depend on field order. */
const canonical = (value: unknown): string =>
  JSON.stringify(value, (_key, entry: unknown) =>
    entry !== null && typeof entry === "object" && !Array.isArray(entry)
      ? Object.fromEntries(
          Object.entries(entry as Record<string, unknown>).sort(([left], [right]) =>
            left < right ? -1 : left > right ? 1 : 0
          )
        )
      : entry
  );

/**
 * Folds one snapshot into the held seats. Pure.
 *
 * @param receivedAt the receiving clock, used only to refuse readings dated in
 *   the future and to stamp what was accepted.
 */
export const ingestSnapshot = (
  held: ReadonlyMap<string, StoredSeat>,
  snapshot: SeatCapacitySnapshot,
  receivedAt: string
): { readonly next: ReadonlyMap<string, StoredSeat>; readonly report: IngestReport } => {
  const received = Date.parse(receivedAt);
  if (!Number.isFinite(received)) throw new RangeError(`receivedAt is not an instant: ${receivedAt}`);
  const next = new Map(held);
  const horizon = received + CLOCK_SKEW_TOLERANCE_S * 1000;
  if (!(Date.parse(snapshot.published_at) <= horizon)) {
    return {
      next,
      report: {
        results: snapshot.seats.map((seat) => ({ seat: seat.seat, outcome: "future" as const })),
        changed: false
      }
    };
  }
  const results: Array<IngestResult> = [];
  let changed = false;
  for (const seat of snapshot.seats) {
    const observed = Date.parse(seat.observed_at);
    if (observed > horizon) {
      results.push({ seat: seat.seat, outcome: "future" });
      continue;
    }
    const current = next.get(seat.seat);
    if (current !== undefined) {
      const heldObserved = Date.parse(current.seat.observed_at);
      if (observed < heldObserved) {
        results.push({ seat: seat.seat, outcome: "older" });
        continue;
      }
      if (observed === heldObserved) {
        if (canonical(current.seat) === canonical(seat)) {
          results.push({ seat: seat.seat, outcome: "duplicate" });
          continue;
        }
        if (Date.parse(snapshot.published_at) <= Date.parse(current.published_at)) {
          results.push({ seat: seat.seat, outcome: "older" });
          continue;
        }
      }
    }
    next.set(seat.seat, {
      seat,
      host: snapshot.host,
      published_at: snapshot.published_at,
      received_at: new Date(received).toISOString()
    });
    results.push({ seat: seat.seat, outcome: "accepted" });
    changed = true;
  }
  return { next, report: { results, changed } };
};

/** Everything the lake can say about capacity at one moment. */
export interface CapacityView {
  readonly as_of: string;
  readonly seats: ReadonlyArray<SeatProjection & { readonly host: string; readonly received_at: string }>;
  /** When the answer next changes without a new reading; the object's alarm. */
  readonly next_transition_at: string | null;
}

/** The ledger's capability. */
interface ICapacityLedger {
  /** Folds a pushed snapshot in; persists only when something was accepted. */
  readonly ingest: (
    snapshot: SeatCapacitySnapshot,
    receivedAt: string
  ) => Effect.Effect<IngestReport, PlanningStoreError>;
  /** The held readings, by seat id order. */
  readonly latest: Effect.Effect<ReadonlyArray<StoredSeat>, PlanningStoreError>;
  /** Every seat projected to `asOf`. */
  readonly at: (asOf: string) => Effect.Effect<CapacityView, PlanningStoreError>;
  /** Can `seat` take a job of class `job` at `asOf`, and until when. */
  readonly admit: (
    seat: string,
    job: SeatJob,
    asOf: string
  ) => Effect.Effect<AdmissionDecision, PlanningStoreError>;
  /** The earliest projection change strictly after `asOf`. */
  readonly nextTransitionAt: (
    asOf: string
  ) => Effect.Effect<Option.Option<string>, PlanningStoreError>;
}

/** Provides the capacity ledger. */
export class CapacityLedger extends Context.Service<CapacityLedger, ICapacityLedger>()(
  "@substrate/planning/CapacityLedger"
) {}

/** Builds the ledger over whichever `PlanningStore` is provided. */
export const makeCapacityLedger = Effect.gen(function* () {
  const store = yield* PlanningStore;

  const load = Effect.gen(function* () {
    const stored = yield* store.get(CAPACITY_SEATS_KEY);
    if (Option.isNone(stored)) return new Map<string, StoredSeat>();
    const seats = yield* decodeStoredSeats(stored.value).pipe(
      Effect.mapError(
        () => new PlanningStoreError({ reason: "DecodeFailed", key: CAPACITY_SEATS_KEY })
      )
    );
    return new Map(seats.map((entry) => [entry.seat.seat, entry] as const));
  });

  const ordered = (held: ReadonlyMap<string, StoredSeat>): ReadonlyArray<StoredSeat> =>
    [...held.values()].sort((left, right) => (left.seat.seat < right.seat.seat ? -1 : 1));

  return CapacityLedger.of({
    ingest: Effect.fn("CapacityLedger.ingest")(function* (
      snapshot: SeatCapacitySnapshot,
      receivedAt: string
    ) {
      const loaded = yield* load.pipe(
        Effect.map((held) => ({ held, discarded: false })),
        Effect.catchIf(
          (error) => error.reason === "DecodeFailed",
          () => Effect.succeed({ held: new Map<string, StoredSeat>(), discarded: true })
        )
      );
      const ingested = ingestSnapshot(loaded.held, snapshot, receivedAt);
      const { next } = ingested;
      const report: IngestReport =
        loaded.discarded && ingested.report.changed
          ? { ...ingested.report, discarded_unreadable: true }
          : ingested.report;
      if (report.changed) {
        const encoded = yield* encodeStoredSeats(ordered(next)).pipe(
          Effect.mapError(
            () => new PlanningStoreError({ reason: "WriteFailed", key: CAPACITY_SEATS_KEY })
          )
        );
        yield* store.put(CAPACITY_SEATS_KEY, encoded as JsonValue);
      }
      return report;
    }),
    latest: Effect.map(load, ordered),
    at: Effect.fn("CapacityLedger.at")(function* (asOf: string) {
      const held = ordered(yield* load);
      const transition = nextTransitionAt(
        held.map((entry) => entry.seat),
        asOf
      );
      return {
        as_of: asOf,
        seats: held.map((entry) => ({
          ...projectSeat(entry.seat, asOf),
          host: entry.host,
          received_at: entry.received_at
        })),
        next_transition_at: Option.getOrNull(transition)
      } satisfies CapacityView;
    }),
    admit: Effect.fn("CapacityLedger.admit")(function* (
      seat: string,
      job: SeatJob,
      asOf: string
    ) {
      const held = yield* load;
      return admitSeat(seat, held.get(seat)?.seat, job, asOf);
    }),
    nextTransitionAt: Effect.fn("CapacityLedger.nextTransitionAt")(function* (asOf: string) {
      const held = ordered(yield* load);
      return nextTransitionAt(
        held.map((entry) => entry.seat),
        asOf
      );
    })
  });
});

/** The ledger over the provided store: Durable Object SQLite in the Worker. */
export const capacityLedgerLayer: Layer.Layer<CapacityLedger, never, PlanningStore> =
  Layer.effect(CapacityLedger, makeCapacityLedger);

/** The ledger over a fresh in-memory store, for tests and the hermetic bench. */
export const capacityLedgerInMemoryLayer: Layer.Layer<CapacityLedger> = capacityLedgerLayer.pipe(
  Layer.provide(planningStoreInMemoryLayer)
);

/** Re-exported so callers need one import for the admission vocabulary. */
export type { SeatCapacity };
