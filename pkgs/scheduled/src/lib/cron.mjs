/**
 * Cron decoding through @deepseek-ai/dsh-util-time.
 * Exports: scheduleProblems, instantsBetween, nextInstants
 */

import { Cron } from '@deepseek-ai/dsh-util-time';

// 14-day density search window in ms
const DENSITY_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
// 400-day DST-gap search window (cover all upcoming spring-forward transitions)
const DST_GAP_WINDOW_MS = 400 * 24 * 60 * 60 * 1000;
const MIN_GAP_MS = 60 * 60 * 1000; // 60 minutes

/**
 * Parse one schedule entry {cron, timezone} into a Cron instance or problems.
 * Returns { cron: Cron|null, problems: Problem[] }
 */
function parseEntry(entry, entryIndex) {
  const problems = [];
  const { cron: expr, timezone } = entry;

  if (!timezone || typeof timezone !== 'string') {
    problems.push({
      severity: 'error',
      code: 'timezone',
      entryIndex,
      line: 0, col: 0,
      message: 'Each schedule entry must have a "timezone" field.',
    });
    return { cron: null, problems };
  }

  const result = Cron.parse(expr, timezone);
  if (result.kind === 'rejected') {
    if (result.reason === 'time_zone') {
      problems.push({
        severity: 'error',
        code: 'timezone',
        entryIndex,
        line: 0, col: 0,
        message: `Invalid timezone "${timezone}": ${result.detail}`,
      });
    } else {
      problems.push({
        severity: 'error',
        code: 'cron',
        entryIndex,
        line: 0, col: 0,
        message: `Invalid cron expression "${expr}": ${result.detail}`,
      });
    }
    return { cron: null, problems };
  }

  return { cron: result.rule, problems };
}

/**
 * Collect up to maxCount occurrences within the density window.
 */
