/**
 * naive-run: run one workflow script offline, under the mock or the replay backend.
 *
 *   naive-run <script.js | record.json> [--args <json>] [--backend mock|replay]
 *             [--journal <dir>] [--replay <journal.jsonl>] [--concurrency N]
 *             [--budget N] [--max-attempts N] [--print-result]
 *
 * <script> may be a workflow .js or a Claude Code run record (workflows/wf_*.json):
 * a record brings its own `script` and `args`, and under --backend replay its
 * journal is found at ../subagents/workflows/<runId>/journal.jsonl.
 *
 * --journal <dir> holds this run's journal.jsonl (harness format), events.jsonl
 * and record.json. If journal.jsonl already exists the run RESUMES from it
 * (longest unchanged prefix) and appends to it, as the harness does.
 *
 * Under --backend replay a journal holding several runs (a resumed recording) is
 * replayed run by run, each resuming from the ones before it, so the last run's
 * record is reproduced. Nothing here calls a model.
 *
 * Exit codes: 0 completed; 1 failed, or a replay whose final run diverged from
 * its journal (status "diverged"); 2 usage; 3 crash; 4 the final recorded run
 * was killed (status "killed", with the calls it had in flight).
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { MockBackend } from "./backend.ts";
import { runWorkflow, type RunResult } from "./interpreter.ts";
import { FileEventSink, FileJournal, MemoryJournal, parseJournal, splitRuns, type JournalSink } from "./journal.ts";
import { ReplayBackend } from "./replay.ts";

export interface CliOutcome {
  readonly code: number;
  readonly out: string;
}

interface Parsed {
  script: string;
  args: unknown;
  argsGiven: boolean;
  backend: "mock" | "replay";
  journalDir: string | undefined;
  replay: string | undefined;
  concurrency: number | undefined;
  budget: number | undefined;
  maxAttempts: number | undefined;
  /** Replay rule; default: "content" when the journal carries `cid` lines, else the harness's "chain". */
  cacheIdentity: "chain" | "content" | undefined;
  printResult: boolean;
}

const USAGE =
  "usage: naive-run <script.js|record.json> [--args <json>] [--backend mock|replay] [--journal <dir>] [--replay <journal.jsonl>] [--concurrency N] [--budget N] [--max-attempts N] [--cache-identity chain|content] [--print-result]";

