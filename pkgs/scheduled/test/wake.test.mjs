import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { wakeFloor } from '../src/lib/floor.mjs';
import { SAMPLE_FAILED_STATE } from './stub-dshd.mjs';

const STUB_DSHD_PATH = path.resolve('test/stub-dshd.mjs');

// ---------------------------------------------------------------------------
// Injected run / fetch tests covering all C3.10 wake table rows & C3.11 branches
// ---------------------------------------------------------------------------

test('C3.10 row 1: not-found (exit 3) creates nothing and exits 1', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    return { code: 3, stdout: '', stderr: 'floor not found' };
  };

  const res = await wakeFloor({ run });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], ['get', '--json', 'floor']);
  assert.equal(res.fault, true);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<3>floor error=not-found']);
});

test('C3.10 row 2: running / starting / stopping with current release does nothing and exits 0', async () => {
  for (const st of ['running', 'starting', 'stopping']) {
    const calls = [];
    const run = async (argv) => {
      calls.push(argv);
      return { code: 0, stdout: JSON.stringify({ state: st, release: { state: 'current' } }), stderr: '' };
    };

    const res = await wakeFloor({ run });
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0], ['get', '--json', 'floor']);
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, []);
  }
});

test('C3.10 row 3: stopped by intent (lastRun.ending stopped) gives <4> line and exits 0', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    return {
      code: 0,
      stdout: JSON.stringify({
        state: 'stopped',
        enabled: true,
        lastRun: { ending: 'stopped' },
      }),
      stderr: '',
    };
  };

  const res = await wakeFloor({ run, waiting: 2 });
  assert.equal(calls.length, 1);
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<4>floor action=none state=stopped ending=stopped waiting=2']);
});

test('C3.10 row 4: masked gives <4>floor masked and exits 0', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    return {
      code: 0,
      stdout: JSON.stringify({ state: 'masked' }),
      stderr: '',
    };
  };

  const res = await wakeFloor({ run });
  assert.equal(calls.length, 1);
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<4>floor masked']);
});

test('C3.10 row 5: failed gives dshd start, <3> line with child.exitCode, and exits 1', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify(SAMPLE_FAILED_STATE),
        stderr: '',
      };
    }
    if (argv[0] === 'start') {
      return { code: 0, stdout: JSON.stringify({ result: 'started' }), stderr: '' };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  const res = await wakeFloor({ run });
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0], ['get', '--json', 'floor']);
  assert.deepEqual(calls[1], ['start', '--json', 'floor']);
  assert.equal(res.fault, true); // exit 1 even when start succeeds
  assert.equal(res.action, 'start');
  assert.deepEqual(res.lines, ['<3>floor action=start state=failed child=exit:1 result=started']);
});

test('C3.10 row 5: failed with child.signal reports signal:<signal>', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({
          state: 'failed',
          lastRun: {
            ending: 'failed',
            exitCode: 'killed',
            exitStatus: '9',
            child: { signal: 'SIGKILL' },
          },
        }),
        stderr: '',
      };
    }
    if (argv[0] === 'start') {
      return { code: 0, stdout: JSON.stringify({ result: 'started' }), stderr: '' };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  const res = await wakeFloor({ run });
  assert.equal(res.fault, true);
  assert.equal(res.action, 'start');
  assert.deepEqual(res.lines, ['<3>floor action=start state=failed child=signal:SIGKILL result=started']);
});

test('C3.10 row 5: failed falls back to exit:<exitStatus> when child is absent', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({
          state: 'failed',
          lastRun: {
            ending: 'failed',
            exitCode: 'exited',
            exitStatus: '2',
          },
        }),
        stderr: '',
      };
    }
    if (argv[0] === 'start') {
      return { code: 0, stdout: JSON.stringify({ result: 'started' }), stderr: '' };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  const res = await wakeFloor({ run });
  assert.equal(res.fault, true);
  assert.equal(res.action, 'start');
  assert.deepEqual(res.lines, ['<3>floor action=start state=failed child=exit:2 result=started']);
});

