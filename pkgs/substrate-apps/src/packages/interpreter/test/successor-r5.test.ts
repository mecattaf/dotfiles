import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentCall, AgentOutcome, Backend } from "../src/backend.ts";
import { MockBackend } from "../src/backend.ts";
import { main } from "../src/cli.ts";
import { runWorkflow } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal, recordCacheHits } from "../src/journal.ts";
import { chainKey } from "../src/key.ts";
import { ReplayBackend } from "../src/replay.ts";

const M = (b: string) => `export const meta = { name: 'r5', description: 'probe', phases: [{ title: 'W' }] }\n${b}`;

describe("r5: a budget refusal at admission is journaled, logged and replays with no flag", () => {
  it("concurrency 1, four-wide parallel, budget for two: calls 3 and 4 carry the reason; replay without --budget gives 0 divergences", async () => {
    const backend: Backend = { name: "b", run: async () => ({ text: "ok", usage: { inputTokens: 1, outputTokens: 75 } }) };
    const j = new MemoryJournal();
    const S = M(`return await parallel([1, 2, 3, 4].map((i) => () => agent('p' + i, { label: 'p' + i })))`);
    const live = await runWorkflow(S, { backend, budgetTotal: 150, concurrency: 1, journal: j });
    const rows = live.calls;
    expect(rows.filter((c) => c.state === "done")).toHaveLength(2);
    const refused = rows.filter((c) => c.state !== "done");
    expect(refused).toHaveLength(2);
    for (const c of refused) {
      expect(c.error).toMatch(/budget exhausted/);
      expect(c.agentId).toBeTruthy();
    }
    const lines = j.text().trim().split("\n").map((l) => JSON.parse(l) as { type: string; budgetExhausted?: boolean });
    expect(lines.filter((l) => l.type === "failed" && l.budgetExhausted === true)).toHaveLength(2);
    expect(live.logs.filter((l) => /\] failed: agent\(\): budget exhausted/.test(typeof l === "string" ? l : JSON.stringify(l)))).toHaveLength(2);
    expect((live.record as { budgetTotal?: number }).budgetTotal).toBe(150);
    const replay = new ReplayBackend(parseJournal(j.text()));
    const again = await runWorkflow(S, { backend: replay, concurrency: 1 });
    expect(again.result).toEqual(live.result);
    expect(replay.divergences).toEqual([]);
  });
});

describe("r5: a record's cached rows are served from the cache on replay", () => {
  const K1 = "v2:" + "a".repeat(64);
  const K2 = "v2:" + "b".repeat(64);
  it("recordCacheHits keeps only the started/result lines of rows marked cached", () => {
    const j = [
      { type: "launched" },
      { type: "started", key: K1, agentId: "a1" }, { type: "result", key: K1, agentId: "a1", result: "x" },
      { type: "started", key: K2, agentId: "a2" }, { type: "result", key: K2, agentId: "a2", result: "y" },
    ].map((e) => JSON.stringify(e)).join("\n");
    const hits = recordCacheHits([{ agentId: "a1", cached: true }, { agentId: "a2", cached: null }], j);
    expect(parseJournal(hits).results.has(K1)).toBe(true);
    expect(parseJournal(hits).results.has(K2)).toBe(false);
    expect(recordCacheHits([{ agentId: "a2" }], j)).toBe("");
  });
});
