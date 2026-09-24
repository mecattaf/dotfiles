import { describe, expect, it } from "vitest";
import { MockBackend, stubFromSchema, type AgentCall, type AgentOutcome, type Backend } from "../src/backend.ts";
import { defaultConcurrency, ITEMS_PER_CALL_CAP, LIFETIME_AGENT_CAP, runWorkflow } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal } from "../src/journal.ts";
import { SchemaPreflightError } from "../src/jsonschema.ts";
import { chainKey } from "../src/key.ts";
import { run, tick, wf } from "./helpers.ts";

const OBJ = `{ type: 'object', properties: { n: { type: 'integer', minimum: 3 }, tags: { type: 'array', items: { type: 'string' } } }, required: ['n'] }`;

describe("grammar: top-level await and top-level return in one script", () => {
  it("returns the value of a top-level return after top-level awaits", async () => {
    const r = await run(`const a = await agent('x'); const b = await Promise.resolve(2); if (b) return { a, b }; return 'unreached'`);
    expect(r.status).toBe("completed");
    expect(r.result).toEqual({ a: "[[m:#1]] mock result", b: 2 });
  });
  it("a script with no return completes with null", async () => {
    const r = await run(`await agent('x')`);
    expect(r.result).toBeNull();
  });
  it("an uncaught throw fails the run with its message", async () => {
    const r = await run(`throw new TypeError('nope')`);
    // The harness's error starts `<name>: <message>` (MEASURED, wf_12695394-85a; test/fidelity.test.ts).
    expect(r).toMatchObject({ status: "failed", error: "TypeError: nope" });
  });
});

describe("realm isolation and determinism guards", () => {
  it("exposes no host globals (V8 gives every context its own inert console, not the host's)", async () => {
    const r = await run(`return [typeof process, typeof require, typeof setTimeout, typeof fetch, typeof meta, typeof Buffer]`);
    expect(r.result).toEqual(["undefined", "undefined", "undefined", "undefined", "undefined", "undefined"]);
  });
  it("a builtin's constructor chain reaches only the realm's own Function", async () => {
    const r = await run(`return typeof agent.constructor.constructor('return this')().process`);
    expect(r.result).toBe("undefined");
  });
  it.each([
    ["Date.now()", "Date.now()"],
    ["Math.random()", "Math.random()"],
    ["argless new Date()", "new Date()"],
    ["Date() called as a function", "Date()"],
  ])("%s throws", async (_n, expr) => {
    const r = await run(`return ${expr}`);
    expect(r.status).toBe("failed");
    expect(r.error).toMatch(/not available in a workflow script/);
  });
  it("new Date(value), Date.UTC and Date.parse still work", async () => {
    const r = await run(`return [new Date(0).toISOString(), Date.UTC(2026, 8, 23), Date.parse('2026-09-23T00:00:00Z'), new Date(0) instanceof Date]`);
    expect(r.result).toEqual(["1970-01-01T00:00:00.000Z", Date.UTC(2026, 8, 23), Date.UTC(2026, 8, 23), true]);
  });
  it.each([
    ["argless Intl format() (D17)", "new Intl.DateTimeFormat('en-US', { timeStyle: 'medium', timeZone: 'UTC' }).format()"],
    ["argless Intl formatToParts() (D17)", "Intl.DateTimeFormat().formatToParts()"],
  ])("%s throws", async (_n, expr) => {
    const r = await run(`return ${expr}`);
    expect(r.status).toBe("failed");
    expect(r.error).toMatch(/Intl\.DateTimeFormat format(ToParts)?\(\) with no date is not available in a workflow script/);
  });
  it("D17: Intl and toLocaleString default to UTC, not the host zone; a given date and zone still format", async () => {
    // Mirrors critique-pass/scratch/parity-tally/probe/d17.js, which read "Europe/Paris" and the wall clock before.
    const r = await run(`return [Intl.DateTimeFormat().resolvedOptions().timeZone, new Intl.DateTimeFormat('en-US', { timeStyle: 'short' }).format(new Date(0)),
      new Intl.DateTimeFormat('en-US', { timeStyle: 'short', timeZone: 'Asia/Tokyo' }).format(new Date(0)), new Date(0).toLocaleString('en-US'),
      typeof Intl.DateTimeFormat.supportedLocalesOf, new Intl.DateTimeFormat('en-US', { timeZone: 'UTC' }).formatToParts(new Date(0)).length > 0]`);
    expect(r.status).toBe("completed");
    expect(r.result).toEqual(["UTC", "12:00 AM", "9:00 AM", "1/1/1970, 12:00:00 AM", "function", true]);
  });
  it("D17: Date's local-time accessors and multi-field constructor answer in UTC", async () => {
    const r = await run(`const d = new Date(0); const e = new Date(2026, 8, 23, 7); e.setHours(9); return [d.getHours(), d.getTimezoneOffset(), d.toString(), d.toDateString(), d.toTimeString(), e.toISOString(), e.getDay()]`);
    expect(r.result).toEqual([0, 0, "Thu, 01 Jan 1970 00:00:00 GMT", "Thu, 01 Jan 1970", "00:00:00 GMT", "2026-09-23T09:00:00.000Z", 3]);
  });
  it("D17: the Intl guard cannot be undone by the script", async () => {
    const r = await run(`try { Intl.DateTimeFormat = function () {} } catch {}; try { Date.prototype.toLocaleString = () => 'x' } catch {}; return [(() => { try { Intl.DateTimeFormat().format(); return 'ran' } catch { return 'threw' } })(), new Date(0).toLocaleString('en-US')]`);
    expect(r.result).toEqual(["threw", "1/1/1970, 12:00:00 AM"]);
  });
  it("a guard cannot be undone by the script", async () => {
    const r = await run(`try { Math.random = () => 4 } catch {}; try { globalThis.Date = function () {} } catch {}; return [typeof (()=>{ try { return Math.random() } catch { return 'threw' } })(), (()=>{ try { Date.now(); return 'ran' } catch { return 'threw' } })()]`);
    expect(r.result).toEqual(["string", "threw"]);
  });
});

