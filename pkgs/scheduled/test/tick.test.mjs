// tick.test.mjs — scheduled tick v2 (docs/scheduled.md, A tick; rows T1-T13, plus C3.1-C3.7, C3.9, C3.12).
// Run: cd pkgs/scheduled && node --test 'test/*.test.mjs'

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { tick } from '../src/lib/tick.mjs';
import { main as tickMain } from '../src/verbs/tick.mjs';
import { setupEnv, hourly, MACHINE_ID } from './helpers.mjs';

const at = (iso) => new Date(iso);

test('T1 a first tick writes heartbeat.json and intake.json in the state dir, no record, and calls no dshd', async () => {
  const env = setupEnv({ floorInstance: 'floor' });
  try {
    env.item('hb', hourly());
    const res = await tick(env.ctx, { now: at('2026-11-12T14:00:00.000Z') });
    assert.equal(res.code, 0);
    const hb = JSON.parse(fs.readFileSync(join(env.state, 'heartbeat.json'), 'utf8'));
    assert.deepEqual(hb, { v: 1, machineId: MACHINE_ID, lastTick: '2026-11-12T14:00:00.000Z' });
    assert.equal(env.intake().v, 1);
    assert.equal(env.entry('master:hb').valid, true);
    assert.deepEqual(env.records(), []);
    assert.equal(fs.existsSync(env.inbox), false, 'the inbox is created only to hand off a record');
    assert.deepEqual(env.dshdCalls(), []);
  } finally {
    env.cleanup();
  }
});

test('T2 an hourly item and a lastTick 3 hours old link exactly one record: latest instant, missed 2, revision, frozen text, cwd the agency realpath, namespace, by scheduled-heartbeat', async () => {
  const env = setupEnv();
  try {
    env.item('example-hourly', hourly({ name: 'Example hourly', job: { prompt: ['Line one.', 'Line two.'] } }));
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    const res = await tick(env.ctx, { now: at('2026-11-12T14:00:30.000Z') });
    assert.equal(res.code, 0);
    assert.deepEqual(env.records(), ['master~example-hourly@20261112T1400Z.json']);
    const rec = env.record('master~example-hourly@20261112T1400Z.json');
    assert.deepEqual(rec, {
      v: 1,
      kind: 'schedule',
      namespace: 'master',
      item: 'example-hourly',
      name: 'Example hourly',
      cwd: env.home,
      file: join(env.scheduled, 'example-hourly.jsonc'),
      due: '2026-11-12T14:00:00.000Z',
      missed: 2,
      revision: env.entry('master:example-hourly').revision,
      text: 'Line one.\nLine two.',
      by: 'scheduled-heartbeat',
      at: '2026-11-12T14:00:30.000Z',
    });
    assert.match(rec.revision, /^[0-9a-f]{12}$/);
    assert.ok(res.lines.includes('<6>decode item=master:example-hourly due=2026-11-12T14:00:00.000Z result=created'), res.lines.join('\n'));
  } finally {
    env.cleanup();
  }
});

test('T3 the same window ticked again answers exists, both while the record waits in the inbox and after it moved to .done/', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    const made = env.records();
    assert.equal(made.length, 1);

    // The same window again: the deterministic name exists.
    env.heartbeat('2026-11-12T11:00:00.000Z');
    let res = await tick(env.ctx, { now: at('2026-11-12T12:00:20.000Z') });
    assert.ok(res.lines.some((l) => l.endsWith('result=exists')), res.lines.join('\n'));
    assert.deepEqual(env.records(), made);

    // The Source received it: the name in .done/ still answers exists, and nothing new waits.
    env.drain();
    env.heartbeat('2026-11-12T11:00:00.000Z');
    res = await tick(env.ctx, { now: at('2026-11-12T12:00:30.000Z') });
    assert.equal(res.code, 0);
    assert.ok(res.lines.some((l) => l.endsWith('result=exists')), res.lines.join('\n'));
    assert.deepEqual(env.records(), []);
  } finally {
    env.cleanup();
  }
});

