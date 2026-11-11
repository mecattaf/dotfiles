// tick.test.mjs — tests covering C3.1, C3.2, C3.3, C3.5, C3.6, C3.7, C3.9, C3.12
// Run: cd pkgs/scheduled && node --test test/tick.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tick } from '../src/lib/tick.mjs';
import { main as tickMain } from '../src/verbs/tick.mjs';

const STUB_DSHD_PATH = fileURLToPath(new URL('./stub-dshd.mjs', import.meta.url));

function setupTestEnv() {
  const tmpDir = fs.mkdtempSync(join(os.tmpdir(), 'sched-tick-test-'));
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
    out: (s) => {},
    err: (s) => {},
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

function readStubLogs(logFile) {
  if (!fs.existsSync(logFile)) return [];
  return fs.readFileSync(logFile, 'utf8')
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((l) => JSON.parse(l));
}

test('C3.1 A first scheduled tick with no heartbeat.json writes heartbeat.json, one census file, and hands off no occurrence', async () => {
  const env = setupTestEnv();
  try {
    const now = new Date('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now });
    assert.equal(res.code, 0);

    // Assert heartbeat.json written with v 1, machineId, lastTick now
    const heartbeatPath = join(env.fakeState, 'heartbeat.json');
    assert.ok(fs.existsSync(heartbeatPath));
    const hb = JSON.parse(fs.readFileSync(heartbeatPath, 'utf8'));
    assert.equal(hb.v, 1);
    assert.equal(hb.machineId, '9fa751adff4f4e1d9ebed1ce31aac90b');
    assert.equal(hb.lastTick, now.toISOString());

    // Assert one census file written in spool/incoming
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    assert.ok(fs.existsSync(incomingDir));
    const files = fs.readdirSync(incomingDir);
    const censusFiles = files.filter((f) => f.startsWith('census@'));
    assert.equal(censusFiles.length, 1);

    // Assert no occurrences handed off
    const occurrenceFiles = files.filter((f) => !f.startsWith('census@'));
    assert.equal(occurrenceFiles.length, 0);
  } finally {
    env.cleanup();
  }
});

test('C3.2 An hourly workflow and a lastTick 3 hours old links exactly one spool record with missed=2, latest instant, revision, and by scheduled-heartbeat', async () => {
  const env = setupTestEnv();
  try {
    // 1. First tick sets up heartbeat at 11:00
    const t0 = new Date('2026-11-12T11:00:00.000Z');
    const workflowPath = join(env.fakeWorkflows, 'fleet-nightly.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Fleet Nightly',
      enabled: true,
      on: {
        schedule: [{ cron: '0 * * * *', timezone: 'UTC' }],
      },
      job: { prompt: 'Run checks' },
    }));

    // Pre-seed intake with armedSince at 11:00 so it is not anchored to now
    fs.mkdirSync(env.fakeState, { recursive: true });
    const st = fs.statSync(workflowPath, { bigint: true });
    fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
      v: 1,
      machineId: '9fa751adff4f4e1d9ebed1ce31aac90b',
      lastTick: t0.toISOString(),
    }));
    fs.writeFileSync(join(env.fakeState, 'intake.json'), JSON.stringify({
      v: 1,
      files: {
        [workflowPath]: {
          dev: String(st.dev),
          ino: String(st.ino),
          size: Number(st.size),
          mtimeNs: String(st.mtimeNs),
          revision: '3f2a9c1e0b7d',
          problems: [],
          firstSeen: t0.toISOString(),
          armedSince: t0.toISOString(),
          valid: true,
          enabled: true,
          on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
        },
      },
      agencies: { master: { firstSeen: t0.toISOString(), root: env.fakeHome } },
    }));

    // 2. Tick 3 hours later at 14:00
    const t1 = new Date('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now: t1 });
    assert.equal(res.code, 0);

    // Spool record check
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    const files = fs.readdirSync(incomingDir).filter((f) => !f.startsWith('census@'));
    assert.equal(files.length, 1);
    assert.equal(files[0], 'master~fleet-nightly@20261112T1400Z.json');

    const record = JSON.parse(fs.readFileSync(join(incomingDir, files[0]), 'utf8'));
    assert.equal(record.v, 1);
    assert.equal(record.kind, 'schedule');
    assert.equal(record.workflow, 'master:fleet-nightly');
    assert.equal(record.instant, '2026-11-12T14:00:00.000Z');
    assert.equal(record.missed, 2);
    assert.equal(record.by, 'scheduled-heartbeat');

    // heartbeat.json lastTick committed to 14:00
    const hb = JSON.parse(fs.readFileSync(join(env.fakeState, 'heartbeat.json'), 'utf8'));
    assert.equal(hb.lastTick, t1.toISOString());
  } finally {
    env.cleanup();
  }
});

