// scheduled set ID PATH (VALUE | --unset) [--expect REV] [--by WHO] (DESIGN 10.1; C2.11)
// jsonc-parser's modify + applyEdits: comments survive and only the touched text changes.
import { readFileSync } from 'node:fs';
import * as jsonc from 'jsonc-parser';
import { resolveId } from '../lib/resolve.mjs';
import { locate, writeWorkflow, guarded, parseFlags, byOf, WriteError } from '../lib/write.mjs';

export function parsePath(path) {
  // `on.schedule[0].cron` (the skill's spelling) and `on.schedule.0.cron` are the same path.
  return path.replace(/\[(\d+)\]/g, '.$1').split('.').map((seg) => (/^\d+$/.test(seg) ? Number(seg) : seg));
}
export function parseValue(raw) {
  try { return JSON.parse(raw); } catch { return raw; }
}
/** The edited text: one `modify`, applied with formatting that keeps the file's own indentation. */
export function edit(text, path, value) {
  const edits = jsonc.modify(text, parsePath(path), value, { formattingOptions: { insertSpaces: true, tabSize: 2, eol: '\n' } });
  return jsonc.applyEdits(text, edits);
}

export async function main(args, ctx) {
  return guarded(ctx, async () => {
    const flags = parseFlags(args, { allow: ['--expect', '--by', '--unset'] });
    const [id, path, raw] = flags.positional;
    if (!id || !path || (flags.unset ? raw !== undefined : raw === undefined)) {
      throw new WriteError('usage: scheduled set ID PATH (VALUE | --unset) [--expect REV] [--by WHO]', 2);
    }
    let found;
    try { found = await resolveId({ ...ctx, err: () => {} }, id); } catch (e) { throw new WriteError(e.message, e.exitCode ?? 1); }
    const target = await locate(ctx, found.id);
    const text = readFileSync(found.path, 'utf8');
    const next = edit(text, path, flags.unset ? undefined : parseValue(raw));
    if (next === text) { ctx.out(`${found.id} unchanged\n`); return 0; }
    const res = await writeWorkflow(ctx, { path: found.path, bytes: Buffer.from(next), by: byOf(flags, ctx), id: target.id, expect: flags.expect });
    ctx.out(`${found.id} ${res.revision} ${res.path}\n`);
    return 0;
  });
}
