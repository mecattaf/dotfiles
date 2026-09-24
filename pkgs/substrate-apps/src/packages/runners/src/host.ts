/**
 * `host`: the job runs as a plain child process on this machine, with Tom's
 * environment and filesystem. No isolation: it is the baseline every other
 * runtime is measured against, and what every call did before runtimes existed.
 *
 * Mounts are honoured only when they are identities (source equals target),
 * because the host has nothing to mount into; anything else is refused rather
 * than silently ignored.
 */
import { accessSync, constants as fsConstants, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { isRefusal, refuseCommon, refusal, type Job, type Runner, type RunResult } from "./job.ts";
import { runProc } from "./proc.ts";

/**
 * The environment a host job inherits: this process's, minus the orchestrating
 * Claude Code session's identity and messaging channel and anything named like
 * a credential (successor review r5: CLAUDE_CODE_MESSAGING_TOKEN, SESSION_ID,
 * CHILD_SESSION and CLAUDE_EFFORT reached every harness). A job that needs a
 * variable passes it in job.env, which is merged after this.
 */
export function hostHarnessEnv(base: NodeJS.ProcessEnv): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(base)) {
    if (v === undefined) continue;
    if (k === "CLAUDECODE" || k.startsWith("CLAUDE_CODE_") || k === "CLAUDE_EFFORT" || k === "CLAUDE_ENVELOPE" || k === "CLAUDE_PID") continue;
    if (k === "AX_CONWIP_TEST_SEAT") continue;
    if (/(_TOKEN|_KEY|_SECRET|_PASSWORD)$/i.test(k) || /^(TOKEN|SECRET|PASSWORD)$/i.test(k)) continue;
    out[k] = v;
  }
  return out;
}

export const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;

export function hostRunner(name = "host", opts: { timeoutMs?: number } = {}): Runner {
  const refuses = (job: Job): string | undefined => {
    const c = refuseCommon(job);
    if (c) return c;
    if (job.kind !== "process") return "host runs process jobs only; a worker job needs the workerd runtime";
    for (const m of job.mounts ?? []) {
      if (m.source !== m.target) return `host cannot mount ${m.source} at ${m.target}; only identity mounts`;
    }
    return undefined;
  };
  return {
    name,
    type: "host",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why) return refusal(name, job, why);
      if (job.kind !== "process") return refusal(name, job, "unreachable");
      mkdirSync(job.jobDir, { recursive: true });
      const r = await runProc({
        argv: job.argv,
        stdin: job.stdin,
        cwd: job.cwd ?? job.jobDir,
        env: { ...hostHarnessEnv(process.env), ...job.env },
        timeoutMs: job.timeoutMs ?? opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
        signal,
        ...(job.cancelGraceMs !== undefined ? { cancelGraceMs: job.cancelGraceMs } : {}),
        ...(job.procFile ? { procFile: job.procFile } : {}),
      });
      return { runtime: name, jobId: job.id, ...r };
    },
  };
}

export const DEFAULT_RUNTIME_TEST_WRAPPER = "~/.local/bin/runtime-test";

/**
 * The host runner with every job's argv behind `runtime-test --`. Refuses when the wrapper is not an executable
 * file: a job that asked for runtime isolation must not run against the live runtime instead.
 */
export function runtimeTestRunner(name = "runtime-test", opts: { timeoutMs?: number; wrapper?: string } = {}): Runner {
  const raw = opts.wrapper ?? DEFAULT_RUNTIME_TEST_WRAPPER;
  const wrapper = raw === "~" || raw.startsWith("~/") ? homedir() + raw.slice(1) : raw;
  const inner = hostRunner(name, opts);
  const missing = (): string | undefined => {
    try {
      accessSync(wrapper, fsConstants.X_OK);
      return undefined;
    } catch {
      return `runtime-test wrapper ${wrapper} is not an executable file; refusing rather than running against the live runtime`;
    }
  };
  const refuses = (job: Job): string | undefined => missing() ?? inner.refuses(job);
  return {
    name,
    type: "runtime-test",
    refuses,
    async run(job, signal): Promise<RunResult> {
      const why = refuses(job);
      if (why) return refusal(name, job, why);
      if (job.kind !== "process") return refusal(name, job, "unreachable");
      const r = await inner.run({ ...job, argv: [wrapper, "--", ...job.argv] }, signal);
      return isRefusal(r) ? r : { ...r, runtime: name };
    },
  };
}
