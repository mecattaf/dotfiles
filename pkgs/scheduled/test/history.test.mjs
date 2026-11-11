// history.test.mjs — tests for `scheduled history` and C2.15.
//
// Spec ref: C2.15 (read-only node:sqlite over sched_history_v1 and sched_attempts_v1)
//           DESIGN 5.4 (the SQLite schema and views)
//           DESIGN 10.1 (CLI syntax and exit codes)
//           DESIGN b.11 (History and inspection)
//
// Run: node --test test/history.test.mjs

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync } from 'node:fs';
import { rm } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import os from 'node:os';

import {
  openHistoryDb,
  parseDurationMs,
  formatParisDate,
  deriveNote,
  queryHistory,
  queryAttempts,
  queryEdits,
  isInstancePruned,
  formatHistoryTable,
  formatAttemptsOutput,
  formatEditsTable,
} from '../src/lib/history.mjs';
import { main, parseArgs } from '../src/verbs/history.mjs';

const CLI_PATH = join(dirname(fileURLToPath(import.meta.url)), '../src/cli.mjs');

// ---------------------------------------------------------------------------
// DESIGN 5.4 DDL (verbatim from spec)
// ---------------------------------------------------------------------------

const DESIGN_5_4_DDL = `
CREATE TABLE sched_workflows (
  id          TEXT PRIMARY KEY,   -- '<agency id>:<stem>'
  agency      TEXT NOT NULL,      -- agency root, real path
  file        TEXT NOT NULL,      -- the .jsonc, real path
  state       TEXT NOT NULL,      -- valid|invalid|disabled|removed
  revision    TEXT,               -- 12 hex, from the last census
  problems    TEXT,               -- JSON list, from the census
  ticket_id   TEXT,               -- the standing Ticket, once accepted
  first_seen  TEXT NOT NULL,      -- ISO UTC
  changed_at  TEXT NOT NULL
);
CREATE TABLE sched_occurrences (
  occurrence  TEXT PRIMARY KEY,   -- '<wf>@<instant>' | '<wf>@manual:<ulid>'
  workflow_id TEXT NOT NULL,
  kind        TEXT NOT NULL,      -- schedule|manual
  instant     TEXT NOT NULL,      -- ISO UTC; request time if manual
  missed      INTEGER NOT NULL DEFAULT 0,
  deadline    TEXT,               -- instant + window, or NULL
  grp         TEXT NOT NULL,      -- concurrency group
  state       TEXT NOT NULL,      -- section 7.3
  reason      TEXT,
  attempt     INTEGER NOT NULL DEFAULT 0,
  reruns      INTEGER NOT NULL DEFAULT 0,  -- after interruptions
  next_try_at TEXT,
  by          TEXT,               -- manual: requester
  inputs      TEXT,               -- manual: JSON
  updated_at  TEXT NOT NULL
);
CREATE INDEX sched_occ_state ON sched_occurrences (state, grp);
CREATE TABLE sched_attempts (
  occurrence  TEXT NOT NULL,
  attempt     INTEGER NOT NULL,   -- 1..3; a rerun keeps the number
  rerun       INTEGER NOT NULL DEFAULT 0,
  instance    TEXT NOT NULL,      -- dshd name
  revision    TEXT NOT NULL,      -- from \`scheduled show\` at launch
  invocation  TEXT,               -- systemd InvocationID, for journalctl
  started_at  TEXT NOT NULL,
  ended_at    TEXT,
  ending      TEXT,               -- dshd lastRun.ending
  exit_code   INTEGER,
  report      TEXT,               -- report.json or final answer, <= 8 KiB
  PRIMARY KEY (occurrence, attempt, rerun)
);
-- read-only views for \`scheduled history\` and the panel (surface b.14)
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
CREATE VIEW sched_attempts_v1 AS
  SELECT occurrence, attempt, rerun, instance, revision, invocation,
         started_at, ended_at, ending, exit_code, report
  FROM sched_attempts;
`;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function makeTestDir() {
  return mkdtempSync(join(os.tmpdir(), 'scheduled-history-test-'));
}

