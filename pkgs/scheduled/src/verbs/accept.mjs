// scheduled accept ID [--expect REV] [--by WHO] (DESIGN 10.1; C2.12): moves a proposal up to workflows/, sets enabled true, keeps x-proposal.
import { existsSync, readFileSync, unlinkSync } from 'node:fs';
import { resolveId } from '../lib/resolve.mjs';
import { checkExpect, locate, writeWorkflow, guarded, parseFlags, byOf, WriteError } from '../lib/write.mjs';
import { edit } from './set.mjs';

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { allow: ['--expect', '--by'] });
    if (flags.positional.length !== 1) throw new WriteError('usage: scheduled accept ID [--expect REV]', 2);
    let found;
    try { found = await resolveId({ ...ctx, err: () => {} }, flags.positional[0], { proposal: true }); } catch (e) { throw new WriteError(e.message, e.exitCode ?? 1); }
    await checkExpect(found.path, flags.expect, ctx.uid);
    const target = await locate(ctx, found.id);
    if (existsSync(target.path)) throw new WriteError(`${target.path} exists; remove or rename it first`, 1);
    const next = edit(readFileSync(found.path, 'utf8'), 'enabled', true);
    const res = await writeWorkflow(ctx, { path: target.path, bytes: Buffer.from(next), by: byOf(flags, ctx), id: target.id, expect: 'none' });
    unlinkSync(found.path);
    ctx.out(`${target.id} accepted ${res.revision} ${res.path}\n`);
    return 0;
  });
}
