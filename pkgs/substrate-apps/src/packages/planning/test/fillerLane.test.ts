/**
 * The filler lane — spec §4.4's executor-side contract, on the station's side.
 *
 * Three clauses and one non-clause:
 *
 *   the two fillers alternate by round-robin       (D-B10)
 *   a filler passed over 10 times is promoted      (D-B10, TL-10)
 *   a row its own filler saturates is preemptible  (§4.4 clause 1)
 *   a floor with no filler lane behaves as before  (the absence is the default)
 *
 * `tools/batch-replay.mjs` is the same three clauses over a real socket and a
 * real reading; these are the same clauses over a fabricated one, which is what
 * makes each of them separable from the replay that exercises them together.
 */
import { Effect, Option } from "effect";
import { describe, expect, it } from "vitest";
import { Factory, factoryTestLayer } from "../src/objects/index.ts";
import {
  agedIntoPromotion,
  fillerSources,
  fillerTaskIds,
  fillerTurn,
  passedOverBy,
  preemptibleHolders,
  promoteAgedFillers
} from "../src/heuristics/fillerLane.ts";
import { evaluateRelease, type ReleaseState } from "../src/release/evaluator.ts";
import {
  digest,
  executorId,
  familyName,
  fillerLane,
  fillerLevels,
  item,
  laneCatalog,
  reading,
  releaseState,
  rowName,
  taskId
} from "./fixtures.ts";

/** A backlog item on the filler lane. */
const filler = (
  taskId: string,
  source: "e1-replay" | "academic-drain",
  overrides: {
    readonly passedOver?: number;
    readonly attempt?: number;
    readonly state?: "unclaimed" | "released" | "inflight" | "closed";
    readonly rank?: number;
  } = {}
) =>
  item({
    taskId,
    level: "filler",
    family: source,
    needs: "execute",
    rank: overrides.rank ?? 0,
    ...overrides
  });

/** A release state carrying the lane and the three-level document. */
const laneState = (
  backlog: ReadonlyArray<ReturnType<typeof item>>,
  overrides: Partial<ReleaseState> = {}
): ReleaseState =>
  releaseState(backlog, { levels: fillerLevels, filler: fillerLane, ...overrides });

describe("the filler lane: the two fillers", () => {
  it("reads the two fillers off the filler level, in declared order", () => {
    expect(fillerSources(fillerLevels, fillerLane)).toEqual([
      "e1-replay",
      "academic-drain"
    ]);
  });

  it("declares no filler when no lane is declared", () => {
    expect(fillerSources(fillerLevels, undefined)).toEqual([]);
  });

  it("gives the first turn to the first filler the document declares", () => {
    const turn = fillerTurn(
      [filler("f1", "e1-replay"), filler("f2", "academic-drain")],
      fillerLane,
      fillerSources(fillerLevels, fillerLane)
    );
    expect(Option.getOrNull(turn)).toBe("e1-replay");
  });

  it("alternates: after one release the other filler is owed the row", () => {
    const turn = fillerTurn(
      [
        filler("f1", "e1-replay", { state: "closed" }),
        filler("f2", "academic-drain")
      ],
      fillerLane,
      fillerSources(fillerLevels, fillerLane)
    );
    expect(Option.getOrNull(turn)).toBe("academic-drain");
  });

  it("counts a preempted release, so a yielded filler does not run twice in a row", () => {
    // The item came back to the backlog on `attempt 2`: it was released once,
    // and the round-robin must remember that even though it is unclaimed again.
    const turn = fillerTurn(
      [
        filler("f1", "e1-replay", { attempt: 2 }),
        filler("f2", "academic-drain")
      ],
      fillerLane,
      fillerSources(fillerLevels, fillerLane)
    );
    expect(Option.getOrNull(turn)).toBe("academic-drain");
  });

  it("gives the row to the only filler with work left", () => {
    const turn = fillerTurn(
      [filler("f1", "e1-replay"), filler("f2", "academic-drain", { state: "closed" })],
      fillerLane,
      fillerSources(fillerLevels, fillerLane)
    );
    expect(Option.getOrNull(turn)).toBe("e1-replay");
  });

  it("defers the filler whose turn it is not, and names the turn", () => {
    const decision = evaluateRelease(
      laneState([filler("f1", "e1-replay"), filler("f2", "academic-drain")]),
      reading({})
    );

    expect(decision.admits.map((admit) => admit.taskId)).toEqual(["f1"]);
    const deferral = decision.deferrals.find((entry) => entry.taskId === "f2");
    expect(deferral?.rule).toBe("fillerAlternation");
    expect(deferral?.detail).toBe("e1-replay");
  });
});