test('T4 a clock earlier than lastTick writes no record, keeps lastTick, logs <4>clock went back and exits 0', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    env.heartbeat('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now: at('2026-11-12T10:00:00.000Z') });
    assert.equal(res.code, 0);
    assert.ok(res.lines.includes('<4>clock went back'));
    assert.deepEqual(env.records(), []);
    assert.equal(JSON.parse(fs.readFileSync(join(env.state, 'heartbeat.json'), 'utf8')).lastTick, '2026-11-12T14:00:00.000Z');
  } finally {
    env.cleanup();
  }
});

test('T5 a heartbeat.json of another machine or a higher major v exits 1 and writes nothing', async () => {
  for (const state of [{ v: 1, machineId: 'another', lastTick: '2026-11-12T10:00:00.000Z' }, { v: 2, machineId: MACHINE_ID, lastTick: '2026-11-12T10:00:00.000Z' }]) {
    const env = setupEnv();
    try {
      env.item('hb', hourly());
      fs.mkdirSync(env.state, { recursive: true });
      fs.writeFileSync(join(env.state, 'heartbeat.json'), JSON.stringify(state));
      const res = await tick(env.ctx, { now: at('2026-11-12T14:00:00.000Z') });
      assert.equal(res.code, 1);
      assert.ok(res.lines.some((l) => l.startsWith('<3>guard ')), res.lines.join('\n'));
      assert.equal(fs.existsSync(env.inbox), false);
      assert.equal(fs.existsSync(join(env.state, 'intake.json')), false);
      assert.deepEqual(JSON.parse(fs.readFileSync(join(env.state, 'heartbeat.json'), 'utf8')), state);
    } finally {
      env.cleanup();
    }
  }
});

test('T6 two ticks started together: the second waits on .tick.lock', async () => {
  const env = setupEnv();
  try {
    fs.mkdirSync(env.state, { recursive: true });
    const lockFile = join(env.state, '.tick.lock');
    fs.writeFileSync(lockFile, `${process.pid}\n`);
    let done = false;
    const pending = tick(env.ctx, { now: at('2026-11-12T14:00:00.000Z') }).then((r) => { done = true; return r; });
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(done, false, 'the tick waits for the lock');
    fs.unlinkSync(lockFile);
    const res = await pending;
    assert.equal(res.code, 0);
    assert.ok(res.lines.some((l) => l.startsWith('<6>pass ')));
  } finally {
    env.cleanup();
  }
});

test('T7 a disabled item gets no record; an item disabled while its record waits and the floor is stopped has that record withdrawn with <5>withdrawn reason=disabled', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'running' } });
  try {
    env.item('off', hourly({ enabled: false }));
    env.item('hb', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    assert.deepEqual(env.records(), ['master~hb@20261112T1200Z.json']);

    env.item('hb', hourly({ enabled: false }), new Date('2026-11-12T12:10:00.000Z'));
    env.setStub({ state: 'stopped', enabled: false, lastRun: { ending: 'stopped' } });
    const res = await tick(env.ctx, { now: at('2026-11-12T12:30:00.000Z') });
    assert.equal(res.code, 0);
    assert.deepEqual(env.records(), []);
    assert.ok(res.lines.includes('<5>withdrawn occurrence=master~hb@20261112T1200Z reason=disabled'), res.lines.join('\n'));
    // Nothing waits after the withdrawal, so the floor is not started.
    assert.ok(!env.dshdCalls().some((argv) => argv[0] === 'start'));
  } finally {
    env.cleanup();
  }
});

