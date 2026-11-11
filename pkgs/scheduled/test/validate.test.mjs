/**
 * test/validate.test.mjs
 * Tests for schema parsing, validation, and the validate verb.
 * Covers C2.1-C2.7 (validate-side checks).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Import our modules
import { parseWorkflow, formatProblems, revision } from '../src/lib/schema.mjs';
import { validateFile } from '../src/lib/validate.mjs';
import { main as validateVerb } from '../src/verbs/validate.mjs';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Create a temp agency directory structure:
 *   <tmpdir>/
 *     .agency/
 *       workflows/
 *         <stem>.jsonc
 * Returns { agencyDir, workflowsDir, filePath }
 */
function makeTempAgency(stem, content, { mode = 0o700, fileMode = 0o600 } = {}) {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-test-'));
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

// ─── C2.1: Smallest valid file ───────────────────────────────────────────────

test('C2.1: smallest valid file parses cleanly', () => {
  const text = JSON.stringify({
    on: {
      schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }],
    },
    job: { prompt: 'Summarise last week\'s merged PRs in ~/today.' },
  });
  const { value, problems } = parseWorkflow(text);
  const errors = problems.filter(p => p.severity === 'error');
  assert.equal(errors.length, 0, `Expected no errors, got: ${JSON.stringify(errors)}`);
  // Defaults
  assert.equal(value.enabled, true);
  assert.deepEqual(value.context, { previous: 1, diff: true });
  assert.equal(value.outcome?.attempts ?? 1, 1);
  assert.equal(value.permissions?.mode ?? 'workspace-write', 'workspace-write');
  assert.deepEqual(value.hold ?? [], []);
});

test('C2.1: smallest valid file - job timeout default', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { value } = parseWorkflow(text);
  assert.equal(value.job?.timeout_ms, 3 * 60 * 60 * 1000); // 3h
});

test('C2.1: validate verb exits 0 on smallest valid file', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('fleet-nightly', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 0);
});

// ─── C2.2: "enable" → unknown-key with did-you-mean ─────────────────────────

test('C2.2: "enable" key → unknown-key error with did-you-mean', () => {
  const text = JSON.stringify({
    enable: false,
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { value, problems } = parseWorkflow(text);
  const errors = problems.filter(p => p.severity === 'error' && p.code === 'unknown-key');
  assert.equal(errors.length >= 1, true, 'Expected unknown-key error');
  const e = errors.find(p => p.message.includes('"enable"'));
  assert.ok(e, 'Error about "enable" key not found');
  assert.ok(e.message.includes('did you mean "enabled"'), `Expected did-you-mean suggestion, got: ${e.message}`);
});

test('C2.2: validate verb exits 1 on unknown-key error', async () => {
  const fixturePath = path.join(__dirname, 'fixtures', 'unknown-key-enable.jsonc');
  const content = fs.readFileSync(fixturePath, 'utf8');
  const { filePath } = makeTempAgency('test-wf', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[unknown-key]'), `Expected error[unknown-key] in output, got: ${outText}`);
  assert.ok(outText.includes('did you mean "enabled"'), `Expected did-you-mean, got: ${outText}`);
});

// ─── C2.3: timezone, never, density errors ───────────────────────────────────

test('C2.3: schedule entry without timezone → error timezone', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1' }] },
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const tzErr = problems.find(p => p.code === 'timezone');
  assert.ok(tzErr, 'Expected timezone error');
  assert.equal(tzErr.severity, 'error');
});

test('C2.3: cron 0 0 31 2 * → error never', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'never-feb31.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-never', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[never]'), `Expected error[never], got: ${outText}`);
});

test('C2.3: density - entries < 60 min apart → error density', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'density.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-density', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[density]'), `Expected error[density], got: ${outText}`);
});

// ─── C2.4: Various error codes ───────────────────────────────────────────────

test('C2.4: cancel-in-progress: true → error cancel', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'cancel-in-progress.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-cancel', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[cancel]'), `Expected error[cancel], got: ${outText}`);
});

test('C2.4: attempts > 1 without check → error attempts', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'attempts-no-check.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-attempts', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[attempts]'), `Expected error[attempts], got: ${outText}`);
});

test('C2.4: job with both prompt and prompt-file → error job', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'job-both-prompt.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-job-both', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[job]'), `Expected error[job], got: ${outText}`);
});

test('C2.4: model key → error unknown-key', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'banned-model-key.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-model', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[unknown-key]'), `Expected error[unknown-key], got: ${outText}`);
});

test('C2.4: profile key → error unknown-key', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    profile: 'some-profile',
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'unknown-key' && p.message.includes('"profile"'));
  assert.ok(e, 'Expected unknown-key for profile');
});

test('C2.4: priority key → error unknown-key', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    priority: 1,
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'unknown-key');
  assert.ok(e, 'Expected unknown-key for priority');
});

test('C2.4: env key → error unknown-key', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    env: { FOO: 'bar' },
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'unknown-key');
  assert.ok(e, 'Expected unknown-key for env');
});

