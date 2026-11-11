/**
 * test/gate.test.mjs
 * Tests for the `scheduled gate` and `scheduled check` verbs.
 * Covers Claim C2.14.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { main as gateVerb } from '../src/verbs/gate.mjs';
import { main as checkVerb } from '../src/verbs/check.mjs';
import { runCommand } from '../src/lib/command.mjs';

function makeTempAgency(root, stem, content) {
  const agencyDir = path.join(root, '.agency');
  const workflowsDir = path.join(agencyDir, 'workflows');
  fs.mkdirSync(workflowsDir, { recursive: true, mode: 0o700 });
  fs.chmodSync(agencyDir, 0o700);
  fs.chmodSync(workflowsDir, 0o700);

  const filePath = path.join(workflowsDir, `${stem}.jsonc`);
  fs.writeFileSync(filePath, content, { mode: 0o600 });
  return { agencyDir, workflowsDir, filePath };
}

function makeCtx(overrides = {}) {
  const out = [];
  const err = [];
  return {
    uid: process.getuid(),
    home: os.homedir(),
    now: () => new Date('2026-11-12T00:00:00.000Z'),
    out: (s) => out.push(s),
    err: (s) => err.push(s),
    _out: out,
    _err: err,
    stateDir: path.join(os.tmpdir(), 'state'),
    env: {},
    ...overrides,
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test('C2.14: scheduled gate - if.idle defers when busy_reasons is non-empty', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-gate-idle-'));
  const fakePy = path.join(tmpHome, 'fake-update-check.py');
  fs.writeFileSync(
    fakePy,
    'def busy_reasons():\n    return ["five-minute load 2.5 >= 1.0"]\n'
  );

  makeTempAgency(tmpHome, 'idle-task', JSON.stringify({
    if: { idle: true },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Idle check' },
  }));

  const ctx = makeCtx({
    home: tmpHome,
    env: { SCHEDULED_UPDATE_CHECK: fakePy },
  });

  const code = await gateVerb(
    [
      'idle-task',
      '--occurrence',
      'master:idle-task@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.deferred, 'idle: five-minute load 2.5 >= 1.0');
});

test('C2.14: scheduled gate - if.idle passes (null) when busy_reasons is empty', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-gate-idle-empty-'));
  const fakePy = path.join(tmpHome, 'fake-update-check.py');
  fs.writeFileSync(fakePy, 'def busy_reasons():\n    return []\n');

  makeTempAgency(tmpHome, 'idle-pass', JSON.stringify({
    if: { idle: true },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Idle pass' },
  }));

  const ctx = makeCtx({
    home: tmpHome,
    env: { SCHEDULED_UPDATE_CHECK: fakePy },
  });

  const code = await gateVerb(
    [
      'idle-pass',
      '--occurrence',
      'master:idle-pass@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.deferred, null);
});

test('C2.14: scheduled gate - if.idle defers with idle-unknown on failure', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-gate-idle-err-'));
  const fakePy = path.join(tmpHome, 'broken-update-check.py');
  fs.writeFileSync(fakePy, 'raise RuntimeError("cannot read state")\n');

  makeTempAgency(tmpHome, 'idle-err', JSON.stringify({
    if: { idle: true },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Idle broken' },
  }));

  const ctx = makeCtx({
    home: tmpHome,
    env: { SCHEDULED_UPDATE_CHECK: fakePy },
  });

  const code = await gateVerb(
    [
      'idle-err',
      '--occurrence',
      'master:idle-err@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.deferred, 'idle-unknown');
});

test('C2.14: scheduled gate - if.command defers with "command" on non-zero exit', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-gate-cmd-'));

  makeTempAgency(tmpHome, 'cmd-fail', JSON.stringify({
    if: { command: { sh: 'exit 42' } },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Cmd fail' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await gateVerb(
    [
      'cmd-fail',
      '--occurrence',
      'master:cmd-fail@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.deferred, 'command');
});

test('C2.14: scheduled check - outcome.check passes and prints {holds: true, exit: 0, output}', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-check-pass-'));

  makeTempAgency(tmpHome, 'check-pass', JSON.stringify({
    outcome: { check: { sh: 'echo "all good"' } },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Check task' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await checkVerb(
    [
      'check-pass',
      '--occurrence',
      'master:check-pass@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.holds, true);
  assert.equal(res.exit, 0);
  assert.ok(res.output.includes('all good'));
});

test('C2.14: scheduled check - when no outcome.check exists prints holds false exit null', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-check-none-'));

  makeTempAgency(tmpHome, 'check-none', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'No check' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await checkVerb(
    [
      'check-none',
      '--occurrence',
      'master:check-none@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.holds, false);
  assert.equal(res.exit, null);
  assert.equal(res.output, '');
});

test('C2.14: command sandbox - process group kill terminates spawned child sleeping process', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-pgkill-'));
  const pidFile = path.join(tmpHome, 'child.pid');

  // Shell script starts a grandchild sleep in the background, writes PID, then sleeps
  const scriptContent = `#!/bin/sh
sleep 120 &
echo $! > "${pidFile}"
wait
`;
  const scriptPath = path.join(tmpHome, 'spawn-child.sh');
  fs.writeFileSync(scriptPath, scriptContent, { mode: 0o755 });

  const ctx = makeCtx({
    home: tmpHome,
    env: { SCHEDULED_COMMAND_TIMEOUT_MS: '200' },
  });

  const res = await runCommand(ctx, [scriptPath], {
    cwd: tmpHome,
    timeoutMs: 200,
  });

  assert.equal(res.timedOut, true);

  // Read grandchild pid
  assert.ok(fs.existsSync(pidFile), 'PID file should have been written');
  const childPid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
  assert.ok(!isNaN(childPid) && childPid > 0, `Expected numeric PID, got: ${childPid}`);

  // Small pause to allow OS to deliver signal and clean up
  await new Promise((r) => setTimeout(r, 100));

  // Verify process is killed (kill with signal 0 throws ESRCH)
  let isAlive = true;
  try {
    process.kill(childPid, 0);
  } catch (err) {
    if (err.code === 'ESRCH') {
      isAlive = false;
    }
  }

  assert.equal(isAlive, false, `Child process ${childPid} should have been killed with process group`);
});

test('C2.14: outcome.check output captures last 4 KiB when output is large', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-check-large-'));

  // Generate 8 KiB of data with distinct marker at the end
  const scriptContent = `#!/bin/sh
python3 -c 'print("A" * 6000 + "END_MARKER")'
`;
  const scriptPath = path.join(tmpHome, 'large-output.sh');
  fs.writeFileSync(scriptPath, scriptContent, { mode: 0o755 });

  makeTempAgency(tmpHome, 'large-check', JSON.stringify({
    outcome: { check: [scriptPath] },
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Large output check' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await checkVerb(
    [
      'large-check',
      '--occurrence',
      'master:large-check@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const res = JSON.parse(ctx._out.join(''));
  assert.equal(res.holds, true);
  assert.ok(Buffer.byteLength(res.output, 'utf8') <= 4096, 'Output must not exceed 4 KiB');
  assert.ok(res.output.endsWith('END_MARKER\n'), 'Output must contain the end marker');
});
