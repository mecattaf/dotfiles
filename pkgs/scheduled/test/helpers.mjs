// helpers.mjs — a scratch home with one master agency, a heartbeat state dir, an inbox and the stub dshd.

import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STUB_DSHD = fileURLToPath(new URL('./stub-dshd.mjs', import.meta.url));
export const MACHINE_ID = '9fa751adff4f4e1d9ebed1ce31aac90b';

/**
 * A scratch environment: `home/.agency/scheduled/` (agency `master`), `state/` (the heartbeat's own), and
 * `home/.agency/state/master/inbox/scheduled` (the superagent's inbox, as on the NAS). The stub dshd answers
 * `get` from `stubState` (written to a file; `null` means not found) and logs every argv.
 */
export function setupEnv({ stubState = { state: 'running', release: { state: 'current' } }, floorInstance = null } = {}) {
  const tmpDir = fs.realpathSync(fs.mkdtempSync(join(os.tmpdir(), 'sched-test-')));
  const home = join(tmpDir, 'home');
  const agency = join(home, '.agency');
  const scheduled = join(agency, 'scheduled');
  const state = join(tmpDir, 'state');
  const inbox = join(agency, 'state', 'master', 'inbox', 'scheduled');
  fs.mkdirSync(scheduled, { recursive: true, mode: 0o700 });
  fs.chmodSync(agency, 0o700);
  fs.chmodSync(scheduled, 0o700);

  const machineIdFile = join(tmpDir, 'machine-id');
  fs.writeFileSync(machineIdFile, `${MACHINE_ID}\n`);
  const stubStateFile = join(tmpDir, 'stub-dshd-state.json');
  if (stubState !== null) fs.writeFileSync(stubStateFile, JSON.stringify(stubState));
  const stubLogFile = join(tmpDir, 'stub-dshd.log');

  const out = [];
  const err = [];
  const ctx = {
    home,
    stateDir: state,
    inbox,
    floorInstance,
    env: { STUB_DSHD_STATE: stubStateFile, STUB_DSHD_LOG: stubLogFile },
    now: () => new Date('2026-11-12T14:00:00.000Z'),
    out: (s) => out.push(s),
    err: (s) => err.push(s),
    uid: process.getuid(),
    dshd: STUB_DSHD,
    systemctl: '/nonexistent/systemctl',
    machineIdFile,
  };

  return {
    tmpDir, home, agency, scheduled, state, inbox, ctx, out, err, stubStateFile, stubLogFile,
    /** Writes `<scheduled>/<stem>.jsonc` (mode 0600) and sets its mtime, by default an hour before the clock. */
    item(stem, value, mtime = new Date('2026-11-12T00:00:00.000Z')) {
      const p = join(scheduled, `${stem}.jsonc`);
      fs.writeFileSync(p, typeof value === 'string' ? value : JSON.stringify(value, null, 2), { mode: 0o600 });
      fs.chmodSync(p, 0o600);
      fs.utimesSync(p, mtime, mtime);
      return p;
    },
    heartbeat(lastTick) {
      fs.mkdirSync(state, { recursive: true, mode: 0o700 });
      fs.writeFileSync(join(state, 'heartbeat.json'), JSON.stringify({ v: 1, machineId: MACHINE_ID, lastTick }));
    },
    setStub(value) {
      if (value === null) fs.rmSync(stubStateFile, { force: true });
      else fs.writeFileSync(stubStateFile, JSON.stringify(value));
    },
    /** Waiting record names, sorted. */
    records() {
      try { return fs.readdirSync(inbox).filter((n) => n.endsWith('.json') && !n.startsWith('.')).sort(); } catch { return []; }
    },
    record(name, dir = inbox) {
      return JSON.parse(fs.readFileSync(join(dir, name), 'utf8'));
    },
    /** Moves every waiting record into `.done/`, as the Source does after receiving it. */
    drain() {
      fs.mkdirSync(join(inbox, '.done'), { recursive: true });
      for (const n of this.records()) fs.renameSync(join(inbox, n), join(inbox, '.done', n));
    },
    intake() {
      return JSON.parse(fs.readFileSync(join(state, 'intake.json'), 'utf8'));
    },
    /** The intake entry of item `id`, the heartbeat's own census. */
    entry(id) {
      return Object.values(this.intake().files).find((f) => f.id === id);
    },
    dshdCalls() {
      if (!fs.existsSync(stubLogFile)) return [];
      return fs.readFileSync(stubLogFile, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l));
    },
    cleanup() {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    },
  };
}

/** An hourly UTC item, enabled. */
export const hourly = (extra = {}) => ({
  enabled: true,
  on: { schedule: [{ cron: '0 * * * *', timezone: 'UTC' }] },
  job: { prompt: 'Say ok.' },
  ...extra,
});
