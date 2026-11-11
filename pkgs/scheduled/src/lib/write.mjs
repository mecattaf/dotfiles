// write.mjs — every write to a workflow file (DESIGN 10.1, 5.1; claims C2.9-C2.12).
//
// Validate first, compare --expect with the revision on disk, write
// `.<stem>.jsonc.<pid>.tmp` mode 0600, fsync, rename, fsync the directory,
// then append the revision ledger with `by`. Exit codes: 0 ok, 1 invalid or
// refused, 2 usage, 3 --expect conflict, 4 environment.

import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, unlinkSync, writeSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { validateFile } from './validate.mjs';
import { formatProblems, revision } from './schema.mjs';
import { recordRevision } from './ledger.mjs';
import { discover } from './discover.mjs';
import { parseId, STEM_RE } from './ids.mjs';
import { appendLine } from './atomic.mjs';

export class WriteError extends Error {
  constructor(message, code) { super(message); this.code = code; }
}

/** Open proposals allowed per agency (DESIGN 10.1, GUESS). */
export const MAX_PROPOSALS = 3;
/** Days a dismissed stem is refused (DESIGN 10.1, GUESS). */
export const DISMISS_DAYS = 30;

function fsyncDir(dir) {
  try { const fd = openSync(dir, 'r'); try { fsyncSync(fd); } finally { closeSync(fd); } } catch { /* best effort */ }
}

/**
 * Where workflow `id` lives (or would live): its agency root from discovery,
 * `<root>/.agency/workflows/[proposed/]<stem>.jsonc`.
 */
export async function locate(ctx, id, { proposal = false } = {}) {
  let parsed;
  try { parsed = parseId(id); } catch { throw new WriteError(`invalid workflow id '${id}' (want <agency>:<stem>)`, 2); }
  const { agency, stem } = parsed;
  if (!STEM_RE.test(stem)) throw new WriteError(`invalid stem '${stem}'`, 2);
  const { agencies } = await discover({ home: ctx.home, uid: ctx.uid });
  const found = agencies.find((a) => a.id === agency);
  if (!found) throw new WriteError(`agency '${agency}' not found`, 1);
  const workflows = join(found.root, '.agency', 'workflows');
  return { agency, stem, id: `${agency}:${stem}`, root: found.root, workflows,
    path: join(workflows, ...(proposal ? ['proposed'] : []), `${stem}.jsonc`) };
}

/** The revision of the file at `path` now, or null when there is none. */
export async function currentRevision(path, uid) {
  if (!existsSync(path)) return null;
  const { bytes, promptBytes } = await validateFile(path, { uid });
  if (!bytes) return null;
  return revision(bytes, promptBytes);
}

/** --expect REV|none against the file on disk; a mismatch is exit 3 with no write. */
export async function checkExpect(path, expect, uid) {
  if (expect === undefined) return;
  const now = await currentRevision(path, uid);
  if (expect === 'none' ? now !== null : now !== expect) {
    throw new WriteError(`--expect ${expect} does not match the file on disk (${now ?? 'none'})`, 3);
  }
}

/**
 * Validate `bytes` as the file at `path`, then write it atomically and record
 * the revision. The candidate is validated in place under its temp name, so
 * an invalid text never touches the real file (C2.9, C2.10).
 */
export async function writeWorkflow(ctx, { path, bytes, by, id, proposal = false, expect, hooks = {} }) {
  const dir = dirname(path);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  await checkExpect(path, expect, ctx.uid);
  const tmp = join(dir, `.${basename(path)}.${process.pid}.tmp`);
  const fd = openSync(tmp, 'w', 0o600);
  try {
    writeSync(fd, bytes);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  hooks.afterTemp?.(tmp);
  const checked = await validateFile(tmp, { uid: ctx.uid, proposal });
  const errors = checked.problems.filter((p) => p.severity === 'error');
  if (errors.length || !checked.value) {
    try { unlinkSync(tmp); } catch { /* gone */ }
    const lines = formatProblems(path, checked.problems);
    throw new WriteError(lines.join('\n'), 1);
  }
  renameSync(tmp, path);
  fsyncDir(dir);
  const rev = revision(checked.bytes, checked.promptBytes);
  await recordRevision(ctx.stateDir, { workflow: id, revision: rev, fileBytes: checked.bytes, promptBytes: checked.promptBytes,
    by, valid: true, at: ctx.now?.() ?? new Date() });
  return { path, revision: rev, problems: checked.problems };
}

/** Open proposals of an agency (files in proposed/). */
export function openProposals(workflowsDir) {
  try {
    return readdirSync(join(workflowsDir, 'proposed')).filter((n) => n.endsWith('.jsonc') && !n.startsWith('.'));
  } catch { return []; }
}

/** The dismissal of `stem` in `agency` within DISMISS_DAYS, if any. */
export function dismissedRecently(stateDir, agency, stem, now = new Date()) {
  let text;
  try { text = readFileSync(join(stateDir, 'dismissed.jsonl'), 'utf8'); } catch { return null; }
  const cutoff = now.getTime() - DISMISS_DAYS * 86_400_000;
  let hit = null;
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const rec = JSON.parse(line);
      if (rec.agency === agency && rec.stem === stem && Date.parse(rec.at) >= cutoff) hit = rec;
    } catch { /* skip */ }
  }
  return hit;
}

export async function recordDismissal(stateDir, rec) {
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  await appendLine(join(stateDir, 'dismissed.jsonl'), rec);
}

/** Common flag parser: --expect, --by, --proposal; returns the rest positionally. */
export function parseFlags(args, { allow = ['--expect', '--by', '--proposal'] } = {}) {
  const out = { positional: [] };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--expect' && allow.includes(a)) out.expect = args[++i];
    else if (a === '--by' && allow.includes(a)) out.by = args[++i];
    else if (a === '--proposal' && allow.includes(a)) out.proposal = true;
    else if (a === '--unset' && allow.includes(a)) out.unset = true;
    else if (a === '--paused' && allow.includes(a)) out.paused = true;
    else if ((a === '--cron' || a === '--tz' || a === '--prompt') && allow.includes(a)) out[a.slice(2)] = args[++i];
    else if (a.startsWith('--')) throw new WriteError(`unknown flag ${a}`, 2);
    else out.positional.push(a);
  }
  if (('expect' in out && !out.expect) || ('by' in out && !out.by)) throw new WriteError('a flag is missing its value', 2);
  return out;
}

/** Runs a write verb body, mapping WriteError to its exit code. */
export async function guarded(ctx, run) {
  try {
    return await run();
  } catch (e) {
    if (e instanceof WriteError) {
      ctx.err(`scheduled: ${e.message}\n`);
      return e.code;
    }
    throw e;
  }
}

export const byOf = (flags, ctx) => flags.by ?? ctx.env?.USER ?? process.env.USER ?? 'unknown';