test('C3.10 row 6: stopped / previous-boot / interrupted with enabled true gives start and exit 0', async () => {
  for (const state of ['stopped', 'previous-boot', 'interrupted']) {
    const calls = [];
    const run = async (argv) => {
      calls.push(argv);
      if (argv[0] === 'get') {
        return {
          code: 0,
          stdout: JSON.stringify({
            state,
            enabled: true,
            lastRun: { ending: 'exited' },
          }),
          stderr: '',
        };
      }
      if (argv[0] === 'start') {
        return { code: 0, stdout: JSON.stringify({ result: 'started' }), stderr: '' };
      }
      throw new Error(`Unexpected argv: ${argv.join(' ')}`);
    };

    const res = await wakeFloor({ run, waiting: 0 });
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[1], ['start', '--json', 'floor']);
    assert.equal(res.fault, false);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, [`<5>floor action=start state=${state} waiting=0 result=started`]);
  }
});

test('C3.10 row 6: interrupted with waiting > 0 gives start and result=already-running', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({
          state: 'interrupted',
          enabled: false,
        }),
        stderr: '',
      };
    }
    if (argv[0] === 'start') {
      return { code: 0, stdout: JSON.stringify({ result: 'already-running' }), stderr: '' };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  const res = await wakeFloor({ run, waiting: 1 });
  assert.equal(calls.length, 2);
  assert.equal(res.fault, false);
  assert.equal(res.action, 'start');
  assert.deepEqual(res.lines, ['<5>floor action=start state=interrupted waiting=1 result=already-running']);
});

test('C3.10 row 6: start fails gives <3> line and exit 1 (fault true)', async () => {
  const run = async (argv) => {
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({ state: 'interrupted', enabled: true }),
        stderr: '',
      };
    }
    if (argv[0] === 'start') {
      return { code: 1, stdout: JSON.stringify({ result: 'failed' }), stderr: 'start job failed' };
    }
  };

  const res = await wakeFloor({ run, waiting: 1 });
  assert.equal(res.fault, true);
  assert.equal(res.action, 'start');
  assert.deepEqual(res.lines, ['<3>floor action=start state=interrupted waiting=1 result=failed']);
});

test('C3.10 row 7: stopped / previous-boot / interrupted with enabled false and waiting 0 does nothing and exits 0', async () => {
  for (const state of ['stopped', 'previous-boot', 'interrupted']) {
    const calls = [];
    const run = async (argv) => {
      calls.push(argv);
      return {
        code: 0,
        stdout: JSON.stringify({
          state,
          enabled: false,
          lastRun: { ending: 'stopped-without-intent' },
        }),
        stderr: '',
      };
    };

    const res = await wakeFloor({ run, waiting: 0 });
    assert.equal(calls.length, 1);
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, []);
  }
});

test('C3.10 row 8: orphaned, inconsistent, unknown give <3> line with remedy and exit 1', async () => {
  const cases = [
    { state: 'orphaned', remedy: 'reboot host', expected: '<3>floor state=orphaned remedy="reboot host"' },
    { state: 'inconsistent', remedy: 'run dshd doctor', expected: '<3>floor state=inconsistent remedy="run dshd doctor"' },
    { state: 'unknown', remedy: null, expected: '<3>floor state=unknown' },
  ];

  for (const c of cases) {
    const run = async (argv) => {
      return {
        code: 0,
        stdout: JSON.stringify({ state: c.state, remedy: c.remedy }),
        stderr: '',
      };
    };

    const res = await wakeFloor({ run });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, [c.expected]);
  }
});

test('C3.10 row 9: exit 7 (systemd-unavailable, tool-missing) gives <3> line and exit 1', async () => {
  const cases = [
    { stdout: JSON.stringify({ error: 'systemd-unavailable' }), stderr: '', expected: '<3>floor error=systemd-unavailable' },
    { stdout: '', stderr: 'dshd: tool-missing', expected: '<3>floor error=tool-missing' },
  ];

  for (const c of cases) {
    const run = async () => ({ code: 7, stdout: c.stdout, stderr: c.stderr });
    const res = await wakeFloor({ run });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, [c.expected]);
  }
});

