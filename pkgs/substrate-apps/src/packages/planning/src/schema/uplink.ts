/**
 * What an executor posts up, and nothing else reaches the lake.
 *
 * The Worker calls the box; the box posts back. Down go admits, cancels, steers
 * and capacity requests, as calls the Kernel object makes against the executor's
 * endpoint through its tunnel, each carrying the shared secret. Up come exactly
 * four kinds of message, posted to the Worker with the same secret: a witness
 * record, a heartbeat, a doubt, and a capacity reading.
 *
 * That list is closed on purpose, and it is where ruling 3 lives. This package
 * never speaks to herdr. tally wraps herdr completely, the kernel holds the only
 * herdr client and consumes its events plane alone, stamping what it sees with
 * tally's clock — and so every herdr-shaped observation reaches the lake as one
 * of these four. Blocked-on-human is a `Doubt`. Station occupancy is a field on
 * a `CapacityReading`. There is no fifth message, no herdr namespace on this
 * side, and no path by which an observation becomes proof: only a `Verdict`
 * carries proof, and only because the box's ledger minted it first.
 *
 * Nothing here is a command. An up-message can wake an object and change what
 * the release rule sees; it can never release, retry or judge.
 */
import { Schema } from "effect";
import { CapacityReading } from "./capacity.ts";
import { ExecutorId, Seq, TaskId } from "./ids.ts";
import { Verdict } from "./records.ts";

/**
 * Liveness from one lane, and never progress.
 *
 * The per-lane heartbeat says a lane is still there. It says nothing about how
 * far along it is, because inferring progress from liveness is how a plant
 * starts believing its own dashboard. A missing heartbeat is not a verdict
 * either: only the ledger closes a job.
 */
export const Heartbeat = Schema.Struct({
  /** Discriminant. */
  _tag: Schema.tag("Heartbeat"),
  /** The executor that sent it. */
  executor: ExecutorId,
  /** The lane's job, when the heartbeat is a lane's rather than the daemon's. */
  taskId: Schema.OptionFromNullOr(TaskId),
  /** The executor's own monotone sequence, so a replayed post is idempotent. */
  seq: Seq
});
/** Liveness from one lane, and never progress. */
export type Heartbeat = typeof Heartbeat.Type;

/**
 * A lane blocked on a human.
 *
 * herdr's `blocked` is the whole inbox. The three doubt classes tally used to
 * maintain collapse into that one state, and the reason is the text in the pane
 * and the transcript rather than a class this package invents — so there is no
 * classification field here and adding one would be re-inventing what ruling 5
 * removed.
 *
 * The interval is stamped by the kernel on receipt, because herdr's wire has no
 * clock, and it is the one number nothing else on the estate can produce: it
 * measures the drum.
 */
export const Doubt = Schema.Struct({
  /** Discriminant. */
  _tag: Schema.tag("Doubt"),
  /** The executor that observed it. */
  executor: ExecutorId,
  /** The job whose lane is blocked. */
  taskId: TaskId,
  /** The executor's own monotone sequence. */
  seq: Seq,
  /**
   * How long the lane has been blocked, as the kernel stamped it.
   *
   * A measured interval arriving as data. Nothing in this package reads a clock
   * to produce or check it.
   */
  blockedSeconds: Schema.Finite
});
/** A lane blocked on a human, as herdr's single `blocked` state reports it. */
export type Doubt = typeof Doubt.Type;

/**
 * One message posted up by an executor.
 *
 * A closed union, decoded at the boundary. An unknown discriminant is a decode
 * failure and not a silently ignored frame, because a message the lake cannot
 * read is a gap it must know about rather than one it can assume away.
 */
export const UpMessage = Schema.Union([
  Verdict,
  Heartbeat,
  Doubt,
  Schema.Struct({
    /** Discriminant. */
    _tag: Schema.tag("CapacityReading"),
    /** The reading itself. */
    reading: CapacityReading
  })
]);
/** One message posted up by an executor. */
export type UpMessage = typeof UpMessage.Type;
