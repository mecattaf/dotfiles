// ingest.test.mjs — intake and its cache in intake.json: C3.4 first sight and young files, C3.8 one line per
// event (ports ingest.test.mjs:302, :333 and :366 of the donor, which encode real failures).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { tick } from '../src/lib/tick.mjs';
import { setupEnv, hourly } from './helpers.mjs';

const at = (iso) => new Date(iso);

test('C3.4 an item first seen in a pass: no instant before first sight is due (written 13:58 with cron 0 13 * * *, nothing at 14:00)', async () => {
  const env = setupEnv();
  try {
    env.heartbeat('2026-11-12T12:00:00.000Z');
    env.item('afternoon', hourly({ on: { schedule: [{ cron: '0 13 * * *', timezone: 'UTC' }] } }), at('2026-11-12T13:58:00.000Z'));
    const res = await tick(env.ctx, { now: at('2026-11-12T14:00:00.000Z') });
    assert.equal(res.code, 0);
    assert.deepEqual(env.records(), []);
    assert.equal(env.entry('master:afternoon').armedSince, '2026-11-12T14:00:00.000Z');
  } finally {
    env.cleanup();
  }
});

test('C3.4 a file younger than 2 seconds gives warning young and the previous parse is used', async () => {
  const env = setupEnv();
  try {
    env.item('debounced', hourly({ job: { prompt: 'Original prompt' } }), at('2026-11-12T11:59:50.000Z'));
    await tick(env.ctx, { now: at('2026-11-12T12:00:00.000Z') });
    env.item('debounced', hourly({ enabled: false, job: { prompt: 'Modified prompt' } }), at('2026-11-12T12:59:59.500Z'));
    const res = await tick(env.ctx, { now: at('2026-11-12T13:00:00.000Z') });
    assert.equal(res.code, 0);
    const entry = env.entry('master:debounced');
    assert.ok(entry.problems.some((p) => p.code === 'young' && p.severity === 'warning'));
    assert.equal(entry.enabled, true);
    // The occurrence is handed off with the previous text, not the half-written one.
    assert.deepEqual(env.records().map((n) => env.record(n).text), ['Original prompt']);
  } finally {
    env.cleanup();
  }
});

test('C3.8 one invalid revision present over two passes gives exactly one <4>invalid line', async () => {
  const env = setupEnv();
  try {
    env.item('broken', '{ "enabled": true, "on": ');
    const r1 = await tick(env.ctx, { now: at('2026-11-12T12:00:00.000Z') });
    const r2 = await tick(env.ctx, { now: at('2026-11-12T13:00:00.000Z') });
    const invalid = [...r1.lines, ...r2.lines].filter((l) => l.startsWith('<4>invalid'));
    assert.equal(invalid.length, 1, [...r1.lines, ...r2.lines].join('\n'));
    assert.match(invalid[0], /^<4>invalid item=master:broken rev=[0-9a-f]{12} at=\d+:\d+$/);
    assert.equal(r2.code, 0);
    assert.equal(env.entry('master:broken').valid, false);
  } finally {
    env.cleanup();
  }
});

test('C3.8 an agency seen for the first time gives exactly one <5>new-agency line', async () => {
  const env = setupEnv();
  try {
    const r1 = await tick(env.ctx, { now: at('2026-11-12T12:00:00.000Z') });
    const r2 = await tick(env.ctx, { now: at('2026-11-12T13:00:00.000Z') });
    const lines = [...r1.lines, ...r2.lines].filter((l) => l.startsWith('<5>new-agency'));
    assert.deepEqual(lines, [`<5>new-agency agency=master root=${env.home}`]);
  } finally {
    env.cleanup();
  }
});

test('C3.4 a file whose mtime is hours ahead of the clock (the clock went back after the edit) is parsed, not held as young', async () => {
  const env = setupEnv();
  try {
    env.item('ahead', hourly(), at('2026-11-12T18:00:00.000Z'));
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T12:00:00.000Z') })).code, 0);
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T15:00:30.000Z') })).code, 0);
    const entry = env.entry('master:ahead');
    assert.equal(entry.enabled, true);
    assert.ok(!entry.problems.some((p) => p.code === 'young'));
    assert.deepEqual(env.records().map((n) => env.record(n).missed), [2]);
  } finally {
    env.cleanup();
  }
});

test('C3.4 a file first seen while younger than 2 s is parsed at the next pass, not kept as a placeholder (evaluation review)', async () => {
  const env = setupEnv();
  try {
    env.item('fresh', hourly(), at('2026-11-12T12:00:00.000Z'));
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T12:00:00.500Z') })).code, 0);
    assert.ok(env.entry('master:fresh').problems.some((p) => p.code === 'young'));
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T12:30:00.000Z') })).code, 0);
    const entry = env.entry('master:fresh');
    assert.equal(entry.valid, true);
    assert.equal(entry.enabled, true);
    assert.match(entry.revision, /^[0-9a-f]{12}$/);
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T13:00:30.000Z') })).code, 0);
    assert.equal(env.records().length, 1);
  } finally {
    env.cleanup();
  }
});

test('C3.8 a stat error other than ENOENT keeps the item in intake with its previous parse, and its waiting record is not withdrawn (Zen #2)', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'stopped', lastRun: { ending: 'stopped' } } });
  try {
    env.item('kept', hourly(), at('2026-11-12T11:00:00.000Z'));
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T11:30:00.000Z') })).code, 0);
    env.setStub({ state: 'masked' });
    assert.equal((await tick(env.ctx, { now: at('2026-11-12T12:00:30.000Z') })).code, 0);
    assert.equal(env.records().length, 1);
    // The directory loses its search bit: names still list, stat fails with EACCES.
    fs.chmodSync(env.scheduled, 0o600);
    let res;
    try {
      res = await tick(env.ctx, { now: at('2026-11-12T12:30:30.000Z') });
    } finally {
      fs.chmodSync(env.scheduled, 0o700);
    }
    assert.equal(res.code, 0, res.lines.join('\n'));
    const entry = env.entry('master:kept');
    assert.ok(entry, 'the item is still in intake');
    assert.equal(entry.enabled, true);
    assert.ok(entry.problems.some((p) => p.code === 'stat' && p.severity === 'warning'));
    assert.equal(env.records().length, 1, 'not withdrawn');
  } finally {
    env.cleanup();
  }
});

test('intake.json and heartbeat.json live in the state dir, never in the superagent stateDir', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    assert.deepEqual(fs.readdirSync(env.state).sort(), ['heartbeat.json', 'intake.json']);
    // The inbox's parent (the superagent's stateDir) holds only the inbox.
    assert.deepEqual(fs.readdirSync(join(env.agency, 'state', 'master')), ['inbox']);
  } finally {
    env.cleanup();
  }
});
