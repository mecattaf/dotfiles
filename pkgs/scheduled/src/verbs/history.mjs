// history.mjs — the `scheduled history` verb.
//
// Spec ref: C2.15 (read-only node:sqlite over sched_history_v1 and sched_attempts_v1)
//           DESIGN 5.4 (the SQLite schema and views)
//           DESIGN 10.1 (CLI syntax and exit codes)
//           DESIGN b.11 (History and inspection)

import { join } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import {
  openHistoryDb,
  parseDurationMs,
  queryHistory,
  queryAttempts,
  queryEdits,
  isInstancePruned,
  journalCommand,
  formatHistoryTable,
  formatAttemptsOutput,
  formatEditsTable,
} from '../lib/history.mjs';

export { openHistoryDb };

/**
 * Parse argument list for `scheduled history`.
 *
 * Syntax:
 *   scheduled history (ID | --all) [-n N] [--since DUR] [--json]
 *   scheduled history ID --occurrence KEY [--log] [--json]
 *   scheduled history ID --edits [--diff] [--json]
 *
 * @param {string[]} args
 * @returns {object}
 */
export function parseArgs(args) {
  const result = {
    id: null,
    all: false,
    limit: null,
    since: null,
    json: false,
    occurrence: null,
    log: false,
    edits: false,
    diff: false,
    stateDir: null,
    help: false,
    errors: [],
  };

  const positional = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      result.help = true;
      return result;
    }
    if (arg === '--all') {
      result.all = true;
    } else if (arg === '--json') {
      result.json = true;
    } else if (arg === '--log') {
      result.log = true;
    } else if (arg === '--edits') {
      result.edits = true;
    } else if (arg === '--diff') {
      result.diff = true;
    } else if (arg === '-n') {
      i++;
      if (i >= args.length) {
        result.errors.push('-n requires an argument');
      } else {
        const val = parseInt(args[i], 10);
        if (isNaN(val) || val <= 0 || String(val) !== args[i].trim()) {
          result.errors.push(`invalid -n limit: ${args[i]}`);
        } else {
          result.limit = val;
        }
      }
    } else if (arg.startsWith('-n=')) {
      const valStr = arg.slice(3);
      const val = parseInt(valStr, 10);
      if (isNaN(val) || val <= 0 || String(val) !== valStr.trim()) {
        result.errors.push(`invalid -n limit: ${valStr}`);
      } else {
        result.limit = val;
      }
    } else if (/^-n\d+$/.test(arg)) {
      const val = parseInt(arg.slice(2), 10);
      if (val <= 0) {
        result.errors.push(`invalid -n limit: ${arg.slice(2)}`);
      } else {
        result.limit = val;
      }
    } else if (arg === '--since') {
      i++;
      if (i >= args.length) {
        result.errors.push('--since requires an argument');
      } else {
        result.since = args[i];
      }
    } else if (arg.startsWith('--since=')) {
      result.since = arg.slice(8);
    } else if (arg === '--occurrence') {
      i++;
      if (i >= args.length) {
        result.errors.push('--occurrence requires an argument');
      } else {
        result.occurrence = args[i];
      }
    } else if (arg.startsWith('--occurrence=')) {
      result.occurrence = arg.slice(13);
    } else if (arg === '--state-dir') {
      i++;
      if (i >= args.length) {
        result.errors.push('--state-dir requires an argument');
      } else {
        result.stateDir = args[i];
      }
    } else if (arg.startsWith('--state-dir=')) {
      result.stateDir = arg.slice(12);
    } else if (arg.startsWith('-')) {
      result.errors.push(`unknown option: ${arg}`);
    } else {
      positional.push(arg);
    }
  }

  if (positional.length > 1) {
    result.errors.push(`unexpected positional arguments: ${positional.slice(1).join(' ')}`);
  } else if (positional.length === 1) {
    result.id = positional[0];
  }

  return result;
}

/**
 * Entry point for the `history` verb.
 *
 * @param {string[]} args  argv after `history`
 * @param {object} ctx     shared execution context
 * @returns {Promise<number>} exit code
 */