describe("args are passed verbatim", () => {
  it.each([
    [{ outDir: "/x", n: [1, 2] }],
    ["a plain string, never parsed"],
    [42],
  ])("args = %j", async (args) => {
    const r = await run(`return args`, { args });
    expect(r.result).toEqual(args);
  });
  it("absent args are undefined", async () => {
    const r = await run(`return typeof args`);
    expect(r.result).toBe("undefined");
  });
  it("a string where the script expects an array fails the way the recorded run did (wf_12695394-85a)", async () => {
    const r = await run(`return args.repos.map(x => x)`, { args: { repos: "a b" } });
    expect(r.status).toBe("failed");
    expect(r.error).toMatch(/args\.repos\.map is not a function/);
  });
});

describe("agent()", () => {
  it("returns a string without a schema and a schema-valid object with one", async () => {
    const r = await run(`return [await agent('p'), await agent('q', { schema: ${OBJ} })]`);
    expect(r.result).toEqual(["[[m:#1]] mock result", { n: 3, tags: ["[[m:#2]] $.tags[0]"] }]);
  });
  it("retries a schema mismatch, then returns the first valid object", async () => {
    let n = 0;
    const r = await run(`return await agent('p', { schema: ${OBJ}, label: 'L' })`, {
      mock: { respond: () => (++n < 3 ? { object: { n: "three" } } : undefined) },
    });
    expect(r.result).toEqual({ n: 3, tags: ["[[m:L]] $.tags[0]"] });
    expect(r.calls[0]!.attempts).toBe(3);
    expect(r.backendCalls.map((c) => c.attempt)).toEqual([1, 2, 3]);
    expect(r.backendCalls[1]!.previousErrors?.[0]).toMatch(/\/n must be integer/);
  });
  it("returns null when every attempt mismatches, and journals one started and one failed", async () => {
    const journal = new MemoryJournal();
    const r = await run(`return await agent('p', { schema: ${OBJ} })`, { journal, mock: { respond: () => ({ object: {} }) } });
    expect(r.result).toBeNull();
    expect(r.calls[0]).toMatchObject({ state: "null", attempts: 3 });
    expect(journal.events.map((e) => e.type)).toEqual(["launched", "started", "failed"]);
    expect(r.record.workflowProgress).toContainEqual(expect.objectContaining({ type: "workflow_agent", state: "error" }));
  });
  it("returns null without retrying when the backend skips the call", async () => {
    const r = await run(`return await agent('p')`, { mock: { respond: () => ({ skipped: true }) } });
    expect(r.result).toBeNull();
    expect(r.backendCalls).toHaveLength(1);
  });
  it("does not retry a backend error: it is terminal, and the call returns null (38 of 38 real error rows say attempt 1)", async () => {
    const r = await run(`return await agent('p')`, { maxAttempts: 2, mock: { respond: () => ({ error: "boom" }) } });
    expect(r.result).toBeNull();
    expect(r.backendCalls).toHaveLength(1);
  });
  it("throws (not null) for a schema whose root is not an object or whose required names are missing", async () => {
    for (const schema of [`{ type: 'array' }`, `{ type: 'object', properties: {}, required: ['x'] }`]) {
      const r = await run(`try { await agent('p', { schema: ${schema} }); return 'no throw' } catch (e) { return e.message }`);
      expect(r.result).toMatch(/schema/);
    }
    expect(SchemaPreflightError).toBeDefined();
  });
  it("throws for a non-string prompt", async () => {
    const r = await run(`try { await agent(42) ; return 'no' } catch (e) { return e.message }`);
    expect(r.result).toMatch(/prompt must be a string/);
  });
  it("uses opts.phase, else the last phase() title, and the phase's declared model", async () => {
    const r = await run(`phase('B'); await agent('x'); await agent('y', { phase: 'A', label: 'l' }); return null`);
    expect(r.calls.map((c) => [c.phase, c.model, c.label])).toEqual([["B", "opus", undefined], ["A", undefined, "l"]]);
    expect(r.backendCalls[0]!.opts.model).toBe("opus");
  });
});

