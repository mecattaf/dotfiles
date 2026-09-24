/**
 * Successor review round 3 (2026-09-23), interpreter half: the failure reason
 * on the failed line (D08), a content-resumed journal replays under its own
 * rule, a call's occurrence is fixed at invocation, and a backend that finds
 * the budget spent at its own admission ends the call as the budget does.
 */
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MockBackend, type AgentCall, type Backend } from "../src/backend.ts";
import { main } from "../src/cli.ts";
import { runWorkflow } from "../src/interpreter.ts";
import { FileJournal, MemoryJournal, parseJournal } from "../src/journal.ts";
import { ReplayBackend } from "../src/replay.ts";

const src = `export const meta = { name: 'fr', description: 'd', phases: [{ title: 'A' }] };
phase('A');
const r = await parallel([() => agent('ok', { label: 'good' }), () => agent('bad', { label: 'bad' })]);
return r;`;

describe("r3 D08: the failed line carries its reason", () => {
  it("the live run journals the reason, and a replay of that journal reports it instead of 'journal: failed'", async () => {
    const j = new MemoryJournal();
    await runWorkflow(src, { backend: new MockBackend({ respond: (c) => (c.opts.label === "bad" ? { error: "harness exit 1: rate limited" } : undefined) }), journal: j });
    const line = JSON.parse(j.text().split("\n").find((l) => l.includes('"failed"'))!) as { error?: string };
    expect(line.error).toBe("harness exit 1: rate limited");
    const rep = await runWorkflow(src, { backend: new ReplayBackend(parseJournal(j.text())) });
    expect(rep.logs).toContain("[bad] failed: harness exit 1: rate limited");
    const row = (rep.record.workflowProgress as Array<{ label?: string; error?: string }>).find((e) => e.label === "bad");
    expect(row?.error).toBe("harness exit 1: rate limited");
  });
});

describe("r3: naive-run replays a successor (content-identity) journal under the rule that wrote it", () => {
  it("a completed content-resumed run replays as completed with the recorded result", async () => {
    const dir = mkdtempSync(join(tmpdir(), "axc-r3-replay-"));
    const script = join(dir, "seq.js");
    writeFileSync(script, `export const meta = { name: 'seq', description: 'd', phases: [{ title: 'A' }] };
phase('A');
const a = await agent('first', { label: 'a' });
const b = await agent('second', { label: 'b' });
const c = await agent('third', { label: 'c' });
return [a, b, c];`);
    const s = readFileSync(script, "utf8");
    const jp = join(dir, "journal.jsonl");
    let failA = true;
    const backend = new MockBackend({ respond: (c) => (c.opts.label === "a" && failA ? { error: "transient: harness exit 1" } : undefined) });
    await runWorkflow(s, { backend, journal: new FileJournal(jp), cacheIdentity: "content" });
    failA = false;
    const r2 = await runWorkflow(s, { backend, journal: new FileJournal(jp), cacheIdentity: "content", resumeFrom: parseJournal(readFileSync(jp, "utf8")) });
    expect(r2.status).toBe("completed");
    const out = await main([script, "--backend", "replay", "--replay", jp, "--print-result"]);
    const o = JSON.parse(out.out) as { status: string; divergences: number; result: unknown };
    expect(out.code).toBe(0);
    expect(o.status).toBe("completed");
    expect(o.divergences).toBe(0);
    expect(o.result).toEqual(r2.result);
  });
});

describe("r3: the call carries its occurrence and cid, fixed at invocation", () => {
  it("three identical calls are occurrences 1, 2, 3 on every attempt", async () => {
    const seen: Array<[string | undefined, number | undefined, number]> = [];
    let n = 0;
    const backend: Backend = {
      name: "rec",
      run: async (c: AgentCall) => {
        seen.push([c.opts.label, c.occurrence, c.attempt]);
        n++;
        // The first reply of every call is empty: each is retried once.
        return c.attempt === 1 ? {} : { text: "ok" };
      },
    };
    await runWorkflow(`export const meta = { name: 'v', description: 'd', phases: [{ title: 'A' }] };
phase('A');
return await parallel([1, 2, 3].map(() => () => agent('vote', {})));`, { backend, maxAttempts: 2 });
    expect(n).toBe(6);
    const byOcc = new Map<number, number[]>();
    for (const [, occ, att] of seen) byOcc.set(occ!, [...(byOcc.get(occ!) ?? []), att]);
    expect([...byOcc.keys()].sort()).toEqual([1, 2, 3]);
    for (const atts of byOcc.values()) expect(atts.sort()).toEqual([1, 2]);
  });
});

describe("r3 D10: a backend's own admission can find the budget spent", () => {
  it("an outcome marked budgetExhausted ends the call as the budget does, and spends nothing", async () => {
    let asked = 0;
    // A backend with a WIP cap of 1: calls queue here after passing the
    // interpreter's own check, and ask the budget again when they leave the queue.
    let chain: Promise<unknown> = Promise.resolve();
    const backend: Backend = {
      name: "queued",
      run: (c: AgentCall) => {
        const p = chain.then(() => once(c));
        chain = p.catch(() => undefined);
        return p;
      },
    };
    const once = async (c: AgentCall) => {
        asked++;
        await new Promise((r) => setTimeout(r, 5));
        const why = c.budgetExhausted?.();
        if (why !== undefined) return { error: why, budgetExhausted: true };
        return { text: "ran", usage: { inputTokens: 0, outputTokens: 100 } };
    };
    const r = await runWorkflow(`export const meta = { name: 'b', description: 'd', phases: [{ title: 'A' }] };
phase('A');
return await parallel([1, 2, 3, 4].map((i) => () => agent('p' + i, {})));`, { backend, budgetTotal: 100, concurrency: 4 });
    expect(r.calls.filter((c) => c.state === "done")).toHaveLength(1);
    expect(asked).toBe(4);
    expect(r.record.totalTokens).toBe(100);
  });
});
