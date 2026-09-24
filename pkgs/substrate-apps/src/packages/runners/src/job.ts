/**
 * The Runner seam.
 *
 * A runner is the one place a job actually executes. The interpreter owns the
 * script, the journal and the retries; CONWIP owns admission; a runner owns one
 * attempt at one job in one runtime, and reports what happened. It never
 * decides whether the job should run, and it never throws for an ordinary
 * failure: a non-zero exit is a result, a refusal is a result.
 *
 * Two job shapes exist, and every runtime says which it accepts:
 *
 * - a `process` job is argv plus stdin in a working directory. Every agent()
 *   call becomes one: a harness CLI (claude, pi) needs a process, a shell, a
 *   filesystem and a credential.
 * - a `worker` job is an ES module with a `test(ctrl, env)` export plus text
 *   bindings. Only workerd runs it, and workerd runs nothing else: an isolate
 *   has no process, no shell and no CLI, so an agent() call cannot land there.
 *
 * Credentials are mounts, never content. A job names a host path and where it
 * appears inside the runtime; no runner copies, reads or bakes the bytes into a
 * bundle, a closure or an image.
 */

/** A host path made visible inside the runtime. */
export interface Mount {
  /** Absolute host path. */
  readonly source: string;
  /** Absolute path inside the runtime. Equal to `source` on runtimes that share the host filesystem. */
  readonly target: string;
  /** `rw` is the default for the seat config mount (Tom, 2026-09-21); everything else should be `ro`. */
  readonly mode: "ro" | "rw";
  /** Why this mount exists, for receipts. `credential` mounts are never copied. */
  readonly purpose?: "credential" | "workdir" | "store" | "other";
}

export interface ProcessJob {
  readonly kind: "process";
  /** Stable id, used for state dirs and container names. [A-Za-z0-9_.-] only. */
  readonly id: string;
  readonly argv: readonly string[];
  readonly stdin?: string;
  /** Host job directory: the runtime's working directory and where result files land. */
  readonly jobDir: string;
  /** Working directory when it is not the job dir (a git worktree for isolation:'worktree'). Host runtime only. */
  readonly cwd?: string;
  /** Non-secret environment only. A secret goes in a mount. */
  readonly env?: Readonly<Record<string, string>>;
  readonly mounts?: readonly Mount[];
  readonly timeoutMs?: number;
  /** True when the job is an agent() call; a runtime that cannot host a harness refuses it. */
  readonly agent?: boolean;
  /**
   * Runner-side file (OUTSIDE the job dir) where a runner that spawns a local
   * process group records {pid, pgid, runnerPid, startedAt}, so a later start of
   * the same run can find and kill an orphan (successor review 2026-09-23).
   */
  readonly procFile?: string;
  /** G-BK1: SIGTERM, then this long before SIGKILL, when the call is aborted (cancel, stop, supersede, lost). */
  readonly cancelGraceMs?: number;
}

export interface WorkerJob {
  readonly kind: "worker";
  readonly id: string;
  /** ES module source exporting `default { async test(ctrl, env) {...} }`. */
  readonly module: string;
  /** Text bindings visible as `env.<NAME>`. */
  readonly bindings?: Readonly<Record<string, string>>;
  readonly jobDir: string;
  readonly timeoutMs?: number;
}

export type Job = ProcessJob | WorkerJob;

/** What one attempt produced. */
export interface RunOutcome {
  readonly runtime: string;
  readonly jobId: string;
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
  readonly durationMs: number;
  /** Set when the runtime killed the job at its timeout. */
  readonly timedOut?: boolean;
  /** Runtime-specific evidence: bundle path, log id, runner store path. */
  readonly detail?: Readonly<Record<string, string>>;
}

/** A runtime declined the job before starting anything. Nothing ran. */
export interface Refusal {
  readonly runtime: string;
  readonly jobId: string;
  readonly refused: string;
  /** What was done before refusing (a microvm runner built before its boot gate). */
  readonly detail?: Readonly<Record<string, string>>;
}

export type RunResult = RunOutcome | Refusal;

export const isRefusal = (r: RunResult): r is Refusal => "refused" in r;

export interface Runner {
  /** The runtime name as the config names it (`gvisor`, `ssh:worker`). */
  readonly name: string;
  /** The adapter type (`host`, `herdr`, `gvisor`, `microvm`, `ssh`, `workerd`, `ax`). */
  readonly type: string;
  /** A pure, synchronous check: why this runtime will not take this job, or undefined. */
  readonly refuses: (job: Job) => string | undefined;
  readonly run: (job: Job, signal?: AbortSignal) => Promise<RunResult>;
}

/** Job ids reach file names, container ids and herdr correlation ids. */
export const JOB_ID = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/;

export function refuseCommon(job: Job): string | undefined {
  if (!JOB_ID.test(job.id)) return `job id ${JSON.stringify(job.id)} is not [A-Za-z0-9][A-Za-z0-9_.-]{0,127}`;
  if (!job.jobDir.startsWith("/")) return `jobDir must be absolute, got ${job.jobDir}`;
  if (job.kind === "process") {
    if (job.argv.length === 0) return "argv is empty";
    for (const m of job.mounts ?? []) {
      if (!m.source.startsWith("/") || !m.target.startsWith("/")) {
        return `mount ${m.source} -> ${m.target} is not absolute on both sides`;
      }
    }
  }
  return undefined;
}

export const refusal = (runtime: string, job: Job, refused: string): Refusal => ({
  runtime,
  jobId: job.id,
  refused,
});
