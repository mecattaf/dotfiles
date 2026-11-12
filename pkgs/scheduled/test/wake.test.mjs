// wake.test.mjs — the wake table (docs/scheduled.md, A tick, step 6; rows W1-W10): one test per row, then the stub dshd.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { wake, floorState } from '../src/lib/floor.mjs';
import { tick } from '../src/lib/tick.mjs';
import { setupEnv, hourly } from './helpers.mjs';
import { SAMPLE_FAILED_STATE } from './stub-dshd.mjs';

/** A fake dshd: `get` answers `getAnswer`, `start` answers `startAnswer`; every argv is kept. */
function fake({ get = { code: 0, stdout: JSON.stringify({ state: 'running' }) }, start = { code: 0, stdout: JSON.stringify({ outcome: 'started' }) } } = {}) {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    const answer = argv[0] === 'get' ? get : argv[0] === 'start' ? start : { code: 0, stdout: '' };
    return { stderr: '', ...answer };
  };
  return { run, calls };
}
const state = (s, extra = {}) => ({ code: 0, stdout: JSON.stringify({ state: s, ...extra }) });

test('W1 without --floor-instance no dshd command runs, whatever waits', async () => {
  const f = fake();
  const res = await wake({ instance: null, waiting: 5, floor: null, run: f.run });
  assert.deepEqual(res, { lines: [], fault: false, action: 'none' });
  assert.deepEqual(f.calls, []);
});

test('W2 with nothing waiting no dshd command runs', async () => {
  const f = fake({ get: state('stopped', { lastRun: { ending: 'stopped' } }) });
  const res = await wake({ instance: 'floor', waiting: 0, floor: null, run: f.run });
  assert.equal(res.fault, false);
  assert.deepEqual(f.calls, []);
});

test('W3 running, starting or stopping with records waiting: no start, exit 0', async () => {
  for (const s of ['running', 'starting', 'stopping']) {
    const f = fake({ get: state(s) });
    const res = await wake({ instance: 'floor', waiting: 2, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [`<6>floor state=${s} waiting=2`], fault: false, action: 'none' });
    assert.deepEqual(f.calls, [['get', '--json', 'floor']]);
  }
});

test('W4 stopped by intent with a record waiting: dshd start --json NAME, <5> line, exit 0', async () => {
  const f = fake({ get: state('stopped', { enabled: false, lastRun: { ending: 'stopped' } }) });
  const res = await wake({ instance: 'floor', waiting: 1, floor: null, run: f.run });
  assert.deepEqual(res, { lines: ['<5>floor action=start state=stopped waiting=1 result=started'], fault: false, action: 'start' });
  assert.deepEqual(f.calls, [['get', '--json', 'floor'], ['start', '--json', 'floor']]);
});

test('W5 previous-boot and interrupted with a record waiting: start', async () => {
  for (const s of ['previous-boot', 'interrupted']) {
    const f = fake({ get: state(s), start: { code: 0, stdout: JSON.stringify({ outcome: 'already-running' }) } });
    const res = await wake({ instance: 'floor', waiting: 3, floor: null, run: f.run });
    assert.deepEqual(res.lines, [`<5>floor action=start state=${s} waiting=3 result=already-running`]);
    assert.equal(res.fault, false);
    assert.deepEqual(f.calls.at(-1), ['start', '--json', 'floor']);
  }
});

test('W6 failed with a record waiting: start, <3> line with child exit or signal, exit 1', async () => {
  let f = fake({ get: { code: 0, stdout: JSON.stringify(SAMPLE_FAILED_STATE) } });
  let res = await wake({ instance: 'floor', waiting: 1, floor: null, run: f.run });
  assert.deepEqual(res, { lines: ['<3>floor action=start state=failed child=exit:1 result=started'], fault: true, action: 'start' });
  f = fake({ get: state('failed', { lastRun: { child: { signal: 'SIGKILL' } } }) });
  res = await wake({ instance: 'floor', waiting: 1, floor: null, run: f.run });
  assert.equal(res.lines[0], '<3>floor action=start state=failed child=signal:SIGKILL result=started');
});

