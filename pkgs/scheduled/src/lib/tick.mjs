// tick.mjs — heartbeat tick algorithm (phases 0-8).
//
// Spec ref: §6 (The heartbeat tick algorithm)
//           §6.1 (Discovery)
//           §6.2 (The wake table)
//           §6.3 (Journal lines and exit codes)
//           §5.1, §5.3, §b.1, §b.12

import { join, dirname } from 'node:path';
import path from 'node:path';
import { statSync } from 'node:fs';
import { readFile, open, unlink, mkdir, link } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { discover } from './discover.mjs';
import { validateFile } from './validate.mjs';
import { revision } from './schema.mjs';
import { instantsBetween } from './cron.mjs';
import { wakeFloor } from './floor.mjs';
import { writeAtomic } from './atomic.mjs';
import { ensureSpool, handOff, writeCensus, waitingCount } from './spool.mjs';
import { recordRevision, known } from './ledger.mjs';

/** This boot's id, or null off Linux. */
async function currentBoot() {
  try { return (await readFile('/proc/sys/kernel/random/boot_id', 'utf8')).trim() || null; } catch { return null; }
}

/** A process's start time in clock ticks since boot (field 22 of /proc/PID/stat), or null. */
export async function processStart(pid) {
  try {
    const stat = await readFile(`/proc/${pid}/stat`, 'utf8');
    return stat.slice(stat.lastIndexOf(')') + 2).split(' ')[19] ?? null;
  } catch { return null; }
}

/**
 * Whether the lock text `content` names a holder that still runs.
 * The text is `PID BOOT START` (older locks hold the PID alone). A lock written
 * in another boot is stale: after a power cut its PID usually belongs to some
 * other process, so a liveness check alone would wait on it forever (found by
 * the VM check's power cut). Within a boot, a PID whose start time differs was
 * reused and is stale too.
 */
export async function holderAlive(content, { boot, start = processStart } = {}) {
  const [pidText, lockBoot, lockStart] = content.trim().split(/\s+/);
  const pid = parseInt(pidText, 10);
  if (!pid || Number.isNaN(pid)) return false;
  if (lockBoot && boot && lockBoot !== boot) return false;
  try {
    process.kill(pid, 0);
  } catch (e) {
    if (e.code !== 'EPERM') return false;
  }
  if (lockStart) {
    const now = await start(pid);
    if (now !== null && now !== lockStart) return false;
  }
  return true;
}

/**
 * Acquire an exclusive lock on lockPath: O_EXCL create holding
 * `PID BOOT START`, a stale-holder check, and a blocking retry loop.
 *
 * @param {string} lockPath
 * @param {object} [opts]
 * @param {number} [opts.retryIntervalMs=25]
 * @param {number} [opts.timeoutMs=60000]
 * @returns {Promise<() => Promise<void>>} Release function
 */
export async function acquireLock(lockPath, { retryIntervalMs = 25, timeoutMs = 300000, boot: bootOpt } = {}) {
  await mkdir(dirname(lockPath), { recursive: true, mode: 0o700 });
  const start = Date.now();
  const boot = bootOpt === undefined ? await currentBoot() : bootOpt;
  const mine = [process.pid, boot ?? '-', (await processStart(process.pid)) ?? '-'].join(' ');

  // The lock is created complete: its text is written and fsynced under a
  // private name, then link()ed into place, which fails with EEXIST while
  // another holder has it. So a lock file is never seen empty half-written
  // (evaluation review, C3.7), and an empty one can only be damage.
  const tmp = `${lockPath}.${process.pid}.tmp`;
  {
    const fh = await open(tmp, 'w', 0o600);
    try {
      await fh.writeFile(`${mine}\n`);
      await fh.sync();
    } finally {
      await fh.close();
    }
  }

  while (true) {
    try {
      await link(tmp, lockPath);
      try { await unlink(tmp); } catch {}

      return async function releaseLock() {
        // Remove only our own lock, never one a later tick holds.
        try {
          if ((await readFile(lockPath, 'utf8')).trim() === mine) await unlink(lockPath);
        } catch {}
      };
    } catch (err) {
      if (err.code !== 'EEXIST') {
        try { await unlink(tmp); } catch {}
        throw err;
      }

      // The lock file exists: take it over only from a holder that no longer runs.
      try {
        const content = await readFile(lockPath, 'utf8');
        const normalized = content.replace(/(^|\s)-(?=\s|$)/g, '$1');
        if (!(await holderAlive(normalized, { boot }))) {
          // Unlink only the text we judged, not a lock another tick just took.
          if ((await readFile(lockPath, 'utf8')) === content) {
            await unlink(lockPath);
            continue;
          }
        }
      } catch {}

      if (timeoutMs && Date.now() - start > timeoutMs) {
        try { await unlink(tmp); } catch {}
        throw new Error(`Timed out waiting for lock on ${lockPath}`);
      }

      await new Promise((resolve) => setTimeout(resolve, retryIntervalMs));
    }
  }
}

