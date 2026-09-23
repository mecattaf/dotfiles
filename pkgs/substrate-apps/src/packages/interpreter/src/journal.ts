/**
 * journal.jsonl, in the harness's own format.
 *
 * MEASURED from Claude Code 2.1.280 and the real journals: four line types,
 *   {"type":"launched"}
 *   {"type":"started","key","agentId","label"?,"phase"?}
 *   {"type":"result","key","agentId","result"}
 *   {"type":"failed","key","agentId"}
 * The harness's reader drops any other line, so phase and log events are NOT
 * written here: they go to events.jsonl beside it (see `EventSink`). A journal
 * this module writes is therefore readable by the harness's own reader.
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname } from "node:path";
import { Schema } from "effect";
import { CID_PATTERN, KEY_PATTERN } from "./key.ts";

const Key = Schema.String.check(Schema.isPattern(KEY_PATTERN));
const Cid = Schema.String.check(Schema.isPattern(CID_PATTERN));
/** Tokens a call spent (input + output), on its terminal line (D10). Optional: harness journals carry none. */
const Tokens = Schema.Number.check(Schema.isGreaterThanOrEqualTo(0));

export const JournalEvent = Schema.Union([
  Schema.Struct({ type: Schema.Literal("launched") }),
  Schema.Struct({
    type: Schema.Literal("started"),
    key: Key,
    agentId: Schema.String,
    label: Schema.optionalKey(Schema.String),
    phase: Schema.optionalKey(Schema.String),
    /** The call's content identity (key.ts contentId); absent in harness journals. */
    cid: Schema.optionalKey(Cid),
  }),
  Schema.Struct({ type: Schema.Literal("result"), key: Key, agentId: Schema.String, result: Schema.Unknown, tokens: Schema.optionalKey(Tokens) }),
  /** `error`: the failure reason (D08); absent in harness journals, which drop unknown keys. */
  Schema.Struct({ type: Schema.Literal("failed"), key: Key, agentId: Schema.String, tokens: Schema.optionalKey(Tokens), error: Schema.optionalKey(Schema.String), budgetExhausted: Schema.optionalKey(Schema.Boolean) }),
]);
export type JournalEvent = typeof JournalEvent.Type;

const decodeEvent = Schema.decodeUnknownOption(JournalEvent);

export interface StartedEntry {
  readonly key: string;
  readonly agentId: string;
  readonly label?: string;
  readonly phase?: string;
  readonly cid?: string;
}

export interface LoadedJournal {
  readonly events: readonly JournalEvent[];
  readonly results: ReadonlyMap<string, unknown>;
  readonly started: ReadonlyMap<string, readonly StartedEntry[]>;
  readonly failed: ReadonlySet<string>;
  /** Distinct started keys in first-seen order: the real invocation order. */
  readonly startOrder: readonly StartedEntry[];
  /** Keys in the order they reached a terminal event (result, or failed with no later result). */
  readonly terminalOrder: readonly string[];
  readonly skippedLines: number;
  /** content identity -> the chained key it was last started under (lines that carry `cid`). */
  readonly byCid: ReadonlyMap<string, string>;
  /** Tokens recorded on terminal lines, summed over the whole file (0 for harness journals). */
  readonly tokensSpent: number;
  /** key -> the reason on its last `failed` line (D08), for journals that carry one. */
  readonly failReasons: ReadonlyMap<string, string>;
  /** key -> tokens recorded on its last terminal line. */
  readonly tokens: ReadonlyMap<string, number>;
  /**
   * Keys whose last `failed` line was a budget refusal (`budgetExhausted: true`,
   * successor review r4): a replay answers them with a refusal, so the replayed
   * run throws BudgetExhaustedError as the original did instead of reading null.
   */
  readonly budgetFailed: ReadonlySet<string>;
}

