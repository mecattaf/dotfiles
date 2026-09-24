/**
 * Capacity rows: the constraint table the LP of Volume I chapter 6 writes down
 * as R1 to R4, and the thing every admission decision evaluates against.
 *
 * A row is one physical contended thing with its own dual price. A pool is a
 * row and `pool_allows` is the row evaluator. Nothing in this table is a mutex:
 * the two serialization mutexes that existed only because every enqueue must
 * name a pool set are ordering the lake now does.
 */
import { Schema } from "effect";
import { RowName } from "./ids.ts";

/**
 * What kind of capacity a row meters.
 *
 * `vram` and `build-slot` and `slot` are renewable positions; `budget` is the
 * nonrenewable, partially renewable envelope of Boettcher and Drexl. The
 * distinction is load-bearing: positions constraints and budget constraints are
 * different rows with different duals, and the mutex incident conflated them.
 */
const RowKind = Schema.Literals([
  "vram",
  "build-slot",
  "cpu-slot",
  "slot",
  "budget"
]);
/** What kind of capacity a row meters. */
type RowKind = typeof RowKind.Type;

/** One declared capacity row. */
const Row = Schema.Struct({
  /** The row's name, as the kernel's pool table declares it. */
  name: RowName,
  /** Which kind of capacity this row meters. */
  kind: RowKind,
  /** Holder capacity. GPU rows stay at one per device until jobs carry a VRAM request. */
  capacity: Schema.Int,
  /**
   * Whether the row is metered against a reset horizon.
   *
   * Metered rows carry the pace line and the duals `lambda` and `mu`; durable
   * rows carry `gamma`, usually near zero, which is the formal statement of
   * "saturate the small lanes".
   */
  metered: Schema.Boolean
});
/** One declared capacity row. */
type Row = typeof Row.Type;

/** The declared row table. */
export const Rows = Schema.Array(Row);
/** The declared row table. */
export type Rows = typeof Rows.Type;

/**
 * A job's consumption of one row.
 *
 * This is `a_jr` in the value-density denominator. For a position row it is a
 * count of holders; for a budget row it is expected weight at the p80
 * protection level.
 */
const RowRequest = Schema.Struct({
  /** The row consumed. */
  row: RowName,
  /** Holders taken on a position row; one unless the member says otherwise. */
  holders: Schema.Int,
  /**
   * Expected consumption on a budget row, at the p80 protection level.
   *
   * Unbranded because the engine derives it from an estimate rather than
   * receiving it across a boundary; branding a derived number would fabricate
   * provenance the value does not have.
   */
  consumption: Schema.Finite
});
/** A job's consumption of one row. */
type RowRequest = typeof RowRequest.Type;

/**
 * A row set requested on one enqueue.
 *
 * Admission of a set is atomic: the kernel grants all of it or queues the job,
 * with no partial hold-and-wait state. A two-GPU item names both device rows
 * here, which is the whole reason one kernel must own both.
 */
export const RowSet = Schema.Array(RowRequest);
/** A row set requested on one enqueue, granted all-or-nothing. */
export type RowSet = typeof RowSet.Type;
