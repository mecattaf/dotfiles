// history.mjs — queries and formatting for `scheduled history`.
//
// Spec ref: C2.15 (read-only node:sqlite over sched_history_v1 and sched_attempts_v1)
//           DESIGN 5.4 (the SQLite schema and views)
//           DESIGN 10.1 (CLI syntax and exit codes)
//           DESIGN b.11 (History and inspection)

import { DatabaseSync } from 'node:sqlite';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

// ---------------------------------------------------------------------------
// Database connection
// ---------------------------------------------------------------------------

/**
 * Open the orchestrator database in read-only mode.
 * C2.15: opens with readOnly: true, so any write fails with
 * 'attempt to write a readonly database'.
 *
 * @param {string} dbPath  absolute path to orchestrator.sqlite
 * @returns {DatabaseSync}
 */
export function openHistoryDb(dbPath) {
  return new DatabaseSync(dbPath, { readOnly: true });
}

// ---------------------------------------------------------------------------
// Duration parsing
// ---------------------------------------------------------------------------

/**
 * Parse a human duration string (e.g. '24h', '1d', '30m', '3600s') into milliseconds.
 *
 * @param {string} str
 * @returns {number} duration in milliseconds
 * @throws {Error} if format is invalid
 */
export function parseDurationMs(str) {
  if (typeof str !== 'string' || !str.trim()) {
    throw new Error(`Invalid duration: ${str}`);
  }
  const s = str.trim();
  const re = /^([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]+)$/;
  const match = s.match(re);
  if (!match) {
    throw new Error(`Invalid duration format: "${str}"`);
  }
  const val = parseFloat(match[1]);
  const unit = match[2].toLowerCase();
  switch (unit) {
    case 'ms':
    case 'msec':
    case 'millisecond':
    case 'milliseconds':
      return val;
    case 's':
    case 'sec':
    case 'secs':
    case 'second':
    case 'seconds':
      return val * 1000;
    case 'm':
    case 'min':
    case 'mins':
    case 'minute':
    case 'minutes':
      return val * 60 * 1000;
    case 'h':
    case 'hr':
    case 'hrs':
    case 'hour':
    case 'hours':
      return val * 60 * 60 * 1000;
    case 'd':
    case 'day':
    case 'days':
      return val * 24 * 60 * 60 * 1000;
    case 'w':
    case 'week':
    case 'weeks':
      return val * 7 * 24 * 60 * 60 * 1000;
    default:
      throw new Error(`Unknown duration unit: "${unit}" in "${str}"`);
  }
}

// ---------------------------------------------------------------------------
// Date formatting (Paris timezone)
// ---------------------------------------------------------------------------

/**
 * Format an ISO date/timestamp into 'Europe/Paris' time:
 * Example: '12 Nov 01:00'
 *
 * @param {string|Date} iso
 * @returns {string}
 */
export function formatParisDate(iso) {
  if (!iso) return '-';
  try {
    const d = iso instanceof Date ? iso : new Date(iso);
    if (isNaN(d.getTime())) return String(iso);
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Paris',
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(d);
    const m = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    return `${m.day} ${m.month} ${m.hour}:${m.minute}`;
  } catch {
    return String(iso);
  }
}

// ---------------------------------------------------------------------------
// Note derivation
// ---------------------------------------------------------------------------

/**
 * Derive the NOTE column value for a history row.
 * Spec examples:
 *   - 'receipt ok 04:12'
 *   - 'command exited 1'
 *   - 'by panel; exit 1'
 *
 * @param {object} row
 * @returns {string}
 */
export function deriveNote(row) {
  const parts = [];
  if (row.by) {
    parts.push(`by ${row.by}`);
  }
  const detail = row.reason || (row.report ? row.report.trim().split('\n')[0] : '');
  if (detail) {
    if (row.by && detail.startsWith(`by ${row.by}`)) {
      return detail;
    }
    parts.push(detail);
  }
  return parts.join('; ');
}

// ---------------------------------------------------------------------------
// Floor database queries (read-only views)
// ---------------------------------------------------------------------------

/**
 * Query `sched_history_v1`.
 *
 * @param {DatabaseSync} db
 * @param {object} opts
 * @param {string} [opts.id] workflow ID ('<agency>:<stem>')
 * @param {boolean} [opts.all] if true, include all workflows
 * @param {number} [opts.sinceMs] milliseconds back from `now`
 * @param {number} [opts.limit] maximum rows
 * @param {Date} [opts.now] current clock reference
 * @returns {object[]} plain row objects
 */
