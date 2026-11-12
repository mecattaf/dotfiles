/**
 * src/verbs/show.mjs - The `scheduled show` verb.
 * Usage: show (ID | PATH) [--json] [-n N] [--from ISO] [--inbox DIR]
 * The parsed item, its next N instants and the last N records the floor handled for it.
 */

import { lstatSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { normalize, revision, formatProblems } from '../lib/schema.mjs';
import { nextInstants } from '../lib/cron.mjs';
import { validateFile, agencyRootOf } from '../lib/validate.mjs';
import { resolveId } from '../lib/resolve.mjs';
import { agencyId } from '../lib/ids.mjs';
import { handled, ofItem } from './history.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled show (ID | PATH) [--json] [-n N] [--from ISO] [--inbox DIR]\n');
}

const jsonProblem = (p) => ({ level: p.severity, code: p.code, path: [], line: p.line ?? 0, col: p.col ?? 0, message: p.message });

export async function main(args, ctx) {
  let target = null;
  let jsonOutput = false;
  let n = 3;
  let fromIso = null;
  let inbox = ctx.inbox;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') jsonOutput = true;
    else if (a === '-n') {
      n = parseInt(args[++i], 10);
      if (isNaN(n) || n < 1) { ctx.err('"-n" must be a positive integer\n'); return 2; }
    } else if (a === '--from') fromIso = args[++i];
    else if (a === '--inbox') inbox = args[++i];
    else if (a.startsWith('-') || target !== null) { usage(ctx); return 2; }
    else target = a;
  }
  if (!target) { usage(ctx); return 2; }

  // A path that exists is shown as the file; anything else is an item id.
  let filePath = resolve(target);
  let isFile = false;
  try { lstatSync(filePath); isFile = true; } catch { /* an id */ }
  if (!isFile) {
    try {
      filePath = (await resolveId(ctx, target)).path;
    } catch (err) {
      return err.exitCode ?? 1;
    }
  }

  const root = agencyRootOf(filePath);
  const stem = basename(filePath, '.jsonc');
  const agency = agencyId(root, ctx.home);
  const { problems, value, bytes, promptBytes, prompt } = await validateFile(filePath, { uid: ctx.uid });

  if (!value) {
    if (jsonOutput) {
      ctx.out(JSON.stringify({ v: 1, results: [{ item: `${agency}:${stem}`, path: filePath,
        revision: bytes ? revision(bytes, promptBytes) : null, valid: false, problems: problems.map(jsonProblem) }] }) + '\n');
    } else {
      ctx.err(formatProblems(filePath, problems).join('\n') + '\n');
    }
    return 1;
  }

  const norm = normalize(value, { file: filePath, root, agency, stem, prompt });
  norm.revision = revision(bytes, promptBytes);
  norm.problems = problems.filter((p) => p.severity === 'warning').map(jsonProblem);

  const fromDate = fromIso ? new Date(fromIso) : (ctx.now ? ctx.now() : new Date());
  if (isNaN(fromDate.getTime())) { ctx.err(`Invalid --from value: "${fromIso}"\n`); return 2; }
  norm.next = nextInstants(value.on?.schedule ?? [], fromDate, n).map((d) => d.toISOString());
  norm.records = inbox ? ofItem(handled(inbox), norm.id).slice(0, n) : null;

  if (jsonOutput) {
    ctx.out(JSON.stringify(norm) + '\n');
    return 0;
  }
  ctx.out(`id: ${norm.id}\n`);
  ctx.out(`path: ${norm.path}\n`);
  ctx.out(`revision: ${norm.revision}\n`);
  ctx.out(`state: ${norm.state}\n`);
  ctx.out(`name: ${norm.spec.name}\n`);
  ctx.out(`enabled: ${norm.spec.enabled}\n`);
  if (norm.next.length > 0) {
    ctx.out(norm.spec.enabled ? 'next occurrences:\n' : 'next occurrences (once enabled):\n');
    for (const d of norm.next) ctx.out(`  ${d}\n`);
  }
  if (norm.records === null) ctx.out('records: no inbox (set SCHEDULED_INBOX or pass --inbox)\n');
  else if (norm.records.length === 0) ctx.out('records: none handled yet\n');
  else {
    ctx.out('records:\n');
    for (const r of norm.records) ctx.out(`  ${r.due ?? '-'}  ${r.state}  ${r.kind ?? '-'}  ${r.occurrence}${r.error ? `  error: ${r.error}` : ''}\n`);
  }
  if (problems.length > 0) ctx.out(formatProblems(filePath, problems).join('\n') + '\n');
  return 0;
}
