// Buildkite-family critique pass (2026-09-24): cancel grace (G-BK1) and operator lifecycle hooks (G-BK8).
// G-BK1 inverts audit probe P1: before, an abort SIGKILLed the group in 2 ms and the agent's TERM trap never ran.
import { existsSync, readFileSync, writeFileSync, chmodSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import type { Job, ProcessJob, Runner, RunResult } from "../src/job.ts";
import { runProc } from "../src/proc.ts";
import { tmp } from "./helpers.ts";

const trapScript = (m: string) => ["bash", "-c", `trap 'echo term > ${m}; exit 0' TERM; echo ready; sleep 30 & wait`];
const ready = () => new Promise((r) => setTimeout(r, 400));

describe("G-BK1 cancel grace", () => {
  it("an abort sends SIGTERM first: the agent's TERM trap runs (probe P1 inverted)", async () => {
    const m = join(tmp("bk-"), "marker");
    const ac = new AbortController();
    const p = runProc({ argv: trapScript(m), signal: ac.signal, noDeathSignal: true, cancelGraceMs: 5_000 });
    await ready();
    const t0 = Date.now();
    ac.abort();
    const r = await p;
    expect(existsSync(m)).toBe(true);
    expect(r.aborted).toBe(true);
    expect(r.killedAfterGrace).toBeUndefined();
    expect(Date.now() - t0).toBeLessThan(4_000); // the trap exits at once; the grace is a ceiling, not a delay
  });

  it("a child that ignores SIGTERM is SIGKILLed when the grace runs out", async () => {
    const ac = new AbortController();
    const p = runProc({ argv: ["bash", "-c", "trap '' TERM; sleep 30 & wait; sleep 30"], signal: ac.signal, noDeathSignal: true, cancelGraceMs: 300 });
    await ready();
    const t0 = Date.now();
    ac.abort();
    const r = await p;
    expect(r.aborted).toBe(true);
    expect(r.killedAfterGrace).toBe(true);
    expect(r.exitCode).toBe(137);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(250);
  });

  it("cancelGraceMs 0 keeps the old immediate SIGKILL", async () => {
    const m = join(tmp("bk-"), "marker");
    const ac = new AbortController();
    const p = runProc({ argv: trapScript(m), signal: ac.signal, noDeathSignal: true, cancelGraceMs: 0 });
    await ready();
    ac.abort();
    const r = await p;
    expect(existsSync(m)).toBe(false);
    expect(r.exitCode).toBe(137);
  });

  it("a custom cancel signal is delivered (SIGINT)", async () => {
    const m = join(tmp("bk-"), "marker");
    const ac = new AbortController();
    const p = runProc({ argv: ["bash", "-c", `trap 'echo int > ${m}; exit 0' INT; sleep 30 & wait`], signal: ac.signal, noDeathSignal: true, cancelSignal: "SIGINT", cancelGraceMs: 5_000 });
    await ready();
    ac.abort();
    await p;
    expect(readFileSync(m, "utf8").trim()).toBe("int");
  });

  it("runtimes.toml cancel_grace_ms reaches every agent job; an out-of-range value is refused", async () => {
    const cfg = parseRuntimesToml(`default = "gv"\ncancel_grace_ms = 2500\n[credentials]\nscope = "dir"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t", "/home/u");
    expect(cfg.cancelGraceMs).toBe(2500);
    const jobs: ProcessJob[] = [];
    const gv: Runner = { name: "gv", type: "gvisor", refuses: () => undefined,
      run: async (j: Job) => { jobs.push(j as ProcessJob); return { runtime: "gv", jobId: j.id, exitCode: 0, stdout: "ok\n", stderr: "", durationMs: 1 } as RunResult } };
    const b = new RunnerBackend(cfg, { jobsRoot: tmp(), runId: "r", runners: { gv } });
    await b.run({ index: 1, key: "k1", prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never);
    expect(jobs[0]!.cancelGraceMs).toBe(2500);
    expect(() => parseRuntimesToml(`default = "host"\ncancel_grace_ms = -1\n`, "t", "/home/u")).toThrow(/cancel_grace_ms/);
  });
});

describe("G-BK8 lifecycle hooks", () => {
  const hookBin = (dir: string, name: string, body: string) => { const p = join(dir, name); writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`); chmodSync(p, 0o755); return p; };
  const gvRunner = (jobs: ProcessJob[], wait?: (s?: AbortSignal) => Promise<void>): Runner => ({ name: "gv", type: "gvisor", refuses: () => undefined,
    run: async (j: Job, s?: AbortSignal) => { jobs.push(j as ProcessJob); await wait?.(s); return { runtime: "gv", jobId: j.id, exitCode: 0, stdout: "done\n", stderr: "", durationMs: 1 } as RunResult } });

  it("a pre_start hook that exits non-zero vetoes the call before the harness runs", async () => {
    const d = tmp("bk-hooks-");
    const veto = hookBin(d, "veto", `echo "disk full on $SUBSTRATE_RUNTIME" >&2; exit 3`);
    const cfg = parseRuntimesToml(`default = "gv"\n[credentials]\nscope = "dir"\n[hooks]\npre_start = ["${veto}"]\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t", "/home/u");
    const jobs: ProcessJob[] = [];
    const b = new RunnerBackend(cfg, { jobsRoot: tmp(), runId: "r", runners: { gv: gvRunner(jobs) } });
    const out = await b.run({ index: 1, key: "k1", prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never) as { error?: string };
    expect(out.error).toMatch(/pre_start hook vetoed \(exit 3\): disk full on gv/);
    expect(jobs).toHaveLength(0);
  });

  it("pre_exit runs after the harness with the job's env, even on an aborted call", async () => {
    const d = tmp("bk-hooks-");
    const log = join(d, "log");
    const ok = hookBin(d, "ok", `echo "start $SUBSTRATE_JOB_ID" >> ${log}`);
    const post = hookBin(d, "post", `echo "exit $SUBSTRATE_JOB_ID aborted=$SUBSTRATE_ABORTED dir=$([ -d "$SUBSTRATE_JOB_DIR" ] && echo y)" >> ${log}`);
    const cfg = parseRuntimesToml(`default = "gv"\n[credentials]\nscope = "dir"\n[hooks]\npre_start = ["${ok}"]\npre_exit = ["${post}"]\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t", "/home/u");
    const jobs: ProcessJob[] = [];
    const ac = new AbortController();
    const b = new RunnerBackend(cfg, { jobsRoot: tmp(), runId: "r", runners: { gv: gvRunner(jobs, (s) => new Promise((ok2) => s?.addEventListener("abort", () => ok2(), { once: true }))) } });
    const p = b.run({ index: 1, key: "k1", prompt: "P", opts: {}, phase: undefined, attempt: 1, signal: ac.signal } as never);
    await new Promise((r) => setTimeout(r, 200));
    ac.abort();
    await p;
    const lines = readFileSync(log, "utf8").trim().split("\n");
    expect(lines[0]).toMatch(/^start r-1-a1$/);
    expect(lines[1]).toBe("exit r-1-a1 aborted=1 dir=y");
  });

  it("a hook must be an absolute argv", () => {
    expect(() => parseRuntimesToml(`default = "host"\n[hooks]\npre_start = ["veto.sh"]\n`, "t", "/home/u")).toThrow(/absolute path/);
  });
});
