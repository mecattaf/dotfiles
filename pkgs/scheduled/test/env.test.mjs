/**
 * test/env.test.mjs
 * Tests for the `scheduled env` verb.
 * Covers Claim C2.13.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { main as envVerb } from '../src/verbs/env.mjs';

function makeTempAgency(root, stem, content) {
  const agencyDir = path.join(root, '.agency');
  const workflowsDir = path.join(agencyDir, 'workflows');
  fs.mkdirSync(workflowsDir, { recursive: true, mode: 0o700 });
  fs.chmodSync(agencyDir, 0o700);
  fs.chmodSync(workflowsDir, 0o700);

  const filePath = path.join(workflowsDir, `${stem}.jsonc`);
  fs.writeFileSync(filePath, content, { mode: 0o600 });
  return { agencyDir, workflowsDir, filePath };
}

function makeCtx(overrides = {}) {
  const out = [];
  const err = [];
  return {
    uid: process.getuid(),
    home: os.homedir(),
    now: () => new Date('2026-11-12T00:00:00.000Z'),
    out: (s) => out.push(s),
    err: (s) => err.push(s),
    _out: out,
    _err: err,
    stateDir: path.join(os.tmpdir(), 'state'),
    env: {},
    ...overrides,
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test('C2.13: scheduled env ID --occurrence KEY --attempt N --json prints all required SCHED_* keys', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-env-c213-'));
  makeTempAgency(tmpHome, 'fleet-nightly', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * 1', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Nightly fleet check' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await envVerb(
    [
      'fleet-nightly',
      '--occurrence',
      'master:fleet-nightly@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0, `Failed with err: ${ctx._err.join('')}`);
  const envMap = JSON.parse(ctx._out.join(''));

  // C2.13 required keys
  assert.equal(envMap.SCHED_WORKFLOW, 'master:fleet-nightly');
  assert.equal(envMap.SCHED_AGENCY, 'master');
  assert.equal(envMap.SCHED_KIND, 'schedule');
  assert.equal(envMap.SCHED_OCCURRENCE, 'master:fleet-nightly@2026-11-12T00:00:00.000Z');
  assert.equal(envMap.SCHED_SCHEDULED_AT, '2026-11-12T00:00:00.000Z');
  assert.equal(envMap.SCHED_TIMEZONE, 'Europe/Paris');
  assert.equal(envMap.SCHED_LOCAL_DATE, '2026-11-12');
  assert.equal(envMap.SCHED_NIGHT, '2026-11-11');
  assert.equal(envMap.SCHED_ATTEMPT, '1');
  assert.equal(envMap.SCHED_PREVIOUS_SUCCESS_AT, '');
  assert.ok(path.isAbsolute(envMap.SCHED_FLOOR_CLI));
  assert.match(envMap.SCHED_FLOOR_CLI, /\/\.dsh\/profiles\/floor\/node_modules\/dsh-superagent\/bin\/floor$/);
});

test('C2.13: SCHED_NIGHT rule - local date of instant minus 12 hours in workflow timezone', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-env-night-'));
  makeTempAgency(tmpHome, 'afternoon-job', JSON.stringify({
    on: { schedule: [{ cron: '0 15 * * *', timezone: 'Europe/Paris' }] },
    job: { prompt: 'Afternoon job' },
  }));

  const ctx = makeCtx({ home: tmpHome });

  // 15:00 Paris = 14:00 UTC. Minus 12h = 03:00 Paris on the same date (2026-11-12).
  const code = await envVerb(
    [
      'afternoon-job',
      '--occurrence',
      'master:afternoon-job@2026-11-12T14:00:00.000Z',
      '--attempt',
      '2',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const envMap = JSON.parse(ctx._out.join(''));
  assert.equal(envMap.SCHED_LOCAL_DATE, '2026-11-12');
  assert.equal(envMap.SCHED_NIGHT, '2026-11-12');
  assert.equal(envMap.SCHED_ATTEMPT, '2');
});

test('C2.13: SCHED_KIND is manual when occurrence key indicates manual', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-env-man-'));
  makeTempAgency(tmpHome, 'manual-task', JSON.stringify({
    on: { workflow_dispatch: {} },
    job: { prompt: 'Run manually' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await envVerb(
    [
      'manual-task',
      '--occurrence',
      'master:manual-task@manual:01JCF3W2Q9V7T8K4M6N0P2R5S8',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const envMap = JSON.parse(ctx._out.join(''));
  assert.equal(envMap.SCHED_KIND, 'manual');
});

test('C2.13: SCHED_PREVIOUS_SUCCESS_AT reads from orchestrator.sqlite sched_history_v1', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-env-db-'));
  const tmpState = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-state-'));

  makeTempAgency(tmpHome, 'db-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'DB task' },
  }));

  // orchestrator.sqlite with the floor's real tables and view: copied from the
  // fork's src/app/migration.ts migrateTo12 (scheduled/floor bdcc0d0), so the
  // query meets the columns and state names it will meet on the NAS.
  const dbPath = path.join(tmpState, 'orchestrator.sqlite');
  const db = new DatabaseSync(dbPath);
  db.exec(`
    CREATE TABLE sched_occurrences (
      occurrence TEXT PRIMARY KEY, workflow_id TEXT NOT NULL, kind TEXT NOT NULL, instant TEXT NOT NULL,
      missed INTEGER NOT NULL DEFAULT 0, deadline TEXT, grp TEXT NOT NULL, state TEXT NOT NULL, reason TEXT,
      attempt INTEGER NOT NULL DEFAULT 0, reruns INTEGER NOT NULL DEFAULT 0, next_try_at TEXT, by TEXT,
      inputs TEXT, updated_at TEXT NOT NULL);
    CREATE TABLE sched_attempts (
      occurrence TEXT NOT NULL, attempt INTEGER NOT NULL, rerun INTEGER NOT NULL DEFAULT 0, instance TEXT NOT NULL,
      revision TEXT NOT NULL, invocation TEXT, started_at TEXT NOT NULL, ended_at TEXT, ending TEXT,
      exit_code INTEGER, report TEXT, PRIMARY KEY (occurrence, attempt, rerun));
    CREATE VIEW sched_history_v1 AS
      SELECT o.occurrence, o.workflow_id AS workflow, o.kind,
             o.instant AS due_at, o.missed, o.state, o.reason, o.attempt,
             a.instance, a.revision, a.started_at, a.ended_at,
             substr(a.report, 1, 1500) AS report, o.by, o.updated_at
      FROM sched_occurrences o
      LEFT JOIN sched_attempts a ON a.occurrence = o.occurrence
       AND a.attempt = o.attempt
       AND a.rerun = (SELECT max(rerun) FROM sched_attempts
                      WHERE occurrence = o.occurrence AND attempt = o.attempt);
    INSERT INTO sched_occurrences VALUES ('master:db-task@2026-11-10T06:00:00.000Z', 'master:db-task', 'schedule',
      '2026-11-10T06:00:00.000Z', 0, NULL, 'master:db-task', 'done', NULL, 1, 0, NULL, NULL, NULL, '2026-11-10T06:20:00.000Z');
    INSERT INTO sched_attempts VALUES ('master:db-task@2026-11-10T06:00:00.000Z', 1, 0, 'sch-master-db-task-20261110t0600z-a1',
      'abcdef012345', NULL, '2026-11-10T06:00:05.000Z', '2026-11-10T06:12:00.000Z', 'exited', 0, NULL);
    INSERT INTO sched_occurrences VALUES ('master:db-task@2026-11-11T06:00:00.000Z', 'master:db-task', 'schedule',
      '2026-11-11T06:00:00.000Z', 0, NULL, 'master:db-task', 'failed', 'exit', 1, 0, NULL, NULL, NULL, '2026-11-11T06:30:00.000Z');
    INSERT INTO sched_attempts VALUES ('master:db-task@2026-11-11T06:00:00.000Z', 1, 0, 'sch-master-db-task-20261111t0600z-a1',
      'abcdef012345', NULL, '2026-11-11T06:00:05.000Z', '2026-11-11T06:25:00.000Z', 'exited', 1, NULL);
    INSERT INTO sched_occurrences VALUES ('master:other@2026-11-11T07:00:00.000Z', 'master:other', 'schedule',
      '2026-11-11T07:00:00.000Z', 0, NULL, 'master:other', 'done', NULL, 1, 0, NULL, NULL, NULL, '2026-11-11T07:10:00.000Z');
  `);
  db.close();

  const ctx = makeCtx({ home: tmpHome, stateDir: tmpState });
  const code = await envVerb(
    [
      'db-task',
      '--occurrence',
      'master:db-task@2026-11-12T06:00:00.000Z',
      '--attempt',
      '1',
      '--json',
    ],
    ctx
  );

  assert.equal(code, 0);
  const envMap = JSON.parse(ctx._out.join(''));
  assert.equal(envMap.SCHED_PREVIOUS_SUCCESS_AT, '2026-11-10T06:12:00.000Z');
});

test('env: text output prints KEY=VALUE format', async () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sched-env-txt-'));
  makeTempAgency(tmpHome, 'txt-task', JSON.stringify({
    on: { schedule: [{ cron: '0 6 * * *', timezone: 'UTC' }] },
    job: { prompt: 'Text format' },
  }));

  const ctx = makeCtx({ home: tmpHome });
  const code = await envVerb(
    [
      'txt-task',
      '--occurrence',
      'master:txt-task@2026-11-12T00:00:00.000Z',
      '--attempt',
      '1',
    ],
    ctx
  );

  assert.equal(code, 0);
  const output = ctx._out.join('');
  assert.ok(output.includes('SCHED_WORKFLOW=master:txt-task\n'));
  assert.ok(output.includes('SCHED_AGENCY=master\n'));
  assert.ok(output.includes('SCHED_KIND=schedule\n'));
});