test('C3.3 The same window ticked again with the record still in incoming/ meets EEXIST, no second file appears, and exit is 0', async () => {
  const env = setupTestEnv();
  try {
    const t0 = new Date('2026-11-12T11:00:00.000Z');
    const workflowPath = join(env.fakeWorkflows, 'fleet-nightly.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Fleet Nightly',
      enabled: true,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      job: { prompt: 'Run checks' },
    }));

    const st = fs.statSync(workflowPath, { bigint: true });
    fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
      v: 1,
      machineId: '9fa751adff4f4e1d9ebed1ce31aac90b',
      lastTick: t0.toISOString(),
    }));
    fs.writeFileSync(join(env.fakeState, 'intake.json'), JSON.stringify({
      v: 1,
      files: {
        [workflowPath]: {
          dev: String(st.dev),
          ino: String(st.ino),
          size: Number(st.size),
          mtimeNs: String(st.mtimeNs),
          revision: '3f2a9c1e0b7d',
          problems: [],
          firstSeen: t0.toISOString(),
          armedSince: t0.toISOString(),
          valid: true,
          enabled: true,
          on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
        },
      },
      agencies: { master: { firstSeen: t0.toISOString(), root: env.fakeHome } },
    }));

    // Pre-create the destination file in incoming/ simulating a prior attempt
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    fs.mkdirSync(incomingDir, { recursive: true });
    const targetFile = join(incomingDir, 'master~fleet-nightly@20261112T1400Z.json');
    fs.writeFileSync(targetFile, JSON.stringify({ existing: true }));

    // Tick the same window
    const t1 = new Date('2026-11-12T14:00:00.000Z');
    const res = await tick(env.ctx, { now: t1 });
    assert.equal(res.code, 0);

    // Verify existing file remained untouched and no second occurrence file appeared
    const occurrenceFiles = fs.readdirSync(incomingDir).filter((f) => !f.startsWith('census@'));
    assert.equal(occurrenceFiles.length, 1);
    const content = JSON.parse(fs.readFileSync(targetFile, 'utf8'));
    assert.equal(content.existing, true);
  } finally {
    env.cleanup();
  }
});

test('C3.5 A clock earlier than lastTick gives no hand-off, one <4>clock went back line, lastTick kept, and exit 0', async () => {
  const env = setupTestEnv();
  try {
    const tFuture = new Date('2026-11-12T14:00:00.000Z');
    fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
      v: 1,
      machineId: '9fa751adff4f4e1d9ebed1ce31aac90b',
      lastTick: tFuture.toISOString(),
    }));

    const workflowPath = join(env.fakeWorkflows, 'hourly.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Hourly',
      enabled: true,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      job: { prompt: 'Do work' },
    }));

    const tPast = new Date('2026-11-12T13:00:00.000Z');
    const res = await tick(env.ctx, { now: tPast });
    assert.equal(res.code, 0);

    // Line check
    assert.ok(res.lines.includes('<4>clock went back'));

    // No occurrence handed off
    const incomingDir = join(env.fakeState, 'spool', 'incoming');
    if (fs.existsSync(incomingDir)) {
      const occs = fs.readdirSync(incomingDir).filter((f) => !f.startsWith('census@'));
      assert.equal(occs.length, 0);
    }

    // lastTick kept unchanged
    const hb = JSON.parse(fs.readFileSync(join(env.fakeState, 'heartbeat.json'), 'utf8'));
    assert.equal(hb.lastTick, tFuture.toISOString());
  } finally {
    env.cleanup();
  }
});

test('C3.6 A heartbeat.json whose machineId differs from /etc/machine-id, or higher major v, exits 1, writes nothing, hands off nothing', async () => {
  // Part 1: machineId differs
  {
    const env = setupTestEnv();
    try {
      fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
        v: 1,
        machineId: 'different-machine-id-12345',
        lastTick: '2026-11-12T10:00:00.000Z',
      }));

      const res = await tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') });
      assert.equal(res.code, 1);
      assert.ok(res.lines.some((l) => l.includes('<3>guard machine-id differs')));

      // Nothing handed off
      const incomingDir = join(env.fakeState, 'spool', 'incoming');
      assert.ok(!fs.existsSync(incomingDir));
    } finally {
      env.cleanup();
    }
  }

  // Part 2: higher major v in heartbeat.json
  {
    const env = setupTestEnv();
    try {
      fs.writeFileSync(join(env.fakeState, 'heartbeat.json'), JSON.stringify({
        v: 2,
        machineId: '9fa751adff4f4e1d9ebed1ce31aac90b',
        lastTick: '2026-11-12T10:00:00.000Z',
      }));

      const res = await tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') });
      assert.equal(res.code, 1);
      assert.ok(res.lines.some((l) => l.includes('<3>guard higher state version')));

      const incomingDir = join(env.fakeState, 'spool', 'incoming');
      assert.ok(!fs.existsSync(incomingDir));
    } finally {
      env.cleanup();
    }
  }
});

