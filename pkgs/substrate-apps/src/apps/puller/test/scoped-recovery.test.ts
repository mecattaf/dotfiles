import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import type { Grant } from "@substrate/link/contract.ts";
import { A, Puller, type FloorPort, type RunTask } from "../src/puller.ts";
import { PullerState } from "../src/state.ts";

const scope = [{ project: "dotfiles", thread: "T-69" }];
const script = 'export const meta = { name: "turn", description: "synthetic" }; return "ok";';
const grant: Grant = {
  leaseId: "run-scoped-recovery-a1", attempt: 1,
  lease: { holderIdentity: "coord", leaseDurationSeconds: 90, acquireTime: 1, renewTime: 1, leaseTransitions: 0 },
  job: { apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
    metadata: { name: "run-scoped-recovery", annotations: { [A + "run-id-raw"]: "scoped-recovery", [A + "args"]: JSON.stringify({ synthetic: true }) } },
    spec: { "runs-on": ["runtime:interpreter"], with: { model: "local", prompt_ref: { sha256: createHash("sha256").update(script).digest("hex"), bytes: script.length, uri: "synthetic://script" } } } },
};
const until = async (f: () => boolean) => {
  const end = Date.now() + 5_000;
  while (!f()) { if (Date.now() > end) throw new Error("timed out waiting for execution"); await new Promise(r => setTimeout(r, 5)); }
};
const hold = (t: RunTask) => new Promise<{ result: "failure"; output: null }>(resolve => {
  const done = () => resolve({ result: "failure", output: null });
  if (t.signal.aborted) done(); else t.signal.addEventListener("abort", done, { once: true });
});

const heldScoped = async () => {
  const stateDir = mkdtempSync(join(tmpdir(), "scoped-recovery-"));
  let offered = false, started = false;
  const floor: FloorPort = {
    lease: async p => { expect(p.sessionScope).toEqual(scope); const grants = offered ? [] : [grant]; offered = true; return { grants }; },
    heartbeat: async p => ({ renewed: p.leaseIds, lost: [], cancelRequested: [] }),
    complete: async () => ({ duplicate: false }),
  };
  const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, sessionScope: scope, pollMs: 5, heartbeatMs: 20 },
    { floor, client: { runScript: async () => script }, execute: t => { started = true; return hold(t); } });
  // A crash after held.json is written must already have its durable scope proof.
  const putHeld = p.state.putHeld.bind(p.state);
  vi.spyOn(p.state, "putHeld").mockImplementation(h => {
    if (h[grant.leaseId]) expect(p.state.scopedAdmissions()[grant.leaseId]?.grantSha256).toBe(createHash("sha256").update(JSON.stringify(h[grant.leaseId])).digest("hex"));
    putHeld(h);
  });
  const done = p.run();
  await until(() => started);
  p.stop(); await done;
  return { stateDir, floor };
};

const refused = async (stateDir: string, sessionScope = scope) => {
  const calls: string[] = [];
  const floor: FloorPort = {
    lease: async () => { calls.push("lease"); return { grants: [] }; },
    heartbeat: async () => { calls.push("heartbeat"); return { renewed: [grant.leaseId], lost: [], cancelRequested: [] }; },
    complete: async () => { calls.push("complete"); return { duplicate: false }; },
  };
  const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, sessionScope, pollMs: 5, heartbeatMs: 5 },
    { floor, client: { runScript: async () => { calls.push("script"); return script; } }, execute: async () => { calls.push("execute"); return { result: "success", output: null }; } });
  await expect(p.run()).rejects.toThrow(/scope|scoped admission/);
  expect(calls).toEqual([]);
};

