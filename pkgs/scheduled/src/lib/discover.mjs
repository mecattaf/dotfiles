import { readdirSync, statSync, lstatSync } from 'node:fs';
import path from 'node:path';

// Stem regex from specification: ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$
const STEM_RE = /^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/;

/**
 * Checks if a path is a real directory (not a symlink)
 * @param {string} p
 * @returns {boolean}
 */
function isRealDir(p) {
  try {
    const st = lstatSync(p);
    return st.isDirectory();
  } catch {
    return false;
  }
}

/**
 * Validates file/directory ownership and permissions
 * @param {string} targetPath
 * @param {number} expectedUid
 * @returns {{ ok: boolean, message?: string }}
 */
function checkOwnership(targetPath, expectedUid) {
  try {
    const st = statSync(targetPath);
    if (st.uid !== expectedUid) {
      return {
        ok: false,
        message: `Ownership mismatch for ${targetPath}: expected uid ${expectedUid}, got ${st.uid}`
      };
    }
    if ((st.mode & 0o022) !== 0) {
      return {
        ok: false,
        message: `Permissions too permissive for ${targetPath}: mode ${(st.mode & 0o777).toString(8)} is group- or world-writable`
      };
    }
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      message: `Cannot stat ${targetPath}: ${err.message}`
    };
  }
}

/**
 * Walk directory tree and discover agencies and their scheduled items
 * @param {{ home: string, uid?: number }} options
 * @returns {Promise<{ agencies: Array<{id: string, root: string, dir: string}>, files: Array<{agency: string, root: string, stem: string, id: string, path: string}>, problems: Array<{severity: string, code: string, line: number, col: number, message: string, path: string}>, visited: string[] }>}
 */
export async function discover({ home, uid }) {
  const expectedUid = uid !== undefined ? uid : (typeof process.getuid === 'function' ? process.getuid() : 1000);
  const realHome = path.resolve(home);

  const agencies = [];
  const files = [];
  const problems = [];
  const visited = [];

  function processAgency(root, agencyId) {
    const agencyDir = path.join(root, '.agency');
    agencies.push({
      id: agencyId,
      root,
      dir: agencyDir
    });

    const agencyOwnership = checkOwnership(agencyDir, expectedUid);
    if (!agencyOwnership.ok) {
      problems.push({
        severity: 'error',
        code: 'ownership',
        line: 0,
        col: 0,
        message: agencyOwnership.message,
        path: agencyDir
      });
    }

    const scheduledDir = path.join(agencyDir, 'scheduled');
    let scheduledStat;
    try {
      scheduledStat = statSync(scheduledDir);
    } catch {
      // no scheduled directory
      return;
    }
    if (!scheduledStat.isDirectory()) {
      return;
    }
    const scheduledOwnership = checkOwnership(scheduledDir, expectedUid);
    if (!scheduledOwnership.ok) {
      problems.push({
        severity: 'error',
        code: 'ownership',
        line: 0,
        col: 0,
        message: scheduledOwnership.message,
        path: scheduledDir
      });
    }
    let entries;
    try {
      entries = readdirSync(scheduledDir, { withFileTypes: true });
    } catch (err) {
      problems.push({
        severity: 'error',
        code: 'io',
        line: 0,
        col: 0,
        message: `Failed to read ${scheduledDir}: ${err.message}`,
        path: scheduledDir
      });
      return;
    }
    // Items are the *.jsonc files directly in scheduled/; subdirectories (a left-over proposed/) are not read.
    for (const ent of entries) {
      if (!ent.name.endsWith('.jsonc') || ent.name.startsWith('.')) continue;
      const filePath = path.join(scheduledDir, ent.name);
      const stem = ent.name.slice(0, -6);
      if (!STEM_RE.test(stem)) {
        problems.push({
          severity: 'error',
          code: 'stem',
          line: 0,
          col: 0,
          message: `Invalid item stem "${stem}" in ${ent.name}`,
          path: filePath
        });
        continue;
      }
      const fileOwnership = checkOwnership(filePath, expectedUid);
      if (!fileOwnership.ok || !agencyOwnership.ok || !scheduledOwnership.ok) {
        const msg = !fileOwnership.ok
          ? fileOwnership.message
          : (!agencyOwnership.ok
            ? `Agency directory ownership invalid for ${filePath}`
            : `Scheduled directory ownership invalid for ${filePath}`);
        problems.push({
          severity: 'error',
          code: 'ownership',
          line: 0,
          col: 0,
          message: msg,
          path: filePath
        });
      }
      files.push({
        agency: agencyId,
        root,
        stem,
        id: `${agencyId}:${stem}`,
        path: filePath
      });
    }
  }

  function walk(dir, depth) {
    visited.push(dir);

    // Check if dir is an agency root (down to depth 3)
    if (depth <= 3) {
      const agencyDir = path.join(dir, '.agency');
      if (isRealDir(agencyDir)) {
        if (dir === realHome) {
          processAgency(dir, 'master');
        } else {
          const rel = path.relative(realHome, dir).split(path.sep).join('/');
          if (rel === 'master') {
            problems.push({
              severity: 'error',
              code: 'agency-name',
              line: 0,
              col: 0,
              message: 'Only ~ can be master agency',
              path: agencyDir
            });
          } else {
            processAgency(dir, rel);
          }
        }
      }
    }

    // Walk down to depth 4
    if (depth >= 4) return;

    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }

    // Sort entries deterministically
    entries.sort((a, b) => a.name.localeCompare(b.name));

    for (const ent of entries) {
      // Do not descend into dot-directories or node_modules
      if (ent.name.startsWith('.') || ent.name === 'node_modules') continue;

      // Never follow symlinks while walking
      if (ent.isSymbolicLink() || !ent.isDirectory()) continue;

      walk(path.join(dir, ent.name), depth + 1);
    }
  }

  walk(realHome, 0);

  // Sort results by agency id then stem
  agencies.sort((a, b) => a.id.localeCompare(b.id));
  files.sort((a, b) => {
    const cmp = a.agency.localeCompare(b.agency);
    if (cmp !== 0) return cmp;
    return a.stem.localeCompare(b.stem);
  });

  return { agencies, files, problems, visited };
}
