// ingest.test.mjs — tests covering C3.4, C3.8, revision ledger, and ingest debounce / anchoring
// Run: cd pkgs/scheduled && node --test test/ingest.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tick } from '../src/lib/tick.mjs';
import { recordRevision, readIndex, known } from '../src/lib/ledger.mjs';

const STUB_DSHD_PATH = fileURLToPath(new URL('./stub-dshd.mjs', import.meta.url));

function setupTestEnv() {
  const tmpDir = fs.mkdtempSync(join(os.tmpdir(), 'sched-ingest-test-'));
  const fakeHome = join(tmpDir, 'home');
  const fakeAgency = join(fakeHome, '.agency');
  const fakeWorkflows = join(fakeAgency, 'workflows');
  const fakeState = join(fakeAgency, 'state', 'master');
  fs.mkdirSync(fakeWorkflows, { recursive: true });
  fs.mkdirSync(fakeState, { recursive: true });

  const machineIdFile = join(tmpDir, 'machine-id');
  fs.writeFileSync(machineIdFile, '9fa751adff4f4e1d9ebed1ce31aac90b\n');

  const stubStateFile = join(tmpDir, 'stub-dshd-state.json');
  fs.writeFileSync(stubStateFile, JSON.stringify({
    state: 'running',
    release: { state: 'current' },
  }));
  const stubLogFile = join(tmpDir, 'stub-dshd.log');

  const ctx = {
    home: fakeHome,
    stateDir: fakeState,
    env: {
      STUB_DSHD_STATE: stubStateFile,
      STUB_DSHD_LOG: stubLogFile,
    },
    now: () => new Date('2026-11-12T14:00:00.000Z'),
    out: () => {},
    err: () => {},
    uid: typeof process.getuid === 'function' ? process.getuid() : 1000,
    dshd: STUB_DSHD_PATH,
    systemctl: '/run/current-system/sw/bin/systemctl',
    floorUrl: 'http://127.0.0.1:3082',
    machineIdFile,
  };

  return {
    tmpDir,
    fakeHome,
    fakeWorkflows,
    fakeState,
    machineIdFile,
    stubStateFile,
    stubLogFile,
    ctx,
    cleanup: () => {
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch {}
    },
  };
}

test('C3.4 A workflow file first seen in a pass: no instant before first sight is due; file written at 13:58 with cron 0 13 * * * yields nothing at the 14:00 pass', async () => {
  const env = setupTestEnv();
  try {
    // Prior heartbeat at 12:00
    fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
      v: 1,
      machineId: '9fa751adff4f4e1d9ebed1ce31aac90b',
      lastTick: '2026-11-12T12:00:00.000Z',
    }));

    // Workflow written at 13:58 with cron 0 13 * * * (13:00)
    const workflowPath = join(env.fakeWorkflows, 'afternoon.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Afternoon Check',
      enabled: true,
      on: { schedule: [{ cron: '0 13 * * *', timezone: 'UTC' }] },
      job: { prompt: 'Check afternoon status' },
    }));

    const writtenTime = new Date('2026-11-12T13:58:00.000Z');
    fs.utimesSync(workflowPath, writtenTime, writtenTime);

    // Pass runs at 14:00
    const passTime = new Date('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now: passTime });
    assert.equal(res.code, 0);

    // 13:00 instant is before first sight (13:58/14:00) -> yields nothing
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    const occurrenceFiles = fs.readdirSync(incomingDir).filter((f) => !f.startsWith('census@'));
    assert.equal(occurrenceFiles.length, 0);
  } finally {
    env.cleanup();
  }
});

