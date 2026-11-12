// tick.mjs — the heartbeat tick, scheduled-jsonc §4 (phases 0-10).
//
// A nudger only: it decodes the cron times of every agency's .agency/scheduled/*.jsonc, links one
// occurrence record per due item into the superagent's inbox, withdraws its own records of items no longer
// enabled, and starts the floor instance when records wait. It holds no superagent logic: it opens no
// orchestrator database, calls no floor API, runs no `dshd run` and runs no item command.

import { join, dirname, sep } from 'node:path';
import { statSync } from 'node:fs';
import { readFile, open, unlink, mkdir, link } from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
import { discover } from './discover.mjs';
import { validateFile } from './validate.mjs';
import { instantsBetween } from './cron.mjs';
import { dshdRunner, floorState, wake, LIVE } from './floor.mjs';
import { writeAtomic } from './atomic.mjs';
import { HEARTBEAT, handOff, makeRecord, readRecord, recordProblem, waiting, withdraw } from './inbox.mjs';

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

/** One intake entry: the cached parse of one item file, keyed by path in intake.json. */
function entryOf(f, st, v, prev, { now, lastTick }) {
  const valid = Boolean(v.value);
  const enabled = valid && v.value.enabled === true;
  let armedSince = null;
  if (valid && enabled) {
    if (prev?.valid && prev.enabled && prev.armedSince) armedSince = prev.armedSince;
    // Fixed after being invalid: anchored to lastTick, so the latest missed instant is still due.
    else if (prev && !prev.valid) armedSince = lastTick.toISOString();
    // New, or enabled now: instants before this tick never fire (T10).
    else armedSince = now.toISOString();
  }
  return {
    id: f.id,
    dev: String(st.dev),
    ino: String(st.ino),
    size: Number(st.size),
    mtimeNs: String(st.mtimeNs),
    revision: v.revision ?? null,
    problems: v.problems || [],
    firstSeen: prev?.firstSeen || now.toISOString(),
    armedSince,
    valid,
    enabled,
    promptFile: Boolean(v.value?.job?.['prompt-file']),
    name: v.value?.name ?? null,
    pair: v.value?.pair ?? null,
    on: v.value?.on ?? {},
    text: v.prompt ?? null,
  };
}

const sameStat = (prev, st) => prev && prev.dev === String(st.dev) && prev.ino === String(st.ino)
  && prev.size === Number(st.size) && prev.mtimeNs === String(st.mtimeNs);

/**
 * Execute one tick pass.
 *
 * @param {object} ctx Context from makeContext()
 * @param {object} [opts]
 * @param {Date|string} [opts.now] Clock override
 * @param {string} [opts.stateDir] Heartbeat state (heartbeat.json, intake.json, .tick.lock)
 * @param {string} [opts.inbox] The superagent's inbox (required)
 * @param {string|null} [opts.floorInstance] The floor's dshd instance; null: never call dshd
 * @param {string} [opts.home] Agency discovery root, agency id `master`
 * @param {string[]|null} [opts.pairs] The floor's pair names (ctx.pairs, from SCHEDULED_PAIRS)
 * @param {(argv: string[]) => Promise<{code: number, stdout: string, stderr: string}>} [opts.run] dshd runner
 * @returns {Promise<{code: number, lines: string[]}>}
 */
