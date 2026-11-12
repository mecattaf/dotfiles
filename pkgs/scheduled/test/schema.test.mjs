// schema.test.mjs — scheduled item schema v1 (docs/scheduled.md, An item; rows S1-S10), and the validate verb.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseItem, formatProblems, revision, jsonSchema } from '../src/lib/schema.mjs';
import { validateFile } from '../src/lib/validate.mjs';
import { main as validateVerb } from '../src/verbs/validate.mjs';
import { main as schemaVerb } from '../src/verbs/schema.mjs';

const SMALLEST = `{
  "enabled": false,
  "on": { "schedule": [ { "cron": "0 * * * *", "timezone": "Europe/Paris" } ] },
  "job": { "prompt": "Reply READY and end." }
}
`;

const base = (extra = {}) => ({ enabled: false, on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] }, job: { prompt: 'Say ok.' }, ...extra });
const errors = (text) => parseItem(typeof text === 'string' ? text : JSON.stringify(text)).problems.filter((p) => p.severity === 'error');

/** `<tmp>/.agency/scheduled/<stem>.jsonc` with private modes; returns the paths. */
function agencyWith(stem, content, { dirMode = 0o700, fileMode = 0o600 } = {}) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'sched-schema-')));
  const agency = path.join(root, '.agency');
  const dir = path.join(agency, 'scheduled');
  fs.mkdirSync(dir, { recursive: true });
  fs.chmodSync(agency, dirMode);
  fs.chmodSync(dir, dirMode);
  const file = path.join(dir, `${stem}.jsonc`);
  fs.writeFileSync(file, content);
  fs.chmodSync(file, fileMode);
  return { root, agency, dir, file, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('S1 the smallest valid item parses with no problem and revision is 12 hex', async () => {
  const { value, problems } = parseItem(SMALLEST);
  assert.deepEqual(problems, []);
  assert.deepEqual(value, { enabled: false, on: { schedule: [{ cron: '0 * * * *', timezone: 'Europe/Paris' }] }, job: { prompt: 'Reply READY and end.' } });
  const a = agencyWith('smallest', SMALLEST);
  try {
    const res = await validateFile(a.file);
    assert.deepEqual(res.problems, []);
    assert.equal(res.prompt, 'Reply READY and end.');
    assert.match(res.revision, /^[0-9a-f]{12}$/);
    assert.equal(res.revision, revision(Buffer.from(SMALLEST), null));
  } finally {
    a.cleanup();
  }
});

test('S2 an item without enabled is an error enabled-required', () => {
  const { enabled, ...rest } = base();
  const errs = errors(rest);
  assert.deepEqual(errs.map((e) => e.code), ['enabled-required']);
  assert.match(errs[0].message, /never armed by omission/);
  assert.deepEqual(errors(base({ enabled: 'yes' })).map((e) => e.code), ['type']);
});

test('S3 a workflow key is an unknown-key error whose message says workflow scripts start on a request to the superagent', () => {
  const errs = errors(base({ workflow: 'nightly.js' }));
  assert.equal(errs.length, 1);
  assert.equal(errs[0].code, 'unknown-key');
  assert.equal(errs[0].message, '"workflow" is not a scheduled-item key: a workflow script starts on a request to the superagent that names the script and the agency, never from a scheduled item.');
});

test('S4 each removed key (if, window, concurrency, permissions, hold, outcome, context, on.workflow_dispatch, job.cwd, job.timeout) is a removed-key error naming where its intent goes', () => {
  const inPrompt = 'write the condition into job.prompt; the superagent judges it when the occurrence arrives.';
  const cases = [
    [base({ if: { idle: true } }), `"if" was removed: ${inPrompt}`],
    [base({ window: '2h' }), `"window" was removed: ${inPrompt}`],
    [base({ hold: ['x'] }), `"hold" was removed: ${inPrompt}`],
    [base({ outcome: { goal: 'x' } }), `"outcome" was removed: ${inPrompt}`],
    [base({ context: { previous: 1 } }), `"context" was removed: ${inPrompt}`],
    [base({ concurrency: 'x' }), '"concurrency" was removed: the floor\'s executor.maxWorkers is the only cap.'],
    [base({ permissions: { mode: 'danger-full-access' } }), '"permissions" was removed: workers run with the floor\'s full permissions.'],
    [base({ on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }], workflow_dispatch: {} } }), '"on.workflow_dispatch" was removed: any item can be run now with "scheduled run <agency>:<item>".'],
    [base({ job: { prompt: 'x', cwd: '/tmp' } }), '"job.cwd" was removed: the agency folder is always the working directory.'],
    [base({ job: { prompt: 'x', timeout: '1h' } }), '"job.timeout" was removed: a worker ends when its work is done.'],
  ];
  for (const [item, message] of cases) {
    const errs = errors(item);
    assert.deepEqual(errs.map((e) => [e.code, e.message]), [['removed-key', message]]);
    assert.ok(errs[0].line > 0, 'the problem points at the key');
  }
});

