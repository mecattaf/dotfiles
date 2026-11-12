// ids.mjs — agency/item identity and inbox record names.
//
// Spec ref: agency ids, item ids
//           scheduled-jsonc §3 (record file names)

import { randomBytes } from 'node:crypto';
import { relative } from 'node:path';

// ---------------------------------------------------------------------------
// Stem validation
// ---------------------------------------------------------------------------

/**
 * Regular expression that an item stem must match.
 * Pattern: ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$
 * (single character stems are also valid: just [a-z0-9])
 */
export const STEM_RE = /^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/;

// ---------------------------------------------------------------------------
// Agency id
// ---------------------------------------------------------------------------

/**
 * Compute the agency id for the agency rooted at `root`.
 *
 * - If `root` resolves to `home`, return `'master'`.
 * - Otherwise return the POSIX-style path relative to `home`
 *   (e.g. `'mecattaf/crm'`).
 *
 * @param {string} root  absolute path to the agency root directory
 * @param {string} home  absolute path to $HOME
 * @returns {string}
 */
export function agencyId(root, home) {
  if (root === home) return 'master';
  return relative(home, root);
}

// ---------------------------------------------------------------------------
// Id parsing
// ---------------------------------------------------------------------------

/**
 * Parse an item id of the form `<agency>:<stem>`.
 *
 * @param {string} id
 * @returns {{ agency: string, stem: string }}
 * @throws {Error} if the id does not contain exactly one `:` separator
 */
export function parseId(id) {
  const colon = id.indexOf(':');
  if (colon < 0) throw new Error(`Invalid item id (no colon): ${id}`);
  const agency = id.slice(0, colon);
  const stem = id.slice(colon + 1);
  return { agency, stem };
}

// ---------------------------------------------------------------------------
// Timestamps
// ---------------------------------------------------------------------------

/**
 * Format a Date as the occurrence stamp of a record name: `yyyymmddThhmmZ`.
 *
 * @param {Date} date
 * @returns {string}  e.g. `'20261112T0000Z'`
 */
export function spoolStamp(date) {
  const y = date.getUTCFullYear().toString().padStart(4, '0');
  const mo = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const d = date.getUTCDate().toString().padStart(2, '0');
  const h = date.getUTCHours().toString().padStart(2, '0');
  const mi = date.getUTCMinutes().toString().padStart(2, '0');
  return `${y}${mo}${d}T${h}${mi}Z`;
}

// ---------------------------------------------------------------------------
// Occurrence record file names (the producer's convention; the Source reads any *.json)
// ---------------------------------------------------------------------------

// `~` separates namespace and item; `/` in a namespace (a nested agency) becomes `+`.
const nsSlug = (namespace) => namespace.replaceAll('/', '+');

/**
 * The inbox file name of a scheduled occurrence: `<ns>~<item>@<yyyymmddThhmmZ>.json`.
 *
 * @param {{ namespace: string, item: string, due: Date }} opts
 * @returns {string}
 */
export function occurrenceName({ namespace, item, due }) {
  return `${nsSlug(namespace)}~${item}@${spoolStamp(due)}.json`;
}

/**
 * The inbox file name of a manual run: `<ns>~<item>@run~<ULID>.json`.
 *
 * @param {{ namespace: string, item: string, run: string }} opts
 * @returns {string}
 */
export function runName({ namespace, item, run }) {
  return `${nsSlug(namespace)}~${item}@run~${run}.json`;
}

// ---------------------------------------------------------------------------
// ULID
// ---------------------------------------------------------------------------

// Crockford base32 alphabet (uppercase): 0-9 A-H J-N P-Z (excludes I L O U)
const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/**
 * Generate a standard 26-character Crockford base32 ULID.
 *
 * Layout: 10 chars time (48-bit milliseconds) + 16 chars random (80 bits).
 *
 * @param {Date} [date]  timestamp to encode; defaults to `new Date()`
 * @returns {string}  uppercase 26-character ULID
 */
export function ulid(date = new Date()) {
  const tsMs = date.getTime();
  if (!Number.isFinite(tsMs)) throw new RangeError('Invalid date for ULID');

  // Encode 48-bit timestamp into 10 Crockford base32 characters.
  // Max 48-bit value = 2^48 - 1 = 281474976710655; JS bitwise ops are 32-bit
  // so we split into high and low 32-bit halves.
  let hi = Math.floor(tsMs / 0x100000000); // top 16 bits of 48
  let lo = tsMs >>> 0;                      // low 32 bits

  const timeChars = new Array(10);
  // Encode right-to-left in base 32.
  // We only have 48 bits: encode bottom 48 bits of a 64-bit number stored
  // as [hi (top 16 bits), lo (low 32 bits)].
  // We work right-to-left: each step pulls 5 bits from the least-significant.
  let remaining_lo = lo;
  let remaining_hi = hi & 0xFFFF; // only 16 bits in hi for a 48-bit ms value
  for (let i = 9; i >= 0; i--) {
    timeChars[i] = CROCKFORD[remaining_lo & 0x1F];
    // right-shift the combined [remaining_hi, remaining_lo] by 5 bits
    remaining_lo = (remaining_lo >>> 5) | ((remaining_hi & 0x1F) << 27);
    remaining_hi = remaining_hi >>> 5;
  }

  // 80 random bits = 10 bytes → 16 Crockford chars (each takes 5 bits)
  const rnd = randomBytes(10);
  const randChars = new Array(16);
  // Pack 80 bits into 16 × 5-bit groups.
  // rnd[0] is MSB; build a bit stream.
  let bits = 0n;
  for (let i = 0; i < 10; i++) bits = (bits << 8n) | BigInt(rnd[i]);
  for (let i = 15; i >= 0; i--) {
    randChars[i] = CROCKFORD[Number(bits & 0x1Fn)];
    bits >>= 5n;
  }

  return timeChars.join('') + randChars.join('');
}
