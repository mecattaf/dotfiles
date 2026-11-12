// flags.mjs — the location flags shared by `tick` and `run`: --inbox, --state-dir, --home, --floor-instance.

import { realpathSync } from 'node:fs';
import { resolve } from 'node:path';

const VALUE_FLAGS = { '--inbox': 'inbox', '--state-dir': 'stateDir', '--home': 'home', '--floor-instance': 'floorInstance', '--now': 'now' };

/**
 * Parse `args` against `allowed` value flags plus `--json`; the flag wins over ctx's environment default.
 * @returns {{ opts: object, positional: string[], json: boolean } | { error: string }}
 */
export function parseLocationFlags(args, ctx, allowed) {
  const opts = { inbox: ctx.inbox, stateDir: ctx.stateDir, home: ctx.home, floorInstance: ctx.floorInstance ?? null };
  const positional = [];
  let json = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const eq = a.indexOf('=');
    const flag = a.startsWith('--') && eq > 0 ? a.slice(0, eq) : a;
    if (flag === '--json' && eq < 0) { json = true; continue; }
    if (VALUE_FLAGS[flag] && allowed.includes(flag)) {
      const value = eq > 0 && a.startsWith('--') ? a.slice(eq + 1) : args[++i];
      if (value === undefined || value === '') return { error: `missing value for ${flag}` };
      opts[VALUE_FLAGS[flag]] = value;
      continue;
    }
    if (a.startsWith('-')) return { error: `unknown option '${a}'` };
    positional.push(a);
  }
  if (opts.now !== undefined) {
    const d = new Date(opts.now);
    if (Number.isNaN(d.getTime())) return { error: `invalid date for --now: ${opts.now}` };
    opts.now = d;
  }
  if (opts.inbox) opts.inbox = resolve(opts.inbox);
  if (opts.stateDir) opts.stateDir = resolve(opts.stateDir);
  if (opts.home !== ctx.home) {
    try { opts.home = realpathSync(opts.home); } catch { return { error: `--home ${opts.home} does not exist` }; }
  }
  return { opts, positional, json };
}
