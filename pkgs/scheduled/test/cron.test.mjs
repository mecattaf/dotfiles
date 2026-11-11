/**
 * test/cron.test.mjs
 * Tests for cron decoding, instantsBetween, nextInstants, and scheduleProblems.
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { scheduleProblems, instantsBetween, nextInstants } from '../src/lib/cron.mjs';

// ─── Basic cron parsing ───────────────────────────────────────────────────────

test('scheduleProblems: valid entry has no problems', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }];
  const problems = scheduleProblems(entries);
  // May have dst-gap warning, but no errors
  const errors = problems.filter(p => p.severity === 'error');
  assert.equal(errors.length, 0, `Unexpected errors: ${JSON.stringify(errors)}`);
});

test('scheduleProblems: missing timezone → error timezone', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: '' }];
  const problems = scheduleProblems(entries);
  const e = problems.find(p => p.code === 'timezone');
  assert.ok(e, 'Expected timezone error');
  assert.equal(e.severity, 'error');
});

test('scheduleProblems: invalid timezone → error timezone', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: 'Bogus/Zone' }];
  const problems = scheduleProblems(entries);
  const e = problems.find(p => p.code === 'timezone');
  assert.ok(e, 'Expected timezone error');
});

test('scheduleProblems: 0 0 31 2 * → error never', () => {
  const entries = [{ cron: '0 0 31 2 *', timezone: 'UTC' }];
  const problems = scheduleProblems(entries);
  const e = problems.find(p => p.code === 'never');
  assert.ok(e, 'Expected never error');
  assert.equal(e.severity, 'error');
  assert.equal(e.entryIndex, 0);
});

test('scheduleProblems: two entries < 60 min apart → error density', () => {
  // 0 * * * * and 30 * * * * are 30 min apart every hour
  const entries = [
    { cron: '0 * * * *', timezone: 'UTC' },
    { cron: '30 * * * *', timezone: 'UTC' },
  ];
  const problems = scheduleProblems(entries);
  const e = problems.find(p => p.code === 'density');
  assert.ok(e, 'Expected density error');
  assert.equal(e.severity, 'error');
});

// ─── C2.3: Specific cron expressions ─────────────────────────────────────────

test('C2.3: cron 0 0 31 2 * never fires (Feb 31 does not exist)', () => {
  const entries = [{ cron: '0 0 31 2 *', timezone: 'UTC' }];
  const problems = scheduleProblems(entries);
  assert.ok(problems.some(p => p.code === 'never'), 'Expected never error');
});

test('C2.3: density - 0 * * * * and 30 * * * * → density error', () => {
  const entries = [
    { cron: '0 * * * *', timezone: 'UTC' },
    { cron: '30 * * * *', timezone: 'UTC' },
  ];
  const problems = scheduleProblems(entries);
  assert.ok(problems.some(p => p.code === 'density'), 'Expected density error');
});

// ─── C2.5: DST gap ───────────────────────────────────────────────────────────

test('C2.5: 30 2 * * * in Europe/Paris → warning dst-gap', () => {
  const entries = [{ cron: '30 2 * * *', timezone: 'Europe/Paris' }];
  const problems = scheduleProblems(entries);
  const w = problems.find(p => p.code === 'dst-gap');
  assert.ok(w, `Expected dst-gap warning, got: ${JSON.stringify(problems)}`);
  assert.equal(w.severity, 'warning');
});

test('C2.5: nextInstants from 2027-03-27T12:00:00Z gives 2027-03-29T00:30:00.000Z first', () => {
  const entries = [{ cron: '30 2 * * *', timezone: 'Europe/Paris' }];
  const from = new Date('2027-03-27T12:00:00Z');
  const instants = nextInstants(entries, from, 1);
  assert.equal(instants.length, 1);
  assert.equal(instants[0].toISOString(), '2027-03-29T00:30:00.000Z',
    `Expected 2027-03-29T00:30:00.000Z (spring-forward skips March 28), got: ${instants[0].toISOString()}`);
});

// ─── instantsBetween ─────────────────────────────────────────────────────────

test('instantsBetween returns sorted unique dates in range', () => {
  const entries = [{ cron: '0 12 * * 1', timezone: 'UTC' }]; // Every Monday noon
  const from = new Date('2026-11-01T00:00:00Z');
  const to = new Date('2026-11-30T23:59:59Z');
  const instants = instantsBetween(entries, from, to);
  assert.ok(instants.length > 0, 'Expected some Mondays in November');
  // All should be on Monday
  for (const d of instants) {
    assert.equal(d.getUTCDay(), 1, `Expected Monday, got ${d.getUTCDay()} for ${d.toISOString()}`);
    assert.ok(d > from && d <= to, `Date ${d.toISOString()} not in range`);
  }
  // Should be sorted
  for (let i = 1; i < instants.length; i++) {
    assert.ok(instants[i] > instants[i - 1], 'Should be sorted ascending');
  }
});

test('instantsBetween: empty when no occurrences in range', () => {
  const entries = [{ cron: '0 0 31 2 *', timezone: 'UTC' }]; // never fires
  const from = new Date('2026-01-01T00:00:00Z');
  const to = new Date('2026-12-31T23:59:59Z');
  const instants = instantsBetween(entries, from, to);
  assert.equal(instants.length, 0);
});

test('instantsBetween: deduplicates overlapping entries', () => {
  // Same cron twice - should deduplicate
  const entries = [
    { cron: '0 12 * * 1', timezone: 'UTC' },
    { cron: '0 12 * * 1', timezone: 'UTC' },
  ];
  const from = new Date('2026-11-01T00:00:00Z');
  const to = new Date('2026-11-30T23:59:59Z');
  const instants1 = instantsBetween([entries[0]], from, to);
  const instants2 = instantsBetween(entries, from, to);
  assert.equal(instants1.length, instants2.length, 'Should deduplicate identical occurrences');
});

// ─── nextInstants ─────────────────────────────────────────────────────────────

test('nextInstants returns n sorted unique future instants', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: 'UTC' }]; // Weekly Monday 6am
  const from = new Date('2026-11-01T00:00:00Z');
  const instants = nextInstants(entries, from, 3);
  assert.equal(instants.length, 3);
  // All should be on Mondays at 6am UTC
  for (const d of instants) {
    assert.equal(d.getUTCDay(), 1);
    assert.equal(d.getUTCHours(), 6);
    assert.ok(d > from, 'Should be strictly after from');
  }
  // Sorted
  for (let i = 1; i < instants.length; i++) {
    assert.ok(instants[i] > instants[i - 1]);
  }
});

test('nextInstants: multiple entries merged and sorted', () => {
  const entries = [
    { cron: '0 6 * * 1', timezone: 'UTC' },
    { cron: '0 18 * * 3', timezone: 'UTC' }, // Wednesday 6pm
  ];
  const from = new Date('2026-11-01T00:00:00Z');
  const instants = nextInstants(entries, from, 4);
  assert.equal(instants.length, 4);
  // Sorted
  for (let i = 1; i < instants.length; i++) {
    assert.ok(instants[i] > instants[i - 1], 'Should be sorted ascending');
  }
});

// ─── Edge cases ───────────────────────────────────────────────────────────────

test('scheduleProblems: UTC timezone is valid', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: 'UTC' }];
  const problems = scheduleProblems(entries);
  const errors = problems.filter(p => p.severity === 'error');
  assert.equal(errors.length, 0, JSON.stringify(errors));
});

test('scheduleProblems: single entry that fires regularly has no density error', () => {
  const entries = [{ cron: '0 6 * * 1', timezone: 'UTC' }]; // Once a week
  const problems = scheduleProblems(entries);
  assert.ok(!problems.some(p => p.code === 'density'), 'Should not have density error');
});

test('scheduleProblems: entryIndex is correct on errors', () => {
  const entries = [
    { cron: '0 6 * * 1', timezone: 'UTC' }, // valid
    { cron: '0 0 31 2 *', timezone: 'UTC' }, // never
  ];
  const problems = scheduleProblems(entries);
  const e = problems.find(p => p.code === 'never');
  assert.ok(e, 'Expected never error');
  assert.equal(e.entryIndex, 1, 'entryIndex should be 1 for second entry');
});