test('C2.4: secrets key → error unknown-key', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    secrets: ['MY_SECRET'],
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'unknown-key');
  assert.ok(e, 'Expected unknown-key for secrets');
});

test('C2.4: window outside 1h-30d → error type', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'window-too-large.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-window', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  assert.equal(code, 1);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('error[type]'), `Expected error[type], got: ${outText}`);
});

test('C2.4: window below 1h (e.g. 59m) → error type', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    window: '59m',
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'type' && p.message.includes('"window"'));
  assert.ok(e, 'Expected type error for 59m window');
});

test('C2.4: proposed/ file without x-proposal → error proposal', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'proposal-no-xproposal.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-proposal', content);
  const ctx = makeCtx();
  // Parse in proposal mode
  const text = fs.readFileSync(filePath, 'utf8');
  const { problems } = parseWorkflow(text, { proposal: true });
  const e = problems.find(p => p.code === 'proposal');
  assert.ok(e, `Expected proposal error, got: ${JSON.stringify(problems)}`);
});

test('C2.4: x-* keys pass validation', () => {
  const text = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    'x-custom-data': { foo: 'bar' },
    'x-proposal': { by: 'agent', at: '2026-01-01', why: 'test' },
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const errors = problems.filter(p => p.severity === 'error');
  assert.equal(errors.length, 0, `Expected no errors, got: ${JSON.stringify(errors)}`);
});

// ─── C2.5: DST gap warning ───────────────────────────────────────────────────

test('C2.5: 30 2 * * * in Europe/Paris → warning dst-gap', async () => {
  const content = fs.readFileSync(path.join(__dirname, 'fixtures', 'dst-gap.jsonc'), 'utf8');
  const { filePath } = makeTempAgency('test-dst', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath], ctx);
  // This is a warning only, so should exit 0
  assert.equal(code, 0);
  const outText = ctx._out.join('');
  assert.ok(outText.includes('warning[dst-gap]'), `Expected warning[dst-gap], got: ${outText}`);
});

// ─── C2.6: Ownership errors ───────────────────────────────────────────────────

test('C2.6: file writable by group → error ownership', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-ownership', content, { fileMode: 0o664 }); // group-writable
  fs.chmodSync(filePath, 0o664);
  const { problems } = await validateFile(filePath, { uid: process.getuid() });
  const e = problems.find(p => p.code === 'ownership');
  assert.ok(e, `Expected ownership error, got: ${JSON.stringify(problems)}`);
});

test('C2.6: workflows/ dir writable by others → error ownership', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath, workflowsDir } = makeTempAgency('test-ownership2', content);
  fs.chmodSync(workflowsDir, 0o757); // world-writable
  const { problems } = await validateFile(filePath, { uid: process.getuid() });
  const e = problems.find(p => p.code === 'ownership');
  assert.ok(e, `Expected ownership error, got: ${JSON.stringify(problems)}`);
});

test('C2.6: .agency/ dir writable by group → error ownership', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath, agencyDir } = makeTempAgency('test-ownership3', content);
  fs.chmodSync(agencyDir, 0o770); // group-writable
  const { problems } = await validateFile(filePath, { uid: process.getuid() });
  const e = problems.find(p => p.code === 'ownership');
  assert.ok(e, `Expected ownership error, got: ${JSON.stringify(problems)}`);
});

// ─── C2.7: Defaults, revision, prompt-file inlining ─────────────────────────

test('C2.7: revision is first 12 hex of sha256(sha256(file)+newline+sha256(prompt-bytes or empty))', () => {
  const fileContent = Buffer.from('hello file');
  const promptContent = Buffer.from('hello prompt');
  const rev = revision(fileContent, promptContent);
  assert.equal(typeof rev, 'string');
  assert.equal(rev.length, 12);
  assert.ok(/^[0-9a-f]{12}$/.test(rev), `Revision should be 12 hex chars, got: ${rev}`);
});

test('C2.7: revision without prompt-file uses empty string', () => {
  const fileContent = Buffer.from('test file content');
  const rev = revision(fileContent, null);
  assert.equal(rev.length, 12);
  assert.ok(/^[0-9a-f]{12}$/.test(rev));
});

test('C2.7: validate JSON output includes revision', async () => {
  const content = JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-rev', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath, '--json'], ctx);
  assert.equal(code, 0);
  const result = JSON.parse(ctx._out.join(''));
  assert.equal(result.v, 1);
  assert.equal(result.results.length, 1);
  const r = result.results[0];
  assert.equal(r.valid, true);
  assert.ok(r.revision && /^[0-9a-f]{12}$/.test(r.revision), `Expected 12-hex revision, got: ${r.revision}`);
});

test('C2.7: validate --json output has correct structure', async () => {
  // Provide an invalid file to test error JSON structure
  const content = JSON.stringify({
    enable: false, // unknown-key
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Test.' },
  });
  const { filePath } = makeTempAgency('test-invalid', content);
  const ctx = makeCtx();
  const code = await validateVerb([filePath, '--json'], ctx);
  assert.equal(code, 1);
  const result = JSON.parse(ctx._out.join(''));
  assert.equal(result.v, 1);
  const r = result.results[0];
  assert.equal(r.valid, false);
  assert.ok(r.problems.length > 0);
  const p = r.problems[0];
  assert.ok(['level', 'code', 'line', 'col', 'message'].every(k => k in p), `Missing fields in problem: ${JSON.stringify(p)}`);
});

