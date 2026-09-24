/**
 * The messages the Worker sends down to an executor, and the answers it gets.
 *
 * The Worker calls the box. An admit, a cancel and a steer are calls the Kernel
 * object makes against the executor's endpoint, not items an uplink pulls, so
 * every one of them can fail in transit and every one of them must be safe to
 * repeat. That is what the dedup key is for, and it is why a failed send is
 * queued rather than dropped or re-decided.
 *
 * An admit is still a proposal. The executor's door is the only door, it
 * verifies the brief hash against its armed set before anything runs, and it
 * answers with one of three idempotent outcomes. A wrong or compromised Worker
 * can therefore only ask for work that was armed.
 *
 * An admit never carries brief content and never carries argv. No argv is
 * computed at release; that is what keeps a plan data rather than a script.
 */
import { Schema } from "effect";
import { RowSet } from "./rows.ts";
import { EvidenceSpec } from "./backlog.ts";
import { PriorStamp } from "./selection.ts";
import {
  DedupKey,
  ExecutorId,
  LevelName,
  MemberId,
  PlanId,
  Sha256Hex,
  TaskId
} from "./ids.ts";

/** One release proposal crossing the uplink. */
export const Admit = Schema.Struct({
  /** The item proposed. */
  taskId: TaskId,
  /** The plan that authorises it. */
  planId: PlanId,
  /** The executor this admit is addressed to. */
  executor: ExecutorId,
  /** The brief hash the executor verifies against its armed set. */
  briefHash: Sha256Hex,
  /** The digest of the plan artifact that armed this item; the whole authority. */
  planHash: Sha256Hex,
  /** The rows requested, granted all-or-nothing. */
  rows: RowSet,
  /** The catalog member resolved for this item. */
  member: MemberId,
  /** Evidence forms the kernel will check. */
  evidence: Schema.Array(EvidenceSpec),
  /** The kernel's idempotency key. */
  dedupKey: DedupKey,
  /** The level this item was released at, stamped on the witness record. */
  level: LevelName,
  /**
   * The lane duration cap, at the class p99.
   *
   * Read as a learning-augmented scheduler, this is the robustness parameter
   * that bounds the damage a wrong p80 prediction does. Left unset it bounds
   * nothing and Graham's additive bound goes vacuous.
   */
  runtimeMaxSec: Schema.Finite,
  /**
   * The elapsed multiple of the class median at which the kernel should ask the
   * holder to checkpoint and exit.
   *
   * The engine decides; the kernel's cooperative yield hook acts, because tally
   * never infers a safe checkpoint from process state.
   */
  yieldAtMedianMultiple: Schema.Finite,
  /** The envelope allocation this item may spend, which its children debit. */
  envelope: Schema.Finite,
  /**
   * The prior this item is released under, when the selector supplied one.
   *
   * U-A24. `register next` writes `cards/selection-<pass>.tsv`; the lake decodes
   * it and carries the row's `prior_source` and, from pass 2, the parameters of
   * the Thompson draw that ranked it. It is stamped here because the release is
   * where the prior stops being a belief and starts being a bet: the receipt the
   * evaluator writes scores the outcome against exactly this stamp, and Brier is
   * reported per `(prior_source x arm)` (§6.2 B11). A prior recorded anywhere
   * later would be a prior scored that was not the prior used.
   *
   * The executor never reads it. It is not argv, not a routing and not a
   * capability: an admit is still a proposal and this field changes nothing the
   * door decides.
   *
   * Optional because a plan armed from a card rather than from a selection pass
   * has no draw behind it, and an absent stamp is the honest record of that.
   */
  prior: Schema.optionalKey(PriorStamp)
});
/** One release proposal crossing the uplink. */
export type Admit = typeof Admit.Type;

/**
 * A cancel the Worker sends down.
 *
 * The lake never originates one. A cancel exists only because a human asked or
 * because an armed supersession retired the plan that authorised the work, and
 * the message carries which.
 */
export const Cancel = Schema.Struct({
  /** The job to cancel. */
  taskId: TaskId,
  /** The executor holding it. */
  executor: ExecutorId,
  /** What authorised the cancel. There is no third source. */
  authorisedBy: Schema.Literals(["human", "supersession"])
});
/** A cancel the Worker sends down. */
export type Cancel = typeof Cancel.Type;

/**
 * A steer the Worker sends down.
 *
 * Delivery is populate-first and can never be a submit: the type has one legal
 * value for `delivery`, so the safety property is enforced by the schema rather
 * than by a caller remembering it. The durable half of a steer is the lake's;
 * this is only the delivery to a live pane.
 */