function collectOccurrences(cron, fromMs, windowMs, maxCount = 500) {
  const endMs = fromMs + windowMs;
  const result = [];
  let cur = fromMs;
  while (result.length < maxCount) {
    const next = cron.next(cur);
    if (!next) break;
    const ms = new Date(next).getTime();
    if (ms >= endMs) break;
    result.push(ms);
    cur = ms;
  }
  return result;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** `YYYY-MM-DDTHH:MM` wall-clock minute of `ms` in `timeZone`. */
function wallMinute(ms, timeZone) {
  const parts = {};
  for (const { type, value } of new Intl.DateTimeFormat('en-CA', {
    timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  }).formatToParts(ms)) parts[type] = value;
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

/**
 * Whether `cron` in `timeZone` skips a wall time the expression names. The same expression in UTC lists the wall
 * times it names, with no DST; one missing from the zone's own list fell in a spring-forward gap. A fall-back
 * overlap gives a wall time once (the earlier instant), which is not a skip.
 */
function skipsWallTime(expr, timeZone, occurrences) {
  if (occurrences.length < 2) return false;
  const utc = Cron.parse(expr, 'UTC');
  if (utc.kind !== 'accepted') return false;
  const first = occurrences[0];
  const last = occurrences[occurrences.length - 1];
  const local = new Set(occurrences.map((ms) => wallMinute(ms, timeZone)));
  // A zone is at most 14 h from UTC: wall times a day inside the window's ends are covered by both lists.
  for (const ms of collectOccurrences(utc.rule, first + DAY_MS, last - first - 2 * DAY_MS, 20000)) {
    if (!local.has(new Date(ms).toISOString().slice(0, 16))) return true;
  }
  return false;
}

/**
 * Check a list of parsed crons for density and never problems.
 * entries: array of {cron, timezone} objects (already validated for parse errors).
 * Returns problems with entryIndex instead of line/col.
 * @param {{ now?: Date|number }} [opts] the clock the checks start from (default: the wall clock)
 */
export function scheduleProblems(entries, { now: nowOpt } = {}) {
  const problems = [];
  const now = nowOpt === undefined ? Date.now() : new Date(nowOpt).getTime();

  // Parse all entries, collect parse-level problems
  const parsedEntries = [];
  for (let i = 0; i < entries.length; i++) {
    const { cron, problems: entryProbs } = parseEntry(entries[i], i);
    for (const p of entryProbs) problems.push(p);
    parsedEntries.push(cron);
  }

  // For each valid cron, check never and dst-gap
  for (let i = 0; i < parsedEntries.length; i++) {
    const cron = parsedEntries[i];
    if (!cron) continue;

    // Check never: does it fire within library horizon?
    const firstNext = cron.next(now);
    if (!firstNext) {
      problems.push({
        severity: 'error',
        code: 'never',
        entryIndex: i,
        line: 0, col: 0,
        message: `Schedule entry ${i} has no occurrence within the search horizon (e.g. "0 0 31 2 *" never fires).`,
      });
      continue;
    }

    // dst-gap: a wall time the expression names that the zone skips (spring-forward gap) in a 400-day window.
    // Compared by wall-clock minute, not by gap length: a weekday or irregular schedule has uneven gaps and
    // no skip (review SCHED-4).
    const dstOccurrences = collectOccurrences(cron, now, DST_GAP_WINDOW_MS, 2000);
    if (dstOccurrences.length >= 3) {
      if (skipsWallTime(entries[i].cron, entries[i].timezone, dstOccurrences)) {
        problems.push({
          severity: 'warning',
          code: 'dst-gap',
          entryIndex: i,
          line: 0, col: 0,
          message: `Schedule entry ${i}: a spring-forward DST gap skips one occurrence in the schedule horizon.`,
        });
      }
    }
  }

  // Cross-entry density check: all valid crons combined, check < 60 min gaps
  if (parsedEntries.some(c => c !== null)) {
    const allOccurrences = [];
    for (let i = 0; i < parsedEntries.length; i++) {
      const cron = parsedEntries[i];
      if (!cron) continue;
      const occ = collectOccurrences(cron, now, DENSITY_WINDOW_MS);
      for (const ms of occ) allOccurrences.push({ ms, entryIndex: i });
    }
    allOccurrences.sort((a, b) => a.ms - b.ms);

    for (let j = 1; j < allOccurrences.length; j++) {
      const gap = allOccurrences[j].ms - allOccurrences[j - 1].ms;
      if (gap < MIN_GAP_MS) {
        // Find if this involves two different entries or same entry repeating fast
        const prevIdx = allOccurrences[j - 1].entryIndex;
        const curIdx = allOccurrences[j].entryIndex;
        // Report density for the later entry (or first one if same)
        const reportIdx = curIdx !== prevIdx ? curIdx : curIdx;
        problems.push({
          severity: 'error',
          code: 'density',
          entryIndex: reportIdx,
          line: 0, col: 0,
          message: `Two schedule occurrences are only ${Math.round(gap / 60000)} minute(s) apart (minimum is 60 minutes).`,
        });
        break; // Report once per item
      }
    }
  }

  return problems;
}

/**
 * Collect all instants from the given entries that fall in (fromExclusive, toInclusive].
 * Returns sorted unique Date[].
 */
export function instantsBetween(entries, fromExclusive, toInclusive) {
  const fromMs = fromExclusive.getTime();
  const toMs = toInclusive.getTime();
  const seen = new Set();

  for (const entry of entries) {
    const result = Cron.parse(entry.cron, entry.timezone);
    if (result.kind !== 'accepted') continue;
    const cron = result.rule;

    let cur = fromMs;
    while (true) {
      const next = cron.next(cur);
      if (!next) break;
      const ms = new Date(next).getTime();
      if (ms > toMs) break;
      seen.add(ms);
      cur = ms;
    }
  }

  return Array.from(seen)
    .sort((a, b) => a - b)
    .map(ms => new Date(ms));
}

/**
 * Compute the next n instants from the given entries, starting strictly after `from`.
 * Returns sorted unique Date[].
 */
export function nextInstants(entries, from, n) {
  const fromMs = from.getTime();
  const all = [];

  for (const entry of entries) {
    const result = Cron.parse(entry.cron, entry.timezone);
    if (result.kind !== 'accepted') continue;
    const cron = result.rule;

    let cur = fromMs;
    let count = 0;
    while (count < n * 2 + 10) { // over-collect then trim
      const next = cron.next(cur);
      if (!next) break;
      const ms = new Date(next).getTime();
      all.push(ms);
      cur = ms;
      count++;
    }
  }

  // Deduplicate and sort
  const unique = Array.from(new Set(all)).sort((a, b) => a - b);
  return unique.slice(0, n).map(ms => new Date(ms));
}