export async function main(args, ctx) {
  const parsed = parseArgs(args);

  if (parsed.help) {
    ctx.out(`Usage:
  scheduled history (ID | --all) [-n N] [--since DUR] [--json]
  scheduled history ID --occurrence KEY [--log] [--json]
  scheduled history ID --edits [--diff] [--json]
`);
    return 0;
  }

  if (parsed.errors.length > 0) {
    for (const err of parsed.errors) {
      ctx.err(`scheduled: ${err}\n`);
    }
    return 2;
  }

  if (parsed.all && parsed.id) {
    ctx.err('scheduled: cannot specify both --all and a workflow ID\n');
    return 2;
  }

  if (!parsed.all && !parsed.id) {
    ctx.err('scheduled: must specify a workflow ID or --all\n');
    return 2;
  }

  if (parsed.occurrence && parsed.all) {
    ctx.err('scheduled: --occurrence requires a workflow ID, not --all\n');
    return 2;
  }

  if (parsed.edits && parsed.all) {
    ctx.err('scheduled: --edits requires a workflow ID, not --all\n');
    return 2;
  }

  if (parsed.occurrence && parsed.edits) {
    ctx.err('scheduled: cannot specify both --occurrence and --edits\n');
    return 2;
  }

  if (parsed.diff && !parsed.edits) {
    ctx.err('scheduled: --diff requires --edits\n');
    return 2;
  }

  if (parsed.log && !parsed.occurrence) {
    ctx.err('scheduled: --log requires --occurrence\n');
    return 2;
  }

  if ((parsed.limit !== null || parsed.since !== null) && (parsed.occurrence || parsed.edits)) {
    ctx.err('scheduled: -n and --since cannot be used with --occurrence or --edits\n');
    return 2;
  }


  // Validate --since format before touching the database
  let sinceMs = null;
  if (parsed.since) {
    try {
      sinceMs = parseDurationMs(parsed.since);
    } catch (err) {
      ctx.err(`scheduled: ${err.message}\n`);
      return 2;
    }
  }

  const stateDir = parsed.stateDir || ctx.stateDir || join(ctx.home, '.agency', 'state', 'master');

  // -------------------------------------------------------------------------
  // Form 3: `scheduled history ID --edits [--diff] [--json]`
  // -------------------------------------------------------------------------
  if (parsed.edits) {
    let edits;
    try {
      edits = queryEdits({ stateDir, id: parsed.id });
    } catch (err) {
      ctx.err(`scheduled: state directory unreadable: ${err.message}\n`);
      return 4;
    }
    if (parsed.diff) {
      // The last two stored revisions of the workflow, older first (blobs under revisions/).
      const stored = edits.filter((e) => typeof e.file === 'string' && e.file && !e.removed);
      if (stored.length < 2) {
        ctx.err(`scheduled: ${parsed.id} has ${stored.length} stored revision(s); --diff needs two\n`);
        return 1;
      }
      const [newer, older] = stored;
      const read = (e) => readFileSync(join(stateDir, 'revisions', `${e.file}.jsonc`), 'utf8');
      let a, b;
      try { a = read(older); b = read(newer); } catch (err) {
        ctx.err(`scheduled: revision blob unreadable: ${err.message}\n`);
        return 4;
      }
      ctx.out(unifiedDiff(a, b, `${parsed.id}@${older.revision} (${older.seen_at}, ${older.by})`,
        `${parsed.id}@${newer.revision} (${newer.seen_at}, ${newer.by})`));
      return 0;
    }
    if (parsed.json) {
      ctx.out(JSON.stringify(edits, null, 2) + '\n');
      return 0;
    }
    ctx.out(formatEditsTable(edits));
    return 0;
  }

  // -------------------------------------------------------------------------
  // Forms 1 & 2: Database operations over sched_history_v1 / sched_attempts_v1
  // -------------------------------------------------------------------------
  const dbPath = join(stateDir, 'orchestrator.sqlite');
  let db;
  let shouldClose = false;

  try {
    if (ctx.db) {
      db = ctx.db;
    } else {
      if (!existsSync(dbPath)) {
        ctx.err(`scheduled: database not found or unreadable: ${dbPath}\n`);
        return 4;
      }
      db = openHistoryDb(dbPath);
      shouldClose = true;
    }
  } catch (err) {
    ctx.err(`scheduled: database not found or unreadable: ${err.message}\n`);
    return 4;
  }

  if (ctx._dbRef) {
    ctx._dbRef.current = db;
    shouldClose = false;
  }

  // -------------------------------------------------------------------------
  // Form 2: `scheduled history ID --occurrence KEY [--log] [--json]`
  // -------------------------------------------------------------------------
  if (parsed.occurrence) {
    let attempts;
    try {
      attempts = queryAttempts(db, parsed.occurrence);
    } catch (err) {
      ctx.err(`scheduled: database not found or unreadable: ${err.message}\n`);
      if (shouldClose) db.close();
      return 4;
    }

    if (parsed.log) {
      if (attempts.length === 0) {
        ctx.err(`scheduled: no attempts found for occurrence ${parsed.occurrence}\n`);
        if (shouldClose) db.close();
        return 1;
      }
      const latest = attempts[attempts.length - 1];
      const pruned = isInstancePruned(ctx, latest.instance);
      if (pruned) {
        ctx.out('instance pruned\n');
        ctx.out(`${journalCommand(latest)}\n`);
        if (shouldClose) db.close();
        return 0;
      }
      const dshd = ctx.dshd || process.env.SCHEDULED_DSHD;
      const res = spawnSync(dshd, ['read', '-n', '200', latest.instance], {
        encoding: 'utf8',
        env: ctx.env || process.env,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      if (res.error || res.status !== 0) {
        ctx.out('instance pruned\n');
        ctx.out(`${journalCommand(latest)}\n`);
      } else {
        ctx.out(res.stdout);
      }
      if (shouldClose) db.close();
      return 0;
    }

    if (parsed.json) {
      ctx.out(JSON.stringify(attempts, null, 2) + '\n');
    } else {
      ctx.out(formatAttemptsOutput(attempts, ctx));
    }
    if (shouldClose) db.close();
    return 0;
  }

  // -------------------------------------------------------------------------
  // Form 1: `scheduled history (ID | --all) [-n N] [--since DUR] [--json]`
  // -------------------------------------------------------------------------
  let rows;
  try {
    rows = queryHistory(db, {
      id: parsed.all ? null : parsed.id,
      all: parsed.all,
      sinceMs,
      limit: parsed.limit,
      now: typeof ctx.now === 'function' ? ctx.now() : new Date(),
    });
  } catch (err) {
    ctx.err(`scheduled: database not found or unreadable: ${err.message}\n`);
    if (shouldClose) db.close();
    return 4;
  }

  if (parsed.json) {
    ctx.out(JSON.stringify(rows, null, 2) + '\n');
  } else {
    ctx.out(formatHistoryTable(rows, { all: parsed.all }));
  }

  if (shouldClose) db.close();
  return 0;
}

/**
 * A unified diff with whole-file context (workflow files are at most 64 KiB):
 * `---`/`+++` headers, then every line prefixed ' ', '-' or '+', from an LCS.
 */
export function unifiedDiff(a, b, labelA, labelB) {
  const x = a.split('\n'), y = b.split('\n');
  if (x.at(-1) === '') x.pop();
  if (y.at(-1) === '') y.pop();
  const n = x.length, m = y.length;
  const lcs = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) {
    lcs[i][j] = x[i] === y[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  }
  const out = [`--- ${labelA}`, `+++ ${labelB}`, `@@ -1,${n} +1,${m} @@`];
  let i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && x[i] === y[j]) { out.push(` ${x[i]}`); i++; j++; }
    else if (i < n && (j >= m || lcs[i + 1][j] >= lcs[i][j + 1])) { out.push(`-${x[i]}`); i++; }
    else { out.push(`+${y[j]}`); j++; }
  }
  return out.join('\n') + '\n';
}
