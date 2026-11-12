// history.test.mjs — scheduled history over the Source's .done/ and .bad/ (scheduled-jsonc §5, §8 H1-H2).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { main as historyMain } from '../src/verbs/history.mjs';
import { main as showMain } from '../src/verbs/show.mjs';
import { setupEnv, hourly } from './helpers.mjs';

function handled(env) {
  const rec = (item, due, extra = {}) => ({ v: 1, kind: 'schedule', namespace: 'master', item, cwd: env.home, file: join(env.scheduled, `${item}.jsonc`),
    due, missed: 0, revision: 'a1b2c3d4e5f6', text: 'Say ok.', by: 'scheduled-heartbeat', at: due, ...extra });
  fs.mkdirSync(join(env.inbox, '.done'), { recursive: true });
  fs.mkdirSync(join(env.inbox, '.bad'), { recursive: true });
  const put = (dir, name, value) => fs.writeFileSync(join(env.inbox, dir, name), typeof value === 'string' ? value : JSON.stringify(value));
  put('.done', 'master~hb@20261112T1000Z.json', rec('hb', '2026-11-12T10:00:00.000Z', { missed: 2 }));
  put('.done', 'master~hb@20261112T1200Z.json', rec('hb', '2026-11-12T12:00:00.000Z'));
  put('.done', 'master~other@20261112T1100Z.json', rec('other', '2026-11-12T11:00:00.000Z'));
  put('.bad', 'master~hb@20261112T1300Z.json', rec('hb', '2026-11-12T13:00:00.000Z', { v: 2 }));
  put('.bad', 'master~hb@20261112T1300Z.json.error', 'v: Invalid input: expected 1\n');
  put('.bad', 'torn.json', '{ torn');
}

test('H1 history lists .done and .bad records newest first with state and error', async () => {
  const env = setupEnv();
  try {
    handled(env);
    assert.equal(await historyMain(['--json'], env.ctx), 0);
    const { rows } = JSON.parse(env.out.join(''));
    assert.deepEqual(rows.map((r) => [r.occurrence, r.state]), [
      ['master~hb@20261112T1300Z', 'bad'],
      ['master~hb@20261112T1200Z', 'done'],
      ['master~other@20261112T1100Z', 'done'],
      ['master~hb@20261112T1000Z', 'done'],
      ['torn', 'bad'],
    ]);
    assert.equal(rows[0].error, 'v: Invalid input: expected 1');
    assert.equal(rows[3].missed, 2);
    assert.deepEqual(Object.keys(rows[1]).sort(), ['by', 'due', 'error', 'item', 'kind', 'missed', 'namespace', 'occurrence', 'revision', 'state']);
  } finally {
    env.cleanup();
  }
});

test('H2 history ID filters to one item, also for an item that no longer exists; show lists the last records', async () => {
  const env = setupEnv();
  try {
    handled(env);
    assert.equal(await historyMain(['master:hb', '--json', '-n', '2'], env.ctx), 0);
    const { rows } = JSON.parse(env.out.join(''));
    assert.deepEqual(rows.map((r) => r.occurrence), ['master~hb@20261112T1300Z', 'master~hb@20261112T1200Z']);
    env.out.length = 0;
    assert.equal(await historyMain(['other'], env.ctx), 0);
    assert.match(env.out.join(''), /master~other@20261112T1100Z/);
    assert.doesNotMatch(env.out.join(''), /master~hb@/);

    env.item('hb', hourly());
    env.out.length = 0;
    assert.equal(await showMain(['master:hb', '--json', '-n', '1'], env.ctx), 0);
    const shown = JSON.parse(env.out.join(''));
    assert.deepEqual(shown.records.map((r) => r.occurrence), ['master~hb@20261112T1300Z']);
    assert.equal(shown.next.length, 1);
  } finally {
    env.cleanup();
  }
});

test('history without an inbox exits 2', async () => {
  const env = setupEnv();
  try {
    assert.equal(await historyMain([], { ...env.ctx, inbox: null }), 2);
  } finally {
    env.cleanup();
  }
});
