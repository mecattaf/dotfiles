/**
 * The integrated path, one run end to end:
 *
 *   interpreter (@substrate/interpreter runWorkflow: the script, the key chain,
 *     the journal, retries, the return value)
 *   -> CONWIP admission (Conwip.submit: the fail-closed CapacityGate for the
 *     call's model on the run's seat, the FM-2 Task spec and size check, the WIP
 *     cap, the ledger)
 *   -> Runner (this module's `runnerFromBackend`: the admitted call handed to
 *     @substrate/runners RunnerBackend)
 *   -> harness on a runtime (runtimes.toml: claude pinned to claude-opus-5-5,
 *     pi on Halogen through ssh:worker, codex against a fake binary only)
 *   -> the outcome back into agent() -> the journal line.
 *
 * Every artefact of a run lives in one directory, so a killed run is resumed
 * by running the same command again:
 *
 *   <dir>/run.lock       flock'd by the one live process on this dir (content: pid, start, for people)
 *   <dir>/run.json       run id, script path, args, budget, one entry per start
 *   <dir>/journal.jsonl  the interpreter's harness-format journal (resume key)
 *   <dir>/events.jsonl   the interpreter's run events
 *   <dir>/ledger.jsonl   the CONWIP ledger (derive/admit/dispatch/outcome/release/refuse)
 *   <dir>/jobs/<id>/     one job dir per runner attempt, with receipt.json
 *   <dir>/jobs/<id>.proc.json  the runner-side record of a local child's group
 *   <dir>/jobs/<runId>-c<hash>o<occurrence>-a<n>.outcome.json  a finished attempt's outcome, adopted by a resume
 *                        that finds no journal line for it (C3-4)
 *   <dir>/record.json    the run record, written when the run ends
 *   <dir>/result.json    status, return value, per-call states, written when the run ends
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import {
  extractMeta,
  FileEventSink,
  FileJournal,
  parseJournal,
  runWorkflow,
  type AgentCall as InterpreterCall,
  type AgentOutcome as InterpreterOutcome,
  type RunResult,
} from "@substrate/interpreter";
import {
  PDEATHSIG_WRAPPER,
  procStartTicks,
  reapHerdrRecords,
  reapProcFiles,
  reapSshRecords,
  reapWorktreeRecords,
  RunnerBackend,
  unreapedSshRecords,
  sweepSeatShadows,
  type RuntimesConfig,
  type Runner as JobRunner,
} from "@substrate/runners";
import { spawn } from "node:child_process";
import type { AgentOpts as InterpreterOpts } from "@substrate/interpreter";
import type { CapacityGate } from "./capacity/gate.ts";
import { runOutcome, type CallCounts, type Outcome } from "./run-outcome.ts";
import type { MachineSlots } from "./slots.ts";
import { Conwip, type AgentCall, type AgentOutcome, type Runner } from "./submit.ts";

/** Anything with the interpreter's Backend shape (RunnerBackend is one). */
export interface CallBackend {
  readonly name: string;
  run(call: AgentCall, admitted?: unknown): Promise<AgentOutcome>;
}

/**
 * The CONWIP's Runner over a Backend: the admitted Task was already built and
 * size-checked by `Conwip.submit`; the backend runs the call itself on the
 * runtime its config selects. The Task spec stays the ax seam (FIELD-MAP 5a).
 */
export function runnerFromBackend(backend: CallBackend): Runner {
  return {
    name: `backend:${backend.name}`,
    // The admitted Task travels on: the ax runtime writes it as admitted (one builder).
    run: (task, _item, call) => backend.run(call, task),
  };
}