export async function tick(ctx, { now: nowOpt, stateDir: stateDirOpt, inbox: inboxOpt, floorInstance: floorOpt, home: homeOpt, pairs: pairsOpt, run: runOpt } = {}) {
  const passStart = performance.now();
  const stateDir = stateDirOpt || ctx.stateDir;
  const inbox = inboxOpt || ctx.inbox;
  const floorInstance = floorOpt === undefined ? (ctx.floorInstance ?? null) : floorOpt;
  const home = homeOpt || ctx.home;
  const pairs = pairsOpt === undefined ? (ctx.pairs ?? null) : pairsOpt;
  // The pair names a cached parse was checked against; a parse checked against other names is not reused.
  const pairsKey = pairs?.length ? [...new Set(pairs)].sort().join(' ') : null;
  if (!inbox) throw new Error('--inbox is required');

  const now = nowOpt
    ? (nowOpt instanceof Date ? nowOpt : new Date(nowOpt))
    : (typeof ctx.now === 'function' ? ctx.now() : new Date());
  if (Number.isNaN(now.getTime())) throw new Error(`Invalid now timestamp: ${nowOpt}`);

  const lines = [];
  const run = runOpt || dshdRunner(ctx.dshd, { ...process.env, ...(ctx.env || {}) });

  // Phase 0: lock.
  await mkdir(stateDir, { recursive: true, mode: 0o700 });
  const releaseLock = await acquireLock(join(stateDir, '.tick.lock'));

  try {
    // Phase 1: guard. State from another machine or a newer major version is never overwritten.
    let hostMachineId;
    try {
      hostMachineId = (await readFile(ctx.machineIdFile, 'utf8')).trim();
    } catch {
      hostMachineId = 'unknown';
    }
    const heartbeatPath = join(stateDir, 'heartbeat.json');
    const intakePath = join(stateDir, 'intake.json');
    const readState = async (p) => {
      try {
        return JSON.parse(await readFile(p, 'utf8'));
      } catch (err) {
        if (err.code === 'ENOENT') return null;
        throw Object.assign(err, { statePath: p });
      }
    };
    let heartbeat, intake;
    try {
      heartbeat = await readState(heartbeatPath);
      intake = await readState(intakePath);
    } catch (err) {
      lines.push(`<3>guard error reading ${err.statePath.split(sep).pop()}: ${err.message}`);
      return { code: 1, lines };
    }
    for (const state of [heartbeat, intake]) {
      if (state && typeof state.v === 'number' && Math.floor(state.v) > 1) {
        lines.push(`<3>guard higher state version: v=${state.v}`);
        return { code: 1, lines };
      }
    }
    if (heartbeat?.machineId && hostMachineId && heartbeat.machineId !== hostMachineId) {
      lines.push('<3>guard machine-id differs: state from another host');
      return { code: 1, lines };
    }

    const isFirstTick = heartbeat === null;
    const lastTick = isFirstTick ? now : new Date(heartbeat.lastTick);

    // Phase 2: intake. Unchanged files reuse their cached parse; a file written within 2 s keeps its last one.
    const discStart = performance.now();
    const disc = await discover({ home, uid: ctx.uid });
    const discover_ms = Math.round(performance.now() - discStart);

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
    const samePairs = (intake?.pairs ?? null) === pairsKey;
    const currentFiles = {};
    const items = [];

    for (const f of disc.files) {
      const prev = prevFiles[f.path];
      let st;
      try {
        st = statSync(f.path, { bigint: true });
      } catch (err) {
        // Gone since discovery: removed. Any other error (EACCES, EIO, a busy mount) is not a removal: the
        // previous parse is carried, or its waiting record would be withdrawn (Zen second opinion #2).
        if (err?.code !== 'ENOENT' && prev) {
          const problems = [{ severity: 'warning', code: 'stat', line: 0, col: 0, message: `stat failed (${err?.code ?? 'error'}); previous parse used` },
            ...(prev.problems || []).filter((p) => p.code !== 'stat')];
          currentFiles[f.path] = { ...prev, problems, id: f.id };
          items.push({ ...prev, file: f, problems });
        }
        continue;
      }

      // Young means written within 2 s of now, either side. A mtime further in the future was set under a clock
      // that has since gone back: the file is not being written now, so it is read (found by the VM check).
      const age = now.getTime() - Number(st.mtimeMs);
      if (age > -2000 && age < 2000) {
        const young = { severity: 'warning', code: 'young', line: 0, col: 0, message: 'File is younger than 2s; previous parse used' };
        if (prev) {
          const problems = [young, ...(prev.problems || []).filter((p) => p.code !== 'young')];
          currentFiles[f.path] = { ...prev, problems, id: f.id };
          items.push({ ...prev, file: f, problems });
        } else {
          // No stat is cached for a file never parsed, so the next pass parses it (evaluation review, C3.4).
          const placeholder = { id: f.id, dev: null, ino: null, size: null, mtimeNs: null, revision: null, problems: [young],
            firstSeen: now.toISOString(), armedSince: null, valid: false, enabled: false, placeholder: true };
          currentFiles[f.path] = placeholder;
          items.push({ ...placeholder, file: f });
        }
        continue;
      }

      // A prompt-file is read at each tick: an item that names one is never served from the cache. Nor is any
      // item when the floor's pairs changed: an item's `pair` is valid only while it is one of them.
      if (samePairs && sameStat(prev, st) && !prev.promptFile && !prev.placeholder) {
        // The cached parse, without the warnings of a pass that could not read the file.
        const problems = (prev.problems || []).filter((p) => p.code !== 'stat' && p.code !== 'young');
        currentFiles[f.path] = { ...prev, problems, id: f.id };
        items.push({ ...prev, problems, file: f });
        continue;
      }

      const v = await validateFile(f.path, { uid: ctx.uid, pairs });
      const entry = entryOf(f, st, v, prev, { now, lastTick });
      // Once per revision, and once more when a valid parse turns invalid unchanged (the floor's pairs changed).
      if (!entry.valid && entry.revision && (entry.revision !== prev?.revision || prev?.valid)) {
        const first = entry.problems.find((p) => p.severity === 'error') || { line: 0, col: 0 };
        lines.push(`<4>invalid item=${f.id} rev=${entry.revision} at=${first.line}:${first.col}`);
      }
      currentFiles[f.path] = entry;
      items.push({ ...entry, file: f });
    }

    // Phase 4: decode. Per valid, enabled item: one record for the latest instant in (max(lastTick, armedSince), now].
    const clockWentBack = now.getTime() < lastTick.getTime();
    const due = [];
    if (clockWentBack) {
      lines.push('<4>clock went back');
    } else if (!isFirstTick) {
      for (const it of items) {
        if (!it.valid || !it.enabled || !(it.on?.schedule?.length > 0) || !it.text) continue;
        const anchor = new Date(Math.max(lastTick.getTime(), it.armedSince ? new Date(it.armedSince).getTime() : 0));
        const instants = instantsBetween(it.on.schedule, anchor, now);
        if (instants.length === 0) continue;
        due.push({ it, instant: instants[instants.length - 1], missed: instants.length - 1 });
      }
    }

    // Phase 5: hand off.
    let handOffFaulted = false;
    for (const { it, instant, missed } of due) {
      const record = makeRecord({
        kind: 'schedule', namespace: it.file.agency, item: it.file.stem, name: it.name ?? undefined,
        cwd: it.file.root, file: it.file.path, due: instant, missed, revision: it.revision, text: it.text,
        pair: it.pair ?? undefined, by: HEARTBEAT, at: now,
      });
      const problem = recordProblem(record);
      if (problem) {
        lines.push(`<3>decode item=${it.id} due=${instant.toISOString()} result=refused reason=${JSON.stringify(problem)}`);
        handOffFaulted = true;
        continue;
      }
      try {
        const { result } = await handOff(inbox, record);
        lines.push(`<6>decode item=${it.id} due=${instant.toISOString()} result=${result}`);
      } catch (err) {
        lines.push(`<3>decode item=${it.id} due=${instant.toISOString()} error=${JSON.stringify(err.message)}`);
        handOffFaulted = true;
      }
    }

    // Phase 6: floor state, read once and only when a record waits.
    let floor = null;
    if (floorInstance && waiting(inbox).length > 0) floor = await floorState(floorInstance, run);

    // Phase 7: withdraw this heartbeat's records of items no longer valid and enabled, unless the Source reads now.
    if (!(floor && LIVE.has(floor.state))) {
      const known = new Map();
      for (const it of items) known.set(`${it.file.root}\0${it.file.stem}`, it);
      const under = (p) => p === home || p.startsWith(home.endsWith(sep) ? home : home + sep);
      for (const name of waiting(inbox)) {
        const rec = readRecord(inbox, name);
        if (!rec || rec.by !== HEARTBEAT || rec.kind !== 'schedule' || typeof rec.cwd !== 'string' || !under(rec.cwd)) continue;
        const it = known.get(`${rec.cwd}\0${rec.item}`);
        if (it?.placeholder || (it?.valid && it.enabled)) continue;
        const reason = !it ? 'removed' : it.valid ? 'disabled' : 'invalid';
        if (withdraw(inbox, name)) lines.push(`<5>withdrawn occurrence=${name.slice(0, -'.json'.length)} reason=${reason}`);
      }
    }

    // Phase 8: commit. A clock that went back keeps lastTick and the cache as they were.
    let commitFaulted = false;
    if (!clockWentBack) {
      try {
        await writeAtomic(heartbeatPath, JSON.stringify({ v: 1, machineId: hostMachineId, lastTick: now.toISOString() }, null, 2) + '\n');
        await writeAtomic(intakePath, JSON.stringify({ v: 1, pairs: pairsKey, files: currentFiles, agencies: currentAgencies }, null, 2) + '\n');
      } catch (err) {
        lines.push(`<3>guard error committing state: ${err.message}`);
        commitFaulted = true;
      }
    }

    // Phase 9: wake.
    const waitingCount = waiting(inbox).length;
    let floorFaulted = false;
    try {
      const res = await wake({ instance: floorInstance, waiting: waitingCount, floor, run });
      lines.push(...res.lines);
      floorFaulted = res.fault;
    } catch (err) {
      lines.push(`<3>floor error=${JSON.stringify(err.message)}`);
      floorFaulted = true;
    }

    // Phase 10: summary.
    const reason = ctx.env?.TRIGGER_UNIT ? 'timer' : 'manual';
    const took_ms = Math.round(performance.now() - passStart);
    lines.push(`<6>pass reason=${reason} took_ms=${took_ms} discover_ms=${discover_ms} agencies=${disc.agencies.length} items=${disc.files.length} waiting=${waitingCount}`);

    return { code: (handOffFaulted || commitFaulted || floorFaulted) ? 1 : 0, lines };
  } finally {
    await releaseLock();
  }
}
