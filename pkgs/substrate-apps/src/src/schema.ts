// Boundary schemas. Every external representation is parsed here and never cast.
// Effect is used as Schema plus (in axclient/loop) plain values: no Stream, Fiber,
// Queue, Scope, Semaphore or Schedule appears anywhere in this repository.
import { Schema } from "effect";

/**
 * One WorkItem per `workflow_agent` entry of a run record. Never one per workflow.
 * Phases are dependency edges between items, not items themselves.
 */
export const WorkItem = Schema.Struct({
  runId: Schema.String,
  workflowName: Schema.String,
  label: Schema.String,
  index: Schema.Int,
  phaseIndex: Schema.Int,
  phaseTitle: Schema.String,
  model: Schema.String,
  effort: Schema.optionalKey(Schema.String),
  prompt: Schema.String,
  sizingTokens: Schema.optionalKey(Schema.Int),
  sizingDurationMs: Schema.optionalKey(Schema.Int),
  // Added beyond the brief's table, and named in DESIGN.md:
  // the extraction outcome, and the source record's own status, which the
  // admission pass needs in order to refuse a killed run's items by name.
  promptResolved: Schema.Boolean,
  promptUnresolvedReason: Schema.optionalKey(Schema.String),
  sourceStatus: Schema.String,
  /**
   * CR-10 of the 2026-09-23 evals. The outcome of THIS agent in the source
   * record, from the entry's own `state`, not the run's `status`: 84 agents
   * with `state: error` inside completed runs used to be posted Completed.
   * Only the fixture arm reads it; a live run posts what the seat returned.
   */
  sourceOutcome: Schema.optionalKey(Schema.Literals(["Completed", "Failed"])),
  /** The entry's `state` verbatim, when it has one. */
  sourceAgentState: Schema.optionalKey(Schema.String),
  /** The entry's `attempt`, 1-based, when it has one. */
  attempt: Schema.optionalKey(Schema.Int),
  /**
   * D05/D06 of the 2026-09-23 evals (successor review r2): the indices of the
   * items of the same run this item provably waited on, from the run's
   * journal: an earlier-phase item whose terminal line precedes this item's
   * `started` line. Absent (no journal) means independent: phase adjacency is
   * never read as a dependency, because a no-barrier pipeline starts phase n+1
   * work before phase n has finished.
   */
  after: Schema.optionalKey(Schema.Array(Schema.Int)),
});

export type WorkItem = typeof WorkItem.Type;

/** The fixture outcome of an item: its own entry state first, the run status only as a fallback. */
export function fixtureOutcome(i: WorkItem): "Completed" | "Failed" {
  if (i.sourceOutcome !== undefined) return i.sourceOutcome;
  return i.sourceStatus === "completed" ? "Completed" : "Failed";
}

export const decodeWorkItem = Schema.decodeUnknownSync(WorkItem);

/** A `phases` entry is `{title, detail?}` and nothing else. */
export const WorkflowPhase = Schema.Struct({
  title: Schema.String,
  detail: Schema.optionalKey(Schema.String),
});

export type WorkflowPhase = typeof WorkflowPhase.Type;

/**
 * The `workflow_agent` entries of `workflowProgress`. Only the keys this
 * scheduler consumes are required; the rest are carried as unknown so that a
 * new key upstream is not a parse failure.
 */
export const WorkflowAgentEntry = Schema.Struct({
  type: Schema.String,
  index: Schema.Int,
  label: Schema.String,
  phaseIndex: Schema.Int,
  phaseTitle: Schema.String,
  model: Schema.optionalKey(Schema.String),
  tokens: Schema.optionalKey(Schema.Number),
  toolCalls: Schema.optionalKey(Schema.Number),
  durationMs: Schema.optionalKey(Schema.Number),
});

export type WorkflowAgentEntry = typeof WorkflowAgentEntry.Type;

export const decodeWorkflowAgentEntry = Schema.decodeUnknownSync(WorkflowAgentEntry);
export const decodeWorkflowPhase = Schema.decodeUnknownSync(WorkflowPhase);
