/**
 * Record fidelity: what the harness writes into the run record beyond the call
 * sequence, checked against every real record on this box (read in place,
 * skipped when absent), plus one synthetic test per rule.
 *
 * MEASURED from the records (2026-09-23 review):
 *  - a terminally failed call appends `[<label>] failed: <reason>` to `logs`,
 *    interleaved with the script's own log() lines (wf_cb547366-473: 25 lines,
 *    wf_e4049b3a-85d: 13 lines);
 *  - its workflow_agent row carries `error: <reason>` and `attempt: 1` (38 of 38
 *    error rows): a backend error is not retried by the harness;
 *  - resultPreview and promptPreview are the first 400 characters (JSON for a
 *    structured result) followed by an ellipsis;
 *  - a cached row has no `attempt`;
 *  - the run's `error` starts with the error's name ("TypeError: ..."), not the
 *    bare message;
 *  - `logs` also carries harness notices, `[<label>] [harness: subagent output
 *    matched instruction-shaped pattern(s) ...`, which an offline interpreter
 *    cannot reproduce; they are filtered out before comparing.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { runWorkflow, type RunResult } from "../src/interpreter.ts";
import { MemoryJournal, parseJournal, recordCacheHits, splitRuns } from "../src/journal.ts";
import { ReplayBackend } from "../src/replay.ts";
import { run } from "./helpers.ts";

const ROOTS = [
  process.env.NAIVE_PROJECTS ?? join(process.env.HOME ?? "", ".claude/projects/-home-tom-today"),
  join(process.env.HOME ?? "", ".claude-work/projects/-home-tom-today"),
];

interface Row {
  type: string;
  index: number;
  label?: string;
  agentId?: string;
  state: string;
  cached?: boolean;
  attempt?: number;
  error?: string;
  resultPreview?: string;
  promptPreview?: string;
}
interface Rec {
  runId: string;
  script: string;
  scriptPath?: string;
  args?: unknown;
  status: string;
  error?: string;
  logs?: string[];
  workflowProgress: Row[];
}

const HARNESS_NOTICE = /^\[[^\]]*\] \[harness: /;
const rows = (rec: { workflowProgress?: unknown }) =>
  (rec.workflowProgress as Row[]).filter((x) => x.type === "workflow_agent").sort((a, b) => a.index - b.index);

/** agentId -> the reason the record gives for its failure. */
export function failureReasons(rec: Rec): Map<string, string> {
  const m = new Map<string, string>();
  for (const r of rows(rec)) if (r.agentId && typeof r.error === "string") m.set(r.agentId, r.error);
  return m;
}

async function replayRecord(rec: Rec, journalText: string): Promise<RunResult> {
  // A hit the harness copied in from another runId is served from the cache, as the row says (r5).
  let history = recordCacheHits(rows(rec) as never, journalText);
  let r: RunResult | undefined;
  const reasons = failureReasons(rec);
  // Each run resumes from the REAL journal of the runs before it; a run killed
  // part way ends at its kill (ReplayBackend parks the calls in flight there).
  for (const part of splitRuns(journalText)) {
    const backend = new ReplayBackend(parseJournal(part), { failureReasons: reasons });
    const done = runWorkflow(rec.script, {
      backend,
      journal: new MemoryJournal(),
      args: rec.args,
      scriptPath: rec.scriptPath,
      ...(history && { resumeFrom: parseJournal(history) }),
    });
    const first = await Promise.race([done, backend.killed.then(() => undefined)]);
    r = first ?? r;
    history += part;
  }
  return r!;
}

const corpus: { rec: Rec; journal: string }[] = [];
for (const root of ROOTS) {
  if (!existsSync(root)) continue;
  for (const s of readdirSync(root)) {
    const wd = join(root, s, "workflows");
    if (!existsSync(wd)) continue;
    for (const f of readdirSync(wd)) {
      if (!/^wf_.*\.json$/.test(f)) continue;
      const rec = JSON.parse(readFileSync(join(wd, f), "utf8")) as Rec;
      const jp = join(root, s, "subagents", "workflows", rec.runId, "journal.jsonl");
      if (!existsSync(jp)) continue;
      if (rec.status !== "completed" && rec.status !== "failed") continue;
      corpus.push({ rec, journal: readFileSync(jp, "utf8") });
    }
  }
}

describe.skipIf(corpus.length === 0)("record fidelity, every finished real record under replay", () => {
  for (const { rec, journal } of corpus) {
    describe(`${rec.runId} (${rec.status})`, () => {
      let r: RunResult;
      it("logs: the script's lines and the harness's `[label] failed: reason` lines, in the recorded order", async () => {
        r = await replayRecord(rec, journal);
        expect(r.logs).toEqual((rec.logs ?? []).filter((l) => !HARNESS_NOTICE.test(l)));
      }, 120_000);
      it("rows: error, attempt, resultPreview and promptPreview as the harness writes them", () => {
        const ours = rows(r.record);
        const real = rows(rec);
        expect(ours).toHaveLength(real.length);
        real.forEach((x, i) => {
          const o = ours[i]!;
          expect(o.error, `row ${x.index} error`).toEqual(x.error);
          expect("attempt" in o, `row ${x.index} attempt present`).toBe("attempt" in x);
          if ("attempt" in x) expect(o.attempt, `row ${x.index} attempt`).toBe(x.attempt);
          expect(o.resultPreview, `row ${x.index} resultPreview`).toEqual(x.resultPreview);
          expect(o.promptPreview, `row ${x.index} promptPreview`).toEqual(x.promptPreview);
        });
      });
      if (rec.error !== undefined) {
        it("the run's error starts with the error's name and message, as the harness's does", () => {
          expect(r.error).toBeDefined();
          expect(rec.error!.startsWith(r.error!)).toBe(true);
          expect(r.error).toMatch(/^[A-Z][A-Za-z]*Error: /);
        });
      }
    });
  }
});

describe("synthetic: the same rules without the corpus", () => {
  it("a backend error is terminal: one attempt, a `[label] failed: reason` log line, and `error` on the row", async () => {
    const r = await run(`const a = await agent('p', { label: 'L' }); log('after'); return a`, {
      mock: { respond: () => ({ error: "limit reached" }) },
    });
    expect(r.result).toBeNull();
    expect(r.backendCalls).toHaveLength(1);
    expect(r.logs).toEqual(["[L] failed: limit reached", "after"]);
    expect(rows(r.record)[0]).toMatchObject({ state: "error", attempt: 1, error: "limit reached" });
  });
  it("previews are the first 400 characters and an ellipsis; a short value is kept whole", async () => {
    const long = "x".repeat(500);
    const r = await run(`return [await agent(${JSON.stringify(long)}), await agent('short')]`, {
      mock: { respond: (c) => ({ text: c.prompt === "short" ? "tiny" : "y".repeat(450) }) },
    });
    const [a, b] = rows(r.record);
    expect(a).toMatchObject({ promptPreview: `${"x".repeat(400)}…`, resultPreview: `${"y".repeat(400)}…` });
    expect(b).toMatchObject({ promptPreview: "short", resultPreview: "tiny" });
  });
  it("an uncaught throw fails the run with `<name>: <message>`", async () => {
    const r = await run(`throw new TypeError('nope')`);
    expect(r).toMatchObject({ status: "failed", error: "TypeError: nope" });
    expect(r.record.error).toBe("TypeError: nope");
  });
});