export function queryHistory(db, { id = null, all = false, sinceMs = null, limit = null, now = new Date() } = {}) {
  let sql = 'SELECT occurrence, workflow, kind, due_at, missed, state, reason, attempt, instance, revision, started_at, ended_at, report, "by", updated_at FROM sched_history_v1';
  const conditions = [];
  const params = [];

  if (!all && id) {
    conditions.push('workflow = ?');
    params.push(id);
  }

  if (sinceMs !== null && Number.isFinite(sinceMs)) {
    const cutoff = new Date(now.getTime() - sinceMs).toISOString();
    conditions.push('due_at >= ?');
    params.push(cutoff);
  }

  if (conditions.length > 0) {
    sql += ' WHERE ' + conditions.join(' AND ');
  }

  sql += ' ORDER BY due_at DESC';

  if (limit !== null && Number.isFinite(limit)) {
    sql += ' LIMIT ?';
    params.push(limit);
  }

  const stmt = db.prepare(sql);
  return stmt.all(...params);
}

/**
 * Query `sched_attempts_v1` for a specific occurrence key.
 *
 * @param {DatabaseSync} db
 * @param {string} occurrence  occurrence key
 * @returns {object[]} plain row objects ordered by attempt ASC, rerun ASC
 */
export function queryAttempts(db, occurrence) {
  const sql = 'SELECT occurrence, attempt, rerun, instance, revision, invocation, started_at, ended_at, ending, exit_code, report FROM sched_attempts_v1 WHERE occurrence = ? ORDER BY attempt ASC, rerun ASC';
  const stmt = db.prepare(sql);
  return stmt.all(occurrence);
}

// ---------------------------------------------------------------------------
// Revisions ledger queries
// ---------------------------------------------------------------------------

/**
 * Query the revisions ledger from `<stateDir>/revisions/index.jsonl`.
 *
 * @param {object} opts
 * @param {string} opts.stateDir
 * @param {string} opts.id workflow ID
 * @returns {object[]} list of revision objects, newest first
 */
export function queryEdits({ stateDir, id }) {
  if (!existsSync(stateDir)) {
    const err = new Error(`State directory does not exist: ${stateDir}`);
    err.code = 'ENOENT';
    throw err;
  }
  const indexFile = join(stateDir, 'revisions', 'index.jsonl');
  if (!existsSync(indexFile)) {
    return [];
  }
  const content = readFileSync(indexFile, 'utf8');
  const lines = content.split('\n');
  const results = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const entry = JSON.parse(trimmed);
      const entryId = entry.id ?? entry.workflow ?? entry.workflow_id;
      if (entryId === id) {
        results.push({
          revision: entry.revision ?? entry.rev ?? '',
          seen_at: entry.seen_at ?? entry.at ?? '',
          by: entry.by ?? '',
          ...entry,
        });
      }
    } catch {
      // Ignore malformed JSON lines
    }
  }
  results.sort((a, b) => {
    const timeA = a.seen_at ? new Date(a.seen_at).getTime() : 0;
    const timeB = b.seen_at ? new Date(b.seen_at).getTime() : 0;
    return timeB - timeA;
  });
  return results;
}

// ---------------------------------------------------------------------------
// dshd pruning check
// ---------------------------------------------------------------------------

/**
 * Check if a dshd instance has been pruned.
 * Uses `dshd get --json <instance>`.
 *
 * @param {object} ctx
 * @param {string} instance
 * @returns {boolean} true if pruned or instance not found
 */
