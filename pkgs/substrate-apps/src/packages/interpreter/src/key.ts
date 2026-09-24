/**
 * The resume key of one agent() call, byte-compatible with Claude Code 2.1.280.
 *
 * MEASURED against the real journals under ~/.claude/projects/-home-tom-today:
 * the harness's key is a HASH CHAIN,
 *
 *   key_n = "v2:" + sha256(key_{n-1} + "\0" + prompt + "\0" + canonical(opts))
 *   key_0 = ""
 *
 * where n counts agent() INVOCATIONS in the order the script makes them, and
 * canonical(opts) is JSON of the subset {schema, model, effort, isolation,
 * agentType, disallowedTools, bashCommandClamp} with object keys sorted
 * recursively and functions dropped. label and phase are NOT part of the key.
 *
 * The chain is what makes resume "longest unchanged prefix": change one call's
 * prompt or options and that key, and every key after it, changes; every call
 * before it keeps its key and its cached result.
 */
import { createHash } from "node:crypto";

export const KEY_VERSION = "v2";

const KEYED_OPTS = [
  "schema",
  "model",
  "effort",
  "isolation",
  "agentType",
  "disallowedTools",
  "bashCommandClamp",
] as const;

function canon(v: unknown): unknown {
  if (typeof v === "function") return undefined;
  if (Array.isArray(v)) {
    const out: unknown[] = [];
    const n = Number.isSafeInteger(v.length) ? v.length : 0;
    for (let i = 0; i < n; i++) out[i] = canon(v[i]);
    return out;
  }
  if (v && typeof v === "object") {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(v).sort()) {
      if (k === "__proto__") continue;
      out[k] = canon((v as Record<string, unknown>)[k]);
    }
    return out;
  }
  return v;
}

/** The option subset that enters the key, serialized canonically. */
export function canonicalOpts(opts: Record<string, unknown> | undefined | null): string {
  if (!opts) return "{}";
  const picked: Record<string, unknown> = {};
  for (const k of KEYED_OPTS) {
    const v = opts[k];
    if (v === undefined || typeof v === "function") continue;
    picked[k] = v;
  }
  return JSON.stringify(canon(picked));
}

export function chainKey(prevKey: string, prompt: string, opts: Record<string, unknown> | undefined | null): string {
  const h = createHash("sha256")
    .update(prevKey)
    .update("\0")
    .update(prompt)
    .update("\0")
    .update(canonicalOpts(opts))
    .digest("hex");
  return `${KEY_VERSION}:${h}`;
}

export const KEY_PATTERN = /^v\d+:[0-9a-f]{64}$/;

/**
 * A call's CONTENT identity (D04/D18 of the 2026-09-23 naive evals): a hash of
 * the prompt and the keyed opts, plus the occurrence index among identical
 * (prompt, opts) calls in this run's invocation order. Unlike the chained key it
 * does not depend on which calls came before or on the order they finished, so
 * a resume keyed on it keeps every finished call. The chained key stays the
 * journal's `key` (harness compatibility); this rides beside it as `cid`.
 */
export function contentHash(prompt: string, opts: Record<string, unknown> | undefined | null): string {
  const h = createHash("sha256").update(prompt).update("\0").update(canonicalOpts(opts));
  // codex review 3, C3-8: where a call runs is part of what it is. Two calls with one prompt on different runtimes
  // or seats must not share a cid, or a resume that reaches them in another order hands one the other's result.
  // Added only when a route is named, so the cid of every call without one is unchanged (journals stay valid).
  const route = routeOpts(opts);
  if (route !== "{}") h.update("\0route\0").update(route);
  return h.digest("hex");
}

const ROUTE_OPTS = ["runtime", "seat", "runsOn"] as const;
/** The routing subset of opts (not part of the harness chain key), serialized canonically. */
export function routeOpts(opts: Record<string, unknown> | undefined | null): string {
  if (!opts) return "{}";
  const picked: Record<string, unknown> = {};
  for (const k of ROUTE_OPTS) if (opts[k] !== undefined && typeof opts[k] !== "function") picked[k] = opts[k];
  return JSON.stringify(canon(picked));
}
export const contentId = (hash: string, occurrence: number): string => `c1:${hash}#${occurrence}`;
export const CID_PATTERN = /^c1:[0-9a-f]{64}#[1-9][0-9]*$/;
