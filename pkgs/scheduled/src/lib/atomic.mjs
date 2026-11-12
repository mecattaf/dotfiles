// atomic.mjs — crash-safe file operations used by writers and the heartbeat.
//
// All writes go through a tmp file → fsync → rename pattern so readers never
// see a partial file. Directory fsyncs ensure the rename survives a crash.

import { randomBytes } from 'node:crypto';
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
    await fh.write(data);
    await fh.sync();
  } finally {
    await fh.close();
  }
  await rename(tmp, path);
  fsyncDir(dir);
}

/**
 * Write `data` into `tmpDir/<basename(destPath)>.<pid>.<6 random hex>` (mode 0600), fsync, then hard-link
 * it to `destPath` and unlink the temp. Returns `'created'`, or `'exists'` when `destPath` already exists
 * (EEXIST) or `exists()` answers true after the temp is written. Any other error is re-thrown.
 *
 * @param {string} tmpDir
 * @param {string} destPath
 * @param {string | Buffer | Uint8Array} data
 * @param {{ exists?: () => boolean }} [opts]
 * @returns {Promise<'created' | 'exists'>}
 */
export async function linkExclusive(tmpDir, destPath, data, { exists } = {}) {
  const tmp = join(tmpDir, `${basename(destPath)}.${process.pid}.${randomBytes(3).toString('hex')}`);
  const fh = await open(tmp, 'w', 0o600);
  try {
    await fh.write(data);
    await fh.sync();
  } finally {
    await fh.close();
  }
  try {
    if (exists?.()) return 'exists';
    await link(tmp, destPath);
  } catch (err) {
    if (err.code === 'EEXIST') return 'exists';
    throw err;
  } finally {
    await unlink(tmp).catch(() => {});
  }
  // The new name is durable only once its directory is: a power cut after link() could otherwise lose
  // the record the commit then skips.
  fsyncDir(dirname(destPath));
  return 'created';
}
