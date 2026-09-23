/**
 * Branded identifiers and scalar domain types shared by every planning module.
 *
 * Identity in the factory is always a hash or an authored name, never a
 * position: an item is its `payloadHash`, a plan is its `planHash`, a member is
 * its catalog id. Branding these keeps a namespace from being passed where a
 * family is expected, which is the class of mistake the mutex incident made
 * possible.
 */
import { Schema } from "effect";

/** One admitted job: the atomic item the rail leases, witnesses and reports. */
export const TaskId = Schema.String.pipe(Schema.brand("TaskId"));
/** One admitted job: the atomic item the rail leases, witnesses and reports. */
export type TaskId = typeof TaskId.Type;

/** One armed plan artifact at a pinned revision. */
export const PlanId = Schema.String.pipe(Schema.brand("PlanId"));
/** One armed plan artifact at a pinned revision. */
export type PlanId = typeof PlanId.Type;

/** One campaign, which is one Durable Object holding one worklist DAG. */
export const CampaignId = Schema.String.pipe(Schema.brand("CampaignId"));
/** One campaign, which is one Durable Object holding one worklist DAG. */
export type CampaignId = typeof CampaignId.Type;

/**
 * One executor: one admission door with its own single-writer witness chain.
 *
 * A kernel is anything implementing the admit-and-witness contract, so the
 * identity is the executor's and not the box's. The local rail on the
 * coordinator is one executor; a cloud-side executor running a harness in a
 * sandbox is another. There is one Kernel object per executor id, the mirror
 * verifies each chain separately, and nothing in the release rule assumes there
 * is exactly one.
 */
export const ExecutorId = Schema.String.pipe(Schema.brand("ExecutorId"));
/** One executor: one admission door with its own single-writer witness chain. */
export type ExecutorId = typeof ExecutorId.Type;

/** A namespace is `workspace.repo`; release fairness round-robins across these. */
export const NamespaceName = Schema.String.pipe(Schema.brand("NamespaceName"));
/** A namespace is `workspace.repo`; release fairness round-robins across these. */
export type NamespaceName = typeof NamespaceName.Type;

/** A product family: the unit that carries a WIP cap, a buffer and a holding cost. */
export const FamilyName = Schema.String.pipe(Schema.brand("FamilyName"));
/** A product family: the unit that carries a WIP cap, a buffer and a holding cost. */
export type FamilyName = typeof FamilyName.Type;

/** A preemptive priority level in Tom's lexicographic hierarchy. */
export const LevelName = Schema.String.pipe(Schema.brand("LevelName"));
/** A preemptive priority level in Tom's lexicographic hierarchy. */
export type LevelName = typeof LevelName.Type;

/** A capacity row: one physical contended thing with its own dual price. */
export const RowName = Schema.String.pipe(Schema.brand("RowName"));
/** A capacity row: one physical contended thing with its own dual price. */
export type RowName = typeof RowName.Type;

/** A catalog member id, resolving to one `(model x herdr agent kind)` machine. */
export const MemberId = Schema.String.pipe(Schema.brand("MemberId"));
/** A catalog member id, resolving to one `(model x herdr agent kind)` machine. */
export type MemberId = typeof MemberId.Type;

/** A model identity as the catalog declares it; never chosen per call site. */
export const ModelId = Schema.String.pipe(Schema.brand("ModelId"));
/** A model identity as the catalog declares it; never chosen per call site. */
export type ModelId = typeof ModelId.Type;

/**
 * A herdr agent kind. tally carries the string and no behaviour: launch, argv
 * and resume semantics are herdr's manifest, not this package's business.
 */
export const AgentKind = Schema.String.pipe(Schema.brand("AgentKind"));
/** A herdr agent kind, carried opaquely; harness knowledge lives in herdr. */
export type AgentKind = typeof AgentKind.Type;

/** The maker of a model, used only to decorrelate redundant attempts. */
export const MakerName = Schema.String.pipe(Schema.brand("MakerName"));
/** The maker of a model, used only to decorrelate redundant attempts. */
export type MakerName = typeof MakerName.Type;

