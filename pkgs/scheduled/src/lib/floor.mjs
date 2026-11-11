import { execFile } from 'node:child_process';
import path from 'node:path';

/**
 * Default child_process runner for dshd.
 */
function defaultRun(dshd) {
  const nodeDir = path.dirname(process.execPath);
  const env = {
    ...process.env,
    PATH: process.env.PATH ? `${nodeDir}:${process.env.PATH}` : nodeDir,
  };
  return (argv) => new Promise((resolve) => {
    execFile(dshd, argv, { timeout: 150_000, env }, (error, stdout, stderr) => {
      const outStr = String(stdout || '');
      const errStr = String(stderr || '');
      if (error && typeof error.code === 'number') {
        resolve({ code: error.code, stdout: outStr, stderr: errStr });
      } else if (error) {
        // e.g. ENOENT (tool missing) or spawned failure
        resolve({ code: 7, stdout: outStr, stderr: errStr || error.message });
      } else {
        resolve({ code: 0, stdout: outStr, stderr: errStr });
      }
    });
  });
}

/**
 * Phase 7 of the tick: the wake table and the update rule.
 *
 * @param {object} options
 * @param {string} [options.dshd]
 * @param {string} [options.floorUrl]
 * @param {number|boolean} [options.waiting]
 * @param {(argv: string[]) => Promise<{code: number, stdout: string, stderr: string}>} [options.run]
 * @param {(url: string, init?: object) => Promise<Response>} [options.fetch]
 * @returns {Promise<{lines: string[], fault: boolean, action: string}>}
 */