function makeMockContext(stateDir, opts = {}) {
  const stdout = [];
  const stderr = [];
  return {
    ctx: {
      home: stateDir,
      stateDir,
      env: {},
      now: opts.now || (() => new Date('2026-11-12T12:00:00.000Z')),
      out: (s) => stdout.push(s),
      err: (s) => stderr.push(s),
      uid: 1000,
      dshd: opts.dshd ?? '/bin/false',
      systemctl: '/bin/false',
      floorUrl: 'http://127.0.0.1:3082',
      machineIdFile: '/dev/null',
      ...opts,
    },
    stdout,
    stderr,
    getOut: () => stdout.join(''),
    getErr: () => stderr.join(''),
  };
}

function seedDatabase(dbPath) {
  const db = new DatabaseSync(dbPath);
  db.exec(DESIGN_5_4_DDL);

  // Seed sample rows from DESIGN b.11
  // Row 1: 12 Nov 01:00 Paris (2026-11-12T00:00:00.000Z), done, attempt 2, receipt ok 04:12
  db.exec(`
    INSERT INTO sched_occurrences (occurrence, workflow_id, kind, instant, state, attempt, updated_at, grp)
    VALUES ('master:fleet-nightly@2026-11-12T00:00:00.000Z', 'master:fleet-nightly', 'schedule', '2026-11-12T00:00:00.000Z', 'done', 2, '2026-11-12T04:12:00.000Z', 'default');
    INSERT INTO sched_attempts (occurrence, attempt, rerun, instance, revision, started_at, ended_at, report)
    VALUES ('master:fleet-nightly@2026-11-12T00:00:00.000Z', 1, 0, 'sch-master-fleet-nightly-20261112t0000z', '3f2a9c1e0b7d', '2026-11-12T00:01:00.000Z', '2026-11-12T00:05:00.000Z', 'first fail');
    INSERT INTO sched_attempts (occurrence, attempt, rerun, instance, revision, started_at, ended_at, ending, exit_code, report)
    VALUES ('master:fleet-nightly@2026-11-12T00:00:00.000Z', 2, 0, 'sch-master-fleet-nightly-20261112t0000z-r1', '3f2a9c1e0b7d', '2026-11-12T04:10:00.000Z', '2026-11-12T04:12:00.000Z', 'success', 0, 'receipt ok 04:12');

    -- Row 2: 11 Nov 01:00 Paris (2026-11-11T00:00:00.000Z), missed, attempt 0, command exited 1
    INSERT INTO sched_occurrences (occurrence, workflow_id, kind, instant, missed, state, reason, attempt, updated_at, grp)
    VALUES ('master:fleet-nightly@2026-11-11T00:00:00.000Z', 'master:fleet-nightly', 'schedule', '2026-11-11T00:00:00.000Z', 1, 'missed', 'command exited 1', 0, '2026-11-11T00:01:00.000Z', 'default');

    -- Row 3: 10 Nov 15:42 Paris (2026-11-10T14:42:00.000Z), failed, attempt 1, by panel; exit 1
    INSERT INTO sched_occurrences (occurrence, workflow_id, kind, instant, state, reason, attempt, "by", updated_at, grp)
    VALUES ('master:fleet-nightly@manual:01JCF3W2Q9V7T8K4M6N0P2R5S8', 'master:fleet-nightly', 'manual', '2026-11-10T14:42:00.000Z', 'failed', 'exit 1', 1, 'panel', '2026-11-10T14:45:00.000Z', 'default');
    INSERT INTO sched_attempts (occurrence, attempt, rerun, instance, revision, started_at, ended_at, ending, exit_code, report)
    VALUES ('master:fleet-nightly@manual:01JCF3W2Q9V7T8K4M6N0P2R5S8', 1, 0, 'now-master-fleet-nightly-20261110t1442z-p2r5s8', '3f2a9c1e0b7d', '2026-11-10T14:42:05.000Z', '2026-11-10T14:45:00.000Z', 'failed', 1, 'panel run error');

    -- A second workflow for --all testing
    INSERT INTO sched_occurrences (occurrence, workflow_id, kind, instant, state, attempt, updated_at, grp)
    VALUES ('master:journal-day@2026-11-12T00:00:00.000Z', 'master:journal-day', 'schedule', '2026-11-12T00:00:00.000Z', 'done', 1, '2026-11-12T00:02:00.000Z', 'default');
    INSERT INTO sched_attempts (occurrence, attempt, rerun, instance, revision, started_at, ended_at, ending, exit_code, report)
    VALUES ('master:journal-day@2026-11-12T00:00:00.000Z', 1, 0, 'sch-master-journal-day-20261112t0000z', '8a7b6c5d4e3f', '2026-11-12T00:00:10.000Z', '2026-11-12T00:02:00.000Z', 'success', 0, 'satisfied 11 Nov');
  `);
  db.close();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('C2.15: Read-only database connection and views', () => {
  let tmp;
  let dbPath;

  before(() => {
    tmp = makeTestDir();
    dbPath = join(tmp, 'orchestrator.sqlite');
    seedDatabase(dbPath);
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('opens orchestrator.sqlite with readOnly: true and an INSERT fails with readonly error', () => {
    const db = openHistoryDb(dbPath);
    try {
      assert.throws(
        () => {
          db.exec(
            "INSERT INTO sched_occurrences (occurrence, workflow_id, kind, instant, state, updated_at, grp) VALUES ('dummy', 'dummy', 'schedule', '2026-11-12T00:00:00Z', 'done', '2026-11-12T00:00:00Z', 'grp')"
          );
        },
        (err) => {
          assert.equal(err.code, 'ERR_SQLITE_ERROR');
          assert.match(err.message, /attempt to write a readonly database/i);
          return true;
        }
      );
    } finally {
      db.close();
    }
  });

  it('an INSERT through the verb’s connection fails with readonly error', async () => {
    const { ctx } = makeMockContext(tmp);
    const dbRef = {};
    ctx._dbRef = dbRef;

    const code = await main(['master:fleet-nightly'], ctx);
    assert.equal(code, 0);
    assert.ok(dbRef.current, 'verb should have populated dbRef.current');

    try {
      assert.throws(
        () => {
          dbRef.current.exec("INSERT INTO sched_attempts (occurrence, attempt, instance, revision, started_at) VALUES ('x', 1, 'inst', 'rev', 'now')");
        },
        (err) => {
          assert.equal(err.code, 'ERR_SQLITE_ERROR');
          assert.match(err.message, /attempt to write a readonly database/i);
          return true;
        }
      );
    } finally {
      dbRef.current.close();
    }
  });

  it('reads only sched_history_v1 and sched_attempts_v1', () => {
    const db = openHistoryDb(dbPath);
    try {
      // Query history uses only sched_history_v1
      const historyRows = queryHistory(db, { id: 'master:fleet-nightly' });
      assert.equal(historyRows.length, 3);

      // Query attempts uses only sched_attempts_v1
      const attemptRows = queryAttempts(db, 'master:fleet-nightly@2026-11-12T00:00:00.000Z');
      assert.equal(attemptRows.length, 2);
    } finally {
      db.close();
    }
  });
});

describe('scheduled history ID: table and JSON output', () => {
  let tmp;
  let dbPath;

  before(() => {
    tmp = makeTestDir();
    dbPath = join(tmp, 'orchestrator.sqlite');
    seedDatabase(dbPath);
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('prints the exact table format matching DESIGN b.11', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly'], ctx);
    assert.equal(code, 0);

    const out = getOut();
    const expected =
`OCCURRENCE (Paris)  KIND      STATE   ATTEMPTS  NOTE
12 Nov 01:00        schedule  done    2         receipt ok 04:12
11 Nov 01:00        schedule  missed  0         command exited 1
10 Nov 15:42        manual    failed  1         by panel; exit 1
`;
    assert.equal(out, expected);
  });

  it('outputs valid JSON when --json is passed', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '--json'], ctx);
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 3);
    assert.equal(data[0].workflow, 'master:fleet-nightly');
    assert.equal(data[0].state, 'done');
    assert.equal(data[0].attempt, 2);
    assert.equal(data[0].report, 'receipt ok 04:12');
    assert.equal(data[1].state, 'missed');
    assert.equal(data[1].reason, 'command exited 1');
    assert.equal(data[2].kind, 'manual');
    assert.equal(data[2].by, 'panel');
    assert.equal(data[2].reason, 'exit 1');
  });

  it('limits output with -n', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '-n', '2', '--json'], ctx);
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.equal(data.length, 2);
    assert.equal(data[0].due_at, '2026-11-12T00:00:00.000Z');
    assert.equal(data[1].due_at, '2026-11-11T00:00:00.000Z');
  });

  it('filters with --since', async () => {
    // Current test clock is 2026-11-12T12:00:00.000Z
    // 24h back is 2026-11-11T12:00:00.000Z
    // Row 1 (Nov 12 00:00Z) is inside 24h
    // Row 2 (Nov 11 00:00Z) is 36h ago, outside 24h
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '--since', '24h', '--json'], ctx);
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.equal(data.length, 1);
    assert.equal(data[0].due_at, '2026-11-12T00:00:00.000Z');
  });
});

