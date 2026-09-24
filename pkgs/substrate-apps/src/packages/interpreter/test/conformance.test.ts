/**
 * Conformance against what Claude Code actually did.
 *
 * Oracles, all read in place (never copied into the repo, they hold private
 * results): the run records ~/.claude/projects/-home-tom-today/<session>/workflows/wf_*.json
 * (script, args, result, workflowProgress in invocation order) and the journals
 * .../subagents/workflows/<runId>/journal.jsonl (keys, labels, phases, results).
 * A test whose inputs are absent on this box is skipped, not passed.
 */
import { existsSync, mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MockBackend } from "../src/backend.ts";
import { main } from "../src/cli.ts";
import { runWorkflow, type CallRecord, type RunResult } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal, recordCacheHits, splitRuns, type LoadedJournal } from "../src/journal.ts";
import { ReplayBackend } from "../src/replay.ts";
import { covers } from "./helpers.ts";

const ROOTS = [
  process.env.NAIVE_PROJECTS ?? join(process.env.HOME ?? "", ".claude/projects/-home-tom-today"),
  join(process.env.HOME ?? "", ".claude-work/projects/-home-tom-today"),
];
const E59 = join(ROOTS[0]!, "e59fc066-efe6-4b87-961e-dd08d420ff51");
const S178 = join(ROOTS[0]!, "178f37b2-adfd-4490-b746-e71294b721ea");

interface Rec {
  runId: string;
  script: string;
  scriptPath?: string;
  args?: unknown;
  status: string;
  agentCount: number;
  result: unknown;
  workflowProgress: { type: string; index: number; label?: string; phaseTitle?: string; state: string; cached?: boolean }[];
}
interface Case {
  rec: Rec;
  recPath: string;
  journalText: string;
  scriptFile: string | undefined;
}

function load(session: string, runId: string): Case | undefined {
  const recPath = join(session, "workflows", `${runId}.json`);
  const jPath = join(session, "subagents", "workflows", runId, "journal.jsonl");
  if (!existsSync(recPath) || !existsSync(jPath)) return undefined;
  const rec = JSON.parse(readFileSync(recPath, "utf8")) as Rec;
  const scriptFile = rec.scriptPath && existsSync(rec.scriptPath) ? rec.scriptPath : undefined;
  return { rec, recPath, journalText: readFileSync(jPath, "utf8"), scriptFile };
}

const agentsOf = (rec: Rec) => rec.workflowProgress.filter((x) => x.type === "workflow_agent").sort((a, b) => a.index - b.index);
const recState = (x: { state: string; cached?: boolean }) => (x.cached ? "cached" : x.state === "error" ? "null" : x.state);

/**
 * Replay every run held in the journal, each resuming from the REAL journal of
 * the runs before it (the joined splitRuns prefix), as the harness did. Resuming
 * from the replay's own journal instead made an earlier run's replay decide what
 * the next run keeps, and an earlier run may have been killed, or run an earlier
 * edit of the script (wf_70fb1fc5-b3b, wf_85776b29-1e1): the record holds only
 * the final script. `divergences` counts the FINAL run only. A run that reaches
 * its kill (only calls in flight at the kill remain, parked by ReplayBackend)
 * ends there: `r` is then undefined and `queued` holds the keys it invoked.
 */
async function replayAll(c: Case, source?: string): Promise<{ r: RunResult; divergences: number; runs: string[]; ours: string; queued: string[]; killed: boolean }> {
  const runs = splitRuns(c.journalText);
  // A hit the harness copied in from another runId is served from the cache, as the row says (r5).
  let history = recordCacheHits(agentsOf(c.rec) as never, c.journalText);
  let r: RunResult | undefined;
  let divergences = 0;
  let ours = "";
  let queued: string[] = [];
  let killed = false;
  for (const run of runs) {
    const backend = new ReplayBackend(parseJournal(run));
    const journal = new MemoryJournal();
    queued = [];
    const events = { emit: (e: { type: string; key?: string }) => { if (e.type === "agent_queued") queued.push(e.key!); } };
    const done = runWorkflow(source ?? c.rec.script, {
      backend,
      journal,
      events,
      args: c.rec.args,
      scriptPath: c.rec.scriptPath,
      ...(history && { resumeFrom: parseJournal(history) }),
    });
    const first = await Promise.race([done, backend.killed.then(() => "killed" as const)]);
    killed = first === "killed";
    r = killed ? undefined : (first as RunResult);
    ours += journal.text();
    history += run;
    divergences = backend.divergences.length;
  }
  return { r: r!, divergences, runs, ours, queued, killed };
}

