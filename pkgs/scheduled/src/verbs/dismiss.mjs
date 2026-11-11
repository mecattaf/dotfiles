// scheduled dismiss ID [--by WHO] (DESIGN 10.1; C2.12): deletes a proposal and refuses its stem for 30 days.
import { unlinkSync } from 'node:fs';
import { resolveId } from '../lib/resolve.mjs';
import { guarded, parseFlags, byOf, recordDismissal, WriteError } from '../lib/write.mjs';

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { allow: ['--by'] });
    if (flags.positional.length !== 1) throw new WriteError('usage: scheduled dismiss ID', 2);
    let found;
    try { found = await resolveId({ ...ctx, err: () => {} }, flags.positional[0], { proposal: true }); } catch (e) { throw new WriteError(e.message, e.exitCode ?? 1); }
    unlinkSync(found.path);
    await recordDismissal(ctx.stateDir, { v: 1, agency: found.agency, stem: found.stem, id: found.id, at: (ctx.now?.() ?? new Date()).toISOString(), by: byOf(flags, ctx) });
    ctx.out(`${found.id} dismissed\n`);
    return 0;
  });
}
