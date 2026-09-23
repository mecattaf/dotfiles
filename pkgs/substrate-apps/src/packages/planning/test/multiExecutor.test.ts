/**
 * Several executors, and the rules that only bite when there is more than one.
 *
 * A kernel is anything implementing the admit-and-witness contract with its own
 * single-writer chain: the local rail is one, a cloud-side sandbox is another.
 * These are the properties that a single-executor test cannot state — that work
 * lands where its rows are, that nothing is proposed twice, that the caps count
 * the whole fold, that the chains are verified apart, and that an executor
 * nobody can reach holds its work instead of losing it.
 */
import { Effect, Option, Ref, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  evaluateRelease,
  evaluateReleaseAcross
} from "../src/release/evaluator.ts";
import { conwipCaps } from "../src/heuristics/conwip.ts";
import {
  advanceMirror,
  emptyMirror,
  mirrorGaps
} from "../src/objects/mirror.ts";
import {
  Kernel,
  kernelTestLayer,
  makeFakeKernelLink,
  makeKernel,
  KernelLink,
  type IKernelLink
} from "../src/objects/kernel.ts";
import type { Admit } from "../src/schema/admit.ts";
import { KernelLinkError } from "../src/schema/errors.ts";
import { Verdict } from "../src/schema/records.ts";
import { ExecutorId, Seq } from "../src/schema/ids.ts";
import { cloudReading, digest, item, levelName, reading, releaseState } from "./fixtures.ts";

const executorId = Schema.decodeUnknownSync(ExecutorId);
const decodeVerdict = Schema.decodeUnknownSync(Verdict);
const seqNo = Schema.decodeUnknownSync(Seq);

const taskIds = (values: ReadonlyArray<{ readonly taskId: string }>): ReadonlyArray<string> =>
  values.map((value) => value.taskId);

const verdict = (fields: {
  readonly executor: string;
  readonly taskId: string;
  readonly seq: number;
  readonly hash: string;
  readonly prevHash: string;
}) =>
  decodeVerdict({
    _tag: "Verdict",
    taskId: fields.taskId,
    executor: fields.executor,
    seq: fields.seq,
    hash: digest(fields.hash),
    prevHash: digest(fields.prevHash),
    outcome: "pass",
    serviceSeconds: 120
  });