test('C3.4 A file younger than 2 seconds gives warning young and the previous parse is used', async () => {
  const env = setupTestEnv();
  try {
    const workflowPath = join(env.fakeWorkflows, 'debounced.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Debounced Original',
      enabled: true,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      job: { prompt: 'Original prompt' },
    }));

    // Pass 1 at 12:00: parse and cache the original file (written 10s prior)
    const t0 = new Date('2026-11-12T12:00:00.000Z');
    const tOriginal = new Date(t0.getTime() - 10000);
    fs.utimesSync(workflowPath, tOriginal, tOriginal);
    const res1 = await tick(env.ctx, { now: t0 });
    assert.equal(res1.code, 0);

    // Now edit the file at 13:59:59.500 (500ms before pass at 14:00)
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Debounced Modified',
      enabled: false,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      job: { prompt: 'Modified prompt' },
    }));
    const tYoung = new Date('2026-11-12T13:59:59.500Z');
    fs.utimesSync(workflowPath, tYoung, tYoung);

    // Pass 2 at 14:00: file is younger than 2s (500ms old)
    const t1 = new Date('2026-11-12T14:00:00.000Z');
    const res2 = await tick(env.ctx, { now: t1 });
    assert.equal(res2.code, 0);

    // Census should show warning young, and the previous parse's enabled: true is used
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    const censusFiles = fs.readdirSync(incomingDir).filter((f) => f.startsWith('census@')).sort();
    assert.ok(censusFiles.length >= 2);
    const latestCensus = JSON.parse(fs.readFileSync(join(incomingDir, censusFiles[censusFiles.length - 1]), 'utf8'));

    const wfEntry = latestCensus.workflows.find((w) => w.id === 'master:debounced');
    assert.ok(wfEntry);
    assert.ok(wfEntry.problems.some((p) => p.code === 'young' && p.severity === 'warning'));
    // Previous parse was enabled: true; modified parse had enabled: false. Previous parse used:
    assert.equal(wfEntry.enabled, true);
  } finally {
    env.cleanup();
  }
});

