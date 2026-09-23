/**
 * Edge cases found by the 2026-09-23 naive-confirmation review: nested
 * workflow(), budget exhaustion mid-parallel, throwing stages, null
 * propagation, the 4096 and 1000 caps, computed labels, schema retry.
 * Each `it` here failed before the fix it names (MEASURED), unless it says
 * "guard" (a behaviour that was already right and is pinned so it stays so).
 */
import { describe, expect, it } from "vitest";
import { MockBackend, type AgentCall } from "../src/backend.ts";
import { ITEMS_PER_CALL_CAP, runWorkflow } from "../src/interpreter.ts";
import { MemoryJournal, splitRuns } from "../src/journal.ts";
import { run, wf } from "./helpers.ts";

const ID_SCHEMA = `{ $id: 'https://example.invalid/finding', type: 'object', properties: { n: { type: 'integer' } }, required: ['n'] }`;

describe("schema handling", () => {
  it("a schema carrying $id can be used by more than one agent() call", async () => {
    const r = await run(`const a = await agent('one', { schema: ${ID_SCHEMA} }); const b = await agent('two', { schema: ${ID_SCHEMA} }); return [a, b]`);
    expect(r.status).toBe("completed");
    expect(r.result).toEqual([{ n: 1 }, { n: 1 }]);
  });
  it("a schema carrying $id works inside parallel() (every item, not only the first)", async () => {
    const r = await run(`return await parallel([1, 2, 3].map(i => () => agent('p' + i, { schema: ${ID_SCHEMA} })))`);
    expect(r.result).toEqual([{ n: 1 }, { n: 1 }, { n: 1 }]);
  });
  it("an uncompilable schema throws at the call site, before any key, journal line or backend spend", async () => {
    const journal = new MemoryJournal();
    const r = await run(
      `let e1; try { await agent('bad', { schema: { type: 'object', properties: { n: { type: 'intger' } } } }) } catch (e) { e1 = e.message }
       const ok = await agent('good'); return { e1, ok }`,
      { journal },
    );
    expect((r.result as { e1: string }).e1).toMatch(/schema/i);
    expect(r.backendCalls).toHaveLength(1);
    expect(r.calls.map((c) => c.prompt)).toEqual(["good"]);
    expect(journal.events.filter((e) => e.type === "started")).toHaveLength(1);
    expect(r.totalTokens).toBe(100); // only 'good': 100 output tokens (input is not charged, per the dialect)
  });
  it("guard: a schema-retry that stops because the budget ran out announces no retry it never makes", async () => {
    const backend = new MockBackend({ latency: () => 0, respond: () => ({ object: { n: "x" }, usage: { inputTokens: 50, outputTokens: 110 } }) });
    const r = await runWorkflow(wf(`return await agent('p', { schema: { type: 'object', properties: { n: { type: 'integer' } }, required: ['n'] } })`), {
      backend,
      budgetTotal: 100,
    });
    expect(r.result).toBeNull();
    expect(backend.calls).toHaveLength(1);
    expect(r.events.filter((e) => e.type === "agent_retry")).toHaveLength(0);
  });
});

