/**
 * The lease as a resource envelope, not a token.
 *
 * Volume II Part III section 6: a dispatched job may itself expand into a shop.
 * Opacity is fine while the subtree draws only on resources already charged in
 * full and non-rival at the margin — local subagents on idle devices. Opacity
 * fails the moment a child draws on a metered lane, and it fails in three
 * specific ways. The parent's consumption becomes a random variable with
 * unbounded upside, so the bid-price test is evaluated against an estimate the
 * job can falsify after admission. The card deck stops bounding concurrency,
 * because one card can spawn many metered children. And the p80 estimate is
 * corrupted at the root, since the outer-level cost of a job becomes a subtree
 * cost that depends on the width the subtree happened to take.
 *
 * The fix is the standard one from two-level scheduling and it is a change in
 * what a lease is: a parent holds an allocation, children debit it at grant, and
 * the daemon refuses a child when the parent's envelope is exhausted. That is a
 * hierarchical token bucket. It composes with the existing capability strip that
 * removes child enqueue entirely, which is the degenerate zero-envelope case and
 * needs no separate code path.
 *
 * The invariant that makes admission safe is one-directional: a child can only
 * reduce headroom, never mint it. Every function here preserves it, and the
 * property test asserts it over arbitrary grant sequences.
 */
import { Option } from "effect";
import type { TaskId } from "../schema/ids.ts";

/** A parent's allocation and what its subtree has already drawn. */
export interface Envelope {
  /** The task holding the allocation. */
  readonly owner: TaskId;
  /** The allocation granted at admission, in subscription weight. */
  readonly allocated: number;
  /** What the subtree has already debited. Never decreases. */
  readonly debited: number;
}

/** The outcome of asking a parent for a child's allocation. */
type EnvelopeGrant =
  | {
      readonly _tag: "Granted";
      /** The parent envelope after the debit. */
      readonly parent: Envelope;
      /** The child's own envelope, which its own children will debit in turn. */
      readonly child: Envelope;
    }
  | {
      readonly _tag: "Refused";
      /** How much of the request could not be covered. */
      readonly shortfall: number;
    };

/**
 * Creates a root envelope.
 *
 * @param owner - The task admitted.
 * @param allocated - Its allocation. A negative allocation is clamped to zero,
 *   because a negative envelope would be headroom minted by arithmetic.
 * @returns A fresh envelope with nothing debited.
 */
export const rootEnvelope = (owner: TaskId, allocated: number): Envelope => ({
  owner,
  allocated: Math.max(0, allocated),
  debited: 0
});

/** What remains of an envelope, floored at zero. */
export const remaining = (envelope: Envelope): number =>
  Math.max(0, envelope.allocated - envelope.debited);

/**
 * Asks a parent for a child's allocation.
 *
 * @param parent - The parent's envelope.
 * @param child - The child task.
 * @param request - The allocation asked for.
 * @returns A grant carrying both updated envelopes, or a refusal naming the
 *   shortfall. There is no partial grant: a child either gets what it asked for
 *   or is refused, because a partially funded subtree falsifies its own estimate
 *   exactly as an unbounded one does.
 */
export const grantChild = (
  parent: Envelope,
  child: TaskId,
  request: number
): EnvelopeGrant => {
  const asked = Math.max(0, request);
  const available = remaining(parent);
  if (asked > available) return { _tag: "Refused", shortfall: asked - available };
  return {
    _tag: "Granted",
    parent: { ...parent, debited: parent.debited + asked },
    child: rootEnvelope(child, asked)
  };
};

/**
 * Whether an envelope has any allocation left to give.
 *
 * The zero case is the capability strip that removes child enqueue: a lane with
 * a zero envelope cannot dispatch anything, which is the guarantee stated as
 * arithmetic rather than as etiquette.
 */
export const canSpawn = (envelope: Envelope): boolean => remaining(envelope) > 0;

/**
 * Finds a task's envelope among those the Factory holds.
 *
 * @returns The envelope, or `None` when the parent is unknown, which refuses the
 *   child rather than treating an unknown parent as unbounded.
 */
export const envelopeOf = (
  envelopes: ReadonlyArray<Envelope>,
  owner: TaskId
): Option.Option<Envelope> => {
  for (const envelope of envelopes) {
    if (envelope.owner === owner) return Option.some(envelope);
  }
  return Option.none();
};

/**
 * Total allocation outstanding across a set of envelopes.
 *
 * Used by the property test that asserts conservation: over any sequence of
 * grants, the sum of debits never exceeds the root allocation, and no operation
 * increases it.
 */
export const totalOutstanding = (envelopes: ReadonlyArray<Envelope>): number =>
  envelopes.reduce((sum, envelope) => sum + remaining(envelope), 0);
