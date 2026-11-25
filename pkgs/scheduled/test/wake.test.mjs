// wake.test.mjs — the wake table (docs/scheduled.md, A tick, step 6; rows W1-W10): one test per row, then the
// stub systemctl and a real spawn.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { wake, floorState, unitRunner, parseShow, validUnitName, PROPERTIES } from '../src/lib/floor.mjs';
import { tick } from '../src/lib/tick.mjs';
import { setupEnv, hourly, UNIT } from './helpers.mjs';
import { UNIT_STATES } from './stub-systemctl.mjs';

const SHOW = ['--user', 'show', `--property=${PROPERTIES.join(',')}`, '--', UNIT];
const START = ['--user', 'start', '--no-block', '--', UNIT];

/** `systemctl show` text for named state `name`, or for raw properties. */
const showText = (p) => Object.entries(typeof p === 'string' ? UNIT_STATES[p] : p).map(([k, v]) => `${k}=${v}`).join('\n') + '\n';
const shows = (p) => ({ code: 0, stdout: showText(p) });

/** A fake systemctl: `show` answers `show`, `start` answers `start`; every argv is kept. */
function fake({ show = shows('running'), start = { code: 0, stdout: '' } } = {}) {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    const answer = argv[1] === 'show' ? show : argv[1] === 'start' ? start : { code: 1, stdout: '', stderr: 'not offered' };
    return { stderr: '', ...answer };
  };
  return { run, calls };
}

test('W1 without a floor unit no systemctl command runs, whatever waits', async () => {
  const f = fake();
  for (const unit of [null, undefined, '']) {
    const res = await wake({ unit, waiting: 5, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [], fault: false, action: 'none' });
  }
  assert.deepEqual(f.calls, []);
});

test('W2 with nothing waiting no systemctl command runs', async () => {
  const f = fake({ show: shows('stopped') });
  const res = await wake({ unit: UNIT, waiting: 0, floor: null, run: f.run });
  assert.equal(res.fault, false);
  assert.deepEqual(f.calls, []);
});

test('W3 active, activating or deactivating with records waiting: no start, <6> line, exit 0', async () => {
  for (const [name, s] of [['running', 'running'], ['starting', 'starting'], ['stopping', 'stopping']]) {
    const f = fake({ show: shows(name) });
    const res = await wake({ unit: UNIT, waiting: 2, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [`<6>floor state=${s} waiting=2`], fault: false, action: 'none' });
    assert.deepEqual(f.calls, [SHOW]);
  }
});

test('W4 inactive with a record waiting: systemctl --user start --no-block UNIT, <5> line with the unit, exit 0', async () => {
  const f = fake({ show: shows('stopped') });
  const res = await wake({ unit: UNIT, waiting: 1, floor: null, run: f.run });
  assert.deepEqual(res, { lines: [`<5>floor action=start unit=${UNIT} state=stopped waiting=1 result=queued`], fault: false, action: 'start' });
  assert.deepEqual(f.calls, [SHOW, START]);
});

test('W5 reloading and auto-restart read as live; a unit still active after its file vanished is running, not not-found', async () => {
  for (const [p, s] of [['reloading', 'running'], ['auto-restart', 'starting'],
    [{ ...UNIT_STATES.running, LoadState: 'not-found' }, 'running'], [{ ...UNIT_STATES.running, ActiveState: 'refreshing' }, 'running']]) {
    const f = fake({ show: shows(p) });
    const res = await wake({ unit: UNIT, waiting: 3, floor: null, run: f.run });
    assert.deepEqual(res.lines, [`<6>floor state=${s} waiting=3`]);
    assert.equal(res.fault, false);
    assert.deepEqual(f.calls, [SHOW]);
  }
});