test('S5 model, profile, priority, pair, env and secrets are unknown-key errors that say work runs on the default pair', () => {
  for (const key of ['model', 'profile', 'priority', 'pair', 'env', 'secrets']) {
    const errs = errors(base({ [key]: 'x' }));
    assert.deepEqual(errs.map((e) => [e.code, e.message]), [['unknown-key',
      `"${key}" is not a scheduled-item key: scheduled work runs on the floor's default pair, and priority is the superagent's judgement.`]]);
  }
  // Any other unknown key gets a did-you-mean.
  assert.match(errors(base({ enable: true }))[0].message, /did you mean "enabled"\?/);
});

test('S6 x-* keys are free and kept; $schema and name are allowed', () => {
  const { value, problems } = parseItem(JSON.stringify(base({ $schema: './schema.json', name: 'Probe', 'x-owner': { why: 'kept' } })));
  assert.deepEqual(problems, []);
  assert.deepEqual(value['x-owner'], { why: 'kept' });
  assert.equal(value.name, 'Probe');
  assert.deepEqual(errors(base({ name: '' })).map((e) => e.code), ['type']);
});

test('S7 job needs exactly one of prompt and prompt-file; a prompt over 32 KiB is an error', () => {
  assert.deepEqual(errors(base({ job: {} })).map((e) => e.code), ['job']);
  assert.match(errors(base({ job: { prompt: 'x', 'prompt-file': 'p.md' } }))[0].message, /not both/);
  assert.deepEqual(errors(base({ job: { prompt: '' } })).map((e) => e.code), ['job']);
  assert.deepEqual(errors(base({ job: { prompt: 'é'.repeat(16 * 1024) + 'x' } })).map((e) => e.code), ['job']);
  assert.deepEqual(errors(base({ job: { prompt: 'x'.repeat(32 * 1024) } })), []);
  assert.equal(parseItem(JSON.stringify(base({ job: { prompt: ['a', 'b'] } }))).value.job.prompt, 'a\nb');
});

test('S8 prompt-file resolves inside the agency; a ../ escape and a symlink out are errors', async () => {
  const item = (pf) => JSON.stringify(base({ job: { 'prompt-file': pf } }));
  const a = agencyWith('pf', item('.agency/prompts/pf.md'));
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-outside-'));
  try {
    fs.mkdirSync(path.join(a.agency, 'prompts'));
    fs.writeFileSync(path.join(a.agency, 'prompts', 'pf.md'), 'From the file.\n');
    let res = await validateFile(a.file);
    assert.deepEqual(res.problems, []);
    assert.equal(res.prompt, 'From the file.\n');
    assert.notEqual(res.revision, revision(fs.readFileSync(a.file), null), 'the prompt bytes are in the revision');

    fs.writeFileSync(path.join(outside, 'secret.md'), 'outside');
    fs.writeFileSync(a.file, item('../' + path.basename(outside) + '/secret.md'));
    res = await validateFile(a.file);
    assert.match(res.problems.find((p) => p.severity === 'error').message, /leaves the agency folder/);

    fs.symlinkSync(path.join(outside, 'secret.md'), path.join(a.agency, 'prompts', 'link.md'));
    fs.writeFileSync(a.file, item('.agency/prompts/link.md'));
    res = await validateFile(a.file);
    assert.match(res.problems.find((p) => p.severity === 'error').message, /resolves outside the agency folder/);

    fs.writeFileSync(a.file, item('.agency/prompts/missing.md'));
    res = await validateFile(a.file);
    assert.match(res.problems.find((p) => p.severity === 'error').message, /does not exist/);
    assert.equal(res.value, null);
  } finally {
    a.cleanup();
    fs.rmSync(outside, { recursive: true, force: true });
  }
});