test('C3.11 branch 1: floor running + release outdated + scheduled.evalInProgress === false runs dshd update -R --json floor once', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({
          state: 'running',
          release: { state: 'outdated' },
        }),
        stderr: '',
      };
    }
    if (argv[0] === 'update') {
      return { code: 0, stdout: JSON.stringify({ result: 'updated' }), stderr: '' };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  let fetchedUrl = null;
  const mockFetch = async (url) => {
    fetchedUrl = url;
    return {
      ok: true,
      json: async () => ({ scheduled: { evalInProgress: false } }),
    };
  };

  const res = await wakeFloor({
    run,
    fetch: mockFetch,
    floorUrl: 'http://127.0.0.1:3082',
  });

  assert.equal(fetchedUrl, 'http://127.0.0.1:3082/orchestrator/api/state');
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0], ['get', '--json', 'floor']);
  assert.deepEqual(calls[1], ['update', '-R', '--json', 'floor']);
  assert.equal(res.fault, false);
  assert.equal(res.action, 'update');
  assert.deepEqual(res.lines, ["<5>update action=update result=ok"]);
});

test('C3.11 branch 2: floor running + release outdated + scheduled.evalInProgress === true emits <6>update deferred reason=eval', async () => {
  const calls = [];
  const run = async (argv) => {
    calls.push(argv);
    if (argv[0] === 'get') {
      return {
        code: 0,
        stdout: JSON.stringify({
          state: 'running',
          release: { state: 'outdated' },
        }),
        stderr: '',
      };
    }
    throw new Error(`Unexpected argv: ${argv.join(' ')}`);
  };

  const mockFetch = async () => ({
    ok: true,
    json: async () => ({ scheduled: { evalInProgress: true } }),
  });

  const res = await wakeFloor({ run, fetch: mockFetch });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], ['get', '--json', 'floor']);
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<6>update deferred reason=eval']);
});

test('C3.11 branch 2: floor running + release outdated + scheduled.evalInProgress missing emits <6>update deferred reason=unknown', async () => {
  const run = async () => ({
    code: 0,
    stdout: JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }),
    stderr: '',
  });

  const mockFetch = async () => ({
    ok: true,
    json: async () => ({ state: 'idle' }), // no scheduled.evalInProgress
  });

  const res = await wakeFloor({ run, fetch: mockFetch });
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<6>update deferred reason=unknown']);
});

test('C3.11 branch 2: floor running + release outdated + state API HTTP error emits <6>update deferred reason=api-error', async () => {
  const run = async () => ({
    code: 0,
    stdout: JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }),
    stderr: '',
  });

  const mockFetch = async () => ({
    ok: false,
    status: 500,
    json: async () => ({ error: 'internal error' }),
  });

  const res = await wakeFloor({ run, fetch: mockFetch });
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<6>update deferred reason=api-error']);
});

test('C3.11 branch 2: floor running + release outdated + state API fetch timeout/exception emits <6>update deferred reason=api-error', async () => {
  const run = async () => ({
    code: 0,
    stdout: JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }),
    stderr: '',
  });

  const mockFetch = async () => {
    throw new Error('Connection refused / timeout');
  };

  const res = await wakeFloor({ run, fetch: mockFetch });
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<6>update deferred reason=api-error']);
});

test('C3.11 branch 2: floor running + release outdated + bad JSON response emits <6>update deferred reason=api-error', async () => {
  const run = async () => ({
    code: 0,
    stdout: JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }),
    stderr: '',
  });

  const mockFetch = async () => ({
    ok: true,
    json: async () => { throw new SyntaxError('Unexpected token'); },
  });

  const res = await wakeFloor({ run, fetch: mockFetch });
  assert.equal(res.fault, false);
  assert.equal(res.action, 'none');
  assert.deepEqual(res.lines, ['<6>update deferred reason=api-error']);
});

// ---------------------------------------------------------------------------
// Integration tests through test/stub-dshd.mjs executable script
// ---------------------------------------------------------------------------

function setupTempStubEnv() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'scheduled-test-'));
  const stateFile = path.join(tmpDir, 'state.json');
  const logFile = path.join(tmpDir, 'dshd.log');
  return {
    tmpDir,
    stateFile,
    logFile,
    cleanup: () => fs.rmSync(tmpDir, { recursive: true, force: true }),
  };
}