test('W6 failed with a record waiting: start, <3> line with the main process\'s exit, signal or result, exit 1', async () => {
  for (const [p, child] of [['failed', 'exit:1'], ['killed', 'signal:9'], ['timed-out', 'result:timeout'],
    [{ ...UNIT_STATES.failed, Result: 'start-limit-hit', ExecMainStatus: '' }, 'result:start-limit-hit']]) {
    const f = fake({ show: shows(p) });
    const res = await wake({ unit: UNIT, waiting: 1, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [`<3>floor action=start unit=${UNIT} state=failed child=${child} result=queued`], fault: true, action: 'start' });
    assert.deepEqual(f.calls, [SHOW, START]);
  }
});

test('W7 masked: no start, <4>floor masked, exit 0', async () => {
  const f = fake({ show: shows('masked') });
  const res = await wake({ unit: UNIT, waiting: 4, floor: null, run: f.run });
  assert.deepEqual(res, { lines: ['<4>floor masked waiting=4'], fault: false, action: 'none' });
  assert.deepEqual(f.calls, [SHOW]);
});

test('W8 not-found, a unit that failed to load, an unknown state, a systemctl that fails or answers nothing: no start, <3> line, exit 1', async () => {
  const cases = [
    [shows('not-found'), '<3>floor state=not-found waiting=1'],
    [shows('bad-setting'), `<3>floor state=bad-setting remedy="systemctl --user status ${UNIT}" waiting=1`],
    [shows({ ...UNIT_STATES.stopped, ActiveState: 'maintenance' }), `<3>floor state=maintenance remedy="systemctl --user status ${UNIT}" waiting=1`],
    [{ code: 1, stdout: '', stderr: 'Failed to connect to user scope bus via local transport: No such file or directory\n' },
      '<3>floor state=unavailable error="Failed to connect to user scope bus via local transport: No such file or directory" waiting=1'],
    [{ code: 1, stdout: '', stderr: '' }, '<3>floor state=unavailable error=exit:1 waiting=1'],
    [{ code: 0, stdout: 'garbage\n', stderr: '' }, '<3>floor state=unavailable error=invalid-output waiting=1'],
  ];
  for (const [show, line] of cases) {
    const f = fake({ show });
    const res = await wake({ unit: UNIT, waiting: 1, floor: null, run: f.run });
    assert.deepEqual(res, { lines: [line], fault: true, action: 'none' });
    assert.deepEqual(f.calls, [SHOW]);
  }
});

test('W8b a unit name that is not a full unit name is refused before systemctl runs', async () => {
  for (const unit of ['floor', '-floor.service', 'flo*.service', '/home', 'a b.service', 'floor.mount', 'x'.repeat(250) + '.service']) {
    const f = fake();
    const res = await wake({ unit, waiting: 1, floor: null, run: f.run });
    assert.deepEqual(res, { lines: ['<3>floor state=unavailable error=invalid-unit-name waiting=1'], fault: true, action: 'none' }, unit);
    assert.deepEqual(f.calls, [], unit);
  }
  for (const unit of ['factory-floor.service', 'floor-stub.service', 'dsh@floor.service', 'floor.target', 'a\\x2db.service']) assert.ok(validUnitName(unit), unit);
});

test('W9 a failed start (non-zero exit) gives <3> with systemctl\'s error and exit 1', async () => {
  const f = fake({ show: shows('stopped'), start: { code: 5, stdout: '', stderr: 'Failed to start floor.service: Unit floor.service is masked.\n' } });
  const res = await wake({ unit: UNIT, waiting: 1, floor: null, run: f.run });
  assert.deepEqual(res, { lines: [`<3>floor action=start unit=${UNIT} state=stopped waiting=1 result=failed error="Failed to start floor.service: Unit floor.service is masked."`], fault: true, action: 'start' });
  const g = fake({ show: shows('failed'), start: { code: 1, stdout: '', stderr: '' } });
  const res2 = await wake({ unit: UNIT, waiting: 1, floor: null, run: g.run });
  assert.deepEqual(res2.lines, [`<3>floor action=start unit=${UNIT} state=failed child=exit:1 result=failed error=exit:1`]);
});