test('S9 on.schedule needs at least one entry, each with a timezone; density under 60 min, never and dst-gap keep their codes', async () => {
  assert.deepEqual(errors(base({ on: {} })).map((e) => e.code), ['no-trigger']);
  assert.deepEqual(errors(base({ on: { schedule: [] } })).map((e) => e.code), ['type']);
  assert.deepEqual(errors(base({ on: { schedule: [{ cron: '0 * * * *' }] } })).map((e) => e.code), ['timezone']);
  const codes = async (schedule) => {
    const a = agencyWith('c', JSON.stringify(base({ on: { schedule } })));
    try {
      return (await validateFile(a.file)).problems.map((p) => `${p.severity}:${p.code}`);
    } finally {
      a.cleanup();
    }
  };
  assert.deepEqual(await codes([{ cron: '*/30 * * * *', timezone: 'UTC' }]), ['error:density']);
  assert.deepEqual(await codes([{ cron: '0 * * * *', timezone: 'UTC' }, { cron: '30 * * * *', timezone: 'UTC' }]), ['error:density']);
  assert.deepEqual(await codes([{ cron: '0 0 31 2 *', timezone: 'UTC' }]), ['error:never']);
  assert.deepEqual(await codes([{ cron: '30 2 * * *', timezone: 'Europe/Paris' }]), ['warning:dst-gap']);
  assert.deepEqual(await codes([{ cron: '0 2 * * *', timezone: 'Mars/Olympus' }]), ['error:timezone']);
});

test('S10 scheduled schema prints a JSON Schema whose required keys are enabled, on and job', async () => {
  const out = [];
  assert.equal(await schemaVerb([], { out: (s) => out.push(s) }), 0);
  const schema = JSON.parse(out.join(''));
  assert.deepEqual(schema, jsonSchema());
  assert.equal(schema.$id, 'scheduled-item.v1');
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
  assert.deepEqual(schema.required, ['enabled', 'on', 'job']);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.patternProperties, { '^x-': {} });
  assert.deepEqual(Object.keys(schema.properties).sort(), ['$schema', 'enabled', 'job', 'name', 'on']);
});

test('a duplicate key, malformed JSONC and a non-object are errors; comments and trailing commas are JSONC', () => {
  assert.deepEqual(errors('{ "enabled": false, "enabled": true, "on": { "schedule": [ { "cron": "0 * * * *", "timezone": "UTC" } ] }, "job": { "prompt": "x" } }').map((e) => e.code), ['duplicate-key']);
  assert.deepEqual(errors('{ "enabled": ').map((e) => e.code).slice(0, 1), ['parse']);
  assert.deepEqual(errors('[1]').map((e) => e.code), ['parse']);
  assert.deepEqual(errors('// note\n{ "enabled": false, "on": { "schedule": [ { "cron": "0 * * * *", "timezone": "UTC", }, ], }, "job": { "prompt": "x", }, }'), []);
});

test('ownership: a group-writable scheduled/ or item, or a file of another uid, is an ownership error', async () => {
  let a = agencyWith('own', SMALLEST, { dirMode: 0o770 });
  try {
    assert.equal((await validateFile(a.file)).problems[0].code, 'ownership');
  } finally {
    a.cleanup();
  }
  a = agencyWith('own', SMALLEST, { fileMode: 0o666 });
  try {
    assert.equal((await validateFile(a.file)).problems[0].code, 'ownership');
    fs.chmodSync(a.file, 0o600);
    assert.equal((await validateFile(a.file, { uid: process.getuid() + 1 })).problems[0].code, 'ownership');
  } finally {
    a.cleanup();
  }
});

test('formatProblems produces compiler-style output', () => {
  const lines = formatProblems('/x/a.jsonc', errors(base({ window: '1h' })));
  assert.match(lines[0], /^\/x\/a\.jsonc:\d+:\d+: error\[removed-key\]:$/);
  assert.equal(lines.at(-1), '/x/a.jsonc: 1 error, 0 warnings');
});

test('validate verb: exit 0 for a valid file, 1 for errors, JSON results name the item', async () => {
  const good = agencyWith('good', SMALLEST);
  const bad = agencyWith('bad', JSON.stringify(base({ model: 'opus' })));
  try {
    const out = [];
    const ctx = { uid: process.getuid(), home: os.homedir(), out: (s) => out.push(s), err: () => {} };
    assert.equal(await validateVerb([good.file], ctx), 0);
    out.length = 0;
    assert.equal(await validateVerb(['--json', good.file, bad.file], ctx), 1);
    const { results } = JSON.parse(out.join(''));
    assert.deepEqual(results.map((r) => [r.item, r.valid]), [['good', true], ['bad', false]]);
    assert.equal(results[1].problems[0].code, 'unknown-key');
  } finally {
    good.cleanup();
    bad.cleanup();
  }
});

test('S9 a symlinked item file is refused as a symbolic link, not as group-writable', async () => {
  const a = agencyWith('real', SMALLEST);
  try {
    const link = path.join(a.dir, 'linked.jsonc');
    fs.symlinkSync(a.file, link);
    const res = await validateFile(link);
    const owner = res.problems.filter((p) => p.code === 'ownership');
    assert.equal(owner.length, 1, JSON.stringify(res.problems));
    assert.match(owner[0].message, /is a symbolic link/);
    assert.doesNotMatch(owner[0].message, /writable by group/);
  } finally {
    a.cleanup();
  }
});
