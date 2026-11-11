// The baseline workflows of DESIGN 11 (claim C6.1, fixture half). Every one
// ships with "enabled": false tonight (D-11): nothing may fire in the morning.
import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, chmodSync, readdirSync, statSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';
import { discover } from '../src/lib/discover.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));

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

const FILES = ['fleet-nightly.jsonc', 'journal-day.jsonc', 'floor-upkeep.jsonc', 'proposed/next-day-prep.jsonc'];

test('C6.1: every baseline file validates with zero problems', async () => {
  const h = home();
  try {
    for (const f of FILES) {
      const r = await validateFile(join(h, '.agency/workflows', f), { proposal: f.startsWith('proposed/') });
      assert.deepEqual(r.problems, [], f);
      assert.ok(r.value, f);
    }
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('D-11: every baseline file reads enabled false', async () => {
  const h = home();
  try {
    for (const f of FILES) {
      const r = await validateFile(join(h, '.agency/workflows', f), { proposal: f.startsWith('proposed/') });
      assert.equal(r.value.enabled, false, f);
    }
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C6.1: next-day-prep is listed as a proposal, the others as workflows of master', async () => {
  const h = home();
  try {
    const d = await discover({ home: h, uid: process.getuid() });
    const ids = d.files.map(f => `${f.id}${f.proposal ? ' (proposal)' : ''}`).sort();
    assert.deepEqual(ids, ['master:fleet-nightly', 'master:floor-upkeep', 'master:journal-day', 'master:next-day-prep (proposal)']);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('validate --all validates every discovered workflow and proposal (DESIGN 10.1)', async () => {
  const h = home();
  try {
    const { main } = await import('../src/verbs/validate.mjs');
    const out = [];
    const ctx = { home: h, uid: process.getuid(), env: {}, out: s => out.push(s), err: s => out.push(s) };
    const code = await main(['--all', '--json'], ctx);
    assert.equal(code, 0);
    const { results } = JSON.parse(out.join(''));
    assert.deepEqual(results.map(r => [r.id ?? r.workflow, r.valid]).sort(),
      [['master:fleet-nightly', true], ['master:floor-upkeep', true], ['master:journal-day', true], ['master:next-day-prep', true]]);
  } finally { rmSync(h, { recursive: true, force: true }); }
});
