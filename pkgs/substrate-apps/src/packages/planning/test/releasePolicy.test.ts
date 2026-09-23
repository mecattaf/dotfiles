/**
 * The policy inputs: the rules that had no source in the theory, now data.
 *
 * Each test here changes one field of `ReleasePolicy` and nothing else, and
 * shows the release rule answering differently. That is the whole claim being
 * tested — not that one answer is right, but that the choice is Tom's to make as
 * data rather than someone's to have made as code.
 */
import { describe, expect, it } from "vitest";
import {
  defaultReleasePolicy,
  evaluateRelease,
  type ReleasePolicy
} from "../src/release/evaluator.ts";
import { item, prices, reading, releaseState } from "./fixtures.ts";

const taskIds = (values: ReadonlyArray<{ readonly taskId: string }>): ReadonlyArray<string> =>
  values.map((value) => value.taskId);

const withPolicy = (overrides: Partial<ReleasePolicy>): ReleasePolicy => ({
  ...defaultReleasePolicy,
  ...overrides
});

describe("the documented defaults", () => {
  it("are the canon's own reading, so an unset field never invents a preference", () => {
    // Each of these is a decision the theory does not make, defaulted to the
    // conservative side and stated once, here.
    expect(defaultReleasePolicy.routingPreference).toBe("routerOrder");
    expect(defaultReleasePolicy.dropMeteredWhenFreePreferred).toBe(true);
    expect(defaultReleasePolicy.lengthExponent).toBe(1);
    expect(defaultReleasePolicy.congestion).toEqual({ _tag: "Wait" });
  });
});

describe("routingPreference", () => {
  // The second free member is resident, so warmth and catalog order disagree.
  const warm = reading({ resident: ["gemma-coding"] });

  it("routerOrder takes the router's own first choice, which prefers warmth", () => {
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), warm);
    expect(decision.admits[0]?.member).toBe("gemma-coding");
  });

  it("catalogOrder follows the authored catalog and ignores warmth", () => {
    const state = releaseState([item({ taskId: "t1" })], {
      policy: withPolicy({ routingPreference: "catalogOrder" })
    });
    const decision = evaluateRelease(state, warm);
    expect(decision.admits[0]?.member).toBe("qwen-general");
  });

  it("warmFirst lifts the resident member to the front of the catalog order", () => {
    const state = releaseState([item({ taskId: "t1" })], {
      policy: withPolicy({ routingPreference: "warmFirst" })
    });
    const decision = evaluateRelease(state, warm);
    expect(decision.admits[0]?.member).toBe("gemma-coding");
  });

  it("changes only the order and never the licence to escalate", () => {
    // Both device rows are held. Whatever order the free members are tried in,
    // none of these settings may reach the metered lane on its own.
    const busy = reading({ gpuHolders: 1 });
    for (const preference of ["routerOrder", "catalogOrder", "warmFirst"] as const) {
      const state = releaseState([item({ taskId: "t1" })], {
        policy: withPolicy({ routingPreference: preference })
      });
      const decision = evaluateRelease(state, busy);
      expect(decision.admits).toEqual([]);
    }
  });
});

describe("dropMeteredWhenFreePreferred", () => {
  const busy = reading({ gpuHolders: 1 });

  it("true keeps a congested item waiting for the free lane it preferred", () => {
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), busy);

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.some((entry) => entry.rule === "capacityRow")).toBe(true);
  });

  it("false lets the walk fall through to the metered member", () => {
    const state = releaseState([item({ taskId: "t1" })], {
      policy: withPolicy({ dropMeteredWhenFreePreferred: false })
    });
    const decision = evaluateRelease(state, busy);

    expect(decision.admits[0]?.member).toBe("opus-lane");
  });

  it("does not change what happens when the free rows are open", () => {
    const state = releaseState([item({ taskId: "t1" })], {
      policy: withPolicy({ dropMeteredWhenFreePreferred: false })
    });
    const decision = evaluateRelease(state, reading({}));

    // The filter is about congestion. With a free row open, local-first still
    // decides, and it decides the same way either way.
    expect(decision.admits[0]?.member).toBe("qwen-general");
  });
});

describe("lengthExponent", () => {
  // Priced free lanes, so the density carries a service-time term and the length
  // term is what actually orders.
  const busyPrices = {
    ...prices,
    rows: prices.rows.map((entry) =>
      entry.row === "gpu-coordinator" || entry.row === "gpu-worker"
        ? { ...entry, price: 0.5 }
        : entry
    )
  };
  const backlog = [
    item({ taskId: "long", medianSeconds: 5000, value: 20000 }),
    item({ taskId: "short", medianSeconds: 100, value: 20000 })
  ];

  it("at one, the unattended regime puts the long job first", () => {
    const state = releaseState(backlog, { prices: busyPrices });
    const decision = evaluateRelease(state, reading({ regime: "unattended" }));
    expect(decision.admits[0]?.taskId).toBe("long");
  });

  it("at zero, the term is neutral and the flip is off in both regimes", () => {
    const state = releaseState(backlog, {
      prices: busyPrices,
      policy: withPolicy({ lengthExponent: 0 })
    });

    const unattended = evaluateRelease(state, reading({ regime: "unattended" }));
    const attended = evaluateRelease(state, reading({ regime: "attended" }));

    // With no length preference the bid-price denominator alone orders, and it
    // is already short-first on a priced position row.
    expect(unattended.admits[0]?.taskId).toBe("short");
    expect(attended.admits[0]?.taskId).toBe("short");
  });

  it("a steeper exponent keeps the unattended order and sharpens it", () => {
    const state = releaseState(backlog, {
      prices: busyPrices,
      policy: withPolicy({ lengthExponent: 3 })
    });
    const decision = evaluateRelease(state, reading({ regime: "unattended" }));
    expect(taskIds(decision.admits)).toEqual(["long", "short"]);
  });
});

describe("congestion", () => {
  const busy = reading({ gpuHolders: 1 });

  it("Wait leaves an item deferred however long it has been passed over", () => {
    const decision = evaluateRelease(
      releaseState([item({ taskId: "t1", deferrals: 20 })]),
      busy
    );
    expect(decision.admits).toEqual([]);
  });

  it("EscalateAfter lets a sustained deferral reach the metered lane", () => {
    const state = releaseState([item({ taskId: "t1", deferrals: 3 })], {
      policy: withPolicy({ congestion: { _tag: "EscalateAfter", deferrals: 3 } })
    });
    const decision = evaluateRelease(state, busy);

    expect(decision.admits[0]?.member).toBe("opus-lane");
  });

  it("holds an item that has not yet been passed over enough times", () => {
    const state = releaseState([item({ taskId: "t1", deferrals: 1 })], {
      policy: withPolicy({ congestion: { _tag: "EscalateAfter", deferrals: 3 } })
    });
    const decision = evaluateRelease(state, busy);

    expect(decision.admits).toEqual([]);
    expect(decision.deferrals.some((entry) => entry.rule === "capacityRow")).toBe(true);
  });

  it("never escalates an item whose free lane is open, whatever its count", () => {
    // Congestion is the only thing this clause responds to. With a row free
    // there is no congestion, and a long deferral history is not a licence.
    const state = releaseState([item({ taskId: "t1", deferrals: 50 })], {
      policy: withPolicy({ congestion: { _tag: "EscalateAfter", deferrals: 3 } })
    });
    const decision = evaluateRelease(state, reading({}));

    expect(decision.admits[0]?.member).toBe("qwen-general");
  });
});
