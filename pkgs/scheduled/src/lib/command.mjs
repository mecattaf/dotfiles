// command.mjs — Command execution, process-group management, and SCHED_* env.
//
// Spec ref: §5.2 (Command type, SCHED_* env vars, execution sandbox)
//           Claim C2.14 (sandbox rules, process-group kill, last 4 KiB output)

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

/**
 * Format a Date as YYYY-MM-DD in the specified timezone using en-CA locale.
 *
 * @param {Date} date
 * @param {string} timezone
 * @returns {string}
 */
export function formatLocalDate(date, timezone) {
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    return formatter.format(date);
  } catch {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'UTC',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    return formatter.format(date);
  }
}

/**
 * Decode timestamp from standard 26-char Crockford base32 ULID.
 *
 * @param {string} ulidStr
 * @returns {Date | null}
 */
export function ulidToDate(ulidStr) {
  if (typeof ulidStr !== 'string' || ulidStr.length < 10) return null;
  const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let ms = 0;
  for (let i = 0; i < 10; i++) {
    const ch = ulidStr[i].toUpperCase();
    const val = CROCKFORD.indexOf(ch);
    if (val < 0) return null;
    ms = ms * 32 + val;
  }
  const date = new Date(ms);
  return isNaN(date.getTime()) ? null : date;
}

/**
 * Parse the occurrence instant Date from an occurrence key.
 *
 * @param {string} occurrence
 * @param {Date} fallback
 * @returns {Date}
 */
export function parseInstantFromOccurrence(occurrence, fallback) {
  if (typeof occurrence !== 'string') return fallback;

  const atIndex = occurrence.lastIndexOf('@');
  if (atIndex >= 0) {
    let tail = occurrence.slice(atIndex + 1);
    if (tail.endsWith('.json')) tail = tail.slice(0, -5);

    if (tail.startsWith('manual:') || tail.startsWith('manual~')) {
      const ulidStr = tail.slice(7);
      const d = ulidToDate(ulidStr);
      if (d) return d;
    } else {
      const d = new Date(tail);
      if (!isNaN(d.getTime())) return d;
    }
  }

  const direct = new Date(occurrence);
  if (!isNaN(direct.getTime())) return direct;

  return fallback;
}

/**
 * Query previous successful execution timestamp from sched_history_v1 view.
 *
 * @param {string} stateDir
 * @param {string} workflowId
 * @returns {string} ISO timestamp or empty string
 */
export function queryPreviousSuccess(stateDir, workflowId) {
  if (!stateDir) return '';
  const dbPath = join(stateDir, 'orchestrator.sqlite');
  try {
    if (!existsSync(dbPath)) return '';
    const db = new DatabaseSync(dbPath, { readOnly: true });
    try {
      // The floor's view (DESIGN 5.4, fork migration to schema 12): a run that
      // succeeded is state 'done'; it ended at its attempt's ended_at, or at
      // updated_at when the check held at census and no attempt ran.
      const row = db.prepare(
        "SELECT max(coalesce(ended_at, updated_at)) AS at FROM sched_history_v1 WHERE workflow = ? AND state = 'done'"
      ).get(workflowId);
      return row && row.at ? String(row.at) : '';
    } finally {
      db.close();
    }
  } catch {
    return '';
  }
}

/**
 * Build the SCHED_* environment map per DESIGN 5.2 and C2.13.
 *
 * @param {object} ctx
 * @param {{ id: string, agency: string, root: string, stem: string }} target
 * @param {object} parsedValue - The parsed workflow object (from validateFile)
 * @param {{ occurrence: string, attempt: string | number }} opts
 * @returns {Record<string, string>}
 */
export function buildSchedEnv(ctx, target, parsedValue, { occurrence, attempt }) {
  const occurrenceStr = String(occurrence || '');
  const attemptStr = String(attempt ?? 1);

  const isManual =
    occurrenceStr.includes('@manual') ||
    occurrenceStr.includes(':manual') ||
    occurrenceStr.includes('manual~');
  const kind = isManual ? 'manual' : 'schedule';

  const now = ctx.now ? ctx.now() : new Date();
  const instant = parseInstantFromOccurrence(occurrenceStr, now);

  const tz = parsedValue?.on?.schedule?.[0]?.timezone || 'UTC';
  const localDate = formatLocalDate(instant, tz);

  // SCHED_NIGHT: local date of instant minus 12 hours in workflow's timezone
  const minus12h = new Date(instant.getTime() - 12 * 60 * 60 * 1000);
  const night = formatLocalDate(minus12h, tz);

  const prevSuccess = queryPreviousSuccess(ctx.stateDir, target.id);

  // The fork's `bin/floor` as the floor profile installs it (DESIGN 9.2, 7.6
  // `floor upkeep`), not this CLI: floor-upkeep runs "$SCHED_FLOOR_CLI" upkeep.
  const floorCli =
    ctx?.env?.SCHEDULED_FLOOR_CLI ??
    join(ctx?.home ?? process.env.HOME ?? '/home/tom', '.dsh', 'profiles', 'floor', 'node_modules', 'dsh-superagent', 'bin', 'floor');

  return {
    SCHED_WORKFLOW: target.id,
    SCHED_AGENCY: target.agency,
    SCHED_KIND: kind,
    SCHED_OCCURRENCE: occurrenceStr,
    SCHED_SCHEDULED_AT: instant.toISOString(),
    SCHED_TIMEZONE: tz,
    SCHED_LOCAL_DATE: localDate,
    SCHED_NIGHT: night,
    SCHED_ATTEMPT: attemptStr,
    SCHED_PREVIOUS_SUCCESS_AT: prevSuccess,
    SCHED_FLOOR_CLI: floorCli,
  };
}

