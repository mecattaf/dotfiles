// ledger.mjs — revision ledger and content-addressed revision store.
//
// Spec ref: §5.1 (state/master/revisions/), §b.12 (revision ledger)

import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { mkdir, chmod, readFile, stat } from 'node:fs/promises';
import { appendLine, writeAtomic } from './atomic.mjs';

/**
 * Ensure the revisions directory exists with mode 0700:
 *   <stateDir>/revisions
 *
 * @param {string} stateDir
 */
async function ensureRevisionsDir(stateDir) {
  const revDir = join(stateDir, 'revisions');
  await mkdir(revDir, { recursive: true, mode: 0o700 });
  try {
    await chmod(revDir, 0o700);
  } catch {}
  return revDir;
}

/**
 * Read the revision index at <stateDir>/revisions/index.jsonl.
 * Readers keep the first line per (workflow, revision).
 *
 * @param {string} stateDir
 * @returns {Promise<Array<object>>}
 */
export async function readIndex(stateDir) {
  const indexFile = join(stateDir, 'revisions', 'index.jsonl');
  let content;
  try {
    content = await readFile(indexFile, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }

  const lines = content.trim().split('\n').filter(Boolean);
  const seen = new Set();
  const entries = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      const key = `${entry.workflow}:${entry.revision}`;
      if (!seen.has(key)) {
        seen.add(key);
        entries.push(entry);
      }
    } catch {}
  }

  return entries;
}

/**
 * Check if a (workflow, revision) pair is already in the ledger index.
 *
 * @param {string} stateDir
 * @param {string} workflow
 * @param {string} revision
 * @returns {Promise<boolean>}
 */
export async function known(stateDir, workflow, revision) {
  const entries = await readIndex(stateDir);
  return entries.some((e) => e.workflow === workflow && e.revision === revision);
}

/**
 * Record a workflow revision in the ledger:
 * 1. Stores revisions/<sha256>.jsonc and revisions/<sha256>.md content-addressed.
 * 2. Appends one index line only when (workflow, revision) is new.
 *
 * Line shape per DESIGN b.12:
 *   {"v":1,"workflow":"master:fleet-nightly","revision":"3f2a9c1e0b7d",
 *    "file":"<64 hex>","prompt":null,"seen_at":"2026-11-11T09:00:02Z",
 *    "by":"tick","valid":true}
 *
 * @param {string} stateDir
 * @param {object} opts
 * @param {string} opts.workflow
 * @param {string} opts.revision
 * @param {Buffer|Uint8Array|string|null} [opts.fileBytes]
 * @param {Buffer|Uint8Array|string|null} [opts.promptBytes]
 * @param {string} [opts.by]
 * @param {boolean} [opts.valid]
 * @param {Date|string} [opts.at]
 * @returns {Promise<boolean>} true if a new revision was recorded, false if already known
 */
export async function recordRevision(stateDir, {
  workflow,
  revision,
  fileBytes = null,
  promptBytes = null,
  by = 'tick',
  valid = true,
  at = new Date(),
} = {}) {
  if (await known(stateDir, workflow, revision)) {
    return false;
  }

  const revDir = await ensureRevisionsDir(stateDir);

  let fileSha = null;
  if (fileBytes) {
    fileSha = createHash('sha256').update(fileBytes).digest('hex');
    const filePath = join(revDir, `${fileSha}.jsonc`);
    try {
      await stat(filePath);
    } catch {
      await writeAtomic(filePath, fileBytes, { mode: 0o600 });
    }
  }

  let promptSha = null;
  if (promptBytes && promptBytes.length > 0) {
    promptSha = createHash('sha256').update(promptBytes).digest('hex');
    const promptPath = join(revDir, `${promptSha}.md`);
    try {
      await stat(promptPath);
    } catch {
      await writeAtomic(promptPath, promptBytes, { mode: 0o600 });
    }
  }

  const seen_at = at instanceof Date ? at.toISOString() : (at || new Date().toISOString());
  const record = {
    v: 1,
    workflow,
    revision,
    file: fileSha,
    prompt: promptSha,
    seen_at,
    by,
    valid: Boolean(valid),
  };

  const indexFile = join(revDir, 'index.jsonl');
  await appendLine(indexFile, record);
  return true;
}
