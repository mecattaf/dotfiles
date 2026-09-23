/**
 * Successor review, fix round 1 (2026-09-23), interpreter half:
 *  - D04/D18: content-identity resume (cacheIdentity "content") keeps every
 *    finished call, after a failure and after a reordered pipeline;
 *  - D14: a journal value that fails the call's schema is a miss, not a value;
 *  - D10: terminal lines carry tokens and a resume counts them against the budget;
 *  - D08: a replay of a killed run parks the calls in flight at the kill, so its
 *    journal keeps them started-only and a resume keeps the finished work.
 */
import { describe, expect, it } from "vitest";
import type { AgentCall, AgentOutcome, Backend } from "../src/backend.ts";
import { BudgetExhaustedError, runWorkflow } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal, splitRuns } from "../src/journal.ts";
import { chainKey } from "../src/key.ts";
import { ReplayBackend } from "../src/replay.ts";

const M = (b: string) => `export const meta = { name: 'p', description: 'probe', phases: [{ title: 'W' }] }\n${b}`;

/** Answers every prompt with its first word; prompts containing "slow" finish late; FAIL-set prompts fail. */
class Counting implements Backend {
  readonly name = "counting";
  readonly ran: string[] = [];
  constructor(readonly fail = new Set<string>()) {}
  async run(call: AgentCall): Promise<AgentOutcome> {
    this.ran.push(call.opts.label ?? call.prompt);
    if (call.prompt.includes("slow")) await new Promise((r) => setTimeout(r, 30));
    if (this.fail.has(call.prompt)) return { error: "down", usage: { inputTokens: 999, outputTokens: 10 } };
    return { text: call.prompt.split(" ")[0]!, usage: { inputTokens: 2000, outputTokens: 150 } };
  }
}

const SEQ = M(`const a = await agent('alpha', { label: 'a' })
const b = await agent('beta', { label: 'b' })
const c = await agent('gamma', { label: 'c' })
return { a, b, c }`);

const REORDER = M(`return await pipeline(['slow-x', 'fast-y'],
  (it) => agent('stage1 ' + it, { label: 's1:' + it }),
  (r, it) => agent('stage2 of ' + it + ' got ' + r, { label: 's2:' + it }))`);

