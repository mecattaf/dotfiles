/**
 * Test fixtures, built by parsing at the boundary.
 *
 * Every domain value here is produced by the schema-owned parser rather than
 * asserted into shape, so a fixture that would not survive the uplink cannot
 * survive a test either. That discipline is the point: the property tests are
 * only worth anything if the values they quantify over are values the engine
 * could actually receive.
 *
 * A capacity reading is a complete fixture. That is the whole claim of the
 * design: the release evaluator reads its state and one reading and nothing
 * else, so fabricating a reading fabricates the world.
 */
import { Schema } from "effect";
import { BacklogItem } from "../src/schema/backlog.ts";
import { CapacityReading } from "../src/schema/capacity.ts";
import { Catalog } from "../src/schema/catalog.ts";
import { EstimateTable, Estimate } from "../src/schema/estimate.ts";
import { LevelList } from "../src/schema/levels.ts";
import { NamespaceTable } from "../src/schema/namespace.ts";
import { PlanRow } from "../src/schema/plan.ts";
import { PriceVector } from "../src/schema/prices.ts";
import { Rows } from "../src/schema/rows.ts";
import { Worklist } from "../src/schema/worklist.ts";
import {
  ExecutorId,
  FamilyName,
  LevelName,
  NamespaceName,
  RowName,
  TaskId
} from "../src/schema/ids.ts";
import type { FillerLane } from "../src/heuristics/fillerLane.ts";
import {
  defaultReleasePolicy,
  type ReleasePolicy,
  type ReleaseState
} from "../src/release/evaluator.ts";

const decodeBacklogItem = Schema.decodeUnknownSync(BacklogItem);
const decodeCapacityReading = Schema.decodeUnknownSync(CapacityReading);
const decodeCatalog = Schema.decodeUnknownSync(Catalog);
const decodeEstimate = Schema.decodeUnknownSync(Estimate);
const decodeEstimateTable = Schema.decodeUnknownSync(EstimateTable);
const decodeLevelList = Schema.decodeUnknownSync(LevelList);
const decodeNamespaceTable = Schema.decodeUnknownSync(NamespaceTable);
const decodePlanRow = Schema.decodeUnknownSync(PlanRow);
const decodePriceVector = Schema.decodeUnknownSync(PriceVector);
const decodeRows = Schema.decodeUnknownSync(Rows);
const decodeWorklist = Schema.decodeUnknownSync(Worklist);

/** Parses a level name, so a test never asserts a bare string into a brand. */
export const levelName = Schema.decodeUnknownSync(LevelName);
/** Parses a family name. */
export const familyName = Schema.decodeUnknownSync(FamilyName);
/** Parses a namespace name. */
export const namespaceName = Schema.decodeUnknownSync(NamespaceName);
/** Parses a row name. */
export const rowName = Schema.decodeUnknownSync(RowName);
/** Parses a task id. */
export const taskId = Schema.decodeUnknownSync(TaskId);
/** Parses an executor id. */
export const executorId = Schema.decodeUnknownSync(ExecutorId);

/** A sha-256 digest of the right shape, distinguished by one nibble. */
export const digest = (nibble: string): string => nibble.repeat(64).slice(0, 64);

/** The two GPU device rows, the build lane and the metered seat rows. */
export const rows = decodeRows([
  { name: "gpu-coordinator", kind: "vram", capacity: 1, metered: false },
  { name: "gpu-worker", kind: "vram", capacity: 1, metered: false },
  { name: "build", kind: "build-slot", capacity: 1, metered: false },
  { name: "claude-lanes", kind: "slot", capacity: 4, metered: false },
  { name: "claude-budget", kind: "budget", capacity: 4, metered: true },
  // Declared only by the cloud-side executor. The row table is the union across
  // executors; which executor declares which row is what a reading says.
  { name: "cloud-slot", kind: "cpu-slot", capacity: 2, metered: false }
]);

/**
 * A catalog with one free member on each device row and one metered member.
 *
 * The shipped catalog on the box has two members both naming the same
 * capacity-one row, so a family-diverse quorum of two runs serially. This
 * fixture is the shape that fixes it: one member per device.
 */
