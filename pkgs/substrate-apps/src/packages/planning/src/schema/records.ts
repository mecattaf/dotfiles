/**
 * The two record types.
 *
 * They keep two names and neither is ever cast to the other. A merge or a
 * supersession is a control-plane fact, never a verdict. The lake is a mirror
 * and never a ledger: it holds what is safe to copy, verifies hash continuity on
 * arrival, records any gap and never fills one. The box keeps proof; the lake
 * keeps the record that planning reads.
 *
 * There was a third, `ForgeFact`, and it is gone. There is no webhook and no
 * forge admission: an ultracode workflow has zero forge admission, and pushing
 * or merging is an ordinary act an agent performs inside a node, witnessed like
 * any other node. So a merge reaches the lake as a `Verdict` on the node that
 * performed it, and never as a separate class of fact with its own intake.
 *
 * Nothing in `heuristics` or `release` can construct a `Verdict`. The only
 * producer is the boundary decoder here, which is what "no verdict from the
 * object" means mechanically rather than as etiquette.
 */
import { Schema } from "effect";
import { ExecutorId, Seq, Sha256Hex, TaskId } from "./ids.ts";

/** How a witnessed job ended. */
export const VerdictOutcome = Schema.Literals([
  "pass",
  "fail",
  "cancelled",
  "preempted",
  "expired"
]);
/** How a witnessed job ended. */
export type VerdictOutcome = typeof VerdictOutcome.Type;

/**
 * One witness record, mirrored verbatim.
 *
 * The witness ledger on the box is the only proof, and journald is the only
 * clock. This is a copy carrying its sequence and its chaining hash so
 * continuity can be verified here without the lake ever becoming the authority.
 */
export const Verdict = Schema.Struct({
  /** Discriminant; the two record types never share one. */
  _tag: Schema.tag("Verdict"),
  /** The job witnessed. */
  taskId: TaskId,
  /** Which executor witnessed it, and therefore whose chain this belongs to. */
  executor: ExecutorId,
  /** Position in that executor's hash chain. */
  seq: Seq,
  /** This record's hash. */
  hash: Sha256Hex,
  /** The previous record's hash, which is what continuity is verified against. */
  prevHash: Sha256Hex,
  /** How the job ended. */
  outcome: VerdictOutcome,
  /** Measured service interval, from the box's own clock, carried as a duration. */
  serviceSeconds: Schema.Finite,
  /**
   * Receipt-evidence cells carried only by the kernel's evaluator verdict.
   *
   * Ordinary witness records omit them.  When present they remain part of the
   * mirrored record so `POST /receipts` can require an exact match without the
   * lake constructing or recomputing any evidence.
   */
  unit_id: Schema.optionalKey(Schema.String),
  oracle_rc: Schema.optionalKey(Schema.Int),
  mutation_rc: Schema.optionalKey(Schema.Int),
  oracle_output_sha256: Schema.optionalKey(Schema.String)
});
/** One witness record, mirrored verbatim. */
export type Verdict = typeof Verdict.Type;

/**
 * Decodes a witness record arriving over the uplink.
 *
 * This is the only producer of a `Verdict` in the package. A verdict can be
 * mirrored and never minted.
 */
export const parseVerdict = Schema.decodeUnknownEffect(Verdict);

/**
 * Something the lake itself decided.
 *
 * A release, a supersession, an andon, a plan arming. These are the lake's own
 * acts and carry no claim about what happened on the box.
 */
export const ControlPlaneFact = Schema.Struct({
  /** Discriminant. */
  _tag: Schema.tag("ControlPlaneFact"),
  /** What the lake decided. */
  kind: Schema.Literals([
    "armed",
    "released",
    "deferred",
    "rejected",
    "superseded",
    "andon"
  ]),
  /** The item or plan it concerns. */
  subject: Schema.String,
  /** The lake's own monotone sequence. */
  seq: Seq,
  /** A short legible reason, for the object's journal of dispositions. */
  detail: Schema.String
});
/** Something the lake itself decided. */
export type ControlPlaneFact = typeof ControlPlaneFact.Type;

/**
 * A gap in a mirrored hash chain.
 *
 * Recorded and never filled. The discipline is tally's own: fresh snapshot,
 * explicit gap, never pretend continuity.
 */
export const ContinuityGap = Schema.Struct({
  /** Which executor's chain has the gap. Chains are verified one per executor. */
  executor: ExecutorId,
  /** The last sequence seen before the gap. */
  after: Seq,
  /** The first sequence seen after it. */
  before: Seq
});
/** A gap in a mirrored hash chain, recorded and never filled. */
export type ContinuityGap = typeof ContinuityGap.Type;
