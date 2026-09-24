/**
 * Arming, refusing, and the one piece of history the release rule reads.
 *
 * There is no forge here and no revision: `plan arm` hands the object the bytes,
 * the object hashes them through a capability, and that digest is the authority.
 * These tests state that the refusal is real — a mismatch is refused rather than
 * repaired — and that an artifact the hasher cannot hash arms nothing at all.
 */
import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  ArtifactHasher,
  artifactHasherTableLayer,
  Factory,
  factoryTestLayer,
  type ArmedArtifact
} from "../src/objects/index.ts";
import { PlanArm } from "../src/schema/plan.ts";
import { Sha256Hex } from "../src/schema/ids.ts";
import { cloudReading, digest, item, reading, releaseState } from "./fixtures.ts";

const decodePlanArm = Schema.decodeUnknownSync(PlanArm);
const sha = Schema.decodeUnknownSync(Sha256Hex);

/** The artifact's bytes, as they arrived over HTTPS. */
const bytes = Uint8Array.of(1, 2, 3, 4);
/** What the hasher will say those bytes hash to. */
const armedDigest = sha(digest("e"));

const arm = (planHash: string) =>
  decodePlanArm({
    label: "night.js",
    kind: "workflow",
    level: "approved",
    namespace: "mecattaf/conwip",
    planHash,
    author: "tom"
  });

/**
 * What the artifact expands to.
 *
 * The plan id matches the items' own, because an item is a candidate only while
 * the plan that armed it is armed — which is exactly the check being relied on
 * here.
 */
const artifact: ArmedArtifact = {
  planId: item({ taskId: "t9" }).planId,
  bytes,
  items: [item({ taskId: "t9" })]
};

/** The state an object starts from, with no plans and no backlog. */
const empty = releaseState([], { plans: [] });

const withHasher = <A, E>(program: Effect.Effect<A, E, Factory | ArtifactHasher>) =>
  Effect.runPromise(
    program.pipe(
      Effect.provide(factoryTestLayer(empty)),
      Effect.provide(artifactHasherTableLayer([[bytes, armedDigest]]))
    ) as Effect.Effect<A, E, never>
  );

describe("arming a plan", () => {
  it("hashes the bytes it was handed and writes the row with that digest", () =>
    withHasher(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const row = yield* factory.armPlan(arm(armedDigest), artifact);

        expect(row.planHash).toBe(armedDigest);
        expect(row.status).toBe("armed");
        // No repository, no revision, no path: the row records a label and a
        // digest, and the digest is the authority.
        expect(Object.keys(row.arm)).not.toContain("repo");
        expect(Object.keys(row.arm)).not.toContain("rev");
      })
    ));

  it("refuses a mismatch rather than repairing it", () =>
    withHasher(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const failure = yield* Effect.result(
          factory.armPlan(arm(digest("a")), artifact)
        );

        expect(failure._tag).toBe("Failure");
        if (failure._tag !== "Failure") return;
        expect(failure.failure.reason).toBe("PlanHashMismatch");

        // And nothing was armed: a plan whose bytes are not the bytes that were
        // approved has no authority at all, so its items are not candidates.
        const state = yield* factory.releaseState;
        expect(state.plans).toEqual([]);
        expect(state.backlog).toEqual([]);
      })
    ));

  it("arms nothing when the bytes cannot be hashed", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const failure = yield* Effect.result(factory.armPlan(arm(armedDigest), artifact));
        expect(failure._tag).toBe("Failure");
      }).pipe(
        Effect.provide(factoryTestLayer(empty)),
        // A hasher that knows about no bytes at all: an unknown artifact must
        // refuse, never proceed under a fabricated digest.
        Effect.provide(artifactHasherTableLayer([]))
      ) as Effect.Effect<void, never, never>
    ));

  it("makes the armed plan's items candidates, and stamps its digest on the admit", () =>
    withHasher(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.armPlan(arm(armedDigest), artifact);

        const decision = yield* factory.evaluate(reading({}));
        expect(decision.admits.map((admit) => admit.taskId)).toEqual(["t9"]);
        expect(decision.admits[0]?.planHash).toBe(armedDigest);
      })
    ));
});

describe("the deferral counter the congestion policy reads", () => {
  it("counts a pass that passed an item over", () =>
    withHasher(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.armPlan(arm(armedDigest), artifact);

        // Both device rows held: the item is passed over.
        const decision = yield* factory.evaluate(reading({ gpuHolders: 1 }));
        expect(decision.admits).toEqual([]);
        yield* factory.recordDeferrals(decision.deferrals);

        const state = yield* factory.releaseState;
        expect(state.backlog[0]?.deferrals).toBe(1);

        // Twice deferred, twice counted. This is the only history the release
        // rule reads, and the Factory is the only thing that writes it.
        const again = yield* factory.evaluate(reading({ gpuHolders: 1 }));
        yield* factory.recordDeferrals(again.deferrals);
        expect((yield* factory.releaseState).backlog[0]?.deferrals).toBe(2);
      })
    ));

  it("evaluates across several executors from the object", () =>
    withHasher(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.armPlan(arm(armedDigest), artifact);

        const decision = yield* factory.evaluateAcross([
          reading({ gpuHolders: 1 }),
          cloudReading({})
        ]);

        // The rail could not take it; the cloud-side executor could. That is not
        // a deferral.
        expect(decision.admits[0]?.executor).toBe("cloud-sandbox");
        expect(decision.deferrals).toEqual([]);
        expect(decision.paces.length).toBe(2);
      })
    ));
});