describe("parallel(): a barrier that never rejects", () => {
  it("waits for every thunk, keeps order, and turns throws (sync or async) into null", async () => {
    const r = await run(`
      const out = await parallel([
        () => agent('slow'),
        () => { throw new Error('sync') },
        async () => { await agent('x'); throw new Error('async') },
        () => 7,
      ])
      return out`, { mock: { latency: (c) => (c.prompt === "slow" ? 20 : 0) } });
    expect(r.result).toEqual(["[[m:#1]] mock result", null, null, 7]);
    expect(r.events.filter((e) => e.type === "item_null").map((e) => (e as { item: number }).item)).toEqual([1, 2]);
  });
  it(`caps items per call at ${ITEMS_PER_CALL_CAP}`, async () => {
    expect(ITEMS_PER_CALL_CAP).toBe(4096);
    const ok = await run(`return (await parallel(Array.from({ length: 4096 }, (_, i) => () => i))).length`);
    expect(ok.result).toBe(4096);
    const bad = await run(`return await parallel(Array.from({ length: 4097 }, () => () => 1))`);
    expect(bad.status).toBe("failed");
    expect(bad.error).toMatch(/4097 items exceeds the per-call cap of 4096/);
  });
});

describe("pipeline(): no barrier between stages", () => {
  it("passes (prev, item, index) and lets a fast item reach stage 2 while a slow item is in stage 1", async () => {
    const r = await run(`
      return await pipeline(['slow', 'fast'],
        (item, _i, index) => agent(item, { label: 's1:' + item }),
        (prev, item, index) => agent(prev + '|' + item + '|' + index, { label: 's2:' + item }),
      )`, { mock: { latency: (c) => (c.prompt === "slow" ? 30 : 0) } });
    const byLabel = Object.fromEntries(r.calls.map((c) => [c.label, c]));
    expect(byLabel["s2:fast"]!.startTick!).toBeLessThan(byLabel["s1:slow"]!.endTick!);
    expect(r.calls.map((c) => c.label)).toEqual(["s1:slow", "s1:fast", "s2:fast", "s2:slow"]);
    expect(r.backendCalls.find((c) => c.opts.label === "s2:fast")!.prompt).toBe("[[m:s1:fast]] mock result|fast|1");
    expect((r.result as string[]).length).toBe(2);
  });
  it("a throwing stage nulls only its item; a stage returning null still feeds the next stage", async () => {
    const r = await run(`
      return await pipeline([1, 2, 3],
        x => { if (x === 2) throw new Error('bad'); return x === 3 ? null : x },
        (prev, item) => prev === null ? 'saw null for ' + item : prev * 10,
      )`);
    expect(r.result).toEqual([10, null, "saw null for 3"]);
    expect(r.events).toContainEqual(expect.objectContaining({ type: "item_null", where: "pipeline", item: 1, stage: 0, reason: "bad" }));
  });
  it(`caps items per call at ${ITEMS_PER_CALL_CAP}`, async () => {
    const bad = await run(`return await pipeline(Array.from({ length: 4097 }, () => 1), x => x)`);
    expect(bad.error).toMatch(/per-call cap of 4096/);
  });
});

