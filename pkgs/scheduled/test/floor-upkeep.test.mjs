// floor-upkeep.test.mjs — the master floor-upkeep item is a report-only brief a worker can run end to end
// (scheduled-jsonc §7 asked for its inert prompt to be rewritten before it is enabled).
//
// The brief is read as the Ticket gets it: the schema joins an array prompt with newlines. Every command it
// names in backticks is checked against the verbs that exist, and its `scheduled` commands are run as written
// against a scratch inbox.

import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, mkdirSync, chmodSync, readdirSync, readFileSync, statSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));
const ITEM = '.agency/scheduled/floor-upkeep.jsonc';

function home() {
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-floor-upkeep-'));
  cpSync(FIXTURE, dir, { recursive: true });
  const walk = (p) => {
    const st = statSync(p);
    chmodSync(p, st.isDirectory() ? 0o700 : 0o600);
    if (st.isDirectory()) for (const e of readdirSync(p)) walk(join(p, e));
  };
  walk(dir);
  return dir;
}

async function item() {
  const h = home();
  try {
    const r = await validateFile(join(h, ITEM));
    return { ...r, source: readFileSync(join(h, ITEM), 'utf8') };
  } finally { rmSync(h, { recursive: true, force: true }); }
}

const commands = (prompt) => [...prompt.matchAll(/`([^`]+)`/g)].map((m) => m[1].trim());
const neverLine = (lines) => lines.filter((l) => /^Never:/.test(l));

test('FU1 floor-upkeep validates with zero problems, stays enabled false and keeps its daily 04:00 Europe/Paris schedule', async () => {
  const r = await item();
  assert.deepEqual(r.problems, []);
  assert.equal(r.value.enabled, false);
  assert.deepEqual(r.value.on, { schedule: [{ cron: '0 4 * * *', timezone: 'Europe/Paris' }] });
  assert.ok(r.value.name.length <= 80);
  assert.doesNotMatch(r.source, /INERT|SCHED_FLOOR_CLI|\$SCHED_/);
});

test('FU2 the brief covers ended tickets, .done growth and failed records, from the heartbeat\'s own inbox value', async () => {
  const { prompt } = await item();
  assert.match(prompt, /^Report only/);
  assert.match(prompt, /24 hours before the Due time/);
  // The inbox and floor names come from the heartbeat unit, the one place that knows them; the brief names no path.
  assert.ok(commands(prompt).includes('systemctl --user show -p Environment --value scheduled-heartbeat.service'));
  assert.match(prompt, /SCHEDULED_INBOX=/);
  assert.match(prompt, /SCHEDULED_FLOOR_INSTANCE=/);
  assert.doesNotMatch(prompt, /\.agency\/state|inbox\/scheduled/);
  // Stale tickets.
  assert.ok(commands(prompt).includes('dshd ls --json'));
  assert.match(prompt, /superagent\.ticket/);
  assert.ok(commands(prompt).includes('dshd get --json <name>'));
  assert.ok(commands(prompt).some((c) => /^dshd read -n \d+ <name>$/.test(c)));
  assert.match(prompt, /possibly stuck/);
  // .done growth and records the floor has not read.
  assert.match(prompt, /<inbox>\/\.done/);
  assert.match(prompt, /<inbox>\/\.bad/);
  assert.ok(commands(prompt).includes("find <inbox> -maxdepth 1 -name '*.json' -mmin +60"));
  // Failed records: every item, no --all (contract §5).
  assert.ok(commands(prompt).includes('scheduled history --inbox <inbox> -n 50 --json'));
  assert.doesNotMatch(prompt, /--all/);
  assert.match(prompt, /word for word/);
  assert.match(prompt, /\n[^\n]*nothing to report\.?$/);
});

test('FU3 every command the brief names is a read: dshd ls/get/read, systemctl show, find, du, scheduled history', async () => {
  const { prompt } = await item();
  const named = commands(prompt).filter((c) => /^(dshd|systemctl|scheduled|find|du|ls|rm|mv)\b/.test(c));
  assert.ok(named.length >= 6, named.join('\n'));
  for (const c of named) {
    const [tool, ...rest] = c.split(/\s+/);
    if (tool === 'dshd') assert.ok(['ls', 'get', 'read'].includes(rest[0]), c);
    else if (tool === 'systemctl') assert.equal(rest.filter((a) => !a.startsWith('-'))[0], 'show', c);
    else if (tool === 'scheduled') assert.equal(rest[0], 'history', c);
    else if (tool === 'find') assert.doesNotMatch(c, /-delete|-exec|-ok\b|-fprint/, c);
    else assert.ok(tool === 'du', c);
  }
});

test('FU4 state-changing words appear only on the Never line, which forbids each of them', async () => {
  const { prompt } = await item();
  const lines = prompt.split('\n');
  assert.equal(neverLine(lines).length, 1);
  const never = neverLine(lines)[0];
  const change = /\b(dshd|scheduled)\s+(run|start|stop|restart|update|label|enable|disable|rm|set|new|tick)\b|\bsystemctl\b[^\n]*\b(start|stop|restart|reset-failed|kill|mask)\b|\b(rm|mv|truncate)\s|-delete\b/;
  for (const l of lines.filter((x) => x !== never)) assert.doesNotMatch(l, change, l);
  for (const w of ['dshd run, start, stop, restart, update, label, enable, disable or rm', 'scheduled run, set, new, rm or tick',
    'systemctl start, stop, restart or reset-failed', 'move, delete or edit any file', 'restart Herdr or the user manager'])
    assert.ok(never.includes(w), w);
  assert.match(prompt, /Write the report as your reply only/);
});

test('FU5 the brief names no person, host or private path', async () => {
  const { source } = await item();
  assert.doesNotMatch(source.replace(/^\/\/.*$/gm, ''), /\/home\/|~\/notes|~\/today|~\/mecattaf|\bcc2\b|claude-work|\btom\b|strix|\bnas\b/i);
});

test('FU6 the scheduled commands of the brief run as written: exit 0, every item, the bad record with its error', async () => {
  const { prompt } = await item();
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-floor-upkeep-inbox-'));
  try {
    const inbox = join(dir, 'inbox');
    for (const d of ['.done', '.bad']) mkdirSync(join(inbox, d), { recursive: true });
    const rec = (item, due) => ({ v: 1, kind: 'schedule', namespace: 'master', item, cwd: dir, file: null, due, missed: 0,
      revision: 'a1b2c3d4e5f6', text: 'Say ok.', by: 'scheduled-heartbeat', at: due });
    writeFileSync(join(inbox, '.done', 'master~a@20261112T0300Z.json'), JSON.stringify(rec('a', '2026-11-12T03:00:00.000Z')));
    writeFileSync(join(inbox, '.bad', 'master~b@20261112T0200Z.json'), JSON.stringify(rec('b', '2026-11-12T02:00:00.000Z')));
    writeFileSync(join(inbox, '.bad', 'master~b@20261112T0200Z.json.error'), 'cwd: not a directory\n');
    const sched = commands(prompt).filter((c) => c.startsWith('scheduled '));
    assert.ok(sched.length >= 1);
    for (const c of sched) {
      const [, verb, ...args] = c.replaceAll('<inbox>', inbox).split(/\s+/);
      const { main } = await import(`../src/verbs/${verb}.mjs`);
      const out = [];
      const err = [];
      const code = await main(args, { inbox: null, home: dir, uid: process.getuid(), out: (s) => out.push(s), err: (s) => err.push(s) });
      assert.equal(code, 0, `${c}: ${err.join('')}`);
      const { rows } = JSON.parse(out.join(''));
      assert.deepEqual(rows.map((r) => [r.item, r.state, r.error]), [['a', 'done', null], ['b', 'bad', 'cwd: not a directory']]);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
