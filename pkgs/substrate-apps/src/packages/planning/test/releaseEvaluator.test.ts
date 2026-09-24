/**
 * The release evaluator, tested against fabricated capacity readings.
 *
 * This is the test the mutex incident's code could not have had. Every property
 * here is one of the invariants stated in the design, quantified over
 * arbitrary readings and backlogs.
 */
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { evaluateRelease } from "../src/release/evaluator.ts";
import { conwipCaps } from "../src/heuristics/conwip.ts";
import {
  armedPlan,
  familyName,
  item,
  levelName,
  policy,
  prices,
  reading,
  releaseState
} from "./fixtures.ts";

const taskIds = (values: ReadonlyArray<{ readonly taskId: string }>): ReadonlyArray<string> =>
  values.map((value) => value.taskId);

describe("release evaluator", () => {
  it("proposes an admit for an armed item against a healthy reading", () => {
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), reading({}));

    expect(taskIds(decision.admits)).toEqual(["t1"]);
    expect(decision.admits[0]?.executor).toBe("coordinator");
    expect(decision.admits[0]?.level).toBe("approved");
  });

  it("carries the brief hash and the plan hash, and never a commit or any brief content", () => {
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), reading({}));
    const admit = decision.admits[0];

    expect(admit?.briefHash).toBeDefined();
    // The plan's authority is its hash, taken from the armed row. There is no
    // revision on the wire and no field for one.
    expect(admit?.planHash).toBe(armedPlan.planHash);
    expect(Object.keys(admit ?? {})).not.toContain("pinnedCommit");
    expect(Object.keys(admit ?? {})).not.toContain("rev");
    // The wire type has no field for brief content or argv, which is what keeps
    // a plan data rather than a script.
    expect(Object.keys(admit ?? {})).not.toContain("brief");
    expect(Object.keys(admit ?? {})).not.toContain("argv");
  });

  it("stamps a finite lane cap rather than leaving one unbounded", () => {
    const decision = evaluateRelease(
      releaseState([item({ taskId: "t1", medianSeconds: 600 })]),
      reading({})
    );
    expect(decision.admits[0]?.runtimeMaxSec).toBeLessThan(policy.runtimeCeilingSeconds);
    expect(Number.isFinite(decision.admits[0]?.runtimeMaxSec)).toBe(true);
  });

  it("defers an item whose plan is not armed", () => {
    const state = releaseState([item({ taskId: "t1" })], {
      plans: []
    });
    const decision = evaluateRelease(state, reading({}));

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.some((entry) => entry.rule === "planNotArmed")).toBe(true);
  });

  it("defers on a stopped row and names the row", () => {
    const decision = evaluateRelease(
      releaseState([item({ taskId: "t1" })]),
      reading({ signal: "STOP" })
    );

    expect(decision.admits).toEqual([]);
    const deferral = decision.deferrals.find((entry) => entry.rule === "capacityRow");
    expect(deferral?.detail).toBe("gpu-coordinator");
  });

  it("defers on a row already at capacity", () => {
    const decision = evaluateRelease(
      releaseState([item({ taskId: "t1" })]),
      reading({ gpuHolders: 1 })
    );
    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.some((entry) => entry.rule === "capacityRow")).toBe(true);
  });

  it("does not over-release one row within a single pass", () => {
    // Both free members name a capacity-one device row each; a third item has
    // nowhere to go until a witness clears one.
    const decision = evaluateRelease(
      releaseState([
        item({ taskId: "t1" }),
        item({ taskId: "t2" }),
        item({ taskId: "t3" })
      ]),
      reading({})
    );

    const perRow = new Map<string, number>();
    for (const admit of decision.admits) {
      for (const request of admit.rows) {
        perRow.set(request.row, (perRow.get(request.row) ?? 0) + request.holders);
      }
    }
    for (const [, holders] of perRow) expect(holders).toBeLessThanOrEqual(1);
  });

  it("respects the level hierarchy: a lower level never displaces a higher one", () => {
    const state = releaseState(
      [
        item({ taskId: "low", level: "maintenance", value: 1000 }),
        item({ taskId: "high", level: "approved", value: 1 })
      ],
      { caps: conwipCaps([[levelName("approved"), 8]], [[familyName("build"), 1]], []) }
    );
    const decision = evaluateRelease(state, reading({}));

    // Only one item fits under the family cap, and it must be the higher level's
    // even though the lower level's value is a thousand times greater.
    expect(taskIds(decision.admits)).toEqual(["high"]);
  });

  it("defers a metered item on a stale oracle reading", () => {
    const state = releaseState([item({ taskId: "t1", needs: "chromium" })]);
    const decision = evaluateRelease(state, reading({ freshness: "stale" }));

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.some((entry) => entry.rule === "oracleFreshness")).toBe(true);
  });

  it("routes local-first, and escalates only on a capability floor", () => {
    const local = evaluateRelease(releaseState([item({ taskId: "t1" })]), reading({}));
    expect(local.admits[0]?.member).not.toBe("opus-lane");

    // Only the metered member declares the chromium class, so the floor licenses
    // escalation.
    const escalated = evaluateRelease(
      releaseState([item({ taskId: "t2", needs: "chromium" })]),
      reading({})
    );
    expect(escalated.admits[0]?.member).toBe("opus-lane");
  });

  it("flips the length term between the attended and unattended regimes", () => {
    // Values high enough that both clear the bid-price test on a priced free
    // lane, so what orders them is the length term and nothing else.
    const short = item({ taskId: "short", medianSeconds: 100, value: 20000 });
    const long = item({ taskId: "long", medianSeconds: 5000, value: 20000 });

    // Priced free lanes, so the length term is what actually orders.
    const busyPrices = {
      ...prices,
      rows: prices.rows.map((entry) =>
        entry.row === "gpu-coordinator" || entry.row === "gpu-worker"
          ? { ...entry, price: 0.5 }
          : entry
      )
    };
    const state = releaseState([long, short], { prices: busyPrices });

    const attended = evaluateRelease(state, reading({ regime: "attended" }));
    const unattended = evaluateRelease(state, reading({ regime: "unattended" }));

    expect(attended.admits[0]?.taskId).toBe("short");
    expect(unattended.admits[0]?.taskId).toBe("long");
  });

  it("interleaves namespaces within a level", () => {
    const state = releaseState(
      [
        item({ taskId: "a1", namespace: "mecattaf/conwip", rank: 0 }),
        item({ taskId: "a2", namespace: "mecattaf/conwip", rank: 1 }),
        item({ taskId: "b1", namespace: "mecattaf/dotfiles", rank: 2 })
      ],
      { caps: conwipCaps([[levelName("approved"), 2]], [], []) }
    );
    const decision = evaluateRelease(state, reading({}));

    // Two device rows means two admits, and they must not both come from the
    // namespace that happened to sort first.
    const namespaces = new Set(
      decision.admits.map(
        (admit) => state.backlog.find((entry) => entry.taskId === admit.taskId)?.namespace
      )
    );
    expect(namespaces.size).toBe(2);
  });

  it("raises an andon for a family below its reorder point", () => {
    const state = releaseState([], {
      buffers: [{ family: familyName("build"), reorderPoint: 5, orderUpTo: 20 }],
      inventory: [{ family: familyName("build"), onHand: 2 }]
    });
    const decision = evaluateRelease(state, reading({}));

    expect(decision.andons).toEqual([{ family: "build", onHand: 2, shortfall: 18 }]);
  });

  it("is deterministic: the same state and reading give the same admits", () => {
    const state = releaseState([
      item({ taskId: "t1" }),
      item({ taskId: "t2" }),
      item({ taskId: "t3" })
    ]);
    const first = evaluateRelease(state, reading({}));
    const second = evaluateRelease(state, reading({}));

    expect(taskIds(first.admits)).toEqual(taskIds(second.admits));
  });

  it("defers monotonically: a better reading admits a superset", () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 1, max: 6 }),
        fc.constantFrom<"GO" | "SLOW">("GO", "SLOW"),
        (count, signal) => {
          const backlog = Array.from({ length: count }, (_, index) =>
            item({ taskId: `t${index}`, rank: index })
          );
          const state = releaseState(backlog);

          const weak = evaluateRelease(state, reading({ gpuHolders: 1, signal }));
          const strong = evaluateRelease(state, reading({ gpuHolders: 0, signal }));

          const strongSet = new Set(taskIds(strong.admits));
          return taskIds(weak.admits).every((taskId) => strongSet.has(taskId));
        }
      ),
      { numRuns: 100 }
    );
  });

  it("never admits past a cap, for any cap and any backlog size", () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 6 }),
        fc.integer({ min: 1, max: 8 }),
        (cap, size) => {
          const backlog = Array.from({ length: size }, (_, index) =>
            item({ taskId: `t${index}`, rank: index })
          );
          const state = releaseState(backlog, {
            caps: conwipCaps([[levelName("approved"), cap]], [], [])
          });
          const decision = evaluateRelease(state, reading({}));
          return decision.admits.length <= cap;
        }
      ),
      { numRuns: 200 }
    );
  });

  it("accounts for every candidate: each is admitted or deferred with a named rule", () => {
    fc.assert(
      fc.property(fc.integer({ min: 1, max: 6 }), (size) => {
        const backlog = Array.from({ length: size }, (_, index) =>
          item({ taskId: `t${index}`, rank: index })
        );
        const decision = evaluateRelease(releaseState(backlog), reading({}));
        const seen = new Set([
          ...taskIds(decision.admits),
          ...decision.deferrals.map((entry) => entry.taskId)
        ]);
        return seen.size === size;
      }),
      { numRuns: 100 }
    );
  });
});

