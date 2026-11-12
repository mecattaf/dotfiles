// pair.test.mjs — the optional per-item `pair` key: the compute pair an occurrence's work runs on.
//
// An item may name one of the floor's provider-harness pairs; the record carries it as `pair`, and the fork's
// scheduled Source copies it into the Trigger's meta, where the executor picks that pair. An item without `pair`
// writes no `pair`, so the executor's default pair applies. The heartbeat knows the floor's pairs from
// SCHEDULED_PAIRS (ctx.pairs) and refuses an item that names any other, so it never hands off work the
// executor would refuse as "unknown pair".

import test from 'node:test';
import assert from 'node:assert/strict';
import { parseItem, normalize, jsonSchema } from '../src/lib/schema.mjs';
import { pairsOf } from '../src/lib/context.mjs';
import { tick } from '../src/lib/tick.mjs';
import { main as runMain } from '../src/verbs/run.mjs';
import { setupEnv, hourly } from './helpers.mjs';

const PAIRS = ['opus', 'gufo'];
const base = (extra = {}) => ({ enabled: false, on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] }, job: { prompt: 'Say ok.' }, ...extra });
const errorsOf = (value, opts) => parseItem(JSON.stringify(value), opts).problems.filter((p) => p.severity === 'error');

test('P1 an item may name one of the floor\'s pairs; the parsed value keeps it, and an item without one has none', () => {
  const named = parseItem(JSON.stringify(base({ pair: 'gufo' })), { pairs: PAIRS });
  assert.deepEqual(named.problems, []);
  assert.equal(named.value.pair, 'gufo');
  const plain = parseItem(JSON.stringify(base()), { pairs: PAIRS });
  assert.deepEqual(plain.problems, []);
  assert.equal('pair' in plain.value, false);
  // An item without `pair` is valid whether or not any pairs are configured.
  assert.deepEqual(parseItem(JSON.stringify(base())).problems, []);
});

test('P2 a pair the floor does not have is an unknown-pair error that names the floor\'s pairs, with a did-you-mean', () => {
  const unknown = errorsOf(base({ pair: 'gpu' }), { pairs: PAIRS });
  assert.deepEqual(unknown.map((e) => e.code), ['unknown-pair']);
  assert.equal(unknown[0].message, '"pair" "gpu" is not one of the floor\'s pairs (gufo, opus); leave "pair" out to run on the floor\'s default pair.');
  assert.ok(unknown[0].line > 0, 'the problem points at the value');
  const near = errorsOf(base({ pair: 'gufu' }), { pairs: PAIRS });
  assert.equal(near[0].message, '"pair" "gufu" is not one of the floor\'s pairs (gufo, opus); did you mean "gufo"?');
});

test('P3 with no pairs configured any named pair is refused: the heartbeat never hands off a pair it cannot check', () => {
  for (const pairs of [undefined, null, []]) {
    const errs = errorsOf(base({ pair: 'opus' }), { pairs });
    assert.deepEqual(errs.map((e) => [e.code, e.message]), [['unknown-pair',
      '"pair" "opus" cannot be checked: no pairs are configured (SCHEDULED_PAIRS); leave "pair" out to run on the floor\'s default pair.']]);
  }
});

test('P4 a pair that is not a pair name is a type error, whatever the floor\'s pairs', () => {
  for (const pair of ['', 'Gufo', '-gufo', 'gufo-', 'a'.repeat(41), 'g_ufo', 5, null, ['gufo']]) {
    const errs = errorsOf(base({ pair }), { pairs: [...PAIRS, 'Gufo'] });
    assert.deepEqual(errs.map((e) => [e.code, e.message]), [['type',
      '"pair" must be a pair name: lowercase letters and digits, inner hyphens, at most 40 characters.']], JSON.stringify(pair));
  }
  assert.deepEqual(errorsOf(base({ pair: 'a'.repeat(40) }), { pairs: ['a'.repeat(40)] }), []);
});

test('P5 model, profile, priority, env and secrets stay unknown-key errors, and say compute is named with "pair"', () => {
  for (const key of ['model', 'profile', 'priority', 'env', 'secrets']) {
    const errs = errorsOf(base({ [key]: 'x' }), { pairs: PAIRS });
    assert.deepEqual(errs.map((e) => [e.code, e.message]), [['unknown-key',
      `"${key}" is not a scheduled-item key: name one of the floor's compute pairs with "pair", or leave it out for the floor's default pair; priority is the superagent's judgement.`]]);
  }
});