describe("the filler lane: age-based promotion (D-B10)", () => {
  it("promotes at ten passes and not at nine", () => {
    expect(agedIntoPromotion(filler("f1", "e1-replay", { passedOver: 9 }), fillerLane)).toBe(
      false
    );
    expect(agedIntoPromotion(filler("f1", "e1-replay", { passedOver: 10 }), fillerLane)).toBe(
      true
    );
  });

  it("promotes no item when no lane is declared", () => {
    expect(
      agedIntoPromotion(filler("f1", "e1-replay", { passedOver: 99 }), undefined)
    ).toBe(false);
  });

  it("rewrites the level for the pass and leaves the backlog item alone", () => {
    const aged = filler("f1", "e1-replay", { passedOver: 10 });
    const promoted = promoteAgedFillers([aged], fillerLane);

    expect(promoted[0]?.level).toBe("approved");
    expect(aged.level).toBe("filler");
  });

  it("proposes a promoted filler at level one", () => {
    const decision = evaluateRelease(
      laneState([filler("f1", "e1-replay", { passedOver: 10 })]),
      reading({})
    );
    expect(decision.admits[0]?.level).toBe("approved");
  });

  it("proposes an un-aged filler at the filler level", () => {
    const decision = evaluateRelease(
      laneState([filler("f1", "e1-replay", { passedOver: 9 })]),
      reading({})
    );
    expect(decision.admits[0]?.level).toBe("filler");
  });

  it("counts only non-filler admits that took the lane's row", () => {
    const fillers = fillerTaskIds([filler("f1", "e1-replay")], fillerLane);
    const admits = [
      { taskId: taskId("w1"), rows: [{ row: rowName("gpu-coordinator") }] },
      { taskId: taskId("w2"), rows: [{ row: rowName("gpu-worker") }] },
      { taskId: taskId("f1"), rows: [{ row: rowName("gpu-coordinator") }] }
    ];
    expect(passedOverBy(admits, fillers, fillerLane)).toBe(1);
  });
});

describe("the filler lane: preemption (§4.4 clause 1)", () => {
  /** The station's own filler, out on the lane's row, as the door sees it. */
  const held = filler("f1", "e1-replay", { state: "inflight" });
  /** A level-one item that wants the same row. */
  const arriving = item({ taskId: "w1", level: "approved", needs: "execute", rank: 0 });
  /** The floor a moment after the filler took the row: saturated, and STOP. */
  const saturated = reading({ gpuHolders: 1, signal: "STOP" });

  it("counts the station's own filler holders and nothing else", () => {
    expect(preemptibleHolders([held, arriving], fillerLane)).toBe(1);
    expect(preemptibleHolders([arriving], fillerLane)).toBe(0);
    expect(preemptibleHolders([held], undefined)).toBe(0);
  });

  it("proposes the higher item against a row its own filler saturates", () => {
    const decision = evaluateRelease(laneState([held, arriving]), saturated);
    const admit = decision.admits.find((entry) => entry.taskId === "w1");

    expect(admit).toBeDefined();
    expect(admit?.rows.map((request) => request.row)).toContain("gpu-coordinator");
  });

  it("defers on the same floor when no filler is holding it", () => {
    const decision = evaluateRelease(
      laneState([arriving], { filler: fillerLane }),
      saturated
    );

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.find((entry) => entry.taskId === "w1")?.rule).toBe(
      "capacityRow"
    );
  });

  it("never lets a filler preempt a filler", () => {
    const decision = evaluateRelease(
      laneState([held, filler("f2", "academic-drain")]),
      saturated
    );
    expect(decision.admits).toEqual([]);
  });

  it("releases at most one item onto the preempted row in one pass", () => {
    const decision = evaluateRelease(
      laneState([
        held,
        arriving,
        item({ taskId: "w2", level: "approved", needs: "execute", rank: 1 })
      ]),
      saturated
    );
    expect(decision.admits).toHaveLength(1);
  });
});

