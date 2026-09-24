import { Effect, Option } from "effect";
import { describe, expect, it } from "vitest";

import {
  FACTORY_STATE_KEY,
  makeFactory,
  makeInMemoryPlanningStore,
  PlanningStore
} from "../src/index.ts";
import { item, reading, releaseState, report, run } from "./fixtures.ts";

describe("Factory state in PlanningStore", () => {
  it("restores inflight work, WIP, alarms, readings and outcome identity", async () => {
    const store = await run(makeInMemoryPlanningStore);
    const create = (initial: ReturnType<typeof releaseState>) =>
      run(makeFactory(initial).pipe(Effect.provideService(PlanningStore, store)));
    const alarmAt = "2026-09-07T03:04:05Z";

    const first = await create(releaseState([item({ taskId: "A" })]));
    const capacity = reading({ nextWindowAt: alarmAt });
    await run(first.observeCapacity(capacity));
    const proposals = await run(first.handOut(capacity.executor));
    const outcome = report("A", "Accepted", {
      dedupKey: proposals[0]?.dedupKey,
      lease_id: "lease-persisted"
    });
    await run(first.observeOutcome(outcome));

    expect(Option.isSome(await run(store.get(FACTORY_STATE_KEY)))).toBe(true);
    const recreated = await create(releaseState([], { plans: [], wip: [] }));
    const state = await run(recreated.stateView);
    expect(state.backlog[0]?.state).toBe("inflight");
    expect(state.wip.level.approved).toBe(1);
    expect(state.alarm_at).toBe(alarmAt);
    expect(state.latest_readings.coordinator?.seq).toBe(1);
    expect(await run(recreated.handOut(capacity.executor))).toEqual([]);
    expect((await run(recreated.observeOutcome(outcome))).idempotent).toBe(true);
    expect((await run(recreated.stateView)).wip.level.approved).toBe(1);
  });

  it("restores explicit proposal command and mutation references", async () => {
    const store = await run(makeInMemoryPlanningStore);
    const create = (initial: ReturnType<typeof releaseState>) =>
      run(makeFactory(initial).pipe(Effect.provideService(PlanningStore, store)));
    const enriched = item({
      taskId: "A",
      argv_ref: "cards/U-A11.json#A",
      mutation_hint: "delete dependencyUnmet"
    });

    const first = await create(releaseState([enriched]));
    expect((await run(first.releaseState)).backlog[0]).toMatchObject({
      argv_ref: "cards/U-A11.json#A",
      mutation_hint: "delete dependencyUnmet"
    });

    const recreated = await create(releaseState([], { plans: [], wip: [] }));
    expect((await run(recreated.releaseState)).backlog[0]).toMatchObject({
      argv_ref: "cards/U-A11.json#A",
      mutation_hint: "delete dependencyUnmet"
    });
    const capacity = reading({});
    await run(recreated.observeCapacity(capacity));
    expect((await run(recreated.handOut(capacity.executor)))[0]).toMatchObject({
      taskId: "A",
      argv_ref: "cards/U-A11.json#A",
      mutation_hint: "delete dependencyUnmet"
    });
  });
});