describe("release across several executors", () => {
  it("defers on an executor that does not declare the row, with no special case", () => {
    // The cloud-side executor declares one slot row and neither device row nor
    // seat. An item whose preferred member needs a GPU finds no such row and
    // falls out through the ordinary capacity gate.
    const local = evaluateRelease(releaseState([item({ taskId: "t1" })]), reading({}));
    expect(local.admits[0]?.member).toBe("qwen-general");

    const cloud = evaluateRelease(releaseState([item({ taskId: "t1" })]), cloudReading({}));
    expect(cloud.admits[0]?.member).toBe("qwen-cloud");
    expect(cloud.admits[0]?.executor).toBe("cloud-sandbox");
  });

  it("spills to a second executor once the first executor's rows are full", () => {
    // Two device rows on the box, two slots in the cloud: four items, all placed.
    const backlog = [
      item({ taskId: "t1", rank: 0 }),
      item({ taskId: "t2", rank: 1 }),
      item({ taskId: "t3", rank: 2 }),
      item({ taskId: "t4", rank: 3 })
    ];
    const decision = evaluateReleaseAcross(releaseState(backlog), [
      reading({}),
      cloudReading({})
    ]);

    const byExecutor = new Map<string, ReadonlyArray<string>>();
    for (const admit of decision.admits) {
      byExecutor.set(admit.executor, [...(byExecutor.get(admit.executor) ?? []), admit.taskId]);
    }
    expect(byExecutor.get("coordinator")).toEqual(["t1", "t2"]);
    expect(byExecutor.get("cloud-sandbox")).toEqual(["t3", "t4"]);
    expect(decision.deferrals).toEqual([]);
  });

  it("proposes each item to at most one executor", () => {
    const backlog = [item({ taskId: "t1" }), item({ taskId: "t2" })];
    const decision = evaluateReleaseAcross(releaseState(backlog), [
      reading({}),
      cloudReading({})
    ]);

    const seen = new Set<string>();
    for (const admit of decision.admits) {
      expect(seen.has(admit.taskId)).toBe(false);
      seen.add(admit.taskId);
    }
    expect(seen.size).toBe(2);
  });

  it("counts the caps across the whole fold, not once per executor", () => {
    // Four items and four free rows across two executors, but a cap of two: the
    // second executor must see the first executor's admits.
    const backlog = [
      item({ taskId: "t1", rank: 0 }),
      item({ taskId: "t2", rank: 1 }),
      item({ taskId: "t3", rank: 2 }),
      item({ taskId: "t4", rank: 3 })
    ];
    const state = releaseState(backlog, {
      caps: conwipCaps([[levelName("approved"), 2]], [], [])
    });
    const decision = evaluateReleaseAcross(state, [reading({}), cloudReading({})]);

    expect(decision.admits.length).toBe(2);
  });

  it("does not report an item as deferred when a later executor took it", () => {
    // Both device rows are held, so the local pass defers; the cloud pass runs
    // it. Counting that as a deferral would inflate the very number the
    // congestion policy reads.
    const decision = evaluateReleaseAcross(releaseState([item({ taskId: "t1" })]), [
      reading({ gpuHolders: 1 }),
      cloudReading({})
    ]);

    expect(taskIds(decision.admits)).toEqual(["t1"]);
    expect(decision.deferrals).toEqual([]);
  });

  it("keeps the deferral no executor resolved, with the first refusal's reason", () => {
    const decision = evaluateReleaseAcross(releaseState([item({ taskId: "t1" })]), [
      reading({ gpuHolders: 1 }),
      cloudReading({ holders: 2 })
    ]);

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.length).toBe(1);
    expect(decision.deferrals[0]?.rule).toBe("capacityRow");
    expect(decision.deferrals[0]?.detail).toBe("gpu-coordinator");
  });

  it("reports one pace line per executor", () => {
    const decision = evaluateReleaseAcross(releaseState([]), [
      reading({}),
      cloudReading({})
    ]);
    expect(decision.paces.map(([executor]) => executor)).toEqual([
      "coordinator",
      "cloud-sandbox"
    ]);
  });

  it("is deterministic in the order the readings are given", () => {
    const backlog = [item({ taskId: "t1", rank: 0 }), item({ taskId: "t2", rank: 1 })];
    const first = evaluateReleaseAcross(releaseState(backlog), [
      cloudReading({}),
      reading({})
    ]);
    const second = evaluateReleaseAcross(releaseState(backlog), [
      cloudReading({}),
      reading({})
    ]);

    expect(first.admits.map((admit) => [admit.taskId, admit.executor])).toEqual(
      second.admits.map((admit) => [admit.taskId, admit.executor])
    );
    // Reading the cloud first places the head of the backlog there, which is the
    // point of the order being the caller's and visible.
    expect(first.admits[0]?.executor).toBe("cloud-sandbox");
  });

  it("an executor that has not reported is simply absent, and its work waits", () => {
    const backlog = [item({ taskId: "t1" }), item({ taskId: "t2" }), item({ taskId: "t3" })];
    const decision = evaluateReleaseAcross(releaseState(backlog), [reading({})]);

    expect(decision.admits.length).toBe(2);
    // The third is deferred and still in the backlog; nothing invented a door
    // for it.
    expect(decision.deferrals.length).toBe(1);
  });
});

