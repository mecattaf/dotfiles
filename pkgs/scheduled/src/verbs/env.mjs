// env.mjs — the `scheduled env` verb.
//
// Spec ref: §10.1 (env ID --occurrence KEY --attempt N [--json])
//           Claim C2.13 (SCHED_* environment variables)

import { resolveId } from '../lib/resolve.mjs';
import { validateFile } from '../lib/validate.mjs';
import { buildSchedEnv } from '../lib/command.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled env ID --occurrence KEY --attempt N [--json]\n');
}

/**
 * Main handler for `scheduled env`.
 *
 * @param {string[]} args
 * @param {object} ctx
 * @returns {Promise<number>}
 */
export async function main(args, ctx) {
  let idArg = null;
  let occurrence = null;
  let attempt = null;
  let jsonOutput = false;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      jsonOutput = true;
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
  const envMap = buildSchedEnv(ctx, target, value, { occurrence, attempt });

  if (jsonOutput) {
    ctx.out(JSON.stringify(envMap) + '\n');
  } else {
    for (const [k, v] of Object.entries(envMap)) {
      ctx.out(`${k}=${v}\n`);
    }
  }

  return 0;
}
