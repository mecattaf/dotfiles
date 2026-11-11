/**
 * test/ls.test.mjs
 * Tests for the `scheduled ls` verb and ID resolution.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { main as lsVerb } from '../src/verbs/ls.mjs';
import { resolveId } from '../src/lib/resolve.mjs';

function makeTempAgency(root, stem, content, { isProposal = false } = {}) {
  const agencyDir = path.join(root, '.agency');
  const workflowsDir = path.join(agencyDir, 'workflows');
  const targetDir = isProposal ? path.join(workflowsDir, 'proposed') : workflowsDir;
  fs.mkdirSync(targetDir, { recursive: true, mode: 0o700 });
  fs.chmodSync(agencyDir, 0o700);
  fs.chmodSync(workflowsDir, 0o700);
  if (isProposal) fs.chmodSync(targetDir, 0o700);

  const filePath = path.join(targetDir, `${stem}.jsonc`);
  fs.writeFileSync(filePath, content, { mode: 0o600 });
  return { agencyDir, workflowsDir, filePath };
}

function makeFakeSystemctl(dir, { activeState = 'active', result = 'success', nextElapse = '1762820000000000', fail = false } = {}) {
  const scriptPath = path.join(dir, 'fake-systemctl.sh');
  if (fail) {
    fs.writeFileSync(scriptPath, '#!/bin/sh\nexit 1\n', { mode: 0o755 });
  } else {
    fs.writeFileSync(
      scriptPath,
      `#!/bin/sh
cat << 'EOF'
ActiveState=${activeState}
Result=${result}
NextElapseUSecRealtime=0

ActiveState=${activeState}
Result=${result}
NextElapseUSecRealtime=${nextElapse}
EOF
`,
      { mode: 0o755 }
    );
  }
  return scriptPath;
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
    systemctl: '/bin/true',
    stateDir: path.join(os.tmpdir(), 'state'),
    env: {},
    ...overrides,
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test('ls: text header line from systemctl show on success', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-test-'));
  const fakeSys = makeFakeSystemctl(tmpHome, { activeState: 'active' });

  makeTempAgency(tmpHome, 'daily-sync', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Sync tasks' },
  }));

  const ctx = makeCtx({ home: tmpHome, systemctl: fakeSys });
  const code = await lsVerb([], ctx);

  assert.equal(code, 0);
  const lines = ctx._out.join('').trim().split('\n');
  assert.ok(lines[0].startsWith('heartbeat: active'), `Expected heartbeat line, got: ${lines[0]}`);
  assert.ok(lines.some((l) => l.includes('master:daily-sync') && l.includes('valid')));
});

test('ls: systemctl failure prints heartbeat: unknown', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-fail-'));
  const fakeSys = makeFakeSystemctl(tmpHome, { fail: true });

  const ctx = makeCtx({ home: tmpHome, systemctl: fakeSys });
  const code = await lsVerb([], ctx);

  assert.equal(code, 0);
  const lines = ctx._out.join('').trim().split('\n');
  assert.equal(lines[0], 'heartbeat: unknown');
});

test('ls: invalid workflows sort first, before valid, paused, proposal', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-sort-'));
  const fakeSys = makeFakeSystemctl(tmpHome);

  // 1. Valid workflow (starts with 'a' alphabetically)
  makeTempAgency(tmpHome, 'aaa-valid', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Valid task' },
  }));

  // 2. Invalid workflow (starts with 'z')
  makeTempAgency(tmpHome, 'zzz-invalid', 'INVALID JSON CONTENT');

  // 3. Paused workflow
  makeTempAgency(tmpHome, 'mmm-paused', JSON.stringify({
    enabled: false,
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Paused task' },
  }));

  // 4. Proposal
  makeTempAgency(tmpHome, 'ppp-prop', JSON.stringify({
    enabled: false,
    'x-proposal': { by: 'tom', at: '2026-11-12T00:00:00Z', why: 'test' },
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Prop task' },
  }), { isProposal: true });

  const ctx = makeCtx({ home: tmpHome, systemctl: fakeSys });
  const code = await lsVerb(['--json'], ctx);
  assert.equal(code, 0);

  const json = JSON.parse(ctx._out.join(''));
  assert.equal(json.workflows.length, 4);

  // Invalid must be first!
  assert.equal(json.workflows[0].id, 'master:zzz-invalid');
  assert.equal(json.workflows[0].state, 'invalid');

  const states = json.workflows.map((w) => w.state);
  assert.ok(states.includes('valid'));
  assert.ok(states.includes('paused'));
  assert.ok(states.includes('proposal'));
});

test('ls: --json output shape contains heartbeat, agencies, workflows', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-json-'));
  const fakeSys = makeFakeSystemctl(tmpHome, { activeState: 'active' });

  makeTempAgency(tmpHome, 'task-one', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Do something' },
  }));

  const ctx = makeCtx({ home: tmpHome, systemctl: fakeSys });
  const code = await lsVerb(['--json'], ctx);
  assert.equal(code, 0);

  const parsed = JSON.parse(ctx._out.join(''));
  assert.ok(parsed.heartbeat);
  assert.equal(parsed.heartbeat.activeState, 'active');
  assert.ok(Array.isArray(parsed.agencies));
  assert.ok(Array.isArray(parsed.workflows));
  assert.equal(parsed.workflows.length, 1);
  assert.equal(parsed.workflows[0].id, 'master:task-one');
  assert.equal(parsed.workflows[0].state, 'valid');
  assert.ok(parsed.workflows[0].revision);
  assert.ok(parsed.workflows[0].next);
});

test('ls: --agency filters to specified agency', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-filter-'));
  const fakeSys = makeFakeSystemctl(tmpHome);

  // Master agency
  makeTempAgency(tmpHome, 'master-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Master' },
  }));

  // Sub-agency: crm
  const crmDir = path.join(tmpHome, 'crm');
  makeTempAgency(crmDir, 'crm-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'CRM' },
  }));

  const ctx = makeCtx({ home: tmpHome, systemctl: fakeSys });

  // Filter to crm
  const code = await lsVerb(['--agency', 'crm', '--json'], ctx);
  assert.equal(code, 0);

  const json = JSON.parse(ctx._out.join(''));
  assert.equal(json.workflows.length, 1);
  assert.equal(json.workflows[0].id, 'crm:crm-task');
});

test('resolveId: resolves <agency>:<stem> and bare <stem> when unique', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-resolve-'));
  makeTempAgency(tmpHome, 'unique-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Unique' },
  }));

  const ctx = makeCtx({ home: tmpHome });

  // 1. Full ID
  const r1 = await resolveId(ctx, 'master:unique-task');
  assert.equal(r1.id, 'master:unique-task');
  assert.equal(r1.agency, 'master');
  assert.equal(r1.stem, 'unique-task');

  // 2. Bare stem
  const r2 = await resolveId(ctx, 'unique-task');
  assert.equal(r2.id, 'master:unique-task');
});

test('resolveId: refuses unknown workflow (exit 1)', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-resolve-unk-'));
  const ctx = makeCtx({ home: tmpHome });

  await assert.rejects(
    () => resolveId(ctx, 'non-existent'),
    (err) => err.exitCode === 1
  );
  assert.ok(ctx._err.join('').includes("workflow 'non-existent' not found"));
});

test('resolveId: refuses ambiguous bare stem across multiple agencies (exit 1)', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-resolve-amb-'));

  // master:shared-task
  makeTempAgency(tmpHome, 'shared-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Master shared' },
  }));

  // sub:shared-task
  const subDir = path.join(tmpHome, 'sub');
  makeTempAgency(subDir, 'shared-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Sub shared' },
  }));

  const ctx = makeCtx({ home: tmpHome });

  await assert.rejects(
    () => resolveId(ctx, 'shared-task'),
    (err) => err.exitCode === 1 && err.candidates.length === 2
  );
  assert.ok(ctx._err.join('').includes('ambiguous workflow id'));
});

test('C2.8: ls --json carries discovery problems (an agency named master under ~)', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-ls-problems-'));
  try {
    fs.chmodSync(root, 0o700);
    makeTempAgency(root, 'kept', JSON.stringify({ enabled: false, on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] }, job: { prompt: 'x' } }));
    makeTempAgency(path.join(root, 'master'), 'other', JSON.stringify({ enabled: false, on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] }, job: { prompt: 'x' } }));
    const ctx = makeCtx({ home: root, systemctl: makeFakeSystemctl(root) });
    assert.equal(await lsVerb(['--json'], ctx), 0, ctx._err.join(''));
    const data = JSON.parse(ctx._out.join(''));
    assert.ok(Array.isArray(data.problems));
    assert.ok(data.problems.some((p) => p.code === 'agency-name'), JSON.stringify(data.problems));
    const text = makeCtx({ home: root, systemctl: makeFakeSystemctl(root) });
    assert.equal(await lsVerb([], text), 0);
    assert.match(text._out.join(''), /agency-name/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
