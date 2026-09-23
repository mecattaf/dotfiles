import { Option } from "effect";
import { describe, expect, it } from "vitest";
import { cloudReading, armedPlan } from "../../planning/test/fixtures.ts";
import {
  armItems,
  emptyFactory,
  factoryFor,
  heartbeat,
  item,
  reading,
  report,
  run,
  verdict
} from "./fixtures.ts";

const capped = (cap = 1) => [
  { axis: "level" as const, subject: "approved", cap },
  { axis: "namespace" as const, subject: "mecattaf/conwip", cap },
  { axis: "family" as const, subject: "build", cap }
];

describe("the Factory state machine", () => {
  it("an accepted, unclosed item is not proposed on the next evaluate", async () => {
    const factory = await factoryFor(
      [item({ taskId: "A", rank: 0 }), item({ taskId: "B", rank: 1 })],
      { caps: capped(1) }
    );
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    expect((await run(factory.handOut(capacity.executor))).map((p) => p.taskId)).toEqual(["A"]);
    await run(factory.observeOutcome(report("A", "Accepted")));

    expect(await run(factory.handOut(capacity.executor))).toEqual([]);
    expect((await run(factory.releaseState)).backlog[0]?.state).toBe("inflight");
  });

  it("wip after verdict equals wip before admit", async () => {
    const factory = await factoryFor([item({ taskId: "A" })], { caps: capped(1) });
    const before = (await run(factory.releaseState)).wip;
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Accepted")));
    const during = await run(factory.stateView);
    expect(during.wip).toEqual({
      level: { approved: 1 },
      namespace: { "mecattaf/conwip": 1 },
      family: { build: 1 }
    });

    await run(factory.observeVerdict(verdict("A", "pass")));
    expect((await run(factory.releaseState)).wip).toEqual(before);
  });

  it("a NotYet returns the item with deferrals+1", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "NotYet")));

    const state = await run(factory.releaseState);
    expect(state.backlog[0]?.state).toBe("unclaimed");
    expect(state.backlog[0]?.deferrals).toBe(1);
    expect((await run(factory.stateView)).deferrals_by_row).toEqual({
      "gpu-coordinator": 1
    });
  });

  it("applies the same NotYet report again after a new release cycle", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    const notYet = report("A", "NotYet");
    await run(factory.observeCapacity(capacity));

    await run(factory.handOut(capacity.executor));
    expect((await run(factory.observeOutcome(notYet))).idempotent).toBe(false);
    expect((await run(factory.observeOutcome(notYet))).idempotent).toBe(true);

    await run(factory.handOut(capacity.executor));
    expect((await run(factory.observeOutcome(notYet))).idempotent).toBe(false);
    const state = await run(factory.stateView);
    expect(state.backlog[0]).toMatchObject({ state: "unclaimed", deferrals: 2 });
    expect(state.deferrals_by_row).toEqual({ "gpu-coordinator": 2 });
  });

  it("the same verdict posted twice mirrors once and frees one slot", async () => {
    const factory = await factoryFor([item({ taskId: "A" })], { caps: capped(1) });
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Accepted")));
    const first = await run(factory.observeVerdict(verdict("A", "pass")));
    const second = await run(factory.observeVerdict(verdict("A", "pass")));

    expect(first.idempotent).toBe(false);
    expect(second.idempotent).toBe(true);
    const state = await run(factory.stateView);
    expect(state.mirrored_verdicts).toBe(1);
    expect(state.wip.level.approved).toBe(0);
  });

  it("a re-arm with the same planHash adds only new ordinals", async () => {
    const factory = await emptyFactory();
    const original = item({ taskId: "ordinal-3", rank: 3, value: 10 });
    await armItems(factory, [original]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("ordinal-3", "Accepted")));
    await run(factory.observeVerdict(verdict("ordinal-3", "pass")));

    await armItems(factory, [
      item({ taskId: "ordinal-3-rewritten", rank: 3, value: 999 }),
      item({ taskId: "ordinal-4", rank: 4 })
    ]);
    const state = await run(factory.releaseState);
    expect(state.backlog.map((entry) => entry.rank)).toEqual([3, 4]);
    expect(state.backlog[0]).toMatchObject({
      taskId: "ordinal-3",
      state: "closed",
      value: 10
    });
    expect(state.backlog[1]).toMatchObject({ taskId: "ordinal-4", state: "unclaimed" });
  });

  it("moves a handed-out item from unclaimed to released", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    const proposals = await run(factory.handOut(capacity.executor));
    expect(proposals[0]).toMatchObject({
      taskId: "A",
      row: "gpu-coordinator",
      argv_ref: "A"
    });
    expect((await run(factory.releaseState)).backlog[0]?.state).toBe("released");
  });

  it("reserves cap slack while a released proposal awaits its answer", async () => {
    const factory = await factoryFor(
      [item({ taskId: "A", rank: 0 }), item({ taskId: "B", rank: 1 })],
      { caps: capped(1) }
    );
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    expect((await run(factory.handOut(capacity.executor))).map((p) => p.taskId)).toEqual(["A"]);
    expect(await run(factory.handOut(capacity.executor))).toEqual([]);
    expect((await run(factory.releaseState)).wip).toEqual([]);
  });

  it("refuses a verdict before Accepted and leaves released WIP unchanged", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    const before = await run(factory.releaseState);
    expect(before.backlog[0]).toMatchObject({ state: "released", outcome: Option.none() });

    await expect(run(factory.observeVerdict(verdict("A", "pass")))).rejects.toMatchObject({
      reason: "InvalidTransition",
      operation: "Factory.observeVerdict",
      subject: "A (state released)"
    });

    const after = await run(factory.releaseState);
    expect(after.backlog[0]).toMatchObject({ state: "released", outcome: Option.none() });
    expect(after.wip).toEqual(before.wip);
    expect((await run(factory.stateView)).mirrored_verdicts).toBe(0);
  });

  it("closes a rejected release without minting a verdict outcome", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Rejected", { code: "not-armed" })));
    const state = await run(factory.stateView);
    expect(state.backlog[0]).toMatchObject({ state: "closed", outcome: null });
    expect(state.facts.at(-1)).toMatchObject({ kind: "rejected", detail: "not-armed" });
  });

  it("deduplicates an outcome report before changing WIP", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    const first = await run(factory.observeOutcome(report("A", "Accepted", { lease_id: "L1" })));
    const second = await run(factory.observeOutcome(report("A", "Accepted", { lease_id: "L1" })));
    expect(first.idempotent).toBe(false);
    expect(second.idempotent).toBe(true);
    expect((await run(factory.releaseState)).wip[0]?.count).toBe(1);
  });

  it("does not confuse outcome identities containing embedded NULs", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    const first = report("A", "NotYet", {
      lease_id: "lease\u0000part",
      row: "row"
    });
    const boundaryShifted = report("A", "NotYet", {
      lease_id: "lease",
      row: "part\u0000row"
    });
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(first));

    await expect(run(factory.observeOutcome(boundaryShifted))).rejects.toMatchObject({
      reason: "InvalidTransition"
    });
    await run(factory.handOut(capacity.executor));
    expect((await run(factory.observeOutcome(boundaryShifted))).idempotent).toBe(false);
    expect((await run(factory.releaseState)).backlog[0]).toMatchObject({
      state: "unclaimed",
      deferrals: 2
    });
  });

  it("refuses an outcome carrying another proposal's dedup key", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await expect(
      run(factory.observeOutcome(report("A", "Accepted", { dedupKey: "wrong" })))
    ).rejects.toMatchObject({ reason: "DedupMismatch" });
  });
});

