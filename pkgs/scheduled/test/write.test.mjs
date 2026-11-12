// The write verbs new, set and rm (rows C2.9-C2.11 below; docs/scheduled.md, Everyday commands). Temporary homes only.
import test from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { writeItem } from '../src/lib/write.mjs';
import { validateFile } from '../src/lib/validate.mjs';
import { parsePath } from '../src/verbs/set.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));

function home() {
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-write-'));
  cpSync(FIXTURE, dir, { recursive: true });
  const walk = (p) => { const st = statSync(p); chmodSync(p, st.isDirectory() ? 0o700 : 0o600); if (st.isDirectory()) for (const e of readdirSync(p)) walk(join(p, e)); };
  walk(dir);
  return dir;
}
function ctxFor(h, extra = {}) {
  const out = [], err = [];
  return { home: h, uid: process.getuid(), env: {}, now: () => new Date('2026-11-12T02:00:00Z'),
    out: (s) => out.push(s), err: (s) => err.push(s), _out: out, _err: err, ...extra };
}
const verb = async (name, args, ctx) => (await import(`../src/verbs/${name}.mjs`)).main(args, ctx);
const IT = (h, f) => join(h, '.agency/scheduled', f);

test('C2.9: set to an invalid value exits 1, and an --expect that differs from disk exits 3; neither writes', async () => {
  const h = home();
  try {
    const before = readFileSync(IT(h, 'journal-day.jsonc'));
    assert.equal(await verb('set', ['master:journal-day', 'enabled', '"yes"'], ctxFor(h)), 1);
    assert.equal(await verb('set', ['master:journal-day', 'window', '"2h"'], ctxFor(h)), 1);
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'true', '--expect', 'deadbeef0000'], ctxFor(h)), 3);
    assert.deepEqual(readFileSync(IT(h, 'journal-day.jsonc')), before);
    assert.deepEqual(readdirSync(join(h, '.agency/scheduled')).filter((n) => n.endsWith('.tmp')), []);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.10: a write goes through .<stem>.jsonc.<pid>.tmp mode 0600 and answers the revision on disk', async () => {
  const h = home();
  try {
    let seen = null;
    const text = '{ "enabled": false, "on": { "schedule": [ { "cron": "0 6 * * *", "timezone": "UTC" } ] }, "job": { "prompt": "Say ok." } }\n';
    const res = await writeItem(ctxFor(h), { path: IT(h, 'probe.jsonc'), bytes: Buffer.from(text), expect: 'none',
      hooks: { afterTemp: (tmp) => { seen = { name: tmp.split('/').pop(), mode: statSync(tmp).mode & 0o777 }; } } });
    assert.equal(seen.name, `.probe.jsonc.${process.pid}.tmp`);
    assert.equal(seen.mode, 0o600);
    assert.equal(res.revision, (await validateFile(IT(h, 'probe.jsonc'))).revision);
    await assert.rejects(writeItem(ctxFor(h), { path: IT(h, 'probe.jsonc'), bytes: Buffer.from(text), expect: 'none' }), { code: 3 });
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.11: set ID enabled true on a commented file changes exactly one line and keeps every comment byte-identical', async () => {
  const h = home();
  try {
    const before = readFileSync(IT(h, 'journal-day.jsonc'), 'utf8').split('\n');
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'true'], ctxFor(h)), 0);
    const after = readFileSync(IT(h, 'journal-day.jsonc'), 'utf8').split('\n');
    const changed = before.map((l, i) => [l, after[i]]).filter(([a, b]) => a !== b);
    assert.deepEqual(changed, [['  "enabled": false,', '  "enabled": true,']]);
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'false'], ctxFor(h)), 0);
    assert.deepEqual(readFileSync(IT(h, 'journal-day.jsonc'), 'utf8').split('\n'), before);
    // The skill's spelling of a path into an array.
    assert.deepEqual(parsePath('on.schedule[0].cron'), ['on', 'schedule', 0, 'cron']);
    assert.equal(await verb('set', ['master:journal-day', 'on.schedule[0].cron', '0 1 * * *'], ctxFor(h)), 0);
    assert.match(readFileSync(IT(h, 'journal-day.jsonc'), 'utf8'), /"cron": "0 1 \* \* \*"/);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('new always writes enabled false (prompt or prompt-file), refuses an existing item and --paused; rm deletes the file', async () => {
  const h = home();
  try {
    const ctx = ctxFor(h);
    assert.equal(await verb('new', ['master:probe', '--cron', '0 6 * * *', '--tz', 'Europe/Paris', '--prompt', 'Say ok.', '--name', 'Probe'], ctx), 0, ctx._err.join(''));
    let r = await validateFile(IT(h, 'probe.jsonc'));
    assert.deepEqual(r.problems, []);
    assert.equal(r.value.enabled, false);
    assert.equal(r.value.name, 'Probe');
    assert.equal(await verb('new', ['master:probe', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'Again.'], ctxFor(h)), 3);
    assert.equal(await verb('new', ['master:paused', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'x', '--paused'], ctxFor(h)), 2);
    assert.equal(await verb('new', ['master:both', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'x', '--prompt-file', 'p.md'], ctxFor(h)), 2);

    assert.equal(await verb('new', ['master:filed', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt-file', '.agency/scheduled/missing.md'], ctxFor(h)), 1);
    assert.equal(existsSync(IT(h, 'filed.jsonc')), false);

    assert.equal(await verb('rm', ['master:probe', '--expect', r.revision], ctxFor(h)), 0);
    assert.equal(existsSync(IT(h, 'probe.jsonc')), false);
    assert.equal(await verb('rm', ['master:probe'], ctxFor(h)), 1);
  } finally { rmSync(h, { recursive: true, force: true }); }
});
