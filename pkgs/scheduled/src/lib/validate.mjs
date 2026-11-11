/**
 * validate.mjs - Validates one workflow file on disk.
 * Exports: validateFile
 */

import { readFileSync, statSync, lstatSync } from 'node:fs';
import { dirname, basename, resolve, join } from 'node:path';
import { parseWorkflow, revision } from './schema.mjs';
import { scheduleProblems } from './cron.mjs';

const MAX_FILE_SIZE = 64 * 1024; // 64 KiB

/**
 * Check ownership and permissions for a path.
 * Returns an error message string if the check fails, or null if OK.
 */
function checkOwnership(path, uid) {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    return `Cannot stat "${path}".`;
  }
  if (st.uid !== uid) {
    return `"${path}" is not owned by uid ${uid}.`;
  }
  // Group-writable (0o020) or world-writable (0o002)
  if (st.mode & 0o022) {
    return `"${path}" is writable by group or others (mode ${(st.mode & 0o777).toString(8)}).`;
  }
  return null;
}

/**
 * Validate one workflow file on disk.
 * @param {string} path - Absolute path to the .jsonc file
 * @param {object} opts - { uid, proposal }
 * @returns {{ path, problems, value, bytes, promptBytes }}
 */
export async function validateFile(path, { uid = process.getuid?.(), proposal = false } = {}) {
  const problems = [];

  // ── Ownership checks ──────────────────────────────────────────────────────
  // The file itself
  const fileOwnerErr = checkOwnership(path, uid);
  if (fileOwnerErr) {
    problems.push({ severity: 'error', code: 'ownership', line: 0, col: 0, message: fileOwnerErr });
    return { path, problems, value: null, bytes: null, promptBytes: null };
  }

  // The workflows/ directory containing the file
  const workflowsDir = dirname(path);
  const wfOwnerErr = checkOwnership(workflowsDir, uid);
  if (wfOwnerErr) {
    problems.push({ severity: 'error', code: 'ownership', line: 0, col: 0, message: wfOwnerErr });
    return { path, problems, value: null, bytes: null, promptBytes: null };
  }

  // The .agency/ directory (parent of workflows/; a proposal sits one level
  // deeper, in workflows/proposed/)
  const agencyDir = basename(workflowsDir) === 'proposed' && basename(dirname(workflowsDir)) === 'workflows'
    ? dirname(dirname(workflowsDir))
    : dirname(workflowsDir);
  const agOwnerErr = checkOwnership(agencyDir, uid);
  if (agOwnerErr) {
    problems.push({ severity: 'error', code: 'ownership', line: 0, col: 0, message: agOwnerErr });
    return { path, problems, value: null, bytes: null, promptBytes: null };
  }

  // ── Read the file ─────────────────────────────────────────────────────────
  let bytes;
  let st;
  try {
    st = lstatSync(path);
    if (!st.isFile()) {
      problems.push({ severity: 'error', code: 'file', line: 0, col: 0,
        message: `"${path}" is not a regular file.` });
      return { path, problems, value: null, bytes: null, promptBytes: null };
    }
    if (st.size > MAX_FILE_SIZE) {
      problems.push({ severity: 'error', code: 'file', line: 0, col: 0,
        message: `"${path}" exceeds 64 KiB.` });
      return { path, problems, value: null, bytes: null, promptBytes: null };
    }
    bytes = readFileSync(path);
  } catch (e) {
    problems.push({ severity: 'error', code: 'file', line: 0, col: 0,
      message: `Cannot read "${path}": ${e.message}` });
    return { path, problems, value: null, bytes: null, promptBytes: null };
  }

  // Check UTF-8
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    problems.push({ severity: 'error', code: 'file', line: 0, col: 0,
      message: `"${path}" is not valid UTF-8.` });
    return { path, problems, value: null, bytes, promptBytes: null };
  }

  // ── Parse and validate ────────────────────────────────────────────────────
  const { value, problems: parseProblems } = parseWorkflow(text, { proposal });
  problems.push(...parseProblems);

  if (value === null) {
    return { path, problems, value: null, bytes, promptBytes: null };
  }

  // ── Cron validation ───────────────────────────────────────────────────────
  const schedEntries = value.on?.schedule ?? [];
  if (schedEntries.length > 0) {
    const cronProbs = scheduleProblems(schedEntries);
    // Map cron problems onto positions: use the schedule entry's position if possible
    for (const cp of cronProbs) {
      problems.push({
        severity: cp.severity,
        code: cp.code,
        line: cp.line ?? 0,
        col: cp.col ?? 0,
        message: cp.message,
      });
    }
  }

  // ── Prompt-file resolution ────────────────────────────────────────────────
  let promptBytes = null;
  if (value.job?.['prompt-file']) {
    const agencyRoot = agencyDir; // .agency/ parent is agency root? No: agencyDir IS .agency/
    // prompt-file path is relative to .agency/
    const promptPath = join(agencyDir, value.job['prompt-file']);
    // Verify it's under .agency/
    const resolvedPrompt = resolve(promptPath);
    const resolvedAgency = resolve(agencyDir);
    if (!resolvedPrompt.startsWith(resolvedAgency + '/') && resolvedPrompt !== resolvedAgency) {
      problems.push({ severity: 'error', code: 'job', line: 0, col: 0,
        message: `"job.prompt-file" must be a path under .agency/ directory.` });
    } else {
      try {
        promptBytes = readFileSync(promptPath);
      } catch {
        problems.push({ severity: 'error', code: 'job', line: 0, col: 0,
          message: `"job.prompt-file" "${value.job['prompt-file']}" does not exist under .agency/.` });
      }
    }
  }

  // ── Revision ──────────────────────────────────────────────────────────────
  const rev = revision(bytes, promptBytes);

  return { path, problems, value: { ...value, _revision: rev }, bytes, promptBytes };
}
