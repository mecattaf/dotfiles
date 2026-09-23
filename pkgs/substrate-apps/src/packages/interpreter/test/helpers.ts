import { MockBackend, type MockOptions } from "../src/backend.ts";
import { runWorkflow, type RunOptions, type RunResult } from "../src/interpreter.ts";

export const META = `export const meta = { name: 't', description: 'synthetic test workflow', phases: [{ title: 'A' }, { title: 'B', model: 'opus' }] }\n`;

/** A script from a body, with a valid meta header. */
export const wf = (body: string) => META + body;

export async function run(
  body: string,
  opts: Partial<RunOptions> & { mock?: MockOptions } = {},
): Promise<RunResult & { backendCalls: MockBackend["calls"] }> {
  const backend = (opts.backend as MockBackend | undefined) ?? new MockBackend({ latency: () => 0, ...opts.mock });
  const r = await runWorkflow(wf(body), { concurrency: 4, ...opts, backend });
  return Object.assign(r, { backendCalls: (backend as MockBackend).calls ?? [] });
}

export const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms));

/**
 * `real` fits inside `mock`: same JSON types wherever both have a value, arrays
 * compared by their first element. The mock fills every schema property; a real
 * agent may omit optional ones, and may ADD keys the schema does not forbid
 * (MEASURED: substrate-cloudflare-thread readers[2].verify.command). Keys the
 * real value has and the mock lacks are pushed to `extra`, not reported.
 */
export function covers(mock: unknown, real: unknown, path = "$", extra: string[] = []): string[] {
  if (real === null || real === undefined) return [];
  const t = (v: unknown) => (Array.isArray(v) ? "array" : v === null ? "null" : typeof v);
  if (t(mock) !== t(real)) return [`${path}: mock ${t(mock)} vs real ${t(real)}`];
  if (Array.isArray(real)) {
    const m = mock as unknown[];
    return real.length && m.length ? covers(m[0], real[0], `${path}[0]`, extra) : [];
  }
  if (typeof real === "object") {
    const m = mock as Record<string, unknown>;
    return Object.keys(real as object).flatMap((k) => {
      if (k in m) return covers(m[k], (real as Record<string, unknown>)[k], `${path}.${k}`, extra);
      extra.push(`${path}.${k}`);
      return [];
    });
  }
  return [];
}
