// scheduled rm ID [--expect REV] [--by WHO] (DESIGN 10.1): deletes the file; the ledger keeps a removed line.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { resolveId } from '../lib/resolve.mjs';
import { appendLine } from '../lib/atomic.mjs';
import { checkExpect, currentRevision, guarded, parseFlags, byOf, WriteError } from '../lib/write.mjs';

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { allow: ['--expect', '--by'] });
    if (flags.positional.length !== 1) throw new WriteError('usage: scheduled rm ID [--expect REV] [--by WHO]', 2);
    let found;
    try { found = await resolveId({ ...ctx, err: () => {} }, flags.positional[0]); } catch (e) { throw new WriteError(e.message, e.exitCode ?? 1); }
    await checkExpect(found.path, flags.expect, ctx.uid);
    const rev = await currentRevision(found.path, ctx.uid);
    const bytes = readFileSync(found.path);
    unlinkSync(found.path);
    const revDir = join(ctx.stateDir, 'revisions');
    mkdirSync(revDir, { recursive: true, mode: 0o700 });
    await appendLine(join(revDir, 'index.jsonl'), { v: 1, workflow: found.id, revision: rev, file: createHash('sha256').update(bytes).digest('hex'),
      prompt: null, seen_at: (ctx.now?.() ?? new Date()).toISOString(), by: byOf(flags, ctx), valid: false, removed: true });
    ctx.out(`${found.id} removed (was ${rev ?? 'unknown'}) from ${dirname(found.path)}\n`);
    return 0;
  });
}