test('P6 the JSON Schema and the show shape carry the optional pair', () => {
  const schema = jsonSchema();
  assert.equal(schema.properties.pair.type, 'string');
  assert.equal(schema.properties.pair.pattern, '^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$');
  assert.equal(schema.required.includes('pair'), false);
  const where = { file: '/h/.agency/scheduled/x.jsonc', root: '/h', agency: 'master', stem: 'x', prompt: 'Say ok.' };
  assert.equal(normalize(parseItem(JSON.stringify(base({ pair: 'gufo' })), { pairs: PAIRS }).value, where).spec.pair, 'gufo');
  assert.equal('pair' in normalize(parseItem(JSON.stringify(base())).value, where).spec, false);
});

test('P7 SCHEDULED_PAIRS names the pairs, separated by spaces or commas; unset or blank names none', () => {
  assert.deepEqual(pairsOf('opus gufo'), ['opus', 'gufo']);
  assert.deepEqual(pairsOf(' opus, gufo ,'), ['opus', 'gufo']);
  assert.equal(pairsOf(undefined), null);
  assert.equal(pairsOf(''), null);
  assert.equal(pairsOf(' , '), null);
});

test('P8 a tick writes the item\'s pair into its record, after text in the fork\'s field order; an item without one writes none', async () => {
  const env = setupEnv();
  try {
    env.ctx.pairs = PAIRS;
    env.item('local', hourly({ pair: 'gufo' }));
    env.item('plain', hourly());
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    const res = await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.equal(res.code, 0, res.lines.join('\n'));
    const local = env.record('master~local@20261112T1200Z.json');
    assert.equal(local.pair, 'gufo');
    assert.deepEqual(Object.keys(local), ['v', 'kind', 'namespace', 'item', 'cwd', 'file', 'due', 'missed', 'revision', 'text', 'pair', 'by', 'at']);
    assert.equal('pair' in env.record('master~plain@20261112T1200Z.json'), false);
  } finally {
    env.cleanup();
  }
});

test('P9 a pair the floor no longer has is refused at the next tick although the file is unchanged, and its waiting record is withdrawn', async () => {
  const env = setupEnv();
  try {
    env.ctx.pairs = PAIRS;
    env.item('local', hourly({ pair: 'gufo' }));
    await tick(env.ctx, { now: new Date('2026-11-12T11:00:00.000Z') });
    await tick(env.ctx, { now: new Date('2026-11-12T12:00:10.000Z') });
    assert.deepEqual(env.records(), ['master~local@20261112T1200Z.json']);
    assert.equal(env.entry('master:local').valid, true);

    // The floor's pairs change (a switch removed gufo); the item file does not.
    env.ctx.pairs = ['opus'];
    const res = await tick(env.ctx, { now: new Date('2026-11-12T13:00:10.000Z') });
    const entry = env.entry('master:local');
    assert.equal(entry.valid, false);
    assert.deepEqual(entry.problems.map((p) => p.code), ['unknown-pair']);
    assert.ok(res.lines.includes('<5>withdrawn occurrence=master~local@20261112T1200Z reason=invalid'), res.lines.join('\n'));
    assert.deepEqual(env.records(), []);

    // Restored: the item is valid again, and the latest instant since the last tick is due.
    env.ctx.pairs = PAIRS;
    await tick(env.ctx, { now: new Date('2026-11-12T14:00:10.000Z') });
    assert.equal(env.entry('master:local').valid, true);
    assert.deepEqual(env.records(), ['master~local@20261112T1400Z.json']);
    assert.equal(env.record('master~local@20261112T1400Z.json').pair, 'gufo');
  } finally {
    env.cleanup();
  }
});

test('P10 scheduled run carries the item\'s pair into the manual record, and refuses an item whose pair the floor does not have', async () => {
  const env = setupEnv();
  try {
    env.ctx.pairs = PAIRS;
    env.item('local', hourly({ enabled: false, pair: 'gufo' }));
    assert.equal(await runMain(['master:local'], env.ctx), 0, env.err.join(''));
    const [name] = env.records();
    const rec = env.record(name);
    assert.equal(rec.kind, 'manual');
    assert.equal(rec.pair, 'gufo');
    assert.deepEqual(Object.keys(rec).slice(-4), ['text', 'pair', 'by', 'at']);

    env.item('far', hourly({ enabled: false, pair: 'gpu' }));
    assert.equal(await runMain(['master:far'], env.ctx), 1);
    assert.match(env.err.join(''), /error\[unknown-pair\]/);
    assert.deepEqual(env.records(), [name]);
  } finally {
    env.cleanup();
  }
});