/**
 * Format the last 4 KiB (4096 bytes) of a buffer as UTF-8 text.
 *
 * @param {Buffer} buf
 * @returns {string}
 */
export function formatLast4KiB(buf) {
  if (!buf || buf.length === 0) return '';
  const max = 4096;
  const slice = buf.length > max ? buf.subarray(buf.length - max) : buf;
  return new TextDecoder('utf-8', { fatal: false }).decode(slice);
}

/**
 * Run a Command per C2.14 sandbox rules:
 * - cwd the agency root
 * - stdin /dev/null
 * - exact environment: PATH, LANG, TZ, plus SCHED_* map
 * - timeout killing the whole process group
 *
 * @param {object} ctx
 * @param {string[] | { sh: string | string[] }} commandSpec
 * @param {{ cwd?: string, schedEnv?: Record<string, string>, timeoutMs?: number }} [opts]
 * @returns {Promise<{ exitCode: number | null, signal: string | null, timedOut: boolean, output: string }>}
 */
export function runCommand(ctx, commandSpec, { cwd, schedEnv, timeoutMs } = {}) {
  return new Promise((resolve) => {
    let file;
    let args;

    if (Array.isArray(commandSpec)) {
      if (commandSpec.length === 0) {
        return resolve({ exitCode: 1, signal: null, timedOut: false, output: '' });
      }
      file = commandSpec[0];
      args = commandSpec.slice(1);
    } else if (commandSpec && typeof commandSpec === 'object' && 'sh' in commandSpec) {
      file = ctx?.env?.SCHEDULED_SH ?? '/bin/sh';
      const lines = Array.isArray(commandSpec.sh)
        ? commandSpec.sh.join('\n')
        : String(commandSpec.sh ?? '');
      args = ['-c', lines];
    } else {
      return resolve({ exitCode: 1, signal: null, timedOut: false, output: '' });
    }

    const effectiveTimeout =
      timeoutMs ??
      (parseInt(ctx?.env?.SCHEDULED_COMMAND_TIMEOUT_MS, 10) || 60000);

    const childEnv = {
      PATH:
        ctx?.env?.SCHEDULED_PATH ??
        process.env.SCHEDULED_PATH ??
        '/run/current-system/sw/bin:/etc/profiles/per-user/tom/bin',
      LANG: 'C.UTF-8',
      TZ: schedEnv?.SCHED_TIMEZONE ?? 'UTC',
      ...(schedEnv || {}),
    };

    let child;
    try {
      child = spawn(file, args, {
        cwd: cwd || process.cwd(),
        stdio: ['ignore', 'pipe', 'pipe'],
        detached: true,
        env: childEnv,
      });
    } catch (err) {
      return resolve({
        exitCode: 127,
        signal: null,
        timedOut: false,
        output: err.message,
      });
    }

    const chunks = [];
    child.stdout.on('data', (d) => chunks.push(d));
    child.stderr.on('data', (d) => chunks.push(d));

    let timedOut = false;
    let timer = null;

    if (effectiveTimeout > 0) {
      timer = setTimeout(() => {
        timedOut = true;
        try {
          process.kill(-child.pid, 'SIGKILL');
        } catch {
          try {
            child.kill('SIGKILL');
          } catch {}
        }
      }, effectiveTimeout);
    }

    child.on('error', (err) => {
      if (timer) clearTimeout(timer);
      const combined = Buffer.concat(chunks);
      const output = formatLast4KiB(combined);
      resolve({
        exitCode: 1,
        signal: null,
        timedOut,
        output: output || err.message,
      });
    });

    child.on('close', (code, signal) => {
      if (timer) clearTimeout(timer);
      const combined = Buffer.concat(chunks);
      const output = formatLast4KiB(combined);
      resolve({ exitCode: code, signal, timedOut, output });
    });
  });
}