const terminalLines = (j: LoadedJournal) =>
  j.events.filter((e) => e.type !== "launched").map((e) => `${e.type} ${"key" in e ? e.key : ""}`).sort();

// ------------------------------------------------------------------ the two named real scripts

const NAMED = [
  { runId: "wf_bae1093b-2ad", name: "orthogonal-overnight-review", readers: 8 },
  { runId: "wf_8f24b273-9a7", name: "substrate-cloudflare-thread", readers: 6 },
];

for (const n of NAMED) {
  const c = load(E59, n.runId);
  describe.skipIf(!c || !c.scriptFile)(`${n.name} (${n.runId}), the script file on disk`, () => {
    const source = () => readFileSync(c!.scriptFile!, "utf8");

    it("the script file is the script the record ran", () => {
      expect(source()).toBe(c!.rec.script);
    });

    describe("ReplayBackend: reproduces the real run exactly", () => {
      it("same chained keys in the same invocation order as the journal, zero divergences", async () => {
        const { r, divergences } = await replayAll(c!, source());
        const j = parseJournal(c!.journalText);
        expect(divergences).toBe(0);
        expect(r.calls.map((x) => x.key)).toEqual(j.startOrder.map((s) => s.key));
      });
      it("same labels, phases and states in the record's invocation order, and the same return value", async () => {
        const { r } = await replayAll(c!, source());
        expect(r.status).toBe(c!.rec.status);
        expect(r.calls).toHaveLength(c!.rec.agentCount);
        expect(r.calls.map((x) => [x.label, x.phase, x.state])).toEqual(agentsOf(c!.rec).map((x) => [x.label, x.phaseTitle, recState(x)]));
        expect(r.result).toEqual(c!.rec.result);
      });
      it("the journal it writes carries the same started/result lines as the real one", async () => {
        const { ours } = await replayAll(c!, source());
        expect(terminalLines(parseJournal(ours))).toEqual(terminalLines(parseJournal(c!.journalText)));
        expect(ours.startsWith('{"type":"launched"}\n')).toBe(true);
      });
    });

    describe("MockBackend: same call graph and return shape, no recorded data used", () => {
      let r: RunResult;
      let mock: MockBackend;
      const recAgents = () => agentsOf(c!.rec);
      const byLabel = (l: string | undefined) => r.calls.find((x) => x.label === l)!;

      it("runs to completion with the recorded agent count and the same label multiset and phase per label", async () => {
        mock = new MockBackend();
        r = await runWorkflow(source(), { backend: mock, args: c!.rec.args, scriptPath: c!.scriptFile });
        expect(r.status).toBe("completed");
        expect(r.calls).toHaveLength(c!.rec.agentCount);
        const phaseOf = (xs: { label?: string; phase?: string }[]) => xs.map((x) => `${x.label}@${x.phase}`).sort();
        expect(phaseOf(r.calls.map((x) => ({ label: x.label, phase: x.phase })))).toEqual(
          phaseOf(recAgents().map((x) => ({ label: x.label, phase: x.phaseTitle }))),
        );
        expect(r.phases).toEqual(["Read", "Judge"]);
      });
      it("ordering: the readers first in script order, then one verifier per reader, then the judges in script order", () => {
        const rec = recAgents();
        const k = n.readers;
        expect(r.calls.slice(0, k).map((x) => x.label)).toEqual(rec.slice(0, k).map((x) => x.label));
        expect(r.calls.slice(k, 2 * k).every((x) => x.phase === "Verify")).toBe(true);
        expect(r.calls.slice(2 * k).map((x) => x.label)).toEqual(rec.slice(2 * k).map((x) => x.label));
      });
      it("ordering: each verifier starts after its own reader ended and embeds that reader's output (data-flow edge)", () => {
        const reads = r.calls.slice(0, n.readers);
        for (const v of r.calls.filter((x) => x.phase === "Verify")) {
          const src = reads.filter((rd) => v.prompt.includes(`[[m:${rd.label}]]`));
          expect(src).toHaveLength(1);
          expect(v.startTick!).toBeGreaterThan(src[0]!.endTick!);
        }
      });
      it("ordering: the pipeline has no barrier, and the judges wait for every verifier (the parallel is after a barrier)", () => {
        const verifies = r.calls.filter((x) => x.phase === "Verify");
        const reads = r.calls.slice(0, n.readers);
        expect(Math.min(...verifies.map((x) => x.startTick!))).toBeLessThan(Math.max(...reads.map((x) => x.endTick!)));
        const lastVerifyEnd = Math.max(...verifies.map((x) => x.endTick!));
        for (const j of r.calls.filter((x) => x.phase === "Judge")) {
          expect(j.startTick!).toBeGreaterThan(lastVerifyEnd);
          for (const rd of reads) expect(j.prompt).toContain(`[[m:${rd.label}]]`);
        }
      });
      it("final return shape: the real result fits the mock result's shape", () => {
        const real = c!.rec.result as { readers: { key: string }[]; judges: { key: string }[] };
        const got = r.result as typeof real;
        expect(Object.keys(got)).toEqual(Object.keys(real));
        expect(got.readers.map((x) => x.key)).toEqual(real.readers.map((x) => x.key));
        expect(got.judges.map((x) => x.key)).toEqual(real.judges.map((x) => x.key));
        const extra: string[] = [];
        real.readers.forEach((x, i) => expect(covers(got.readers[i], x, `readers[${i}]`, extra)).toEqual([]));
        real.judges.forEach((x, i) => expect(covers(got.judges[i], x, `judges[${i}]`, extra)).toEqual([]));
        // Real agents may add keys the schema does not forbid; there are few, and they are listed here.
        expect(extra.length).toBeLessThanOrEqual(2);
      });
      it("is deterministic: a second mock run gives the same calls and the same result", async () => {
        const again = await runWorkflow(source(), { backend: new MockBackend(), args: c!.rec.args });
        expect(again.calls.map((x: CallRecord) => [x.label, x.key])).toEqual(r.calls.map((x) => [x.label, x.key]));
        expect(again.result).toEqual(r.result);
      });
    });
  });
}