function parseArgv(argv: readonly string[]): Parsed {
  const p: Parsed = {
    script: "",
    args: undefined,
    argsGiven: false,
    backend: "mock",
    journalDir: undefined,
    replay: undefined,
    concurrency: undefined,
    budget: undefined,
    cacheIdentity: undefined,
    maxAttempts: undefined,
    printResult: false,
  };
  const num = (flag: string, v: string | undefined) => {
    const n = Number(v);
    if (v === undefined || !Number.isFinite(n) || n < 0) throw new Error(`${flag} needs a non-negative number`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} needs a value`);
      return v;
    };
    switch (a) {
      case "--args": {
        const v = next();
        try {
          p.args = JSON.parse(v);
        } catch (e) {
          throw new Error(`--args is not JSON: ${(e as Error).message}`);
        }
        p.argsGiven = true;
        break;
      }
      case "--backend": {
        const v = next();
        if (v !== "mock" && v !== "replay") throw new Error(`--backend must be mock or replay, not '${v}'`);
        p.backend = v;
        break;
      }
      case "--journal":
        p.journalDir = next();
        break;
      case "--replay":
        p.replay = next();
        break;
      case "--concurrency":
        p.concurrency = num(a, next());
        break;
      case "--cache-identity": {
        const v = next();
        if (v !== "chain" && v !== "content") throw new Error(`--cache-identity must be chain or content, got ${v}`);
        p.cacheIdentity = v;
        break;
      }
      case "--budget":
        p.budget = num(a, next());
        break;
      case "--max-attempts":
        p.maxAttempts = num(a, next());
        break;
      case "--print-result":
        p.printResult = true;
        break;
      default:
        if (a.startsWith("--")) throw new Error(`unknown flag ${a}`);
        if (p.script) throw new Error(`one script only (got '${p.script}' and '${a}')`);
        p.script = a;
    }
  }
  if (!p.script) throw new Error("no script given");
  return p;
}

interface Loaded {
  source: string;
  scriptPath: string;
  args: unknown;
  recordedJournal: string | undefined;
  /** From a run record's rows: agentId -> the reason its call failed (journals do not carry it). */
  failureReasons: Map<string, string>;
}

function reasonsOf(rec: { workflowProgress?: unknown }): Map<string, string> {
  const m = new Map<string, string>();
  if (!Array.isArray(rec.workflowProgress)) return m;
  for (const r of rec.workflowProgress as { type?: unknown; agentId?: unknown; error?: unknown }[]) {
    if (r && r.type === "workflow_agent" && typeof r.agentId === "string" && typeof r.error === "string") m.set(r.agentId, r.error);
  }
  return m;
}

function loadInput(p: Parsed): Loaded {
  const path = resolve(p.script);
  const text = readFileSync(path, "utf8");
  if (path.endsWith(".json")) {
    const rec = JSON.parse(text) as { script?: unknown; args?: unknown; runId?: unknown; scriptPath?: unknown; workflowProgress?: unknown };
    if (typeof rec.script !== "string") throw new Error(`${path} is JSON but has no string 'script' field (not a run record)`);
    const runId = typeof rec.runId === "string" ? rec.runId : basename(path, ".json");
    const j = join(dirname(path), "..", "subagents", "workflows", runId, "journal.jsonl");
    return {
      source: rec.script,
      scriptPath: typeof rec.scriptPath === "string" ? rec.scriptPath : path,
      args: p.argsGiven ? p.args : rec.args,
      recordedJournal: existsSync(j) ? j : undefined,
      failureReasons: reasonsOf(rec),
    };
  }
  // A script saved by the harness as <name>-<runId>.js next to ../<runId>.json.
  const m = /-(wf_[0-9a-f]{8}-[0-9a-f]{3})\.js$/.exec(path);
  let recordedJournal: string | undefined;
  let args = p.args;
  let failureReasons = new Map<string, string>();
  if (m) {
    const j = join(dirname(path), "..", "..", "subagents", "workflows", m[1]!, "journal.jsonl");
    if (existsSync(j)) recordedJournal = j;
    const r = join(dirname(path), "..", `${m[1]}.json`);
    if (existsSync(r)) {
      const rec = JSON.parse(readFileSync(r, "utf8")) as { args?: unknown; workflowProgress?: unknown };
      if (!p.argsGiven) args = rec.args;
      failureReasons = reasonsOf(rec);
    }
  }
  return { source: text, scriptPath: path, args, recordedJournal, failureReasons };
}

function summary(r: RunResult, extra: Record<string, unknown>, printResult: boolean): string {
  return JSON.stringify(
    {
      runId: r.runId,
      status: r.status,
      ...(r.error !== undefined && { error: r.error }),
      agentCount: r.calls.length,
      cached: r.calls.filter((c) => c.state === "cached").length,
      nulls: r.calls.filter((c) => c.state === "null").length,
      peakConcurrency: r.peakConcurrency,
      phases: r.phases,
      calls: r.calls.map((c) => ({ index: c.index, label: c.label, phase: c.phase, state: c.state })),
      ...extra,
      ...(printResult && { result: r.result }),
    },
    null,
    2,
  );
}

export async function main(argv: readonly string[]): Promise<CliOutcome> {
  let p: Parsed;
  let input: Loaded;
  try {
    p = parseArgv(argv);
    input = loadInput(p);
  } catch (e) {
    return { code: 2, out: `${(e as Error).message}\n${USAGE}` };
  }
  const dir = p.journalDir ? resolve(p.journalDir) : undefined;
  if (dir) mkdirSync(dir, { recursive: true });
  const journalPath = dir ? join(dir, "journal.jsonl") : undefined;
  const common = {
    args: input.args,
    scriptPath: input.scriptPath,
    ...(p.concurrency !== undefined && { concurrency: p.concurrency }),
    ...(p.budget !== undefined && { budgetTotal: p.budget }),
    ...(p.maxAttempts !== undefined && { maxAttempts: p.maxAttempts }),
    ...(dir && { events: new FileEventSink(join(dir, "events.jsonl")) }),
  };
  const sink = (): JournalSink => (journalPath ? new FileJournal(journalPath) : new MemoryJournal());
  const existing = () => (journalPath && existsSync(journalPath) ? parseJournal(readFileSync(journalPath, "utf8")) : undefined);

  let result: RunResult;
  const extra: Record<string, unknown> = { backend: p.backend };
  if (p.backend === "mock") {
    const resumeFrom = existing();
    result = await runWorkflow(input.source, { ...common, backend: new MockBackend(), journal: sink(), ...(resumeFrom && { resumeFrom }) });
  } else {
    const src = p.replay ? resolve(p.replay) : input.recordedJournal;
    if (!src) return { code: 2, out: `--backend replay needs --replay <journal.jsonl> (none could be inferred from ${p.script})\n${USAGE}` };
    const runs = splitRuns(readFileSync(src, "utf8"));
    if (runs.length === 0) return { code: 2, out: `${src} holds no journal lines` };
    // Replay each recorded run in turn; each resumes from everything journaled before it.
    const mem = new MemoryJournal();
    const prior = existing();
    let history = prior ? prior.events.map((e) => JSON.stringify(e)).join("\n") + "\n" : "";
    let divergences = 0;
    let earlier = 0;
    let last: RunResult | undefined;
    let killedAt: { run: number; parked: ReplayBackend["parked"] } | undefined;
    // A journal the successor wrote carries `cid` on its started lines and was
    // resumed by content identity: replay it under that rule, not the
    // harness's stop-at-first-miss prefix (successor review r3: a completed
    // content-resumed run replayed as 'diverged' with fabricated nulls).
    const content = p.cacheIdentity === "content" || (p.cacheIdentity === undefined && parseJournal(readFileSync(src, "utf8")).byCid.size > 0);
    if (content) extra["cacheIdentity"] = "content";
    for (const [i, run] of runs.entries()) {
      const backend = new ReplayBackend(parseJournal(run), { failureReasons: input.failureReasons });
      const tee = new MemoryJournal();
      const out = journalPath ? new FileJournal(journalPath) : mem;
      const journal: JournalSink = { append: (ev) => (tee.append(ev), out.append(ev)) };
      // A recorded run that was killed parks its in-flight calls forever: race
      // the run against the replay reaching the kill, so the CLI never drains
      // the event loop mid-run and exits 0 with nothing said (successor review r2).
      const done = runWorkflow(input.source, { ...common, backend, journal, ...(content && { cacheIdentity: "content" as const }), ...(history && { resumeFrom: parseJournal(history) }) });
      const raced = await Promise.race([done.then((r) => ({ r })), backend.killed.then(() => ({ r: undefined }))]);
      history += tee.text();
      earlier += divergences;
      divergences = backend.divergences.length;
      if (raced.r === undefined) {
        killedAt = { run: i + 1, parked: backend.parked };
        last = undefined;
        continue; // the next recorded run resumes from this one's journal
      }
      killedAt = undefined;
      last = raced.r;
    }
    Object.assign(extra, { replayed: src, recordedRuns: runs.length, divergences, earlierRunDivergences: earlier });
    if (last === undefined) {
      // The final recorded run was killed: say so, name the calls it had in flight, exit non-zero.
      const out = JSON.stringify({ status: "killed", killedInRun: killedAt!.run, parked: killedAt!.parked, ...extra }, null, 2);
      return { code: 4, out };
    }
    result = last;
    // Divergences in the FINAL run are the conformance signal; earlier runs may have
    // been killed or have run an earlier edit of the script. A final run that
    // reached a call the journal never witnessed is not a replay of the
    // recording: never reported as completed (D02).
    if (divergences > 0) {
      if (dir) writeFileSync(join(dir, "record.json"), JSON.stringify(result.record, null, 2) + "\n");
      const r = JSON.parse(summary(result, extra, p.printResult)) as Record<string, unknown>;
      return { code: 1, out: JSON.stringify({ ...r, status: "diverged", runStatus: result.status }, null, 2) };
    }
  }
  if (dir) writeFileSync(join(dir, "record.json"), JSON.stringify(result.record, null, 2) + "\n");
  return { code: result.status === "completed" ? 0 : 1, out: summary(result, extra, p.printResult) };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main(process.argv.slice(2)).then(
    ({ code, out }) => {
      (code === 2 ? process.stderr : process.stdout).write(out + "\n");
      process.exitCode = code;
    },
    (e: unknown) => {
      process.stderr.write(`naive-run: ${(e as Error).stack ?? String(e)}\n`);
      process.exitCode = 3;
    },
  );
}
