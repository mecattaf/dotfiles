// floor.mjs — read the floor unit's state and wake it when records wait (docs/scheduled.md, A tick, step 6).
//
// The floor is a systemd user unit named by SCHEDULED_FLOOR_UNIT (`factory-floor.service`). The heartbeat
// calls only `systemctl --user show` and `systemctl --user start --no-block` on it. It never stops,
// restarts, masks or reloads the unit, never waits for the start job and never calls the floor's HTTP API.

import { execFile } from 'node:child_process';

/** States in which the floor's Source is reading the inbox: no withdrawal, no start. */
export const LIVE = new Set(['running', 'starting', 'stopping']);

/** The properties one read asks for; `systemctl show` prints them as KEY=VALUE lines. */
export const PROPERTIES = ['LoadState', 'ActiveState', 'SubState', 'Result', 'ExecMainStatus'];

/**
 * A full unit name: systemd's unit-name characters, an optional instance, and a `.service` or `.target`
 * suffix. A glob, a path or a leading `-` is refused before systemctl sees it: `systemctl start` expands
 * globs over loaded units and turns a path into a mount unit.
 */
const UNIT_NAME = /^[A-Za-z0-9:_.\\-]+(@[A-Za-z0-9:_.\\-]*)?\.(service|target)$/;
export const validUnitName = (unit) => typeof unit === 'string' && UNIT_NAME.test(unit) && !unit.startsWith('-') && unit.length <= 255;

// ActiveState → the wake table's state. A unit in a transition is live whatever its LoadState: a unit
// whose file vanished while it runs still has a running Source.
const IN_MOTION = { active: 'running', reloading: 'running', refreshing: 'running', activating: 'starting', deactivating: 'stopping' };
const AT_REST = { inactive: 'stopped', failed: 'failed' };

/**
 * A runner for `systemctl ARGV`: resolves `{ code, stdout, stderr }`. A spawn failure or a timeout is
 * code -1 with the error text in stderr.
 */
export function unitRunner(systemctl, env = process.env) {
  return (argv) => new Promise((resolve) => {
    execFile(systemctl, argv, { timeout: 30_000, env }, (error, stdout, stderr) => {
      const out = String(stdout || '');
      const errText = String(stderr || '');
      if (error && typeof error.code === 'number') resolve({ code: error.code, stdout: out, stderr: errText });
      else if (error) resolve({ code: -1, stdout: out, stderr: error.killed ? `timeout after 30 s: ${systemctl}` : (errText || error.message) });
      else resolve({ code: 0, stdout: out, stderr: errText });
    });
  });
}

/** The first non-empty stderr line, short enough for a journal field; else `exit:N`. */
function errorText(res) {
  const line = String(res.stderr || '').split('\n').map((l) => l.trim()).find(Boolean);
  if (!line) return `exit:${res.code}`;
  return line.length > 160 ? `${line.slice(0, 157)}...` : line;
}

/** Parse `systemctl show` output into { KEY: VALUE }. */
export function parseShow(stdout) {
  const props = {};
  for (const line of String(stdout || '').split('\n')) {
    const eq = line.indexOf('=');
    if (eq > 0) props[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return props;
}

/** What a failed unit's main process did: `exit:N`, `signal:N`, or `result:<Result>`. */
function childOf(props) {
  const status = props.ExecMainStatus;
  const known = status !== undefined && status !== '' && /^\d+$/.test(status);
  if (props.Result === 'exit-code' && known) return `exit:${status}`;
  if ((props.Result === 'signal' || props.Result === 'core-dump') && known) return `signal:${status}`;
  return `result:${props.Result || 'unknown'}`;
}

/**
 * `systemctl --user show` of the floor unit, once.
 * @returns {Promise<{ state: string, info: object|null, error?: string }>} state one of running, starting,
 *   stopping, stopped, failed, masked, not-found, unavailable, or the raw LoadState/ActiveState otherwise
 */
export async function floorState(unit, run) {
  if (!validUnitName(unit)) return { state: 'unavailable', info: null, error: 'invalid-unit-name' };
  const res = await run(['--user', 'show', `--property=${PROPERTIES.join(',')}`, '--', unit]);
  if (res.code !== 0) return { state: 'unavailable', info: null, error: errorText(res) };
  const props = parseShow(res.stdout);
  const { LoadState: load, ActiveState: active } = props;
  if (!load || !active) return { state: 'unavailable', info: props, error: 'invalid-output' };
  const info = { ...props, child: childOf(props) };
  if (IN_MOTION[active]) return { state: IN_MOTION[active], info };
  if (load === 'not-found') return { state: 'not-found', info };
  if (load === 'masked') return { state: 'masked', info };
  // A unit systemd could not load (bad-setting, error): starting it fails; say where to look.
  if (load !== 'loaded') return { state: load, info: { ...info, remedy: `systemctl --user status ${unit}` } };
  if (AT_REST[active]) return { state: AT_REST[active], info };
  return { state: active, info: { ...info, remedy: `systemctl --user status ${unit}` } };
}

/** `systemctl --user start --no-block` of the floor unit: the job is queued, never waited for. */
async function start(unit, run) {
  const res = await run(['--user', 'start', '--no-block', '--', unit]);
  return res.code === 0 ? { ok: true, result: 'queued' } : { ok: false, result: 'failed', error: errorText(res) };
}

const quote = (s) => (/[\s"=]/.test(s) ? JSON.stringify(s) : s);

/**
 * The wake table: what to do with the floor, given its state and the records waiting after withdrawal.
 *
 * @param {object} o
 * @param {string|null} o.unit  the floor's systemd user unit; null: never call systemctl
 * @param {number} o.waiting
 * @param {{ state: string, info: object|null, error?: string }|null} o.floor  phase 6's read, or null when not read
 * @param {(argv: string[]) => Promise<{code: number, stdout: string, stderr: string}>} o.run
 * @returns {Promise<{ lines: string[], fault: boolean, action: 'none'|'start' }>}
 */
export async function wake({ unit, waiting, floor, run }) {
  const none = (lines = [], fault = false) => ({ lines, fault, action: 'none' });
  if (!unit || waiting === 0) return none();
  const read = floor ?? await floorState(unit, run);
  const { state, info } = read;

  if (LIVE.has(state)) return none([`<6>floor state=${state} waiting=${waiting}`]);
  if (state === 'stopped') {
    const s = await start(unit, run);
    const err = s.ok ? '' : ` error=${quote(s.error)}`;
    return { lines: [`${s.ok ? '<5>' : '<3>'}floor action=start unit=${unit} state=stopped waiting=${waiting} result=${s.result}${err}`], fault: !s.ok, action: 'start' };
  }
  if (state === 'failed') {
    const s = await start(unit, run);
    const err = s.ok ? '' : ` error=${quote(s.error)}`;
    return { lines: [`<3>floor action=start unit=${unit} state=failed child=${info?.child ?? 'result:unknown'} result=${s.result}${err}`], fault: true, action: 'start' };
  }
  if (state === 'masked') return none([`<4>floor masked waiting=${waiting}`]);
  if (state === 'not-found') return none([`<3>floor state=not-found waiting=${waiting}`], true);
  if (state === 'unavailable') return none([`<3>floor state=unavailable error=${quote(read.error ?? 'unknown')} waiting=${waiting}`], true);
  const remedy = info?.remedy ? ` remedy=${quote(info.remedy)}` : '';
  return none([`<3>floor state=${quote(state)}${remedy} waiting=${waiting}`], true);
}