describe("dependency release and verdict replay", () => {
  it("proposes B only after A closes pass", async () => {
    const factory = await factoryFor(
      [
        item({ taskId: "A", rank: 0 }),
        item({ taskId: "B", rank: 1, dependsOn: ["A"] })
      ],
      { caps: capped(2) }
    );
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    expect((await run(factory.handOut(capacity.executor))).map((p) => p.taskId)).toEqual(["A"]);
    await run(factory.observeOutcome(report("A", "Accepted")));
    await run(factory.observeVerdict(verdict("A", "pass")));
    expect((await run(factory.handOut(capacity.executor))).map((p) => p.taskId)).toEqual(["B"]);
  });

  it("returns A to attempt 2 after fail and keeps B dependency-blocked", async () => {
    const factory = await factoryFor(
      [
        item({ taskId: "A", rank: 0 }),
        item({ taskId: "B", rank: 1, dependsOn: ["A"] })
      ],
      { caps: capped(2) }
    );
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Accepted")));
    await run(factory.observeVerdict(verdict("A", "fail")));
    const state = await run(factory.releaseState);
    expect(state.backlog[0]).toMatchObject({ state: "unclaimed", attempt: 2 });
    expect((await run(factory.handOut(capacity.executor))).map((p) => p.taskId)).toEqual(["A"]);
  });

  it("gives a retried attempt a new admit identity", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    const first = await run(factory.handOut(capacity.executor));
    const firstKey = first[0]?.dedupKey;
    await run(
      factory.observeOutcome(
        report("A", "Accepted", { dedupKey: firstKey, lease_id: "lease-1" })
      )
    );
    await run(factory.observeVerdict(verdict("A", "fail")));

    const second = await run(factory.handOut(capacity.executor));
    const secondKey = second[0]?.dedupKey;
    expect(secondKey).not.toBe(firstKey);
    const accepted = await run(
      factory.observeOutcome(
        report("A", "Accepted", { dedupKey: secondKey, lease_id: "lease-2" })
      )
    );
    expect(accepted.idempotent).toBe(false);
    expect((await run(factory.releaseState)).backlog[0]).toMatchObject({
      state: "inflight",
      attempt: 2,
      dedupKey: secondKey
    });
    expect((await run(factory.stateView)).wip.level.approved).toBe(1);
  });

  it("closes a failed item at its authored attempt cap", async () => {
    const factory = await factoryFor([item({ taskId: "A" })], {
      plans: [{ ...armedPlan, attemptCap: Option.some(1) }]
    });
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Accepted")));
    await run(factory.observeVerdict(verdict("A", "fail")));
    expect((await run(factory.releaseState)).backlog[0]).toMatchObject({
      state: "closed",
      attempt: 1
    });
  });

  it("refuses a first mirrored verdict that skips the chain", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({});
    await run(factory.observeCapacity(capacity));
    await run(factory.handOut(capacity.executor));
    await run(factory.observeOutcome(report("A", "Accepted")));
    await expect(run(factory.observeVerdict(verdict("A", "pass", 2)))).rejects.toMatchObject({
      reason: "ContinuityGap"
    });
    const state = await run(factory.stateView);
    expect(state.continuity_gaps).toHaveLength(1);
    expect(state.chains).toEqual({});
  });
});

