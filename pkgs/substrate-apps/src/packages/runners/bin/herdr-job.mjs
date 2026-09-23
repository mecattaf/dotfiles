#!/usr/bin/env node
// The one command the substrate-runner herdr plugin runs. It executes the job
// described by a job.json (path from HERDR_PLUGIN_CONTEXT_JSON.selected_text in
// action mode, or argv[2] in pane mode), streams stdout and stderr through to
// herdr, keeps full copies in the job dir, enforces the job timeout itself, and
// exits with the job's exit code so herdr's plugin log records it natively.
import { spawn } from "node:child_process";
import { createWriteStream, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const ctx = process.env.HERDR_PLUGIN_CONTEXT_JSON ? JSON.parse(process.env.HERDR_PLUGIN_CONTEXT_JSON) : {};
const specPath = process.argv[2] ?? ctx.selected_text;
if (!specPath) {
  process.stderr.write("herdr-job: no job spec (argv[2] or context.selected_text)\n");
  process.exit(2);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const dir = spec.jobDir;
const out = createWriteStream(join(dir, ".herdr-stdout"));
const err = createWriteStream(join(dir, ".herdr-stderr"));
const [cmd, ...args] = spec.argv;
const child = spawn(cmd, args, {
  cwd: dir,
  env: { ...process.env, ...(spec.env ?? {}) },
  stdio: ["pipe", "pipe", "pipe"],
  detached: true,
});
const startOf = (pid) => {
  try {
    const st = readFileSync(`/proc/${pid}/stat`, "utf8");
    const f = st.slice(st.lastIndexOf(")") + 2).split(" ");
    // A zombie runner has exited: its job must die (successor review r3).
    if (f[0] === "Z" || f[0] === "X") return undefined;
    return f[19];
  } catch {
    return undefined;
  }
};
writeFileSync(join(dir, ".herdr-pstart"), String(startOf(child.pid) ?? ""));
writeFileSync(join(dir, ".herdr-pid"), String(child.pid ?? ""));
// The job is herdr's child, not the runner's, so the runner's pdeathsig never
// reaches it. Watch the runner (pid and start time) and kill the job's group
// when the runner is gone, by kill -9 or SIGTERM (successor review r2).
const watchdog =
  spec.runnerPid && spec.runnerStart
    ? setInterval(() => {
        if (startOf(spec.runnerPid) !== spec.runnerStart) {
          try { process.kill(-child.pid, "SIGKILL"); } catch { child.kill("SIGKILL"); }
        }
      }, 200)
    : undefined;
let timedOut = false;
const timer = spec.timeoutMs
  ? setTimeout(() => {
      timedOut = true;
      try { process.kill(-child.pid, "SIGKILL"); } catch { child.kill("SIGKILL"); }
    }, spec.timeoutMs)
  : undefined;
child.stdout.on("data", (b) => { out.write(b); if (!spec.quiet) process.stdout.write(b); });
child.stderr.on("data", (b) => { err.write(b); if (!spec.quiet) process.stderr.write(b); });
child.stdin.on("error", () => {});
child.stdin.end(spec.stdinFile ? readFileSync(spec.stdinFile) : "");
let finished = false;
const finish = (rc) => {
  if (finished) return;
  finished = true;
  if (timer) clearTimeout(timer);
  if (watchdog) clearInterval(watchdog);
  const code = timedOut ? 124 : rc;
  let pending = 2;
  const done = () => {
    if (--pending) return;
    writeFileSync(join(dir, ".herdr-rc"), String(code));
    process.exit(code);
  };
  out.end(done);
  err.end(done);
};
// Settle on the child's own 'exit', not on 'close': a detached helper that
// inherited stdout keeps 'close' away until it exits, which turned a job that
// exited 0 in time into a 124 timeout and a retry (successor review r5; the
// same fix runProc got in r2). The timer is cleared at exit, so a job that
// exited in time is never reported as timed out; pipes get a short drain.
const DRAIN_MS = Number(process.env.AX_CONWIP_HERDR_DRAIN_MS ?? 2000);
let exitCode;
child.on("error", (e) => { err.write(`herdr-job: spawn failed: ${e.message}\n`); finish(127); });
child.on("exit", (code, sig) => {
  exitCode = code ?? (sig ? 137 : 1);
  if (timer) clearTimeout(timer);
  if (watchdog) clearInterval(watchdog);
  setTimeout(() => {
    child.stdout.destroy();
    child.stderr.destroy();
    finish(exitCode);
  }, DRAIN_MS).unref();
});
child.on("close", (code, sig) => finish(exitCode ?? code ?? (sig ? 137 : 1)));