export async function wakeFloor({
  dshd = process.env.SCHEDULED_DSHD || '/run/current-system/sw/bin/dshd',
  floorUrl = process.env.SCHEDULED_FLOOR_URL || 'http://127.0.0.1:3082',
  waiting = 0,
  run,
  fetch: customFetch,
} = {}) {
  const runner = run || defaultRun(dshd);
  const fetcher = customFetch || ((url, init) => globalThis.fetch(url, { ...init, signal: AbortSignal.timeout(5000) }));

  const waitingCount = typeof waiting === 'number' ? waiting : (waiting ? 1 : 0);
  const hasWaiting = waitingCount > 0;

  // 1. Read dshd get --json floor
  const getRes = await runner(['get', '--json', 'floor']);

  // Handle exit 3: not-found
  if (getRes.code === 3) {
    return {
      lines: ['<3>floor error=not-found'],
      fault: true,
      action: 'none',
    };
  }

  // Handle exit 7: systemd-unavailable / tool-missing
  if (getRes.code === 7) {
    let errorDetail = 'systemd-unavailable';
    if (getRes.stdout) {
      try {
        const parsed = JSON.parse(getRes.stdout);
        if (parsed.error) errorDetail = parsed.error;
        else if (parsed.reason) errorDetail = parsed.reason;
      } catch {}
    }
    if (errorDetail === 'systemd-unavailable' && getRes.stderr) {
      if (/tool[-_ ]?missing/i.test(getRes.stderr)) {
        errorDetail = 'tool-missing';
      } else if (/systemd/i.test(getRes.stderr)) {
        errorDetail = 'systemd-unavailable';
      }
    }
    return {
      lines: [`<3>floor error=${errorDetail}`],
      fault: true,
      action: 'none',
    };
  }

  // Handle any other non-zero exit code
  if (getRes.code !== 0) {
    return {
      lines: [`<3>floor error=exit:${getRes.code}`],
      fault: true,
      action: 'none',
    };
  }

  // Parse JSON output
  let info;
  try {
    info = JSON.parse(getRes.stdout);
  } catch (err) {
    return {
      lines: ['<3>floor error=invalid-json'],
      fault: true,
      action: 'none',
    };
  }

  const state = info?.state || 'unknown';
  const enabled = Boolean(info?.enabled);
  const ending = info?.lastRun?.ending;
  const remedy = info?.remedy;
  const releaseState = info?.release?.state;

  // 2. Wake table evaluation

  // State: masked
  if (state === 'masked') {
    return {
      lines: ['<4>floor masked'],
      fault: false,
      action: 'none',
    };
  }

  // State: stopped with ending 'stopped' (intent)
  if (state === 'stopped' && ending === 'stopped') {
    return {
      lines: [`<4>floor action=none state=stopped ending=stopped waiting=${waitingCount}`],
      fault: false,
      action: 'none',
    };
  }

  // State: failed
  if (state === 'failed') {
    let child = 'exit:1';
    if (info?.lastRun?.child?.exitCode !== undefined && info?.lastRun?.child?.exitCode !== null) {
      child = `exit:${info.lastRun.child.exitCode}`;
    } else if (info?.lastRun?.child?.signal) {
      child = `signal:${info.lastRun.child.signal}`;
    } else if (info?.lastRun?.exitStatus !== undefined && info?.lastRun?.exitStatus !== null) {
      child = `exit:${info.lastRun.exitStatus}`;
    } else if (typeof info?.lastRun?.exitCode === 'number') {
      child = `exit:${info.lastRun.exitCode}`;
    } else if (info?.lastRun?.signal) {
      child = `signal:${info.lastRun.signal}`;
    }

    const startRes = await runner(['start', '--json', 'floor']);
    let result = 'started';
    try {
      const startData = JSON.parse(startRes.stdout);
      result = startData.result || (startRes.code === 0 ? 'started' : 'failed');
    } catch {
      result = startRes.code === 0 ? 'started' : 'failed';
    }

    return {
      lines: [`<3>floor action=start state=failed child=${child} result=${result}`],
      fault: true, // Exit 1 even if start succeeds
      action: 'start',
    };
  }

  // State: stopped, previous-boot, interrupted
  if (state === 'stopped' || state === 'previous-boot' || state === 'interrupted') {
    if (enabled || hasWaiting) {
      const startRes = await runner(['start', '--json', 'floor']);
      let result = 'started';
      try {
        const startData = JSON.parse(startRes.stdout);
        result = startData.result || (startRes.code === 0 ? 'started' : 'failed');
      } catch {
        result = startRes.code === 0 ? 'started' : 'failed';
      }

      const ok = (result === 'started' || result === 'already-running') && startRes.code === 0;
      const prefix = ok ? '<5>' : '<3>';
      return {
        lines: [`${prefix}floor action=start state=${state} waiting=${waitingCount} result=${result}`],
        fault: !ok,
        action: 'start',
      };
    } else {
      // enabled false, nothing waiting
      return {
        lines: [],
        fault: false,
        action: 'none',
      };
    }
  }

  // State: starting, stopping
  if (state === 'starting' || state === 'stopping') {
    return {
      lines: [],
      fault: false,
      action: 'none',
    };
  }

  // State: running
  if (state === 'running') {
    // Check update rule
    if (releaseState === 'outdated') {
      const url = `${floorUrl.replace(/\/+$/, '')}/orchestrator/api/state`;
      let deferredReason = null;

      try {
        const res = await fetcher(url);
        if (!res.ok) {
          deferredReason = 'api-error';
        } else {
          let data;
          try {
            data = await res.json();
          } catch {
            deferredReason = 'api-error';
          }

          if (!deferredReason) {
            if (data?.scheduled?.evalInProgress === false) {
              // Exactly false: no eval in progress, proceed to update
            } else if (data?.scheduled?.evalInProgress === true) {
              deferredReason = 'eval';
            } else {
              deferredReason = 'unknown';
            }
          }
        }
      } catch {
        deferredReason = 'api-error';
      }

      if (deferredReason) {
        // Do nothing this pass
        return {
          lines: [`<6>update deferred reason=${deferredReason}`],
          fault: false,
          action: 'none',
        };
      }

      // No Eval in progress -> run dshd update -R --json floor once
      const updateRes = await runner(['update', '-R', '--json', 'floor']);
      const ok = updateRes.code === 0;
      return {
        lines: ok ? ['<5>update action=update result=ok'] : [`<3>update error=exit:${updateRes.code}`],
        fault: !ok,
        action: 'update',
      };
    }

    // running, but release not outdated
    return {
      lines: [],
      fault: false,
      action: 'none',
    };
  }

  // State: orphaned, inconsistent, unknown, or other unrecognized states
  const remedyStr = remedy ? ` remedy=${/[\s"=]/.test(remedy) ? JSON.stringify(remedy) : remedy}` : '';
  return {
    lines: [`<3>floor state=${state}${remedyStr}`],
    fault: true,
    action: 'none',
  };
}
