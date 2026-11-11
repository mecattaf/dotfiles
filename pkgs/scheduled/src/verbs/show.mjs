/**
 * src/verbs/show.mjs - The `scheduled show` verb.
 * Usage: show (ID | PATH) [--json] [-n N] [--from ISO]
 */

import { readFileSync, lstatSync } from 'node:fs';
import { resolve, basename, dirname } from 'node:path';
import { parseWorkflow, normalize, revision, formatProblems } from '../lib/schema.mjs';
import { scheduleProblems, nextInstants, instantsBetween } from '../lib/cron.mjs';
import { validateFile } from '../lib/validate.mjs';
import { resolveId } from '../lib/resolve.mjs';
import { discover } from '../lib/discover.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled show (PATH) [--json] [-n N] [--from ISO]\n');
}

export async function main(args, ctx) {
  let filePath = null;
  let rawArg = null;
  let jsonOutput = false;
  let n = 3;
  let fromIso = null;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      jsonOutput = true;
    } else if (a === '-n') {
      n = parseInt(args[++i], 10);
      if (isNaN(n) || n < 1) {
        ctx.err('"--n" must be a positive integer\n');
        return 2;
      }
    } else if (a === '--from') {
      fromIso = args[++i];
    } else if (a.startsWith('-')) {
      usage(ctx);
      return 2;
    } else {
      if (filePath !== null) {
        usage(ctx);
        return 2;
      }
      rawArg = a;
      filePath = resolve(a);
    }
  }

  if (!filePath) {
    usage(ctx);
    return 2;
  }

  // Check if the argument is a file path (exists) or an ID
  let isFile = false;
  try {
    lstatSync(filePath);
    isFile = true;
  } catch {
    // Not a path
  }

  let resolvedId = null;
  let isProposal = false;
  if (!isFile) {
    try {
      const target = await resolveId(ctx, rawArg);
      filePath = target.path;
      resolvedId = target.id;
    } catch (err) {
      return err.exitCode ?? 1;
    }
  } else {
    // A path: name it by the discovered id when it lies inside an agency.
    isProposal = basename(dirname(filePath)) === 'proposed';
    try {
      const { files } = await discover({ home: ctx.home, uid: ctx.uid });
      const hit = files.find(f => resolve(f.path) === filePath);
      if (hit) { resolvedId = hit.id; isProposal = hit.proposal; }
    } catch { /* not inside an agency */ }
  }

  // Validate the file
  const { problems, value, bytes, promptBytes } = await validateFile(filePath, {
    uid: ctx.uid,
    proposal: isProposal,
  });

  const errors = problems.filter(p => p.severity === 'error');
  if (errors.length > 0) {
    if (jsonOutput) {
      const workflowId = resolvedId ?? basename(filePath, '.jsonc');
      ctx.out(JSON.stringify({
        v: 1,
        results: [{
          workflow: workflowId,
          path: filePath,
          revision: bytes ? revision(bytes, promptBytes) : null,
          valid: false,
          problems: problems.map(p => ({
            level: p.severity,
            code: p.code,
            path: [],
            line: p.line ?? 0,
            col: p.col ?? 0,
            message: p.message,
          })),
        }],
      }) + '\n');
    } else {
      const lines = formatProblems(filePath, problems);
      ctx.err(lines.join('\n') + '\n');
    }
    return 1;
  }

  // Compute stem and agency info from path
  const stem = basename(filePath, '.jsonc');
  const workflowsDir = dirname(filePath);
  const agencyDir = dirname(workflowsDir);
  const agencyRoot = dirname(agencyDir); // .agency/ parent
  const home = ctx.home ?? agencyRoot;

  // For now: simple agencyId derivation
  // master = home directory, else relative path
  let agencyId = 'master';
  if (agencyRoot !== home) {
    // Relative from home
    if (agencyRoot.startsWith(home + '/')) {
      agencyId = agencyRoot.slice(home.length + 1);
    } else {
      agencyId = agencyRoot;
    }
  }

  // Get prompt text from prompt-file if applicable
  let promptText = value.job?.prompt ?? '';
  if (promptBytes) {
    promptText = new TextDecoder('utf-8').decode(promptBytes);
  }

  // Normalize
  const norm = normalize(value, {
    file: filePath,
    agencyRoot,
    agencyId,
    stem,
    promptText,
    home,
  });

  // Set revision
  norm.revision = bytes ? revision(bytes, promptBytes) : null;

  // Set state
  if (!value.enabled) norm.state = 'disabled';

  // Add warnings to problems
  norm.problems = problems.filter(p => p.severity === 'warning').map(p => ({
    level: p.severity,
    code: p.code,
    path: [],
    line: p.line ?? 0,
    col: p.col ?? 0,
    message: p.message,
  }));

  // Compute next occurrences
  const schedEntries = value.on?.schedule ?? [];
  let fromDate;
  if (fromIso) {
    fromDate = new Date(fromIso);
    if (isNaN(fromDate.getTime())) {
      ctx.err(`Invalid --from value: "${fromIso}"\n`);
      return 2;
    }
  } else {
    fromDate = ctx.now ? ctx.now() : new Date();
  }

  const nextDates = schedEntries.length > 0
    ? nextInstants(schedEntries, fromDate, n)
    : [];

  norm.next = nextDates.map(d => d.toISOString());

  if (jsonOutput) {
    ctx.out(JSON.stringify(norm) + '\n');
  } else {
    // Human-readable output
    ctx.out(`id: ${norm.id}\n`);
    ctx.out(`path: ${norm.path}\n`);
    ctx.out(`revision: ${norm.revision}\n`);
    ctx.out(`state: ${norm.state}\n`);
    ctx.out(`name: ${norm.spec.name}\n`);
    ctx.out(`enabled: ${norm.spec.enabled}\n`);
    if (norm.next.length > 0) {
      ctx.out(`next occurrences:\n`);
      for (const d of norm.next) ctx.out(`  ${d}\n`);
    }
    if (problems.length > 0) {
      ctx.out(formatProblems(filePath, problems).join('\n') + '\n');
    }
  }

  return 0;
}