test('T8 a removed or invalid item has its waiting heartbeat record withdrawn; a manual record and another producer\'s record stay', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'running' } });
  try {
    env.item('gone', hourly());
    env.item('broken', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    assert.equal(env.records().length, 2);
    const manual = { v: 1, kind: 'manual', namespace: 'master', item: 'gone', cwd: env.home, file: join(env.scheduled, 'gone.jsonc'),
      due: '2026-11-12T12:01:00.000Z', run: '01KE6Q3W8ZJ4S7T2V9XN5R0B1C', missed: 0, revision: 'a1b2c3d4e5f6', text: 'Say ok.', by: 'scheduled-run', at: '2026-11-12T12:01:00.000Z' };
    const other = { ...manual, kind: 'schedule', run: undefined, by: 'another-scheduler', due: '2026-11-12T12:00:00.000Z' };
    fs.writeFileSync(join(env.inbox, 'master~gone@run~01KE6Q3W8ZJ4S7T2V9XN5R0B1C.json'), JSON.stringify(manual));
    fs.writeFileSync(join(env.inbox, 'other~gone@20261112T1200Z.json'), JSON.stringify(other));
    fs.writeFileSync(join(env.inbox, 'unreadable.json'), '{ torn');

    fs.rmSync(join(env.scheduled, 'gone.jsonc'));
    env.item('broken', '{ "enabled": true,', new Date('2026-11-12T12:10:00.000Z'));
    env.setStub({ state: 'stopped', lastRun: { ending: 'stopped' } });
    const res = await tick(env.ctx, { now: at('2026-11-12T12:30:00.000Z') });
    assert.ok(res.lines.includes('<5>withdrawn occurrence=master~gone@20261112T1200Z reason=removed'), res.lines.join('\n'));
    assert.ok(res.lines.includes('<5>withdrawn occurrence=master~broken@20261112T1200Z reason=invalid'), res.lines.join('\n'));
    assert.deepEqual(env.records(), ['master~gone@run~01KE6Q3W8ZJ4S7T2V9XN5R0B1C.json', 'other~gone@20261112T1200Z.json', 'unreadable.json']);
  } finally {
    env.cleanup();
  }
});

test('T8b while the floor is running no record is withdrawn', async () => {
  for (const state of ['running', 'starting', 'stopping']) {
    const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'running' } });
    try {
      env.item('hb', hourly());
      await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
      await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
      env.item('hb', hourly({ enabled: false }), new Date('2026-11-12T12:10:00.000Z'));
      env.setStub({ state });
      const res = await tick(env.ctx, { now: at('2026-11-12T12:30:00.000Z') });
      assert.equal(res.code, 0);
      assert.deepEqual(env.records(), ['master~hb@20261112T1200Z.json'], state);
      assert.ok(!res.lines.some((l) => l.includes('withdrawn')), state);
    } finally {
      env.cleanup();
    }
  }
});

test('T9 an edit between two occurrences: the second record carries the new text and revision; the first record\'s file is unchanged', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly({ job: { prompt: 'First text.' } }));
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    const [first] = env.records();
    const firstBytes = fs.readFileSync(join(env.inbox, first));

    env.item('hb', hourly({ job: { prompt: 'Second text.' } }), new Date('2026-11-12T12:20:00.000Z'));
    await tick(env.ctx, { now: at('2026-11-12T13:00:10.000Z') });
    const names = env.records();
    assert.equal(names.length, 2);
    const second = env.record(names[1]);
    assert.equal(second.text, 'Second text.');
    assert.notEqual(second.revision, JSON.parse(firstBytes).revision);
    assert.deepEqual(fs.readFileSync(join(env.inbox, first)), firstBytes);
    assert.equal(JSON.parse(firstBytes).text, 'First text.');
  } finally {
    env.cleanup();
  }
});

test('T9b a prompt-file is read at each tick and frozen into the record', async () => {
  const env = setupEnv();
  try {
    fs.mkdirSync(join(env.agency, 'prompts'), { recursive: true });
    const prompt = join(env.agency, 'prompts', 'hb.md');
    fs.writeFileSync(prompt, 'From the file, first.\n');
    env.item('hb', { enabled: true, on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] }, job: { 'prompt-file': '.agency/prompts/hb.md' } });
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    // Only the prompt file changes; the item file's stat is the same.
    fs.writeFileSync(prompt, 'From the file, second.\n');
    await tick(env.ctx, { now: at('2026-11-12T13:00:10.000Z') });
    const texts = env.records().map((n) => env.record(n).text);
    assert.deepEqual(texts, ['From the file, first.\n', 'From the file, second.\n']);
  } finally {
    env.cleanup();
  }
});