export interface IntegratedOptions {
  /** The workflow script's path. */
  readonly scriptPath: string;
  readonly args?: unknown;
  /** The run directory; if its journal exists the run resumes from it. */
  readonly dir: string;
  readonly runtimes: RuntimesConfig;
  /** The seat the capacity gate reads (cc, halogen, ...). Data. */
  readonly seat: string;
  /** The model a call without one is admitted for (the harness pins the model it runs). */
  readonly defaultModel: string;
  /** The WIP cap. */
  readonly cap: number;
  /** Interpreter concurrency (calls in flight before admission). Default 4. */
  readonly concurrency?: number;
  readonly maxAttempts?: number;
  /**
   * C3-5: a resume "retry"s a journaled terminal failure (default, the
   * CODEX-TRIAGE default) or "replay"s it as the same null, as the
   * floor-dispatch path does. Pending Tom's ruling (IMPL-reverify-interp).
   */
  readonly resumeFailures?: "retry" | "replay";
  /** Absent means no gate: only for a fake seat under test. */
  readonly capacity?: CapacityGate;
  readonly capacityWait?: { readonly delayMs: number; readonly maxWaitMs: number };
  /** Runner overrides by runtime name (tests). */
  readonly runners?: Readonly<Record<string, JobRunner>>;
  readonly runIdPrefix?: string;
  /**
   * Token ceiling for the whole run (D10). Kept in run.json, so a resume keeps
   * the ceiling unless it names another; spent counts the earlier starts'
   * tokens from the journal.
   */
  readonly budgetTotal?: number | null;
  /** The git repo an isolation:'worktree' call gets a worktree of. Default: the process cwd. */
  readonly repoDir?: string;
  /** Where microvm seat shadows live (never the run dir). Default: runners seatShadowRoot. */
  readonly seatShadowRoot?: string;
  /**
   * Aborts the run from outside (conwip-run's SIGINT/SIGTERM handler): every
   * in-flight call is aborted and awaited, so the runners' own cleanup runs
   * (worktree settle, seat-shadow removal, herdr workspace.close) before the
   * process exits (successor review r4).
   */
  readonly signal?: AbortSignal;
  /** Machine-wide slot holds for slot seats (conwip-run always passes one; successor review r4). */
  readonly machineSlots?: MachineSlots;
}

export interface IntegratedRun {
  readonly runId: string;
  readonly resumed: boolean;
  readonly result: RunResult;
  /** What the calls did (gap G3): all-done, partial, all-failed, refused, or script-failed. */
  readonly outcome: Outcome;
  /** conwip-run's exit code for `outcome` (src/run-outcome.ts EXIT). */
  readonly exitCode: number;
  readonly callCounts: CallCounts;
  /** How many calls reached the runner in THIS process (cache hits never do). */
  readonly dispatched: number;
  readonly dir: string;
}

interface RunMeta {
  runId: string;
  scriptPath: string;
  args: unknown;
  seat: string;
  budgetTotal?: number | null;
  starts: { at: string; pid: number; resumed: boolean; reaped?: string[]; args?: unknown; argsReplaced?: boolean; refused?: string }[];
}

export class RunDirLocked extends Error {
  override readonly name = "RunDirLocked";
}

/**
 * A restart found a dead start's remote job it could not kill (the host was
 * unreachable): the remote copy may still run, so nothing is dispatched
 * (successor review r4: the restart ran a second copy beside it).
 */
export class RemoteMayStillRun extends Error {
  override readonly name = "RemoteMayStillRun";
}

