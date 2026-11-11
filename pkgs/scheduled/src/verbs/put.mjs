// scheduled put ID [--expect REV|none] [--proposal] [--by WHO] < TEXT (DESIGN 10.1; C2.9, C2.10, C2.12)
import { readFileSync } from 'node:fs';
import { locate, writeWorkflow, guarded, parseFlags, byOf, openProposals, dismissedRecently, MAX_PROPOSALS, WriteError } from '../lib/write.mjs';

export function readStdin(ctx) {
  if (typeof ctx.stdin === 'string' || Buffer.isBuffer(ctx.stdin)) return Buffer.from(ctx.stdin);
  try { return readFileSync('/dev/stdin'); } catch (e) { throw new WriteError(`cannot read stdin: ${e.message}`, 4); }
}

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args);
    if (flags.positional.length !== 1) throw new WriteError('usage: scheduled put ID [--expect REV|none] [--proposal] [--by WHO] < TEXT', 2);
    const target = await locate(ctx, flags.positional[0], { proposal: !!flags.proposal });
    if (flags.proposal) {
      const open = openProposals(target.workflows).filter((n) => n !== `${target.stem}.jsonc`);
      if (open.length >= MAX_PROPOSALS) throw new WriteError(`agency ${target.agency} already has ${open.length} open proposals (at most ${MAX_PROPOSALS})`, 1);
      const dismissed = dismissedRecently(ctx.stateDir, target.agency, target.stem, ctx.now?.() ?? new Date());
      if (dismissed) throw new WriteError(`${target.id} was dismissed on ${dismissed.at}; it is refused for 30 days`, 1);
    }
    const bytes = readStdin(ctx);
    const res = await writeWorkflow(ctx, { path: target.path, bytes, by: byOf(flags, ctx), id: target.id, proposal: !!flags.proposal, expect: flags.expect });
    ctx.out(`${target.id} ${res.revision} ${res.path}\n`);
    return 0;
  });
}