test('W10 no tick runs anything but show and start --no-block, and none reads the floor\'s HTTP API', async () => {
  const env = setupEnv({ floorUnit: UNIT, stubState: { state: 'running' } });
  const realFetch = globalThis.fetch;
  let fetched = 0;
  globalThis.fetch = async () => { fetched += 1; throw new Error('no HTTP'); };
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    for (const [now, state] of [['2026-11-12T12:00:10.000Z', 'running'], ['2026-11-12T13:00:10.000Z', 'failed'], ['2026-11-12T14:00:10.000Z', 'stopped']]) {
      env.setStub({ state });
      await tick(env.ctx, { now: new Date(now) });
    }
    assert.equal(fetched, 0);
    const calls = env.systemctlCalls();
    assert.ok(calls.length >= 3);
    for (const argv of calls) assert.ok([JSON.stringify(SHOW), JSON.stringify(START)].includes(JSON.stringify(argv)), argv.join(' '));
    assert.equal(calls.filter((a) => a[1] === 'start').length, 2, 'started once when failed, once when stopped');
  } finally {
    globalThis.fetch = realFetch;
    env.cleanup();
  }
});

test('parseShow reads KEY=VALUE lines and keeps an = inside a value', () => {
  assert.deepEqual(parseShow('LoadState=loaded\nActiveState=active\n\nX=a=b\n'), { LoadState: 'loaded', ActiveState: 'active', X: 'a=b' });
});

test('floorState reads the unit through the stub systemctl, which answers an unknown unit as not-found', async () => {
  const env = setupEnv({ stubState: { state: 'stopped' } });
  try {
    const run = unitRunner(env.ctx.systemctl, { ...process.env, ...env.ctx.env });
    const read = await floorState(UNIT, run);
    assert.equal(read.state, 'stopped');
    assert.equal(read.info.SubState, 'dead');
    env.setStub(null);
    assert.equal((await floorState(UNIT, run)).state, 'not-found');
    env.setStub({ show: { code: 1, stderr: 'Failed to connect to bus: No medium found' } });
    assert.deepEqual(await floorState(UNIT, run), { state: 'unavailable', info: null, error: 'Failed to connect to bus: No medium found' });
    assert.deepEqual(env.systemctlCalls(), [SHOW, SHOW, SHOW]);
  } finally {
    env.cleanup();
  }
});

test('a systemctl that cannot be spawned reads as unavailable with the spawn error', async () => {
  const read = await floorState(UNIT, unitRunner('/nonexistent/systemctl'));
  assert.equal(read.state, 'unavailable');
  assert.match(read.error, /ENOENT/);
});

test('a tick with a record waiting and a stopped floor starts it through the stub systemctl; one without records reads nothing', async () => {
  const env = setupEnv({ floorUnit: UNIT, stubState: { state: 'stopped' } });
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    assert.deepEqual(env.systemctlCalls(), []);
    const res = await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.equal(res.code, 0);
    assert.ok(res.lines.includes(`<5>floor action=start unit=${UNIT} state=stopped waiting=1 result=queued`), res.lines.join('\n'));
    assert.deepEqual(env.systemctlCalls(), [SHOW, START]);
    fs.rmSync(join(env.inbox, env.records()[0]));
    env.setStub(null);
    const quiet = await tick(env.ctx, { now: new Date('2026-11-12T12:30:00.000Z') });
    assert.equal(quiet.code, 0, 'a floor that is not found is not read while nothing waits');
    assert.equal(env.systemctlCalls().length, 2);
  } finally {
    env.cleanup();
  }
});

test('a tick whose floor unit is not found keeps the record, logs <3> and exits 1', async () => {
  const env = setupEnv({ floorUnit: 'missing.service', stubState: null });
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    const res = await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.equal(res.code, 1);
    assert.ok(res.lines.includes('<3>floor state=not-found waiting=1'), res.lines.join('\n'));
    assert.deepEqual(env.records(), ['master~hb@20261112T1200Z.json']);
    assert.ok(!env.systemctlCalls().some((a) => a[1] === 'start'));
  } finally {
    env.cleanup();
  }
});
