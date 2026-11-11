// check.mjs — the `scheduled check` verb.
//
// Spec ref: §10.1 (check ID --occurrence KEY --attempt N --json)
//           Claim C2.14 (outcome.check evaluation)

import { resolveId } from '../lib/resolve.mjs';
import { validateFile } from '../lib/validate.mjs';
import { buildSchedEnv, runCommand } from '../lib/command.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled check ID --occurrence KEY --attempt N --json\n');
}

/**
 * Main handler for `scheduled check`.
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
      // --json is expected/standard for check
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

  if (value?.outcome?.check) {
    const res = await runCommand(ctx, value.outcome.check, {
      cwd: target.root,
      schedEnv,
    });
    const holds = !res.timedOut && res.exitCode === 0;
    ctx.out(
      JSON.stringify({
        holds,
        exit: res.exitCode,
        output: res.output,
      }) + '\n'
    );
  } else {
    ctx.out(
      JSON.stringify({
        holds: false,
        exit: null,
        output: '',
      }) + '\n'
    );
  }

  return 0;
}
