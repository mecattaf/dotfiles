/**
 * The one process primitive every adapter shares: argv (never a shell string),
 * stdin as bytes, stdout and stderr captured apart, the real exit code, a hard
 * timeout that kills the whole process group, and an abort signal.
 */
import { spawn } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

/**
 * The kernel start time of a pid (field 22 of /proc/<pid>/stat, clock ticks
 * since boot), or undefined when the pid is gone. With the pid it names one
 * process for the life of the boot: a reused pid has a later start.
 */
export function procStartTicks(pid: number): string | undefined {
  try {
    const st = readFileSync(`/proc/${pid}/stat`, "utf8");
    const f = st.slice(st.lastIndexOf(")") + 2).split(" ");
    // A zombie (Z) or dead (X) process has exited: it runs nothing and its
    // orphans must be reaped (successor review r3: a dead, unreaped runner
    // counted as live, so the reapers skipped its jobs).
    if (f[0] === "Z" || f[0] === "X") return undefined;
    return f[19];
  } catch {
    return undefined;
  }
}

/** True when `pid` is alive and is the process that had start time `start`. */
export function sameProcess(pid: number | undefined, start: string | undefined): boolean {
  if (typeof pid !== "number" || start === undefined) return false;
  return procStartTicks(pid) === start;
}

/** The environment variable every child of a recorded job carries, so its grandchildren can be told from strangers. */
export const JOB_MARKER = "AX_CONWIP_JOB";

/**
 * `setpriv --pdeathsig KILL --` in front of every child, when setpriv exists:
 * the child gets SIGKILL when the runner dies, even by SIGKILL (successor
 * review 2026-09-23: kill -9 of conwip-run left the harness running, and the
 * restart ran the same call beside it). The child keeps its own process group
 * for timeout kills. A grandchild is not covered; `liveGroups` and the
 * runner-side proc file cover it.
 */
const SETPRIV = ["/run/current-system/sw/bin/setpriv", "/usr/bin/setpriv", "/bin/setpriv"].find((p) => existsSync(p));
export const PDEATHSIG_WRAPPER: readonly string[] = SETPRIV ? [SETPRIV, "--pdeathsig", "KILL", "--"] : [];

/** Process groups this process has started and not yet reaped. */
export const liveGroups = new Set<number>();

/** Kill every live group (a signal handler's last act). */
export function killLiveGroups(sig: NodeJS.Signals = "SIGKILL"): number {
  let n = 0;
  for (const g of liveGroups) {
    try {
      process.kill(-g, sig);
      n++;
    } catch {
      /* gone */
    }
  }
  return n;
}

/**
 * SIGKILL what is left of a finished job's process group: members whose pgid
 * is the job's and, when the job carries a marker, whose environment has it.
 * A job that exited normally used to leave same-group descendants (a harness's
 * backgrounded tool, a gVisor call's pasta) alive with no record to find them
 * by (successor review r5). Returns how many were killed.
 */
export function killGroupRemnants(pgid: number, jobTag: string | undefined): number {
  let n = 0;
  let pids: string[];
  try {
    pids = readdirSync("/proc").filter((d) => /^\d+$/.test(d));
  } catch {
    return 0;
  }
  for (const d of pids) {
    const pid = Number(d);
    if (pid === process.pid) continue;
    try {
      const st = readFileSync(`/proc/${pid}/stat`, "utf8");
      const f = st.slice(st.lastIndexOf(")") + 2).split(" ");
      if (Number(f[2]) !== pgid) continue;
      if (jobTag !== undefined && !readFileSync(`/proc/${pid}/environ`, "latin1").split("\0").includes(`${JOB_MARKER}=${jobTag}`)) continue;
      process.kill(pid, "SIGKILL");
      n++;
    } catch {
      /* gone, or not ours to read */
    }
  }
  return n;
}

