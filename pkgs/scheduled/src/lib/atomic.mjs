// atomic.mjs — crash-safe file operations used by writers and the heartbeat.
//
// All writes go through a tmp file → fsync → rename pattern so readers never
// see a partial file. Directory fsyncs ensure the rename survives a crash.

import { open, rename, link, unlink } from 'node:fs/promises';
import { openSync, fsyncSync, closeSync } from 'node:fs';
import { dirname, basename, join } from 'node:path';

/**
 * Synchronously fsync a directory fd.
 * @param {string} dir
 */
function fsyncDir(dir) {
  const fd = openSync(dir, 'r');
  try {
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

/**
 * Write `data` (string | Buffer | Uint8Array) to `path` atomically.
 * Uses `.<basename>.<pid>.tmp` in the same directory, fsyncs the file,
 * renames over `path`, then fsyncs the directory.
 *
 * @param {string} path
 * @param {string | Buffer | Uint8Array} data
 * @param {{ mode?: number }} [opts]
 */
export async function writeAtomic(path, data, { mode = 0o600 } = {}) {
  const dir = dirname(path);
  const tmp = join(dir, `.${basename(path)}.${process.pid}.tmp`);
  const fh = await open(tmp, 'w', mode);
  try {
    await fh.write(typeof data === 'string' ? data : data);
    await fh.sync();
  } finally {
    await fh.close();
  }
  await rename(tmp, path);
  fsyncDir(dir);
}

/**
 * Write `data` into `tmpDir/<basename(destPath)>.<pid>`, fsync, then
 * hard-link to `destPath`.  Unlinks the temp after a successful link.
 * Returns `'created'` on success or `'exists'` when `destPath` already
 * exists (EEXIST).  Any other error is re-thrown.
 *
 * @param {string} tmpDir
 * @param {string} destPath
 * @param {string | Buffer | Uint8Array} data
 * @returns {Promise<'created' | 'exists'>}
 */
export async function linkExclusive(tmpDir, destPath, data) {
  const tmp = join(tmpDir, `${basename(destPath)}.${process.pid}`);
  const fh = await open(tmp, 'w', 0o600);
  try {
    await fh.write(typeof data === 'string' ? data : data);
    await fh.sync();
  } finally {
    await fh.close();
  }
  try {
    await link(tmp, destPath);
  } catch (err) {
    await unlink(tmp).catch(() => {});
    if (err.code === 'EEXIST') return 'exists';
    throw err;
  }
  await unlink(tmp).catch(() => {});
  return 'created';
}

/**
 * Append one JSON line (JSON.stringify(obj) + '\n') to `path` using
 * O_APPEND so concurrent writers do not corrupt each other, then fsyncs.
 *
 * @param {string} path
 * @param {object} obj
 */
export async function appendLine(path, obj) {
  const line = JSON.stringify(obj) + '\n';
  const fh = await open(path, 'a', 0o600);
  try {
    await fh.write(line);
    await fh.sync();
  } finally {
    await fh.close();
  }
}