export const Steer = Schema.Struct({
  /** The lane to steer. */
  taskId: TaskId,
  /** The executor holding it. */
  executor: ExecutorId,
  /** The text to place in the pane. */
  text: Schema.String,
  /** Populate, never submit. The blocked interlock is the executor's to enforce. */
  delivery: Schema.Literals(["populate"])
});
/** A steer the Worker sends down, populate-first and never a submit. */
export type Steer = typeof Steer.Type;

/**
 * The kernel's answer.
 *
 * `notYet` is a third idempotent outcome beside accept and reject, and it means
 * the item goes back to the backlog untouched. Deferring is not scheduling.
 */
export const AdmitOutcome = Schema.Union([
  Schema.Struct({ _tag: Schema.tag("Accepted"), taskId: TaskId }),
  Schema.Struct({ _tag: Schema.tag("Rejected"), taskId: TaskId, code: Schema.String }),
  Schema.Struct({ _tag: Schema.tag("NotYet"), taskId: TaskId, row: Schema.String })
]);
/** The kernel's answer to an admit. */
export type AdmitOutcome = typeof AdmitOutcome.Type;

/**
 * The outcome report posted back to the Factory after the kernel answers an
 * admit proposal.
 *
 * The proposal identity is repeated in full.  A task id alone is not enough:
 * an old answer for an earlier proposal must not be allowed to move a newly
 * armed item through the state machine.  `lease_id` and `preempt` are kernel
 * observations carried verbatim when present; the Factory does not derive
 * either one.
 */
export const AdmitOutcomeReport = Schema.Struct({
  taskId: TaskId,
  dedupKey: DedupKey,
  outcome: Schema.Literals(["Accepted", "Rejected", "NotYet"]),
  row: Schema.String,
  lease_id: Schema.optionalKey(Schema.String),
  preempt: Schema.optionalKey(Schema.Unknown),
  /** The kernel's legible rejection code, when the outcome is `Rejected`. */
  code: Schema.optionalKey(Schema.String)
});
/** The kernel's answer together with the proposal identity it answers. */
export type AdmitOutcomeReport = typeof AdmitOutcomeReport.Type;

/** Decodes an untrusted `POST /outcomes` body. */
export const parseAdmitOutcomeReport = Schema.decodeUnknownEffect(AdmitOutcomeReport);

/**
 * Why an item was not proposed this pass.
 *
 * Deferrals are returned as data with the deferring rule named, so a deferral is
 * legible rather than silent. This is the record the mutex incident had no way
 * to produce.
 */
export const Deferral = Schema.Struct({
  /** The item deferred. */
  taskId: TaskId,
  /** The heuristic module that deferred it. */
  rule: Schema.Literals([
    "conwip",
    "valueDensity",
    "paceLine",
    "protectionLevel",
    "envelope",
    "localFirst",
    "capacityRow",
    "oracleFreshness",
    "namespaceRoundRobin",
    "levelPreemption",
    "planNotArmed",
    "attemptCap",
    // The predecessor rule. An item whose `dependsOn` names a task that has not
    // closed `pass` is deferred here and nowhere else; `detail` is the first
    // unmet task id, so the deferral names what it is waiting for rather than
    // saying only that it waited.
    "dependencyUnmet",
    // The filler lane's round-robin (D-B10: "the two fillers alternate by
    // round-robin"). At most one filler source is releasable in a pass; the
    // other's items are deferred here and nowhere else, and `detail` is the
    // family whose turn it actually is, so the deferral names who went instead.
    "fillerAlternation"
  ]),
  /** The specific binding thing: a row, a cap, a namespace. */
  detail: Schema.String
});
/** Why an item was not proposed this pass. */
export type Deferral = typeof Deferral.Type;

/**
 * The one thing the factory asks of Tom unprompted.
 *
 * A family below its reorder point, with the shortfall that brings it to the
 * order-up-to level. A notification, not a nag, and the only output of the
 * engine addressed to a human rather than to a kernel.
 */
export const Andon = Schema.Struct({
  /** The family below its reorder point. */
  family: Schema.String,
  /** How many scoped-ready items are on hand. */
  onHand: Schema.Int,
  /** How many more bring it to the order-up-to level. */
  shortfall: Schema.Int
});
/** A family below its reorder point, with its shortfall. */
export type Andon = typeof Andon.Type;