describe("budget exhaustion mid-parallel", () => {
  it("calls queued behind the concurrency gate do not start once the budget is spent", async () => {
    // Each mock call costs 100 output tokens (budget.spent() counts output only);
    // budget 200. p0 and p1 are admitted at 0; p2 is admitted when p0 ends (spent
    // 100 < 200). The ceiling is checked at admission, so in-flight work can
    // overshoot it (p2 ends at 300), but nothing
    // starts once spent >= total: p3..p7 never reach the backend. Before the fix
    // all 8 ran (808 tokens).
    const r = await run(`return await parallel(Array.from({ length: 8 }, (_, i) => () => agent('p' + i)))`, {
      concurrency: 2,
      budgetTotal: 200,
      mock: { latency: () => 1 },
    });
    const out = r.result as (string | null)[];
    expect(out.filter((x) => x !== null)).toHaveLength(3);
    expect(r.backendCalls).toHaveLength(3);
    expect(r.totalTokens).toBe(300);
    expect(r.events.filter((e) => e.type === "item_null")).toHaveLength(5);
    expect(r.events).toContainEqual(expect.objectContaining({ type: "item_null", reason: expect.stringMatching(/budget exhausted/) }));
  });
  it("the same, inside a pipeline stage: later items null, earlier results kept", async () => {
    const r = await run(`return await pipeline([0, 1, 2, 3, 4, 5], (x) => agent('s' + x))`, {
      concurrency: 1,
      budgetTotal: 200,
      mock: { latency: () => 1 },
    });
    const out = r.result as (string | null)[];
    expect(out.slice(0, 2).every((x) => typeof x === "string")).toBe(true);
    expect(out.slice(2)).toEqual([null, null, null, null]);
    expect(r.backendCalls).toHaveLength(2);
  });
  // Successor review r5 reversed "journaled nowhere": a refusal at admission now
  // leaves a started and a failed line with budgetExhausted, as an in-attempt one does.
  it("a budget-refused queued call is journaled as a budget failure and leaves no 'running' record", async () => {
    const journal = new MemoryJournal();
    const r = await run(`return await parallel([0, 1, 2].map(i => () => agent('p' + i)))`, {
      concurrency: 1,
      budgetTotal: 100,
      journal,
      mock: { latency: () => 1 },
    });
    expect(journal.events.filter((e) => e.type === "started")).toHaveLength(3);
    expect(journal.events.filter((e) => e.type === "failed" && (e as { budgetExhausted?: boolean }).budgetExhausted === true)).toHaveLength(2);
    expect(r.calls.map((c) => c.state)).toEqual(["done", "null", "null"]);
    const wp = (r.record.workflowProgress as { type: string; state?: string }[]).filter((p) => p.type === "workflow_agent");
    expect(wp.map((p) => p.state)).toEqual(["done", "error", "error"]);
  });
  it("guard: a nested workflow shares the parent's budget", async () => {
    const child = wf(`return await agent('c')`);
    const r = await run(`await agent('abcd'); try { await workflow('child'); return 'ran' } catch (e) { return e.message }`, {
      budgetTotal: 100,
      resolveWorkflow: () => ({ source: child, path: "/virtual/child.js" }),
    });
    expect(r.result).toMatch(/budget exhausted/);
  });
});

describe("computed labels", () => {
  it("a non-string computed label is kept as a string, like a computed phase", async () => {
    const journal = new MemoryJournal();
    const r = await run(`const i = 3; await agent('p', { label: i, phase: i }); return null`, { journal });
    expect(r.calls[0]).toMatchObject({ label: "3", phase: "3" });
    expect(journal.events[1]).toMatchObject({ type: "started", label: "3", phase: "3" });
  });
  it("guard: template-literal labels reach the journal verbatim and are not keyed", async () => {
    const journal = new MemoryJournal();
    const r = await run(`for (const k of ['a', 'b']) await agent('same', { label: \`verify:\${k}\` }); return null`, { journal });
    expect(r.calls.map((c) => c.label)).toEqual(["verify:a", "verify:b"]);
    expect(journal.events.filter((e) => e.type === "started").map((e) => (e as { label?: string }).label)).toEqual(["verify:a", "verify:b"]);
  });
  const k = (n: number) => `v2:${n.toString(16).padStart(64, "0")}`;
  const jl = (lines: object[]) => lines.map((e) => JSON.stringify(e)).join("\n") + "\n";
  it("splitRuns: calls sharing a computed label inside ONE live parallel burst are not split into two runs", () => {
    const text = jl([
      { type: "launched" },
      { type: "started", key: k(1), agentId: "a1", label: "review:r1" },
      { type: "started", key: k(3), agentId: "a3", label: "fix:r1" },
      { type: "started", key: k(2), agentId: "a2", label: "review:r1" },
      { type: "result", key: k(3), agentId: "a3", result: "ok" },
      { type: "result", key: k(2), agentId: "a2", result: "ok" },
    ]);
    expect(splitRuns(text)).toHaveLength(1);
  });
  it("guard: a killed run resumed under an edited key still splits (the wf_70fb1fc5-b3b shape)", () => {
    const text = jl([
      { type: "launched" },
      { type: "started", key: k(1), agentId: "a1", label: "x" },
      { type: "result", key: k(1), agentId: "a1", result: "ok" },
      { type: "started", key: k(2), agentId: "a2", label: "y" },
      { type: "started", key: k(9), agentId: "a9", label: "y" },
      { type: "result", key: k(9), agentId: "a9", result: "ok" },
    ]);
    expect(splitRuns(text)).toHaveLength(2);
  });
});

