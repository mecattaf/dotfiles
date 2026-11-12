// scheduled rm ID [--expect REV]: deletes the item file. A record it already handed off is withdrawn by the
// next tick while the floor is not reading the inbox.
import { unlinkSync } from 'node:fs';
import { dirname } from 'node:path';
import { resolveId } from '../lib/resolve.mjs';
import { checkExpect, currentRevision, guarded, parseFlags, WriteError } from '../lib/write.mjs';

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { values: ['--expect'] });
    if (flags.positional.length !== 1) throw new WriteError('usage: scheduled rm ID [--expect REV]', 2);
    let found;
    try { found = await resolveId({ ...ctx, err: () => {} }, flags.positional[0]); } catch (e) { throw new WriteError(e.message, e.exitCode ?? 1); }
    await checkExpect(found.path, flags.expect, ctx.uid);
    const rev = await currentRevision(found.path, ctx.uid);
    unlinkSync(found.path);
    ctx.out(`${found.id} removed (was ${rev ?? 'unknown'}) from ${dirname(found.path)}\n`);
    return 0;
  });
}
