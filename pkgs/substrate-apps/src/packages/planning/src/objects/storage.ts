/**
 * The storage capability each Durable Object's SQLite Layer implements.
 *
 * The interface is deliberately narrow and untyped at the value boundary: a key
 * and a JSON value going down, an `unknown` coming back up. Persistence is an
 * untrusted external representation even when the process that wrote it was this
 * one, so every read is parsed by the schema-owned parser that owns the record
 * type, and no inner module receives a raw stored value.
 *
 * Two shapes are needed and no more. A keyed store for object state, and an
 * append-only log for the two workflows that must survive a restart, whose
 * replay is a fold over their own recorded steps. The lake analysis is explicit
 * about why this is written by hand: Effect's durable workflow and cluster
 * machinery live under the release candidate's `unstable` path, and the
 * Cloudflare-native cluster backend is an unmerged branch published to npm under
 * no tag. Nothing in this package imports from `unstable`.
 *
 * The production Layer is the Durable Object SQLite binding and lives in the
 * host package, because a binding is a composition-root concern. The in-memory
 * Layer here is behaviourally faithful and is what the tests and the hermetic
 * bench run against.
 */
import { Brand, Context, Effect, Layer, Option, Ref, Schema } from "effect";
import { PlanningStoreError } from "../schema/errors.ts";

/**
 * A storage key, namespaced by object and record type.
 *
 * Branded nominally rather than through a schema because a key never crosses the
 * wire: it is constructed here and consumed here, and the brand exists only to
 * stop a task id being passed where a key belongs.
 */
export type StorageKey = string & Brand.Brand<"StorageKey">;
/** Constructs a storage key. */
export const StorageKey = Brand.nominal<StorageKey>();

/** A name for one append-only log within an object. */
export type LogName = string & Brand.Brand<"LogName">;
/** Constructs a log name. */
export const LogName = Brand.nominal<LogName>();

/** Any value that can be written to storage. */
export type JsonValue = typeof Schema.Json.Type;

/**
 * The persistence capability.
 *
 * Reads return `unknown` because storage is a boundary; that is the one place
 * the coding standard sanctions it, and the value must be parsed by its owning
 * schema before any inner module sees it.
 */
export interface IPlanningStore {
  /** Reads one record. `None` is absence and never a failure. */
  readonly get: (key: StorageKey) => Effect.Effect<Option.Option<unknown>, PlanningStoreError>;
  /** Writes one record, replacing any previous value. */
  readonly put: (key: StorageKey, value: JsonValue) => Effect.Effect<void, PlanningStoreError>;
  /** Removes one record. Removing an absent record succeeds. */
  readonly remove: (key: StorageKey) => Effect.Effect<void, PlanningStoreError>;
  /** Lists the keys under a prefix, in lexicographic order. */
  readonly list: (
    prefix: string
  ) => Effect.Effect<ReadonlyArray<StorageKey>, PlanningStoreError>;
  /**
   * Appends one step to a log and returns its position.
   *
   * Positions are monotone and dense within a log, which is what lets a workflow
   * replay be a fold rather than a reconciliation.
   */
  readonly append: (log: LogName, value: JsonValue) => Effect.Effect<number, PlanningStoreError>;
  /** Reads a log from a position, for workflow replay. */
  readonly since: (
    log: LogName,
    from: number
  ) => Effect.Effect<ReadonlyArray<unknown>, PlanningStoreError>;
}

/** Provides the planning engine's persistence capability. */
export class PlanningStore extends Context.Service<PlanningStore, IPlanningStore>()(
  "@substrate/planning/PlanningStore"
) {}

/**
 * Constructs an in-memory store.
 *
 * Behaviourally faithful rather than a partial mock: it enforces the same
 * absence semantics, the same prefix ordering, and the same dense monotone log
 * positions as a SQLite-backed implementation, so a test that passes here is not
 * passing because the store was lenient.
 */
export const makeInMemoryPlanningStore = Effect.gen(function* () {
  const records = yield* Ref.make(new Map<string, JsonValue>());
  const logs = yield* Ref.make(new Map<string, Array<JsonValue>>());

  return PlanningStore.of({
    get: Effect.fn("PlanningStore.get")(function* (key: StorageKey) {
      const current = yield* Ref.get(records);
      const found = current.get(key);
      return found === undefined ? Option.none<unknown>() : Option.some<unknown>(found);
    }),
    put: Effect.fn("PlanningStore.put")(function* (key: StorageKey, value: JsonValue) {
      yield* Ref.update(records, (current) => new Map(current).set(key, value));
    }),
    remove: Effect.fn("PlanningStore.remove")(function* (key: StorageKey) {
      yield* Ref.update(records, (current) => {
        const next = new Map(current);
        next.delete(key);
        return next;
      });
    }),
    list: Effect.fn("PlanningStore.list")(function* (prefix: string) {
      const current = yield* Ref.get(records);
      const keys: Array<StorageKey> = [];
      for (const key of current.keys()) {
        if (key.startsWith(prefix)) keys.push(StorageKey(key));
      }
      return keys.sort();
    }),
    append: Effect.fn("PlanningStore.append")(function* (log: LogName, value: JsonValue) {
      const updated = yield* Ref.updateAndGet(logs, (current) => {
        const next = new Map(current);
        const entries = [...(next.get(log) ?? [])];
        entries.push(value);
        next.set(log, entries);
        return next;
      });
      return (updated.get(log)?.length ?? 1) - 1;
    }),
    since: Effect.fn("PlanningStore.since")(function* (log: LogName, from: number) {
      const current = yield* Ref.get(logs);
      const entries = current.get(log) ?? [];
      return entries.slice(Math.max(0, from));
    })
  });
});

/** Provides the store without selecting a persistence implementation. */
const planningStoreLayerWithoutDependencies: Layer.Layer<PlanningStore> = Layer.effect(
  PlanningStore,
  makeInMemoryPlanningStore
);

/**
 * Provides the in-memory store.
 *
 * This is the ready Layer for tests and for the hermetic bench. The Cloudflare
 * production Layer wraps a Durable Object's SQLite storage and lives in the host
 * package, because a binding belongs in a composition root and not in a library.
 */
export const planningStoreInMemoryLayer: Layer.Layer<PlanningStore> =
  planningStoreLayerWithoutDependencies;