describe("scoped durable recovery", () => {
  it("refuses legacy held grants despite matching payload claims, without renewing or changing state", async () => {
    const stateDir = mkdtempSync(join(tmpdir(), "legacy-held-scope-"));
    const state = new PullerState(stateDir);
    state.putHeld({ [grant.leaseId]: { ...grant, job: { ...grant.job, metadata: { ...grant.job.metadata, annotations: { ...grant.job.metadata.annotations, [A + "args"]: JSON.stringify({ project: "dotfiles", thread: "T-69" }) } } } } });
    const before = readFileSync(join(stateDir, "held.json"), "utf8");
    await refused(stateDir);
    expect(readFileSync(join(stateDir, "held.json"), "utf8")).toBe(before);
  });
  it("refuses old outbox verdicts before sending completion or discarding the verdict", async () => {
    const stateDir = mkdtempSync(join(tmpdir(), "legacy-outbox-scope-"));
    const state = new PullerState(stateDir); state.putVerdict({ leaseId: grant.leaseId, attempt: 1, result: "success", output: "old" });
    await refused(stateDir);
    expect(state.outbox()).toHaveLength(1);
  });
  it("checks a pending request's scope before its startup heartbeat", async () => {
    const stateDir = mkdtempSync(join(tmpdir(), "legacy-pending-scope-"));
    const state = new PullerState(stateDir); state.setPendingKey("old-unscoped-request");
    await refused(stateDir);
    expect(state.pendingKey()).toBe("old-unscoped-request");
  });
  it("refuses a changed scope or altered persisted grant even when its payload claims an allowed thread", async () => {
    const { stateDir } = await heldScoped();
    await refused(stateDir, [{ project: "dotfiles", thread: "T-70" }]);
    const state = new PullerState(stateDir), held = state.held();
    const g = held[grant.leaseId]!;
    held[grant.leaseId] = { ...g, job: { ...g.job, spec: { ...g.job.spec, with: { ...g.job.spec.with, model: "tampered" } } } };
    state.putHeld(held);
    await refused(stateDir);
  });
  it.each([false, true])("re-adopts authentic same-scope grants, including a transient first heartbeat: %s", async transient => {
    const { stateDir, floor } = await heldScoped();
    let started = false, heartbeats = 0;
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, sessionScope: scope, pollMs: 5, heartbeatMs: 10 },
      { floor: { ...floor, heartbeat: p => { heartbeats++; return transient && heartbeats === 1 ? Promise.reject(new Error("synthetic transient")) : floor.heartbeat(p); } },
        client: { runScript: async () => script }, execute: t => { started = true; return hold(t); } });
    const done = p.run(); await until(() => started); p.stop(); await done;
    expect(p.held[grant.leaseId]).toBeDefined();
    expect(heartbeats).toBeGreaterThanOrEqual(transient ? 2 : 1);
  });
  it("recovers the crash window after its admission receipt but before held.json is written", async () => {
    const { stateDir, floor } = await heldScoped();
    const state = new PullerState(stateDir), receipt = state.scopedAdmissions()[grant.leaseId]!;
    state.putHeld({});
    const key = receipt.scope + "response-before-held-window";
    state.setPendingKey(key);
    let started = false;
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, sessionScope: scope, pollMs: 5, heartbeatMs: 10 },
      { floor: { ...floor, lease: async q => { expect(q.requestKey).toBe(key); expect(q.sessionScope).toEqual(scope); return { grants: [grant] }; } },
        client: { runScript: async () => script }, execute: t => { started = true; return hold(t); } });
    const done = p.run(); await until(() => started); p.stop(); await done;
    expect(state.held()[grant.leaseId]).toBeDefined(); expect(state.pendingKey()).toBeUndefined();
  });
  it("delivers a same-scope durable verdict after restart without re-executing its grant", async () => {
    const { stateDir, floor } = await heldScoped();
    const state = new PullerState(stateDir);
    state.putVerdict({ leaseId: grant.leaseId, attempt: 1, result: "success", output: "original" });
    let p: Puller, completed = 0;
    p = new Puller({ holder: "coord", maxRuns: 1, stateDir, sessionScope: scope },
      { floor: { ...floor, complete: async v => { completed++; expect(v.output).toBe("original"); p.stop(); return { duplicate: false }; } },
        client: { runScript: async () => { throw new Error("must not fetch"); } }, execute: async () => { throw new Error("must not execute"); } });
    await p.run();
    expect(completed).toBe(1); expect(state.outbox()).toEqual([]); expect(state.held()).toEqual({});
  });
});
