/**
 * Arming: the one human act between the two phases of the day.
 *
 * Fable writes the plan; Tom arms it; arming is approval. The input is a plan
 * artifact — an ultracode workflow script with its arguments, or a campaign
 * worklist — sent straight to the Factory object over HTTPS. No commit and no
 * forge is involved. Pushing to a forge is an ordinary act an agent performs
 * inside a node, exactly as it is in any ultracode workflow, so there is nothing
 * here that fetches at a revision and nothing that waits on a webhook.
 *
 * Constitution article A1 survives, read as the rulings read it: authority is
 * the bytes Tom armed, held by their hash. The object hashes the artifact it was
 * handed, refuses a mismatch against what the client claimed, and that digest is
 * the authority the kernel verifies before it runs anything. A plan that wants
 * its own bytes committed commits them as a node.
 *
 * Under ruling 6 there is exactly one write path into the lake, `plan arm`.
 * There is no pardon and no lifetime latch: a malformed flow fails as a type
 * error before anything is armed, and a failed node is a fact the release rule
 * reads. Fable's own lane keeps `noEnqueue`, so the model that writes a plan is
 * mechanically incapable of arming it.
 */
import { Schema } from "effect";
import { Author, LevelName, NamespaceName, PlanId, Sha256Hex } from "./ids.ts";

/**
 * Which of the two legal plan artifacts this is.
 *
 * A worklist is a precedence DAG, and gets the critical path and float. A
 * workflow is an ultracode script accepted byte for byte, whose nodes become
 * items directly.
 */
const PlanKind = Schema.Literals(["worklist", "workflow"]);
/** Which of the two legal plan artifacts this is. */
type PlanKind = typeof PlanKind.Type;

/**
 * The `tally plan arm` message.
 *
 * The Factory hashes the bytes it was handed, refuses a mismatch against
 * `planHash`, writes a plan row, expands the artifact into backlog items and
 * wakes the release evaluator.
 */
export const PlanArm = Schema.Struct({
  /**
   * A human-legible name for the artifact, for the release journal.
   *
   * A label and never a locator: nothing fetches it, and two artifacts may
   * carry the same label without colliding, because identity is the hash.
   */
  label: Schema.String,
  /** Which of the two legal artifact kinds this is. */
  kind: PlanKind,
  /** The preemptive level every item of this plan competes at. */
  level: LevelName,
  /** The namespace this plan's work belongs to. */
  namespace: NamespaceName,
  /**
   * Hash of the artifact bytes, and the whole of the plan's authority.
   *
   * The object recomputes it over the bytes it received and refuses a mismatch,
   * never repairs one. Every later admit carries this digest, and the kernel
   * refuses any hash absent from the armed set it was given over the same
   * channel — which is what bounds a compromised Worker to asking for work Tom
   * already armed.
   */
  planHash: Sha256Hex,
  /** The identity that armed it. Arming is approval, and approval has an author. */
  author: Author
});
/** The `tally plan arm` message. */
export type PlanArm = typeof PlanArm.Type;

/** Decodes an untrusted arm request from the client. */
export const parsePlanArm = Schema.decodeUnknownEffect(PlanArm);

/**
 * Whether an armed plan is still the authority for its items.
 *
 * A superseded plan's unclaimed items are retired and its in-flight ones are
 * eligible for an authorised cancel. Supersession is a control-plane fact and
 * never a verdict.
 */
const PlanStatus = Schema.Literals(["armed", "superseded", "complete"]);
/** Whether an armed plan is still the authority for its items. */
type PlanStatus = typeof PlanStatus.Type;

/** The row the Factory writes when a plan is armed. */
export const PlanRow = Schema.Struct({
  /** The plan's identity. */
  planId: PlanId,
  /**
   * The hash of the armed bytes, lifted out of the arm message.
   *
   * Held at the top level because it is what every admit cites and what the
   * kernel verifies. There is no commit beside it and none is required.
   */
  planHash: Sha256Hex,
  /** The arming message, kept verbatim so a decision can cite its authority. */
  arm: PlanArm,
  /** Whether this plan still authorises its items. */
  status: PlanStatus,
  /**
   * The per-plan attempt cap.
   *
   * A release-rule datum Tom can set to unlimited. There is no global constant
   * and no counter a human must lift; ruling 6 removed both.
   */
  attemptCap: Schema.OptionFromNullOr(Schema.Int)
});
/** The row the Factory writes when a plan is armed. */
export type PlanRow = typeof PlanRow.Type;
