/**
 * `ssh:<host>`: the job runs on another fleet machine over ssh, under that
 * machine's own seat configuration. Nothing is copied to the remote: argv is
 * shell-quoted element by element (ssh carries a string, not argv), stdin is the
 * prompt, and the remote working directory is the remote `$HOME` unless the job
 * names one that exists there.
 *
 * Credential mounts are refused, not ignored: a remote host holds its own seat,
 * and a runner that silently dropped a mount would make a job believe it had a
 * credential it does not have.
 */
import { refuseCommon, refusal, type Job, type Runner, type RunResult } from "./job.ts";
import { existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { procStartTicks, runProc, sameProcess, shq } from "./proc.ts";
import { DEFAULT_TIMEOUT_MS } from "./host.ts";

export interface SshOptions {
  readonly host: string;
  readonly timeoutMs?: number;
  /** ssh binary; tests pass a fake. */
  readonly ssh?: string;
  /** Remote working directory. Default: the remote login directory. */
  readonly remoteCwd?: string;
}

/**
 * Where the remote records a job's process group, relative to the remote $HOME.
 * A timeout or abort kills the local ssh client only; sshd sends a `-T` session
 * no SIGHUP, so the remote job kept running and a retry ran a second copy
 * (successor review 2026-09-23). The remote job now runs in its own session
 * (setsid) and writes its pgid here; the runner kills that group over a second
 * ssh on timeout or abort.
 */
export const REMOTE_PID_DIR = ".local/state/substrate/jobs";
const remotePidFile = (id: string) => `${REMOTE_PID_DIR}/${id.replace(/[^A-Za-z0-9_.-]/g, "_")}.pid`;

const SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-T"];

/** The exact argv this runner executes for a job, exported for tests and dry runs. */
export function sshArgv(o: SshOptions, job: { readonly id?: string; readonly argv: readonly string[]; readonly env?: Readonly<Record<string, string>> }): string[] {
  const env = Object.entries(job.env ?? {}).map(([k, v]) => `${k}=${shq(v)}`);
  const cd = o.remoteCwd ? [`cd ${shq(o.remoteCwd)} &&`] : [];
  const cmd = [...(env.length ? ["env", ...env] : []), ...job.argv.map(shq)];
  const remote =
    job.id === undefined
      ? [...cd, ...cmd].join(" ")
      : `mkdir -p ${REMOTE_PID_DIR} && exec setsid -w sh -c ${shq(`echo $$ > ${remotePidFile(job.id)}; ${[...cd, ...cmd].join(" ")}; rc=$?; rm -f ${remotePidFile(job.id)}; exit $rc`)}`;
  return [o.ssh ?? "ssh", ...SSH_OPTS, o.host, "--", remote];
}

/** The argv that kills a job's remote process group and forgets its pid file. */
export function sshKillArgv(o: SshOptions, id: string): string[] {
  const f = remotePidFile(id);
  return [o.ssh ?? "ssh", ...SSH_OPTS, o.host, "--", `test -s ${f} && kill -KILL -- -"$(cat ${f})"; rm -f ${f}`];
}

export function sshRunner(name: string, o: SshOptions): Runner {
  const refuses = (job: Job): string | undefined => {
    const c = refuseCommon(job);
    if (c) return c;
    if (job.kind !== "process") return `${name} runs process jobs only`;
    for (const k of Object.keys(job.env ?? {})) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) return `env key ${JSON.stringify(k)} is not a shell identifier`;
    }
    if ((job.mounts ?? []).length) {
      return `${name} cannot mount host paths on ${o.host}; the remote uses its own seat configuration`;
    }
    return undefined;
  };
  return {
    name,
    type: "ssh",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why || job.kind !== "process") return refusal(name, job, why ?? "unreachable");
      // An earlier attempt of the same call whose remote kill failed may still
      // be running there: kill it first, and refuse while it cannot be proved
      // dead (successor review r3: the retry ran a second copy beside it).
      const stale = job.procFile ? await killEarlierAttempts(o, job) : undefined;
      if (stale) return refusal(name, job, stale);
      const argv = sshArgv(o, job);
      // A runner-side record of the remote job, removed once this runner has
      // judged its outcome: kill -9 of the runner kills only the local ssh
      // client (pdeathsig), so a later start reads the record and kills the
      // remote group before dispatching anything (successor review r2).
      const record = job.procFile ? sshRecordFile(job.procFile) : undefined;
      if (record) {
        writeFileSync(record, JSON.stringify({ host: o.host, ssh: o.ssh ?? "ssh", id: job.id, runnerPid: process.pid, runnerStart: procStartTicks(process.pid) }) + "\n");
      }
      let r: Awaited<ReturnType<typeof runProc>>;
      try {
        r = await runProc({
          argv,
          stdin: job.stdin,
          timeoutMs: job.timeoutMs ?? o.timeoutMs ?? DEFAULT_TIMEOUT_MS,
          signal,
          ...(job.cancelGraceMs !== undefined ? { cancelGraceMs: job.cancelGraceMs } : {}),
        });
      } catch (e) {
        if (record) rmSync(record, { force: true });
        throw e;
      }
      // 255 is ssh's own failure (unreachable, auth), not the job's.
      let remoteKill: string | undefined;
      let killFailed = false;
      if (r.timedOut || signal?.aborted || r.exitCode === 255) {
        // The local client is gone; the remote job may not be. Kill its group.
        const k = await runProc({ argv: sshKillArgv(o, job.id), timeoutMs: 20_000 });
        killFailed = k.exitCode !== 0;
        remoteKill = !killFailed ? "remote group killed" : `remote kill rc ${k.exitCode}: ${k.stderr.slice(-200)}`;
      }
      // The record goes only when the remote job is proved over: it finished
      // with its own exit code, or its kill succeeded. A failed kill keeps it,
      // marked, for the next attempt or the restart reaper.
      if (record) {
        if (killFailed) writeFileSync(record, JSON.stringify({ ...JSON.parse(readFileSync(record, "utf8")), killFailed: remoteKill }) + "\n");
        else rmSync(record, { force: true });
      }
      const detail = {
        host: o.host,
        ...(r.exitCode === 255 ? { transport: "ssh exit 255: connection or auth failure; outcome unknown" } : {}),
        ...(remoteKill ? { remoteKill } : {}),
        ...(killFailed ? { remoteMayStillRun: "yes: the record is kept for the next attempt and the restart reaper" } : {}),
      };
      return { runtime: name, jobId: job.id, ...r, detail };
    },
  };
}

