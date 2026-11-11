// resolve.mjs — workflow ID and bare-stem resolution.
//
// Spec ref: §10.1 (ID resolution: <agency>:<stem>, or bare stem when unique)

import { discover } from './discover.mjs';

export class ResolveError extends Error {
  /**
   * @param {string} message
   * @param {number} [exitCode=1]
   * @param {string[]} [candidates=[]]
   */
  constructor(message, exitCode = 1, candidates = []) {
    super(message);
    this.name = 'ResolveError';
    this.exitCode = exitCode;
    this.candidates = candidates;
  }
}

/**
 * Resolve an id or bare stem against discovered workflows.
 *
 * @param {object} ctx - Context with home, uid, err, etc.
 * @param {string} idOrStem - "<agency>:<stem>" or bare "<stem>"
 * @param {{ proposal?: boolean }} [opts]
 * @returns {Promise<{ agency: string, root: string, stem: string, id: string, path: string }>}
 */
export async function resolveId(ctx, idOrStem, { proposal = false } = {}) {
  if (typeof idOrStem !== 'string' || idOrStem.length === 0) {
    const msg = `workflow '${idOrStem}' not found`;
    if (ctx?.err) ctx.err(`scheduled: ${msg}\n`);
    throw new ResolveError(msg, 1);
  }

  const { files } = await discover({ home: ctx.home, uid: ctx.uid });
  const isProposal = !!proposal;

  let matches;
  const colonIndex = idOrStem.indexOf(':');
  if (colonIndex >= 0) {
    const targetAgency = idOrStem.slice(0, colonIndex);
    const targetStem = idOrStem.slice(colonIndex + 1);
    matches = files.filter(
      (f) => f.proposal === isProposal && f.agency === targetAgency && f.stem === targetStem
    );
  } else {
    matches = files.filter(
      (f) => f.proposal === isProposal && f.stem === idOrStem
    );
  }

  if (matches.length === 0) {
    const msg = `workflow '${idOrStem}' not found`;
    if (ctx?.err) ctx.err(`scheduled: ${msg}\n`);
    throw new ResolveError(msg, 1);
  }

  if (matches.length > 1) {
    const candidates = matches.map((m) => m.id);
    const msg = `ambiguous workflow id '${idOrStem}'; candidates: ${candidates.join(', ')}`;
    if (ctx?.err) ctx.err(`scheduled: ${msg}\n`);
    throw new ResolveError(msg, 1, candidates);
  }

  const m = matches[0];
  return {
    agency: m.agency,
    root: m.root,
    stem: m.stem,
    id: m.id,
    path: m.path,
  };
}
