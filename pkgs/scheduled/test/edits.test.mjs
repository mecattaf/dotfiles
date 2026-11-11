// history --edits [--diff] reads the revision ledger (DESIGN 10.1, 5.1).
import test from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, cpSync, mkdtempSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { unifiedDiff } from '../src/verbs/history.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));
function home() {
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-edits-'));
  cpSync(FIXTURE, dir, { recursive: true });
  const walk = (p) => { const st = statSync(p); chmodSync(p, st.isDirectory() ? 0o700 : 0o600); if (st.isDirectory()) for (const e of readdirSync(p)) walk(join(p, e)); };
  walk(dir);
  return dir;
}
let tick = 0;
function ctxFor(h) {
  const out = [], err = [];
  return { home: h, stateDir: join(h, '.agency', 'state', 'master'), uid: process.getuid(), env: { USER: 'tom' },
    now: () => new Date(Date.UTC(2026, 10, 11, 2, 0, tick++)), out: (s) => out.push(s), err: (s) => err.push(s), _out: out, _err: err };
}
const verb = async (name, args, ctx) => (await import(`../src/verbs/${name}.mjs`)).main(args, ctx);

test('history --edits lists the ledger newest first with by; --diff shows the last change as a unified diff', async () => {
  const h = home();
  try {
    assert.equal(await verb('new', ['master:probe', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'Say ok.', '--paused', '--by', 'tom'], ctxFor(h)), 0);
    assert.equal(await verb('set', ['master:probe', 'enabled', 'true', '--by', 'cc2'], ctxFor(h)), 0);
    const json = ctxFor(h);
    assert.equal(await verb('history', ['master:probe', '--edits', '--json'], json), 0);
    const edits = JSON.parse(json._out.join(''));
    assert.deepEqual(edits.map((e) => e.by), ['cc2', 'tom']);
    const diff = ctxFor(h);
    assert.equal(await verb('history', ['master:probe', '--edits', '--diff'], diff), 0);
    const text = diff._out.join('');
    assert.match(text, /^--- master:probe@/m);
    assert.match(text, /^-  "enabled": false,$/m);
    assert.match(text, /^\+  "enabled": true,$/m);
    assert.equal(text.split('\n').filter((l) => /^[-+] /.test(l) || /^[-+]  /.test(l)).length, 2);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('history --diff with one stored revision exits 1', async () => {
  const h = home();
  try {
    assert.equal(await verb('new', ['master:solo', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'x', '--paused'], ctxFor(h)), 0);
    assert.equal(await verb('history', ['master:solo', '--edits', '--diff'], ctxFor(h)), 1);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('unifiedDiff puts a deletion before its addition', () => {
  assert.equal(unifiedDiff('a\nb\nc\n', 'a\nB\nc\n', 'x', 'y'), '--- x\n+++ y\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n');
});

test('set path: on.schedule[0].cron (the skill spelling) is the same path as on.schedule.0.cron (evaluation review)', async () => {
  const { edit, parsePath } = await import('../src/verbs/set.mjs');
  assert.deepEqual(parsePath('on.schedule[0].cron'), ['on', 'schedule', 0, 'cron']);
  const text = '{\n  // keep\n  "on": { "schedule": [{ "cron": "0 6 * * *", "timezone": "UTC" }] }\n}\n';
  const out = edit(text, 'on.schedule[0].cron', '0 6 * * 1');
  assert.match(out, /"cron": "0 6 \* \* 1"/);
  assert.match(out, /\/\/ keep/);
  assert.ok(!out.includes('schedule[0]'));
});