describe("capacity wake state", () => {
  it("treats SLOW as STOP for proposals", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    const capacity = reading({ signal: "SLOW" });
    await run(factory.observeCapacity(capacity));
    expect(await run(factory.handOut(capacity.executor))).toEqual([]);
  });

  it("keeps only the newest reading from each executor", async () => {
    const factory = await factoryFor([]);
    expect(await run(factory.observeCapacity(reading({ seq: 2 })))).toBe(true);
    expect(await run(factory.observeCapacity(reading({ seq: 1 })))).toBe(false);
    expect((await run(factory.stateView)).latest_readings.coordinator?.seq).toBe(2);
  });

  it("sets alarm_at to the minimum next_window_at and records alarm firing", async () => {
    const factory = await factoryFor([]);
    await run(
      factory.observeCapacity(reading({ nextWindowAt: "2026-09-06T18:00:00Z" }))
    );
    await run(
      factory.observeCapacity(cloudReading({ nextWindowAt: "2026-09-06T17:00:00Z" }))
    );
    expect((await run(factory.stateView)).alarm_at).toBe("2026-09-06T17:00:00Z");
    await run(factory.alarm("2026-09-06T17:00:00Z"));
    expect((await run(factory.stateView)).alarm_fired_at).toBe("2026-09-06T17:00:00Z");
  });

  it("returns chain high-water marks and the constant price hash", async () => {
    const factory = await factoryFor([]);
    await run(factory.observeVerdict(verdict("external-task", "pass")));
    const state = await run(factory.stateView);
    expect(state.chains.coordinator).toEqual({
      last_seq: 1,
      last_hash: verdict("external-task", "pass").hash
    });
    expect(state.price_hash).toBe("d".repeat(64));
  });

  it("reports the latest heartbeat by lane", async () => {
    const factory = await factoryFor([]);
    await run(
      factory.observeHeartbeat(
        heartbeat("lane-A", 1),
        "lane-A",
        "2026-09-06T16:00:00Z"
      )
    );
    await run(factory.observeHeartbeat(heartbeat("lane-A", 1), "lane-A"));
    expect((await run(factory.stateView)).heartbeats_by_lane["lane-A"]).toEqual({
      executor: "coordinator",
      task_id: "lane-A",
      last_seq: 1,
      status: "live",
      observed_at: "2026-09-06T16:00:00Z"
    });
  });
});
