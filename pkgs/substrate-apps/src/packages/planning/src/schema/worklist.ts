/**
 * The campaign worklist: a precedence DAG, armed by the digest of its artifact.
 *
 * Article A5 says a campaign is state, not process: desired state is the
 * worklist DAG, observed state is what the ledger reports, and execution is
 * short stateless reconcile passes over the gap. That is a Durable Object's
 * whole job description, and it is why a campaign is one object rather than a
 * process anyone has to keep alive.
 *
 * The object holds its DAG in its own state and computes over it; it never
 * rewrites the armed artifact, because the artifact's digest is the authority
 * every later admit carries. Merges and pushes are not events the lake waits
 * for: they are ordinary nodes an agent performs, witnessed like any other.
 */
import { Schema } from "effect";
import { CampaignId, ClassName, Seconds, Sha256Hex, TaskId } from "./ids.ts";
import { MergeGate } from "./backlog.ts";

/** One task in a worklist. */
const WorklistTask = Schema.Struct({
  /** The task's identity within the campaign. */
  taskId: TaskId,
  /** Tasks that must complete before this one, the DAG's edges. */
  dependencies: Schema.Array(TaskId),
  /**
   * Mutual-exclusion groups.
   *
   * These are the machine-disjunctive arcs of a job shop. They lengthen the
   * critical path arbitrarily, so the path must be computed on the disjunctive
   * graph; on the dependency DAG alone it systematically under-predicts.
   */
  conflictDomains: Schema.Array(Schema.String),
  /** The capability class the task requires. */
  needs: ClassName,
  /** Estimated duration, which is all the critical path needs. */
  durationSeconds: Seconds,
  /** Rank on the ready frontier, below the least-cost-last ordering. */
  rank: Schema.Int,
  /** Whether the task's merge gate is mechanical, which licenses redundancy. */
  gate: MergeGate
});
/** One task in a worklist. */
type WorklistTask = typeof WorklistTask.Type;

/** One campaign's worklist, held in the object's own state. */
export const Worklist = Schema.Struct({
  /** The campaign. */
  campaignId: CampaignId,
  /** The digest of the artifact this worklist was armed from. */
  planHash: Sha256Hex,
  /** The tasks. */
  tasks: Schema.Array(WorklistTask),
  /** The campaign's own work-in-process cap. */
  maxParallel: Schema.Int
});
/** One campaign's worklist, held in the object's own state. */
export type Worklist = typeof Worklist.Type;
