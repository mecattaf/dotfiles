/**
 * The backlog item: one node of one armed plan, waiting in the lake.
 *
 * The backlog is deliberately not the kernel's pending list. One-step aging
 * promotes a deep pending list uniformly to interrupt priority, after which
 * dispatch is first-in-first-out and Tom's order is destroyed by design; and
 * every enqueue burns records from a bounded change log. So unclaimed work
 * lives here under the lexicographic hierarchy and value density, while
 * `pending` on the box stays the small work-in-process buffer the rail runs.
 * Value density orders release and the aging rule orders dispatch: two correct
 * rules at two gates, which can only coexist while the backlog is outside the
 * kernel.
 *
 * An item carries its class and never a pool. That absence is the orthogonality
 * of routing and scheduling: no scheduling decision edits a routing, and no
 * routing embeds a scheduling decision.
 */
import { Effect, Schema } from "effect";
import { Estimate } from "./estimate.ts";
import { VerdictOutcome } from "./records.ts";
import {
  ClassName,
  DedupKey,
  FamilyName,
  LevelName,
  NamespaceName,
  Seconds,
  Sha256Hex,
  SubassemblyKey,
  TaskId,
  WindowIndex
} from "./ids.ts";
import { PlanId } from "./ids.ts";

/**
 * A witnessed evidence form.
 *
 * Evidence is what the kernel checks to close a job. It is part of the routing
 * and never a scheduling decision, so the engine carries it verbatim.
 */
export const EvidenceSpec = Schema.String.pipe(Schema.brand("EvidenceSpec"));
/** A witnessed evidence form, carried verbatim from the plan artifact. */
export type EvidenceSpec = typeof EvidenceSpec.Type;

/**
 * Where an item sits between arming and closure.
 *
 * `unclaimed` is the backlog proper. `released` means an admit has crossed the
 * uplink and not yet been answered. `inflight` means the kernel accepted it and
 * it holds rows. `closed` means a witness arrived. Nothing here is a verdict;
 * the verdict is a mirrored record.
 */
const ItemState = Schema.Literals(["unclaimed", "released", "inflight", "closed"]);
/** Where an item sits between arming and closure. */
type ItemState = typeof ItemState.Type;

/**
 * Whether an item's merge gate can discard a losing attempt without a human.
 *
 * This is the field that licenses redundancy. Where the gate is Tom, `k`
 * attempts multiply the bottleneck by `k` and redundancy is strictly harmful.
 */
export const MergeGate = Schema.Literals(["mechanical", "human"]);
/** Whether an item's merge gate can discard a losing attempt without a human. */
export type MergeGate = typeof MergeGate.Type;

