// gate.mjs — the `scheduled gate` verb.
//
// Spec ref: §10.1 (gate ID --occurrence KEY --attempt N --json)
//           Claim C2.14 (if.idle, if.command gate evaluation)

import { resolveId } from '../lib/resolve.mjs';
import { validateFile } from '../lib/validate.mjs';
import { buildSchedEnv, runCommand } from '../lib/command.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled gate ID --occurrence KEY --attempt N --json\n');
}

/**
 * Main handler for `scheduled gate`.
 *
 * @param {string[]} args
 * @param {object} ctx
 * @returns {Promise<number>}
 */
export async function main(args, ctx) {
  let idArg = null;
  let occurrence = null;
  let attempt = null;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      // --json is expected/standard for gate
    } else if (a === '--occurrence') {
      if (i + 1 >= args.length) {
        usage(ctx);
        return 2;
      }
      occurrence = args[++i];
    } else if (a.startsWith('--occurrence=')) {
      occurrence = a.slice('--occurrence='.length);
    } else if (a === '--attempt') {
      if (i + 1 >= args.length) {
        usage(ctx);
        return 2;
      }
      attempt = args[++i];
    } else if (a.startsWith('--attempt=')) {
      attempt = a.slice('--attempt='.length);
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

  if (!idArg || occurrence === null || attempt === null) {
    usage(ctx);
    return 2;
  }

  let target;
  try {
    target = await resolveId(ctx, idArg, { proposal: false });
  } catch (err) {
    return err.exitCode ?? 1;
  }

  const { value } = await validateFile(target.path, { uid: ctx.uid });
  const schedEnv = buildSchedEnv(ctx, target, value, { occurrence, attempt });

  // 1. Check if.idle
  if (value?.if?.idle === true) {
    const pythonBin =
      ctx?.env?.SCHEDULED_PYTHON ?? '/etc/profiles/per-user/tom/bin/python3';
    const updateCheckPath =
      ctx?.env?.SCHEDULED_UPDATE_CHECK ?? `${ctx.home}/.local/bin/update-check`;

    const pyCode =
      'import json, runpy, sys; m = runpy.run_path(sys.argv[1], run_name="scheduled_gate"); print(json.dumps(m["busy_reasons"]()))';

    const idleRes = await runCommand(
      ctx,
      [pythonBin, '-I', '-c', pyCode, updateCheckPath],
      { cwd: target.root, schedEnv }
    );

    if (idleRes.timedOut || idleRes.exitCode !== 0) {
      ctx.out(JSON.stringify({ deferred: 'idle-unknown' }) + '\n');
      return 0;
    }

    let reasons;
    try {
      reasons = JSON.parse(idleRes.output.trim());
    } catch {
      ctx.out(JSON.stringify({ deferred: 'idle-unknown' }) + '\n');
      return 0;
    }

    if (!Array.isArray(reasons)) {
      ctx.out(JSON.stringify({ deferred: 'idle-unknown' }) + '\n');
      return 0;
    }

    if (reasons.length > 0) {
      ctx.out(JSON.stringify({ deferred: `idle: ${reasons[0]}` }) + '\n');
      return 0;
    }
  }

  // 2. Check if.command
  if (value?.if?.command) {
    const cmdRes = await runCommand(ctx, value.if.command, {
      cwd: target.root,
      schedEnv,
    });

    if (cmdRes.timedOut || cmdRes.exitCode !== 0) {
      ctx.out(JSON.stringify({ deferred: 'command' }) + '\n');
      return 0;
    }
  }

  // Neither deferred
  ctx.out(JSON.stringify({ deferred: null }) + '\n');
  return 0;
}
