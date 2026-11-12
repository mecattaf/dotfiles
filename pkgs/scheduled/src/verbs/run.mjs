// scheduled run ID [--home DIR] [--inbox DIR] [--floor-instance NAME] [--json] (scheduled-jsonc §5)
//
// Run now: validates the item (enabled or not), links one `manual` occurrence record into the inbox, then
// applies the wake table with that record waiting. No database, no waiting for the work: the floor's
// Source turns the record into a Trigger, and the superagent judges it like any occurrence.

import { resolveId } from '../lib/resolve.mjs';
import { validateFile } from '../lib/validate.mjs';
import { formatProblems } from '../lib/schema.mjs';
import { ulid } from '../lib/ids.mjs';
import { RUN, handOff, makeRecord, recordProblem, waiting } from '../lib/inbox.mjs';
import { dshdRunner, wake } from '../lib/floor.mjs';
import { parseLocationFlags } from '../lib/flags.mjs';

const USAGE = 'usage: scheduled run ID [--home DIR] [--inbox DIR] [--floor-instance NAME] [--json]';

export async function main(args, ctx, { run: runOpt } = {}) {
  const parsed = parseLocationFlags(args, ctx, ['--inbox', '--home', '--floor-instance']);
  if (parsed.error || parsed.positional.length !== 1) {
    ctx.err(`scheduled run: ${parsed.error ?? USAGE}\n`);
    return 2;
  }
  const { opts, json } = parsed;
  if (!opts.inbox) {
    ctx.err('scheduled: --inbox is required\n');
    return 2;
  }

  let found;
  try {
    found = await resolveId({ ...ctx, home: opts.home }, parsed.positional[0]);
  } catch (e) {
    return e.exitCode ?? 1;
  }
  const checked = await validateFile(found.path, { uid: ctx.uid });
  if (!checked.value) {
    ctx.err(formatProblems(found.path, checked.problems).join('\n') + '\n');
    return 1;
  }

  const now = ctx.now?.() ?? new Date();
  const record = makeRecord({
    kind: 'manual', namespace: found.agency, item: found.stem, name: checked.value.name, cwd: found.root,
    file: found.path, due: now, run: ulid(now), missed: 0, revision: checked.revision, text: checked.prompt, by: RUN, at: now,
  });
  const problem = recordProblem(record);
  if (problem) {
    ctx.err(`scheduled run: ${found.id}: ${problem}\n`);
    return 1;
  }
  const { name, result } = await handOff(opts.inbox, record);

  const runner = runOpt || dshdRunner(ctx.dshd, { ...process.env, ...(ctx.env || {}) });
  const woke = await wake({ instance: opts.floorInstance, waiting: Math.max(1, waiting(opts.inbox).length), floor: null, run: runner });
  const floor = !opts.floorInstance ? 'none' : (woke.lines[0] ?? '').replace(/^<\d>/, '');
  for (const line of woke.lines) ctx.err(line.replace(/^<\d>/, 'scheduled run: ') + '\n');

  const occurrence = name.slice(0, -'.json'.length);
  if (json) ctx.out(JSON.stringify({ occurrence, file: `${opts.inbox}/${name}`, floor, result }) + '\n');
  else ctx.out(`${found.id} ${occurrence} ${result} floor: ${floor}\n`);
  return result === 'created' && !woke.fault ? 0 : 1;
}
