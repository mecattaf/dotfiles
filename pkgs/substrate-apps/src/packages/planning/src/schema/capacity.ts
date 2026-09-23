/**
 * The capacity reading: the single value that carries the world into the
 * release evaluator.
 *
 * Everything the engine knows about a box arrives here — per-row holders, the
 * headroom oracle's signal, its freshness, the resident local models, the
 * envelope's remaining budget and how many windows are left in it. The
 * evaluator reads nothing else, which is what makes it a pure function and what
 * makes a fabricated reading a complete test fixture.
 */
import { Option, Schema } from "effect";
import { ExecutorId, MemberId, RowName, Seq, Weight } from "./ids.ts";
import { SeatCapacitySnapshot } from "./seatCapacity.ts";

/**
 * The headroom oracle's coarsened price schedule.
 *
 * `GO`, `SLOW` and `STOP` are the `{0, infinity}` coarsening of the bid price
 * that Volume I section 7.3 names: free while measured budget remains, infinite
 * when exhausted. Replacing it with real duals is a data swap, not an
 * architecture change.
 */
const OracleSignal = Schema.Literals(["GO", "SLOW", "STOP"]);
/** The headroom oracle's coarsened price schedule. */
type OracleSignal = typeof OracleSignal.Type;

/**
 * Whether the oracle observation behind a reading is current.
 *
 * A stale observation defers and never admits. The cloud-seat blindness that
 * made two usage snapshots byte-identical is exactly the case this exists for.
 */
const OracleFreshness = Schema.Literals(["fresh", "stale"]);
/** Whether the oracle observation behind a reading is current. */
type OracleFreshness = typeof OracleFreshness.Type;

/** The measured state of one capacity row on one executor. */
const RowReading = Schema.Struct({
  /** The row read. */
  row: RowName,
  /** Holders currently granted. */
  holders: Schema.Int,
  /** Declared holder capacity, repeated here so a reading stands alone. */
  capacity: Schema.Int,
  /** The oracle's signal for this row. */
  signal: OracleSignal,
  /** Remaining budget on a metered row; `None` on a position row. */
  remainingBudget: Schema.OptionFromNullOr(Weight),
  /**
   * The next known instant at which this row's window changes.
   *
   * This is supplied by the capacity instrument and kept in its wire spelling
   * so the Worker can mirror it without translating a clock field.  Absence
   * means the row has no known window; the Factory never invents one.
   */
  next_window_at: Schema.optionalKey(Schema.String)
});
/** The measured state of one capacity row on one kernel. */
type RowReading = typeof RowReading.Type;

/**
 * The envelope's slow clock, expressed as counts rather than as a clock.
 *
 * `windowsRemaining` is how the passage of the outer horizon reaches the engine.
 * Nothing here is a timestamp, and nothing derives one.
 */
export const EnvelopeReading = Schema.Struct({
  /** Budget remaining in the outer envelope, `B_out(t)`. */
  outerRemaining: Weight,
  /** Windows remaining in the outer envelope, `N_rem(t)`. */
  windowsRemaining: Schema.Int,
  /** The inner per-window cap, `C_in`. */
  innerCap: Weight,
  /** Total windows in one outer envelope, `N`; used only to compute `r`. */
  windowsPerEnvelope: Schema.Int
});
/** The envelope's slow clock, expressed as window counts. */
export type EnvelopeReading = typeof EnvelopeReading.Type;

/**
 * Whether the plant is attended.
 *
 * The regime is a flag set by the operator or by herdr presence. It is never a
 * clock the queue reads, and this package has no way to read one.
 */
export const Regime = Schema.Literals(["attended", "unattended"]);
/** Whether the plant is attended; a flag, never a clock. */
export type Regime = typeof Regime.Type;

/**
 * What one station on an executor is doing.
 *
 * Station occupancy is herdr-shaped: a pane is idle, working, blocked or
 * unknown. It reaches the lake only as part of a capacity reading the kernel
 * sends up, because this package never speaks to herdr — tally wraps herdr, the
 * kernel consumes its events plane and stamps them with tally's clock, and what
 * crosses to the lake is a kernel up-message like any other. It is an
 * observation and never proof: nothing here promotes a station state to a
 * verdict, and the release rule reads occupancy only as capacity.
 */
const StationReading = Schema.Struct({
  /** The catalog member mounted on this station. */
  member: MemberId,
  /**
   * The station's state, in herdr's four.
   *
   * `blocked` is the whole inbox: the reason is the text in the pane and the
   * transcript, not a class tally maintains.
   */
  state: Schema.Literals(["idle", "working", "blocked", "unknown"])
});
/** What one station on an executor is doing, as the kernel observed it. */
type StationReading = typeof StationReading.Type;

/** One executor's capacity, as the kernel reports it up. */
export const CapacityReading = Schema.Struct({
  /** Which executor this reading describes. */
  executor: ExecutorId,
  /** Monotone sequence number; the engine orders readings by this. */
  seq: Seq,
  /** Per-row measured state. */
  rows: Schema.Array(RowReading),
  /** Whether the observation behind the signals is current. */
  freshness: OracleFreshness,
  /** The envelope's remaining budget and window counts. */
  envelope: EnvelopeReading,
  /**
   * Models currently resident in local VRAM.
   *
   * The lease and residency are unrelated state machines: tally leases dispatch
   * and llama-swap owns residency. Knowing what is warm lets the engine prefer
   * it, and lets it never assume it.
   */
  residentMembers: Schema.Array(MemberId),
  /**
   * Station occupancy, as the kernel observed it on its own live plane.
   *
   * Empty on an executor that runs nothing under a harness, which is an ordinary
   * case and not a degraded reading.
   */
  stations: Schema.Array(StationReading),
  /** Whether the plant is attended, which flips the length term in the sort. */
  regime: Regime,
  /**
   * Per-seat capacity windows (`seat-capacity/2`), when the publisher attaches
   * them.
   *
   * Optional, so today's uplink keeps working unchanged. The Factory folds it
   * into its capacity ledger independently of `seq` (a reading refused as a
   * repeat may still carry a newer seat observation) and never stores it inside
   * the reading itself.
   */
  seats: Schema.optionalKey(SeatCapacitySnapshot)
});
/** One executor's capacity, as the kernel reports it up. */
export type CapacityReading = typeof CapacityReading.Type;

/** Decodes an untrusted capacity reading arriving over the uplink. */
export const parseCapacityReading = Schema.decodeUnknownEffect(CapacityReading);

/**
 * Looks up one row's reading.
 *
 * @returns the reading, or `None` when the executor does not declare that row,
 *   which is a deferral and never an admission. This is the whole mechanism by
 *   which an item needing a Claude seat or a device row simply defers on a
 *   cloud-side executor: no table of exceptions, no special case.
 */
export const rowReading = (
  reading: CapacityReading,
  row: RowName
): Option.Option<RowReading> => {
  for (const candidate of reading.rows) {
    if (candidate.row === row) return Option.some(candidate);
  }
  return Option.none();
};

/** Free holders on a row, floored at zero. */
export const rowHeadroom = (row: RowReading): number =>
  Math.max(0, row.capacity - row.holders);
