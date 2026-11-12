/**
 * validate.mjs - Validates one scheduled item on disk: ownership, size, UTF-8, schema, cron and prompt-file.
 * Exports: validateFile, agencyRootOf
 */

import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, resolve, sep } from 'node:path';
import { parseItem, revision, PROMPT_MAX_BYTES } from './schema.mjs';
import { scheduleProblems } from './cron.mjs';

const MAX_FILE_SIZE = 64 * 1024;

/** The agency folder of `<root>/.agency/scheduled/<item>.jsonc`. */
export const agencyRootOf = (path) => dirname(dirname(dirname(path)));

/** An error message when `path` is not owned by `uid` or is group/world-writable, else null. */
function checkOwnership(path, uid) {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    return `Cannot stat "${path}".`;
  }
  if (st.uid !== uid) return `"${path}" is not owned by uid ${uid}.`;
  if (st.mode & 0o022) return `"${path}" is writable by group or others (mode ${(st.mode & 0o777).toString(8)}).`;
  return null;
}

const problem = (code, message) => ({ severity: 'error', code, line: 0, col: 0, message });
const inside = (child, parent) => child.startsWith(parent.endsWith(sep) ? parent : parent + sep);

/**
 * Read `job.prompt-file` relative to the agency folder `root`; it must stay inside it, also after symlinks.
 * @returns {{ bytes: Buffer|null, text: string|null, problem: object|null }}
 */
function readPromptFile(root, relative) {
  const fail = (message) => ({ bytes: null, text: null, problem: problem('job', message) });
  if (isAbsolute(relative)) return fail('"job.prompt-file" must be a path relative to the agency folder.');
  const target = resolve(root, relative);
  if (!inside(target, resolve(root))) return fail(`"job.prompt-file" "${relative}" leaves the agency folder.`);
  let real;
  try {
    real = realpathSync(target);
  } catch {
    return fail(`"job.prompt-file" "${relative}" does not exist in the agency folder.`);
  }
  if (!inside(real, realpathSync(root))) return fail(`"job.prompt-file" "${relative}" resolves outside the agency folder.`);
  let bytes;
  try {
    bytes = readFileSync(real);
  } catch (e) {
    return fail(`Cannot read "job.prompt-file" "${relative}": ${e.message}`);
  }
  if (bytes.length === 0) return fail(`"job.prompt-file" "${relative}" is empty.`);
  if (bytes.length > PROMPT_MAX_BYTES) return fail(`"job.prompt-file" "${relative}" exceeds 32 KiB.`);
  try {
    return { bytes, text: new TextDecoder('utf-8', { fatal: true }).decode(bytes), problem: null };
  } catch {
    return fail(`"job.prompt-file" "${relative}" is not valid UTF-8.`);
  }
}

/**
 * Validate one scheduled item on disk.
 * @param {string} path - Absolute path of `<root>/.agency/scheduled/<item>.jsonc`
 * @param {{ uid?: number }} [opts]
 * @returns {Promise<{ path, problems, value, bytes, promptBytes, prompt }>} `prompt` is the work text when valid
 */
export async function validateFile(path, { uid = process.getuid?.() } = {}) {
  const problems = [];
  // Every answer carries the revision of the bytes read, so an invalid revision is still named once.
  const done = (extra = {}) => {
    const out = { path, problems, value: null, bytes: null, promptBytes: null, prompt: null, ...extra };
    return { ...out, revision: out.bytes ? revision(out.bytes, out.promptBytes) : null };
  };

  // The file, scheduled/ and .agency/ must be ours and not group/world-writable: an item runs with full permissions.
  for (const p of [path, dirname(path), dirname(dirname(path))]) {
    const owner = checkOwnership(p, uid);
    if (owner) {
      problems.push(problem('ownership', owner));
      return done();
    }
  }

  let bytes;
  try {
    const st = lstatSync(path);
    if (!st.isFile()) {
      problems.push(problem('file', `"${path}" is not a regular file.`));
      return done();
    }
    if (st.size > MAX_FILE_SIZE) {
      problems.push(problem('file', `"${path}" exceeds 64 KiB.`));
      return done();
    }
    bytes = readFileSync(path);
  } catch (e) {
    problems.push(problem('file', `Cannot read "${path}": ${e.message}`));
    return done();
  }

  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    problems.push(problem('file', `"${path}" is not valid UTF-8.`));
    return done({ bytes });
  }

  const { value, problems: parsed } = parseItem(text);
  problems.push(...parsed);
  if (value === null) return done({ bytes });

  problems.push(...scheduleProblems(value.on?.schedule ?? []).map((p) => ({
    severity: p.severity, code: p.code, line: p.line ?? 0, col: p.col ?? 0, message: p.message,
  })));

  let promptBytes = null;
  let prompt = value.job?.prompt ?? null;
  if (value.job?.['prompt-file']) {
    const read = readPromptFile(agencyRootOf(path), value.job['prompt-file']);
    if (read.problem) problems.push(read.problem);
    promptBytes = read.bytes;
    prompt = read.text;
  }

  const rev = revision(bytes, promptBytes);
  if (problems.some((p) => p.severity === 'error')) return done({ bytes, promptBytes });
  return { path, problems, value: { ...value, _revision: rev }, bytes, promptBytes, prompt, revision: rev };
}