// ─── Concurrency defaults ─────────────────────────────────────────────────────

test('C2.1: concurrency group defaults to workflow id in normalize', async () => {
  const { normalize } = await import('../src/lib/schema.mjs');
  const value = {
    enabled: true,
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }], dispatch: { inputs: {} } },
    if: {},
    window_ms: null,
    permissions: { mode: 'workspace-write', 'add-dirs': [] },
    hold: [],
    outcome: { attempts: 1 },
    context: { previous: 1, diff: true },
    job: { prompt: 'Test.', timeout_ms: 10800000 },
  };
  const norm = normalize(value, {
    file: '/home/tom/.agency/workflows/test.jsonc',
    agencyRoot: '/home/tom',
    agencyId: 'master',
    stem: 'test',
    promptText: 'Test.',
    home: '/home/tom',
  });
  assert.equal(norm.spec.concurrency.group, 'master:test');
  assert.equal(norm.spec.concurrency.queue, 'single');
  assert.equal(norm.spec.permissions.mode, 'workspace-write');
  assert.equal(norm.spec.job.timeout_ms, 10800000);
  assert.equal(norm.spec.context.previous, 1);
  assert.equal(norm.spec.context.diff, true);
  assert.equal(norm.spec.outcome.attempts, 1);
});

// ─── Additional validation edge cases ────────────────────────────────────────

test('parse error on malformed JSON', () => {
  const text = '{ "on": { "schedule": [ { bad json } ] } }';
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'parse');
  assert.ok(e, 'Expected parse error');
});

test('no-trigger error when on has no schedule or workflow_dispatch', () => {
  const text = JSON.stringify({
    on: {},
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'no-trigger');
  assert.ok(e, 'Expected no-trigger error');
});

test('event error for unknown on.* keys', () => {
  const text = JSON.stringify({
    on: { push: { branches: ['main'] } },
    job: { prompt: 'Test.' },
  });
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'event');
  assert.ok(e, 'Expected event error');
});

test('duplicate-key error', () => {
  // jsonc-parser preserves last value on duplicates; we detect at the tree level
  const text = `{
    "on": { "schedule": [{ "cron": "0 6 * * 1", "timezone": "UTC" }] },
    "job": { "prompt": "Test." },
    "job": { "prompt": "Test 2." }
  }`;
  const { problems } = parseWorkflow(text);
  const e = problems.find(p => p.code === 'duplicate-key');
  assert.ok(e, 'Expected duplicate-key error');
});

test('formatProblems produces compiler-style output', () => {
  const problems = [
    { severity: 'error', code: 'unknown-key', line: 14, col: 5, message: '"enable" is not a key here; did you mean "enabled"?' },
  ];
  const lines = formatProblems('/home/tom/.agency/workflows/fleet-nightly.jsonc', problems);
  const output = lines.join('\n');
  assert.ok(output.includes('error[unknown-key]'), output);
  assert.ok(output.includes('14:5'), output);
  assert.ok(output.includes('1 error, 0 warnings'), output);
});

test('x-proposal fields are preserved through parsing', () => {
  const text = JSON.stringify({
    'x-proposal': { by: 'agent-1', at: '2026-01-01T00:00:00Z', why: 'Automation' },
    enabled: false,
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'UTC' }] },
    job: { prompt: 'Test.' },
  });
  const { value, problems } = parseWorkflow(text);
  const errors = problems.filter(p => p.severity === 'error');
  assert.equal(errors.length, 0, JSON.stringify(errors));
  assert.deepEqual(value['x-proposal'], { by: 'agent-1', at: '2026-01-01T00:00:00Z', why: 'Automation' });
});

test('C2.4: validate PATH on a file in proposed/ judges it as a proposal (x-proposal required)', async () => {
  const body = { enabled: false, on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] }, job: { prompt: 'Test.' } };
  const { workflowsDir, tmpRoot } = makeTempAgency('unused', JSON.stringify(body));
  try {
    const proposed = path.join(workflowsDir, 'proposed');
    fs.mkdirSync(proposed, { mode: 0o700 });
    fs.chmodSync(proposed, 0o700);
    const bare = path.join(proposed, 'bare.jsonc');
    fs.writeFileSync(bare, JSON.stringify(body), { mode: 0o600 });
    const withMark = path.join(proposed, 'marked.jsonc');
    fs.writeFileSync(withMark, JSON.stringify({ ...body, 'x-proposal': { by: 'agent', at: '2026-11-12T00:00:00Z', why: 'test' } }), { mode: 0o600 });
    const ctx = makeCtx();
    assert.equal(await validateVerb([bare], ctx), 1, 'a proposal without x-proposal is refused');
    assert.equal(await validateVerb([withMark], makeCtx()), 0, makeCtx()._out.join(''));
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
});
