/**
 * The Backend seam: what one agent() call becomes.
 *
 * The interpreter owns the script, the key chain, the journal, the caps and the
 * retry loop. A backend owns exactly one attempt at one call and reports what
 * happened. It never throws for an ordinary failure: it returns `error`.
 */
import { createHash } from "node:crypto";

export interface AgentOpts {
  readonly label?: string;
  readonly phase?: string;
  readonly schema?: Record<string, unknown>;
  readonly model?: string;
  readonly effort?: string;
  readonly isolation?: string;
  readonly agentType?: string;
  readonly [k: string]: unknown;
}

export interface AgentCall {
  /** 1-based invocation index within the run (nested workflows share the counter). */
  readonly index: number;
  /** The harness-compatible chained resume key. */
  readonly key: string;
  readonly prompt: string;
  readonly opts: AgentOpts;
  /** The phase in force: opts.phase, else the last phase() title. */
  readonly phase: string | undefined;
  /** 1-based attempt number; attempt > 1 is a retry after a schema mismatch or an error. */
  readonly attempt: number;
  /** Validation errors from the previous attempt, for a backend that can feed them back. */
  readonly previousErrors?: readonly string[];
  readonly signal?: AbortSignal;
  /**
   * Which occurrence of the same content (prompt and keyed opts) this call is
   * in the run, fixed at invocation: the same on every attempt and on every
   * resume (successor review r3: a backend that counted its own occurrences
   * gave a retry, or a resumed call, another call's identity).
   */
  readonly occurrence?: number;
  /** The call's content identity (key.ts contentId), fixed at invocation. */
  readonly cid?: string;
  /**
   * The run's budget ceiling at the moment a backend admits the call: a
   * reason when the budget is spent, else undefined. A backend that queues
   * calls (a WIP cap) asks it again when the call leaves the queue, and
   * answers `budgetExhausted` instead of running (successor review r3: calls
   * that passed the interpreter's check waited for a WIP slot and then ran
   * after the budget was spent).
   */
  readonly budgetExhausted?: () => string | undefined;
}

export interface Usage {
  readonly inputTokens: number;
  readonly outputTokens: number;
}

export interface AgentOutcome {
  /** Unstructured result (no schema). */
  readonly text?: string;
  /** Structured result (schema given); validated by the interpreter, not the backend. */
  readonly object?: unknown;
  readonly usage?: Usage;
  /** A terminal failure of this attempt. */
  readonly error?: string;
  /** The backend's own id for the agent (session id, subagent id). */
  readonly agentId?: string;
  /** A backend may declare the call skipped: the interpreter returns null without retrying. */
  readonly skipped?: boolean;
  /** The backend refused to run the call because the run's budget was spent at admission. */
  readonly budgetExhausted?: boolean;
}

export interface Backend {
  readonly name: string;
  run(call: AgentCall): Promise<AgentOutcome>;
}

// ---------------------------------------------------------------- MockBackend

export interface MockOptions {
  /** Length of every generated array (clamped to minItems/maxItems). Default 1. */
  readonly arrayLength?: number;
  /**
   * Simulated latency in wall-clock ms (setTimeout). When given, completion order
   * follows the timers and is only as deterministic as they are. Default: none;
   * see `turns`.
   */
  readonly latency?: (call: AgentCall) => number;
  /**
   * Simulated latency in event-loop turns (setImmediate), used when `latency` is
   * not given. Default: a function of the call ORDINAL, (index * 7) % 5, so calls
   * finish out of invocation order (exercising pipelines) yet every run of the
   * same script completes its calls in the same order: same keys, same results.
   */
  readonly turns?: (call: AgentCall) => number;
  /** Override the value for a call; return undefined to use the stub. */
  readonly respond?: (call: AgentCall) => AgentOutcome | undefined | Promise<AgentOutcome | undefined>;
  /** Boolean fields' stub value. Default true (so `filter(c => c.flag)` keeps items). */
  readonly booleanValue?: boolean;
}

const digest = (s: string) => createHash("sha256").update(s).digest("hex");

/**
 * A schema-satisfying stub. Deterministic: the same (schema, tag) gives the
 * same value. Covers type (and type arrays), enum, const, properties, required,
 * items/prefixItems, min/maxItems, anyOf/oneOf/allOf (first branch), minimum,
 * minLength, and `$ref` into local `$defs`/`definitions`.
 */
