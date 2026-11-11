// run.mjs — the `scheduled run` verb.
//
// Spec ref: §10.1 (run ID [--input K=V]... [--by WHO] [--wait] [--follow])
//           Claim C9.1, Claim C2.9

import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { resolveId } from '../lib/resolve.mjs';
import { validateFile } from '../lib/validate.mjs';
import { revision, formatProblems } from '../lib/schema.mjs';
import { ulid, manualSpoolName } from '../lib/ids.mjs';
import { linkExclusive } from '../lib/atomic.mjs';

function usage(ctx) {
  ctx.err(
    'Usage: scheduled run ID [--input K=V]... [--by WHO] [--wait] [--follow]\n'
  );
}

function checkFloorRunning(dshdBin) {
  return new Promise((resolve) => {
    execFile(
      dshdBin,
      ['get', '--json', 'floor'],
      { timeout: 5000 },
      (err, stdout) => {
        if (err) return resolve(false);
        try {
          const data = JSON.parse(stdout);
          resolve(data?.state === 'running' || data?.status === 'running');
        } catch {
          resolve(false);
        }
      }
    );
  });
}

function kickHeartbeat(systemctlBin) {
  return new Promise((resolve) => {
    execFile(
      systemctlBin,
      ['--user', 'start', '--no-block', 'scheduled-heartbeat.service'],
      { timeout: 5000 },
      () => resolve() // failure is not an error
    );
  });
}

/**
 * Main handler for `scheduled run`.
 *
 * @param {string[]} args
 * @param {object} ctx
 * @returns {Promise<number>}
 */
export async function main(args, ctx) {
  let idArg = null;
  let by = ctx?.env?.USER ?? 'tom';
  const rawInputs = {};

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--wait') {
      ctx.err('scheduled run: --wait is not built yet\n');
      return 2;
    } else if (a === '--follow') {
      ctx.err('scheduled run: --follow is not built yet\n');
      return 2;
    } else if (a === '--by') {
      if (i + 1 >= args.length) {
        usage(ctx);
        return 2;
      }
      by = args[++i];
    } else if (a.startsWith('--by=')) {
      by = a.slice('--by='.length);
    } else if (a === '--input') {
      if (i + 1 >= args.length) {
        usage(ctx);
        return 2;
      }
      const pair = args[++i];
      const eq = pair.indexOf('=');
      if (eq <= 0) {
        ctx.err(`scheduled run: invalid --input format '${pair}', expected K=V\n`);
        return 2;
      }
      rawInputs[pair.slice(0, eq)] = pair.slice(eq + 1);
    } else if (a.startsWith('--input=')) {
      const pair = a.slice('--input='.length);
      const eq = pair.indexOf('=');
      if (eq <= 0) {
        ctx.err(`scheduled run: invalid --input format '${pair}', expected K=V\n`);
        return 2;
      }
      rawInputs[pair.slice(0, eq)] = pair.slice(eq + 1);
    } else if (a.startsWith('-')) {
      usage(ctx);
      return 2;
    } else {
      if (idArg !== null) {
        usage(ctx);
        return 2;
      }
      idArg = a;
    }
  }

  if (!idArg) {
    usage(ctx);
    return 2;
  }

  // 1. Resolve ID (never proposed/)
  let target;
  try {
    target = await resolveId(ctx, idArg, { proposal: false });
  } catch (err) {
    return err.exitCode ?? 1;
  }

  // 2. Validate the live file (paused allowed)
  const { problems, value, bytes, promptBytes } = await validateFile(
    target.path,
    { uid: ctx.uid, proposal: false }
  );

  const errors = problems.filter((p) => p.severity === 'error');
  if (errors.length > 0) {
    const formatted = formatProblems(target.path, problems);
    ctx.err(formatted.join('\n') + '\n');
    return 1;
  }

  // 3. Validate inputs against on.workflow_dispatch.inputs
  const definedInputs =
    value?.on?.dispatch?.inputs ??
    value?.on?.workflow_dispatch?.inputs ??
    {};

  const parsedInputs = {};

  // Check for unknown inputs
  for (const k of Object.keys(rawInputs)) {
    if (!(k in definedInputs)) {
      ctx.err(`scheduled run: unknown input '${k}'\n`);
      return 1;
    }
  }

  // Check required and parse types
  for (const [name, def] of Object.entries(definedInputs)) {
    const isProvided = name in rawInputs;
    if (!isProvided) {
      if (def?.required === true && def?.default === undefined) {
        ctx.err(`scheduled run: missing required input '${name}'\n`);
        return 1;
      }
      if (def?.default !== undefined) {
        parsedInputs[name] = def.default;
      }
    } else {
      const val = rawInputs[name];
      if (def?.type === 'boolean') {
        if (val === 'true') {
          parsedInputs[name] = true;
        } else if (val === 'false') {
          parsedInputs[name] = false;
        } else {
          ctx.err(`scheduled run: input '${name}' must be true or false\n`);
          return 1;
        }
      } else if (def?.type === 'choice') {
        if (Array.isArray(def.options) && !def.options.includes(val)) {
          ctx.err(
            `scheduled run: input '${name}' must be one of: ${def.options.join(
              ', '
            )}\n`
          );
          return 1;
        }
        parsedInputs[name] = val;
      } else {
        parsedInputs[name] = val;
      }
    }
  }

  // 4. Write manual spool file
  const tmpDir = join(ctx.stateDir, 'spool', 'tmp');
  const incomingDir = join(ctx.stateDir, 'spool', 'incoming');
  await mkdir(tmpDir, { recursive: true, mode: 0o700 });
  await mkdir(incomingDir, { recursive: true, mode: 0o700 });

  const now = ctx.now ? ctx.now() : new Date();
  const reqUlid = ulid(now);
  const spoolFileName = manualSpoolName({
    agency: target.agency,
    stem: target.stem,
    ulid: reqUlid,
  });
  const destPath = join(incomingDir, spoolFileName);

  const occurrence = `${target.id}@manual:${reqUlid}`;
  const rev = revision(bytes, promptBytes);

  const spoolData = {
    v: 1,
    kind: 'manual',
    occurrence,
    workflow: target.id,
    agency: target.root,
    file: target.path,
    instant: now.toISOString(),
    missed: 0,
    revision: rev,
    by,
    inputs: parsedInputs,
    at: now.toISOString(),
  };

  await linkExclusive(tmpDir, destPath, JSON.stringify(spoolData, null, 2) + '\n');

  // 5. Print confirmation
  ctx.out(JSON.stringify({ v: 1, occurrence, state: 'requested' }) + '\n');

  // 6. Check dshd and kick heartbeat if floor is not running
  const isFloorRunning = await checkFloorRunning(ctx.dshd);
  if (!isFloorRunning) {
    await kickHeartbeat(ctx.systemctl);
  }

  return 0;
}