/** JSON with sorted object keys: two args values are the same args iff their canonical forms are equal. */
export function canonicalJson(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map((x) => canonicalJson(x === undefined ? null : x)).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonicalJson(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(v ?? null);
}

const FLOCK = ["/run/current-system/sw/bin/flock", "/usr/bin/flock", "/bin/flock"].find((p) => existsSync(p));

/**
 * One live process per run dir, held by the kernel (successor review r2: the
 * O_EXCL pid file's stale-lock reclaim was a check-then-remove race, and
 * release() removed a lock it did not own). flock(1) takes LOCK_EX|LOCK_NB on
 * run.lock and holds it for the life of a small helper whose stdin is this
 * process: the helper exits, and the kernel drops the lock, when this process
 * closes that pipe or dies by any signal (pdeathsig as well). There is no
 * reclaim path, and the file is never removed. Its content (pid, start) is
 * for people only; no decision reads it.
 */
async function takeLock(dir: string): Promise<{ release: () => Promise<void> }> {
  const path = join(dir, "run.lock");
  if (!FLOCK) throw new RunDirLocked(`run dir ${dir}: flock(1) not found; refusing to run without a kernel lock`);
  const child = spawn(PDEATHSIG_WRAPPER.length ? PDEATHSIG_WRAPPER[0]! : FLOCK, [...PDEATHSIG_WRAPPER.slice(1), ...(PDEATHSIG_WRAPPER.length ? [FLOCK] : []), "-n", "-o", "-E", "75", path, "sh", "-c", "echo locked; exec cat >/dev/null"], {
    stdio: ["pipe", "pipe", "ignore"],
  });
  const exited = new Promise<number>((r) => child.on("close", (code) => r(code ?? 1)));
  const got = await new Promise<boolean>((r) => {
    child.stdout.once("data", () => r(true));
    void exited.then(() => r(false));
    child.on("error", () => r(false));
  });
  if (!got) {
    const code = await exited;
    let holder = "";
    try {
      holder = readFileSync(path, "utf8").trim();
    } catch {
      /* no content */
    }
    throw new RunDirLocked(
      code === 75
        ? `run dir ${dir} is held by another live process (run.lock ${holder || "flocked"}); refusing a second process on it`
        : `run dir ${dir}: could not take run.lock (flock exit ${code})`,
    );
  }
  child.stdout.resume();
  writeFileSync(path, JSON.stringify({ pid: process.pid, start: procStartTicks(process.pid), at: new Date().toISOString() }) + "\n");
  return {
    release: async () => {
      child.stdin.end();
      await exited;
    },
  };
}

/** Write a file whole or not at all. */
function writeAtomic(path: string, text: string): void {
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, text);
  renameSync(tmp, path);
}

/**
 * Kill what a dead earlier start left running before this start dispatches
 * anything: local harness groups (proved by start time and job marker, never
 * a reused pid), remote ssh groups, herdr jobs and their pane workspaces.
 */
async function reapOrphans(jobsRoot: string): Promise<string[]> {
  // Worktrees last: the harness that edited one is dead once its group is reaped.
  return [...reapProcFiles(jobsRoot), ...(await reapSshRecords(jobsRoot)), ...(await reapHerdrRecords(jobsRoot)), ...reapWorktreeRecords(jobsRoot)];
}

const newRunId = (prefix: string) => `${prefix}_${Date.now().toString(16).slice(-8)}-${process.pid.toString(16)}`;

export async function runIntegrated(o: IntegratedOptions): Promise<IntegratedRun> {
  const dir = resolve(o.dir);
  mkdirSync(dir, { recursive: true });
  const metaPath = join(dir, "run.json");
  const journalPath = join(dir, "journal.jsonl");
  const scriptPath = resolve(o.scriptPath);
  const source = readFileSync(scriptPath, "utf8");

  const lock = await takeLock(dir);
  try {
    return await runLocked(o, dir, metaPath, journalPath, scriptPath, source);
  } finally {
    await lock.release();
  }
}

