/**
 * Run-record reader. A run record is an untrusted external representation: it
 * is type-checked here, never cast.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { deployConfig } from "./deploy-config.ts";
import { resolveThroughLinks } from "./pathguard.ts";
import { buildLabelIndex, resolveFromIndex } from "./extract.ts";
import { decodeWorkItem, type WorkItem } from "./schema.ts";

/**
 * Paths that must never be opened by this reader, nor bound into any sandbox
 * it feeds. Deployment data: `forbiddenReadPrefixes` in the substrate config.
 */
export const FORBIDDEN_PREFIXES: readonly string[] = deployConfig().forbiddenReadPrefixes;

export function assertReadablePath(path: string): void {
  // A-05 of the 2026-09-23 review. The comparison used to be against the raw
  // string, so `/home/tom/notes/../rawa/secret` and the relative `rawa/secret`
  // both walked straight past a guard whose whole job is to stop them. A path is
  // normalized first, exactly as `assertLedgerPathAllowed` in jsonl.ts does.
  //
  // A-24 of the same review. Normalizing is not enough: `resolve()` does not
  // follow links, so a symlink whose TARGET is under a forbidden prefix still
  // walked past. The resolver both guards now share lives in `pathguard.ts`.
  const abs = resolveThroughLinks(path);
  for (const p of FORBIDDEN_PREFIXES) {
    if (abs === p || abs.startsWith(p + "/")) {
      throw new Error(`refusing to read a forbidden path: ${path} (resolves to ${abs})`);
    }
  }
}

export type ResultKind = "list" | "dict" | "null" | "other";

/**
 * `result` is a list on some records, a dict on others and null on the killed
 * one, so every reader must type-check it before touching it.
 */
export function classifyResult(value: unknown): ResultKind {
  if (value === null || value === undefined) return "null";
  if (Array.isArray(value)) return "list";
  if (typeof value === "object") return "dict";
  return "other";
}

export interface RunRecordSummary {
  readonly runId: string;
  readonly workflowName: string;
  readonly status: string;
  readonly defaultModel: string;
  readonly agentCount: number;
  readonly phaseCount: number;
  readonly resultKind: ResultKind;
  readonly hasError: boolean;
}

export interface DerivedRecord {
  readonly summary: RunRecordSummary;
  readonly items: readonly WorkItem[];
  /** Non-fatal observations: phase-title mismatches and the like. */
  readonly diagnostics: readonly string[];
}

function asString(v: unknown, fallback: string): string {
  return typeof v === "string" ? v : fallback;
}

function asInt(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : undefined;
}

/** Read and derive one run record from disk. The file is opened read-only. */
export function deriveFromFile(path: string): DerivedRecord {
  assertReadablePath(path);
  const raw = JSON.parse(readFileSync(path, "utf8")) as { runId?: unknown };
  // The harness keeps a run's journal at ../subagents/workflows/<runId>/journal.jsonl.
  let journal: string | undefined;
  if (typeof raw.runId === "string" && /^[A-Za-z0-9_.-]+$/.test(raw.runId)) {
    const j = join(dirname(path), "..", "subagents", "workflows", raw.runId, "journal.jsonl");
    if (existsSync(j)) journal = readFileSync(j, "utf8");
  }
  return derive(raw, journal, journal === undefined ? undefined : transcriptPrompts(join(dirname(path), "..", "subagents", "workflows", raw.runId as string)));
}

/**
 * The full prompt each subagent was given: the first user message of
 * <dir>/agent-<agentId>.jsonl. Used only to find data lineage when the
 * record's own prompt was not resolved. Read-only; a file that does not parse
 * is skipped.
 */
function transcriptPrompts(dir: string): ReadonlyMap<string, string> {
  const out = new Map<string, string>();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir)) {
    const m = /^agent-(.+)\.jsonl$/.exec(f);
    if (!m) continue;
    try {
      const first = readFileSync(join(dir, f), "utf8").split("\n", 1)[0] ?? "";
      const c = (JSON.parse(first) as { message?: { content?: unknown } }).message?.content;
      const text = typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => (x as { text?: string }).text ?? "").join("\n") : "";
      if (text) out.set(m[1]!, text);
    } catch {
      /* not a transcript */
    }
  }
  return out;
}

