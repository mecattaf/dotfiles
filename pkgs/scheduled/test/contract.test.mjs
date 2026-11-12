// contract.test.mjs — the record this side writes is the fork's occurrence record v1 (scheduled-jsonc §8 C1).
// test/fixtures/occurrence-v1.json is byte-identical to the fork's tests/fixtures/scheduled-occurrence-v1.json.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { tick } from '../src/lib/tick.mjs';
import { main as runMain } from '../src/verbs/run.mjs';
import { setupEnv, hourly } from './helpers.mjs';

const FIXTURE = JSON.parse(fs.readFileSync(fileURLToPath(new URL('./fixtures/occurrence-v1.json', import.meta.url)), 'utf8'));
// `pair` is a record field this side never writes: work runs on the floor's default pair.
const shape = (record) => Object.fromEntries(Object.entries(record).filter(([k]) => k !== 'pair').map(([k, v]) => [k, typeof v]).sort());
const fixtureOf = (kind) => FIXTURE.find((r) => r.kind === kind);

test('C1 a tick\'s record and a run\'s record have exactly the field set and types of test/fixtures/occurrence-v1.json', async () => {
  assert.ok(Array.isArray(FIXTURE) && fixtureOf('schedule') && fixtureOf('manual'), 'the fixture holds one schedule and one manual record');
  const env = setupEnv();
  try {
    const named = (kind) => ('name' in fixtureOf(kind) ? { name: 'Contract item' } : {});
    env.item('sched', hourly(named('schedule')));
    env.item('manual', hourly({ enabled: false, ...named('manual') }));
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.equal(await runMain(['master:manual'], env.ctx), 0);
    const records = env.records().map((n) => env.record(n));
    const schedule = records.find((r) => r.kind === 'schedule');
    const manual = records.find((r) => r.kind === 'manual');
    assert.deepEqual(shape(schedule), shape(fixtureOf('schedule')));
    assert.deepEqual(shape(manual), shape(fixtureOf('manual')));
    // And in the fixture's field order, so a record reads the same in both repositories.
    const order = (r) => Object.keys(r).filter((k) => k !== 'pair');
    assert.deepEqual(order(schedule), order(fixtureOf('schedule')));
    assert.deepEqual(order(manual), order(fixtureOf('manual')));
    for (const r of [schedule, manual]) {
      assert.equal(r.v, 1);
      assert.match(r.item, /^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/);
      assert.match(r.namespace, /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/);
      assert.match(r.revision, /^[0-9a-f]{12}$/);
      assert.match(r.cwd, /^\//);
      for (const t of [r.due, r.at]) assert.equal(new Date(t).toISOString(), t);
    }
    assert.match(manual.run, /^[0-9A-HJKMNP-TV-Z]{26}$/);
    assert.equal('run' in schedule, false);
  } finally {
    env.cleanup();
  }
});