export function parseJournal(text: string): LoadedJournal {
  const events: JournalEvent[] = [];
  let skippedLines = 0;
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    let raw: unknown;
    try {
      raw = JSON.parse(line);
    } catch {
      skippedLines++;
      continue;
    }
    const ev = decodeEvent(raw);
    if (ev._tag === "Some") events.push(ev.value);
    else skippedLines++;
  }
  const results = new Map<string, unknown>();
  const started = new Map<string, StartedEntry[]>();
  const failed = new Set<string>();
  const startOrder: StartedEntry[] = [];
  const terminal: string[] = [];
  const byCid = new Map<string, string>();
  const tokens = new Map<string, number>();
  const failReasons = new Map<string, string>();
  const budgetFailed = new Set<string>();
  let tokensSpent = 0;
  for (const e of events) {
    if ((e.type === "result" || e.type === "failed") && e.tokens !== undefined) {
      tokensSpent += e.tokens;
      tokens.set(e.key, e.tokens);
    }
    if (e.type === "result") {
      results.set(e.key, e.result);
      const i = terminal.indexOf(e.key);
      if (i >= 0) terminal.splice(i, 1);
      terminal.push(e.key);
    } else if (e.type === "started") {
      const entry: StartedEntry = { key: e.key, agentId: e.agentId, label: e.label, phase: e.phase, ...(e.cid !== undefined && { cid: e.cid }) };
      if (e.cid !== undefined) byCid.set(e.cid, e.key);
      const list = started.get(e.key);
      if (list) list.push(entry);
      else {
        started.set(e.key, [entry]);
        startOrder.push(entry);
      }
    } else if (e.type === "failed") {
      failed.add(e.key);
      if (e.error !== undefined) failReasons.set(e.key, e.error);
      if (e.budgetExhausted === true) budgetFailed.add(e.key);
      else budgetFailed.delete(e.key);
      if (!results.has(e.key)) {
        const i = terminal.indexOf(e.key);
        if (i >= 0) terminal.splice(i, 1);
        terminal.push(e.key);
      }
    }
  }
  return { events, results, started, failed, startOrder, terminalOrder: terminal, skippedLines, byCid, tokensSpent, tokens, failReasons, budgetFailed };
}

/**
 * One journal file can hold several RUNS: a resume appends to the same file and
 * writes no second `launched` line (MEASURED: wf_7382b31b-d3e, 203 lines, one
 * `launched`, a failed first run then a resumed second run). Cache hits are not
 * re-journaled, so a resumed run's lines start at its first miss.
 *
 * Two signals open a new run:
 *  1. a `started` line for a key already started in this run. Within one run a
 *     key is started at most once (the key is a hash chain; a repeat needs a
 *     collision), so this is a resume re-running a key (wf_7382b31b-d3e);
 *  2. a `started` line whose LABEL belongs to an earlier start in this run that
 *     never reaches a terminal line anywhere in the file: that call was in flight
 *     when the run was killed, and the resume re-invoked it, here under a new key
 *     because the script had been edited (MEASURED: wf_70fb1fc5-b3b, .claude-work).
 * Signal 2 is only taken when the current run is provably dead at that line: no
 * key started earlier in the run reaches a terminal line later (unless it is
 * re-started first). A killed run writes nothing after the kill, so a real
 * boundary always passes this check; two in-flight calls that merely SHARE a
 * computed label inside one live parallel burst do not (they were split in two
 * before; test/edges.test.ts). Two such calls with nothing else in flight
 * remain indistinguishable from a resume (INFERRED limit, in NAIVE.md).
 * A `launched` line also opens a run. A resume whose first miss is a new key
 * with a new label after a clean stop is still invisible to both signals
 * (INFERRED limit, in NAIVE.md).
 */
export function splitRuns(text: string): string[] {
  const lines = text.split("\n").filter((l) => l.trim());
  const parsed = lines.map((l) => {
    try {
      return JSON.parse(l) as { type?: unknown; key?: unknown; label?: unknown };
    } catch {
      return undefined;
    }
  });
  const terminated = new Set(parsed.filter((e) => e?.type === "result" || e?.type === "failed").map((e) => e!.key));
  const runs: string[][] = [];
  let cur: string[] = [];
  let seen = new Set<unknown>();
  let orphanLabels = new Set<unknown>();
  /** True when some key started in the current run (before line i) still terminates after i. */
  const runStillLive = (i: number): boolean => {
    const restarted = new Set<unknown>();
    for (let j = i; j < parsed.length; j++) {
      const e = parsed[j];
      if (e?.type === "launched") return false;
      if (e?.type === "started") restarted.add(e.key);
      else if ((e?.type === "result" || e?.type === "failed") && seen.has(e.key) && !restarted.has(e.key)) return true;
    }
    return false;
  };
  const flush = () => {
    if (cur.length) runs.push(cur);
    cur = [];
    seen = new Set();
    orphanLabels = new Set();
  };
  lines.forEach((line, i) => {
    const e = parsed[i];
    if (e?.type === "launched" && cur.length) flush();
    else if (e?.type === "started" && typeof e.key === "string") {
      if (seen.has(e.key) || (e.label !== undefined && orphanLabels.has(e.label) && !runStillLive(i))) flush();
      seen.add(e.key);
      if (!terminated.has(e.key) && e.label !== undefined) orphanLabels.add(e.label);
    }
    cur.push(line);
  });
  flush();
  return runs.map((r) => r.join("\n") + "\n");
}

