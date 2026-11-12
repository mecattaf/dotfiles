// A synthetic master agency: three example items that cover the item schema's paths (a daily and an
// hourly cron, an inline prompt and a prompt-file, a reader of the header's time, an item with no name).
// Real items live in an agency's .agency/scheduled/ and never in this repository; every one starts with
// "enabled": false, as these do, so nothing runs unattended before an item is enabled.
import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, chmodSync, readdirSync, readFileSync, statSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';
import { discover } from '../src/lib/discover.mjs';
import { tick } from '../src/lib/tick.mjs';
import { main as validateVerb } from '../src/verbs/validate.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));
const FILES = ['example-daily.jsonc', 'example-hourly.jsonc', 'example-inert.jsonc'];

function home() {
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-baseline-'));
  cpSync(FIXTURE, dir, { recursive: true });
  const walk = (p) => {
    const st = statSync(p);
    chmodSync(p, st.isDirectory() ? 0o700 : 0o600);
    if (st.isDirectory()) for (const e of readdirSync(p)) walk(join(p, e));
  };
  walk(dir);
  return dir;
}

test('C6.1: every fixture item validates with zero problems and reads enabled false', async () => {
  const h = home();
  try {
    for (const f of FILES) {
      const r = await validateFile(join(h, '.agency/scheduled', f));
      assert.deepEqual(r.problems, [], f);
      assert.equal(r.value.enabled, false, f);
      assert.ok(r.prompt.length > 0, f);
    }
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C6.1: the items are master:example-daily, master:example-hourly and master:example-inert; example-inert says it is inert', async () => {
  const h = home();
  try {
    const d = await discover({ home: h, uid: process.getuid() });
    assert.deepEqual(d.files.map((f) => f.id), FILES.map((f) => `master:${f.replace('.jsonc', '')}`));
    assert.deepEqual(d.problems, []);
    assert.match(readFileSync(join(h, '.agency/scheduled/example-inert.jsonc'), 'utf8'), /INERT/);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

// The fork's scheduled Source writes the header's second line as "Due <iso>; …" for an occurrence and as
// "Requested <iso> by …" for `scheduled run`, so an item that reads a time from the header must name both.
test('C6.1: an item that reads a time from the header names both second lines, Due and Requested', async () => {
  const h = home();
  try {
    const readers = [];
    for (const f of FILES) {
      const { prompt } = await validateFile(join(h, '.agency/scheduled', f));
      if (!/\bDue\b/.test(prompt)) continue;
      readers.push(f);
      assert.match(prompt, /\bDue or Requested time\b/, f);
    }
    assert.deepEqual(readers, ['example-daily.jsonc']);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C6.1: the fixture items cover a daily and an hourly cron, prompt lines, a prompt string and a prompt-file', async () => {
  const h = home();
  try {
    const at = (f) => join(h, '.agency/scheduled', f);
    const daily = await validateFile(at('example-daily.jsonc'));
    const hourly = await validateFile(at('example-hourly.jsonc'));
    const inert = await validateFile(at('example-inert.jsonc'));
    assert.deepEqual(daily.value.on.schedule, [{ cron: '0 6 * * *', timezone: 'Europe/Paris' }]);
    assert.match(readFileSync(at('example-daily.jsonc'), 'utf8'), /"prompt": \[/);
    assert.equal(daily.value.name, 'Example: daily summary');
    // Hourly sits on the density bound: instants exactly 60 min apart pass, a half hour more does not.
    assert.deepEqual(hourly.value.on.schedule, [{ cron: '0 * * * *', timezone: 'UTC' }]);
    assert.equal(hourly.value.job['prompt-file'], '.agency/prompts/example-hourly.md');
    assert.equal(hourly.prompt, readFileSync(join(h, '.agency/prompts/example-hourly.md'), 'utf8'));
    assert.ok(hourly.promptBytes.length > 0);
    writeFileSync(at('example-hourly.jsonc'), readFileSync(at('example-hourly.jsonc'), 'utf8').replace('"0 * * * *"', '"0,30 * * * *"'));
    assert.ok((await validateFile(at('example-hourly.jsonc'))).problems.some((p) => p.code === 'density'));
    assert.match(readFileSync(at('example-inert.jsonc'), 'utf8'), /"prompt": "/);
    assert.equal(inert.value.name, undefined);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('R-S5: with every item enabled false, ticks hand off nothing and call no dshd', async () => {
  const h = home();
  try {
    const inbox = join(h, '.agency/state/master/inbox/scheduled');
    const calls = [];
    const ctx = { home: h, stateDir: join(h, 'state'), inbox, floorInstance: 'floor', env: {}, uid: process.getuid(),
      machineIdFile: '/nonexistent', dshd: '/nonexistent', now: () => new Date() };
    const run = async (argv) => { calls.push(argv); return { code: 0, stdout: '{"state":"stopped"}', stderr: '' }; };
    for (const now of ['2026-11-12T20:00:00Z', '2026-11-13T06:00:00Z', '2026-11-14T06:00:00Z']) {
      const res = await tick(ctx, { now: new Date(now), run });
      assert.equal(res.code, 0, res.lines.join('\n'));
    }
    assert.throws(() => readdirSync(inbox), { code: 'ENOENT' });
    assert.deepEqual(calls, []);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('validate --all validates every discovered item', async () => {
  const h = home();
  try {
    const out = [];
    const ctx = { home: h, uid: process.getuid(), out: (s) => out.push(s), err: () => {} };
    assert.equal(await validateVerb(['--all', '--json'], ctx), 0);
    assert.deepEqual(JSON.parse(out.join('')).results.map((r) => [r.item, r.valid]), FILES.map((f) => [`master:${f.replace('.jsonc', '')}`, true]));
  } finally { rmSync(h, { recursive: true, force: true }); }
});
