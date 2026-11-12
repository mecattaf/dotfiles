// floor.mjs — read the floor instance's state and wake it when records wait (docs/scheduled.md, A tick, step 6).
//
// The heartbeat calls only `dshd get --json NAME` and `dshd start --json NAME`. It never stops, restarts or
// updates the floor, never reads the instance's `enabled` flag and never calls the floor's HTTP API.

import { execFile } from 'node:child_process';
import path from 'node:path';

/** States in which the floor's Source is reading the inbox: no withdrawal, no start. */
export const LIVE = new Set(['running', 'starting', 'stopping']);
const STARTABLE = new Set(['stopped', 'previous-boot', 'interrupted']);

/**
 * A runner for `dshd ARGV`: resolves `{ code, stdout, stderr }`; a spawn failure is code 7.
 * Node's own directory leads PATH, so a dshd that runs Node finds it.
 */
export function dshdRunner(dshd, env = process.env) {
  const nodeDir = path.dirname(process.execPath);
  const childEnv = { ...env, PATH: env.PATH ? `${nodeDir}:${env.PATH}` : nodeDir };
  return (argv) => new Promise((resolve) => {
    execFile(dshd, argv, { timeout: 150_000, env: childEnv }, (error, stdout, stderr) => {
      const out = String(stdout || '');
      const errText = String(stderr || '');
      if (error && typeof error.code === 'number') resolve({ code: error.code, stdout: out, stderr: errText });
      else if (error) resolve({ code: 7, stdout: out, stderr: errText || error.message });
      else resolve({ code: 0, stdout: out, stderr: errText });
    });
  });
}

/**
 * `dshd get --json NAME` once.
 * @returns {Promise<{ state: string, info: object|null, error?: string }>} state `not-found` on exit 3,
 *   `unavailable` on exit 7 or another failure
 */
export async function floorState(instance, run) {
  const res = await run(['get', '--json', instance]);
  if (res.code === 3) return { state: 'not-found', info: null };
  if (res.code !== 0) {
    let error = `exit:${res.code}`;
    try {
      const parsed = JSON.parse(res.stdout);
      error = parsed.error || parsed.reason || error;
    } catch {}
    if (error === `exit:${res.code}` && /tool[-_ ]?missing/i.test(res.stderr)) error = 'tool-missing';
    else if (error === `exit:${res.code}` && /systemd/i.test(res.stderr)) error = 'systemd-unavailable';
    return { state: 'unavailable', info: null, error };
  }
  try {
    const info = JSON.parse(res.stdout);
    return { state: info?.state || 'unknown', info };
  } catch {
    return { state: 'unavailable', info: null, error: 'invalid-json' };
  }
}

function childOf(info) {
  const last = info?.lastRun ?? {};
  if (last.child?.exitCode !== undefined && last.child?.exitCode !== null) return `exit:${last.child.exitCode}`;
  if (last.child?.signal) return `signal:${last.child.signal}`;
  if (last.exitStatus !== undefined && last.exitStatus !== null) return `exit:${last.exitStatus}`;
  if (last.signal) return `signal:${last.signal}`;
  return 'exit:1';
}

async function start(instance, run) {
  const res = await run(['start', '--json', instance]);
  let result;
  try {
    const parsed = JSON.parse(res.stdout);
    result = parsed.outcome || parsed.result;
  } catch {}
  result ||= res.code === 0 ? 'started' : 'failed';
  const ok = res.code === 0 && (result === 'started' || result === 'already-running');
  return { ok, result };
}

const quote = (s) => (/[\s"=]/.test(s) ? JSON.stringify(s) : s);

/**
 * The wake table: what to do with the floor, given its state and the records waiting after withdrawal.
 *
 * @param {object} o
 * @param {string|null} o.instance  the floor instance; null: never call dshd
 * @param {number} o.waiting
 * @param {{ state: string, info: object|null, error?: string }|null} o.floor  phase 6's read, or null when not read
 * @param {(argv: string[]) => Promise<{code: number, stdout: string, stderr: string}>} o.run
 * @returns {Promise<{ lines: string[], fault: boolean, action: 'none'|'start' }>}
 */
export async function wake({ instance, waiting, floor, run }) {
  const none = (lines = [], fault = false) => ({ lines, fault, action: 'none' });
  if (!instance || waiting === 0) return none();
  const read = floor ?? await floorState(instance, run);
  const { state, info } = read;

  if (LIVE.has(state)) return none([`<6>floor state=${state} waiting=${waiting}`]);
  if (STARTABLE.has(state)) {
    const { ok, result } = await start(instance, run);
    return { lines: [`${ok ? '<5>' : '<3>'}floor action=start state=${state} waiting=${waiting} result=${result}`], fault: !ok, action: 'start' };
  }
  if (state === 'failed') {
    const { result } = await start(instance, run);
    return { lines: [`<3>floor action=start state=failed child=${childOf(info)} result=${result}`], fault: true, action: 'start' };
  }
  if (state === 'masked') return none([`<4>floor masked waiting=${waiting}`]);
  if (state === 'not-found') return none([`<3>floor state=not-found waiting=${waiting}`], true);
  if (state === 'unavailable') return none([`<3>floor state=unavailable error=${quote(read.error ?? 'unknown')} waiting=${waiting}`], true);
  const remedy = info?.remedy ? ` remedy=${quote(info.remedy)}` : '';
  return none([`<3>floor state=${state}${remedy} waiting=${waiting}`], true);
}