async function runLocked(
  o: IntegratedOptions,
  dir: string,
  metaPath: string,
  journalPath: string,
  scriptPath: string,
  source: string,
): Promise<IntegratedRun> {
  const prior = existsSync(metaPath) ? (JSON.parse(readFileSync(metaPath, "utf8")) as RunMeta) : undefined;
  const journalText = existsSync(journalPath) ? readFileSync(journalPath, "utf8") : "";
  const resumed = prior !== undefined && journalText.trim() !== "";
  const runId = prior?.runId ?? newRunId(o.runIdPrefix ?? "wf_int");
  // Args given on a restart are the args this start runs with (successor
  // review r4: they were dropped silently and the old run's cached result came
  // back). Content identity decides what re-runs: a call whose prompt the new
  // args change runs live, one they leave alone stays a cache hit. The change
  // is recorded on this start's entry in run.json and in result.json.
  const argsReplaced = prior !== undefined && o.args !== undefined && canonicalJson(o.args) !== canonicalJson(prior.args);
  const args = prior !== undefined && !argsReplaced ? prior.args : o.args;
  const budgetTotal = o.budgetTotal !== undefined ? o.budgetTotal : (prior?.budgetTotal ?? null);
  const meta: RunMeta = prior ?? { runId, scriptPath, args, seat: o.seat, starts: [] };
  meta.budgetTotal = budgetTotal;
  meta.args = args;
  const jobsRoot = join(dir, "jobs");
  const reaped = [...(await reapOrphans(jobsRoot)), ...sweepSeatShadows(o.runtimes, runId, jobsRoot, o.seatShadowRoot)];
  const unreaped = unreapedSshRecords(jobsRoot);
  const refused = unreaped.length
    ? `remote may still run: ${unreaped.map((u) => `${u.id} on ${u.host}`).join(", ")}; the reaper could not kill it. Retry when the host is reachable`
    : undefined;
  meta.starts.push({
    at: new Date().toISOString(),
    pid: process.pid,
    resumed,
    ...(reaped.length ? { reaped } : {}),
    ...(argsReplaced ? { args, argsReplaced: true } : {}),
    ...(refused ? { refused } : {}),
  });
  writeAtomic(metaPath, JSON.stringify(meta, null, 2) + "\n");
  if (refused) throw new RemoteMayStillRun(`run dir ${dir}: ${refused}`);

  const { meta: scriptMeta } = extractMeta(source);
  const phaseTitles = (scriptMeta.phases ?? []).map((p) => p.title);
  const backend = new RunnerBackend(o.runtimes, {
    jobsRoot,
    runId,
    start: meta.starts.length,
    defaultSeat: o.seat,
    workflow: basename(scriptPath),
    phaseIndexOf: (title: string) => {
      const i = phaseTitles.indexOf(title);
      return i >= 0 ? i + 1 : undefined;
    },
    ...(o.repoDir ? { repoDir: o.repoDir } : {}),
    ...(o.seatShadowRoot ? { seatShadowRoot: o.seatShadowRoot } : {}),
    ...(o.runners ? { runners: o.runners } : {}),
  });
  const routeOf = (c: { opts: { runtime?: unknown }; phase: string | undefined }) => {
    const r = backend.route(c);
    return { model: r.model, seat: r.seat, harness: r.harness, runtime: r.selection.name };
  };
  let dispatched = 0;
  let adopted = 0;
  const counting: CallBackend = {
    name: backend.name,
    // C3-4: an outcome adopted from an earlier start's finished job ran nothing here.
    run: async (call, admitted) => {
      const out = await backend.run(call, admitted);
      if ((out as { adoptedFrom?: string }).adoptedFrom !== undefined) adopted++;
      else dispatched++;
      return out;
    },
  };
  const ledgerPath = join(dir, "ledger.jsonl");
  const conwip = new Conwip({
    runId,
    workflowName: scriptMeta.name,
    phaseIndexOf: (title) => {
      const i = phaseTitles.indexOf(title);
      return i >= 0 ? i + 1 : undefined;
    },
    defaultModel: o.defaultModel,
    cap: o.cap,
    seat: o.seat,
    atespace: "ultracode",
    image: "none",
    runner: runnerFromBackend(counting),
    route: (call) => routeOf({ opts: call.opts as { runtime?: unknown }, phase: call.phase }),
    ...(o.capacity ? { capacity: o.capacity } : {}),
    ...(o.capacityWait ? { capacityWait: o.capacityWait } : {}),
    ...(o.machineSlots ? { machineSlots: o.machineSlots } : {}),
    ledgerSink: { append: (e) => appendFileSync(ledgerPath, JSON.stringify(e) + "\n") },
  });
  const conwipBackend = conwip.asBackend();

  // Every call carries this run's abort signal, and every call still in
  // flight when the script ends (a sibling of a call that threw) is aborted
  // and awaited before result.json is written and the lock is released
  // (successor review r2: a resume took the lock while the first process was
  // still running a call, and dispatched it again).
  const ac = new AbortController();
  if (o.signal?.aborted) ac.abort();
  else o.signal?.addEventListener("abort", () => ac.abort(), { once: true });
  const inflight = new Set<Promise<unknown>>();
  const result = await runWorkflow(source, {
    backend: {
      name: conwipBackend.name,
      run: (call: InterpreterCall) => {
        const p = conwipBackend.run({ ...call, signal: ac.signal } as AgentCall) as Promise<InterpreterOutcome>;
        inflight.add(p);
        void p.finally(() => inflight.delete(p)).catch(() => undefined);
        return p;
      },
    },
    args,
    runId,
    scriptPath,
    concurrency: o.concurrency ?? 4,
    // D04/D18: a resume looks every call up by content identity, with no
    // stop-at-first-miss rule, so finished work is never dispatched again.
    cacheIdentity: "content",
    budgetTotal,
    defaultModel: o.defaultModel,
    // The record names the model that RUNS: the harness's pinned id for the
    // runtime this call selects, not the script's pin (fable, sonnet, ...).
    modelPolicy: (declared, c) => {
      try {
        return routeOf({ opts: (c.opts ?? {}) as InterpreterOpts & { runtime?: unknown }, phase: c.phase }).model;
      } catch {
        return declared; // a refused runtime is refused at admission, as an outcome
      }
    },
    ...(o.maxAttempts !== undefined ? { maxAttempts: o.maxAttempts } : {}),
    ...(o.resumeFailures !== undefined ? { resumeFailures: o.resumeFailures } : {}),
    journal: new FileJournal(journalPath),
    events: new FileEventSink(join(dir, "events.jsonl")),
    ...(resumed ? { resumeFrom: parseJournal(journalText) } : {}),
  });

  const abortedInFlight = inflight.size;
  if (abortedInFlight > 0) {
    ac.abort();
    await Promise.allSettled([...inflight]);
    // Let the interpreter's continuations journal those calls' terminal lines.
    await new Promise((r) => setImmediate(r));
  }
  writeFileSync(join(dir, "record.json"), JSON.stringify(result.record, null, 2) + "\n");
  // A completed script is not a run that did its work: agent() returns null
  // for a failed or refused call (gap G3). The outcome and the counts say so.
  const done = runOutcome(result.status, result.calls, result.events, result.result);
  writeFileSync(
    join(dir, "result.json"),
    JSON.stringify(
      {
        runId,
        resumed,
        ...(argsReplaced ? { argsReplaced: true } : {}),
        // What this start reaped first, a worktree kept as "killed mid-edit" included.
        ...(reaped.length ? { reaped } : {}),
        status: result.status,
        outcome: done.outcome,
        exitCode: done.code,
        callCounts: done.counts,
        error: result.error ?? null,
        result: result.result,
        dispatchedThisProcess: dispatched,
        ...(adopted ? { adoptedThisProcess: adopted } : {}),
        peakConcurrency: result.peakConcurrency,
        slotsInUseAtEnd: conwip.slotsInUse,
        abortedInFlight,
        calls: result.calls.map((c) => ({ index: c.index, label: c.label, phase: c.phase, state: c.state, attempts: c.attempts, key: c.key, ...(c.error !== undefined ? { error: c.error } : {}) })),
      },
      null,
      2,
    ) + "\n",
  );
  return { runId, resumed, result, outcome: done.outcome, exitCode: done.code, callCounts: done.counts, dispatched, dir };
}
