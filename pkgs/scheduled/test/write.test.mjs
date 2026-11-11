// The write verbs (DESIGN 10.1; claims C2.9-C2.12). Temporary homes only.
import test from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { writeWorkflow, MAX_PROPOSALS } from '../src/lib/write.mjs';

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
  return { home: h, stateDir: join(h, '.agency', 'state', 'master'), uid: process.getuid(), env: { USER: 'tester' }, now: () => new Date('2026-11-11T02:00:00Z'),
    out: (s) => out.push(s), err: (s) => err.push(s), _out: out, _err: err, ...extra };
}
const verb = async (name, args, ctx) => (await import(`../src/verbs/${name}.mjs`)).main(args, ctx);
const index = (h) => readFileSync(join(h, '.agency/state/master/revisions/index.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const WF = (h, f) => join(h, '.agency/workflows', f);
const VALID = `{
  "name": "Probe",
  "enabled": false,
  "on": { "schedule": [ { "cron": "0 6 * * *", "timezone": "UTC" } ] },
  "job": { "prompt": "Say ok." }
}
`;

test('C2.9: put of invalid text exits 1 and leaves the bytes on disk unchanged', async () => {
  const h = home();
  try {
    const before = readFileSync(WF(h, 'journal-day.jsonc'));
    const ctx = ctxFor(h, { stdin: '{ "name": 1 }' });
    assert.equal(await verb('put', ['master:journal-day'], ctx), 1);
    assert.deepEqual(readFileSync(WF(h, 'journal-day.jsonc')), before);
    assert.deepEqual(readdirSync(join(h, '.agency/workflows')).filter((n) => n.endsWith('.tmp')), []);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.9: put or set with an --expect that differs from disk exits 3 and writes nothing', async () => {
  const h = home();
  try {
    const before = readFileSync(WF(h, 'journal-day.jsonc'));
    assert.equal(await verb('put', ['master:journal-day', '--expect', 'deadbeef0000'], ctxFor(h, { stdin: VALID })), 3);
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'true', '--expect', 'deadbeef0000'], ctxFor(h)), 3);
    assert.equal(await verb('put', ['master:journal-day', '--expect', 'none'], ctxFor(h, { stdin: VALID })), 3);
    assert.deepEqual(readFileSync(WF(h, 'journal-day.jsonc')), before);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.10: a write goes through .<stem>.jsonc.<pid>.tmp mode 0600, then one ledger line with by and a blob of exactly the bytes', async () => {
  const h = home();
  try {
    const ctx = ctxFor(h);
    let seen;
    const res = await writeWorkflow(ctx, { path: WF(h, 'probe.jsonc'), bytes: Buffer.from(VALID), by: 'cc2', id: 'master:probe', expect: 'none',
      hooks: { afterTemp: (tmp) => { seen = { name: tmp.split('/').at(-1), mode: statSync(tmp).mode & 0o777 }; } } });
    assert.deepEqual(seen, { name: `.probe.jsonc.${process.pid}.tmp`, mode: 0o600 });
    assert.equal(statSync(WF(h, 'probe.jsonc')).mode & 0o777, 0o600);
    const lines = index(h).filter((l) => l.workflow === 'master:probe');
    assert.equal(lines.length, 1);
    assert.equal(lines[0].by, 'cc2');
    assert.equal(lines[0].revision, res.revision);
    const sha = createHash('sha256').update(VALID).digest('hex');
    assert.equal(lines[0].file, sha);
    assert.equal(readFileSync(join(h, '.agency/state/master/revisions', `${sha}.jsonc`), 'utf8'), VALID);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.11: set ID enabled true on a commented file changes exactly one line and keeps every comment byte-identical', async () => {
  const h = home();
  try {
    const before = readFileSync(WF(h, 'journal-day.jsonc'), 'utf8').split('\n');
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'true', '--by', 'tom'], ctxFor(h)), 0);
    const after = readFileSync(WF(h, 'journal-day.jsonc'), 'utf8').split('\n');
    assert.equal(after.length, before.length);
    const changed = before.map((l, i) => [l, after[i]]).filter(([a, b]) => a !== b);
    assert.deepEqual(changed, [['  "enabled": false,', '  "enabled": true,']]);
    for (const [i, l] of before.entries()) if (l.trim().startsWith('//')) assert.equal(after[i], l);
    // And back: the D-11 pause is one command too.
    assert.equal(await verb('set', ['master:journal-day', 'enabled', 'false'], ctxFor(h)), 0);
    assert.deepEqual(readFileSync(WF(h, 'journal-day.jsonc'), 'utf8').split('\n'), before);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.12: put --proposal lands only in proposed/ and needs enabled false and x-proposal; a fourth open proposal exits 1', async () => {
  const h = home();
  try {
    const proposal = (stem) => `{
  "name": "${stem}",
  "enabled": false,
  "x-proposal": { "by": "cc2", "at": "2026-11-11T01:00:00.000Z", "why": ["test"] },
  "on": { "schedule": [ { "cron": "0 6 * * *", "timezone": "UTC" } ] },
  "job": { "prompt": "Say ok." }
}
`;
    assert.equal(await verb('put', ['master:p-armed', '--proposal'], ctxFor(h, { stdin: proposal('p-armed').replace('"enabled": false', '"enabled": true') })), 1);
    assert.equal(await verb('put', ['master:p-bare', '--proposal'], ctxFor(h, { stdin: VALID })), 1);
    // The fixture already holds one open proposal (next-day-prep).
    for (let k = 1; k < MAX_PROPOSALS; k++) assert.equal(await verb('put', [`master:p${k}`, '--proposal'], ctxFor(h, { stdin: proposal(`p${k}`) })), 0);
    assert.ok(existsSync(join(h, '.agency/workflows/proposed/p1.jsonc')));
    assert.ok(!existsSync(WF(h, 'p1.jsonc')));
    assert.equal(await verb('put', ['master:p-fourth', '--proposal'], ctxFor(h, { stdin: proposal('p-fourth') })), 1);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('C2.12: accept moves a proposal up, sets enabled true and keeps x-proposal; dismiss deletes it and refuses the stem for 30 days', async () => {
  const h = home();
  try {
    assert.equal(await verb('accept', ['master:next-day-prep', '--by', 'tom'], ctxFor(h)), 0);
    const text = readFileSync(WF(h, 'next-day-prep.jsonc'), 'utf8');
    assert.match(text, /"enabled": true/);
    assert.match(text, /"x-proposal"/);
    assert.ok(!existsSync(join(h, '.agency/workflows/proposed/next-day-prep.jsonc')));
    // Put it back as a proposal, then dismiss it.
    const prop = text.replace('"enabled": true', '"enabled": false');
    assert.equal(await verb('rm', ['master:next-day-prep'], ctxFor(h)), 0);
    assert.equal(await verb('put', ['master:next-day-prep', '--proposal'], ctxFor(h, { stdin: prop })), 0);
    assert.equal(await verb('dismiss', ['master:next-day-prep'], ctxFor(h)), 0);
    assert.ok(!existsSync(join(h, '.agency/workflows/proposed/next-day-prep.jsonc')));
    const dismissed = readFileSync(join(h, '.agency/state/master/dismissed.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
    assert.equal(dismissed.at(-1).stem, 'next-day-prep');
    assert.equal(await verb('put', ['master:next-day-prep', '--proposal'], ctxFor(h, { stdin: prop })), 1);
    const later = ctxFor(h, { stdin: prop, now: () => new Date('2026-12-12T02:00:00Z') });
    assert.equal(await verb('put', ['master:next-day-prep', '--proposal'], later), 0);
  } finally { rmSync(h, { recursive: true, force: true }); }
});

test('new writes a minimal valid file (paused with --paused) and refuses an existing one; rm keeps a removed ledger line', async () => {
  const h = home();
  try {
    assert.equal(await verb('new', ['master:probe', '--cron', '0 6 * * *', '--tz', 'Europe/Paris', '--prompt', 'Say ok.', '--paused'], ctxFor(h)), 0);
    assert.match(readFileSync(WF(h, 'probe.jsonc'), 'utf8'), /"enabled": false/);
    assert.equal(await verb('new', ['master:probe', '--cron', '0 6 * * *', '--tz', 'UTC', '--prompt', 'x'], ctxFor(h)), 3);
    assert.equal(await verb('new', ['master:probe2', '--cron', '61 * * * *', '--tz', 'UTC', '--prompt', 'x'], ctxFor(h)), 1);
    assert.equal(await verb('rm', ['master:probe', '--by', 'cc2'], ctxFor(h)), 0);
    assert.ok(!existsSync(WF(h, 'probe.jsonc')));
    const last = index(h).at(-1);
    assert.deepEqual([last.workflow, last.by, last.valid, last.removed], ['master:probe', 'cc2', false, true]);
  } finally { rmSync(h, { recursive: true, force: true }); }
});
