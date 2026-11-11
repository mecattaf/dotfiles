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
 * Walk directory tree and discover agencies and workflows
 * @param {{ home: string, uid?: number }} options
 * @returns {Promise<{ agencies: Array<{id: string, root: string, dir: string}>, files: Array<{agency: string, root: string, stem: string, id: string, path: string, proposal: boolean}>, problems: Array<{severity: string, code: string, line: number, col: number, message: string, path: string}>, visited: string[] }>}
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

    const workflowsDir = path.join(agencyDir, 'workflows');
    let workflowsStat;
    try {
      workflowsStat = statSync(workflowsDir);
    } catch {
      // no workflows directory
      return;
    }

    if (!workflowsStat.isDirectory()) {
      return;
    }

    const workflowsOwnership = checkOwnership(workflowsDir, expectedUid);
    if (!workflowsOwnership.ok) {
      problems.push({
        severity: 'error',
        code: 'ownership',
        line: 0,
        col: 0,
        message: workflowsOwnership.message,
        path: workflowsDir
      });
    }

    // Read workflows/ directory
    let workflowEntries;
    try {
      workflowEntries = readdirSync(workflowsDir, { withFileTypes: true });
    } catch (err) {
      problems.push({
        severity: 'error',
        code: 'io',
        line: 0,
        col: 0,
        message: `Failed to read ${workflowsDir}: ${err.message}`,
        path: workflowsDir
      });
      return;
    }

    // Process armed/paused workflows in workflows/
    for (const ent of workflowEntries) {
      if (ent.name === 'proposed') continue;
      if (!ent.name.endsWith('.jsonc')) continue;

      const filePath = path.join(workflowsDir, ent.name);
      const stem = ent.name.slice(0, -6);

      if (!STEM_RE.test(stem)) {
        problems.push({
          severity: 'error',
          code: 'stem',
          line: 0,
          col: 0,
          message: `Invalid workflow stem "${stem}" in ${ent.name}`,
          path: filePath
        });
        continue;
      }

      const fileOwnership = checkOwnership(filePath, expectedUid);
      if (!fileOwnership.ok || !agencyOwnership.ok || !workflowsOwnership.ok) {
        const msg = !fileOwnership.ok
          ? fileOwnership.message
          : (!agencyOwnership.ok
            ? `Agency directory ownership invalid for ${filePath}`
            : `Workflows directory ownership invalid for ${filePath}`);
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
        path: filePath,
        proposal: false
      });
    }

    // Process proposed/ directory
    const proposedDir = path.join(workflowsDir, 'proposed');
    let proposedStat;
    try {
      proposedStat = statSync(proposedDir);
    } catch {
      // no proposed directory
      return;
    }

    if (!proposedStat.isDirectory()) {
      return;
    }

    const proposedOwnership = checkOwnership(proposedDir, expectedUid);
    if (!proposedOwnership.ok) {
      problems.push({
        severity: 'error',
        code: 'ownership',
        line: 0,
        col: 0,
        message: proposedOwnership.message,
        path: proposedDir
      });
    }

    let proposedEntries;
    try {
      proposedEntries = readdirSync(proposedDir, { withFileTypes: true });
    } catch (err) {
      problems.push({
        severity: 'error',
        code: 'io',
        line: 0,
        col: 0,
        message: `Failed to read ${proposedDir}: ${err.message}`,
        path: proposedDir
      });
      return;
    }

    for (const ent of proposedEntries) {
      if (!ent.name.endsWith('.jsonc')) continue;

      const filePath = path.join(proposedDir, ent.name);
      const stem = ent.name.slice(0, -6);

      if (!STEM_RE.test(stem)) {
        problems.push({
          severity: 'error',
          code: 'stem',
          line: 0,
          col: 0,
          message: `Invalid workflow stem "${stem}" in ${ent.name}`,
          path: filePath
        });
        continue;
      }

      const fileOwnership = checkOwnership(filePath, expectedUid);
      if (!fileOwnership.ok || !agencyOwnership.ok || !workflowsOwnership.ok || !proposedOwnership.ok) {
        const msg = !fileOwnership.ok
          ? fileOwnership.message
          : (!agencyOwnership.ok
            ? `Agency directory ownership invalid for ${filePath}`
            : (!workflowsOwnership.ok
              ? `Workflows directory ownership invalid for ${filePath}`
              : `Proposed directory ownership invalid for ${filePath}`));
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
        path: filePath,
        proposal: true
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
    const stemCmp = a.stem.localeCompare(b.stem);
    if (stemCmp !== 0) return stemCmp;
    return (a.proposal === b.proposal ? 0 : a.proposal ? 1 : -1);
  });

  return { agencies, files, problems, visited };
}