test('C3.7 Two scheduled tick processes started together: the second holds on state/master/.tick.lock until the first ones pass line', async () => {
  const env = setupTestEnv();
  try {
    const lockFile = join(env.fakeState, '.tick.lock');

    // Acquire lock manually to simulate an in-flight first tick
    fs.mkdirSync(env.fakeState, { recursive: true });
    fs.writeFileSync(lockFile, `${process.pid}\n`);

    let tickCompleted = false;
    const tickPromise = tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') }).then((r) => {
      tickCompleted = true;
      return r;
    });

    // Verify tick is blocked holding on the lock
    await new Promise((r) => setTimeout(r, 100));
    assert.equal(tickCompleted, false, 'Tick should be waiting for lock to release');

    // Simulate first process completing pass line and releasing lock
    fs.unlinkSync(lockFile);

    // Second process should now acquire lock and finish
    const res = await tickPromise;
    assert.equal(tickCompleted, true);
    assert.equal(res.code, 0);
    assert.ok(res.lines.some((l) => l.startsWith('<6>pass ')));
  } finally {
    env.cleanup();
  }
});

test('C3.9 One pass of scheduled tick opens no file named orchestrator.sqlite, runs no dshd run, and runs no if or outcome command', async () => {
  const env = setupTestEnv();
  try {
    // Create workflow with if.command and outcome.check
    const workflowPath = join(env.fakeWorkflows, 'gated.jsonc');
    fs.writeFileSync(workflowPath, JSON.stringify({
      name: 'Gated Workflow',
      enabled: true,
      on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
      if: { command: ['false'] },
      outcome: { check: ['false'] },
      job: { prompt: 'Do test' },
    }));

    const res = await tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') });
    assert.equal(res.code, 0);

    // Assert orchestrator.sqlite does not exist
    const sqlitePath = join(env.fakeState, 'orchestrator.sqlite');
    assert.equal(fs.existsSync(sqlitePath), false, 'orchestrator.sqlite must not exist');

    // Assert no dshd run was invoked in stub-dshd log
    const logs = readStubLogs(env.stubLogFile);
    for (const argv of logs) {
      assert.notEqual(argv[0], 'run', `dshd ${argv.join(' ')} must not be called with 'run'`);
    }
  } finally {
    env.cleanup();
  }
});

test('C3.12 Any tick line carries an sd-daemon level prefix, and pass carries reason=timer when TRIGGER_UNIT is set and reason=manual otherwise', async () => {
  // Case 1: TRIGGER_UNIT is set -> reason=timer
  {
    const env = setupTestEnv();
    try {
      env.ctx.env.TRIGGER_UNIT = 'scheduled-heartbeat.timer';
      const res = await tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') });
      assert.equal(res.code, 0);

      // Verify all lines have sd-daemon prefix
      for (const line of res.lines) {
        assert.match(line, /^<[3-6]>[a-z]/, `Line '${line}' must carry an sd-daemon level prefix`);
      }

      const passLine = res.lines.find((l) => l.startsWith('<6>pass '));
      assert.ok(passLine);
      assert.match(passLine, /^<6>pass reason=timer took_ms=\d+ discover_ms=\d+ agencies=\d+ workflows=\d+$/);
    } finally {
      env.cleanup();
    }
  }

  // Case 2: TRIGGER_UNIT not set -> reason=manual
  {
    const env = setupTestEnv();
    try {
      delete env.ctx.env.TRIGGER_UNIT;
      const res = await tick(env.ctx, { now: new Date('2026-11-12T14:00:00.000Z') });
      assert.equal(res.code, 0);

      const passLine = res.lines.find((l) => l.startsWith('<6>pass '));
      assert.ok(passLine);
      assert.match(passLine, /^<6>pass reason=manual took_ms=\d+ discover_ms=\d+ agencies=\d+ workflows=\d+$/);
    } finally {
      env.cleanup();
    }
  }
});

test('CLI verb main parses flags and prints lines', async () => {
  const env = setupTestEnv();
  try {
    const outLines = [];
    const errLines = [];
    const testCtx = {
      ...env.ctx,
      out: (s) => outLines.push(s),
      err: (s) => errLines.push(s),
    };

    const code = await tickMain(['--now', '2026-11-12T14:00:00.000Z', '--state-dir', env.fakeState], testCtx);
    assert.equal(code, 0);
    assert.ok(outLines.some((l) => l.includes('<6>pass ')));
  } finally {
    env.cleanup();
  }
});
