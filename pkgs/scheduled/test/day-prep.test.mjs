// The master agency's day-prep workflow (.agency/workflows/day-prep.workflow.js) and the nudge item that asks the
// main Session to start it (.agency/scheduled/day-prep.jsonc). The nudge is checked here with the scheduled CLI's
// own validator. The script is run through the superagent fork's vendored interpreter (src/workflow) with its
// MockBackend, so its meta, its nodes and its result are the ones the floor would see; nothing calls a model.
// Those tests need a checkout of the fork with its dependencies installed, and Node's TypeScript transform:
//   DSH_SUPERAGENT_SRC=<fork checkout> node --experimental-transform-types --test test/day-prep.test.mjs
// Without DSH_SUPERAGENT_SRC they are skipped (the flake check has no fork checkout).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';

const AGENCY = fileURLToPath(new URL('./fixtures/master/.agency', import.meta.url));
const SCRIPT = join(AGENCY, 'workflows/day-prep.workflow.js');
const NUDGE = join(AGENCY, 'scheduled/day-prep.jsonc');
const SRC = process.env.DSH_SUPERAGENT_SRC;
const skip = SRC ? false : 'DSH_SUPERAGENT_SRC names no superagent fork checkout';
const READERS = ['journal', 'projects', 'chats', 'overnight'];

const interpreter = () => import(join(SRC, 'src/workflow/index.ts'));
const source = () => readFileSync(SCRIPT, 'utf8');

async function run(args, respond) {
  const { runWorkflow, MockBackend } = await interpreter();
  const backend = new MockBackend({ turns: () => 0, booleanValue: true, respond });
  const r = await runWorkflow(source(), { backend, args, maxAttempts: 1, concurrency: 4 });
  return { ...r, backendCalls: backend.calls };
}

test('the nudge validates, is off, and asks the main Session to start the script with this Trigger as trigger_id', async () => {
  const r = await validateFile(NUDGE);
  assert.deepEqual(r.problems, []);
  assert.equal(r.value.enabled, false);
  assert.match(r.prompt, /orchestrator_workflow_start/);
  assert.match(r.prompt, /\.agency\/workflows\/day-prep\.workflow\.js/);
  assert.match(r.prompt, /trigger_id/);
  assert.match(r.prompt, /"date"/);
});

test('meta names the workflow and its two phases', { skip }, async () => {
  const { extractMeta } = await interpreter();
  const meta = extractMeta(source());
  assert.equal(meta.name, 'day-prep');
  assert.deepEqual(meta.phases.map((p) => p.title), ['read', 'write']);
});

test('a missing or impossible date fails the run before any node', { skip }, async () => {
  for (const args of [undefined, {}, { date: '12 Nov 2026' }, { date: '2026-02-30' }]) {
    const r = await run(args);
    assert.equal(r.status, 'failed', JSON.stringify(args));
    assert.match(r.error, /args\.date/);
    assert.equal(r.backendCalls.length, 0);
  }
});

test('four read-only readers on yesterday, then one writer of the day folder\'s day-prep.md', { skip }, async () => {
  const r = await run({ date: '2026-11-13' });
  assert.equal(r.status, 'completed', r.error);
  const calls = r.backendCalls;
  assert.deepEqual(calls.map((c) => c.opts.label), [...READERS, 'write']);
  assert.deepEqual(calls.map((c) => c.phase), ['read', 'read', 'read', 'read', 'write']);
  for (const c of calls) assert.ok(c.opts.schema, `${c.opts.label} has a schema`);
  for (const c of calls.slice(0, 4)) {
    assert.match(c.prompt, /Change nothing/, c.opts.label);
    assert.match(c.prompt, /2026-11-12/, c.opts.label);
  }
  assert.match(calls[0].prompt, /~\/notes\/journal\/2026\/11\/12\//);
  assert.match(calls[2].prompt, /~\/notes\/journal\/2026\/11\/12\/raw-chat-index\.jsonl/);
  assert.match(calls[2].prompt, /pointer-only/);
  const write = calls[4].prompt;
  assert.match(write, /~\/notes\/journal\/2026\/11\/13\/day-prep\.md/);
  assert.match(write, /# Assistant draft/);
  assert.match(write, /never in Tom's voice/i);
  assert.match(write, /already exists/);
  assert.deepEqual(r.result.missing, []);
  assert.equal(r.result.date, '2026-11-13');
  assert.equal(r.result.path, '~/notes/journal/2026/11/13/day-prep.md');
  assert.equal(r.result.written, true);
});

test('yesterday crosses a month and a year', { skip }, async () => {
  const r = await run({ date: '2027-01-01' });
  assert.equal(r.status, 'completed', r.error);
  assert.match(r.backendCalls[0].prompt, /~\/notes\/journal\/2026\/12\/31\//);
  assert.match(r.backendCalls[4].prompt, /~\/notes\/journal\/2027\/01\/01\/day-prep\.md/);
});

test('a reader with no answer is named to the writer and in the result; the writer still runs', { skip }, async () => {
  const r = await run({ date: '2026-11-13' }, (c) => (c.opts.label === 'chats' ? { error: 'unit failed' } : undefined));
  assert.equal(r.status, 'completed', r.error);
  assert.deepEqual(r.result.missing, ['chats']);
  assert.equal(r.backendCalls.at(-1).opts.label, 'write');
  assert.match(r.backendCalls.at(-1).prompt, /No answer from: chats/);
});

test('a writer with no answer leaves the result unwritten', { skip }, async () => {
  const r = await run({ date: '2026-11-13' }, (c) => (c.opts.label === 'write' ? { error: 'unit failed' } : undefined));
  assert.equal(r.status, 'completed', r.error);
  assert.equal(r.result.written, false);
  assert.match(r.result.reason, /no answer/);
});
