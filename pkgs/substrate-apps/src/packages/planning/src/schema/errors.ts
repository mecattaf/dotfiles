/**
 * Tagged errors for the planning engine.
 *
 * Errors are product interfaces: each says what failed, gives the most specific
 * safe reason known, and carries diagnostic context as typed fields rather than
 * in prose. Every reason is a stable literal so a caller can branch on it and a
 * new failure mode produces a type error until its translation is chosen.
 */
import { Schema } from "effect";

/** The Factory object could not satisfy a request against its own state. */
export class FactoryError extends Schema.TaggedError<FactoryError>()("FactoryError", {
  /** What went wrong, classified. */
  reason: Schema.Literals([
    "PlanHashMismatch",
    "PlanNotArmed",
    "UnknownTask",
    "DedupMismatch",
    "InvalidTransition",
    "ContinuityGap",
    "ReceiptInvalid",
    "ReceiptMismatch",
    "UnknownLevel",
    "UnknownNamespace",
    "StoredStateInvalid",
    "PersistenceFailed",
    "NoClock"
  ]),
  /** The operation that failed. */
  operation: Schema.String,
  /** A safe domain identifier: a plan id, a level name, a namespace. */
  subject: Schema.String
}) {}

/**
 * The link to one kernel failed, or the kernel refused.
 *
 * A refusal is not this error: `NotYet` and `Rejected` are ordinary outcomes on
 * the success channel, because deferring is not a failure of the link.
 */
export class KernelLinkError extends Schema.TaggedError<KernelLinkError>()("KernelLinkError", {
  /**
   * What went wrong, classified.
   *
   * `Unreachable` is the ordinary case, not the exceptional one: the box may be
   * off, the tunnel may be down, a cloud-side executor may not be provisioned
   * yet. It queues the payload and the alarm retries it; nothing is dropped and
   * nothing is invented in its place.
   */
  reason: Schema.Literals([
    "Unreachable",
    "Unauthorised",
    "ProtocolViolation",
    "SendFailed"
  ]),
  /** The executor addressed. */
  executor: Schema.String,
  /**
   * Whether the send may already have reached the kernel.
   *
   * This is the retry partition, and it is the one question the wire cannot
   * answer for itself: a resend after an ambiguous failure can duplicate an
   * admit unless the dedup key covers it.
   */
  mayHaveArrived: Schema.Boolean
}) {}

/**
 * The plan artifact's bytes could not be hashed.
 *
 * Hashing is a capability rather than a function here, because a digest needs a
 * platform primitive and this package imports nothing but `effect`. A failure to
 * hash refuses the arming outright: an artifact whose digest is unknown has no
 * authority at all, and there is nothing weaker to fall back to.
 */
export class ArtifactHashError extends Schema.TaggedError<ArtifactHashError>()(
  "ArtifactHashError",
  {
    /** What went wrong, classified. */
    reason: Schema.Literals(["Unavailable", "Failed"]),
    /** The artifact's label, for the release journal. Never its content. */
    label: Schema.String
  }
) {}

/** The object's own storage failed or returned something that will not decode. */
export class PlanningStoreError extends Schema.TaggedError<PlanningStoreError>()(
  "PlanningStoreError",
  {
    /** What went wrong, classified. */
    reason: Schema.Literals(["ReadFailed", "WriteFailed", "DecodeFailed", "NotFound"]),
    /** The storage key involved. */
    key: Schema.String
  }
) {}