describe("phase() and log()", () => {
  it("records phases and logs in order", async () => {
    const r = await run(`phase('A'); log('one'); phase('B'); log(2); return null`);
    expect(r.phases).toEqual(["A", "B"]);
    expect(r.logs).toEqual(["one", "2"]);
    expect(r.events.filter((e) => e.type === "phase").map((e) => (e as { index?: number }).index)).toEqual([1, 2]);
  });
});

describe("budget: a hard ceiling", () => {
  it("reports total, spent() and remaining(); unlimited is null and Infinity", async () => {
    const r = await run(`return [budget.total, budget.spent(), budget.remaining()]`);
    expect(r.result).toEqual([null, 0, null]); // JSON turns Infinity into null
    const r2 = await run(`const a = budget.remaining() === Infinity; await agent('abcd'); return [a, budget.spent()]`);
    expect(r2.result).toEqual([true, 100]); // mock usage: 100 out; input tokens are not charged
  });
  it("makes agent() throw once spent reaches total, and the throw nulls a parallel item", async () => {
    const r = await run(`
      const first = await agent('abcd')
      const rest = await parallel([() => agent('x')])
      let top = 'no throw'
      try { await agent('y') } catch (e) { top = e.name + ': ' + e.message }
      return { first, rest, top, left: budget.remaining(), total: budget.total }`, { budgetTotal: 100 });
    expect(r.result).toMatchObject({ rest: [null], left: 0, total: 100 });
    expect((r.result as { top: string }).top).toMatch(/budget exhausted \(100 of 100/);
    expect(r.calls).toHaveLength(1);
  });
});

describe("caps", () => {
  it("default concurrency is min(16, cpus - 2), at least 1 (the real journals peak at 16 on this 32-cpu box)", () => {
    expect([defaultConcurrency(32), defaultConcurrency(18), defaultConcurrency(8), defaultConcurrency(2), defaultConcurrency(1)]).toEqual([16, 16, 6, 1, 1]);
  });
  it("never runs more agents at once than the cap", async () => {
    const r = await run(`return (await parallel(Array.from({ length: 40 }, (_, i) => () => agent('p' + i)))).length`, {
      concurrency: 5,
      mock: { latency: () => 2 },
    });
    expect(r.result).toBe(40);
    expect(r.peakConcurrency).toBe(5);
  });
  it(`the ${LIFETIME_AGENT_CAP + 1}th agent() of a run throws`, async () => {
    expect(LIFETIME_AGENT_CAP).toBe(1000);
    const r = await run(`
      const out = await parallel(Array.from({ length: 1001 }, (_, i) => () => agent('p' + i)))
      return [out.filter(x => x !== null).length, out[1000]]`, { concurrency: 16 });
    expect(r.result).toEqual([1000, null]);
    expect(r.events).toContainEqual(expect.objectContaining({ type: "item_null", item: 1000, reason: expect.stringMatching(/lifetime cap of 1000/) }));
  });
});

describe("workflow(): one level of nesting", () => {
  const child = wf(`log('child ' + args.n); const r = await agent('child prompt ' + args.n); return { r, n: args.n }`);
  const grand = wf(`return await workflow('child', { n: 2 })`);
  const resolveWorkflow = (ref: string) => ({ source: ref === "child" ? child : grand, path: `/virtual/${ref}.js` });

  it("runs a named child with args and returns its result; its agents count toward the parent's run", async () => {
    const r = await run(`const a = await agent('parent'); const c = await workflow('child', { n: 1 }); return { a, c }`, { resolveWorkflow });
    expect(r.result).toEqual({ a: "[[m:#1]] mock result", c: { r: "[[m:#2]] mock result", n: 1 } });
    expect(r.calls.map((c) => c.depth)).toEqual([0, 1]);
    expect(r.logs).toEqual(["child 1"]);
  });
  it("accepts a { name } or { scriptPath } reference", async () => {
    const r = await run(`return [(await workflow({ name: 'child' }, { n: 3 })).n, (await workflow({ scriptPath: 'child' }, { n: 4 })).n]`, { resolveWorkflow });
    expect(r.result).toEqual([3, 4]);
  });
  it("a workflow() inside a nested workflow throws", async () => {
    const r = await run(`try { await workflow('grand'); return 'nested twice' } catch (e) { return e.message }`, { resolveWorkflow });
    expect(r.result).toMatch(/nesting is limited to 1 level/);
  });
});

describe("resume: the longest unchanged prefix of agent() calls", () => {
  const SEQ = `const a = await agent('one'); const b = await agent(PROMPT2); const c = await agent('three'); return [a, b, c]`;
  async function first(body = SEQ.replace("PROMPT2", "'two'")) {
    const journal = new MemoryJournal();
    const r = await run(body, { journal });
    return { r, text: journal.text() };
  }

  it("an unchanged script is answered entirely from the journal, and hits are not re-journaled", async () => {
    const { r, text } = await first();
    const backend = new MockBackend({ latency: () => 0 });
    const journal = new MemoryJournal();
    const again = await runWorkflow(wf(SEQ.replace("PROMPT2", "'two'")), { backend, resumeFrom: parseJournal(text), journal });
    expect(again.result).toEqual(r.result);
    expect(again.calls.map((c) => c.state)).toEqual(["cached", "cached", "cached"]);
    expect(backend.calls).toHaveLength(0);
    expect(journal.events).toEqual([]); // no `launched`, no started/result lines for hits
  });
  it("changing call 2 keeps call 1 cached and re-runs calls 2 and 3 (their chained keys change)", async () => {
    const { text } = await first();
    const backend = new MockBackend({ latency: () => 0 });
    const r = await runWorkflow(wf(SEQ.replace("PROMPT2", "'TWO'")), { backend, resumeFrom: parseJournal(text) });
    expect(r.calls.map((c) => c.state)).toEqual(["cached", "done", "done"]);
    expect(backend.calls.map((c) => c.prompt)).toEqual(["TWO", "three"]);
  });
  it("after the first miss, later calls re-run even when their key has a result (wf_7382b31b-d3e shows this)", async () => {
    const o = {};
    const k1 = chainKey("", "one", o), k2 = chainKey(k1, "two", o), k3 = chainKey(k2, "three", o);
    const text = [
      { type: "launched" },
      { type: "started", key: k1, agentId: "a1" }, { type: "result", key: k1, agentId: "a1", result: "R1" },
      { type: "started", key: k2, agentId: "a2" }, { type: "failed", key: k2, agentId: "a2" },
      { type: "started", key: k3, agentId: "a3" }, { type: "result", key: k3, agentId: "a3", result: "R3" },
    ].map((e) => JSON.stringify(e)).join("\n");
    const backend = new MockBackend({ latency: () => 0 });
    const r = await runWorkflow(wf(SEQ.replace("PROMPT2", "'two'")), { backend, resumeFrom: parseJournal(text) });
    expect(r.calls.map((c) => [c.key, c.state])).toEqual([[k1, "cached"], [k2, "done"], [k3, "done"]]);
    expect((r.result as string[])[2]).not.toBe("R3");
  });
  it("a key started but never finished (the run was killed in flight) is re-run without ending the prefix", async () => {
    const o = {};
    const k1 = chainKey("", "a", o), k2 = chainKey(k1, "b", o);
    const text = [
      { type: "started", key: k1, agentId: "a1" },
      { type: "started", key: k2, agentId: "a2" }, { type: "result", key: k2, agentId: "a2", result: "RB" },
    ].map((e) => JSON.stringify(e)).join("\n");
    const backend = new MockBackend({ latency: () => 0 });
    const r = await runWorkflow(wf(`return [await agent('a'), await agent('b')]`), { backend, resumeFrom: parseJournal(text) });
    expect(r.calls.map((c) => c.state)).toEqual(["done", "cached"]);
    expect(r.result).toEqual(["[[m:#1]] mock result", "RB"]);
  });

  describe("a no-barrier pipeline whose recorded completion order differs from its invocation order", () => {
    const PIPE = `return await pipeline(['slow', 'fast'], x => agent(x, { label: 'a:' + x }), (p, x) => agent('b ' + p, { label: 'b:' + x }))`;
    async function recorded() {
      const journal = new MemoryJournal();
      await run(PIPE, { journal, mock: { latency: (c) => (c.prompt === "slow" ? 25 : 0) } });
      return parseJournal(journal.text());
    }
    it("immediate cache release (the harness's, MEASURED) re-runs the reordered later stage", async () => {
      const backend = new MockBackend({ latency: () => 0 });
      const r = await runWorkflow(wf(PIPE), { backend, resumeFrom: await recorded() });
      expect(r.calls.filter((c) => c.state !== "cached").length).toBeGreaterThan(0);
    });
    it("recorded cache release (opt-in) answers every call from the journal", async () => {
      const backend = new MockBackend({ latency: () => 0 });
      const r = await runWorkflow(wf(PIPE), { backend, resumeFrom: await recorded(), cacheRelease: "recorded" });
      expect(r.calls.map((c) => c.state)).toEqual(["cached", "cached", "cached", "cached"]);
      expect(backend.calls).toHaveLength(0);
    });
  });
});

describe("resume key", () => {
  it("is a v2 sha256 chain over (previous key, prompt, keyed opts); label and phase are not keyed; key order is not significant", () => {
    const a = chainKey("", "p", { schema: { type: "object", properties: { x: {}, y: {} } }, model: "opus", label: "L", phase: "P" });
    const b = chainKey("", "p", { model: "opus", schema: { properties: { y: {}, x: {} }, type: "object" } });
    expect(a).toBe(b);
    expect(a).toMatch(/^v2:[0-9a-f]{64}$/);
    expect(chainKey(a, "p", {})).not.toBe(chainKey(b + "0", "p", {}));
    expect(chainKey("", "p", { effort: "low" })).not.toBe(chainKey("", "p", {}));
  });
});

describe("MockBackend: schema-satisfying and deterministic by call ordinal", () => {
  it("two runs of the same script give identical results, calls and journals", async () => {
    const body = `phase('A'); const xs = await parallel([1,2,3].map(i => () => agent('p' + i, { schema: ${OBJ} }))); return [xs, await agent('z')]`;
    const j1 = new MemoryJournal(), j2 = new MemoryJournal();
    const a = await run(body, { journal: j1, mock: { latency: (c) => (4 - c.index) * 3 } });
    const b = await run(body, { journal: j2, mock: { latency: (c) => (4 - c.index) * 3 } });
    expect(a.result).toEqual(b.result);
    expect(j1.text().replace(/"agentId":"[^"]*"/g, "")).toBe(j2.text().replace(/"agentId":"[^"]*"/g, ""));
  });
  it("covers $ref, anyOf, enum, const, minItems, minLength, nullable types", () => {
    const schema = {
      type: "object",
      $defs: { Sev: { enum: ["high", "low"] } },
      properties: {
        sev: { $ref: "#/$defs/Sev" },
        k: { const: "K" },
        u: { anyOf: [{ type: "null" }, { type: "number", minimum: 5 }] },
        l: { type: "array", minItems: 2, items: { type: "string", minLength: 12 } },
        n: { type: ["null", "boolean"] },
      },
    };
    expect(stubFromSchema(schema, "t")).toEqual({ sev: "high", k: "K", u: 5, l: ["t $.l[0]____", "t $.l[1]____"], n: true });
  });
});

describe("backend contract", () => {
  it("a backend that throws (infrastructure failure) fails the call's caller, not silently", async () => {
    const backend: Backend = { name: "throws", run: async (_c: AgentCall): Promise<AgentOutcome> => { throw new Error("socket closed") } };
    const r = await runWorkflow(wf(`return await agent('x')`), { backend });
    expect(r).toMatchObject({ status: "failed", error: "Error: socket closed" });
    await tick();
  });
});