describe('scheduled history --all', () => {
  let tmp;
  let dbPath;

  before(() => {
    tmp = makeTestDir();
    dbPath = join(tmp, 'orchestrator.sqlite');
    seedDatabase(dbPath);
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('includes WORKFLOW column in table when --all is passed', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['--all'], ctx);
    assert.equal(code, 0);

    const out = getOut();
    assert.match(out, /^WORKFLOW\s+OCCURRENCE \(Paris\)\s+KIND/);
    assert.ok(out.includes('master:fleet-nightly'));
    assert.ok(out.includes('master:journal-day'));
  });

  it('returns rows across all workflows when --all --json is passed', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['--all', '--json'], ctx);
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 4);
    const workflows = new Set(data.map((r) => r.workflow));
    assert.ok(workflows.has('master:fleet-nightly'));
    assert.ok(workflows.has('master:journal-day'));
  });
});

describe('scheduled history ID --occurrence KEY', () => {
  let tmp;
  let dbPath;

  before(() => {
    tmp = makeTestDir();
    dbPath = join(tmp, 'orchestrator.sqlite');
    seedDatabase(dbPath);
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('lists attempts with dshd commands when instance is not pruned', async () => {
    // Mock dshd that returns active instance (exit 0)
    const mockDshd = join(tmp, 'mock-dshd-active.sh');
    writeFileSync(mockDshd, '#!/bin/sh\necho \'{"state":"running"}\'\nexit 0\n');
    chmodSync(mockDshd, 0o755);

    const { ctx, getOut } = makeMockContext(tmp, { dshd: mockDshd });
    const code = await main(
      ['master:fleet-nightly', '--occurrence', 'master:fleet-nightly@2026-11-12T00:00:00.000Z'],
      ctx
    );
    assert.equal(code, 0);

    const out = getOut();
    assert.ok(out.includes('Attempt 1 (rerun 0)'));
    assert.ok(out.includes('Attempt 2 (rerun 0)'));
    assert.ok(out.includes('Instance:   sch-master-fleet-nightly-20261112t0000z-r1'));
    assert.ok(out.includes('Report:'));
    assert.ok(out.includes('receipt ok 04:12'));
    assert.ok(out.includes('dshd read sch-master-fleet-nightly-20261112t0000z-r1'));
    assert.ok(out.includes('journalctl --user -u dshd@sch-master-fleet-nightly-20261112t0000z-r1.service'));
  });

  it('gives an instance pruned note with journalctl command when instance is pruned', async () => {
    // Mock dshd that returns exit 1 (pruned / not found)
    const mockDshd = join(tmp, 'mock-dshd-pruned.sh');
    writeFileSync(mockDshd, '#!/bin/sh\nexit 1\n');
    chmodSync(mockDshd, 0o755);

    const { ctx, getOut } = makeMockContext(tmp, { dshd: mockDshd });
    const code = await main(
      ['master:fleet-nightly', '--occurrence', 'master:fleet-nightly@2026-11-12T00:00:00.000Z'],
      ctx
    );
    assert.equal(code, 0);

    const out = getOut();
    assert.ok(out.includes('instance pruned'), 'must contain instance pruned note');
    assert.ok(
      out.includes('journalctl --user -u dshd@sch-master-fleet-nightly-20261112t0000z-r1.service'),
      'must print journalctl command'
    );
    assert.ok(!out.includes('dshd read'), 'pruned instance must not suggest dshd read');
  });

  it('outputs JSON attempts when --json is passed', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(
      ['master:fleet-nightly', '--occurrence', 'master:fleet-nightly@2026-11-12T00:00:00.000Z', '--json'],
      ctx
    );
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 2);
    assert.equal(data[0].attempt, 1);
    assert.equal(data[1].attempt, 2);
    assert.equal(data[1].instance, 'sch-master-fleet-nightly-20261112t0000z-r1');
  });

  it('--log with pruned instance outputs instance pruned note and journalctl command', async () => {
    const mockDshd = join(tmp, 'mock-dshd-pruned-log.sh');
    writeFileSync(mockDshd, '#!/bin/sh\nexit 1\n');
    chmodSync(mockDshd, 0o755);

    const { ctx, getOut } = makeMockContext(tmp, { dshd: mockDshd });
    const code = await main(
      ['master:fleet-nightly', '--occurrence', 'master:fleet-nightly@2026-11-12T00:00:00.000Z', '--log'],
      ctx
    );
    assert.equal(code, 0);

    const out = getOut();
    assert.equal(
      out,
      'instance pruned\njournalctl --user -u dshd@sch-master-fleet-nightly-20261112t0000z-r1.service\n'
    );
  });
});