export interface ProcSpec {
  readonly argv: readonly string[];
  readonly stdin?: string;
  readonly cwd?: string;
  /** Full environment for the child. Callers start from `process.env` deliberately, never implicitly. */
  readonly env?: NodeJS.ProcessEnv;
  readonly timeoutMs?: number;
  readonly signal?: AbortSignal;
  /** Output cap per stream; the rest is dropped and marked. Default 16 MiB. */
  readonly maxBytes?: number;
  /**
   * Runner-side file to record {pid, pgid, start, runnerPid, runnerStart, job}
   * in once spawned. Removed when the child has exited (a finished job is
   * never an orphan). The child's environment gains AX_CONWIP_JOB=<job>.
   */
  readonly procFile?: string;
  /** Skip the pdeathsig wrapper (a child that must outlive the runner). */
  readonly noDeathSignal?: boolean;
  /**
   * After the child exits, how long to wait for its stdout and stderr to close
   * before giving up on them (a detached helper may hold the pipes). Default 2000.
   */
  readonly drainGraceMs?: number;
  /**
   * Buildkite's cancel-signal / cancel-grace-period (G-BK1): on abort the whole
   * group first gets `cancelSignal` (default SIGTERM), so an agent can save its
   * session, transcript or partial result; whatever is left after
   * `cancelGraceMs` (default DEFAULT_CANCEL_GRACE_MS) gets SIGKILL. 0 kills at once.
   * A timeout still kills at once: its budget is already spent.
   */
  readonly cancelSignal?: NodeJS.Signals;
  readonly cancelGraceMs?: number;
}

export interface ProcResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
  readonly durationMs: number;
  readonly timedOut: boolean;
  /** True when the abort signal ended the process (the cancel path, graceful or not). */
  readonly aborted?: boolean;
  /** True when the grace ran out and the group got SIGKILL after the cancel signal. */
  readonly killedAfterGrace?: boolean;
}

/** Default cancel grace (G-BK1): Buildkite's cancel-grace-period is 10 s. */
export const DEFAULT_CANCEL_GRACE_MS = 10_000;

/** Exit code reported when the process could not be started at all (ENOENT, EACCES). */
export const SPAWN_FAILED = 127;
/** Exit code reported when the signal was already aborted: nothing was spawned (SIGKILL's 137, as an abort kill reports). */
export const ABORTED_BEFORE_SPAWN = 137;
/** Exit code reported for a timeout, matching coreutils `timeout`. */
export const TIMED_OUT = 124;

