// scheduled run (DESIGN 10.1 run, 5.3 manual spool file; claims C2.9, C9.1).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { main as runVerb } from '../src/verbs/run.mjs';

function setup({ floorState = 'stopped' } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'scheduled-run-'));
  fs.chmodSync(root, 0o700);
  const wf = path.join(root, '.agency', 'workflows');
  fs.mkdirSync(wf, { recursive: true, mode: 0o700 });
  fs.chmodSync(path.join(root, '.agency'), 0o700);
  fs.chmodSync(wf, 0o700);
  const file = path.join(wf, 'nightly.jsonc');
  fs.writeFileSync(file, '{\n  "name": "Nightly",\n  "enabled": false,\n  "on": {"schedule": [{"cron": "0 3 * * *", "timezone": "Europe/Paris"}], "workflow_dispatch": {"inputs": {"target": {"type": "string"}}}},\n  "job": {"prompt": "hi"}\n}\n');
  fs.chmodSync(file, 0o600);
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const log = path.join(root, 'calls.log');
  const dshd = path.join(bin, 'dshd');
  fs.writeFileSync(dshd, `#!/bin/sh\necho "dshd $*" >> ${log}\necho '{"state":"${floorState}"}'\n`, { mode: 0o755 });
  const systemctl = path.join(bin, 'systemctl');
  fs.writeFileSync(systemctl, `#!/bin/sh\necho "systemctl $*" >> ${log}\n`, { mode: 0o755 });
  const out = [], err = [];
  const stateDir = path.join(root, '.agency', 'state', 'master');
  const ctx = { home: root, stateDir, env: { USER: 'tom' }, now: () => new Date('2026-11-11T09:00:00Z'), out: s => out.push(s), err: s => err.push(s),
    uid: process.getuid(), dshd, systemctl, floorUrl: 'http://127.0.0.1:1', machineIdFile: path.join(root, 'machine-id') };
  const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '');
  return { root, stateDir, ctx, out, err, calls, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('C2.9: run on a missing workflow exits 1 and writes no spool file', async () => {
  const s = setup();
  try {
    const code = await runVerb(['master:nope'], s.ctx);
    assert.equal(code, 1);
    const incoming = path.join(s.stateDir, 'spool', 'incoming');
    assert.ok(!fs.existsSync(incoming) || fs.readdirSync(incoming).length === 0);
  } finally { s.cleanup(); }
});

test('C9.1: run writes one manual spool file and prints requested; a stopped floor gets one heartbeat start', async () => {
  const s = setup({ floorState: 'stopped' });
  try {
    const code = await runVerb(['master:nightly', '--input', 'target=nas', '--by', 'tom'], s.ctx);
    assert.equal(code, 0, s.err.join(''));
    const printed = JSON.parse(s.out.join('').trim());
    assert.equal(printed.v, 1);
    assert.equal(printed.state, 'requested');
    assert.match(printed.occurrence, /^master:nightly@manual:[0-9A-Z]{26}$/);
    const files = fs.readdirSync(path.join(s.stateDir, 'spool', 'incoming'));
    assert.equal(files.length, 1);
    assert.match(files[0], /^master~nightly@manual~[0-9A-Z]{26}\.json$/);
    const record = JSON.parse(fs.readFileSync(path.join(s.stateDir, 'spool', 'incoming', files[0]), 'utf8'));
    assert.equal(record.v, 1);
    assert.equal(record.kind, 'manual');
    assert.equal(record.workflow, 'master:nightly');
    assert.equal(record.by, 'tom');
    assert.deepEqual(record.inputs, { target: 'nas' });
    assert.equal(fs.readdirSync(path.join(s.stateDir, 'spool', 'tmp')).length, 0);
    assert.match(s.calls(), /dshd get --json floor/);
    assert.match(s.calls(), /systemctl --user start --no-block scheduled-heartbeat\.service/);
  } finally { s.cleanup(); }
});

test('C9.1: a running floor is not nudged through the heartbeat', async () => {
  const s = setup({ floorState: 'running' });
  try {
    assert.equal(await runVerb(['master:nightly'], s.ctx), 0, s.err.join(''));
    assert.doesNotMatch(s.calls(), /systemctl/);
  } finally { s.cleanup(); }
});

test('run refuses an unknown input with exit 1', async () => {
  const s = setup();
  try {
    assert.equal(await runVerb(['master:nightly', '--input', 'bogus=1'], s.ctx), 1);
  } finally { s.cleanup(); }
});

// C9.4: --wait polls sched_history_v1 until the occurrence leaves queued, running, deferred and awaiting;
// --follow runs `dshd read -f <instance>` once the attempt starts.
function historyDb(stateDir) {
  fs.mkdirSync(stateDir, { recursive: true });
  const db = new DatabaseSync(path.join(stateDir, 'orchestrator.sqlite'));
  db.exec('PRAGMA journal_mode=WAL; CREATE TABLE sched_history_v1 (occurrence TEXT PRIMARY KEY, workflow TEXT, kind TEXT, state TEXT, reason TEXT, attempt INTEGER, instance TEXT, started_at TEXT, ended_at TEXT)');
  return db;
}

/** Drive the floor's side of the table from the spool file the run wrote. */
function floorSteps(s, db, steps) {
  let i = 0;
  const timer = setInterval(() => {
    const incoming = path.join(s.stateDir, 'spool', 'incoming');
    const files = fs.existsSync(incoming) ? fs.readdirSync(incoming) : [];
    if (!files.length || i >= steps.length) return;
    const occ = JSON.parse(fs.readFileSync(path.join(incoming, files[0]), 'utf8')).occurrence;
    const [state, instance] = steps[i++];
    db.prepare('INSERT INTO sched_history_v1 (occurrence, workflow, kind, state, attempt, instance) VALUES (?, ?, ?, ?, 1, ?) ON CONFLICT(occurrence) DO UPDATE SET state = excluded.state, instance = excluded.instance')
      .run(occ, 'master:nightly', 'manual', state, instance);
  }, 15);
  return () => clearInterval(timer);
}

test('C9.4: --wait returns when the occurrence leaves the active states; stdout is the final row alone', async () => {
  const s = setup({ floorState: 'running' });
  const db = historyDb(s.stateDir);
  const stop = floorSteps(s, db, [['queued', null], ['running', 'sch-master-nightly-0900z'], ['awaiting', 'sch-master-nightly-0900z'], ['done', 'sch-master-nightly-0900z']]);
  try {
    const code = await runVerb(['master:nightly', '--by', 'probe', '--wait', '--json'], { ...s.ctx, waitPollMs: 10 });
    assert.equal(code, 0, s.err.join(''));
    const final = JSON.parse(s.out.join('').trim());
    assert.equal(final.state, 'done');
    assert.equal(final.instance, 'sch-master-nightly-0900z');
    assert.match(final.occurrence, /^master:nightly@manual:/);
    assert.match(s.err.join(''), /"state":"requested"/);
  } finally { stop(); db.close(); s.cleanup(); }
});

test('C9.4: --wait exits 1 when the occurrence ends anything but done', async () => {
  const s = setup({ floorState: 'running' });
  const db = historyDb(s.stateDir);
  const stop = floorSteps(s, db, [['queued', null], ['failed', 'sch-master-nightly-0900z']]);
  try {
    assert.equal(await runVerb(['master:nightly', '--wait'], { ...s.ctx, waitPollMs: 10 }), 1);
    assert.equal(JSON.parse(s.out.join('').trim()).state, 'failed');
  } finally { stop(); db.close(); s.cleanup(); }
});

test('C9.4: --follow runs dshd read -f on the instance once the attempt starts', async () => {
  const s = setup({ floorState: 'running' });
  const db = historyDb(s.stateDir);
  const stop = floorSteps(s, db, [['queued', null], ['running', 'sch-master-nightly-0900z']]);
  try {
    assert.equal(await runVerb(['master:nightly', '--follow'], { ...s.ctx, waitPollMs: 10 }), 0, s.err.join(''));
    assert.match(s.calls(), /dshd read -f sch-master-nightly-0900z/);
    assert.match(s.out.join(''), /"state":"requested"/);
  } finally { stop(); db.close(); s.cleanup(); }
});