describe('scheduled history ID --edits', () => {
  let tmp;

  before(() => {
    tmp = makeTestDir();
    const revDir = join(tmp, 'revisions');
    mkdirSync(revDir, { recursive: true });
    writeFileSync(
      join(revDir, 'index.jsonl'),
      JSON.stringify({
        id: 'master:fleet-nightly',
        revision: '3f2a9c1e0b7d',
        seen_at: '2026-11-11T03:12:00.000Z', // 04:12 in Paris
        by: 'tom',
      }) +
        '\n' +
        JSON.stringify({
          id: 'master:fleet-nightly',
          revision: '1a2b3c4d5e6f',
          seen_at: '2026-11-09T09:00:00.000Z',
          by: 'alice',
        }) +
        '\n' +
        JSON.stringify({
          id: 'other:workflow',
          revision: '999999999999',
          seen_at: '2026-11-10T10:00:00.000Z',
          by: 'bob',
        }) +
        '\n'
    );
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('prints revision edits table', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '--edits'], ctx);
    assert.equal(code, 0);

    const out = getOut();
    assert.match(out, /^REVISION\s+SEEN \(Paris\)\s+BY/);
    assert.ok(out.includes('3f2a9c1e0b7d'));
    assert.ok(out.includes('11 Nov 04:12'));
    assert.ok(out.includes('tom'));
    assert.ok(out.includes('1a2b3c4d5e6f'));
    assert.ok(!out.includes('999999999999'), 'should filter by workflow ID');
  });

  it('prints JSON revisions with --json', async () => {
    const { ctx, getOut } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '--edits', '--json'], ctx);
    assert.equal(code, 0);

    const data = JSON.parse(getOut());
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 2);
    assert.equal(data[0].revision, '3f2a9c1e0b7d');
    assert.equal(data[0].by, 'tom');
    assert.equal(data[1].revision, '1a2b3c4d5e6f');
  });

  it('--diff exits 2 with not built yet message', async () => {
    const { ctx, getErr } = makeMockContext(tmp);
    const code = await main(['master:fleet-nightly', '--edits', '--diff'], ctx);
    assert.equal(code, 2);
    assert.match(getErr(), /history --diff is not built yet/);
  });
});

