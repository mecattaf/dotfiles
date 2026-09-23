/**
 * The interpreter: runs one workflow script against one Backend.
 *
 * Plain async/await, as in the rest of substrate (DESIGN.md section 2): Effect
 * is used for Schema at the boundaries (meta, journal lines, CLI args), not as
 * a concurrency runtime. The semaphore below is twenty lines of FIFO.
 */
import { randomBytes } from "node:crypto";
import { cpus } from "node:os";
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import type { AgentCall, AgentOpts, AgentOutcome, Backend } from "./backend.ts";
import { chainKey, contentHash, contentId } from "./key.ts";
import { compileValidator, preflightSchema } from "./jsonschema.ts";
import type { EventSink, JournalSink, LoadedJournal, RunEvent } from "./journal.ts";
import { extractMeta, type WorkflowMeta } from "./meta.ts";
import { ReplayBackend } from "./replay.ts";
import { compileInRealm, type HostBridge } from "./sandbox.ts";

export const LIFETIME_AGENT_CAP = 1000;
export const ITEMS_PER_CALL_CAP = 4096;
export const MAX_NESTING = 1;

/** The harness's default: min(16, cpus - 2), and at least 1. */
export function defaultConcurrency(n = cpus().length): number {
  return Math.max(1, Math.min(16, n - 2));
}

export class BudgetExhaustedError extends Error {
  override readonly name = "BudgetExhaustedError";
}
export class AgentCapError extends Error {
  override readonly name = "AgentCapError";
}

export class Semaphore {
  private active = 0;
  private readonly queue: (() => void)[] = [];
  peak = 0;
  constructor(readonly permits: number) {
    if (!(permits >= 1)) throw new RangeError("concurrency must be at least 1");
  }
  acquire(): Promise<void> {
    if (this.active < this.permits) {
      this.active++;
      this.peak = Math.max(this.peak, this.active);
      return Promise.resolve();
    }
    return new Promise((r) =>
      this.queue.push(() => {
        this.peak = Math.max(this.peak, this.active);
        r();
      }),
    );
  }
  release(): void {
    const next = this.queue.shift();
    if (next) next();
    else this.active--;
  }
  get inFlight(): number {
    return this.active;
  }
}

export interface ModelPolicy {
  /** Return the model to run (possibly rewritten), or throw to refuse the call. */
  (model: string | undefined, call: { index: number; label?: string; phase?: string; opts?: AgentOpts }): string | undefined;
}

/**
 * A model policy from an allowlist: `allow` maps each accepted name (a full id
 * or an alias) to the full id that runs; anything else runs as `fallback`.
 * The runners' models.ts is the configurable source of such a list.
 */
export const modelAllowlistPolicy =
  (allow: Readonly<Record<string, string>>, fallback: string | undefined): ModelPolicy =>
  (model) => {
    if (model === undefined) return fallback;
    const hit = allow[model] ?? allow[model.toLowerCase()];
    return hit ?? fallback;
  };

/**
 * The former standing rule (opus only; fable and sonnet rewritten). Kept for
 * callers that want exactly that; the default policy is now the allowlist.
 */
export const opusOnly: ModelPolicy = (model) => {
  if (model === undefined) return "opus";
  if (/opus/i.test(model)) return model;
  return "opus";
};

export interface WorkflowSource {
  readonly source: string;
  readonly path: string;
}