test('T10 an item enabled now does not fire instants before it was armed', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly({ enabled: false }));
    await tick(env.ctx, { now: at('2026-11-12T09:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T11:30:00.000Z') });
    env.item('hb', hourly(), new Date('2026-11-12T11:40:00.000Z'));
    // Armed at 11:40, when the file was written: the 10:00 and 11:00 instants never fire.
    await tick(env.ctx, { now: at('2026-11-12T11:45:00.000Z') });
    assert.deepEqual(env.records(), []);
    assert.equal(env.entry('master:hb').armedSince, '2026-11-12T11:40:00.000Z');
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    assert.deepEqual(env.records(), ['master~hb@20261112T1200Z.json']);
    assert.equal(env.record('master~hb@20261112T1200Z.json').missed, 0);
  } finally {
    env.cleanup();
  }
});

test('T10 with only the hourly timer, an item enabled at 11:40 fires 12:00 at the 12:00 tick, not 13:00', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly({ enabled: false }));
    await tick(env.ctx, { now: at('2026-11-12T11:00:05.000Z') });
    env.item('hb', hourly(), new Date('2026-11-12T11:40:00.000Z'));
    await tick(env.ctx, { now: at('2026-11-12T12:00:05.000Z') });
    assert.deepEqual(env.records(), ['master~hb@20261112T1200Z.json']);
    assert.equal(env.record('master~hb@20261112T1200Z.json').missed, 0);
    // A file stamped before the last tick (a copy that kept its mtime) is armed now, as before.
    env.item('old', hourly(), new Date('2026-11-01T00:00:00.000Z'));
    await tick(env.ctx, { now: at('2026-11-12T13:00:05.000Z') });
    assert.equal(env.entry('master:old').armedSince, '2026-11-12T13:00:05.000Z');
    assert.deepEqual(env.records().filter((n) => n.startsWith('master~old@')), []);
  } finally {
    env.cleanup();
  }
});

test('T11 a tick opens no file named orchestrator.sqlite, runs no dshd run and no item command, and writes no census', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'stopped', lastRun: { ending: 'stopped' } } });
  try {
    const marker = join(env.tmpDir, 'command-ran');
    // A withdrawn key naming a command is refused, never run.
    env.item('gated', hourly({ if: { command: ['touch', marker] }, outcome: { check: ['touch', marker] } }));
    env.item('hb', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    const res = await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    assert.equal(res.code, 0);
    assert.equal(fs.existsSync(marker), false);
    const all = fs.readdirSync(env.tmpDir, { recursive: true }).map(String);
    assert.ok(!all.some((p) => p.endsWith('orchestrator.sqlite')), all.join('\n'));
    assert.ok(!all.some((p) => p.includes('census')), all.join('\n'));
    const calls = env.dshdCalls();
    assert.ok(calls.length > 0, 'the stopped floor was read and started');
    for (const argv of calls) assert.ok(['get', 'start'].includes(argv[0]), argv.join(' '));
    assert.ok(env.entry('master:gated').problems.some((p) => p.code === 'removed-key'));
  } finally {
    env.cleanup();
  }
});

test('T12 every file the tick creates in the inbox is a *.json linked from .tmp/, mode 0600; the inbox and .tmp are 0700', async () => {
  const env = setupEnv();
  try {
    env.item('a', hourly());
    env.item('b', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    const mode = (p) => fs.statSync(p).mode & 0o777;
    assert.equal(mode(env.inbox), 0o700);
    assert.equal(mode(join(env.inbox, '.tmp')), 0o700);
    assert.deepEqual(fs.readdirSync(join(env.inbox, '.tmp')), []);
    const names = fs.readdirSync(env.inbox).filter((n) => n !== '.tmp');
    assert.deepEqual(names.sort(), ['master~a@20261112T1200Z.json', 'master~b@20261112T1200Z.json']);
    for (const n of names) {
      assert.equal(mode(join(env.inbox, n)), 0o600);
      assert.equal(fs.statSync(join(env.inbox, n)).nlink, 1, 'the temp link is gone');
    }
  } finally {
    env.cleanup();
  }
});

test('T13 --inbox missing exits 2 with the message', async () => {
  const env = setupEnv();
  try {
    const code = await tickMain(['--now', '2026-11-12T14:00:00.000Z'], { ...env.ctx, inbox: null });
    assert.equal(code, 2);
    assert.ok(env.err.join('').includes('scheduled: --inbox is required'), env.err.join(''));
    assert.equal(fs.existsSync(env.state), false);
  } finally {
    env.cleanup();
  }
});

test('T13b --now without an explicit --state-dir exits 2 and writes nothing (review SCHED-3)', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    const code = await tickMain(['--now', '2026-12-01T00:00:00.000Z'], env.ctx);
    assert.equal(code, 2);
    assert.ok(env.err.join('').includes('--now needs an explicit --state-dir'), env.err.join(''));
    assert.equal(fs.existsSync(env.state), false);
    assert.deepEqual(env.records(), []);
  } finally {
    env.cleanup();
  }
});

