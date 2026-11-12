// resolve.mjs — item ID and bare-stem resolution.
//
// docs/scheduled.md, Everyday commands (ID resolution: <agency>:<stem>, or bare stem when unique)

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
 * Resolve an id or bare stem against discovered items.
 *
 * @param {object} ctx - Context with home, uid, err, etc.
 * @param {string} idOrStem - "<agency>:<stem>" or bare "<stem>"
 * @returns {Promise<{ agency: string, root: string, stem: string, id: string, path: string }>}
 */
export async function resolveId(ctx, idOrStem) {
  if (typeof idOrStem !== 'string' || idOrStem.length === 0) {
    const msg = `item '${idOrStem}' not found`;
    if (ctx?.err) ctx.err(`scheduled: ${msg}\n`);
    throw new ResolveError(msg, 1);
  }

  const { files } = await discover({ home: ctx.home, uid: ctx.uid });

  let matches;
  const colonIndex = idOrStem.indexOf(':');
  if (colonIndex >= 0) {
    const targetAgency = idOrStem.slice(0, colonIndex);
    const targetStem = idOrStem.slice(colonIndex + 1);
    matches = files.filter(
      (f) => f.agency === targetAgency && f.stem === targetStem
    );
  } else {
    matches = files.filter(
      (f) => f.stem === idOrStem
    );
  }

  if (matches.length === 0) {
    const msg = `item '${idOrStem}' not found`;
    if (ctx?.err) ctx.err(`scheduled: ${msg}\n`);
    throw new ResolveError(msg, 1);
  }

  if (matches.length > 1) {
    const candidates = matches.map((m) => m.id);
    const msg = `ambiguous item id '${idOrStem}'; candidates: ${candidates.join(', ')}`;
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