export interface RunOptions {
  readonly backend: Backend;
  readonly args?: unknown;
  readonly concurrency?: number;
  readonly maxAgents?: number;
  readonly maxItems?: number;
  /** Token ceiling for the whole run, nested workflows included. null or undefined = none. */
  readonly budgetTotal?: number | null;
  /** Attempts per call for schema mismatch or backend error. Default 3. */
  readonly maxAttempts?: number;
  readonly journal?: JournalSink;
  /** A journal to resume from: calls whose chained key has a result there are not re-run. */
  readonly resumeFrom?: LoadedJournal;
  /**
   * Copy cache hits into `journal`. Default false. Note (successor review r5,
   * MEASURED wf_52b91c07-c54): a harness resume into a NEW runId does copy the
   * hit as an ordinary started/result pair; replays take hits from the record's
   * `cached: true` rows (recordCacheHits). Otherwise the harness does not re-journal
   * a hit when it resumes into the same file (MEASURED, wf_7382b31b-d3e). Set it
   * when resuming into a DIFFERENT file that must stand alone.
   */
  readonly copyCachedToJournal?: boolean;
  readonly events?: EventSink;
  readonly runId?: string;
  readonly scriptPath?: string;
  readonly resolveWorkflow?: (ref: string, fromPath: string | undefined) => WorkflowSource;
  readonly modelPolicy?: ModelPolicy;
  readonly defaultModel?: string;
  readonly newAgentId?: () => string;
  /**
   * How cache hits are delivered on resume. "immediate" (default) resolves each
   * hit at once, in invocation order: MEASURED as the harness's behaviour from
   * the one real resume on disk (wf_7382b31b-d3e: the resumed run invoked the
   * menial calls of the cached plans in pipeline order, not in the order the
   * first run finished them). Consequence: on an unchanged resume, a no-barrier
   * pipeline whose recorded completion order differed from its invocation order
   * gets new chained keys for its later stages and re-runs them.
   * "recorded" releases hits in the recorded completion order instead, which
   * keeps those later keys stable (an improvement over the harness, opt-in).
   */
  readonly cacheRelease?: "recorded" | "immediate";
  /**
   * What a resume looks a call up by. "chain" (default) is the harness's rule,
   * kept for fidelity: the chained key, answered only along the longest
   * unchanged prefix. "content" (D04/D18): the call's content identity (a hash
   * of prompt and keyed opts plus its occurrence among identical calls), looked
   * up for EVERY call independently, with no stop-at-first-miss rule, so a
   * completed call is never dispatched again whatever order the earlier run
   * finished in or failed in. Journals written in either mode carry `cid` on
   * their `started` lines; a journal without `cid` (a harness journal) falls
   * back to the chained key, still with no prefix rule.
   */
  readonly cacheIdentity?: "chain" | "content";
}

export interface CallRecord {
  readonly index: number;
  readonly key: string;
  readonly label: string | undefined;
  readonly phase: string | undefined;
  readonly model: string | undefined;
  readonly schema: boolean;
  readonly prompt: string;
  readonly depth: number;
  /** 1-based index of `phase` in the meta of the script that made the call (a nested child's own meta). */
  readonly phaseIndex: number | undefined;
  state: "queued" | "running" | "done" | "null" | "cached";
  attempts: number;
  agentId: string | undefined;
  /** Logical clock ticks: every backend start and end advances the run's clock by one. */
  startTick: number | undefined;
  endTick: number | undefined;
  tokens: number;
  resultPreview: string | undefined;
  /** Why a call returned null; the record's row carries it as `error` (MEASURED, 38 of 38 error rows). */
  error: string | undefined;
}

export interface RunResult {
  readonly runId: string;
  readonly status: "completed" | "failed";
  readonly result: unknown;
  readonly error: string | undefined;
  readonly meta: WorkflowMeta;
  readonly calls: readonly CallRecord[];
  readonly logs: readonly string[];
  readonly phases: readonly string[];
  readonly events: readonly RunEvent[];
  readonly peakConcurrency: number;
  readonly totalTokens: number;
  /** A run record in the shape Claude Code writes to workflows/<runId>.json. */
  readonly record: Record<string, unknown>;
}

interface Shared {
  readonly opts: RunOptions;
  readonly sem: Semaphore;
  readonly maxAgents: number;
  readonly maxItems: number;
  readonly maxAttempts: number;
  readonly calls: CallRecord[];
  readonly events: RunEvent[];
  readonly logs: string[];
  readonly phases: string[];
  count: number;
  lastKey: string;
  prefixBroken: boolean;
  spent: number;
  /** content hash -> how many calls with it were invoked so far (occurrence index). */
  readonly occurrences: Map<string, number>;
  tick: number;
  readonly cacheOrder: ReplayBackend | undefined;
}