/** Every string inside a journal result. */
function leaves(v: unknown, out: string[] = []): string[] {
  if (typeof v === "string") out.push(v);
  else if (Array.isArray(v)) v.forEach((x) => leaves(x, out));
  else if (v !== null && typeof v === "object") Object.values(v).forEach((x) => leaves(x, out));
  return out;
}

/** The windows probed in one long text: 60 characters from near the start and from the middle. */
const windowsOf = (x: string): string[] => [x.slice(20, 80), x.slice(Math.floor(x.length / 2), Math.floor(x.length / 2) + 60)];

/** Shortest result leaf matched whole (successor review r4: a short result, such as a topic name, gave no edge). */
export const SHORT_LEAF_MIN = 16;

/**
 * True when `prompt` embeds `result`:
 * - a 60-character window (from near the start and from the middle) of one of
 *   its strings of 120 characters or more appears verbatim, raw or
 *   JSON-escaped (successor review r4: a consumer that embeds
 *   JSON.stringify(result) of multi-line text carries \n and \" escapes, not
 *   the raw bytes), or a window of JSON.stringify(result) itself does;
 * - or a shorter string leaf (SHORT_LEAF_MIN characters or more) appears
 *   whole, when it is not already in the producer's own prompt (a word both
 *   prompts share from the script's template is not a data dependency).
 * An extra edge only delays a release; a missing one releases a consumer
 * while its producer is pending.
 */
export function embedsResult(prompt: string, result: unknown, producerPrompt = ""): boolean {
  if (!prompt) return false;
  const all = leaves(result);
  const long = all.filter((x) => x.length >= 120);
  const escaped = long.map((x) => JSON.stringify(x).slice(1, -1));
  const whole = result !== null && typeof result === "object" ? JSON.stringify(result) : "";
  const probes = [...long, ...escaped.filter((e, i) => e !== long[i]), ...(whole.length >= 120 ? [whole] : [])].flatMap(windowsOf);
  if (probes.some((w) => w.trim().length >= 50 && prompt.includes(w))) return true;
  return all
    .map((x) => x.trim())
    .filter((x) => x.length >= SHORT_LEAF_MIN && x.length < 120)
    .some((x) => prompt.includes(x) && !producerPrompt.includes(x));
}

/**
 * Journal positions by agentId: the first `started` line and the last terminal
 * (`result` or `failed`) line. A line that does not parse is skipped.
 */
function journalOrder(text: string): { started: Map<string, number>; ended: Map<string, number>; results: Map<string, unknown>; lanes: Map<string, string> } {
  const lanes = new Map<string, string>();
  const started = new Map<string, number>();
  const ended = new Map<string, number>();
  const results = new Map<string, unknown>();
  text.split("\n").forEach((line, i) => {
    if (line.trim() === "") return;
    let e: { type?: unknown; agentId?: unknown; result?: unknown; lane?: unknown };
    try {
      e = JSON.parse(line) as typeof e;
    } catch {
      return;
    }
    if (typeof e.agentId !== "string" || e.agentId === "") return;
    if (e.type === "started" && !started.has(e.agentId)) {
      started.set(e.agentId, i);
      if (typeof e.lane === "string" && e.lane !== "") lanes.set(e.agentId, e.lane);
    }
    if (e.type === "result" || e.type === "failed") ended.set(e.agentId, i);
    if (e.type === "result") results.set(e.agentId, e.result);
  });
  return { started, ended, results, lanes };
}

/**
 * D06: true when two calls ran on independent chains of one combinator: their
 * lanes (`<epoch>.r<realm>/<combinator>:<item>/...`, journaled on `started`)
 * share the epoch and realm, and the first combinator where they differ is the
 * same combinator with different items. A call with no lane is never a
 * sibling, so it keeps the conservative rule. INFERRED limit: a script that
 * passes data between items through shared mutable state defeats this; the
 * interpreter cannot see that flow.
 */
export function siblingLanes(a: string | undefined, b: string | undefined): boolean {
  if (a === undefined || b === undefined) return false;
  const [ra, ...sa] = a.split("/");
  const [rb, ...sb] = b.split("/");
  if (ra !== rb) return false;
  for (let i = 0; i < Math.min(sa.length, sb.length); i++) {
    const [ca, ia] = sa[i]!.split(":");
    const [cb, ib] = sb[i]!.split(":");
    if (ca !== cb) return false;
    if (ia !== ib) return true;
  }
  return false;
}

