// Critique pass 2026-09-24 (AUDIT-reverify-interp): each open item as the test that failed before its fix.
import { describe, expect, it } from "vitest";
import { MockBackend } from "../src/backend.ts";
import { retryableFailure } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal } from "../src/journal.ts";
import { run } from "./helpers.ts";

describe("D17: Intl.DateTimeFormat with no date does not read the clock", () => {
  const body = `const t = (f) => { try { return f() } catch (e) { return 'threw:' + e.message } };
    return {
      fmt: t(() => new Intl.DateTimeFormat('en', { second: 'numeric', timeZone: 'UTC' }).format()),
      fmtUndef: t(() => new Intl.DateTimeFormat('en', { second: 'numeric', timeZone: 'UTC' }).format(undefined)),
      parts: t(() => new Intl.DateTimeFormat('en', { second: 'numeric', timeZone: 'UTC' }).formatToParts().length),
      callable: t(() => Intl.DateTimeFormat('en', { second: 'numeric', timeZone: 'UTC' }).format()),
      detached: t(() => { const f = new Intl.DateTimeFormat('en', { timeZone: 'UTC' }).format; return f(); }),
      epoch: t(() => new Intl.DateTimeFormat('en', { timeZone: 'UTC' }).format(0)),
      epochParts: t(() => new Intl.DateTimeFormat('en', { year: 'numeric', timeZone: 'UTC' }).formatToParts(0)[0].value),
      redefine: t(() => { Object.defineProperty(Intl.DateTimeFormat.prototype, 'formatToParts', { value: () => 1 }); return 'redefined'; }),
    };`;
  it("every argless form throws the ban; an explicit date still formats", async () => {
    const r = await run(body);
    expect(r.status).toBe("completed");
    const v = r.result as Record<string, string>;
    for (const k of ["fmt", "fmtUndef", "parts", "callable", "detached"]) expect(v[k], k).toMatch(/^threw:Intl\.DateTimeFormat .* with no date is not available in a workflow script/);
    expect(v.epoch).toBe("1/1/1970");
    expect(v.epochParts).toBe("1970");
    expect(v.redefine).toMatch(/^threw:/);
  });
});

describe("D09 carried: string codegen through AsyncFunction stays in the realm (probe awaited)", () => {
  it("typeof process is undefined and Date.now() is banned inside AsyncFunction code", async () => {
    const r = await run(`
      const AF = agent.constructor;
      const out = { name: AF.name };
      out.proc = await AF('return typeof process')();
      try { await AF('return Date.now()')(); out.now = 'ran'; } catch (e) { out.now = 'threw'; }
      return out;`);
    expect(r.result).toEqual({ name: "AsyncFunction", proc: "undefined", now: "threw" });
  });
});

describe("C3-5: a journaled terminal failure on resume", () => {
  const body = `const a = await agent('prep'); const b = await agent('act'); return { a, b };`;
  const firstRun = async () => {
    const j = new MemoryJournal();
    const failing = new MockBackend({ latency: () => 0, respond: (c) => (c.prompt === "act" ? { error: "boom" } : undefined) as never });
    const r1 = await run(body, { backend: failing, journal: j, cacheIdentity: "content", maxAttempts: 1 });
    expect(r1.result).toEqual({ a: expect.any(String), b: null });
    return j;
  };
  const modes = [["content", { cacheIdentity: "content" }], ["chain", {}], ["recorded", { cacheIdentity: "content", cacheRelease: "recorded" }]] as const;
  for (const [mode, extra] of modes) {
    it(`${mode}: "retry" (default) runs it again and the null can become a value`, async () => {
      const j = await firstRun();
      const ok = new MockBackend({ latency: () => 0 });
      const r2 = await run(body, { backend: ok, resumeFrom: parseJournal(j.text()), maxAttempts: 1, ...extra });
      expect(ok.calls.map((c) => c.prompt)).toEqual(["act"]);
      expect((r2.result as { b: unknown }).b).not.toBeNull();
    });
    it(`${mode}: "replay" answers it from the journal as the same null, with no dispatch`, async () => {
      const j = await firstRun();
      const ok = new MockBackend({ latency: () => 0 });
      const r2 = await run(body, { backend: ok, resumeFrom: parseJournal(j.text()), maxAttempts: 1, resumeFailures: "replay", ...extra });
      expect(ok.calls.map((c) => c.prompt)).toEqual([]);
      expect(r2.status).toBe("completed");
      expect((r2.result as { b: unknown }).b).toBeNull();
      expect(r2.calls.map((c) => c.state)).toEqual(["cached", "null"]);
      expect(r2.calls[1]!.error).toBe("boom");
    });
  }
  it(`"replay" still retries a failure where nothing ran (capacity refused, aborted) and a budget refusal`, async () => {
    for (const error of ["conwip capacity refused (slots-full): every cc slot is held", "conwip: aborted while waiting for a slot"]) {
      const j = new MemoryJournal();
      const b1 = new MockBackend({ latency: () => 0, respond: (c) => (c.prompt === "act" ? { error } : undefined) as never });
      await run(body, { backend: b1, journal: j, cacheIdentity: "content", maxAttempts: 1 });
      const ok = new MockBackend({ latency: () => 0 });
      await run(body, { backend: ok, resumeFrom: parseJournal(j.text()), cacheIdentity: "content", resumeFailures: "replay" });
      expect(ok.calls.map((c) => c.prompt), error).toEqual(["act"]);
    }
    const j = new MemoryJournal();
    await run(body, { journal: j, cacheIdentity: "content", budgetTotal: 1, mock: { respond: () => ({ text: "x", usage: { inputTokens: 0, outputTokens: 5 } }) as never } }).catch(() => undefined);
    const ok = new MockBackend({ latency: () => 0 });
    await run(body, { backend: ok, resumeFrom: parseJournal(j.text()), cacheIdentity: "content", resumeFailures: "replay" });
    expect(ok.calls.map((c) => c.prompt)).toEqual(["act"]);
  });
  it(`"replay" retries a failure that a later start already retried and was killed in flight`, async () => {
    const j = await firstRun();
    const text = j.text() + JSON.stringify({ type: "started", key: parseJournal(j.text()).startOrder[1]!.key, agentId: "later", cid: parseJournal(j.text()).startOrder[1]!.cid }) + "\n";
    const ok = new MockBackend({ latency: () => 0 });
    await run(body, { backend: ok, resumeFrom: parseJournal(text), cacheIdentity: "content", resumeFailures: "replay" });
    expect(ok.calls.map((c) => c.prompt)).toEqual(["act"]);
  });
});