export function runProc(spec: ProcSpec): Promise<ProcResult> {
  const t0 = performance.now();
  const max = spec.maxBytes ?? 16 * 1024 * 1024;
  if (spec.argv[0] === undefined) return Promise.reject(new Error("runProc: empty argv"));
  // An already-aborted signal never fires 'abort' again: never spawn under one
  // (successor review r3: a queued call was spawned after the run aborted).
  if (spec.signal?.aborted) {
    return Promise.resolve({ exitCode: ABORTED_BEFORE_SPAWN, stdout: "", stderr: "[runner: aborted before spawn; nothing ran]", durationMs: 0, timedOut: false });
  }
  const [cmd, ...args] = [...(spec.noDeathSignal ? [] : PDEATHSIG_WRAPPER), ...spec.argv] as [string, ...string[]];
  return new Promise((resolve) => {
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    let outN = 0;
    let errN = 0;
    let timedOut = false;
    let settled = false;
    const jobTag = spec.procFile ? basename(spec.procFile).replace(/\.proc\.json$/, "") : undefined;
    const env = { ...(spec.env ?? process.env), ...(jobTag ? { [JOB_MARKER]: jobTag } : {}) };
    const child = spawn(cmd, args, {
      cwd: spec.cwd,
      env,
      stdio: ["pipe", "pipe", "pipe"],
      detached: true,
    });
    if (child.pid !== undefined) {
      liveGroups.add(child.pid);
      if (spec.procFile) {
        try {
          writeFileSync(
            spec.procFile,
            JSON.stringify({
              pid: child.pid,
              pgid: child.pid,
              start: procStartTicks(child.pid),
              job: jobTag,
              runnerPid: process.pid,
              runnerStart: procStartTicks(process.pid),
              startedAt: new Date().toISOString(),
            }) + "\n",
          );
        } catch {
          /* best effort: the reaper then has nothing to find */
        }
      }
    }
    const signalGroup = (sig: NodeJS.Signals) => {
      try {
        if (child.pid !== undefined) process.kill(-child.pid, sig);
      } catch {
        try { child.kill(sig); } catch { /* gone */ }
      }
    };
    const killGroup = () => signalGroup("SIGKILL");
    let aborted = false;
    let killedAfterGrace = false;
    let graceTimer: NodeJS.Timeout | undefined;
    let exited: number | undefined;
    let drain: NodeJS.Timeout | undefined;
    const giveUpOnPipes = () => {
      child.stdout.destroy();
      child.stderr.destroy();
    };
    const timer =
      spec.timeoutMs !== undefined
        ? setTimeout(() => {
            // A harness that already exited in time keeps its exit code; only
            // its pipes (held by a detached helper) are abandoned.
            if (exited !== undefined) {
              giveUpOnPipes();
              finish(exited, "\n[runner: stdout/stderr still held open after exit; abandoned at the timeout]");
              return;
            }
            timedOut = true;
            killGroup();
            // The pipes may be held by a helper outside the group: settle anyway.
            setTimeout(() => {
              giveUpOnPipes();
              finish(137, "\n[runner: pipes still held after the timeout kill; abandoned]");
            }, spec.drainGraceMs ?? 2000).unref();
          }, spec.timeoutMs)
        : undefined;
    const onAbort = () => {
      aborted = true;
      if (exited !== undefined) return;
      const grace = spec.cancelGraceMs ?? DEFAULT_CANCEL_GRACE_MS;
      if (grace <= 0) return killGroup();
      signalGroup(spec.cancelSignal ?? "SIGTERM");
      graceTimer = setTimeout(() => {
        // The leader may have exited while a descendant ignores the signal: the group still goes.
        killedAfterGrace = true;
        killGroup();
      }, grace);
      graceTimer.unref();
    };
    spec.signal?.addEventListener("abort", onAbort, { once: true });
    child.stdout.on("data", (b: Buffer) => {
      if (outN < max) out.push(b.subarray(0, max - outN));
      outN += b.length;
    });
    child.stderr.on("data", (b: Buffer) => {
      if (errN < max) err.push(b.subarray(0, max - errN));
      errN += b.length;
    });
    const finish = (exitCode: number, extraErr = "") => {
      if (settled) return;
      settled = true;
      if (child.pid !== undefined) liveGroups.delete(child.pid);
      if (timer) clearTimeout(timer);
      if (drain) clearTimeout(drain);
      if (graceTimer) clearTimeout(graceTimer);
      // The leader is gone; the rest of its group goes with it, before the
      // record that would let a reaper find them is removed.
      if (child.pid !== undefined && !timedOut) {
        const left = killGroupRemnants(child.pid, jobTag);
        if (left) extraErr += `\n[runner: killed ${left} process(es) left in the job's group after it exited]`;
      }
      // The child is reaped: its record must never send a later reaper after a reused pid.
      if (spec.procFile) rmSync(spec.procFile, { force: true });
      spec.signal?.removeEventListener("abort", onAbort);
      let stdout = Buffer.concat(out).toString("utf8");
      let stderr = Buffer.concat(err).toString("utf8") + extraErr;
      if (outN > max) stdout += `\n[runner: stdout truncated at ${max} of ${outN} bytes]`;
      if (errN > max) stderr += `\n[runner: stderr truncated at ${max} of ${errN} bytes]`;
      resolve({
        exitCode: timedOut ? TIMED_OUT : exitCode,
        stdout,
        stderr,
        durationMs: Math.round(performance.now() - t0),
        timedOut,
        ...(aborted ? { aborted: true } : {}),
        ...(killedAfterGrace ? { killedAfterGrace: true } : {}),
      });
    };
    child.on("error", (e) => finish(SPAWN_FAILED, `[runner: spawn failed: ${e.message}]`));
    const codeOf = (code: number | null, sig: NodeJS.Signals | null) => code ?? (sig ? 128 + signalNumber(sig) : 1);
    // 'close' waits for every holder of the pipes; 'exit' does not. Settle on
    // exit plus a short drain, so a detached helper holding stdout cannot hold
    // the call (and its WIP slot) past the harness (successor review r2).
    child.on("exit", (code, sig) => {
      exited = codeOf(code, sig);
      drain = setTimeout(() => {
        giveUpOnPipes();
        finish(exited!, "\n[runner: stdout/stderr still held open by a descendant after exit; abandoned]");
      }, spec.drainGraceMs ?? 2000);
      drain.unref();
    });
    child.on("close", (code, sig) => finish(codeOf(code, sig)));
    child.stdin.on("error", () => {
      /* a child that exits without reading stdin is not an error */
    });
    child.stdin.end(spec.stdin ?? "");
  });
}