function readLoggedArgvs(logFile) {
  if (!fs.existsSync(logFile)) return [];
  return fs.readFileSync(logFile, 'utf8')
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

test('Integration with stub-dshd: not-found (absent state file) exits 1', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    process.env.STUB_DSHD_STATE = stateFile; // file does not exist
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<3>floor error=not-found']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: running / starting / stopping states', async () => {
  for (const st of ['running', 'starting', 'stopping']) {
    const { stateFile, logFile, cleanup } = setupTempStubEnv();
    try {
      fs.writeFileSync(stateFile, JSON.stringify({
        state: st,
        release: { state: 'current' },
      }));
      process.env.STUB_DSHD_STATE = stateFile;
      process.env.STUB_DSHD_LOG = logFile;

      const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
      assert.equal(res.fault, false);
      assert.equal(res.action, 'none');
      assert.deepEqual(res.lines, []);

      const logs = readLoggedArgvs(logFile);
      assert.equal(logs.length, 1);
      assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    } finally {
      delete process.env.STUB_DSHD_STATE;
      delete process.env.STUB_DSHD_LOG;
      cleanup();
    }
  }
});

test('Integration with stub-dshd: masked state', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({ state: 'masked' }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<4>floor masked']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: stopped by intent logs get and does not start', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'stopped',
      enabled: true,
      lastRun: { ending: 'stopped' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 3 });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<4>floor action=none state=stopped ending=stopped waiting=3']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: failed state with real lastRun shape starts floor', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      ...SAMPLE_FAILED_STATE,
      start: { result: 'started' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, ['<3>floor action=start state=failed child=exit:1 result=started']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 2);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    assert.deepEqual(logs[1], ['start', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: failed state via SAMPLE_STATES named preset', async () => {
  const { logFile, cleanup } = setupTempStubEnv();
  try {
    process.env.STUB_DSHD_STATE = 'failed';
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, ['<3>floor action=start state=failed child=exit:1 result=started']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 2);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    assert.deepEqual(logs[1], ['start', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: stopped / previous-boot / interrupted with enabled true starts floor', async () => {
  for (const st of ['stopped', 'previous-boot', 'interrupted']) {
    const { stateFile, logFile, cleanup } = setupTempStubEnv();
    try {
      fs.writeFileSync(stateFile, JSON.stringify({
        state: st,
        enabled: true,
        lastRun: { ending: 'exited' },
      }));
      process.env.STUB_DSHD_STATE = stateFile;
      process.env.STUB_DSHD_LOG = logFile;

      const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 0 });
      assert.equal(res.fault, false);
      assert.equal(res.action, 'start');
      assert.deepEqual(res.lines, [`<5>floor action=start state=${st} waiting=0 result=started`]);

      const logs = readLoggedArgvs(logFile);
      assert.equal(logs.length, 2);
      assert.deepEqual(logs[0], ['get', '--json', 'floor']);
      assert.deepEqual(logs[1], ['start', '--json', 'floor']);
    } finally {
      delete process.env.STUB_DSHD_STATE;
      delete process.env.STUB_DSHD_LOG;
      cleanup();
    }
  }
});

test('Integration with stub-dshd: interrupted state with waiting starts floor', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'interrupted',
      enabled: false,
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 1 });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, ['<5>floor action=start state=interrupted waiting=1 result=started']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 2);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    assert.deepEqual(logs[1], ['start', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: stopped / previous-boot / interrupted with enabled false and waiting 0 does nothing', async () => {
  for (const st of ['stopped', 'previous-boot', 'interrupted']) {
    const { stateFile, logFile, cleanup } = setupTempStubEnv();
    try {
      fs.writeFileSync(stateFile, JSON.stringify({
        state: st,
        enabled: false,
        lastRun: { ending: 'stopped-without-intent' },
      }));
      process.env.STUB_DSHD_STATE = stateFile;
      process.env.STUB_DSHD_LOG = logFile;

      const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 0 });
      assert.equal(res.fault, false);
      assert.equal(res.action, 'none');
      assert.deepEqual(res.lines, []);

      const logs = readLoggedArgvs(logFile);
      assert.equal(logs.length, 1);
      assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    } finally {
      delete process.env.STUB_DSHD_STATE;
      delete process.env.STUB_DSHD_LOG;
      cleanup();
    }
  }
});

