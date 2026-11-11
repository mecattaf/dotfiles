// src/verbs/tick.mjs — The `scheduled tick` verb.
//
// Usage: scheduled tick [--json] [--state-dir DIR --now ISO]

import { tick } from '../lib/tick.mjs';

/**
 * CLI entry point for `scheduled tick`.
 *
 * @param {string[]} args Arguments after the verb
 * @param {object} ctx Context object from makeContext()
 * @returns {Promise<number>} Exit code
 */
export async function main(args, ctx) {
  let json = false;
  let stateDir = ctx.stateDir;
  let now = null;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      json = true;
    } else if (a === '--state-dir') {
      if (i + 1 >= args.length) {
        ctx.err('scheduled tick: missing value for --state-dir\n');
        return 2;
      }
      stateDir = args[++i];
    } else if (a.startsWith('--state-dir=')) {
      stateDir = a.slice('--state-dir='.length);
    } else if (a === '--now') {
      if (i + 1 >= args.length) {
        ctx.err('scheduled tick: missing value for --now\n');
        return 2;
      }
      const iso = args[++i];
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) {
        ctx.err(`scheduled tick: invalid date for --now: ${iso}\n`);
        return 2;
      }
      now = d;
    } else if (a.startsWith('--now=')) {
      const iso = a.slice('--now='.length);
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) {
        ctx.err(`scheduled tick: invalid date for --now: ${iso}\n`);
        return 2;
      }
      now = d;
    } else {
      ctx.err(`scheduled tick: unknown option '${a}'\n`);
      return 2;
    }
  }

  const { code, lines } = await tick(ctx, {
    stateDir,
    now: now || (typeof ctx.now === 'function' ? ctx.now() : new Date()),
  });

  if (json) {
    ctx.out(JSON.stringify({ code, lines }, null, 2) + '\n');
  } else {
    for (const line of lines) {
      ctx.out(line + '\n');
    }
  }

  return code;
}