describe('Error handling and exit codes', () => {
  it('exits 4 when database is missing', async () => {
    const tmp = makeTestDir();
    try {
      const { ctx, getErr } = makeMockContext(tmp);
      const code = await main(['master:fleet-nightly'], ctx);
      assert.equal(code, 4);
      assert.match(getErr(), /database not found or unreadable/i);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('exits 4 when database is unreadable/corrupted', async () => {
    const tmp = makeTestDir();
    try {
      const dbPath = join(tmp, 'orchestrator.sqlite');
      writeFileSync(dbPath, 'NOT A SQLITE DATABASE');
      const { ctx, getErr } = makeMockContext(tmp);
      const code = await main(['master:fleet-nightly'], ctx);
      assert.equal(code, 4);
      assert.match(getErr(), /database not found or unreadable/i);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('exits 2 on invalid arguments or missing flags', async () => {
    const tmp = makeTestDir();
    try {
      const { ctx: c1 } = makeMockContext(tmp);
      assert.equal(await main([], c1), 2, 'no arguments');

      const { ctx: c2 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '--all'], c2), 2, 'both ID and --all');

      const { ctx: c3 } = makeMockContext(tmp);
      assert.equal(await main(['--all', '--occurrence', 'key'], c3), 2, '--all with --occurrence');

      const { ctx: c4 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '--occurrence', 'key', '--edits'], c4), 2, '--occurrence and --edits');

      const { ctx: c5 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '-n', 'bad'], c5), 2, 'invalid -n');

      const { ctx: c6 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '--since', 'invalid'], c6), 2, 'invalid --since');

      const { ctx: c7 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '--diff'], c7), 2, '--diff without --edits');

      const { ctx: c8 } = makeMockContext(tmp);
      assert.equal(await main(['wf', '--log'], c8), 2, '--log without --occurrence');
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });
});