test('Integration with stub-dshd: start returns already-running', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'interrupted',
      enabled: true,
      start: { result: 'already-running' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 1 });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, ['<5>floor action=start state=interrupted waiting=1 result=already-running']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: start fails', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'interrupted',
      enabled: true,
      start: { exitCode: 1, result: 'failed', stderr: 'start failed' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, waiting: 1 });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'start');
    assert.deepEqual(res.lines, ['<3>floor action=start state=interrupted waiting=1 result=failed']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd: orphaned, inconsistent, unknown states', async () => {
  const cases = [
    { state: 'orphaned', remedy: 'reboot', line: '<3>floor state=orphaned remedy=reboot' },
    { state: 'inconsistent', remedy: 'run dshd doctor', line: '<3>floor state=inconsistent remedy="run dshd doctor"' },
    { state: 'unknown', remedy: null, line: '<3>floor state=unknown' },
  ];

  for (const c of cases) {
    const { stateFile, logFile, cleanup } = setupTempStubEnv();
    try {
      fs.writeFileSync(stateFile, JSON.stringify({
        state: c.state,
        remedy: c.remedy,
      }));
      process.env.STUB_DSHD_STATE = stateFile;
      process.env.STUB_DSHD_LOG = logFile;

      const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
      assert.equal(res.fault, true);
      assert.equal(res.action, 'none');
      assert.deepEqual(res.lines, [c.line]);

      const logs = readLoggedArgvs(logFile);
      assert.equal(logs.length, 1);
      assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    } finally {
      delete process.env.STUB_DSHD_STATE;
      delete process.env.STUB_DSHD_LOG;
      cleanup();
    }
  }
});

test('Integration with stub-dshd: exit 7 logs get and exits 1', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      exitCode: 7,
      error: 'systemd-unavailable',
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH });
    assert.equal(res.fault, true);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<3>floor error=systemd-unavailable']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd via SCHEDULED_DSHD environment variable', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  try {
    fs.writeFileSync(stateFile, JSON.stringify({ state: 'masked' }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;
    process.env.SCHEDULED_DSHD = STUB_DSHD_PATH;

    const res = await wakeFloor({});
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<4>floor masked']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    delete process.env.SCHEDULED_DSHD;
    cleanup();
  }
});

test('Integration with stub-dshd and local HTTP server: update executed when scheduled.evalInProgress === false', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  const server = http.createServer((req, res) => {
    if (req.url === '/orchestrator/api/state') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ scheduled: { evalInProgress: false } }));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const floorUrl = `http://127.0.0.1:${port}`;

  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
      update: { result: 'updated' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, floorUrl });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'update');
    assert.deepEqual(res.lines, ["<5>update action=update result=ok"]);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 2);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
    assert.deepEqual(logs[1], ['update', '-R', '--json', 'floor']);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd and local HTTP server: update deferred when scheduled.evalInProgress === true', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  const server = http.createServer((req, res) => {
    if (req.url === '/orchestrator/api/state') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ scheduled: { evalInProgress: true } }));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const floorUrl = `http://127.0.0.1:${port}`;

  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, floorUrl });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<6>update deferred reason=eval']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd and local HTTP server: update deferred when scheduled.evalInProgress is missing', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  const server = http.createServer((req, res) => {
    if (req.url === '/orchestrator/api/state') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ scheduled: {} }));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const floorUrl = `http://127.0.0.1:${port}`;

  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, floorUrl });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<6>update deferred reason=unknown']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});

test('Integration with stub-dshd and local HTTP server: update deferred on 500 error', async () => {
  const { stateFile, logFile, cleanup } = setupTempStubEnv();
  const server = http.createServer((req, res) => {
    res.writeHead(500);
    res.end('Server Error');
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const floorUrl = `http://127.0.0.1:${port}`;

  try {
    fs.writeFileSync(stateFile, JSON.stringify({
      state: 'running',
      release: { state: 'outdated' },
    }));
    process.env.STUB_DSHD_STATE = stateFile;
    process.env.STUB_DSHD_LOG = logFile;

    const res = await wakeFloor({ dshd: STUB_DSHD_PATH, floorUrl });
    assert.equal(res.fault, false);
    assert.equal(res.action, 'none');
    assert.deepEqual(res.lines, ['<6>update deferred reason=api-error']);

    const logs = readLoggedArgvs(logFile);
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0], ['get', '--json', 'floor']);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete process.env.STUB_DSHD_STATE;
    delete process.env.STUB_DSHD_LOG;
    cleanup();
  }
});