test('C3.8 A pass: one census@<t>.json file lists every workflow found, valid or not, with state, enabled, revision, problems, and machineId', async () => {
  const env = setupTestEnv();
  try {
    // 1. One valid workflow
    fs.writeFileSync(join(env.fakeWorkflows, 'valid-wf.jsonc'), JSON.stringify({
      name: 'Valid Workflow',
      enabled: true,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      job: { prompt: 'Valid work' },
    }));

    // 2. One invalid workflow (malformed JSON)
    fs.writeFileSync(join(env.fakeWorkflows, 'invalid-wf.jsonc'), '{ "name": "Broken", on: bad_json }');

    const now = new Date('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now });
    assert.equal(res.code, 0);

    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    const censusFiles = fs.readdirSync(incomingDir).filter((f) => f.startsWith('census@'));
    assert.equal(censusFiles.length, 1);

    const census = JSON.parse(fs.readFileSync(join(incomingDir, censusFiles[0]), 'utf8'));
    assert.equal(census.v, 1);
    assert.equal(census.kind, 'census');
    assert.equal(census.machineId, '9fa751adff4f4e1d9ebed1ce31aac90b');

    const validWf = census.workflows.find((w) => w.id === 'master:valid-wf');
    assert.ok(validWf);
    assert.equal(validWf.state, 'valid');
    assert.equal(validWf.enabled, true);
    assert.ok(typeof validWf.revision === 'string' && validWf.revision.length === 12);
    assert.deepEqual(validWf.problems, []);

    const invalidWf = census.workflows.find((w) => w.id === 'master:invalid-wf');
    assert.ok(invalidWf);
    assert.equal(invalidWf.state, 'invalid');
    assert.equal(invalidWf.enabled, false);
    assert.ok(invalidWf.problems.length > 0);
  } finally {
    env.cleanup();
  }
});

test('C3.8 One invalid revision present over two passes gives exactly one <4>invalid line and unit Result stays success', async () => {
  const env = setupTestEnv();
  try {
    const invalidPath = join(env.fakeWorkflows, 'broken.jsonc');
    fs.writeFileSync(invalidPath, '{ "name": "Broken", bad_json: true }');

    // Pass 1: invalid file first seen
    const t0 = new Date('2026-11-12T14:00:00.000Z');
    const res1 = await tick(env.ctx, { now: t0 });
    assert.equal(res1.code, 0); // Unit result stays success

    const invalidLines1 = res1.lines.filter((l) => l.startsWith('<4>invalid '));
    assert.equal(invalidLines1.length, 1);
    assert.match(invalidLines1[0], /^<4>invalid workflow=master:broken rev=[0-9a-f]{12} at=\d+:\d+$/);

    // Pass 2: same invalid revision still present
    const t1 = new Date('2026-11-12T15:00:00.000Z');
    const res2 = await tick(env.ctx, { now: t1 });
    assert.equal(res2.code, 0); // Unit result stays success

    const invalidLines2 = res2.lines.filter((l) => l.startsWith('<4>invalid '));
    assert.equal(invalidLines2.length, 0, 'Second pass must not emit second <4>invalid line for same revision');
  } finally {
    env.cleanup();
  }
});

test('C3.8 An agency seen for the first time gives exactly one <5>new-agency line', async () => {
  const env = setupTestEnv();
  try {
    // Pass 1: master agency seen for first time
    const t0 = new Date('2026-11-12T14:00:00.000Z');
    const res1 = await tick(env.ctx, { now: t0 });
    assert.equal(res1.code, 0);

    const agencyLines1 = res1.lines.filter((l) => l.startsWith('<5>new-agency '));
    assert.equal(agencyLines1.length, 1);
    assert.ok(agencyLines1[0].includes('agency=master'));

    // Pass 2: agency was seen previously
    const t1 = new Date('2026-11-12T15:00:00.000Z');
    const res2 = await tick(env.ctx, { now: t1 });
    assert.equal(res2.code, 0);

    const agencyLines2 = res2.lines.filter((l) => l.startsWith('<5>new-agency '));
    assert.equal(agencyLines2.length, 0, 'Second pass must not emit new-agency for already-seen agency');
  } finally {
    env.cleanup();
  }
});

test('Revision ledger: recordRevision stores content-addressed files and appends index.jsonl under 4 KiB', async () => {
  const env = setupTestEnv();
  try {
    const fileBytes = Buffer.from('// sample workflow file\n{"name":"Test"}\n');
    const promptBytes = Buffer.from('# Prompt File\nDo this work.\n');

    // First record: new revision
    const added = await recordRevision(env.fakeState, {
      workflow: 'master:test-wf',
      revision: 'abcdef123456',
      fileBytes,
      promptBytes,
      by: 'tick',
      valid: true,
      at: new Date('2026-11-12T14:00:00.000Z'),
    });
    assert.equal(added, true);

    // Verify content-addressed files exist in revisions/
    const revDir = join(env.fakeState, 'revisions');
    assert.ok(fs.existsSync(revDir));

    const indexFile = join(revDir, 'index.jsonl');
    assert.ok(fs.existsSync(indexFile));
    const stat = fs.statSync(indexFile);
    assert.ok(stat.size < 4096, `index line should be well under 4 KiB, got ${stat.size} bytes`);

    // Verify known returns true
    const isKnown = await known(env.fakeState, 'master:test-wf', 'abcdef123456');
    assert.equal(isKnown, true);

    // Second record of same revision returns false and does not append duplicate line
    const addedAgain = await recordRevision(env.fakeState, {
      workflow: 'master:test-wf',
      revision: 'abcdef123456',
      fileBytes,
      promptBytes,
      by: 'tick',
      valid: true,
    });
    assert.equal(addedAgain, false);

    const entries = await readIndex(env.fakeState);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].workflow, 'master:test-wf');
    assert.equal(entries[0].revision, 'abcdef123456');
    assert.equal(entries[0].valid, true);
    assert.ok(entries[0].file);
    assert.ok(entries[0].prompt);
  } finally {
    env.cleanup();
  }
});