function signalNumber(sig: NodeJS.Signals): number {
  const table: Partial<Record<NodeJS.Signals, number>> = { SIGHUP: 1, SIGINT: 2, SIGKILL: 9, SIGTERM: 15 };
  return table[sig] ?? 0;
}

/** Quote one argv element for a POSIX shell (ssh sends a string, not argv). */
export function shq(s: string): string {
  if (s !== "" && /^[A-Za-z0-9_@%+=:,./-]+$/.test(s)) return s;
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

/** The pgid and start time of a pid, from /proc (undefined when gone). */
function statOf(pid: number): { pgid: string; start: string } | undefined {
  try {
    const st = readFileSync(`/proc/${pid}/stat`, "utf8");
    const f = st.slice(st.lastIndexOf(")") + 2).split(" ");
    if (f[0] === "Z" || f[0] === "X") return undefined;
    return { pgid: f[2]!, start: f[19]! };
  } catch {
    return undefined;
  }
}

function carriesMarker(pid: number, job: string): boolean {
  try {
    // Matched as bytes, never logged or kept: the only thing looked for is the marker.
    const env = Buffer.concat([Buffer.from([0]), readFileSync(`/proc/${pid}/environ`)]);
    return env.includes(Buffer.from(`\0${JOB_MARKER}=${job}\0`));
  } catch {
    return false;
  }
}

/**
 * Kill what a dead earlier start of a run left running (successor review r2).
 * A recorded group counts only when its recorded runner (pid AND start time)
 * is gone. Inside it, a process is killed only when it is provably the job's:
 * the recorded leader with its recorded start time, or a member of the
 * recorded pgid started no earlier than the leader that carries the job's
 * AX_CONWIP_JOB marker (a grandchild whose leader has exited). A pid reused by
 * a stranger has another start time and no marker: it is left alone, and the
 * refusal is logged. The record is removed once judged.
 */
export function reapProcFiles(jobsRoot: string, self = process.pid): string[] {
  if (!existsSync(jobsRoot)) return [];
  const lines: string[] = [];
  let all: number[] | undefined;
  for (const f of readdirSync(jobsRoot)) {
    if (!f.endsWith(".proc.json")) continue;
    const path = join(jobsRoot, f);
    let rec: { pid?: number; pgid?: number; start?: string; job?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(path, "utf8")) as typeof rec;
    } catch {
      continue;
    }
    const { pid, pgid, start, job, runnerPid, runnerStart } = rec;
    const id = f.replace(/\.proc\.json$/, "");
    if (runnerPid === self) continue;
    if (typeof runnerPid === "number" && (runnerStart === undefined ? procStartTicks(runnerPid) !== undefined : sameProcess(runnerPid, runnerStart))) continue;
    if (typeof pid !== "number" || typeof pgid !== "number" || start === undefined) {
      lines.push(`${id}: record has no start time; refused to kill anything`);
      rmSync(path, { force: true });
      continue;
    }
    all ??= readdirSync("/proc").filter((d) => /^\d+$/.test(d)).map(Number);
    const victims: number[] = [];
    let strangers = 0;
    for (const p of all) {
      const st = statOf(p);
      if (!st || st.pgid !== String(pgid)) continue;
      const ours = (p === pid && st.start === start) || (Number(st.start) >= Number(start) && job !== undefined && carriesMarker(p, job));
      if (ours) victims.push(p);
      else strangers++;
    }
    for (const p of victims) {
      try {
        process.kill(p, "SIGKILL");
      } catch {
        /* raced to exit */
      }
    }
    if (victims.length) lines.push(`${id}: group ${pgid}, killed ${victims.length} process(es)`);
    if (strangers) lines.push(`${id}: ${strangers} process(es) in group ${pgid} are not provably this job's (pid reused?); left alone`);
    rmSync(path, { force: true });
  }
  return lines;
}
