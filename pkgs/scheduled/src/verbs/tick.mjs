// src/verbs/tick.mjs — The `scheduled tick` verb (scheduled-jsonc §4).
//
// Usage: scheduled tick --inbox DIR [--state-dir DIR] [--home DIR] [--floor-instance NAME] [--now ISO --state-dir DIR] [--json]

import { tick } from '../lib/tick.mjs';
import { parseLocationFlags } from '../lib/flags.mjs';

/**
 * CLI entry point for `scheduled tick`.
 *
 * @param {string[]} args Arguments after the verb
 * @param {object} ctx Context object from makeContext()
 * @returns {Promise<number>} Exit code
 */
export async function main(args, ctx) {
  const parsed = parseLocationFlags(args, ctx, ['--inbox', '--state-dir', '--home', '--floor-instance', '--now']);
  if (parsed.error || parsed.positional.length) {
    ctx.err(`<3>scheduled tick: ${parsed.error ?? `unexpected argument '${parsed.positional[0]}'`}\n`);
    return 2;
  }
  if (!parsed.opts.inbox) {
    ctx.err('<3>scheduled: --inbox is required\n');
    return 2;
  }
  // A pass at another time commits lastTick: in the unit's own state dir, a future --now would stall every
  // real tick after it on "clock went back" until that date (review SCHED-3). So --now names its state dir.
  if (parsed.opts.now !== undefined && !args.some((a) => a === '--state-dir' || a.startsWith('--state-dir='))) {
    ctx.err('<3>scheduled tick: --now needs an explicit --state-dir (a scratch one, never the heartbeat\'s own)\n');
    return 2;
  }
  const { code, lines } = await tick(ctx, parsed.opts);
  if (parsed.json) ctx.out(JSON.stringify({ code, lines }, null, 2) + '\n');
  else for (const line of lines) ctx.out(line + '\n');
  return code;
}
