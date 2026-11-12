// inbox.mjs — the hand-off to the superagent: one occurrence record v1 per file in an inbox directory.
//
// The record format is the fork's (scheduled-source §2; test/fixtures/occurrence-v1.json is byte-identical
// to the fork's tests/fixtures/scheduled-occurrence-v1.json). The fork's Source reads `<inbox>/*.json`, moves
// what it received into `.done/` and what it refused into `.bad/`. This side writes only `<inbox>/*.json`
// (through `.tmp/`) and withdraws its own schedule records; it never reads, moves or deletes `.done/` or `.bad/`.

import { existsSync, readdirSync, readFileSync, unlinkSync } from 'node:fs';
import { chmod, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { linkExclusive } from './atomic.mjs';
import { occurrenceName, runName } from './ids.mjs';

/** The `by` of records the heartbeat writes; the tick withdraws only these. */
export const HEARTBEAT = 'scheduled-heartbeat';
/** The `by` of records `scheduled run` writes. */
export const RUN = 'scheduled-run';

const NAMESPACE_RE = /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/;

/** Creates `<inbox>` and `<inbox>/.tmp` with mode 0700. */
async function ensureInbox(inbox) {
  for (const dir of [inbox, join(inbox, '.tmp')]) {
    await mkdir(dir, { recursive: true, mode: 0o700 });
    await chmod(dir, 0o700).catch(() => {});
  }
}

/**
 * The occurrence record v1 of one item. Field order follows the fork's schema.
 *
 * @param {object} o
 * @param {'schedule'|'manual'} o.kind
 * @param {string} o.namespace  agency id (`master`, `team/widgets`)
 * @param {string} o.item       item stem
 * @param {string} [o.name]     the item's `name`, when it has one
 * @param {string} o.cwd        agency folder (real path)
 * @param {string} o.file       absolute path of the .jsonc
 * @param {Date} o.due          latest due instant, or the request time of a run
 * @param {string} [o.run]      ULID of a manual run
 * @param {number} o.missed
 * @param {string} o.revision
 * @param {string} o.text       the prompt as read now
 * @param {string} o.by
 * @param {Date} o.at
 * @returns {object}
 */
export function makeRecord({ kind, namespace, item, name, cwd, file, due, run, missed, revision, text, by, at }) {
  return {
    v: 1,
    kind,
    namespace,
    item,
    ...(name ? { name } : {}),
    cwd,
    file,
    due: due.toISOString(),
    ...(kind === 'manual' ? { run } : {}),
    missed,
    revision,
    text,
    by,
    at: at.toISOString(),
  };
}

/** The file name of a record: `<ns>~<item>@<stamp>.json` or `<ns>~<item>@run~<ULID>.json`. */
export function recordName(record) {
  return record.kind === 'manual'
    ? runName({ namespace: record.namespace, item: record.item, run: record.run })
    : occurrenceName({ namespace: record.namespace, item: record.item, due: new Date(record.due) });
}

/** Why the Source would refuse `record`, for the fields this side derives from paths; null when none. */
export function recordProblem(record) {
  if (!NAMESPACE_RE.test(record.namespace) || record.namespace.length > 200) return `namespace "${record.namespace}" is not a record namespace`;
  if (record.cwd.length > 4096 || record.file.length > 4096) return 'path longer than 4096';
  if (record.text.length > 32_768) return 'text longer than 32768';
  return null;
}

/**
 * Link `record` into `<inbox>/<name>`: write `.tmp/<name>.<pid>.<hex>` (0600), fsync, then `link()`.
 * An existing `<inbox>/<name>` or `<inbox>/.done/<name>` answers `exists`: the occurrence was handed off.
 *
 * @param {string} inbox
 * @param {object} record
 * @returns {Promise<{ name: string, result: 'created' | 'exists' }>}
 */
export async function handOff(inbox, record) {
  await ensureInbox(inbox);
  const name = recordName(record);
  const result = await linkExclusive(join(inbox, '.tmp'), join(inbox, name), JSON.stringify(record, null, 2) + '\n', {
    exists: () => existsSync(join(inbox, '.done', name)),
  });
  return { name, result };
}

/** The names of records waiting in `<inbox>` (`*.json`, no dot-files); none when it does not exist. */
export function waiting(inbox) {
  try {
    return readdirSync(inbox).filter((n) => n.endsWith('.json') && !n.startsWith('.')).sort();
  } catch {
    return [];
  }
}

/** The parsed record `<dir>/<name>`, or null when it is gone or unreadable. */
export function readRecord(dir, name) {
  try {
    const value = JSON.parse(readFileSync(join(dir, name), 'utf8'));
    return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

/** Unlinks `<inbox>/<name>`; true when this call removed it. */
export function withdraw(inbox, name) {
  try {
    unlinkSync(join(inbox, name));
    return true;
  } catch {
    return false;
  }
}
