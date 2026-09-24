/**
 * Successor review, fix round 2 (2026-09-23), interpreter half:
 *  - budget.spent() counts output tokens only (the dialect), not input + output;
 *  - a replay charges the tokens its journal records, so a budgeted run
 *    replays as the same run;
 *  - identical calls are told apart by occurrence on a content resume;
 *  - naive-run on a killed or divergent journal says so and exits non-zero.
 */
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentCall, AgentOutcome, Backend } from "../src/backend.ts";
import { MockBackend } from "../src/backend.ts";
import { main } from "../src/cli.ts";
import { runWorkflow } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal } from "../src/journal.ts";
import { chainKey } from "../src/key.ts";
import { ReplayBackend } from "../src/replay.ts";

const M = (b: string) => `export const meta = { name: 'p2', description: 'probe', phases: [{ title: 'W' }] }\n${b}`;
const LOOP = M(`let n = 0
while (budget.total && budget.remaining() > 0 && n < 50) { await agent('step ' + n); n++ }
return { n, spent: budget.spent() }`);

describe("budget.spent() counts output tokens only", () => {
  it("2000 input and 10 output per call on a 1000 budget: 50 calls, spent 500", async () => {
    const backend: Backend = { name: "fat-input", run: async () => ({ text: "ok", usage: { inputTokens: 2000, outputTokens: 10 } }) };
    const r = await runWorkflow(LOOP, { backend, budgetTotal: 1000 });
    expect(r.result).toEqual({ n: 50, spent: 500 });
  });
  it("the ceiling throws on output tokens: 100 in, 50 out, budget 300 gives 6 calls", async () => {
    const backend: Backend = { name: "b", run: async () => ({ text: "ok", usage: { inputTokens: 100, outputTokens: 50 } }) };
    const r = await runWorkflow(LOOP, { backend, budgetTotal: 300 });
    expect(r.result).toEqual({ n: 6, spent: 300 });
  });
});

describe("a replay accounts for the journal's tokens", () => {
  it("a budgeted live run and its replay give the same result and 0 divergences", async () => {
    const j = new MemoryJournal();
    const live = await runWorkflow(LOOP, { backend: new MockBackend({ latency: () => 0 }), budgetTotal: 350, journal: j });
    expect(live.status).toBe("completed");
    const replay = new ReplayBackend(parseJournal(j.text()));
    const again = await runWorkflow(LOOP, { backend: replay, budgetTotal: 350 });
    expect(again.result).toEqual(live.result);
    expect(replay.divergences).toEqual([]);
  });
});

/** Answers every call; the prompts in `fail` fail on their Nth occurrence only. */
class Votes implements Backend {
  readonly name = "votes";
  ran = 0;
  seen = 0;
  constructor(readonly failAt: number | undefined) {}
  async run(_call: AgentCall): Promise<AgentOutcome> {
    this.ran++;
    this.seen++;
    if (this.seen === this.failAt) return { error: "down" };
    return { text: `v${this.seen}` };
  }
}
const VOTE = M(`const a = await agent('judge the diff'); const b = await agent('judge the diff'); const c = await agent('judge the diff'); return [a, b, c]`);

describe("identical calls are counted by occurrence on a content resume (D04/D18 majority vote)", () => {
  for (const failAt of [3, 1]) {
    it(`three identical votes, vote ${failAt} failed: the resume dispatches only that vote`, async () => {
      const j = new MemoryJournal();
      await runWorkflow(VOTE, { backend: new Votes(failAt), journal: j, maxAttempts: 1 });
      const again = new Votes(undefined);
      const r = await runWorkflow(VOTE, { backend: again, resumeFrom: parseJournal(j.text()), cacheIdentity: "content" });
      expect(again.ran).toBe(1);
      expect((r.result as string[]).filter((v) => v !== null)).toHaveLength(3);
      expect(r.calls.map((c) => c.state).filter((s) => s === "cached")).toHaveLength(2);
    });
  }
});

describe("naive-run on a killed or divergent journal", () => {
  const dir = mkdtempSync(join(tmpdir(), "axc-cli-r2-"));
  const script = join(dir, "ps.js");
  writeFileSync(script, M(`const [a, b] = await parallel([() => agent('A', { label: 'A' }), () => agent('B', { label: 'B' })]); return { a, b }`));
  const kA = chainKey("", "A", {});
  const kB = chainKey(kA, "B", {});
  const jl = (evs: object[]) => evs.map((e) => JSON.stringify(e)).join("\n") + "\n";

  it("a journal whose only run was killed: status killed, the parked call named, exit 4", async () => {
    const killed = join(dir, "killed.jsonl");
    writeFileSync(killed, jl([{ type: "launched" }, { type: "started", key: kA, agentId: "a1", label: "A" }, { type: "started", key: kB, agentId: "b1", label: "B" }, { type: "result", key: kB, agentId: "b1", result: "rB" }]));
    const out = await main([script, "--backend", "replay", "--replay", killed]);
    expect(out.code).toBe(4);
    const o = JSON.parse(out.out);
    expect(o.status).toBe("killed");
    expect(o.parked.map((p: { label: string }) => p.label)).toEqual(["A"]);
  });
  it("a killed run followed by its resume replays through to the resumed run", async () => {
    const both = join(dir, "both.jsonl");
    writeFileSync(both, jl([
      { type: "launched" }, { type: "started", key: kA, agentId: "a1", label: "A" }, { type: "started", key: kB, agentId: "b1", label: "B" }, { type: "result", key: kB, agentId: "b1", result: "rB" },
      { type: "launched" }, { type: "started", key: kA, agentId: "a2", label: "A" }, { type: "result", key: kA, agentId: "a2", result: "rA" },
    ]));
    const out = await main([script, "--backend", "replay", "--replay", both, "--print-result"]);
    expect(out.code).toBe(0);
    expect(JSON.parse(out.out).result).toEqual({ a: "rA", b: "rB" });
  });
  it("a final run that reaches an unwitnessed call is 'diverged', exit 1, never 'completed'", async () => {
    const seq = join(dir, "seq.js");
    writeFileSync(seq, M(`const a = await agent('A'); const b = await agent('B'); const c = await agent('C'); return { a, b, c }`));
    const kOld = chainKey(kA, "B (an older prompt)", {});
    const div = join(dir, "diverge.jsonl");
    writeFileSync(div, jl([{ type: "launched" }, { type: "started", key: kA, agentId: "a1" }, { type: "result", key: kA, agentId: "a1", result: "A" }, { type: "started", key: kOld, agentId: "b1" }, { type: "result", key: kOld, agentId: "b1", result: "B" }]));
    const out = await main([seq, "--backend", "replay", "--replay", div]);
    expect(out.code).toBe(1);
    const o = JSON.parse(out.out);
    expect(o.status).toBe("diverged");
    expect(o.divergences).toBe(2);
  });
});
