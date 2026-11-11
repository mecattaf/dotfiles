/**
 * src/verbs/validate.mjs - The `scheduled validate` verb.
 * Usage: validate PATH... | --stdin --as PATH [--json]
 */

import { readFileSync } from 'node:fs';
import { resolve, basename, dirname, join } from 'node:path';
import { parseWorkflow, formatProblems, revision } from '../lib/schema.mjs';
import { scheduleProblems } from '../lib/cron.mjs';
import { validateFile } from '../lib/validate.mjs';
import { discover } from '../lib/discover.mjs';

function usage(ctx) {
  ctx.err('Usage: scheduled validate (PATH... | --all | --stdin --as PATH) [--json]\n');
}

/**
 * Build a JSON result object for one file.
 */
function buildJsonResult(filePath, problems, value, bytes, promptBytes, workflowId) {
  const errors = problems.filter(p => p.severity === 'error');
  const valid = errors.length === 0;
  let rev = null;
  if (bytes) {
    try { rev = revision(bytes, promptBytes); } catch {}
  }
  return {
    workflow: workflowId ?? basename(filePath, '.jsonc'),
    path: filePath,
    revision: rev,
    valid,
    problems: problems.map(p => ({
      level: p.severity,
      code: p.code,
      path: [], // JSON path not implemented yet
      line: p.line ?? 0,
      col: p.col ?? 0,
      message: p.message,
    })),
  };
}

export async function main(args, ctx) {
  const paths = [];
  let jsonOutput = false;
  let stdinMode = false;
  let stdinAs = null;
  let allMode = false;

  // Parse args
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') {
      jsonOutput = true;
    } else if (a === '--stdin') {
      stdinMode = true;
    } else if (a === '--as') {
      stdinAs = args[++i];
    } else if (a === '--all') {
      allMode = true;
    } else if (a.startsWith('-')) {
      usage(ctx);
      return 2;
    } else {
      paths.push(resolve(a));
    }
  }

  // --all: every workflow and proposal discovery finds under the listed agencies (DESIGN 10.1).
  const discovered = new Map();
  if (allMode) {
    const { files } = await discover({ home: ctx.home, uid: ctx.uid });
    for (const file of files) {
      paths.push(file.path);
      discovered.set(file.path, file);
    }
    if (paths.length === 0) {
      ctx.out(jsonOutput ? JSON.stringify({ v: 1, results: [] }) + '\n' : 'No workflows found.\n');
      return 0;
    }
  }

  if (stdinMode) {
    if (!stdinAs) {
      ctx.err('--stdin requires --as PATH\n');
      usage(ctx);
      return 2;
    }
    const filePath = resolve(stdinAs);
    // Read from stdin is not directly available in ctx - read process.stdin
    let text;
    try {
      text = readFileSync('/dev/stdin', 'utf8');
    } catch (e) {
      ctx.err(`Cannot read stdin: ${e.message}\n`);
      return 4;
    }

    const { value, problems } = parseWorkflow(text, { proposal: false });
    // Cron check
    if (value?.on?.schedule?.length) {
      const cronProbs = scheduleProblems(value.on.schedule);
      problems.push(...cronProbs);
    }

    const bytes = Buffer.from(text, 'utf8');
    const workflowId = basename(filePath, '.jsonc');
    const result = buildJsonResult(filePath, problems, value, bytes, null, workflowId);

    if (jsonOutput) {
      ctx.out(JSON.stringify({ v: 1, results: [result] }) + '\n');
    } else {
      const lines = formatProblems(filePath, problems);
      ctx.out(lines.join('\n') + '\n');
    }
    return result.valid ? 0 : 1;
  }

  if (paths.length === 0) {
    usage(ctx);
    return 2;
  }

  const results = [];
  let anyError = false;

  for (const filePath of paths) {
    const found = discovered.get(filePath);
    const { problems, value, bytes, promptBytes } = await validateFile(filePath, {
      uid: ctx.uid,
      proposal: found?.proposal ?? false,
    });

    const workflowId = found?.id ?? basename(filePath, '.jsonc');
    const result = buildJsonResult(filePath, problems, value, bytes, promptBytes, workflowId);
    results.push({ filePath, problems, result });

    if (!result.valid) anyError = true;
  }

  if (jsonOutput) {
    ctx.out(JSON.stringify({ v: 1, results: results.map(r => r.result) }) + '\n');
  } else {
    for (const { filePath, problems } of results) {
      const lines = formatProblems(filePath, problems);
      ctx.out(lines.join('\n') + '\n');
    }
  }

  return anyError ? 1 : 0;
}