/** A capability class. Classes are grade-of-service floors, never dedication. */
export const ClassName = Schema.String.pipe(Schema.brand("ClassName"));
/** A capability class. Classes are grade-of-service floors, never dedication. */
export type ClassName = typeof ClassName.Type;

/** The kernel's idempotency key for an enqueue. */
export const DedupKey = Schema.String.pipe(Schema.brand("DedupKey"));
/** The kernel's idempotency key for an enqueue. */
export type DedupKey = typeof DedupKey.Type;

/** A named warm prerequisite: a worktree at a base revision, a corpus, a cache. */
export const SubassemblyKey = Schema.String.pipe(Schema.brand("SubassemblyKey"));
/** A named warm prerequisite: a worktree at a base revision, a corpus, a cache. */
export type SubassemblyKey = typeof SubassemblyKey.Type;

/** The git identity attached to an arming act. Arming is approval. */
export const Author = Schema.String.pipe(Schema.brand("Author"));
/** The git identity attached to an arming act. Arming is approval. */
export type Author = typeof Author.Type;

/**
 * A lowercase hex sha-256 digest.
 *
 * The witness ledger's chaining hashes use this, and so does a plan's authority:
 * the Factory hashes the artifact bytes it was handed, and that digest is what
 * the kernel verifies before it will run anything. There is no revision behind
 * it and none is required.
 */
export const Sha256Hex = Schema.String.pipe(
  Schema.check(Schema.isPattern(/^[0-9a-f]{64}$/)),
  Schema.brand("Sha256Hex")
);
/** A lowercase hex sha-256 digest, as the witness ledger and brief hashes use. */
export type Sha256Hex = typeof Sha256Hex.Type;

/**
 * An elapsed interval in seconds.
 *
 * Durations are measured and supplied by the caller. Nothing in this package
 * reads a clock, so a `Seconds` is always an input and never something the
 * engine obtains for itself.
 */
export const Seconds = Schema.Finite.pipe(
  Schema.check(Schema.isGreaterThanOrEqualTo(0)),
  Schema.brand("Seconds")
);
/** An elapsed interval in seconds, always supplied by the caller. */
export type Seconds = typeof Seconds.Type;

/**
 * Subscription weight: the one scalar every metered consumption is denominated
 * in, because the rate limit is shared across models.
 */
export const Weight = Schema.Finite.pipe(
  Schema.check(Schema.isGreaterThanOrEqualTo(0)),
  Schema.brand("Weight")
);
/** Subscription weight, the single denomination for metered consumption. */
export type Weight = typeof Weight.Type;

/**
 * A monotone sequence number.
 *
 * The engine orders by sequence, never by wall-clock time. Witness records
 * carry one, capacity readings carry one, and a gap in the sequence is recorded
 * rather than filled.
 */
export const Seq = Schema.Int.pipe(
  Schema.check(Schema.isGreaterThanOrEqualTo(0)),
  Schema.brand("Seq")
);
/** A monotone sequence number; the engine orders by these, never by a clock. */
export type Seq = typeof Seq.Type;

/**
 * An index into the envelope's window schedule.
 *
 * A window is a metered reset horizon. Counting windows is how the pace line
 * expresses the passage of the slow clock without reading one.
 */
export const WindowIndex = Schema.Int.pipe(
  Schema.check(Schema.isGreaterThanOrEqualTo(0)),
  Schema.brand("WindowIndex")
);
/** An index into the envelope's window schedule. */
export type WindowIndex = typeof WindowIndex.Type;

/** A probability in `[0, 1]`: a first-pass yield, a fractile, a shrinkage weight. */
export const UnitInterval = Schema.Finite.pipe(
  Schema.check(Schema.isBetween({ minimum: 0, maximum: 1 })),
  Schema.brand("UnitInterval")
);
/** A probability in `[0, 1]`. */
export type UnitInterval = typeof UnitInterval.Type;
