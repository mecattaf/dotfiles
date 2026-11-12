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

/**
 * Check a list of parsed crons for density and never problems.
 * entries: array of {cron, timezone} objects (already validated for parse errors).
 * Returns problems with entryIndex instead of line/col.
 */
export function scheduleProblems(entries) {
  const problems = [];
  const now = Date.now();

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

    // dst-gap: detect skipped occurrences (spring-forward gap) in a 400-day window
    // If any two consecutive occurrences have a gap > minGap + 1h, a DST gap was skipped.
    const dstOccurrences = collectOccurrences(cron, now, DST_GAP_WINDOW_MS, 2000);
    if (dstOccurrences.length >= 3) {
      // Real-time gaps between consecutive fires move by an hour around each
      // DST change (23 h / 25 h for a daily cron), which is not a skip. A
      // skipped fire shows as a gap well above the usual one: more than 1.5
      // times the median gap (48 h for a daily cron, 14 days for a weekly).
      const gaps = [];
      for (let j = 1; j < dstOccurrences.length; j++) gaps.push(dstOccurrences[j] - dstOccurrences[j - 1]);
      const sorted = [...gaps].sort((a, b) => a - b);
      const median = sorted[Math.floor(sorted.length / 2)];
      if (gaps.some(g => g > median * 1.5)) {
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