export function isInstancePruned(ctx, instance) {
  if (!instance) return true;
  const dshd = ctx?.dshd || process.env.SCHEDULED_DSHD;
  if (!dshd) return true;
  try {
    const res = spawnSync(dshd, ['get', '--json', instance], {
      encoding: 'utf8',
      env: ctx.env || process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (res.error || res.status !== 0) {
      return true;
    }
    try {
      const data = JSON.parse(res.stdout);
      if (data && (data.pruned === true || data.state === 'pruned')) {
        return true;
      }
    } catch {
      // non-JSON stdout
    }
    return false;
  } catch {
    return true;
  }
}

// ---------------------------------------------------------------------------
// Output formatting
// ---------------------------------------------------------------------------

/**
 * Format history rows as a tabular text output.
 * Matches DESIGN b.11:
 *
 * OCCURRENCE (Paris)  KIND      STATE   ATTEMPTS  NOTE
 * 12 Nov 01:00        schedule  done    2         receipt ok 04:12
 * 11 Nov 01:00        schedule  missed  0         command exited 1
 * 10 Nov 15:42        manual    failed  1         by panel; exit 1
 *
 * @param {object[]} rows
 * @param {object} [opts]
 * @param {boolean} [opts.all] whether this spans all workflows
 * @returns {string}
 */
export function formatHistoryTable(rows, { all = false } = {}) {
  if (all) {
    let wfWidth = 8; // length of 'WORKFLOW'
    for (const r of rows) {
      if (r.workflow && r.workflow.length > wfWidth) {
        wfWidth = r.workflow.length;
      }
    }
    wfWidth = Math.max(wfWidth + 2, 20);

    const header = `${'WORKFLOW'.padEnd(wfWidth)}OCCURRENCE (Paris)  KIND      STATE   ATTEMPTS  NOTE\n`;
    if (!rows || rows.length === 0) {
      return header;
    }
    const lines = [header];
    for (const r of rows) {
      const wfCol = (r.workflow || '-').padEnd(wfWidth);
      const occCol = formatParisDate(r.due_at).padEnd(20);
      const kindCol = (r.kind || '-').padEnd(10);
      const stateCol = (r.state || '-').padEnd(8);
      const attCol = String(r.attempt ?? 0).padEnd(10);
      const noteCol = deriveNote(r);
      lines.push(`${wfCol}${occCol}${kindCol}${stateCol}${attCol}${noteCol}\n`);
    }
    return lines.join('');
  }

  const header = 'OCCURRENCE (Paris)  KIND      STATE   ATTEMPTS  NOTE\n';
  if (!rows || rows.length === 0) {
    return header;
  }
  const lines = [header];
  for (const r of rows) {
    const occCol = formatParisDate(r.due_at).padEnd(20);
    const kindCol = (r.kind || '-').padEnd(10);
    const stateCol = (r.state || '-').padEnd(8);
    const attCol = String(r.attempt ?? 0).padEnd(10);
    const noteCol = deriveNote(r);
    lines.push(`${occCol}${kindCol}${stateCol}${attCol}${noteCol}\n`);
  }
  return lines.join('');
}

/**
 * Format attempts for an occurrence key.
 *
 * @param {object[]} attempts
 * @param {object} ctx
 * @returns {string}
 */
/**
 * The journalctl command that still prints an attempt's log after upkeep
 * removed its instance (C9.7): by its systemd InvocationID when the floor
 * recorded one, else by the unit name (which a later run of the same name
 * would share).
 *
 * @param {{instance: string, invocation?: string|null}} attempt
 * @returns {string}
 */
export function journalCommand(attempt) {
  const id = typeof attempt.invocation === 'string' ? attempt.invocation.trim() : '';
  return /^[0-9a-f]{32}$/i.test(id)
    ? `journalctl --user _SYSTEMD_INVOCATION_ID=${id}`
    : `journalctl --user -u dshd@${attempt.instance}.service`;
}

export function formatAttemptsOutput(attempts, ctx) {
  if (!attempts || attempts.length === 0) {
    return 'No attempts recorded.\n';
  }

  const out = [];
  for (const a of attempts) {
    const lines = [];
    lines.push(`Attempt ${a.attempt} (rerun ${a.rerun ?? 0})`);
    lines.push(`  Instance:   ${a.instance}`);
    lines.push(`  Started:    ${a.started_at ?? '-'}`);
    lines.push(`  Ended:      ${a.ended_at ?? '-'}`);
    lines.push(`  Ending:     ${a.ending ?? '-'}`);
    lines.push(`  Exit code:  ${a.exit_code !== null && a.exit_code !== undefined ? a.exit_code : '-'}`);
    lines.push(`  Revision:   ${a.revision ?? '-'}`);
    if (a.report) {
      lines.push('  Report:');
      const rep = String(a.report).slice(0, 1500);
      for (const repLine of rep.split('\n')) {
        lines.push(`    ${repLine}`);
      }
    }
    lines.push('  Commands:');
    const pruned = isInstancePruned(ctx, a.instance);
    if (pruned) {
      lines.push('    instance pruned');
      lines.push(`    ${journalCommand(a)}`);
    } else {
      lines.push(`    dshd read ${a.instance}`);
      lines.push(`    ${journalCommand(a)}`);
    }
    out.push(lines.join('\n'));
  }

  return out.join('\n\n') + '\n';
}

/**
 * Format revision edits as a table.
 *
 * @param {object[]} edits
 * @returns {string}
 */
export function formatEditsTable(edits) {
  const header = 'REVISION      SEEN (Paris)      BY\n';
  if (!edits || edits.length === 0) {
    return header;
  }
  const lines = [header];
  for (const e of edits) {
    const rev = (e.revision ?? '').padEnd(14);
    const seen = formatParisDate(e.seen_at).padEnd(18);
    const by = e.by || '-';
    lines.push(`${rev}${seen}${by}\n`);
  }
  return lines.join('');
}
