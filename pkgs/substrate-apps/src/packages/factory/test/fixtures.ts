import { Effect, Schema } from "effect";
import {
  artifactHasherTableLayer,
  makeFactory,
  planningStoreInMemoryLayer,
  type ArmedArtifact,
  type IFactory
} from "../src/index.ts";
import { AdmitOutcomeReport } from "@substrate/planning/schema/admit.ts";
import { Heartbeat } from "@substrate/planning/schema/uplink.ts";
import { PlanArm } from "@substrate/planning/schema/plan.ts";
import { Verdict } from "@substrate/planning/schema/records.ts";
import { Sha256Hex } from "@substrate/planning/schema/ids.ts";
import type { ReleaseState } from "@substrate/planning/release/evaluator.ts";
import {
  digest,
  item,
  reading,
  releaseState
} from "../../planning/test/fixtures.ts";

const decodeOutcome = Schema.decodeUnknownSync(AdmitOutcomeReport);
const decodeHeartbeat = Schema.decodeUnknownSync(Heartbeat);
const decodePlanArm = Schema.decodeUnknownSync(PlanArm);
const decodeVerdict = Schema.decodeUnknownSync(Verdict);
const decodeSha = Schema.decodeUnknownSync(Sha256Hex);

export { digest, item, reading, releaseState };

export const artifactBytes = Uint8Array.of(1, 2, 3, 4);
export const artifactDigest = decodeSha(digest("e"));

export const armRequest = decodePlanArm({
  label: "night.js",
  kind: "workflow",
  level: "approved",
  namespace: "mecattaf/conwip",
  planHash: artifactDigest,
  author: "tom"
});

export const factoryFor = (
  items: ReleaseState["backlog"],
  overrides: Partial<ReleaseState> = {}
): Promise<IFactory> =>
  Effect.runPromise(
    makeFactory(releaseState(items, overrides)).pipe(
      Effect.provide(planningStoreInMemoryLayer)
    )
  );

export const emptyFactory = (): Promise<IFactory> =>
  factoryFor([], { plans: [] });

export const armItems = (
  factory: IFactory,
  items: ArmedArtifact["items"]
): Promise<unknown> =>
  Effect.runPromise(
    factory
      .armPlan(armRequest, {
        planId: items[0]?.planId ?? item({ taskId: "placeholder" }).planId,
        bytes: artifactBytes,
        items
      })
      .pipe(Effect.provide(artifactHasherTableLayer([[artifactBytes, artifactDigest]])))
  );

export const report = (
  taskId: string,
  outcome: "Accepted" | "Rejected" | "NotYet",
  extra: Record<string, unknown> = {}
) =>
  decodeOutcome({
    taskId,
    dedupKey: `dedup-${taskId}`,
    outcome,
    row: "gpu-coordinator",
    ...extra
  });

export const verdict = (
  taskId: string,
  outcome: "pass" | "fail" | "cancelled" | "preempted" | "expired",
  sequence = 1,
  extra: Record<string, unknown> = {}
) =>
  decodeVerdict({
    _tag: "Verdict",
    taskId,
    executor: "coordinator",
    seq: sequence,
    hash: digest(String(sequence % 10)),
    prevHash: digest(String(Math.max(0, sequence - 1) % 10)),
    outcome,
    serviceSeconds: 1,
    ...extra
  });

export const heartbeat = (taskId: string | null, sequence = 1) =>
  decodeHeartbeat({
    _tag: "Heartbeat",
    executor: "coordinator",
    taskId,
    seq: sequence
  });

export const run = <A, E>(effect: Effect.Effect<A, E>): Promise<A> =>
  Effect.runPromise(effect);