export function loadJournal(path: string): LoadedJournal {
  return parseJournal(readFileSync(path, "utf8"));
}

export interface JournalSink {
  append(ev: JournalEvent): void;
}

/** Append-only; one line per event, flushed at once, so a killed run keeps what it recorded. */
export class FileJournal implements JournalSink {
  constructor(readonly path: string) {
    mkdirSync(dirname(path), { recursive: true });
  }
  append(ev: JournalEvent): void {
    appendFileSync(this.path, JSON.stringify(ev) + "\n", "utf8");
  }
  exists(): boolean {
    return existsSync(this.path);
  }
}

export class MemoryJournal implements JournalSink {
  readonly events: JournalEvent[] = [];
  append(ev: JournalEvent): void {
    this.events.push(ev);
  }
  text(): string {
    return this.events.map((e) => JSON.stringify(e) + "\n").join("");
  }
}

// ------------------------------------------------------------ run events

/** Everything the run does that the journal does not carry. */
export type RunEvent =
  | { readonly type: "run_start"; readonly runId: string; readonly workflowName: string; readonly depth: number }
  | { readonly type: "phase"; readonly title: string; readonly index: number | undefined; readonly depth: number }
  | { readonly type: "log"; readonly message: string; readonly depth: number }
  | { readonly type: "agent_queued"; readonly index: number; readonly key: string; readonly label?: string; readonly phase?: string }
  | { readonly type: "agent_started"; readonly index: number; readonly key: string; readonly agentId: string; readonly attempt: number }
  | { readonly type: "agent_cached"; readonly index: number; readonly key: string; readonly label?: string }
  | { readonly type: "cache_rejected"; readonly index: number; readonly key: string; readonly reason: string }
  | { readonly type: "agent_retry"; readonly index: number; readonly key: string; readonly attempt: number; readonly reason: string }
  | { readonly type: "agent_done"; readonly index: number; readonly key: string; readonly state: "done" | "null" | "failed"; readonly reason?: string; readonly sessionId?: string }
  | { readonly type: "model_rewrite"; readonly index: number; readonly from: string; readonly to: string }
  | { readonly type: "item_null"; readonly where: "parallel" | "pipeline"; readonly item: number; readonly stage?: number; readonly reason: string }
  | { readonly type: "run_end"; readonly runId: string; readonly status: "completed" | "failed"; readonly error?: string; readonly depth: number };

export interface EventSink {
  emit(ev: RunEvent): void;
}

export class FileEventSink implements EventSink {
  constructor(readonly path: string) {
    mkdirSync(dirname(path), { recursive: true });
  }
  emit(ev: RunEvent): void {
    appendFileSync(this.path, JSON.stringify(ev) + "\n", "utf8");
  }
}

/**
 * The journal lines of the calls a run record marks `cached: true`, to serve
 * as the cache when that record is replayed (successor review r5). A resume
 * into a NEW runId copies the earlier run's hit into the new journal as an
 * ordinary started/result pair with no cached marker, so the journal alone
 * replays the hit as a live call; the record row is what says it was a hit.
 */
export function recordCacheHits(rows: readonly { readonly cached?: unknown; readonly agentId?: unknown }[], journalText: string): string {
  const ids = new Set(rows.filter((r) => r.cached === true && typeof r.agentId === "string").map((r) => r.agentId as string));
  if (ids.size === 0) return "";
  const keep = journalText.split("\n").filter((l) => {
    if (!l.trim()) return false;
    try {
      const e = JSON.parse(l) as { type?: string; agentId?: string };
      return (e.type === "started" || e.type === "result") && typeof e.agentId === "string" && ids.has(e.agentId);
    } catch {
      return false;
    }
  });
  return keep.length ? keep.join("\n") + "\n" : "";
}
