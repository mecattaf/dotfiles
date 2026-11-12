// ls.mjs — the `scheduled ls` verb.
//
// Every item with its state (enabled, disabled or invalid), next instant and revision.

import { execFile } from 'node:child_process';
import { discover } from '../lib/discover.mjs';
import { validateFile } from '../lib/validate.mjs';
import { revision } from '../lib/schema.mjs';
import { nextInstants } from '../lib/cron.mjs';

function parseSystemctlShow(stdout) {
  const serviceProps = {};
  const timerProps = {};

  const lines = stdout.split('\n');
  let currentUnit = 'service';

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      currentUnit = 'timer';
      continue;
    }
    const eq = trimmed.indexOf('=');
    if (eq > 0) {
      const k = trimmed.slice(0, eq);
      const v = trimmed.slice(eq + 1);
      if (currentUnit === 'service') {
        if (k in serviceProps) {
          // If a key repeats, switch to timer
          timerProps[k] = v;
        } else {
          serviceProps[k] = v;
        }
      } else {
        timerProps[k] = v;
      }
    }
  }

  return { serviceProps, timerProps };
}

function queryHeartbeat(ctx) {
  return new Promise((resolve) => {
    const systemctlBin = ctx?.systemctl || '/run/current-system/sw/bin/systemctl';
    execFile(
      systemctlBin,
      [
        '--user',
        'show',
        '-p',
        'ActiveState,Result,NextElapseUSecRealtime',
        'scheduled-heartbeat.service',
        'scheduled-heartbeat.timer',
      ],
      { timeout: 5000 },
      (err, stdout) => {
        if (err) {
          return resolve({ ok: false, raw: '' });
        }
        resolve({ ok: true, raw: stdout || '' });
      }
    );
  });
}

/**
 * Main handler for `scheduled ls`.
 *
 * @param {string[]} args
 * @param {object} ctx
 * @returns {Promise<number>}
 */
export async function main(args, ctx) {
  let jsonOutput = false;
  let agencyFilter = null;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      jsonOutput = true;
    } else if (a === '--agency') {
      if (i + 1 >= args.length) {
        ctx.err('scheduled ls: --agency requires an argument\n');
        return 2;
      }
      agencyFilter = args[++i];
    } else if (a.startsWith('--agency=')) {
      agencyFilter = a.slice('--agency='.length);
    } else if (a.startsWith('-')) {
      ctx.err(`scheduled ls: unknown option '${a}'\n`);
      return 2;
    } else {
      ctx.err(`scheduled ls: unexpected argument '${a}'\n`);
      return 2;
    }
  }

  // 1. Query heartbeat
  const hbResult = await queryHeartbeat(ctx);
  let heartbeat;
  if (hbResult.ok) {
    const { serviceProps, timerProps } = parseSystemctlShow(hbResult.raw);
    const serviceActive = serviceProps.ActiveState || 'inactive';
    const serviceResult = serviceProps.Result || 'success';
    const timerActive = timerProps.ActiveState || 'active';
    const timerResult = timerProps.Result || 'success';
    const timerNext = timerProps.NextElapseUSecRealtime || null;

    heartbeat = {
      status: timerActive,
      activeState: timerActive,
      result: serviceResult,
      nextElapseUSecRealtime: timerNext,
      service: {
        activeState: serviceActive,
        result: serviceResult,
      },
      timer: {
        activeState: timerActive,
        result: timerResult,
        nextElapseUSecRealtime: timerNext,
      },
    };
  } else {
    heartbeat = {
      status: 'unknown',
      activeState: 'unknown',
      result: 'unknown',
      nextElapseUSecRealtime: null,
    };
  }

  // 2. Discover agencies and items
  const { agencies: allAgencies, files: allFiles, problems: discoverProblems = [] } = await discover({
    home: ctx.home,
    uid: ctx.uid,
  });

  const agencies = agencyFilter
    ? allAgencies.filter((a) => a.id === agencyFilter)
    : allAgencies;

  const targetFiles = agencyFilter
    ? allFiles.filter((f) => f.agency === agencyFilter)
    : allFiles;

  // 3. Evaluate each item: invalid, disabled or enabled; only an enabled item has a next instant.
  const now = ctx.now ? ctx.now() : new Date();
  const items = [];

  for (const f of targetFiles) {
    const { problems, value, bytes, promptBytes } = await validateFile(f.path, { uid: ctx.uid });
    const hasErrors = !value;
    const state = hasErrors ? 'invalid' : value.enabled ? 'enabled' : 'disabled';
    const rev = bytes ? revision(bytes, promptBytes) : null;

    let next = null;
    if (state === 'enabled' && value.on?.schedule?.length > 0) {
      const dates = nextInstants(value.on.schedule, now, 1);
      if (dates.length > 0) {
        next = dates[0].toISOString();
      }
    }

    items.push({
      id: f.id,
      agency: f.agency,
      stem: f.stem,
      path: f.path,
      enabled: hasErrors ? null : value.enabled,
      valid: !hasErrors,
      state,
      next,
      revision: rev,
      problems: problems || [],
    });
  }

  // Sort: invalid first, then alphabetically by id
  items.sort((a, b) => {
    if (a.state === 'invalid' && b.state !== 'invalid') return -1;
    if (a.state !== 'invalid' && b.state === 'invalid') return 1;
    return a.id.localeCompare(b.id);
  });

  if (jsonOutput) {
    // Discovery's own problems (an agency-name error, a bad stem) are part of the listing (C2.8).
    ctx.out(JSON.stringify({ heartbeat, agencies, items, problems: discoverProblems }) + '\n');
  } else {
    // Text output:
    // Header line
    if (hbResult.ok) {
      ctx.out(`heartbeat: ${heartbeat.activeState}\n`);
    } else {
      ctx.out('heartbeat: unknown\n');
    }

    // Item lines
    for (const w of items) {
      const nextStr = w.next ?? '-';
      const revStr = w.revision ?? '-';
      ctx.out(`${w.id}  ${w.state}  ${nextStr}  ${revStr}\n`);
    }
    for (const p of discoverProblems) {
      ctx.out(`${p.path}: ${p.severity} ${p.code}: ${p.message}\n`);
    }
  }

  return 0;
}
