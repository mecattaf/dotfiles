// write.mjs — every write to a scheduled item (new, set).
//
// Validate first, compare --expect with the revision on disk, write `.<stem>.jsonc.<pid>.tmp` mode 0600,
// fsync, rename, fsync the directory. Exit codes: 0 ok, 1 invalid or refused, 2 usage, 3 --expect conflict.

import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, renameSync, unlinkSync, writeSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { validateFile } from './validate.mjs';
import { formatProblems, revision } from './schema.mjs';
import { discover } from './discover.mjs';
import { parseId, STEM_RE } from './ids.mjs';

export class WriteError extends Error {
  constructor(message, code) { super(message); this.code = code; }
}

function fsyncDir(dir) {
  try { const fd = openSync(dir, 'r'); try { fsyncSync(fd); } finally { closeSync(fd); } } catch { /* best effort */ }
}

/** Where item `id` lives (or would live): `<root>/.agency/scheduled/<stem>.jsonc` of its discovered agency. */
export async function locate(ctx, id) {
  let parsed;
  try { parsed = parseId(id); } catch { throw new WriteError(`invalid item id '${id}' (want <agency>:<item>)`, 2); }
  const { agency, stem } = parsed;
  if (!STEM_RE.test(stem)) throw new WriteError(`invalid item stem '${stem}'`, 2);
  const { agencies } = await discover({ home: ctx.home, uid: ctx.uid });
  const found = agencies.find((a) => a.id === agency);
  if (!found) throw new WriteError(`agency '${agency}' not found`, 1);
  const dir = join(found.root, '.agency', 'scheduled');
  return { agency, stem, id: `${agency}:${stem}`, root: found.root, dir, path: join(dir, `${stem}.jsonc`) };
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
 * Validate `bytes` as the file at `path`, then write it atomically. The candidate is validated in place
 * under its temp name, so an invalid text never touches the real file (C2.9, C2.10 in test/write.test.mjs).
 */
export async function writeItem(ctx, { path, bytes, expect, hooks = {} }) {
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
  // A temp file sits beside the item, so a prompt-file resolves against the same agency folder.
  const checked = await validateFile(tmp, { uid: ctx.uid });
  if (!checked.value) {
    try { unlinkSync(tmp); } catch { /* gone */ }
    throw new WriteError(formatProblems(path, checked.problems).join('\n'), 1);
  }
  renameSync(tmp, path);
  fsyncDir(dir);
  return { path, revision: revision(checked.bytes, checked.promptBytes), problems: checked.problems };
}

/** Common flag parser: value flags in `values`, boolean flags in `booleans`; returns the rest positionally. */
export function parseFlags(args, { values = ['--expect'], booleans = [] } = {}) {
  const out = { positional: [] };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (values.includes(a)) {
      const v = args[++i];
      if (v === undefined || v === '') throw new WriteError(`${a} is missing its value`, 2);
      out[a.slice(2)] = v;
    } else if (booleans.includes(a)) out[a.slice(2)] = true;
    else if (a.startsWith('--')) throw new WriteError(`unknown flag ${a}`, 2);
    else out.positional.push(a);
  }
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
