/**
 * test/show.test.mjs
 * Tests for the `scheduled show` verb.
 * Covers C2.1 (show --json shows defaults), C2.5 (DST next instant), C2.7 (normalized output).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { main as showVerb } from '../src/verbs/show.mjs';
import { normalize, revision } from '../src/lib/schema.mjs';
import { main as schemaVerb } from '../src/verbs/schema.mjs';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeTempAgency(stem, content, { mode = 0o700, fileMode = 0o600 } = {}) {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-show-test-'));
  const agencyDir = path.join(tmpRoot, '.agency');
  const workflowsDir = path.join(agencyDir, 'workflows');
  fs.mkdirSync(workflowsDir, { recursive: true });
  fs.chmodSync(agencyDir, mode);
  fs.chmodSync(workflowsDir, mode);
  const filePath = path.join(workflowsDir, `${stem}.jsonc`);
  fs.writeFileSync(filePath, content, { mode: fileMode });
  fs.chmodSync(filePath, fileMode);
  return { tmpRoot, agencyDir, workflowsDir, filePath };
}

function makeCtx(overrides = {}) {
  const out = [];
  const err = [];
  return {
    uid: process.getuid(),
    home: os.homedir(),
    now: () => new Date(),
    out: (s) => out.push(s),
    err: (s) => err.push(s),
    _out: out,
    _err: err,
    ...overrides,
  };
}

// ─── C2.1: show --json fills defaults ────────────────────────────────────────

test('C2.1: show --json on smallest valid file fills all defaults', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Summarise last week\'s merged PRs in ~/today.' },
  });
  const { filePath } = makeTempAgency('fleet-nightly', content);
  const ctx = makeCtx({ home: os.homedir() });
  const code = await showVerb([filePath, '--json'], ctx);
  assert.equal(code, 0, `Expected exit 0, got ${code}; err: ${ctx._err.join('')}`);

  const output = JSON.parse(ctx._out.join(''));
  assert.equal(output.v, 1);
  assert.equal(output.kind, 'workflow');
  assert.equal(output.state, 'valid');
  // C2.1: enabled true
  assert.equal(output.spec.enabled, true);
  // C2.1: concurrency group = workflow id
  assert.ok(output.spec.concurrency.group.includes('fleet-nightly'), `Concurrency group: ${output.spec.concurrency.group}`);
  // C2.1: permissions.mode workspace-write
  assert.equal(output.spec.permissions.mode, 'workspace-write');
  // C2.1: job.timeout_ms = 3h
  assert.equal(output.spec.job.timeout_ms, 3 * 60 * 60 * 1000);
  // C2.1: context.previous = 1
  assert.equal(output.spec.context.previous, 1);
  // C2.1: context.diff = true
  assert.equal(output.spec.context.diff, true);
  // C2.1: outcome.attempts = 1
  assert.equal(output.spec.outcome.attempts, 1);
});

test('C2.1: show --json v field is 1', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-wf', content);
  const ctx = makeCtx();
  await showVerb([filePath, '--json'], ctx);
  const output = JSON.parse(ctx._out.join(''));
  assert.equal(output.v, 1);
});

test('C2.1: show --json includes revision', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-rev', content);
  const ctx = makeCtx();
  await showVerb([filePath, '--json'], ctx);
  const output = JSON.parse(ctx._out.join(''));
  assert.ok(output.revision && /^[0-9a-f]{12}$/.test(output.revision),
    `Expected 12-hex revision, got: ${output.revision}`);
});

test('C2.1: show --json next field has future dates', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-next', content);
  const ctx = makeCtx({ now: () => new Date('2026-11-01T00:00:00Z') });
  await showVerb([filePath, '--json'], ctx);
  const output = JSON.parse(ctx._out.join(''));
  assert.ok(Array.isArray(output.next), 'Expected next array');
  assert.ok(output.next.length > 0, 'Expected at least one next occurrence');
  for (const d of output.next) {
    assert.ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(d), `Expected ISO date, got: ${d}`);
  }
});

// ─── C2.5: DST next instant ───────────────────────────────────────────────────

test('C2.5: show PATH --from 2027-03-27T12:00:00Z -n 1 --json lists 2027-03-29T00:30:00.000Z first', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '30 2 * * *', timezone: 'Europe/Paris' }] },
    job: { prompt: 'DST test.' },
  });
  const { filePath } = makeTempAgency('dst-test', content);
  const ctx = makeCtx();
  const code = await showVerb([filePath, '--json', '-n', '1', '--from', '2027-03-27T12:00:00Z'], ctx);
  assert.equal(code, 0, `Expected exit 0; err: ${ctx._err.join('')}`);
  const output = JSON.parse(ctx._out.join(''));
  assert.ok(Array.isArray(output.next), 'Expected next array');
  assert.equal(output.next.length, 1);
  assert.equal(output.next[0], '2027-03-29T00:30:00.000Z',
    `Expected 2027-03-29T00:30:00.000Z (spring-forward skips March 28), got: ${output.next[0]}`);
});

// ─── C2.7: Normalized output ──────────────────────────────────────────────────

test('C2.7: show --json paths are absolute', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-abs', content);
  const ctx = makeCtx({ home: '/home/tom' });
  await showVerb([filePath, '--json'], ctx);
  const output = JSON.parse(ctx._out.join(''));
  assert.ok(path.isAbsolute(output.path), `path should be absolute: ${output.path}`);
  assert.ok(path.isAbsolute(output.spec.job.cwd), `job.cwd should be absolute: ${output.spec.job.cwd}`);
});

test('C2.7: show --json prompt-file is inlined as job.prompt', async () => {
  // Create a temp agency with a prompt file
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-pf-test-'));
  const agencyDir = path.join(tmpRoot, '.agency');
  const workflowsDir = path.join(agencyDir, 'workflows');
  fs.mkdirSync(workflowsDir, { recursive: true });
  fs.chmodSync(agencyDir, 0o700);
  fs.chmodSync(workflowsDir, 0o700);

  const promptText = 'This is the prompt from a file.';
  const promptFilePath = path.join(agencyDir, 'my-prompt.txt');
  fs.writeFileSync(promptFilePath, promptText, { mode: 0o600 });

  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { 'prompt-file': 'my-prompt.txt' },
  });
  const filePath = path.join(workflowsDir, 'test-pf.jsonc');
  fs.writeFileSync(filePath, content, { mode: 0o600 });

  const ctx = makeCtx({ home: tmpRoot });
  const code = await showVerb([filePath, '--json'], ctx);
  assert.equal(code, 0, `Expected exit 0; err: ${ctx._err.join('')}`);
  const output = JSON.parse(ctx._out.join(''));
  assert.equal(output.spec.job.prompt, promptText,
    `Expected prompt-file inlined as job.prompt, got: ${output.spec.job.prompt}`);
});

// ─── C2.1: schema verb ───────────────────────────────────────────────────────

test('schema verb outputs valid JSON', async () => {
  const ctx = makeCtx();
  const code = await schemaVerb([], ctx);
  assert.equal(code, 0);
  const schema = JSON.parse(ctx._out.join(''));
  assert.equal(typeof schema, 'object');
  assert.ok(schema.$schema, 'Expected $schema field');
  assert.equal(schema.type, 'object');
  assert.ok(schema.properties, 'Expected properties');
  assert.ok(schema.properties.on, 'Expected on property');
  assert.ok(schema.properties.job, 'Expected job property');
});

test('schema verb schema has required fields', async () => {
  const ctx = makeCtx();
  await schemaVerb([], ctx);
  const schema = JSON.parse(ctx._out.join(''));
  assert.ok(Array.isArray(schema.required), 'Expected required array');
  assert.ok(schema.required.includes('on'), 'on should be required');
  assert.ok(schema.required.includes('job'), 'job should be required');
});

// ─── normalize unit tests ─────────────────────────────────────────────────────

test('normalize: fills all defaults from smallest valid value', () => {
  const value = {
    enabled: true,
    on: {
      schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }],
      dispatch: { inputs: {} },
    },
    if: {},
    window_ms: null,
    permissions: { mode: 'workspace-write', 'add-dirs': [] },
    hold: [],
    outcome: { attempts: 1 },
    context: { previous: 1, diff: true },
    job: { prompt: 'Test.', timeout_ms: 10800000 },
  };
  const norm = normalize(value, {
    file: '/home/tom/.agency/workflows/journal-day.jsonc',
    agencyRoot: '/home/tom',
    agencyId: 'master',
    stem: 'journal-day',
    promptText: 'Test.',
    home: '/home/tom',
  });
  assert.equal(norm.v, 1);
  assert.equal(norm.id, 'master:journal-day');
  assert.equal(norm.stem, 'journal-day');
  assert.equal(norm.agency.id, 'master');
  assert.equal(norm.agency.root, '/home/tom');
  assert.equal(norm.kind, 'workflow');
  assert.equal(norm.state, 'valid');
  assert.equal(norm.spec.enabled, true);
  assert.equal(norm.spec.concurrency.group, 'master:journal-day');
  assert.equal(norm.spec.concurrency.queue, 'single');
  assert.equal(norm.spec.permissions.mode, 'workspace-write');
  assert.deepEqual(norm.spec.permissions.add_dirs, []);
  assert.deepEqual(norm.spec.hold, []);
  assert.equal(norm.spec.outcome.attempts, 1);
  assert.equal(norm.spec.context.previous, 1);
  assert.equal(norm.spec.context.diff, true);
  assert.equal(norm.spec.job.timeout_ms, 10800000);
  assert.equal(norm.spec.job.prompt, 'Test.');
});

test('normalize: name defaults to stem when not set', () => {
  const value = {
    enabled: true,
    on: { schedule: [], dispatch: { inputs: {} } },
    if: {},
    window_ms: null,
    permissions: { mode: 'workspace-write', 'add-dirs': [] },
    hold: [],
    outcome: { attempts: 1 },
    context: { previous: 1, diff: true },
    job: { prompt: 'Test.', timeout_ms: 10800000 },
  };
  const norm = normalize(value, {
    file: '/home/tom/.agency/workflows/my-task.jsonc',
    agencyRoot: '/home/tom',
    agencyId: 'master',
    stem: 'my-task',
    promptText: 'Test.',
    home: '/home/tom',
  });
  assert.equal(norm.spec.name, 'my-task');
});

test('normalize: name from value when set', () => {
  const value = {
    name: 'My Custom Task',
    enabled: true,
    on: { schedule: [], dispatch: { inputs: {} } },
    if: {},
    window_ms: null,
    permissions: { mode: 'workspace-write', 'add-dirs': [] },
    hold: [],
    outcome: { attempts: 1 },
    context: { previous: 1, diff: true },
    job: { prompt: 'Test.', timeout_ms: 10800000 },
  };
  const norm = normalize(value, {
    file: '/home/tom/.agency/workflows/my-task.jsonc',
    agencyRoot: '/home/tom',
    agencyId: 'master',
    stem: 'my-task',
    promptText: 'Test.',
    home: '/home/tom',
  });
  assert.equal(norm.spec.name, 'My Custom Task');
});

// ─── Revision ─────────────────────────────────────────────────────────────────

test('revision: same file+prompt gives same result', () => {
  const f = Buffer.from('file content');
  const p = Buffer.from('prompt content');
  const r1 = revision(f, p);
  const r2 = revision(f, p);
  assert.equal(r1, r2);
});

test('revision: different file content gives different result', () => {
  const p = Buffer.from('prompt content');
  const r1 = revision(Buffer.from('file A'), p);
  const r2 = revision(Buffer.from('file B'), p);
  assert.notEqual(r1, r2);
});

test('revision: null promptBytes differs from empty buffer and matches empty-string formula', () => {
  const f = Buffer.from('file content');
  const rNull = revision(f, null);
  const rEmptyBuf = revision(f, Buffer.from(''));
  // A prompt file that exists but is empty is hashed, differing from no prompt file
  assert.notEqual(rNull, rEmptyBuf);
  const fileHash = createHash('sha256').update(f).digest('hex');
  const expected = createHash('sha256').update(fileHash + '\n').digest('hex').slice(0, 12);
  assert.equal(rNull, expected);
});