/** One node of one armed plan. */
export const BacklogItem = Schema.Struct({
  /** The item's identity. */
  taskId: TaskId,
  /** The plan that armed it. */
  planId: PlanId,
  /** The namespace, which is `workspace.repo`. */
  namespace: NamespaceName,
  /** The product family, which carries the cap, the buffer and the holding cost. */
  family: FamilyName,
  /** The preemptive level this item competes at. */
  level: LevelName,
  /** Rank within the plan, used to break ties below value density. */
  rank: Schema.Int,
  /** The capability class the node requires. A floor, never a pool. */
  needs: ClassName,
  /**
   * The items this one waits for, by task id.
   *
   * `needs` and `dependsOn` are two different words and neither is the other.
   * `needs` is a `ClassName` — the capability class the catalog resolves, a
   * floor on who may run this item. `dependsOn` is a set of task ids — the
   * predecessors that must have closed `pass` before this item is a candidate
   * at all. Before this field existed the release evaluator had no predecessor
   * rule of any kind, so "wait for X then resume Y" could be written in a plan
   * and silently ignored at the station.
   *
   * The rule that reads it is `dependencyUnmet` in the evaluator's candidate
   * filter, and the acceptor writes `dependsOn`, never `needs`.
   *
   * Absent on the wire it decodes to the empty array, so an item with no
   * predecessor is exactly what it was before this field: a candidate.
   */
  dependsOn: Schema.Array(TaskId).pipe(
    Schema.withDecodingDefaultKey(Effect.succeed([] as ReadonlyArray<string>))
  ),
  /** Evidence forms the kernel will check. */
  evidence: Schema.Array(EvidenceSpec),
  /** Hash of the brief; the kernel refuses any hash absent from its armed set. */
  briefHash: Sha256Hex,
  /**
   * The digest of the plan artifact that armed this item.
   *
   * This is the authority the kernel verifies against. It replaces the pinned
   * revision: the bytes were handed to the object and hashed there, so there is
   * no commit behind it and none is needed.
   */
  planHash: Sha256Hex,
  /** The kernel's idempotency key. */
  dedupKey: DedupKey,
  /**
   * Stable reference from which the executor resolves this item's command.
   *
   * The lake never turns this reference into argv. It carries the acceptor's
   * value through persistence and falls back to `taskId` at proposal time when
   * an older or hand-authored item omits it.
   */
  argv_ref: Schema.optionalKey(Schema.String),
  /**
   * The authored negative control the mechanical evaluator applies.
   *
   * This is optional because scoping and card-less nodes do not have one, but a
   * present value is part of the durable item rather than transient HTTP data.
   */
  mutation_hint: Schema.optionalKey(Schema.String),
  /** Current state. */
  state: ItemState,
  /**
   * How many passes have deferred this item without admitting it.
   *
   * Maintained by the Factory as it records each pass's deferrals, and read by
   * exactly one rule: the congestion clause of the release policy, which decides
   * whether sustained congestion leaves an item waiting or licenses it to
   * escalate. Zero for an item no pass has yet passed over.
   */
  deferrals: Schema.Int,
  /**
   * Which attempt this is, counting from one.
   *
   * A verdict whose outcome is not `pass` returns the item to `unclaimed` and
   * increments this, under the plan row's `attemptCap`. It is not `deferrals`:
   * a deferral is a pass that did not propose the item, an attempt is a run that
   * happened and ended badly.
   */
  attempt: Schema.Int.pipe(Schema.withDecodingDefaultKey(Effect.succeed(1))),
  /**
   * How many non-filler releases on the filler lane's row have passed this item
   * over.
   *
   * The anti-starvation counter of the filler-lane contract (spec §4.4 clause 3,
   * D-B10): *"a filler item that has been passed over by 10 non-filler releases
   * on its row is proposed at level 1 for one release"*. It is not `deferrals`
   * and not `attempt`: a deferral is any pass that did not propose the item, for
   * any of a dozen reasons, and an attempt is a run that happened. This counts
   * only the releases that took the lane's row while this item waited, which is
   * the quantity the ruling names.
   *
   * Maintained by the Factory as it hands out, read by exactly one rule
   * (`heuristics/fillerLane.ts`), and reset to zero the moment the item is
   * released — which is what makes the promotion last for one release.
   *
   * Zero for every item that is not a filler, and absent on the wire it decodes
   * to zero, so an item armed before this field existed is exactly what it was.
   */
  passedOver: Schema.Int.pipe(Schema.withDecodingDefaultKey(Effect.succeed(0))),
  /**
   * How the item's own witnessed run ended, once one has.
   *
   * `None` while the item has not closed. It is a mirrored outcome and never a
   * constructed one: the only writer is the Factory recording a `Verdict` that
   * arrived, and `records.ts` is the only producer of a `Verdict`.
   *
   * This is what makes `dependencyUnmet` decidable. "Closed" alone is not the
   * predicate the spec states — a predecessor that closed `fail` has not been
   * met — so the outcome has to sit on the item the successor's rule reads.
   */
  outcome: Schema.OptionFromNullOr(VerdictOutcome).pipe(
    Schema.withDecodingDefaultKey(Effect.succeed(null))
  ),
  /** Value of completing this item, `v_j`, from the namespace's value vector. */
  value: Schema.Finite,
  /** The estimate on this item's class, already shrunk. */
  estimate: Estimate,
  /** Whether a losing redundant attempt can be discarded mechanically. */
  gate: MergeGate,
  /** A shared warm prerequisite, if this item has one. */
  subassembly: Schema.OptionFromNullOr(SubassemblyKey),
  /** The window this item is due by, for the few items that are dated. */
  dueBy: Schema.OptionFromNullOr(WindowIndex),
  /** Total float from the campaign's disjunctive critical path, if it is a campaign task. */
  float: Schema.OptionFromNullOr(Seconds),
  /** The parent whose envelope this item debits, if it is a recursive child. */
  envelopeParent: Schema.OptionFromNullOr(TaskId)
});
/** One node of one armed plan, waiting in the lake. */
export type BacklogItem = typeof BacklogItem.Type;

/** Decodes an untrusted backlog. */
export const parseBacklog = Schema.decodeUnknownEffect(Schema.Array(BacklogItem));

/** Current work-in-process counted along the three axes the caps run on. */
export const WipCount = Schema.Struct({
  /** The level. */
  level: LevelName,
  /** The namespace. */
  namespace: NamespaceName,
  /** The family. */
  family: FamilyName,
  /** Items released or in flight against this triple. */
  count: Schema.Int
});
/** Current work-in-process counted along the three axes the caps run on. */
export type WipCount = typeof WipCount.Type;