const newRunId = () => `wf_${randomBytes(4).toString("hex")}-${randomBytes(2).toString("hex").slice(0, 3)}`;
const defaultAgentId = () => `a${randomBytes(8).toString("hex").slice(0, 16)}`;

function defaultResolver(ref: string, fromPath: string | undefined): WorkflowSource {
  const base = fromPath ? dirname(fromPath) : process.cwd();
  const candidates = ref.endsWith(".js")
    ? [isAbsolute(ref) ? ref : resolve(base, ref)]
    : [join(base, `${ref}.js`), join(process.cwd(), ".claude", "workflows", `${ref}.js`)];
  for (const p of candidates) {
    try {
      return { source: readFileSync(p, "utf8"), path: p };
    } catch {
      /* next */
    }
  }
  throw new Error(`workflow(): cannot resolve '${ref}' (looked in ${candidates.join(", ")})`);
}

/**
 * The record's resultPreview and promptPreview: the first 400 characters (JSON for
 * a structured value) and an ellipsis. MEASURED: every one of the 469 previews in
 * the real records longer than 400 is exactly that. A value of 400 or fewer is kept
 * whole (INFERRED: no real value was that short).
 */
export const PREVIEW_CHARS = 400;
export function preview(v: unknown): string {
  const s = typeof v === "string" ? v : (JSON.stringify(v) ?? "null");
  return s.length > PREVIEW_CHARS ? `${s.slice(0, PREVIEW_CHARS)}\u2026` : s;
}

/**
 * The text the record's `error` starts with: `<name>: <message>`. MEASURED
 * (wf_12695394-85a): "TypeError: args.repos.map is not a function. ...". The
 * harness appends its engine's stack; ours would be V8's, so it is left out.
 */
export function errorText(e: unknown): string {
  if (e && typeof (e as Error).message === "string") {
    const name = typeof (e as Error).name === "string" && (e as Error).name ? (e as Error).name : "Error";
    return `${name}: ${(e as Error).message}`;
  }
  return String(e);
}

export async function runWorkflow(source: string, options: RunOptions): Promise<RunResult> {
  const shared: Shared = {
    opts: options,
    sem: new Semaphore(options.concurrency ?? defaultConcurrency()),
    maxAgents: options.maxAgents ?? LIFETIME_AGENT_CAP,
    maxItems: options.maxItems ?? ITEMS_PER_CALL_CAP,
    maxAttempts: Math.max(1, options.maxAttempts ?? 3),
    calls: [],
    events: [],
    logs: [],
    phases: [],
    count: 0,
    lastKey: "",
    prefixBroken: false,
    // A resume counts what its earlier runs spent (D10): the tokens on the
    // journal's terminal lines. A harness journal carries none, so 0.
    spent: options.resumeFrom?.tokensSpent ?? 0,
    occurrences: new Map(),
    tick: 0,
    cacheOrder:
      options.resumeFrom !== undefined && options.cacheRelease === "recorded" ? new ReplayBackend(options.resumeFrom) : undefined,
  };
  const runId = options.runId ?? newRunId();
  const startTime = Date.now();
  // A resume appends to the same journal with no second `launched` line (MEASURED, wf_7382b31b-d3e).
  if (options.resumeFrom === undefined) options.journal?.append({ type: "launched" });
  const top = await runScript(shared, source, options.scriptPath, options.args, 0, runId);
  const record = buildRecord(shared, top, runId, source, startTime);
  return {
    runId,
    status: top.status,
    result: top.result,
    error: top.error,
    meta: top.meta,
    calls: shared.calls,
    logs: shared.logs,
    phases: shared.phases,
    events: shared.events,
    peakConcurrency: shared.sem.peak,
    totalTokens: shared.spent,
    record,
  };
}

