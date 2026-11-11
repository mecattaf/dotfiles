// spool.mjs — heartbeat to floor spool management.
//
// Spec ref: §5.3 (spool layout, file names, hand-off protocol)
//           §6.2 (waiting count definition)

import { join } from 'node:path';
import { mkdir, chmod, readdir } from 'node:fs/promises';
import { linkExclusive } from './atomic.mjs';
import { spoolName, manualSpoolName, censusStamp, parseId, ulid } from './ids.mjs';

/**
 * Ensure the spool directory tree exists with mode 0700:
 *   <stateDir>/spool/{tmp,incoming,done,rejected}
 *
 * @param {string} stateDir
 */
export async function ensureSpool(stateDir) {
  const spoolDir = join(stateDir, 'spool');
  const dirs = ['tmp', 'incoming', 'done', 'rejected'];
  for (const sub of dirs) {
    const p = join(spoolDir, sub);
    await mkdir(p, { recursive: true, mode: 0o700 });
    try {
      await chmod(p, 0o700);
    } catch {}
  }
  try {
    await chmod(spoolDir, 0o700);
  } catch {}
}

/**
 * Hand off one record to the floor by writing to spool/tmp and linking
 * exclusively into spool/incoming.
 *
 * Name format per DESIGN 5.3:
 *   Scheduled: <agency>~<stem>@<yyyymmddThhmmZ>.json
 *   Manual:    <agency>~<stem>@manual~<ULID>.json
 *   Census:    census@<yyyymmddThhmmssZ>.json
 *
 * Returns 'created' on success or 'exists' when already emitted (EEXIST).
 *
 * @param {string} stateDir
 * @param {object} record
 * @returns {Promise<'created' | 'exists'>}
 */
export async function handOff(stateDir, record) {
  await ensureSpool(stateDir);

  let fileName = record.fileName;
  if (!fileName) {
    if (record.kind === 'schedule') {
      const { agency, stem } = parseId(record.workflow);
      const instant = new Date(record.instant);
      fileName = spoolName({ agency, stem, instant });
    } else if (record.kind === 'manual') {
      const { agency, stem } = parseId(record.workflow);
      const ulidStr = record.ulid ||
        (record.occurrence?.split('@manual~')[1] ??
         record.occurrence?.split('@manual:')[1] ??
         ulid(new Date(record.instant || record.at || Date.now())));
      fileName = manualSpoolName({ agency, stem, ulid: ulidStr });
    } else if (record.kind === 'census') {
      const atDate = record.at ? new Date(record.at) : new Date();
      fileName = `census@${censusStamp(atDate)}.json`;
    } else {
      const { agency, stem } = parseId(record.workflow);
      const instant = new Date(record.instant || record.at || Date.now());
      fileName = spoolName({ agency, stem, instant });
    }
  }

  const tmpDir = join(stateDir, 'spool', 'tmp');
  const destPath = join(stateDir, 'spool', 'incoming', fileName);
  const data = JSON.stringify(record, null, 2) + '\n';
  return await linkExclusive(tmpDir, destPath, data);
}

/**
 * Write one census record into spool/incoming/census@<yyyymmddThhmmssZ>.json.
 *
 * @param {string} stateDir
 * @param {object} census
 * @returns {Promise<string>} Full path of the written census file
 */
export async function writeCensus(stateDir, census) {
  await ensureSpool(stateDir);
  const atDate = census.at ? new Date(census.at) : new Date();
  const fileName = `census@${censusStamp(atDate)}.json`;
  const tmpDir = join(stateDir, 'spool', 'tmp');
  const destPath = join(stateDir, 'spool', 'incoming', fileName);
  const data = JSON.stringify(census, null, 2) + '\n';
  await linkExclusive(tmpDir, destPath, data);
  return destPath;
}

/**
 * Count the waiting hand-off occurrence records in spool/incoming/.
 * Excludes hidden files and census records.
 *
 * @param {string} stateDir
 * @returns {Promise<number>}
 */
export async function waitingCount(stateDir) {
  const incomingDir = join(stateDir, 'spool', 'incoming');
  try {
    const entries = await readdir(incomingDir);
    return entries.filter((name) => !name.startsWith('.') && !name.startsWith('census@')).length;
  } catch {
    return 0;
  }
}
