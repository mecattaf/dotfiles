// scheduled history [ID] [--inbox DIR] [--json] [-n N] (docs/scheduled.md, Everyday commands)
//
// What the floor's Source did with each record, newest first: `<inbox>/.done/*.json` (received) and
// `<inbox>/.bad/*.json` (refused, with its `.error` line). The work itself is the superagent's record:
// its Ticket and the dshd unit's session. ID is `<agency>:<item>` or a bare item, matched on the record
// itself, so the history of a removed item still shows.

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readRecord } from '../lib/inbox.mjs';

const USAGE = 'usage: scheduled history [ID] [--inbox DIR] [--json] [-n N]';

/** Every handled record in `inbox`, newest `due` first. */
export function handled(inbox) {
  const rows = [];
  for (const state of ['done', 'bad']) {
    const dir = join(inbox, `.${state}`);
    let names;
    try { names = readdirSync(dir).filter((n) => n.endsWith('.json') && !n.startsWith('.')); } catch { continue; }
    for (const name of names) {
      const rec = readRecord(dir, name) ?? {};
      let error = null;
      if (state === 'bad') {
        try { error = readFileSync(join(dir, `${name}.error`), 'utf8').trim() || null; } catch { /* none */ }
      }
      rows.push({
        occurrence: name.slice(0, -'.json'.length),
        namespace: typeof rec.namespace === 'string' ? rec.namespace : null,
        item: typeof rec.item === 'string' ? rec.item : null,
        kind: rec.kind ?? null,
        due: typeof rec.due === 'string' ? rec.due : null,
        missed: typeof rec.missed === 'number' ? rec.missed : null,
        revision: rec.revision ?? null,
        by: rec.by ?? null,
        state,
        error,
      });
    }
  }
  const at = (r) => (r.due ? Date.parse(r.due) : -Infinity);
  return rows.sort((a, b) => at(b) - at(a) || b.occurrence.localeCompare(a.occurrence));
}

/** Rows of item `id` (`<agency>:<item>` or a bare item). */
export function ofItem(rows, id) {
  const colon = id.lastIndexOf(':');
  const [ns, item] = colon >= 0 ? [id.slice(0, colon), id.slice(colon + 1)] : [null, id];
  return rows.filter((r) => r.item === item && (ns === null || r.namespace === ns));
}

export async function main(args, ctx) {
  let json = false;
  let n = 20;
  let inbox = ctx.inbox;
  let id = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') json = true;
    else if (a === '-n') {
      n = parseInt(args[++i], 10);
      if (!Number.isInteger(n) || n < 1) { ctx.err('scheduled history: -n must be a positive integer\n'); return 2; }
    } else if (a === '--inbox') {
      inbox = args[++i];
      if (!inbox) { ctx.err(`scheduled history: ${USAGE}\n`); return 2; }
    } else if (a.startsWith('-') || id !== null) { ctx.err(`scheduled history: ${USAGE}\n`); return 2; }
    else id = a;
  }
  if (!inbox) { ctx.err('scheduled: --inbox is required\n'); return 2; }

  let rows = handled(inbox);
  if (id) rows = ofItem(rows, id);
  rows = rows.slice(0, n);
  if (json) {
    ctx.out(JSON.stringify({ v: 1, inbox, rows }) + '\n');
    return 0;
  }
  if (rows.length === 0) { ctx.out('no handled records\n'); return 0; }
  for (const r of rows) {
    const missed = r.missed === null ? '-' : String(r.missed);
    ctx.out(`${r.due ?? '-'}  ${r.state.padEnd(4)}  ${(r.kind ?? '-').padEnd(8)}  missed=${missed}  ${r.revision ?? '-'}  ${r.by ?? '-'}  ${r.occurrence}${r.error ? `  error: ${r.error}` : ''}\n`);
  }
  return 0;
}
