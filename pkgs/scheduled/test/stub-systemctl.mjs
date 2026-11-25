#!/usr/bin/env node
// stub-systemctl.mjs — a fake `systemctl --user` for one floor unit, driven by a JSON state file.
//
// `show` prints the requested properties (`--property=A,B` or `-p A,B`) as KEY=VALUE lines, from the
// state file; `start` is recorded and answers exit 0 unless the file says otherwise. Every argv is appended
// to $STUB_SYSTEMCTL_LOG as one JSON line. The state file ($STUB_SYSTEMCTL_STATE) holds either a named
// state, `{ "state": "stopped" }`, or raw properties, `{ "LoadState": "loaded", "ActiveState": "failed", ... }`,
// plus optional overrides `show: { code, stdout, stderr }` and `start: { code, stderr }`. A missing file is
// a unit systemd does not know: LoadState=not-found, exit 0, as the real `systemctl show` answers.

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const props = (LoadState, ActiveState, SubState, Result = 'success', ExecMainStatus = '0') => ({ LoadState, ActiveState, SubState, Result, ExecMainStatus });

/** Named states as `systemctl show` reports them. */
export const UNIT_STATES = {
  running: props('loaded', 'active', 'running'),
  reloading: props('loaded', 'reloading', 'reload'),
  starting: props('loaded', 'activating', 'start'),
  'auto-restart': props('loaded', 'activating', 'auto-restart', 'exit-code', '1'),
  stopping: props('loaded', 'deactivating', 'stop-sigterm'),
  stopped: props('loaded', 'inactive', 'dead'),
  failed: props('loaded', 'failed', 'failed', 'exit-code', '1'),
  killed: props('loaded', 'failed', 'failed', 'signal', '9'),
  'timed-out': props('loaded', 'failed', 'failed', 'timeout', '0'),
  masked: props('masked', 'inactive', 'dead'),
  'not-found': props('not-found', 'inactive', 'dead'),
  'bad-setting': props('bad-setting', 'inactive', 'dead'),
};

/** The unit's properties for state file content `data` (null: not found). */
export function unitProps(data) {
  if (!data) return UNIT_STATES['not-found'];
  if (typeof data.state === 'string') {
    const named = UNIT_STATES[data.state];
    if (!named) throw new Error(`stub-systemctl: unknown named state ${data.state}`);
    return named;
  }
  const { show, start, ...raw } = data;
  return { ...UNIT_STATES['not-found'], ...raw };
}

function requested(argv) {
  const names = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--property=')) names.push(...a.slice('--property='.length).split(','));
    else if (a === '-p' || a === '--property') names.push(...String(argv[++i] ?? '').split(','));
  }
  return names.filter(Boolean);
}

function main() {
  const argv = process.argv.slice(2);
  if (process.env.STUB_SYSTEMCTL_LOG) fs.appendFileSync(process.env.STUB_SYSTEMCTL_LOG, JSON.stringify(argv) + '\n');

  const file = process.env.STUB_SYSTEMCTL_STATE;
  let data = null;
  if (file && fs.existsSync(file)) {
    try {
      data = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (err) {
      process.stderr.write(`stub-systemctl: invalid JSON in ${file}: ${err.message}\n`);
      process.exit(1);
    }
  }

  const verb = argv.find((a) => !a.startsWith('-'));
  const answer = (o) => {
    if (o.stdout) process.stdout.write(o.stdout.endsWith('\n') ? o.stdout : `${o.stdout}\n`);
    if (o.stderr) process.stderr.write(o.stderr.endsWith('\n') ? o.stderr : `${o.stderr}\n`);
    process.exit(o.code ?? 0);
  };

  if (verb === 'show') {
    if (data?.show) answer(data.show);
    const p = unitProps(data);
    const names = requested(argv);
    for (const name of names.length ? names : Object.keys(p)) process.stdout.write(`${name}=${p[name] ?? ''}\n`);
    process.exit(0);
  }
  if (verb === 'start') {
    if (data?.start) answer(data.start);
    process.exit(0);
  }
  process.stderr.write(`stub-systemctl: verb not offered: ${verb}\n`);
  process.exit(1);
}

const selfPath = fileURLToPath(import.meta.url);
if (process.argv[1] && (process.argv[1] === selfPath || process.argv[1].endsWith('stub-systemctl.mjs'))) {
  main();
}