export const catalog = decodeCatalog({
  hash: digest("a"),
  members: [
    {
      id: "qwen-general",
      model: "qwen3.6-35b-a3b",
      agentKind: "pi",
      maker: "alibaba",
      classes: ["review", "execute"],
      rows: ["gpu-coordinator"],
      metered: false
    },
    {
      id: "gemma-coding",
      model: "gemma4-26b-a4b-qat",
      agentKind: "pi",
      maker: "google",
      classes: ["review", "execute"],
      rows: ["gpu-worker"],
      metered: false
    },
    {
      id: "opus-lane",
      model: "opus",
      agentKind: "claude-code",
      maker: "anthropic",
      classes: ["review", "execute", "chromium"],
      rows: ["claude-lanes", "claude-budget"],
      metered: true
    },
    {
      // A member that exists only on the cloud-side executor. The catalog says
      // which rows it needs and nothing about where those rows are; the reading
      // is what decides where it can run.
      id: "qwen-cloud",
      model: "qwen3.6-35b-a3b",
      agentKind: "pi",
      maker: "alibaba",
      classes: ["review", "execute"],
      rows: ["cloud-slot"],
      metered: false
    }
  ]
});

/** An estimate with the given yield and service scale. */
export const estimate = (
  yieldRate: number,
  medianSeconds: number,
  consumption: number
): typeof Estimate.Type =>
  decodeEstimate({
    medianSeconds,
    p80Seconds: medianSeconds * 1.6,
    p99Seconds: medianSeconds * 4,
    p80Consumption: consumption,
    yieldRate,
    observations: 40,
    shrinkageWeight: 0.8
  });

/** Estimates that make every free member usable and every cell informative. */
export const estimates = decodeEstimateTable({
  cells: [],
  mainEffect: {
    medianSeconds: 600,
    p80Seconds: 960,
    p99Seconds: 2400,
    p80Consumption: 5,
    yieldRate: 0.4,
    observations: 40,
    shrinkageWeight: 0.8
  }
});

/** Two preemptive levels, strongest first. */
export const levels = decodeLevelList({
  hash: digest("b"),
  levels: [
    { name: "approved", ordinal: 0, families: ["build"], wipCap: 8 },
    { name: "maintenance", ordinal: 1, families: ["upkeep"], wipCap: 2 }
  ]
});

/**
 * The same two levels with the filler lane beneath them (W-04, D-B10).
 *
 * The filler level is the lowest ordinal and its two goal families ARE the two
 * fillers, in the order they alternate. `docs/levels.md` is the document these
 * three rows are the fixture of.
 */
export const fillerLevels = decodeLevelList({
  hash: digest("b"),
  levels: [
    { name: "approved", ordinal: 0, families: ["build"], wipCap: 8 },
    { name: "maintenance", ordinal: 1, families: ["upkeep"], wipCap: 2 },
    { name: "filler", ordinal: 2, families: ["e1-replay", "academic-drain"], wipCap: 1 }
  ]
});

/**
 * One member, on the filler lane's row and nowhere else.
 *
 * The shipped fixture catalog offers a second device row, which is the right
 * shape for the routing tests and the wrong one for a test that has to say
 * WHICH row an admit took: with two free devices the router's choice, not the
 * rule under test, decides where an item lands.
 */
export const laneCatalog = decodeCatalog({
  hash: digest("a"),
  members: [
    {
      id: "coordinator-only",
      model: "local-coordinator",
      agentKind: "local",
      maker: "local",
      classes: ["review", "execute"],
      rows: ["gpu-coordinator"],
      metered: false
    }
  ]
});

/** The lane itself, carrying D-B10's three numbers and nothing derived. */
export const fillerLane: FillerLane = {
  level: levelName("filler"),
  row: rowName("gpu-coordinator"),
  promoteAfter: 10,
  promoteTo: levelName("approved"),
  abortOnConsecutiveCrash: 2
};

/** Two namespaces with equal shares. */
export const namespaces = decodeNamespaceTable({
  hash: digest("c"),
  namespaces: [
    {
      name: "mecattaf/conwip",
      wipShare: 1,
      value: 10,
      holdingCost: 0.1,
      defaultMember: null
    },
    {
      name: "mecattaf/dotfiles",
      wipShare: 1,
      value: 10,
      holdingCost: 0.1,
      defaultMember: null
    }
  ]
});

/** Every row priced, with the free device rows near zero. */
export const prices = decodePriceVector({
  hash: digest("d"),
  rows: [
    { row: "gpu-coordinator", price: 0 },
    { row: "gpu-worker", price: 0 },
    { row: "build", price: 0 },
    { row: "claude-lanes", price: 0 },
    { row: "claude-budget", price: 0.01 },
    { row: "cloud-slot", price: 0 }
  ],
  drum: 100,
  stage: [{ family: "build", holdingCost: 0.1 }]
});