/**
 * Before attempt N of a call, kill any earlier attempt of the SAME call (same
 * job id up to `-a<n>`) still on record beside it. Returns a refusal reason
 * when one cannot be proved dead; undefined when the way is clear. A record
 * held by another live runner is left alone.
 */
async function killEarlierAttempts(o: SshOptions, job: { id: string; procFile?: string }): Promise<string | undefined> {
  const dir = dirname(job.procFile!);
  if (!existsSync(dir)) return undefined;
  const callOf = (id: string) => id.replace(/-a\d+$/, "");
  const mine = callOf(job.id);
  for (const f of readdirSync(dir)) {
    if (!f.endsWith(".ssh.json")) continue;
    const id = f.slice(0, -".ssh.json".length);
    if (id === job.id || callOf(id) !== mine) continue;
    const path = join(dir, f);
    let rec: { host?: string; ssh?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(path, "utf8")) as typeof rec;
    } catch {
      continue;
    }
    if (rec.runnerPid !== process.pid && sameProcess(rec.runnerPid, rec.runnerStart)) continue;
    const host = rec.host ?? o.host;
    const k = await runProc({ argv: sshKillArgv({ host, ...(rec.ssh ? { ssh: rec.ssh } : o.ssh ? { ssh: o.ssh } : {}) }, id), timeoutMs: 20_000 });
    if (k.exitCode !== 0) return `earlier attempt ${id} may still be running on ${host} (remote kill rc ${k.exitCode}); refusing to start another copy`;
    rmSync(path, { force: true });
  }
  return undefined;
}

/** The runner-side record of a remote job, beside its local proc file. */
export const sshRecordFile = (procFile: string) => procFile.replace(/\.proc\.json$/, "") + ".ssh.json";

/**
 * Kill the remote groups of ssh jobs whose runner died (kill -9): each record
 * whose runner (pid and start time) is gone gets `sshKillArgv` on its host,
 * and is removed. Run before a restart dispatches anything.
 */
export async function reapSshRecords(jobsRoot: string, self = process.pid): Promise<string[]> {
  if (!existsSync(jobsRoot)) return [];
  const lines: string[] = [];
  for (const f of readdirSync(jobsRoot)) {
    if (!f.endsWith(".ssh.json")) continue;
    const path = join(jobsRoot, f);
    let rec: { host?: string; ssh?: string; id?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(path, "utf8")) as typeof rec;
    } catch {
      continue;
    }
    if (rec.runnerPid === self || sameProcess(rec.runnerPid, rec.runnerStart)) continue;
    if (typeof rec.host !== "string" || typeof rec.id !== "string") {
      rmSync(path, { force: true });
      continue;
    }
    const k = await runProc({ argv: sshKillArgv({ host: rec.host, ...(rec.ssh ? { ssh: rec.ssh } : {}) }, rec.id), timeoutMs: 20_000 });
    lines.push(`${rec.id}: ssh ${rec.host} remote group ${k.exitCode === 0 ? "killed" : `kill rc ${k.exitCode}`}`);
    if (k.exitCode === 0) rmSync(path, { force: true });
  }
  return lines;
}

/**
 * The ssh records a dead runner left that the reaper could not kill (the host
 * was unreachable): the remote copy may still run (successor review r4). A
 * restart must not dispatch while any is listed. Each entry names the job id
 * and host.
 */
export function unreapedSshRecords(jobsRoot: string, self = process.pid): { id: string; host: string }[] {
  if (!existsSync(jobsRoot)) return [];
  const out: { id: string; host: string }[] = [];
  for (const f of readdirSync(jobsRoot)) {
    if (!f.endsWith(".ssh.json")) continue;
    let rec: { host?: string; id?: string; runnerPid?: number; runnerStart?: string };
    try {
      rec = JSON.parse(readFileSync(join(jobsRoot, f), "utf8")) as typeof rec;
    } catch {
      continue;
    }
    if (rec.runnerPid === self || sameProcess(rec.runnerPid, rec.runnerStart)) continue;
    if (typeof rec.host !== "string" || typeof rec.id !== "string") continue;
    out.push({ id: rec.id, host: rec.host });
  }
  return out;
}