test('W7 masked: no start, <4>floor masked, exit 0', async () => {
  const f = fake({ get: state('masked') });
  const res = await wake({ instance: 'floor', waiting: 4, floor: null, run: f.run });
  assert.deepEqual(res, { lines: ['<4>floor masked waiting=4'], fault: false, action: 'none' });
  assert.ok(!f.calls.some((a) => a[0] === 'start'));
});

test('W8 not-found, orphaned, inconsistent and exit 7: no start, <3> line, exit 1', async () => {
  const cases = [
    [{ code: 3, stdout: '', stderr: 'floor not found' }, '<3>floor state=not-found waiting=1'],
    [state('orphaned', { remedy: 'dshd rm --orphan floor' }), '<3>floor state=orphaned remedy="dshd rm --orphan floor" waiting=1'],
    [state('inconsistent'), '<3>floor state=inconsistent waiting=1'],
    [{ code: 7, stdout: JSON.stringify({ error: 'systemd-unavailable' }), stderr: '' }, '<3>floor state=unavailable error=systemd-unavailable waiting=1'],
  ];
  for (const [get, line] of cases) {
    const f = fake({ get });
    const res = await wake({ instance: 'floor', waiting: 1, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [line], fault: true, action: 'none' });
    assert.ok(!f.calls.some((a) => a[0] === 'start'));
  }
});

test('W9 a failed start (result failed or non-zero exit) gives <3> and exit 1', async () => {
  for (const start of [{ code: 0, stdout: JSON.stringify({ outcome: 'failed' }) }, { code: 1, stdout: 'not json' }]) {
    const f = fake({ get: state('stopped'), start });
    const res = await wake({ instance: 'floor', waiting: 1, floor: null, run: f.run });
    assert.deepEqual(res, { lines: ['<3>floor action=start state=stopped waiting=1 result=failed'], fault: true, action: 'start' });
  }
});

test('W10 no tick ever runs dshd update or reads the floor\'s HTTP API', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'running', release: { state: 'outdated' } } });
  const realFetch = globalThis.fetch;
  let fetched = 0;
  globalThis.fetch = async () => { fetched += 1; throw new Error('no HTTP'); };
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    for (const now of ['2026-11-12T12:00:10.000Z', '2026-11-12T13:00:10.000Z']) {
      const res = await tick(env.ctx, { now: new Date(now) });
      assert.equal(res.code, 0);
    }
    assert.equal(fetched, 0);
    const calls = env.dshdCalls();
    assert.ok(calls.length >= 2);
    for (const argv of calls) assert.deepEqual(argv, ['get', '--json', 'floor']);
  } finally {
    globalThis.fetch = realFetch;
    env.cleanup();
  }
});

test('floorState reads dshd get once through the stub dshd', async () => {
  const env = setupEnv({ stubState: { state: 'previous-boot' } });
  try {
    const { dshdRunner } = await import('../src/lib/floor.mjs');
    const run = dshdRunner(env.ctx.dshd, { ...process.env, ...env.ctx.env });
    assert.equal((await floorState('floor', run)).state, 'previous-boot');
    env.setStub(null);
    assert.equal((await floorState('floor', run)).state, 'not-found');
    assert.deepEqual(env.dshdCalls(), [['get', '--json', 'floor'], ['get', '--json', 'floor']]);
  } finally {
    env.cleanup();
  }
});

test('a tick with a record waiting and a stopped floor starts it through the stub dshd; one without records reads nothing', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'stopped', lastRun: { ending: 'stopped' } } });
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    assert.deepEqual(env.dshdCalls(), []);
    const res = await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.equal(res.code, 0);
    assert.ok(res.lines.includes('<5>floor action=start state=stopped waiting=1 result=started'), res.lines.join('\n'));
    assert.deepEqual(env.dshdCalls(), [['get', '--json', 'floor'], ['start', '--json', 'floor']]);
    fs.rmSync(join(env.inbox, env.records()[0]));
    env.setStub(null);
    const quiet = await tick(env.ctx, { now: new Date('2026-11-12T12:30:00.000Z') });
    assert.equal(quiet.code, 0, 'a floor that is not found is not read while nothing waits');
    assert.equal(env.dshdCalls().length, 2);
  } finally {
    env.cleanup();
  }
});