/** Derive every WorkItem of one run record. One item per `workflow_agent` entry. */
export function derive(raw: unknown, journal?: string, transcripts?: ReadonlyMap<string, string>): DerivedRecord {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("run record is not a JSON object");
  }
  const rec = raw as Record<string, unknown>;

  const runId = asString(rec["runId"], "");
  const workflowName = asString(rec["workflowName"], "");
  const status = asString(rec["status"], "unknown");
  const defaultModel = asString(rec["defaultModel"], "");
  const script = asString(rec["script"], "");
  if (runId === "") throw new Error("run record has no runId");

  const phasesRaw = Array.isArray(rec["phases"]) ? (rec["phases"] as unknown[]) : [];
  const phaseTitles = phasesRaw.map((p) =>
    p !== null && typeof p === "object" ? asString((p as Record<string, unknown>)["title"], "") : "",
  );

  const progress = Array.isArray(rec["workflowProgress"]) ? (rec["workflowProgress"] as unknown[]) : [];
  const idx = buildLabelIndex(script);

  const items: WorkItem[] = [];
  const agentIds = new Map<number, string>();
  const diagnostics: string[] = [];
  /** index -> the first label that claimed it, for the duplicate diagnostic. */
  const seenIndexes = new Map<number, string>();

  for (const entryRaw of progress) {
    if (entryRaw === null || typeof entryRaw !== "object") continue;
    const e = entryRaw as Record<string, unknown>;
    if (e["type"] !== "workflow_agent") continue;

    const label = asString(e["label"], "");
    const index = asInt(e["index"]);
    const phaseIndex = asInt(e["phaseIndex"]);
    if (index === undefined || phaseIndex === undefined) {
      diagnostics.push(`${runId}: skipped a workflow_agent entry with no index or phaseIndex`);
      continue;
    }
    const phaseTitle = asString(e["phaseTitle"], "");
    // A-14 of the 2026-09-23 review. `itemKey` is `runId#index` and both engines
    // key a Map by it, so a duplicate index displaced an earlier item with
    // nothing recorded anywhere. The item is still derived; the collision is now
    // said out loud, where the other parse diagnostics are said.
    if (seenIndexes.has(index)) {
      diagnostics.push(
        `${runId}: duplicate index ${index} (labels ${JSON.stringify(seenIndexes.get(index))} and ${JSON.stringify(label)}); both share the item key ${runId}#${index} and one will displace the other`,
      );
    } else {
      seenIndexes.set(index, label);
    }
    // CR-06 of the 2026-09-23 evals (A-28). `phaseIndex` is 1-BASED: MEASURED
    // over 2768 real agent entries, every one matches `phases[phaseIndex - 1]`
    // and none matches `phases[phaseIndex]`. Reading it 0-based made every
    // derive diagnostic a false positive (2755 of 2755).
    const declared = phaseTitles[phaseIndex - 1];
    // Only when the record DECLARES phases: several real records carry no
    // `phases` array at all, and "past the end of nothing" is not a finding.
    if (phaseTitles.length > 0 && (phaseIndex < 1 || phaseIndex > phaseTitles.length)) {
      diagnostics.push(
        `${runId}#${index}: phaseIndex ${phaseIndex} is outside phases 1..${phaseTitles.length} (1-based)`,
      );
    }
    if (declared !== undefined && declared !== "" && declared !== phaseTitle) {
      diagnostics.push(
        `${runId}#${index}: phaseTitle ${JSON.stringify(phaseTitle)} does not match phases[${phaseIndex - 1}].title ${JSON.stringify(declared)} (phaseIndex ${phaseIndex} is 1-based)`,
      );
    }

    const resolution = resolveFromIndex(idx, label);
    const model = asString(e["model"], defaultModel);
    const tokens = asInt(e["tokens"]);
    const agentState = typeof e["state"] === "string" ? (e["state"] as string) : undefined;
    const attempt = asInt(e["attempt"]);
    const durationMs = asInt(e["durationMs"]);

    const draft: Record<string, unknown> = {
      runId,
      workflowName,
      label,
      index,
      phaseIndex,
      phaseTitle,
      model,
      // A refused item still carries an empty prompt string rather than a
      // fabricated one; promptPreview is truncated and is never substituted.
      prompt: resolution.ok ? resolution.prompt : "",
      promptResolved: resolution.ok,
      sourceStatus: status,
    };
    if (!resolution.ok) draft["promptUnresolvedReason"] = resolution.reason;
    if (resolution.ok && resolution.effort !== undefined) draft["effort"] = resolution.effort;
    if (agentState !== undefined) {
      draft["sourceAgentState"] = agentState;
      // Per entry (CR-10): `done` is the only state that is a success. Any
      // other state (`error`, or `progress`/`queued` in a killed run) is Failed.
      draft["sourceOutcome"] = agentState === "done" ? "Completed" : "Failed";
    }
    if (attempt !== undefined && attempt >= 1) draft["attempt"] = attempt;
    if (tokens !== undefined) draft["sizingTokens"] = tokens;
    if (durationMs !== undefined) draft["sizingDurationMs"] = durationMs;

    items.push(decodeWorkItem(draft));
    if (typeof e["agentId"] === "string") agentIds.set(index, e["agentId"] as string);
  }

  // Lineage from the journal (D05/D06). Historical rule, replaced in r5 by the
  // conservative one below: an item waited on W when W's
  // terminal line precedes this item's start AND either W is in the phase
  // just before (the phase barrier the harness shows), or this item's prompt
  // embeds W's result, in any phase (successor review r3: a same-phase
  // pipeline chain, plan -> menial in one phase, got no edge, and the loop
  // released a consumer while its producer was pending).
  if (journal !== undefined) {
    const order = journalOrder(journal);
    const promptOf = (x: WorkItem): string => (x.prompt !== "" ? x.prompt : (transcripts?.get(agentIds.get(x.index) ?? "") ?? ""));
    const snapshot = [...items];
    for (const [k, x] of snapshot.entries()) {
      const xs = order.started.get(agentIds.get(x.index) ?? "");
      if (xs === undefined) {
        items[k] = decodeWorkItem({ ...x, after: [] });
        continue;
      }
      const xp = promptOf(x);
      const xl = order.lanes.get(agentIds.get(x.index) ?? "");
      const after = snapshot
        .filter((w) => w.index !== x.index)
        .filter((w) => {
          const wa = agentIds.get(w.index) ?? "";
          const we = order.ended.get(wa);
          // Successor review r5 (D05): phase adjacency and result embedding
          // missed control dependencies (`await a; await b`), same-phase awaits
          // and a skipped phase, and a missing edge is the unsafe direction
          // (loop and serve release the consumer early). Until the interpreter
          // records per-chain lineage on the started line, every call that
          // ended before X started is a dependency. This over-serialises
          // independent pipeline items (D06), which is slow, never wrong.
          // D06 (critique pass 2026-09-24): the started line now carries the
          // call's lane, and a call on a sibling lane of the same combinator
          // (another pipeline item, another parallel thunk) is not an edge.
          return we !== undefined && we < xs && !siblingLanes(xl, order.lanes.get(wa));
        })
        .map((w) => w.index);
      items[k] = decodeWorkItem({ ...x, after });
    }
  }

  const summary: RunRecordSummary = {
    runId,
    workflowName,
    status,
    defaultModel,
    agentCount: asInt(rec["agentCount"]) ?? items.length,
    phaseCount: phasesRaw.length,
    resultKind: classifyResult(rec["result"]),
    hasError: Object.prototype.hasOwnProperty.call(rec, "error"),
  };

  return { summary, items, diagnostics };
}

/**
 * A dependency edge runs from every item at phaseIndex n to every item at
 * phaseIndex n+1 within one runId. Stated as edges, a barrier in practice.
 */
export function dependencyEdges(items: readonly WorkItem[]): ReadonlyArray<{ from: string; to: string }> {
  // Lineage only (successor review r2): an item's `after` list, from its run's
  // journal. No journal, no edges: phase adjacency is not a dependency.
  const edges: Array<{ from: string; to: string }> = [];
  for (const b of items) for (const i of b.after ?? []) edges.push({ from: `${b.runId}#${i}`, to: `${b.runId}#${b.index}` });
  return edges;
}
