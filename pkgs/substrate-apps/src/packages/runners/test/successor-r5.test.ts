/**
 * Successor review round 5 (2026-09-23), runners half. Every program is a fake.
 */
import { describe, expect, it } from "vitest";
import { RunnerBackend, TEST_SEAT_ENV } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { claudeInvocation, CLAUDE_MODEL } from "../src/harness.ts";
import { hostRunner } from "../src/host.ts";
import type { Job, Runner, RunResult } from "../src/job.ts";
import { sshArgv } from "../src/ssh.ts";
import { tmp } from "./helpers.ts";

const fakeRunner = (name: string, type: string, seen: Job[]): Runner => ({
  name,
  type: type as never,
  refuses: () => undefined,
  run: async (job) => {
    seen.push(job);
    return { runtime: name, jobId: job.id, exitCode: 0, stdout: '{"type":"result","subtype":"success","is_error":false,"session_id":"s","result":"ok","usage":{"input_tokens":1,"output_tokens":1}}', stderr: "", durationMs: 1 } as RunResult;
  },
});
const call = () => ({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1 }) as never;

describe("r5: the claude harness pins its subagents to the one model", () => {
  it("claudeInvocation carries CLAUDE_CODE_SUBAGENT_MODEL and _FORCE", () => {
    const inv = claudeInvocation({ prompt: "p" } as never);
    expect(inv.env).toEqual({ CLAUDE_CODE_SUBAGENT_MODEL: CLAUDE_MODEL, CLAUDE_CODE_SUBAGENT_MODEL_FORCE: "1" });
    expect(CLAUDE_MODEL).toBe("claude-opus-5-5");
  });
  for (const type of ["host", "herdr", "gvisor", "microvm", "ssh"]) {
    it(`the job handed to a ${type} runtime carries both variables`, async () => {
      const saved = process.env[TEST_SEAT_ENV];
      process.env[TEST_SEAT_ENV] = "1";
      try {
        const seen: Job[] = [];
        const c = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\n`, "t");
        const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { h: fakeRunner("h", type, seen) } });
        await b.run(call());
        expect(seen).toHaveLength(1);
        const env = (seen[0] as { env?: Record<string, string> }).env ?? {};
        expect(env["CLAUDE_CODE_SUBAGENT_MODEL"]).toBe("claude-opus-5-5");
        expect(env["CLAUDE_CODE_SUBAGENT_MODEL_FORCE"]).toBe("1");
      } finally {
        if (saved === undefined) delete process.env[TEST_SEAT_ENV];
        else process.env[TEST_SEAT_ENV] = saved;
      }
    });
  }
  it("ssh passes them through its env prefix", () => {
    const argv = sshArgv({ host: "worker" } as never, { argv: ["claude"], env: { CLAUDE_CODE_SUBAGENT_MODEL_FORCE: "1" } });
    expect(argv.join(" ")).toContain("CLAUDE_CODE_SUBAGENT_MODEL_FORCE=");
  });
});

describe("r5: a host job never inherits the orchestrator's session or credentials", () => {
  it("canary variables do not reach the child; job.env and PATH do", async () => {
    const canaries = {
      CLAUDE_CODE_MESSAGING_TOKEN: "canary-r5-token",
      CLAUDE_CODE_MESSAGING_SOCKET: "/nonexistent/canary.sock",
      CLAUDE_CODE_SESSION_ID: "canary-session",
      CLAUDE_CODE_CHILD_SESSION: "1",
      CLAUDECODE: "1",
      CLAUDE_EFFORT: "max",
      CLAUDE_ENVELOPE: "canary",
      CLAUDE_PID: "1",
      CANARY_SECRET: "canary",
      SOME_API_KEY: "canary",
      AX_CONWIP_TEST_SEAT: "1",
    };
    const saved: Record<string, string | undefined> = {};
    for (const [k, v] of Object.entries(canaries)) {
      saved[k] = process.env[k];
      process.env[k] = v;
    }
    try {
      const dir = tmp();
      const r = await hostRunner().run({ kind: "process", id: "j", argv: ["env"], stdin: "", jobDir: dir, env: { KEPT_BY_JOB: "yes" } } as never);
      const seen = (r as { stdout: string }).stdout;
      for (const k of Object.keys(canaries)) expect(seen, k).not.toMatch(new RegExp(`^${k}=`, "m"));
      expect(seen).toMatch(/^KEPT_BY_JOB=yes$/m);
      expect(seen).toMatch(/^PATH=/m);
      expect(seen).not.toContain("canary");
    } finally {
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });
});

describe("r5: herdr-job settles on the child's exit, not on a detached helper's stdout", () => {
  it("a job that exits 0 at once while a setsid helper holds stdout reports 0, not 124", async () => {
    const { spawn, spawnSync } = await import("node:child_process");
    const { readFileSync, writeFileSync } = await import("node:fs");
    const { join, dirname } = await import("node:path");
    const { fileURLToPath } = await import("node:url");
    const bin = join(dirname(fileURLToPath(import.meta.url)), "../bin/herdr-job.mjs");
    const dir = tmp();
    const tag = `r5-herdr-${process.pid}-${Date.now()}`;
    const spec = join(dir, "job.json");
    writeFileSync(spec, JSON.stringify({ jobDir: dir, argv: ["bash", "-c", `setsid sh -c "sleep 9; : ${tag}" & echo harness-done; exit 0`], timeoutMs: 3000, quiet: true }));
    const t0 = Date.now();
    const rc = await new Promise<number | null>((res) => {
      const p = spawn(process.execPath, [bin, spec], { stdio: "ignore", env: { ...process.env, AX_CONWIP_HERDR_DRAIN_MS: "300" } });
      p.on("exit", (c) => res(c));
    });
    const took = Date.now() - t0;
    spawnSync("pkill", ["-f", tag]);
    expect(rc).toBe(0);
    expect(readFileSync(join(dir, ".herdr-rc"), "utf8")).toBe("0");
    expect(readFileSync(join(dir, ".herdr-stdout"), "utf8")).toContain("harness-done");
    expect(took).toBeLessThan(2500);
  }, 15000);
});

describe("r5: runProc kills the rest of the job's group when the leader exits normally", () => {
  it("a same-group background process does not outlive a job that exited 0", async () => {
    const { runProc } = await import("../src/proc.ts");
    const { spawnSync } = await import("node:child_process");
    const { join } = await import("node:path");
    const dir = tmp();
    const tag = `r5-grp-${process.pid}-${Date.now()}`;
    const r = await runProc({ argv: ["bash", "-c", `sh -c "sleep 30; : ${tag}" >/dev/null 2>&1 & echo done`], procFile: join(dir, "j1.proc.json"), drainGraceMs: 300 });
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toContain("done");
    await new Promise((res) => setTimeout(res, 200));
    const alive = spawnSync("pgrep", ["-f", tag]).stdout.toString().trim();
    spawnSync("pkill", ["-f", tag]);
    expect(alive).toBe("");
    expect(r.stderr).toMatch(/killed \d+ process\(es\) left in the job's group/);
  });
});

describe("r5: a dead gVisor runner's bundle and container are swept", () => {
  it("dead owner: runsc delete --force and the bundle removed; live owner and a young unowned bundle kept", async () => {
    const { sweepGvisorBundles, GVISOR_OWNER } = await import("../src/gvisor.ts");
    const { procStartTicks } = await import("../src/proc.ts");
    const { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const state = tmp();
    const log = join(state, "runsc.log");
    const runsc = join(state, "runsc");
    writeFileSync(runsc, `#!/bin/sh\necho "$@" >> ${log}\n`);
    chmodSync(runsc, 0o755);
    const mk = (id: string, owner?: object) => {
      mkdirSync(join(state, "bundles", id, "rootfs"), { recursive: true });
      if (owner) writeFileSync(join(state, "bundles", id, GVISOR_OWNER), JSON.stringify(owner));
    };
    mk("axc-dead", { runnerPid: 4194305, runnerStart: "1" });
    mk("axc-live", { runnerPid: process.pid, runnerStart: procStartTicks(process.pid) });
    mk("axc-young");
    const out = await sweepGvisorBundles(state, runsc);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatch(/^axc-dead: /);
    expect(existsSync(join(state, "bundles", "axc-dead"))).toBe(false);
    expect(existsSync(join(state, "bundles", "axc-live"))).toBe(true);
    expect(existsSync(join(state, "bundles", "axc-young"))).toBe(true);
    expect(readFileSync(log, "utf8")).toMatch(/--rootless --root=\S+ delete --force axc-dead/);
    // An unowned bundle past the age bound is an orphan too.
    expect(await sweepGvisorBundles(state, runsc, 0)).toEqual([expect.stringMatching(/^axc-young: /)]);
  });
});