describe('CLI process execution end-to-end', () => {
  let tmp;

  before(() => {
    tmp = makeTestDir();
    seedDatabase(join(tmp, 'orchestrator.sqlite'));
  });

  after(async () => {
    await rm(tmp, { recursive: true, force: true });
  });

  it('cli.mjs invokes history and prints table', () => {
    const r = spawnSync(
      process.execPath,
      [CLI_PATH, 'history', 'master:fleet-nightly', '--state-dir', tmp],
      { encoding: 'utf8' }
    );
    assert.equal(r.status, 0);
    assert.match(r.stdout, /^OCCURRENCE \(Paris\)\s+KIND\s+STATE/);
    assert.ok(r.stdout.includes('12 Nov 01:00'));
    assert.ok(r.stdout.includes('receipt ok 04:12'));
  });

  it('cli.mjs history --all --json outputs JSON', () => {
    const r = spawnSync(
      process.execPath,
      [CLI_PATH, 'history', '--all', '--json', '--state-dir', tmp],
      { encoding: 'utf8' }
    );
    assert.equal(r.status, 0);
    const data = JSON.parse(r.stdout);
    assert.ok(Array.isArray(data));
    assert.equal(data.length, 4);
  });
});

describe('Helper unit functions', () => {
  it('parseDurationMs parses various unit strings', () => {
    assert.equal(parseDurationMs('100ms'), 100);
    assert.equal(parseDurationMs('10s'), 10000);
    assert.equal(parseDurationMs('30m'), 1800000);
    assert.equal(parseDurationMs('24h'), 86400000);
    assert.equal(parseDurationMs('7d'), 604800000);
    assert.equal(parseDurationMs('2w'), 1209600000);
    assert.throws(() => parseDurationMs(''), /Invalid duration/);
    assert.throws(() => parseDurationMs('bad'), /Invalid duration format/);
    assert.throws(() => parseDurationMs('10xyz'), /Unknown duration unit/);
  });

  it('formatParisDate formats dates in Europe/Paris timezone', () => {
    assert.equal(formatParisDate('2026-11-12T00:00:00.000Z'), '12 Nov 01:00');
    assert.equal(formatParisDate('2026-11-11T00:00:00.000Z'), '11 Nov 01:00');
    assert.equal(formatParisDate('2026-11-10T14:42:00.000Z'), '10 Nov 15:42');
    assert.equal(formatParisDate(null), '-');
  });

  it('deriveNote matches expected notes', () => {
    assert.equal(deriveNote({ by: null, reason: null, report: 'receipt ok 04:12' }), 'receipt ok 04:12');
    assert.equal(deriveNote({ by: null, reason: 'command exited 1', report: null }), 'command exited 1');
    assert.equal(deriveNote({ by: 'panel', reason: 'exit 1', report: 'err' }), 'by panel; exit 1');
    assert.equal(deriveNote({ by: null, reason: null, report: null }), '');
  });
});