// HF-reverify-interp: claims VERIFY-reverify-interp found untested.

describe("D17: the guarded format getter keeps the spec's one bound function per formatter", () => {
  it("f.format === f.format, two formatters differ, and a cached format still bans the argless call", async () => {
    const r = await run(`const f = new Intl.DateTimeFormat('en', { timeZone: 'UTC' }); const g = new Intl.DateTimeFormat('en', { timeZone: 'UTC' });
      const h = f.format; let threw = ''; try { h() } catch (e) { threw = e.message }
      return { same: f.format === f.format, other: f.format === g.format, epoch: h(0), threw };`);
    expect(r.status).toBe("completed");
    const v = r.result as Record<string, unknown>;
    expect(v.same).toBe(true);
    expect(v.other).toBe(false);
    expect(v.epoch).toBe("1/1/1970");
    expect(String(v.threw)).toMatch(/with no date is not available in a workflow script/);
  });
});

describe("C3-5: retryableFailure over the real reason strings", () => {
  it("retries refusals where nothing ran; replays a harness exit even when its output says refused or aborted", () => {
    for (const r of [
      "conwip capacity refused (slots-full): every cc slot is held", "conwip refused the route: x", "conwip: aborted while waiting for a slot",
      "runtime cx refused: bound to no capacity seat", 'agent({runtime: "x"}) refused: not allowed (t)', "budget exhausted",
      "runtime cx: job dir /j already exists (EEXIST); refusing to reuse it", "skipped", "journal: failed", "runner threw: ENOENT",
    ]) expect(retryableFailure(r), r).toBe(true);
    for (const r of [
      "runtime cx: codex exited 1: dial tcp: connection refused", "runtime cc: claude exited 137 (timeout): aborted by signal",
      "runtime cx: codex exited 2: boom", "schema mismatch: /a must be string", "no text output", "boom",
    ]) expect(retryableFailure(r), r).toBe(false);
  });
  it(`"replay" replays a harness verdict whose stderr mentions "connection refused"`, async () => {
    const body = `const a = await agent('prep'); const b = await agent('act'); return { a, b };`;
    const error = "runtime cx: codex exited 1: dial tcp 127.0.0.1:9: connection refused";
    const j = new MemoryJournal();
    const b1 = new MockBackend({ latency: () => 0, respond: (c) => (c.prompt === "act" ? { error } : undefined) as never });
    await run(body, { backend: b1, journal: j, cacheIdentity: "content", maxAttempts: 1 });
    const ok = new MockBackend({ latency: () => 0 });
    const r2 = await run(body, { backend: ok, resumeFrom: parseJournal(j.text()), cacheIdentity: "content", resumeFailures: "replay", maxAttempts: 1 });
    expect(ok.calls.map((c) => c.prompt)).toEqual([]);
    expect((r2.result as { b: unknown }).b).toBeNull();
  });
});

describe("D06: the lane epoch is distinct per start", () => {
  it("a resumed start journals its lanes under e<events at load>, never e0, so no call is a sibling of an earlier start's", async () => {
    const body = `return await parallel([() => agent('x1'), () => agent('x2')]);`;
    const j = new MemoryJournal();
    await run(body, { journal: j, cacheIdentity: "content" });
    const lines = j.text().trim().split("\n");
    const firstLanes = lines.map((l) => JSON.parse(l)).filter((e) => e.type === "started").map((e) => e.lane);
    expect(firstLanes.every((l: string) => /^e0\.r1\/1:[01]$/.test(l))).toBe(true);
    const kept = lines.slice(0, -1).join("\n") + "\n"; // the last result line is lost
    const loaded = parseJournal(kept);
    const j2 = new MemoryJournal();
    await run(body, { journal: j2, resumeFrom: loaded, cacheIdentity: "content" });
    const again = j2.text().trim().split("\n").map((l) => JSON.parse(l)).filter((e) => e.type === "started" && e.lane !== undefined).map((e) => e.lane as string);
    expect(again.length).toBeGreaterThan(0);
    for (const l of again) expect(l).toMatch(new RegExp(`^e${loaded.events.length}\\.r1/1:[01]$`));
    expect(loaded.events.length).toBeGreaterThan(0);
  });
});