describe("D04/D18: content-identity resume", () => {
  it("after a failed first call, an unchanged resume dispatches only that call (chain mode dispatches all three)", async () => {
    const j = new MemoryJournal();
    await runWorkflow(SEQ, { backend: new Counting(new Set(["alpha"])), journal: j, maxAttempts: 1 });
    const chain = new Counting();
    await runWorkflow(SEQ, { backend: chain, resumeFrom: parseJournal(j.text()) });
    expect(chain.ran).toEqual(["a", "b", "c"]); // the harness rule, kept as the default
    const content = new Counting();
    const r = await runWorkflow(SEQ, { backend: content, resumeFrom: parseJournal(j.text()), cacheIdentity: "content" });
    expect(content.ran).toEqual(["a"]);
    expect(r.calls.map((c) => c.state)).toEqual(["done", "cached", "cached"]);
    expect(r.result).toEqual({ a: "alpha", b: "beta", c: "gamma" });
  });

  it("an unchanged resume of a COMPLETED pipeline whose first item finished last dispatches nothing", async () => {
    const j = new MemoryJournal();
    const r1 = await runWorkflow(REORDER, { backend: new Counting(), journal: j });
    expect(r1.status).toBe("completed");
    const content = new Counting();
    const r2 = await runWorkflow(REORDER, { backend: content, resumeFrom: parseJournal(j.text()), cacheIdentity: "content" });
    expect(content.ran).toEqual([]);
    expect(r2.result).toEqual(r1.result);
  });

  it("started lines carry the cid; a harness journal without cids is looked up by chained key with no prefix rule", async () => {
    const j = new MemoryJournal();
    await runWorkflow(SEQ, { backend: new Counting(new Set(["alpha"])), journal: j, maxAttempts: 1 });
    expect(j.events.filter((e) => e.type === "started").every((e) => /^c1:[0-9a-f]{64}#1$/.test((e as { cid?: string }).cid ?? ""))).toBe(true);
    const stripped = j.events.map((e) => JSON.stringify(e.type === "started" ? { ...e, cid: undefined } : e)).join("\n") + "\n";
    const content = new Counting();
    await runWorkflow(SEQ, { backend: content, resumeFrom: parseJournal(stripped), cacheIdentity: "content" });
    expect(content.ran).toEqual(["a"]);
  });
});

describe("D14: journal values are validated against the call's schema", () => {
  const schema = { type: "object", properties: { n: { type: "integer" }, tags: { type: "array" } }, required: ["n", "tags"] };
  const src = M(`const r = await agent('count', { label: 'k', schema: ${JSON.stringify(schema)} }); return r`);
  const k = chainKey("", "count", { schema });
  const tampered = [{ type: "launched" }, { type: "started", key: k, agentId: "a1", label: "k" }, { type: "result", key: k, agentId: "a1", result: { n: "three", tags: "not-an-array" } }]
    .map((e) => JSON.stringify(e)).join("\n") + "\n";
  for (const mode of ["chain", "content"] as const) {
    it(`${mode}: a tampered cached value is a miss and the call runs again`, async () => {
      const backend: Backend = { name: "obj", run: async () => ({ object: { n: 3, tags: ["x"] } }) };
      const events: string[] = [];
      const r = await runWorkflow(src, { backend, resumeFrom: parseJournal(tampered), cacheIdentity: mode, events: { emit: (e) => events.push(e.type) } });
      expect(r.result).toEqual({ n: 3, tags: ["x"] });
      expect(r.calls[0]!.state).toBe("done");
      expect(events).toContain("cache_rejected");
    });
  }
});

describe("D10: tokens in the journal, and a resume keeps its spent", () => {
  const SIX = M(`const out = []; for (let i = 0; i < 6; i++) out.push(await agent('call ' + i)); return out`);
  it("result and failed lines carry tokens", async () => {
    const j = new MemoryJournal();
    await runWorkflow(SEQ, { backend: new Counting(new Set(["alpha"])), journal: j, maxAttempts: 1 });
    expect(j.events.filter((e) => e.type === "result" || e.type === "failed").map((e) => (e as { tokens?: number }).tokens)).toEqual([10, 150, 150]);
    expect(parseJournal(j.text()).tokensSpent).toBe(310);
  });
  it("6 calls of 150 tokens on a 300-token budget: the third throws", async () => {
    const r = await runWorkflow(SIX, { backend: new Counting(), budgetTotal: 300 });
    expect(r.status).toBe("failed");
    expect(r.error).toMatch(/budget exhausted \(300 of 300/);
    expect(r.calls).toHaveLength(2);
  });
  it("a resumed run starts from the spent its journal records; cache hits still replay", async () => {
    const j = new MemoryJournal();
    await runWorkflow(SIX, { backend: new Counting(), budgetTotal: 300, journal: j });
    const again = new Counting();
    const r = await runWorkflow(SIX, { backend: again, budgetTotal: 300, resumeFrom: parseJournal(j.text()), cacheIdentity: "content" });
    expect(again.ran).toEqual([]); // no fresh call: spent is already 300
    expect(r.calls.map((c) => c.state)).toEqual(["cached", "cached"]);
    expect(r.totalTokens).toBe(300);
    expect(r.error).toMatch(/budget exhausted/);
    expect(BudgetExhaustedError.name).toBe("BudgetExhaustedError");
  });
});

describe("D08: replaying a killed run keeps the calls in flight at the kill started-only", () => {
  const PS = M(`const [a, b] = await parallel([() => agent('A', { label: 'A' }), () => agent('B', { label: 'B' })]); return { a, b }`);
  const kA = chainKey("", "A", {});
  const kB = chainKey(kA, "B", {});
  const real = [
    { type: "launched" },
    { type: "started", key: kA, agentId: "a1", label: "A" },
    { type: "started", key: kB, agentId: "b1", label: "B" },
    { type: "result", key: kB, agentId: "b1", result: "rB" },
    { type: "started", key: kA, agentId: "a2", label: "A" },
    { type: "result", key: kA, agentId: "a2", result: "rA" },
  ].map((e) => JSON.stringify(e)).join("\n") + "\n";

  it("run 1 replays to the kill, its journal matches the real one, and run 2 resumed from it caches B", async () => {
    const runs = splitRuns(real);
    expect(runs).toHaveLength(2);
    const b1 = new ReplayBackend(parseJournal(runs[0]!));
    const j1 = new MemoryJournal();
    const first = await Promise.race([runWorkflow(PS, { backend: b1, journal: j1 }), b1.killed.then(() => "killed")]);
    expect(first).toBe("killed");
    expect(b1.parked.map((p) => p.label)).toEqual(["A"]);
    expect(j1.events.map((e) => `${e.type}${"key" in e ? (e.key === kA ? ":A" : ":B") : ""}`)).toEqual(["launched", "started:A", "started:B", "result:B"]);
    const b2 = new ReplayBackend(parseJournal(runs[1]!));
    const r = await runWorkflow(PS, { backend: b2, resumeFrom: parseJournal(j1.text()) });
    expect(r.result).toEqual({ a: "rA", b: "rB" });
    expect(r.calls.map((c) => [c.label, c.state])).toEqual([["A", "done"], ["B", "cached"]]);
    expect(b2.divergences).toHaveLength(0);
  });
});