test('T14 a tick sweeps temporary files over an hour old from the inbox .tmp/ and the state dir, and keeps fresh ones (review SCHED-8)', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    const tmp = join(env.inbox, '.tmp');
    fs.mkdirSync(tmp, { recursive: true, mode: 0o700 });
    const old = new Date(Date.now() - 2 * 3600 * 1000);
    const stale = [join(tmp, 'master~hb@20261112T1000Z.json.4242.a1b2c3'), join(env.state, '.tick.lock.4242.tmp'), join(env.state, '.heartbeat.json.4242.tmp')];
    for (const p of stale) { fs.writeFileSync(p, 'x'); fs.utimesSync(p, old, old); }
    const fresh = join(tmp, 'master~hb@20261112T1100Z.json.4343.d4e5f6');
    fs.writeFileSync(fresh, 'x');
    await tick(env.ctx, { now: at('2026-11-12T11:30:00.000Z') });
    for (const p of stale) assert.equal(fs.existsSync(p), false, p);
    assert.equal(fs.existsSync(fresh), true);
    assert.deepEqual(fs.readdirSync(env.state).sort(), ['heartbeat.json', 'intake.json']);
  } finally {
    env.cleanup();
  }
});

test('C3.12 every tick line carries an sd-daemon level prefix; pass carries reason, items and waiting', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    env.ctx.env.TRIGGER_UNIT = 'scheduled-heartbeat.timer';
    await tick(env.ctx, { now: at('2026-11-12T11:00:00.000Z') });
    const res = await tick(env.ctx, { now: at('2026-11-12T12:00:10.000Z') });
    for (const line of res.lines) assert.match(line, /^<[3-6]>[a-z]/, line);
    assert.match(res.lines.at(-1), /^<6>pass reason=timer took_ms=\d+ discover_ms=\d+ agencies=1 items=1 waiting=1$/);
    delete env.ctx.env.TRIGGER_UNIT;
    const again = await tick(env.ctx, { now: at('2026-11-12T12:10:00.000Z') });
    assert.match(again.lines.at(-1), /^<6>pass reason=manual /);
  } finally {
    env.cleanup();
  }
});

test('the verb takes --inbox, --state-dir, --home and --floor-instance flags over the environment defaults', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    const other = join(env.tmpDir, 'other-inbox');
    const state = join(env.tmpDir, 'other-state');
    const args = ['--inbox', other, '--state-dir', state, '--home', env.home];
    assert.equal(await tickMain([...args, '--now', '2026-11-12T11:00:00.000Z'], env.ctx), 0);
    assert.equal(await tickMain([...args, '--now=2026-11-12T12:00:10.000Z', '--json'], env.ctx), 0);
    assert.deepEqual(fs.readdirSync(other).filter((n) => n.endsWith('.json')), ['master~hb@20261112T1200Z.json']);
    assert.ok(fs.existsSync(join(state, 'heartbeat.json')));
    assert.equal(fs.existsSync(env.state), false);
    assert.equal(JSON.parse(env.out.at(-1)).code, 0);
    assert.equal(await tickMain(['--inbox', other, '--bogus'], env.ctx), 2);
  } finally {
    env.cleanup();
  }
});