describe("nested workflow()", () => {
  const child = wf(`phase('B'); const r = await agent('child ' + args.n); return { r, n: args.n }`);
  const resolveWorkflow = (_ref: string) => ({ source: child, path: "/virtual/child.js" });
  it("guard: a failing child fails only the parent's workflow() call, and the parent can catch it", async () => {
    const bad = wf(`throw new Error('child broke')`);
    const r = await run(`let m; try { await workflow('bad') } catch (e) { m = e.message } return [m, await agent('after')]`, {
      resolveWorkflow: () => ({ source: bad, path: "/virtual/bad.js" }),
    });
    expect(r.status).toBe("completed");
    expect((r.result as string[])[0]).toMatch(/child broke/);
  });
  it("guard: a child's phase() does not leak into the parent's current phase", async () => {
    const r = await run(`phase('A'); await workflow('child', { n: 1 }); await agent('parent after'); return null`, { resolveWorkflow });
    expect(r.calls.map((c) => [c.depth, c.phase])).toEqual([[1, "B"], [0, "A"]]);
  });
  it("guard: children in parallel() share the key chain in invocation order and the lifetime cap", async () => {
    const r = await run(`return await parallel([1, 2].map(n => () => workflow('child', { n })))`, { resolveWorkflow, maxAgents: 1 });
    expect(r.result).toEqual([{ r: "[[m:#1]] mock result", n: 1 }, null]);
  });
  it("a child's calls carry the CHILD's phase index in the record, not the parent's", async () => {
    const kid = `export const meta = { name: 'kid', description: 'd', phases: [{ title: 'K1' }, { title: 'K2' }] }\nphase('K2'); return await agent('k')`;
    const r = await run(`phase('A'); return await workflow('kid')`, { resolveWorkflow: () => ({ source: kid, path: "/virtual/kid.js" }) });
    const wp = (r.record.workflowProgress as { type: string; phaseTitle?: string; phaseIndex?: number }[]).filter((p) => p.type === "workflow_agent");
    expect(wp[0]).toMatchObject({ phaseTitle: "K2", phaseIndex: 2 });
  });
});

describe("throwing stages and null propagation (guards)", () => {
  it("a stage that throws a non-Error value nulls its item with a readable reason", async () => {
    const r = await run(`return await pipeline([1, 2], (x) => { if (x === 1) throw undefined; return x }, (x) => x * 10)`);
    expect(r.result).toEqual([null, 20]);
    expect(r.events).toContainEqual(expect.objectContaining({ type: "item_null", where: "pipeline", item: 0, stage: 0, reason: "undefined" }));
  });
  it("a failed agent in stage 1 reaches stage 2 as null, not as a thrown error", async () => {
    const backend = new MockBackend({ latency: () => 0, respond: (c: AgentCall) => (c.prompt === "s1:1" ? { skipped: true } : undefined) });
    const r = await run(`return await pipeline([0, 1], (x) => agent('s1:' + x), (prev, x) => prev === null ? 'saw null ' + x : 'ok ' + x)`, { backend });
    expect(r.result).toEqual(["ok 0", "saw null 1"]);
  });
  it(`the per-call cap is exactly ${ITEMS_PER_CALL_CAP}: ${ITEMS_PER_CALL_CAP} items run, one more throws`, async () => {
    const r = await run(`const a = await parallel(Array.from({ length: ${ITEMS_PER_CALL_CAP} }, (_, i) => i)); let e; try { await pipeline(Array.from({ length: ${ITEMS_PER_CALL_CAP + 1} }, (_, i) => i)) } catch (x) { e = x.message } return [a.length, e]`);
    expect(r.result).toEqual([ITEMS_PER_CALL_CAP, expect.stringMatching(/4097 items exceeds the per-call cap of 4096/)]);
  });
});