// ------------------------------------------------------------------ the one real resume on disk

describe.skipIf(!load(S178, "wf_7382b31b-d3e"))("estate-plan-3-weeks (wf_7382b31b-d3e): a real failed run and its resume in one journal", () => {
  const c = load(S178, "wf_7382b31b-d3e")!;
  it("splitRuns finds the two runs (one `launched` line only)", () => {
    const runs = splitRuns(c.journalText);
    expect(runs.map((r) => r.trim().split("\n").length)).toEqual([105, 98]);
    expect(c.journalText.match(/"type":"launched"/g)).toHaveLength(1);
  });
  it("replaying run 1 then resuming into run 2 reproduces the record: 6 cached, 49 fresh, same order, same result", async () => {
    const { r, divergences } = await replayAll(c);
    expect(divergences).toBe(0);
    expect(r.calls.map((x) => [x.label, x.phase, x.state])).toEqual(agentsOf(c.rec).map((x) => [x.label, x.phaseTitle, recState(x)]));
    expect(r.calls.filter((x) => x.state === "cached")).toHaveLength(6);
    expect(r.result).toEqual(c.rec.result);
  });
  it("releasing cache hits in recorded order instead does NOT reproduce it: the harness releases hits immediately", async () => {
    const runs = splitRuns(c.journalText);
    const j1 = new MemoryJournal();
    await runWorkflow(c.rec.script, { backend: new ReplayBackend(parseJournal(runs[0]!)), journal: j1, args: c.rec.args });
    const r2 = await runWorkflow(c.rec.script, {
      backend: new ReplayBackend(parseJournal(runs[1]!)),
      args: c.rec.args,
      resumeFrom: parseJournal(j1.text()),
      cacheRelease: "recorded",
    });
    expect(r2.calls.map((x) => x.label)).not.toEqual(agentsOf(c.rec).map((x) => x.label));
  });
  it("journal `started` order is NOT invocation order on resume; the record's index is", () => {
    const run2 = parseJournal(splitRuns(c.journalText)[1]!).startOrder.map((s) => s.label);
    const recFresh = agentsOf(c.rec).filter((x) => !x.cached).map((x) => x.label);
    expect(new Set(run2)).toEqual(new Set(recFresh));
    expect(run2).not.toEqual(recFresh);
  });
});

describe.skipIf(!existsSync(join(ROOTS[1]!, "debdd34c-5ac5-47d0-ad60-5014731d873f")))("wf_70fb1fc5-b3b (.claude-work): a killed run resumed after the script was edited", () => {
  const c = load(join(ROOTS[1]!, "debdd34c-5ac5-47d0-ad60-5014731d873f"), "wf_70fb1fc5-b3b")!;
  it("splits at the re-invoked in-flight label and reproduces 14 cached + 12 fresh", async () => {
    expect(splitRuns(c.journalText).map((r) => r.trim().split("\n").length)).toEqual([34, 24]);
    const { r, divergences } = await replayAll(c);
    expect(divergences).toBe(0);
    expect(r.calls.filter((x) => x.state === "cached")).toHaveLength(14);
    expect(r.result).toEqual(c.rec.result);
  });
});