/**
 * One armed plan.
 *
 * No repository, no revision and no path: the artifact was handed to the object,
 * hashed there, and that digest is the authority every admit carries.
 */
export const armedPlan = decodePlanRow({
  planId: "plan-1",
  planHash: digest("e"),
  arm: {
    label: "night.js",
    kind: "workflow",
    level: "approved",
    namespace: "mecattaf/conwip",
    planHash: digest("e"),
    author: "tom"
  },
  status: "armed",
  attemptCap: null
});

/** One backlog item, with everything the evaluator needs. */
export const item = (overrides: {
  readonly taskId: string;
  readonly planId?: string;
  readonly namespace?: string;
  readonly family?: string;
  readonly level?: string;
  readonly rank?: number;
  readonly value?: number;
  readonly needs?: string;
  readonly medianSeconds?: number;
  readonly yieldRate?: number;
  readonly consumption?: number;
  readonly subassembly?: string | null;
  readonly gate?: "mechanical" | "human";
  readonly deferrals?: number;
  readonly passedOver?: number;
  readonly dependsOn?: ReadonlyArray<string>;
  readonly state?: "unclaimed" | "released" | "inflight" | "closed";
  readonly attempt?: number;
  readonly outcome?: "pass" | "fail" | "cancelled" | "preempted" | "expired" | null;
  readonly argv_ref?: string;
  readonly mutation_hint?: string;
}): typeof BacklogItem.Type =>
  decodeBacklogItem({
    taskId: overrides.taskId,
    planId: overrides.planId ?? "plan-1",
    namespace: overrides.namespace ?? "mecattaf/conwip",
    family: overrides.family ?? "build",
    level: overrides.level ?? "approved",
    rank: overrides.rank ?? 0,
    needs: overrides.needs ?? "review",
    dependsOn: overrides.dependsOn ?? [],
    evidence: ["exit:0"],
    briefHash: digest("f"),
    planHash: digest("e"),
    dedupKey: `dedup-${overrides.taskId}`,
    ...(overrides.argv_ref === undefined ? {} : { argv_ref: overrides.argv_ref }),
    ...(overrides.mutation_hint === undefined
      ? {}
      : { mutation_hint: overrides.mutation_hint }),
    state: overrides.state ?? "unclaimed",
    deferrals: overrides.deferrals ?? 0,
    passedOver: overrides.passedOver ?? 0,
    attempt: overrides.attempt ?? 1,
    outcome: overrides.outcome ?? null,
    value: overrides.value ?? 10,
    estimate: {
      medianSeconds: overrides.medianSeconds ?? 600,
      p80Seconds: (overrides.medianSeconds ?? 600) * 1.6,
      p99Seconds: (overrides.medianSeconds ?? 600) * 4,
      p80Consumption: overrides.consumption ?? 5,
      yieldRate: overrides.yieldRate ?? 0.5,
      observations: 40,
      shrinkageWeight: 0.8
    },
    gate: overrides.gate ?? "mechanical",
    subassembly: overrides.subassembly ?? null,
    dueBy: null,
    float: null,
    envelopeParent: null
  });

/**
 * A capacity reading from the local rail, with the given free holders on each
 * device row.
 *
 * The local rail is the executor that declares the device rows and the metered
 * seats, because those are the two things only the box can present.
 */