describe("the filler lane: the counter the Factory maintains", () => {
  /** One executor, one row, so an admit's row is the rule's and not the router's. */
  const withLane = (backlog: ReadonlyArray<ReturnType<typeof item>>) =>
    (effect: Effect.Effect<void, unknown, Factory>) =>
      Effect.runPromise(
        effect.pipe(
          Effect.provide(factoryTestLayer(laneState(backlog, { catalog: laneCatalog })))
        ) as Effect.Effect<void, never, never>
      );

  const worker = (taskId: string, rank: number) =>
    item({ taskId, level: "approved", needs: "execute", rank });

  it("ages every filler the pass passed over on the lane's row", () =>
    withLane([worker("w1", 0), filler("f1", "e1-replay", { rank: 1 }), filler("f2", "academic-drain", { rank: 2 })])(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.observeCapacity(reading({}));
        const handed = yield* factory.handOut(executorId("coordinator"));
        expect(handed.map((proposal) => proposal.taskId)).toEqual(["w1"]);

        const state = yield* factory.releaseState;
        const aged = (taskId: string) =>
          state.backlog.find((entry) => entry.taskId === taskId)?.passedOver;
        expect(aged("f1")).toBe(1);
        expect(aged("f2")).toBe(1);
        // The worker item is not a filler and carries no age.
        expect(aged("w1")).toBe(0);
      })
    ));

  it("resets the counter when the filler is the one released", () =>
    withLane([filler("f1", "e1-replay", { passedOver: 10 })])(
      Effect.gen(function* () {
        const factory = yield* Factory;
        yield* factory.observeCapacity(reading({}));
        const handed = yield* factory.handOut(executorId("coordinator"));

        // Promoted for exactly this release: the proposal carries level one.
        expect(handed.map((proposal) => proposal.level)).toEqual(["approved"]);
        const state = yield* factory.releaseState;
        expect(state.backlog[0]?.passedOver).toBe(0);
      })
    ));

  it("ages by ten over ten passes and promotes on the eleventh", () =>
    withLane([
      ...Array.from({ length: 10 }, (_unused, index) => worker(`w${index}`, index)),
      filler("f1", "e1-replay", { rank: 20 })
    ])(
      Effect.gen(function* () {
        const factory = yield* Factory;
        const ageOf = Effect.gen(function* () {
          const state = yield* Factory.pipe(Effect.flatMap((f) => f.releaseState));
          return state.backlog.find((entry) => entry.taskId === "f1")?.passedOver ?? -1;
        });

        // Ten passes, each of which takes the lane's one row with a worker item
        // and closes it, so the filler is passed over exactly ten times.
        for (let pass = 0; pass < 10; pass += 1) {
          yield* factory.observeCapacity(reading({ seq: pass + 1 }));
          const handed = yield* factory.handOut(executorId("coordinator"));
          expect(handed).toHaveLength(1);
          expect(handed[0]?.taskId).toBe(`w${pass}`);
          yield* factory.observeOutcome({
            taskId: handed[0]!.taskId,
            dedupKey: handed[0]!.dedupKey,
            outcome: "Accepted",
            row: "gpu-coordinator"
          });
          yield* factory.observeVerdict({
            _tag: "Verdict",
            taskId: handed[0]!.taskId,
            executor: "coordinator",
            seq: pass + 1,
            hash: digest(String((pass + 1) % 10)),
            prevHash: digest(String(pass % 10)),
            outcome: "pass",
            serviceSeconds: 1
          } as never);
        }
        expect(yield* ageOf).toBe(10);

        // The eleventh pass has no worker item left, and the filler that has
        // been passed over ten times is proposed at level one.
        yield* factory.observeCapacity(reading({ seq: 11 }));
        const promoted = yield* factory.handOut(executorId("coordinator"));
        expect(promoted.map((proposal) => proposal.taskId)).toEqual(["f1"]);
        expect(promoted[0]?.level).toBe("approved");
      })
    ));
});

describe("the filler lane: its absence", () => {
  it("changes nothing on a floor that declares none", () => {
    const withoutLane = releaseState([
      filler("f1", "e1-replay"),
      filler("f2", "academic-drain")
    ], { levels: fillerLevels });
    const decision = evaluateRelease(withoutLane, reading({}));

    // Both filler items are ordinary candidates: no alternation, no promotion,
    // and the only thing that stops the second is the capacity-one device row.
    expect(
      decision.deferrals.every((entry) => entry.rule !== "fillerAlternation")
    ).toBe(true);
    expect(decision.admits.map((admit) => admit.taskId)).toContain("f1");
  });

  it("keeps the family name a parsed brand, never a bare string", () => {
    expect(familyName("e1-replay")).toBe("e1-replay");
  });
});