interface ScriptOutcome {
  status: "completed" | "failed";
  result: unknown;
  error: string | undefined;
  meta: WorkflowMeta;
}

async function runScript(
  shared: Shared,
  source: string,
  scriptPath: string | undefined,
  args: unknown,
  depth: number,
  runId: string,
): Promise<ScriptOutcome> {
  const { meta, body } = extractMeta(source);
  const o = shared.opts;
  const emit = (ev: RunEvent) => {
    shared.events.push(ev);
    o.events?.emit(ev);
  };
  emit({ type: "run_start", runId, workflowName: meta.name, depth });
  let currentPhase: string | undefined;
  const phaseIndex = (t: string | undefined) => {
    if (t === undefined) return undefined;
    const i = meta.phases?.findIndex((p) => p.title === t) ?? -1;
    return i >= 0 ? i + 1 : undefined;
  };

  const writeLog = (message: string) => {
    shared.logs.push(message);
    emit({ type: "log", message, depth });
  };

  const agent = async (prompt: unknown, optsJson: string | undefined): Promise<string> => {
    // Everything up to the first await runs synchronously at the call site, so
    // the chained key follows the script's own invocation order, as in the harness.
    if (typeof prompt !== "string") throw new TypeError("agent(prompt, opts): prompt must be a string");
    const opts: AgentOpts = optsJson === undefined ? {} : (JSON.parse(optsJson) as AgentOpts);
    if (opts.schema !== undefined) preflightSchema(opts.schema);
    if (shared.count >= shared.maxAgents) {
      throw new AgentCapError(`agent(): lifetime cap of ${shared.maxAgents} agents reached`);
    }
    const total = o.budgetTotal ?? null;
    const phase = opts.phase !== undefined ? String(opts.phase) : currentPhase;
    // A computed label is coerced like a computed phase (label: i gave no label at
    // all while phase: i gave "3"). Neither is keyed. INFERRED: no real script
    // passes a non-string label; the journal's schema requires a string.
    const label = opts.label === undefined || opts.label === null ? undefined : String(opts.label);
    const key = chainKey(shared.lastKey, prompt, opts);
    const chash = contentHash(prompt, opts);
    const occurrence = (shared.occurrences.get(chash) ?? 0) + 1;
    const cid = contentId(chash, occurrence);

    // Resume, "chain" mode (the default): the LONGEST UNCHANGED PREFIX, as in
    // Claude Code 2.1.280 (MEASURED from its bundle): the cache answers only
    // until the first call that misses. A miss on a key that was started but
    // neither finished nor failed (the run was killed while it was in flight)
    // re-runs that call without ending the prefix; any other miss ends it.
    // "content" mode (D04/D18): every call is looked up on its own, by cid when
    // the journal carries one, else by chained key; no prefix rule.
    const cache = o.resumeFrom;
    const byContent = o.cacheIdentity === "content";
    const cacheKey = cache === undefined ? undefined : byContent ? (cache.byCid.get(cid) ?? key) : key;
    let hit = cache !== undefined && cacheKey !== undefined && (byContent || !shared.prefixBroken) && cache.results.has(cacheKey);
    let rejected: string | undefined;
    // D14: a value served from a journal is checked against the call's schema
    // before the script sees it, as a replayed or fresh value is. A mismatch is
    // a miss: the call runs again.
    if (hit && opts.schema !== undefined) {
      const v = compileValidator(opts.schema)(cache!.results.get(cacheKey!));
      if (!v.ok) {
        hit = false;
        rejected = `schema mismatch: ${(v as { errors: string[] }).errors.join("; ")}`;
      }
    }
    // The budget ceiling at invocation, for calls that will actually run: a
    // cache hit spends nothing, so a resumed run still replays its cache. The
    // throwing call takes no index and does not advance the chain.
    if (!hit && total !== null && shared.spent >= total) {
      throw new BudgetExhaustedError(`agent(): budget exhausted (${shared.spent} of ${total} tokens spent)`);
    }
    if (!byContent && cache !== undefined && !hit && !shared.prefixBroken) {
      const inFlight = rejected === undefined && (cache.started.get(key)?.length ?? 0) > 0 && !cache.failed.has(key);
      if (!inFlight) shared.prefixBroken = true;
    }
    const index = ++shared.count;
    shared.lastKey = key;
    shared.occurrences.set(chash, occurrence);
    const declared = opts.model ?? meta.phases?.find((p) => p.title === phase)?.model ?? o.defaultModel;
    let model = declared;
    if (o.modelPolicy) {
      model = o.modelPolicy(declared, { index, label, phase, opts });
      if (model !== declared) emit({ type: "model_rewrite", index, from: String(declared), to: String(model) });
    }
    const rec: CallRecord = {
      index, key, label, phase, model, schema: opts.schema !== undefined, prompt, depth, phaseIndex: phaseIndex(phase),
      state: "queued", attempts: 0, agentId: undefined, startTick: undefined, endTick: undefined, tokens: 0, resultPreview: undefined, error: undefined,
    };
    shared.calls.push(rec);
    emit({ type: "agent_queued", index, key, label, phase });
    if (rejected !== undefined) emit({ type: "cache_rejected", index, key, reason: rejected });

    if (hit) {
      const value = cache!.results.get(cacheKey!);
      rec.state = "cached";
      rec.agentId = cache!.started.get(cacheKey!)?.at(-1)?.agentId;
      rec.tokens = cache!.tokens.get(cacheKey!) ?? 0;
      rec.resultPreview = preview(value);
      emit({ type: "agent_cached", index, key, label });
      if (shared.cacheOrder) await shared.cacheOrder.run({ index, key: cacheKey!, prompt, opts, phase, attempt: 1 });
      if (o.copyCachedToJournal === true && o.journal) {
        o.journal.append({ type: "started", key, agentId: rec.agentId ?? "", ...(label !== undefined && { label }), ...(phase !== undefined && { phase }), cid });
        o.journal.append({ type: "result", key, agentId: rec.agentId ?? "", result: value, tokens: rec.tokens });
      }
      return JSON.stringify(value ?? null);
    }

    await shared.sem.acquire();
    // The budget is a hard ceiling at ADMISSION, not only at invocation: a
    // parallel() or pipeline() invokes every call before any has spent, so the
    // invocation-time check alone let every call queued behind the concurrency
    // gate run and overspend (8 of 8 ran on a 2-call budget; test/edges.test.ts).
    if (total !== null && shared.spent >= total) {
      shared.sem.release();
      rec.state = "null";
      const reason = `agent(): budget exhausted (${shared.spent} of ${total} tokens spent)`;
      // The refusal is journaled and logged exactly as the in-attempt path
      // does (successor review r5: it left no line, no error and no log, so
      // the record lacked the reason and a replay without --budget diverged).
      const agentId = o.newAgentId?.() ?? defaultAgentId();
      rec.agentId = agentId;
      rec.error = reason;
      o.journal?.append({ type: "started", key, agentId, ...(label !== undefined && { label }), ...(phase !== undefined && { phase }), cid });
      o.journal?.append({ type: "failed", key, agentId, error: reason, budgetExhausted: true });
      writeLog(`[${label ?? `#${index}`}] failed: ${reason}`);
      emit({ type: "agent_done", index, key, state: "failed", reason });
      throw new BudgetExhaustedError(reason);
    }
    rec.state = "running";
    rec.startTick = ++shared.tick;
    let previousErrors: string[] | undefined;
    let outcome: AgentOutcome | undefined;
    let final: unknown = null;
    let failReason: string | undefined;
    let sessionId: string | undefined;
    try {
      for (let attempt = 1; attempt <= shared.maxAttempts; attempt++) {
        rec.attempts = attempt;
        const agentId = o.newAgentId?.() ?? defaultAgentId();
        rec.agentId = agentId;
        // One `started` line per CALL, as in the harness: attempts are not journaled.
        if (attempt === 1) o.journal?.append({ type: "started", key, agentId, ...(label !== undefined && { label }), ...(phase !== undefined && { phase }), cid });
        emit({ type: "agent_started", index, key, agentId, attempt });
        const call: AgentCall = {
          index, key, prompt, opts: { ...opts, ...(model !== undefined && { model }) }, phase, attempt, ...(previousErrors && { previousErrors }),
          occurrence, cid,
          budgetExhausted: () => (total !== null && shared.spent >= total ? `agent(): budget exhausted (${shared.spent} of ${total} tokens spent)` : undefined),
        };
        outcome = await o.backend.run(call);
        if (outcome.budgetExhausted === true) throw new BudgetExhaustedError(outcome.error ?? `agent(): budget exhausted (${shared.spent} of ${total ?? "?"} tokens spent)`);
        // The journal's agentId stays the one minted for this call on every
        // line (started, result, failed) and on the record row, as the harness
        // pairs them (successor review r4: 653 of 653 real terminal lines). The
        // harness's own session id rides separately, on agent_done.
        if (outcome.agentId) sessionId = outcome.agentId;
        // The dialect: budget.spent() counts OUTPUT tokens spent this turn
        // (successor review r2: charging input tokens too bound the ceiling
        // several times too early). Input tokens are not charged or journaled.
        const used = outcome.usage?.outputTokens ?? 0;
        shared.spent += used;
        rec.tokens += used;
        if (outcome.skipped) {
          failReason = outcome.error ?? "skipped";
          break;
        }
        if (outcome.error !== undefined) {
          // A backend error is terminal: the harness does not retry it (MEASURED:
          // all 38 error rows in the real records say attempt 1). Only a schema
          // mismatch or an empty answer is retried here (INFERRED analogue of the
          // subagent correcting its own StructuredOutput).
          failReason = outcome.error;
          break;
        } else if (opts.schema !== undefined) {
          const v = compileValidator(opts.schema)(outcome.object);
          if (outcome.object !== undefined && v.ok) {
            final = outcome.object;
            failReason = undefined;
            break;
          }
          failReason = outcome.object === undefined ? "no structured output" : `schema mismatch: ${(v as { errors: string[] }).errors.join("; ")}`;
          previousErrors = v.ok ? [failReason] : (v as { errors: string[] }).errors;
        } else if (typeof outcome.text === "string") {
          final = outcome.text;
          failReason = undefined;
          break;
        } else {
          failReason = "no text output";
          previousErrors = [failReason];
        }
        if (total !== null && shared.spent >= total) break;
        if (attempt < shared.maxAttempts) emit({ type: "agent_retry", index, key, attempt: attempt + 1, reason: failReason });
      }
    } catch (e) {
      rec.endTick = ++shared.tick;
      rec.state = "null";
      shared.sem.release();
      rec.error = (e as Error).message;
      o.journal?.append({ type: "failed", key, agentId: rec.agentId ?? "", tokens: rec.tokens, error: (e as Error).message, ...(e instanceof BudgetExhaustedError && { budgetExhausted: true }) });
      emit({ type: "agent_done", index, key, state: "failed", reason: (e as Error).message, ...(sessionId !== undefined && { sessionId }) });
      throw e;
    }
    rec.endTick = ++shared.tick;
    shared.sem.release();
    if (failReason === undefined) {
      rec.state = "done";
      rec.resultPreview = preview(final);
      o.journal?.append({ type: "result", key, agentId: rec.agentId ?? "", result: final, tokens: rec.tokens });
      emit({ type: "agent_done", index, key, state: "done", ...(sessionId !== undefined && { sessionId }) });
      return JSON.stringify(final);
    }
    rec.state = "null";
    rec.error = failReason;
    // D08: the reason rides on the failed line, so a replay or a resume from
    // this journal reports what failed, not "journal: failed".
    o.journal?.append({ type: "failed", key, agentId: rec.agentId ?? "", tokens: rec.tokens, error: failReason });
    // The harness logs every terminal failure into the run's logs, interleaved with
    // the script's own lines (MEASURED: wf_cb547366-473, wf_e4049b3a-85d). The form
    // for an unlabelled call is INFERRED.
    writeLog(`[${label ?? `#${index}`}] failed: ${failReason}`);
    emit({ type: "agent_done", index, key, state: "null", reason: failReason, ...(sessionId !== undefined && { sessionId }) });
    return "null";
  };

  const host: HostBridge = {
    agent,
    phase(title) {
      currentPhase = title;
      shared.phases.push(title);
      emit({ type: "phase", title, index: phaseIndex(title), depth });
    },
    log(message) {
      writeLog(message);
    },
    itemNull(where, item, stage, reason) {
      emit({ type: "item_null", where, item, ...(where === "pipeline" && { stage }), reason });
    },
    maxItems: () => shared.maxItems,
    budgetTotal: () => o.budgetTotal ?? null,
    budgetSpent: () => shared.spent,
    async workflow(ref, argsJson) {
      if (depth >= MAX_NESTING) throw new Error(`workflow(): nesting is limited to ${MAX_NESTING} level`);
      const src = (o.resolveWorkflow ?? defaultResolver)(ref, scriptPath);
      const child = await runScript(shared, src.source, src.path, argsJson === undefined ? undefined : JSON.parse(argsJson), depth + 1, `${runId}/${ref}`);
      if (child.status === "failed") throw new Error(`workflow(${ref}) failed: ${child.error}`);
      return JSON.stringify(child.result ?? null);
    },
  };

  let status: "completed" | "failed" = "completed";
  let result: unknown = null;
  let error: string | undefined;
  try {
    const compiled = compileInRealm(body, scriptPath ?? `${meta.name}.js`, host);
    const argsJson = args === undefined ? undefined : JSON.stringify(args);
    result = JSON.parse(await compiled.run(argsJson));
  } catch (e) {
    status = "failed";
    error = errorText(e);
  }
  emit({ type: "run_end", runId, status, ...(error !== undefined && { error }), depth });
  return { status, result, error, meta };
}

function buildRecord(shared: Shared, top: ScriptOutcome, runId: string, script: string, startTime: number): Record<string, unknown> {
  const phases = top.meta.phases ?? [];
  return {
    runId,
    timestamp: new Date(startTime).toISOString(),
    scriptPath: shared.opts.scriptPath,
    script,
    args: shared.opts.args,
    result: top.result,
    ...(top.error !== undefined && { error: top.error }),
    agentCount: shared.calls.length,
    logs: shared.logs,
    durationMs: Date.now() - startTime,
    summary: top.meta.description,
    workflowName: top.meta.name,
    status: top.status,
    startTime,
    phases,
    defaultModel: shared.opts.defaultModel,
    totalTokens: shared.spent,
    // The ceiling the run had, so a replay can reproduce its refusals.
    ...(typeof shared.opts.budgetTotal === "number" && { budgetTotal: shared.opts.budgetTotal }),
    workflowProgress: [
      ...phases.map((p, i) => ({ type: "workflow_phase", index: i + 1, title: p.title })),
      ...shared.calls.map((c) => ({
        type: "workflow_agent",
        index: c.index,
        label: c.label,
        phaseIndex: c.phaseIndex,
        phaseTitle: c.phase,
        agentId: c.agentId,
        model: c.model,
        // The harness's record says "error" for a call that returned null.
        state: c.state === "cached" ? "done" : c.state === "null" ? "error" : c.state,
        // A cached row has no attempt (MEASURED, 20 of 20 cached rows).
        ...(c.state === "cached" ? { cached: true } : { attempt: c.attempts }),
        ...(c.error !== undefined && { error: c.error }),
        tokens: c.tokens,
        // The prompt is trimmed before it is cut (MEASURED: 7 real scripts' prompts
        // start with "\n", and none of their 520 previews does; trimming the end too is INFERRED).
        promptPreview: preview(c.prompt.trim()),
        resultPreview: c.resultPreview,
      })),
    ],
  };
}