export function stubFromSchema(
  schema: unknown,
  tag: string,
  o: { arrayLength?: number; booleanValue?: boolean } = {},
  root: unknown = schema,
  path = "$",
  depth = 0,
): unknown {
  if (depth > 32) return null;
  if (schema === true || schema === undefined) return `${tag} ${path}`;
  if (!schema || typeof schema !== "object") return null;
  const s = schema as Record<string, unknown>;
  const rec = (sub: unknown, p: string) => stubFromSchema(sub, tag, o, root, p, depth + 1);
  if (typeof s.$ref === "string") {
    const m = /^#\/(\$defs|definitions)\/(.+)$/.exec(s.$ref);
    const defs = m ? ((root as Record<string, Record<string, unknown>>)[m[1]!] ?? {}) : {};
    return rec(m ? defs[m[2]!] : undefined, path);
  }
  if ("const" in s) return s.const;
  if (Array.isArray(s.enum) && s.enum.length) return s.enum[0];
  for (const k of ["anyOf", "oneOf"] as const) {
    if (Array.isArray(s[k]) && (s[k] as unknown[]).length) {
      const branches = s[k] as Record<string, unknown>[];
      const nonNull = branches.find((b) => b && b.type !== "null") ?? branches[0];
      return rec(nonNull, path);
    }
  }
  if (Array.isArray(s.allOf) && s.allOf.length) {
    return rec(Object.assign({}, ...(s.allOf as object[])), path);
  }
  let t = s.type;
  if (Array.isArray(t)) t = t.find((x) => x !== "null") ?? t[0];
  if (t === undefined && s.properties) t = "object";
  if (t === undefined && s.items) t = "array";
  switch (t) {
    case "object": {
      const out: Record<string, unknown> = {};
      for (const [k, sub] of Object.entries((s.properties ?? {}) as Record<string, unknown>)) out[k] = rec(sub, `${path}.${k}`);
      return out;
    }
    case "array": {
      const min = typeof s.minItems === "number" ? s.minItems : 0;
      const max = typeof s.maxItems === "number" ? s.maxItems : Infinity;
      const n = Math.min(max, Math.max(min, o.arrayLength ?? 1));
      const prefix = Array.isArray(s.prefixItems) ? (s.prefixItems as unknown[]) : [];
      return Array.from({ length: n }, (_, i) => rec(prefix[i] ?? s.items, `${path}[${i}]`));
    }
    case "boolean":
      return o.booleanValue ?? true;
    case "integer":
    case "number": {
      const min = typeof s.minimum === "number" ? s.minimum : typeof s.exclusiveMinimum === "number" ? s.exclusiveMinimum + 1 : 1;
      const max = typeof s.maximum === "number" ? s.maximum : Infinity;
      return Math.min(max, t === "integer" ? Math.ceil(min) : min);
    }
    case "null":
      return null;
    default: {
      let v = `${tag} ${path}`;
      if (typeof s.minLength === "number") while (v.length < s.minLength) v += "_";
      if (typeof s.maxLength === "number") v = v.slice(0, s.maxLength);
      return v;
    }
  }
}

/**
 * Deterministic, offline. Every value carries a provenance tag `[[m:<label>]]`
 * so a test can see which upstream result a later prompt embedded.
 */
export class MockBackend implements Backend {
  readonly name = "mock";
  readonly calls: AgentCall[] = [];
  constructor(readonly options: MockOptions = {}) {}

  async run(call: AgentCall): Promise<AgentOutcome> {
    this.calls.push(call);
    if (this.options.latency) {
      const ms = this.options.latency(call);
      if (ms > 0) await new Promise((r) => setTimeout(r, ms));
    } else {
      const n = this.options.turns ? this.options.turns(call) : (call.index * 7) % 5;
      for (let i = 0; i < n; i++) await new Promise((r) => setImmediate(r));
    }
    const custom = this.options.respond ? await this.options.respond(call) : undefined;
    if (custom) return custom;
    const tag = `[[m:${call.opts.label ?? `#${call.index}`}]]`;
    const usage = { inputTokens: Math.ceil(call.prompt.length / 4), outputTokens: 100 };
    const agentId = `mock-${digest(call.key).slice(0, 16)}`;
    if (call.opts.schema) {
      return { object: stubFromSchema(call.opts.schema, tag, this.options), usage, agentId };
    }
    return { text: `${tag} mock result`, usage, agentId };
  }
}
