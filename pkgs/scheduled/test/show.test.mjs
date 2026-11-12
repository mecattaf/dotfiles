/**
 * test/show.test.mjs
 * Tests for the `scheduled show` verb: the parsed item, the next instants (C2.5) and absolute paths (C2.7).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { main as showVerb } from '../src/verbs/show.mjs';
import { normalize, revision } from '../src/lib/schema.mjs';

function makeTempAgency(stem, content) {
  const tmpRoot = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'sched-show-test-')));
  const agencyDir = path.join(tmpRoot, '.agency');
  const scheduledDir = path.join(agencyDir, 'scheduled');
  fs.mkdirSync(scheduledDir, { recursive: true });
  fs.chmodSync(agencyDir, 0o700);
  fs.chmodSync(scheduledDir, 0o700);
  const filePath = path.join(scheduledDir, `${stem}.jsonc`);
  fs.writeFileSync(filePath, content, { mode: 0o600 });
  fs.chmodSync(filePath, 0o600);
  return { tmpRoot, agencyDir, scheduledDir, filePath };
}

function makeCtx(overrides = {}) {
  const out = [];
  const err = [];
  return { uid: process.getuid(), home: os.homedir(), inbox: null, now: () => new Date('2026-11-12T00:00:00Z'),
    out: (s) => out.push(s), err: (s) => err.push(s), _out: out, _err: err, ...overrides };
}

const item = (extra = {}) => JSON.stringify({ enabled: false, on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] }, job: { prompt: 'Summarise.' }, ...extra });

test('C2.1: show --json gives the parsed item, its revision, its state and the next instants', async () => {
  const { tmpRoot, filePath } = makeTempAgency('example-weekly', item());
  const ctx = makeCtx({ home: path.dirname(tmpRoot) });
  assert.equal(await showVerb([filePath, '--json', '-n', '2'], ctx), 0, ctx._err.join(''));
  const output = JSON.parse(ctx._out.join(''));
  assert.equal(output.v, 1);
  assert.equal(output.id, `${path.basename(tmpRoot)}:example-weekly`);
  assert.equal(output.state, 'disabled');
  assert.match(output.revision, /^[0-9a-f]{12}$/);
  assert.deepEqual(output.spec, { name: 'example-weekly', enabled: false, on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] }, job: { prompt: 'Summarise.' } });
  assert.deepEqual(output.next, ['2026-11-16T05:00:00.000Z', '2026-11-23T05:00:00.000Z']);
  assert.equal(output.records, null, 'no inbox: no records');
});

test('C2.1: show of an invalid item exits 1 and names the problem', async () => {
  const { filePath } = makeTempAgency('bad', JSON.stringify({ on: {}, job: {} }));
  const ctx = makeCtx();
  assert.equal(await showVerb([filePath], ctx), 1);
  assert.match(ctx._err.join(''), /enabled-required/);
});

test('C2.5: show PATH --from 2027-03-27T12:00:00Z -n 1 --json lists 2027-03-29T00:30:00.000Z first', async () => {
  const { filePath } = makeTempAgency('dst', item({ on: { schedule: [{ cron: '30 2 * * *', timezone: 'Europe/Paris' }] } }));
  const ctx = makeCtx();
  assert.equal(await showVerb([filePath, '--from', '2027-03-27T12:00:00Z', '-n', '2', '--json'], ctx), 0);
  const output = JSON.parse(ctx._out.join(''));
  // 28 March has no 02:30 in Paris (the clocks skip it): the next instant is the 29th.
  assert.equal(output.next[0], '2027-03-29T00:30:00.000Z');
  assert.ok(output.problems.some((p) => p.code === 'dst-gap'));
});

test('C2.7: show --json paths are absolute and a prompt-file is inlined as job.prompt', async () => {
  const { tmpRoot, agencyDir, filePath } = makeTempAgency('pf', item({ job: { 'prompt-file': '.agency/prompts/pf.md' } }));
  fs.mkdirSync(path.join(agencyDir, 'prompts'));
  fs.writeFileSync(path.join(agencyDir, 'prompts', 'pf.md'), 'From the file.');
  const ctx = makeCtx();
  assert.equal(await showVerb([filePath, '--json'], ctx), 0, ctx._err.join(''));
  const output = JSON.parse(ctx._out.join(''));
  assert.ok(path.isAbsolute(output.path));
  assert.equal(output.agency.root, tmpRoot);
  assert.deepEqual(output.spec.job, { 'prompt-file': '.agency/prompts/pf.md', prompt: 'From the file.' });
});

test('normalize: name defaults to the stem; enabled gives the state', () => {
  const value = { enabled: true, on: { schedule: [] }, job: { prompt: 'x' } };
  const norm = normalize(value, { file: '/h/.agency/scheduled/a.jsonc', root: '/h', agency: 'master', stem: 'a', prompt: 'x' });
  assert.equal(norm.id, 'master:a');
  assert.equal(norm.spec.name, 'a');
  assert.equal(norm.state, 'enabled');
  assert.equal(normalize({ ...value, name: 'Named', enabled: false }, { file: '', root: '/h', agency: 'master', stem: 'a', prompt: 'x' }).spec.name, 'Named');
});

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