/**
 * Execute one scheduled tick pass.
 *
 * @param {object} ctx Context from makeContext()
 * @param {object} [opts]
 * @param {Date|string} [opts.now] Clock override
 * @param {string} [opts.stateDir] State directory override
 * @returns {Promise<{code: number, lines: string[]}>}
 */
export async function tick(ctx, { now: nowOpt, stateDir: stateDirOpt } = {}) {
  const passStart = performance.now();
  const stateDir = stateDirOpt || ctx.stateDir;

  const now = nowOpt
    ? (nowOpt instanceof Date ? nowOpt : new Date(nowOpt))
    : (typeof ctx.now === 'function' ? ctx.now() : new Date());

  if (Number.isNaN(now.getTime())) {
    throw new Error(`Invalid now timestamp: ${nowOpt}`);
  }

  const lines = [];

  // -------------------------------------------------------------------------
  // Phase 0: Lock
  // -------------------------------------------------------------------------
  const lockPath = join(stateDir, '.tick.lock');
  const releaseLock = await acquireLock(lockPath);

  try {
    // -----------------------------------------------------------------------
    // Phase 1: Guard
    // -----------------------------------------------------------------------
    let hostMachineId = '';
    try {
      hostMachineId = (await readFile(ctx.machineIdFile, 'utf8')).trim();
    } catch {
      hostMachineId = 'unknown';
    }

    const heartbeatPath = join(stateDir, 'heartbeat.json');
    let heartbeat = null;
    try {
      heartbeat = JSON.parse(await readFile(heartbeatPath, 'utf8'));
    } catch (err) {
      if (err.code !== 'ENOENT') {
        lines.push(`<3>guard error reading heartbeat.json: ${err.message}`);
        return { code: 1, lines };
      }
    }

    if (heartbeat !== null) {
      if (typeof heartbeat.v === 'number' && Math.floor(heartbeat.v) > 1) {
        lines.push(`<3>guard higher state version: v=${heartbeat.v}`);
        return { code: 1, lines };
      }
      if (heartbeat.machineId && hostMachineId && heartbeat.machineId !== hostMachineId) {
        lines.push('<3>guard machine-id differs: state from another host');
        return { code: 1, lines };
      }
    }

    const intakePath = join(stateDir, 'intake.json');
    let intake = null;
    try {
      intake = JSON.parse(await readFile(intakePath, 'utf8'));
    } catch (err) {
      if (err.code !== 'ENOENT') {
        lines.push(`<3>guard error reading intake.json: ${err.message}`);
        return { code: 1, lines };
      }
    }

    if (intake !== null && typeof intake.v === 'number' && Math.floor(intake.v) > 1) {
      lines.push(`<3>guard higher state version: v=${intake.v}`);
      return { code: 1, lines };
    }

    const isFirstTick = heartbeat === null;
    const lastTick = isFirstTick ? now : new Date(heartbeat.lastTick);

    // -----------------------------------------------------------------------
    // Phase 2: Intake
    // -----------------------------------------------------------------------
    const discStart = performance.now();
    const disc = await discover({ home: ctx.home, uid: ctx.uid });
    const discover_ms = Math.round(performance.now() - discStart);

    // Track new agencies
    const prevAgencies = intake?.agencies || {};
    const currentAgencies = {};
    for (const ag of disc.agencies) {
      if (!prevAgencies[ag.id]) {
        lines.push(`<5>new-agency agency=${ag.id} root=${ag.root}`);
        currentAgencies[ag.id] = { firstSeen: now.toISOString(), root: ag.root };
      } else {
        currentAgencies[ag.id] = prevAgencies[ag.id];
      }
    }

    const prevFiles = intake?.files || {};
    const currentFiles = {};
    const workflows = [];

    for (const f of disc.files) {
      const filePath = f.path;
      const prev = prevFiles[filePath];

      let st = null;
      try {
        st = statSync(filePath, { bigint: true });
      } catch {
        continue;
      }

      const mtimeMs = Number(st.mtimeMs);
      // Young means written within 2 s of now, either side. A mtime further in
      // the future was set under a clock that has since gone back (a power cut,
      // a corrected RTC): the file is not being written now, so it is read, or it
      // would stay unparsed until the clock caught up (found by the VM check).
      const age = now.getTime() - mtimeMs;
      const isYoung = age > -2000 && age < 2000;

      if (isYoung) {
        if (prev) {
          const youngProb = { severity: 'warning', code: 'young', line: 0, col: 0, message: 'File is younger than 2s; previous parse used' };
          const problems = [youngProb, ...(prev.problems || [])];
          currentFiles[filePath] = { ...prev, problems, id: f.id };
          workflows.push({ id: f.id, ...prev, file: f, path: filePath, problems, isYoung: true });
        } else {
          const youngProb = { severity: 'warning', code: 'young', line: 0, col: 0, message: 'File is younger than 2s; previous parse used' };
          const problems = [youngProb];
          // No stat is cached for a file never parsed: the next pass must parse it,
          // or the unchanged-stat reuse below would keep this placeholder (invalid,
          // unscheduled) until the file changed (evaluation review, C3.4).
          currentFiles[filePath] = {
            id: f.id,
            dev: null,
            ino: null,
            size: null,
            mtimeNs: null,
            revision: null,
            problems,
            firstSeen: now.toISOString(),
            armedSince: null,
            valid: false,
            enabled: false,
          };
          workflows.push({
            id: f.id,
            file: f,
            path: filePath,
            revision: null,
            valid: false,
            enabled: false,
            problems,
            spec: null,
            isYoung: true,
          });
        }
      } else if (
        prev &&
        prev.dev === String(st.dev) &&
        prev.ino === String(st.ino) &&
        prev.size === Number(st.size) &&
        prev.mtimeNs === String(st.mtimeNs)
      ) {
        // Reuse cached parse
        currentFiles[filePath] = { ...prev, id: f.id };
        workflows.push({ id: f.id, ...prev, file: f, path: filePath });
      } else {
        // New or changed file
        const valRes = await validateFile(filePath, { uid: ctx.uid, proposal: f.proposal });
        const problems = valRes.problems || [];
        const valid = !problems.some((p) => p.severity === 'error');
        const rev = valRes.value?._revision ?? (valRes.bytes ? revision(valRes.bytes, valRes.promptBytes) : null);
        const enabled = valid ? (valRes.value?.spec?.enabled ?? valRes.value?.enabled ?? true) : false;
        const on = valRes.value?.spec?.on ?? valRes.value?.on ?? {};

        const isRevKnown = rev ? await known(stateDir, f.id, rev) : false;
        if (rev && !isRevKnown) {
          await recordRevision(stateDir, {
            workflow: f.id,
            revision: rev,
            fileBytes: valRes.bytes,
            promptBytes: valRes.promptBytes,
            by: 'tick',
            valid,
            at: now,
          });

          if (!valid) {
            const firstErr = problems.find((p) => p.severity === 'error') || problems[0] || { line: 0, col: 0 };
            lines.push(`<4>invalid workflow=${f.id} rev=${rev} at=${firstErr.line}:${firstErr.col}`);
          }
        }

        const firstSeen = prev?.firstSeen || now.toISOString();
        let armedSince = null;
        if (valid && enabled && !f.proposal) {
          if (!prev || !prev.valid || !prev.enabled || !prev.armedSince) {
            if (prev && !prev.valid) {
              // Fixed: anchor to lastTick so latest missed instant is due
              armedSince = lastTick ? lastTick.toISOString() : now.toISOString();
            } else {
              // Brand new valid & enabled file or re-enabled
              armedSince = now.toISOString();
            }
          } else {
            armedSince = prev.armedSince;
          }
        }

        const fileRecord = {
          id: f.id,
          dev: String(st.dev),
          ino: String(st.ino),
          size: Number(st.size),
          mtimeNs: String(st.mtimeNs),
          revision: rev,
          problems,
          firstSeen,
          armedSince,
          valid,
          enabled,
          on,
        };
        currentFiles[filePath] = fileRecord;
        workflows.push({
          id: f.id,
          file: f,
          path: filePath,
          revision: rev,
          valid,
          enabled,
          on,
          problems,
          armedSince,
          firstSeen,
        });
      }
    }

    // -----------------------------------------------------------------------
    // Phase 3: Census
    // -----------------------------------------------------------------------
    const censusWorkflows = workflows.map((w) => ({
      id: w.id,
      file: w.path,
      state: w.valid ? 'valid' : 'invalid',
      enabled: Boolean(w.enabled),
      revision: w.revision,
      problems: w.problems || [],
    }));

    const census = {
      v: 1,
      kind: 'census',
      at: now.toISOString(),
      machineId: hostMachineId,
      workflows: censusWorkflows,
    };
    await writeCensus(stateDir, census);

    // -----------------------------------------------------------------------
    // Phase 4: Decode
    // -----------------------------------------------------------------------
    let clockWentBack = false;
    const dueRecords = [];

    if (now.getTime() < lastTick.getTime()) {
      lines.push('<4>clock went back');
      clockWentBack = true;
    } else if (!isFirstTick) {
      for (const w of workflows) {
        if (w.valid && w.enabled && !w.file?.proposal && w.on?.schedule?.length > 0) {
          const anchorTime = w.armedSince
            ? Math.max(lastTick.getTime(), new Date(w.armedSince).getTime())
            : lastTick.getTime();
          const anchor = new Date(anchorTime);
          const instants = instantsBetween(w.on.schedule, anchor, now);

          if (instants.length > 0) {
            const latestInstant = instants[instants.length - 1];
            const missed = instants.length - 1;
            lines.push(`<6>decode workflow=${w.id} due=${latestInstant.toISOString()}`);
            dueRecords.push({
              v: 1,
              kind: 'schedule',
              occurrence: `${w.id}@${latestInstant.toISOString()}`,
              workflow: w.id,
              agency: w.file?.root || ctx.home,
              file: w.path,
              instant: latestInstant.toISOString(),
              missed,
              revision: w.revision,
              by: 'scheduled-heartbeat',
              inputs: {},
              at: now.toISOString(),
            });
          }
        }
      }
    }

    // -----------------------------------------------------------------------
    // Phase 5: Hand off
    // -----------------------------------------------------------------------
    if (!clockWentBack) {
      for (const rec of dueRecords) {
        await handOff(stateDir, rec);
      }
    }

    // -----------------------------------------------------------------------
    // Phase 6: Commit
    // -----------------------------------------------------------------------
    let commitFaulted = false;
    if (!clockWentBack) {
      try {
        const heartbeatData = {
          v: 1,
          machineId: hostMachineId,
          lastTick: now.toISOString(),
        };
        await writeAtomic(heartbeatPath, JSON.stringify(heartbeatData, null, 2) + '\n');

        const intakeData = {
          v: 1,
          files: currentFiles,
          agencies: currentAgencies,
        };
        await writeAtomic(intakePath, JSON.stringify(intakeData, null, 2) + '\n');
      } catch (err) {
        lines.push(`<3>guard error committing state: ${err.message}`);
        commitFaulted = true;
      }
    }

    // -----------------------------------------------------------------------
    // Phase 7: Floor
    // -----------------------------------------------------------------------
    let floorFaulted = false;
    try {
      const waiting = await waitingCount(stateDir);
      const runner = (argv) => new Promise((resolve) => {
        const nodeDir = path.dirname(process.execPath);
        const env = {
          ...process.env,
          ...(ctx.env || {}),
          PATH: process.env.PATH ? `${nodeDir}:${process.env.PATH}` : nodeDir,
        };
        execFile(ctx.dshd, argv, { timeout: 150_000, env }, (error, stdout, stderr) => {
          const outStr = String(stdout || '');
          const errStr = String(stderr || '');
          if (error && typeof error.code === 'number') {
            resolve({ code: error.code, stdout: outStr, stderr: errStr });
          } else if (error) {
            resolve({ code: 7, stdout: outStr, stderr: errStr || error.message });
          } else {
            resolve({ code: 0, stdout: outStr, stderr: errStr });
          }
        });
      });

      const floorRes = await wakeFloor({
        dshd: ctx.dshd,
        floorUrl: ctx.floorUrl,
        waiting,
        run: runner,
      });

      if (floorRes.lines?.length > 0) {
        lines.push(...floorRes.lines);
      }
      if (floorRes.fault) {
        floorFaulted = true;
      }
    } catch (err) {
      lines.push(`<3>floor error=${err.message}`);
      floorFaulted = true;
    }

    // -----------------------------------------------------------------------
    // Phase 8: Summary
    // -----------------------------------------------------------------------
    const reason = ctx.env.TRIGGER_UNIT ? 'timer' : 'manual';
    const took_ms = Math.round(performance.now() - passStart);
    lines.push(
      `<6>pass reason=${reason} took_ms=${took_ms} discover_ms=${discover_ms} agencies=${disc.agencies.length} workflows=${disc.files.length}`
    );

    const code = (commitFaulted || floorFaulted) ? 1 : 0;
    return { code, lines };
  } finally {
    await releaseLock();
  }
}