// A recorded night is replayed as a sequence of readings against one state, with
// each accepted admit removed from the backlog. Because the evaluator is pure and
// takes elapsed intervals and window counts as inputs, the replay is exact and
// needs no test clock.
describe("replay of a recorded sequence", () => {
  it("reproduces an admit sequence exactly", () => {
    const backlog = [
      item({ taskId: "n1", rank: 0 }),
      item({ taskId: "n2", rank: 1 }),
      item({ taskId: "n3", rank: 2 }),
      item({ taskId: "n4", rank: 3 })
    ];

    const recorded = [
      reading({ seq: 1, gpuHolders: 0 }),
      reading({ seq: 2, gpuHolders: 1 }),
      reading({ seq: 3, gpuHolders: 0 })
    ];

    let remaining = backlog;
    const sequence: Array<ReadonlyArray<string>> = [];
    for (const frame of recorded) {
      const decision = evaluateRelease(releaseState(remaining), frame);
      const admitted = new Set(taskIds(decision.admits));
      sequence.push(taskIds(decision.admits));
      remaining = remaining.filter((entry) => !admitted.has(entry.taskId));
    }

    expect(sequence).toEqual([["n1", "n2"], [], ["n3", "n4"]]);
    expect(remaining).toEqual([]);
  });
});
