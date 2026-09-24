// Critique pass 2026-09-24 (AUDIT-reverify-interp), runners half: C3-4 outcome records and adoption.
import { existsSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { IDEMPOTENCY_ENV, outcomeRecordFile, RunnerBackend, stableJobIdFor } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import type { Job, Runner, RunResult } from "../src/job.ts";
import { fakeBin, tmp } from "./helpers.ts";

const fakeRunner = (answer: () => Partial<RunResult>, seen: Job[]): Runner => ({
  name: "h", type: "host", refuses: () => undefined,
  run: async (job) => { seen.push(job); return { runtime: "h", jobId: job.id, exitCode: 0, stdout: "", stderr: "", durationMs: 1, ...answer() } as RunResult; },
});
const config = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\nharness = "codex"\n`, "t");
const ok = '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}\n';
const call = (over: Record<string, unknown> = {}) => ({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1, cid: "abcdef0123456789abcd-1", ...over }) as never;

describe("C3-4: outcome records", () => {
  const guard = (f: () => Promise<void>) => async () => {
    const saved = process.env.AX_CONWIP_TEST_SEAT; process.env.AX_CONWIP_TEST_SEAT = "1";
    const savedPath = process.env.PATH; const bin = tmp(); fakeBin(bin, "codex", "exit 0"); process.env.PATH = `${bin}:${savedPath}`;
    try { await f(); } finally {
      process.env.PATH = savedPath;
      if (saved === undefined) delete process.env.AX_CONWIP_TEST_SEAT; else process.env.AX_CONWIP_TEST_SEAT = saved;
    }
  };
  it("a success is recorded; a later start with the same cid and attempt adopts it without running", guard(async () => {
    const root = tmp(); const seen: Job[] = [];
    const out1 = await new RunnerBackend(config, { jobsRoot: root, runId: "r", runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } }).run(call());
    expect(out1).toMatchObject({ text: "done" });
    expect((seen[0] as { env?: Record<string, string> }).env?.[IDEMPOTENCY_ENV]).toBe(stableJobIdFor("r", "abcdef0123456789abcd-1", 1));
    const out2 = await new RunnerBackend(config, { jobsRoot: root, runId: "r", start: 2, runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } }).run(call({ index: 7 }));
    expect(seen).toHaveLength(1);
    expect(out2).toMatchObject({ text: "done", adoptedFrom: "r-1-a1" });
    // Another attempt of the same call, or a call with no cid, runs.
    await new RunnerBackend(config, { jobsRoot: root, runId: "r", start: 2, runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } }).run(call({ attempt: 2 }));
    await new RunnerBackend(config, { jobsRoot: root, runId: "r", start: 3, runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } }).run(call({ cid: undefined }));
    expect(seen).toHaveLength(3);
  }));
  it("a failure is not recorded (it runs again, as a retry), and a record through a link is not adopted", guard(async () => {
    const root = tmp(); const seen: Job[] = [];
    const b = new RunnerBackend(config, { jobsRoot: root, runId: "r", runners: { h: fakeRunner(() => ({ exitCode: 1, stderr: "boom" }), seen) } });
    expect((await b.run(call())).error).toMatch(/exited 1/);
    const rec = outcomeRecordFile(root, stableJobIdFor("r", "abcdef0123456789abcd-1", 1));
    expect(existsSync(rec)).toBe(false);
    const real = join(root, "planted.json");
    writeFileSync(real, JSON.stringify({ v: 1, jobId: "x", outcome: { text: "planted" } }));
    symlinkSync(real, rec);
    const out = await new RunnerBackend(config, { jobsRoot: root, runId: "r", start: 2, runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } }).run(call());
    expect(out).toMatchObject({ text: "done" });
    expect(seen).toHaveLength(2);
  }));
});

// HF-reverify-interp (CRITIQUE-PASS C3-4): the stable id is built from the REAL cid format,
// `c1:<64 hex>#<occurrence>` (interpreter key.ts contentId), and keeps the occurrence.
describe("C3-4: the stable id is injective over the real cid format", () => {
  const h = "a".repeat(64);
  const cid = (n: number, hash = h) => `c1:${hash}#${n}`;
  it("occurrences, attempts, hashes and non-canonical cids never share an id", () => {
    const ids = [
      stableJobIdFor("r", cid(1), 1), stableJobIdFor("r", cid(2), 1), stableJobIdFor("r", cid(12), 1),
      stableJobIdFor("r", cid(1), 2), stableJobIdFor("r", cid(1, "b".repeat(64)), 1),
      // Same first 14 hash characters, different tail: the old id truncated them together.
      stableJobIdFor("r", cid(1, "a".repeat(14) + "b".repeat(50)), 1),
      stableJobIdFor("r", "abcdef0123456789abcd-1", 1), stableJobIdFor("r", "abcdef0123456789abcd-2", 1),
      stableJobIdFor("r", "x#1", 1), stableJobIdFor("r", "x_1", 1), stableJobIdFor("r", "x-1", 1),
    ];
    expect(new Set(ids).size).toBe(ids.length);
    // The canonical form is readable: the full hash and the occurrence both survive.
    expect(stableJobIdFor("r", cid(2), 3)).toBe(`r-c${h}o2-a3`);
    for (const id of ids) expect(id).toMatch(/^[A-Za-z0-9_.-]{1,200}$/);
  });
  it("two calls with the same content and different occurrences both run; each is adopted only by itself", async () => {
    const saved = process.env.AX_CONWIP_TEST_SEAT; process.env.AX_CONWIP_TEST_SEAT = "1";
    const savedPath = process.env.PATH; const bin = tmp(); fakeBin(bin, "codex", "exit 0"); process.env.PATH = `${bin}:${savedPath}`;
    try {
      const root = tmp(); const seen: Job[] = [];
      const b = () => new RunnerBackend(config, { jobsRoot: root, runId: "r", runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } });
      const o1 = await b().run(call({ index: 1, cid: cid(1) }));
      const o2 = await b().run(call({ index: 2, cid: cid(2) }));
      expect(seen).toHaveLength(2);
      expect(o1).not.toHaveProperty("adoptedFrom");
      expect(o2).not.toHaveProperty("adoptedFrom");
      const keys = seen.map((j) => (j as { env?: Record<string, string> }).env?.[IDEMPOTENCY_ENV]);
      expect(keys).toEqual([stableJobIdFor("r", cid(1), 1), stableJobIdFor("r", cid(2), 1)]);
      expect(new Set(keys).size).toBe(2);
      // A resume adopts each occurrence from its own record.
      const r2 = new RunnerBackend(config, { jobsRoot: root, runId: "r", start: 2, runners: { h: fakeRunner(() => ({ stdout: ok }), seen) } });
      expect(await r2.run(call({ index: 1, cid: cid(2) }))).toMatchObject({ adoptedFrom: "r-2-a1" });
      expect(await r2.run(call({ index: 2, cid: cid(1) }))).toMatchObject({ adoptedFrom: "r-1-a1" });
      expect(seen).toHaveLength(2);
    } finally {
      process.env.PATH = savedPath;
      if (saved === undefined) delete process.env.AX_CONWIP_TEST_SEAT; else process.env.AX_CONWIP_TEST_SEAT = saved;
    }
  });
});
