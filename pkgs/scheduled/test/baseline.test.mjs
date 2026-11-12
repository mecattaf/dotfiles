// The master items: the three live items copied from ~/.agency/workflows/ (docs/scheduled.md, State at
// install) and cli-update, the nightly check-and-ingest half of the CLI tools update. Every one ships with
// "enabled": false, so nothing runs unattended before an item is enabled. They are copied by hand to
// ~/.agency/scheduled/ (mode 0600, directory 0700); Nix never writes them.
import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, chmodSync, readdirSync, readFileSync, statSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';
import { discover } from '../src/lib/discover.mjs';
import { tick } from '../src/lib/tick.mjs';
import { main as validateVerb } from '../src/verbs/validate.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));
const FILES = ['cli-update.jsonc', 'fleet-nightly.jsonc', 'floor-upkeep.jsonc', 'journal-day.jsonc'];

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

test('C6.1: every live item validates with zero problems and reads enabled false', async () => {
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

test('C6.1: the items are master:cli-update, master:fleet-nightly, master:floor-upkeep and master:journal-day; floor-upkeep says it is inert', async () => {
  const h = home();
  try {
    const d = await discover({ home: h, uid: process.getuid() });
    assert.deepEqual(d.files.map((f) => f.id), FILES.map((f) => `master:${f.replace('.jsonc', '')}`));
    assert.deepEqual(d.problems, []);
    assert.match(readFileSync(join(h, '.agency/scheduled/floor-upkeep.jsonc'), 'utf8'), /INERT/);
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
    assert.deepEqual(readers, ['cli-update.jsonc', 'fleet-nightly.jsonc', 'journal-day.jsonc']);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('cli-update: 01:30 and 04:30 Paris; the brief launches update-check once and keeps the guardrails', async () => {
  const h = home();
  try {
    const r = await validateFile(join(h, '.agency/scheduled/cli-update.jsonc'));
    assert.deepEqual(r.problems, []);
    assert.deepEqual(r.value.on.schedule, [
      { cron: '30 1 * * *', timezone: 'Europe/Paris' },
      { cron: '30 4 * * *', timezone: 'Europe/Paris' },
    ]);
    // The builder's free space is checked before update-check's gate builds on it.
    assert.match(r.prompt, /df -BG --output=avail \//);
    assert.match(r.prompt, /less than 25G/);
    // NixOS sets builders to @/etc/nix/machines: the brief reads that file, never ends on the indirection.
    assert.match(r.prompt, /nix config show builders; when that starts with @, read the file it names/);
    assert.match(r.prompt, /^1\. Run exactly: update-check --if-idle --background --json\./m);
    assert.match(r.prompt, /Never name or use strix-worker/);
    // The check proposes; Tom merges and switches.
    for (const never of ['merge', 'push to main', 'nixos-rebuild', 'switch-to-configuration', 'nix flake update', 'fleet-update']) {
      assert.match(r.prompt, new RegExp(`^Never:.*${never.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'm'), never);
    }
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