describe("the mirror, one chain per executor", () => {
  it("verifies each executor's chain separately", () => {
    const first = advanceMirror(
      emptyMirror,
      verdict({ executor: "coordinator", taskId: "t1", seq: 1, hash: "1", prevHash: "0" })
    );
    // A record from an executor the mirror has not seen is the first link of its
    // own chain, not a break in anyone else's.
    const second = advanceMirror(
      first.mirror,
      verdict({ executor: "cloud-sandbox", taskId: "t2", seq: 9, hash: "a", prevHash: "b" })
    );

    expect(first.continuous).toBe(true);
    expect(second.continuous).toBe(true);
    expect(mirrorGaps(second.mirror)).toEqual([]);
  });

  it("records a gap on the executor that has one and on no other", () => {
    let mirror = advanceMirror(
      emptyMirror,
      verdict({ executor: "coordinator", taskId: "t1", seq: 1, hash: "1", prevHash: "0" })
    ).mirror;
    mirror = advanceMirror(
      mirror,
      verdict({ executor: "cloud-sandbox", taskId: "c1", seq: 1, hash: "a", prevHash: "0" })
    ).mirror;

    // A skip on the coordinator's chain only.
    const skipped = advanceMirror(
      mirror,
      verdict({ executor: "coordinator", taskId: "t3", seq: 5, hash: "3", prevHash: "2" })
    );
    // And a clean continuation on the cloud's.
    const continued = advanceMirror(
      skipped.mirror,
      verdict({ executor: "cloud-sandbox", taskId: "c2", seq: 2, hash: "b", prevHash: "a" })
    );

    expect(skipped.continuous).toBe(false);
    expect(continued.continuous).toBe(true);
    const gaps = mirrorGaps(continued.mirror);
    expect(gaps.length).toBe(1);
    expect(gaps[0]?.executor).toBe("coordinator");
    expect(gaps[0]?.after).toBe(1);
    expect(gaps[0]?.before).toBe(5);
  });
});

describe("the Kernel object, one per executor", () => {
  const admitFor = (taskId: string) => {
    const decision = evaluateRelease(releaseState([item({ taskId })]), reading({}));
    const admit = decision.admits[0];
    if (admit === undefined) throw new Error("fixture produced no admit");
    return admit;
  };

  it("queues an admit to an unreachable executor and never drops it", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        const report = yield* kernel.dispatch([admitFor("t1"), admitFor("t2")]);

        // Nothing reached the door, nothing was answered, and both are held.
        expect(report.outcomes).toEqual([]);
        expect(taskIds(report.queued)).toEqual(["t1", "t2"]);
        const state = yield* kernel.state;
        expect(taskIds(state.queued)).toEqual(["t1", "t2"]);
        expect(state.inFlight).toEqual([]);
      }).pipe(
        Effect.provide(
          kernelTestLayer({ executor: executorId("coordinator"), reachable: false })
        )
      )
    ));

  it("re-sends what it queued when the executor comes back", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        // One link and one object throughout, with the executor going from
        // unreachable to reachable between the passes — which is what an alarm
        // retry actually sees.
        const reachable = yield* Ref.make(false);
        const delivered = yield* Ref.make<ReadonlyArray<Admit>>([]);
        const link: IKernelLink = {
          executor: executorId("coordinator"),
          admit: (admit) =>
            Ref.get(reachable).pipe(
              Effect.flatMap((up) =>
                up
                  ? Ref.update(delivered, (current) => [...current, admit]).pipe(
                      Effect.as({ _tag: "Accepted" as const, taskId: admit.taskId })
                    )
                  : Effect.fail(
                      new KernelLinkError({
                        reason: "Unreachable",
                        executor: "coordinator",
                        mayHaveArrived: false
                      })
                    )
              )
            ),
          cancel: () => Effect.void,
          steer: () => Effect.void,
          capacityRequest: Effect.succeed(reading({})),
          drainUp: Effect.succeed([])
        };

        const kernel = yield* makeKernel(executorId("coordinator")).pipe(
          Effect.provideService(KernelLink, link)
        );

        yield* kernel.dispatch([admitFor("t1"), admitFor("t2")]);
        expect(yield* Ref.get(delivered)).toEqual([]);
        expect((yield* kernel.state).queued.length).toBe(2);

        // The box comes back and the alarm fires.
        yield* Ref.set(reachable, true);
        const retried = yield* kernel.retryQueued;

        expect(retried.outcomes.length).toBe(2);
        expect(taskIds(yield* Ref.get(delivered))).toEqual(["t1", "t2"]);
        const state = yield* kernel.state;
        expect(state.queued).toEqual([]);
        expect(state.inFlight).toEqual(["t1", "t2"]);
      })
    ));

  it("delivers the queue in the order it was decided, and no more than once", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const fake = yield* makeFakeKernelLink({ executor: executorId("coordinator") });
        const kernel = yield* makeKernel(executorId("coordinator")).pipe(
          Effect.provideService(KernelLink, fake.link)
        );

        yield* kernel.dispatch([admitFor("t1"), admitFor("t2")]);
        // The queue is empty, so a later alarm sends nothing a second time.
        yield* kernel.retryQueued;

        expect(taskIds((yield* fake.log).admits)).toEqual(["t1", "t2"]);
      })
    ));

  it("retries the queue exactly once per alarm, without doubling it", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        yield* kernel.dispatch([admitFor("t1")]);
        const first = yield* kernel.retryQueued;
        const state = yield* kernel.state;

        // Still unreachable: the admit is re-queued, once, not twice.
        expect(taskIds(first.queued)).toEqual(["t1"]);
        expect(taskIds(state.queued)).toEqual(["t1"]);
      }).pipe(
        Effect.provide(
          kernelTestLayer({ executor: executorId("coordinator"), reachable: false })
        )
      )
    ));

  it("stops sending at the first failure rather than racing ahead of it", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        const report = yield* kernel.dispatch([admitFor("t1"), admitFor("t2")]);
        expect(report.outcomes).toEqual([]);
        expect(report.queued.length).toBe(2);
      }).pipe(
        Effect.provide(
          kernelTestLayer({ executor: executorId("coordinator"), reachable: false })
        )
      )
    ));

  it("takes a fresher reading and drops a stale one", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        expect(yield* kernel.observeCapacity(reading({ seq: 2 }))).toBe(true);
        expect(yield* kernel.observeCapacity(reading({ seq: 1 }))).toBe(false);

        const held = yield* kernel.lastReading;
        expect(Option.isSome(held) && held.value.seq).toBe(2);
      }).pipe(
        Effect.provide(kernelTestLayer({ executor: executorId("coordinator") }))
      )
    ));
});

