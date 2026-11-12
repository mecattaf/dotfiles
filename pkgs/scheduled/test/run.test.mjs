// run.test.mjs — scheduled run (scheduled-jsonc §5, §8 R1-R4).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { main as runMain } from '../src/verbs/run.mjs';
import { setupEnv, hourly } from './helpers.mjs';

test('R1 run on a missing item exits 1 and writes no record', async () => {
  const env = setupEnv({ floorInstance: 'floor' });
  try {
    assert.equal(await runMain(['master:nope'], env.ctx), 1);
    assert.equal(fs.existsSync(env.inbox), false);
    assert.deepEqual(env.dshdCalls(), []);
    // An invalid item is refused too.
    env.item('broken', '{ "on": {} }');
    assert.equal(await runMain(['master:broken'], env.ctx), 1);
    assert.deepEqual(env.records(), []);
  } finally {
    env.cleanup();
  }
});

test('R2 run on a disabled item writes one manual record with a ULID and wakes a stopped floor once', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'stopped', enabled: false, lastRun: { ending: 'stopped' } } });
  try {
    env.item('probe-ready', { name: 'Probe', enabled: false, on: { schedule: [{ cron: '0 4 * * *', timezone: 'Europe/Paris' }] }, job: { prompt: 'Reply READY and end.' } });
    const code = await runMain(['master:probe-ready', '--json'], env.ctx);
    assert.equal(code, 0, env.err.join(''));
    const [name] = env.records();
    assert.match(name, /^master~probe-ready@run~[0-9A-HJKMNP-TV-Z]{26}\.json$/);
    const rec = env.record(name);
    assert.equal(rec.kind, 'manual');
    assert.equal(rec.run, name.slice('master~probe-ready@run~'.length, -'.json'.length));
    assert.equal(rec.missed, 0);
    assert.equal(rec.by, 'scheduled-run');
    assert.equal(rec.name, 'Probe');
    assert.equal(rec.cwd, env.home);
    assert.equal(rec.text, 'Reply READY and end.');
    assert.equal(rec.due, '2026-11-12T14:00:00.000Z');
    const out = JSON.parse(env.out.join(''));
    assert.equal(out.occurrence, name.slice(0, -'.json'.length));
    assert.equal(out.file, join(env.inbox, name));
    assert.equal(out.floor, 'floor action=start state=stopped waiting=1 result=started');
    assert.deepEqual(env.dshdCalls(), [['get', '--json', 'floor'], ['start', '--json', 'floor']]);
  } finally {
    env.cleanup();
  }
});

test('R3 run against a running floor writes the record and starts nothing', async () => {
  const env = setupEnv({ floorInstance: 'floor', stubState: { state: 'running' } });
  try {
    env.item('hb', hourly());
    assert.equal(await runMain(['hb'], env.ctx), 0);
    assert.equal(env.records().length, 1);
    assert.deepEqual(env.dshdCalls(), [['get', '--json', 'floor']]);
  } finally {
    env.cleanup();
  }
});

test('R4 two runs of one item write two records with different run ids', async () => {
  const env = setupEnv();
  try {
    env.item('hb', hourly());
    assert.equal(await runMain(['master:hb'], env.ctx), 0);
    assert.equal(await runMain(['master:hb'], env.ctx), 0);
    const runs = env.records().map((n) => env.record(n).run);
    assert.equal(runs.length, 2);
    assert.notEqual(runs[0], runs[1]);
    // No floor instance: no dshd at all.
    assert.deepEqual(env.dshdCalls(), []);
  } finally {
    env.cleanup();
  }
});

test('run takes --home, --inbox and --floor-instance; --inbox missing exits 2; a not-found floor exits 1 with the record written', async () => {
  const env = setupEnv({ stubState: null });
  try {
    const other = join(env.tmpDir, 'rehearsal');
    fs.mkdirSync(join(other, '.agency', 'scheduled'), { recursive: true, mode: 0o700 });
    fs.chmodSync(join(other, '.agency'), 0o700);
    fs.writeFileSync(join(other, '.agency', 'scheduled', 'probe-ready.jsonc'), JSON.stringify(hourly({ enabled: false })), { mode: 0o600 });
    const inbox = join(env.tmpDir, 'inbox');
    assert.equal(await runMain(['master:probe-ready', '--home', other], { ...env.ctx, inbox: null }), 2);
    const code = await runMain(['master:probe-ready', '--home', other, '--inbox', inbox, '--floor-instance', 'rehearsal'], env.ctx);
    assert.equal(code, 1);
    const names = fs.readdirSync(inbox).filter((n) => n.endsWith('.json'));
    assert.equal(names.length, 1);
    assert.equal(JSON.parse(fs.readFileSync(join(inbox, names[0]), 'utf8')).cwd, other);
    assert.deepEqual(env.dshdCalls(), [['get', '--json', 'rehearsal']]);
  } finally {
    env.cleanup();
  }
});