export const reading = (overrides: {
  readonly seq?: number;
  readonly gpuHolders?: number;
  readonly signal?: "GO" | "SLOW" | "STOP";
  readonly freshness?: "fresh" | "stale";
  readonly regime?: "attended" | "unattended";
  readonly outerRemaining?: number;
  readonly windowsRemaining?: number;
  readonly innerCap?: number;
  readonly resident?: ReadonlyArray<string>;
  readonly stations?: ReadonlyArray<{
    readonly member: string;
    readonly state: "idle" | "working" | "blocked" | "unknown";
  }>;
  readonly nextWindowAt?: string;
}): typeof CapacityReading.Type =>
  decodeCapacityReading({
    executor: "coordinator",
    seq: overrides.seq ?? 1,
    rows: [
      {
        row: "gpu-coordinator",
        holders: overrides.gpuHolders ?? 0,
        capacity: 1,
        signal: overrides.signal ?? "GO",
        remainingBudget: null,
        ...(overrides.nextWindowAt === undefined
          ? {}
          : { next_window_at: overrides.nextWindowAt })
      },
      {
        row: "gpu-worker",
        holders: overrides.gpuHolders ?? 0,
        capacity: 1,
        signal: overrides.signal ?? "GO",
        remainingBudget: null
      },
      { row: "build", holders: 0, capacity: 1, signal: "GO", remainingBudget: null },
      {
        row: "claude-lanes",
        holders: 0,
        capacity: 4,
        signal: overrides.signal ?? "GO",
        remainingBudget: null
      },
      {
        row: "claude-budget",
        holders: 0,
        capacity: 4,
        signal: overrides.signal ?? "GO",
        remainingBudget: 1000
      }
    ],
    freshness: overrides.freshness ?? "fresh",
    envelope: {
      outerRemaining: overrides.outerRemaining ?? 10000,
      windowsRemaining: overrides.windowsRemaining ?? 100,
      innerCap: overrides.innerCap ?? 500,
      windowsPerEnvelope: 235
    },
    residentMembers: overrides.resident ?? [],
    stations: overrides.stations ?? [],
    regime: overrides.regime ?? "unattended"
  });

/**
 * A capacity reading from a cloud-side executor.
 *
 * It declares one ordinary slot row and neither device row nor seat, which is
 * the whole of what makes it different: an item whose member needs a GPU or a
 * Claude seat finds no such row here and defers, by the same rule that defers on
 * a busy row.
 */
export const cloudReading = (overrides: {
  readonly seq?: number;
  readonly holders?: number;
  readonly signal?: "GO" | "SLOW" | "STOP";
  readonly regime?: "attended" | "unattended";
  readonly nextWindowAt?: string;
}): typeof CapacityReading.Type =>
  decodeCapacityReading({
    executor: "cloud-sandbox",
    seq: overrides.seq ?? 1,
    rows: [
      {
        row: "cloud-slot",
        holders: overrides.holders ?? 0,
        capacity: 2,
        signal: overrides.signal ?? "GO",
        remainingBudget: null,
        ...(overrides.nextWindowAt === undefined
          ? {}
          : { next_window_at: overrides.nextWindowAt })
      }
    ],
    freshness: "fresh",
    envelope: {
      outerRemaining: 0,
      windowsRemaining: 100,
      innerCap: 0,
      windowsPerEnvelope: 235
    },
    residentMembers: [],
    stations: [],
    regime: overrides.regime ?? "unattended"
  });

/**
 * The tunables, with nothing that binds unless a test makes it bind.
 *
 * Built from the documented defaults so a test that wants a different policy
 * states only the field it is testing, and so a new policy field cannot be added
 * without deciding what its default is.
 */
export const policy: ReleasePolicy = defaultReleasePolicy;

/** A complete release state around a backlog. */
export const releaseState = (
  backlog: ReadonlyArray<typeof BacklogItem.Type>,
  overrides?: Partial<ReleaseState>
): ReleaseState => ({
  backlog,
  plans: [armedPlan],
  levels,
  namespaces,
  prices,
  rows,
  catalog,
  estimates,
  wip: [],
  caps: [],
  envelopes: [],
  buffers: [],
  inventory: [],
  subassemblies: [],
  policy,
  ...overrides
});

/** A worklist with a conflict domain, so the disjunctive graph differs from the DAG. */
export const worklist = decodeWorklist({
  campaignId: "campaign-1",
  planHash: digest("e"),
  maxParallel: 4,
  tasks: [
    {
      taskId: "t1",
      dependencies: [],
      conflictDomains: ["schema"],
      needs: "review",
      durationSeconds: 100,
      rank: 0,
      gate: "mechanical"
    },
    {
      taskId: "t2",
      dependencies: [],
      conflictDomains: ["schema"],
      needs: "review",
      durationSeconds: 100,
      rank: 1,
      gate: "mechanical"
    },
    {
      taskId: "t3",
      dependencies: [],
      conflictDomains: ["schema"],
      needs: "review",
      durationSeconds: 100,
      rank: 2,
      gate: "mechanical"
    },
    {
      taskId: "t4",
      dependencies: ["t1"],
      conflictDomains: [],
      needs: "review",
      durationSeconds: 50,
      rank: 3,
      gate: "mechanical"
    }
  ]
});