describe("up-messages, the only door a herdr-shaped observation has", () => {
  it("folds a doubt into blocked lanes and a verdict back out again", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        yield* kernel.receive({
          _tag: "Doubt",
          executor: executorId("coordinator"),
          taskId: (yield* Effect.succeed(item({ taskId: "t1" }))).taskId,
          seq: seqNo(4),
          blockedSeconds: 90
        });
        expect((yield* kernel.state).blocked).toEqual(["t1"]);

        yield* kernel.receive(
          verdict({ executor: "coordinator", taskId: "t1", seq: 5, hash: "1", prevHash: "0" })
        );
        const state = yield* kernel.state;
        expect(state.blocked).toEqual([]);
        expect(state.offlineCursor).toBe(5);
      }).pipe(
        Effect.provide(kernelTestLayer({ executor: executorId("coordinator") }))
      )
    ));

  it("drains what the executor posted, in order, and folds all of it", () =>
    Effect.runPromise(
      Effect.gen(function* () {
        const kernel = yield* Kernel;
        const drained = yield* kernel.drain;

        expect(drained.map((message) => message._tag)).toEqual([
          "Heartbeat",
          "CapacityReading"
        ]);
        // The reading arrived as an up-message and is now the object's own.
        const held = yield* kernel.lastReading;
        expect(Option.isSome(held) && held.value.seq).toBe(7);
        // A second drain finds nothing: messages are taken, not replayed.
        expect(yield* kernel.drain).toEqual([]);
      }).pipe(
        Effect.provide(
          kernelTestLayer({
            executor: executorId("coordinator"),
            up: [
              {
                _tag: "Heartbeat",
                executor: executorId("coordinator"),
                taskId: Option.none(),
                seq: seqNo(6)
              },
              { _tag: "CapacityReading", reading: reading({ seq: 7 }) }
            ]
          })
        )
      )
    ));

  it("carries station occupancy as a reading, never as proof", () => {
    // herdr's four states reach the lake here and nowhere else, and the release
    // rule reads the reading, not the pane.
    const observed = reading({
      stations: [
        { member: "qwen-general", state: "blocked" },
        { member: "gemma-coding", state: "working" }
      ]
    });
    expect(observed.stations.length).toBe(2);
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), observed);
    // A blocked station is an observation about a human, not a capacity signal:
    // the row is still free and the item still releases.
    expect(taskIds(decision.admits)).toEqual(["t1"]);
  });
});