// ------------------------------------------------------------------ every record on disk

const corpus: { session: string; runId: string }[] = [];
for (const root of ROOTS) {
  if (!existsSync(root)) continue;
  for (const s of readdirSync(root)) {
    const wd = join(root, s, "workflows");
    if (!existsSync(wd)) continue;
    for (const f of readdirSync(wd)) if (/^wf_.*\.json$/.test(f)) corpus.push({ session: join(root, s), runId: f.slice(0, -5) });
  }
}

describe.skipIf(corpus.length === 0)("corpus: every run record with a journal on this box, under replay", () => {
  for (const { session, runId } of corpus) {
    const c = load(session, runId);
    if (!c) continue;
    const finished = c.rec.status === "completed" || c.rec.status === "failed";
    it(`${runId} ${c.rec.status}: ${finished ? "exact sequence and result" : "key prefix up to the kill"}`, async () => {
      const { r, divergences, runs, queued } = await replayAll(c);
      if (finished) {
        expect(divergences).toBe(0);
        expect(r.calls.map((x) => [x.label, x.phase, x.state])).toEqual(agentsOf(c.rec).map((x) => [x.label, x.phaseTitle, recState(x)]));
        expect(r.result).toEqual(c.rec.result);
      } else {
        // A killed or still-running record: every call the FINAL run started is
        // invoked by the replay of that run. Earlier runs may have run an earlier
        // edit of the script, and a resume's started order is not its invocation
        // order (wf_7382b31b-d3e), so this is a set inclusion, not a prefix.
        // The record's `script` is the script its FIRST run started with; a resume
        // after an edit ran the file on disk (wf_85776b29-1e1: 13215 vs 14577
        // bytes), so when the record's script misses, the file is tried too.
        const started = parseJournal(runs.at(-1)!).startOrder.map((s) => s.key);
        const missingIn = (x: { r: RunResult | undefined; queued: string[] }) => {
          const invoked = new Set(x.r ? x.r.calls.map((y) => y.key) : x.queued);
          return started.filter((k) => !invoked.has(k));
        };
        let missing = missingIn({ r, queued });
        if (missing.length > 0 && c.scriptFile) {
          const onDisk = readFileSync(c.scriptFile, "utf8");
          if (onDisk !== c.rec.script) missing = missingIn(await replayAll(c, onDisk));
        }
        expect(missing).toEqual([]);
      }
    }, 120_000);
  }
});

// ------------------------------------------------------------------ the CLI

describe.skipIf(!load(E59, "wf_bae1093b-2ad"))("naive-run CLI", () => {
  const recPath = join(E59, "workflows", "wf_bae1093b-2ad.json");
  it("replays a run record by path, with its own script, args and journal", async () => {
    const dir = mkdtempSync(join(tmpdir(), "naive-run-"));
    const { code, out } = await main([recPath, "--backend", "replay", "--journal", dir, "--print-result"]);
    expect(code).toBe(0);
    const s = JSON.parse(out) as { divergences: number; agentCount: number; result: unknown };
    expect(s).toMatchObject({ divergences: 0, agentCount: 19 });
    expect(s.result).toEqual(load(E59, "wf_bae1093b-2ad")!.rec.result);
    expect(existsSync(join(dir, "record.json")) && existsSync(join(dir, "events.jsonl"))).toBe(true);
  });
  it("mock-runs a script, then resumes it in place from --journal", async () => {
    const dir = mkdtempSync(join(tmpdir(), "naive-run-"));
    const script = join(E59, "workflows", "scripts", "orthogonal-overnight-review-wf_bae1093b-2ad.js");
    const a = JSON.parse((await main([script, "--backend", "mock", "--journal", dir])).out) as { cached: number; agentCount: number };
    const b = JSON.parse((await main([script, "--backend", "mock", "--journal", dir])).out) as { cached: number };
    expect([a.cached, a.agentCount]).toEqual([0, 19]);
    expect(b.cached).toBeGreaterThanOrEqual(8); // the readers at least; see the pipeline-resume weakness in NAIVE.md
    const lines = readFileSync(join(dir, "journal.jsonl"), "utf8").trim().split("\n");
    expect(lines.filter((l) => l.includes('"launched"'))).toHaveLength(1);
  });
  it("rejects bad usage with exit code 2", async () => {
    expect((await main([])).code).toBe(2);
    expect((await main([recPath, "--backend", "claude"])).code).toBe(2);
    expect((await main([recPath, "--args", "{not json"])).code).toBe(2);
  });
});
