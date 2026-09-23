/**
 * Successor review round 4 (2026-09-23), runners half. Each block names the
 * finding it pins. Every external program is a fake (a fake herdr socket, a
 * fake runner, a scratch git repo, a fake seat dir holding the string FAKE);
 * nothing real is contacted or read.
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { credentialMounts, fakeCodexProblem, reapWorktreeRecords, RunnerBackend, sweepSeatShadows, TEST_SEAT_ENV, worktreeRecordFile } from "../src/backend.ts";
import { parseRuntimesToml, selectRuntime } from "../src/config.ts";
import { herdrRunner, reapHerdrRecords } from "../src/herdr.ts";
import type { Job, Runner, RunResult } from "../src/job.ts";
import { unreapedSshRecords } from "../src/ssh.ts";
import { tmp } from "./helpers.ts";

const HERE = dirname(fileURLToPath(import.meta.url));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/** Runner pid 2^22+1 is never a live pid on this host's default pid_max. */
const DEAD = { runnerPid: 4194305, runnerStart: "1" };

const fakeRunner = (name: string, answer: (job: Job) => Partial<RunResult>, seen: Job[] = []): Runner => ({
  name,
  type: "host",
  refuses: () => undefined,
  run: async (job) => {
    seen.push(job);
    return { runtime: name, jobId: job.id, exitCode: 0, stdout: "", stderr: "", durationMs: 1, ...answer(job) } as RunResult;
  },
});
const call = (over: Record<string, unknown> = {}) => ({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1, ...over }) as never;

describe("r4: the phase map is a floor, never an escalation", () => {
  const toml = `default = "gv"\n[phases]\nReview = "gv"\nBuild = "host"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`;
  it("a gVisor default, a host-mapped phase and agent({phase}) is refused", () => {
    const c = parseRuntimesToml(toml, "t");
    expect(() => selectRuntime(c, { phase: "Build" })).toThrow(/phase "Build" refused.*sandboxed default gv/);
    expect(selectRuntime(c, { phase: "Review" })).toMatchObject({ name: "gv", via: "phase" });
    // A call override is still judged against the default, and refused.
    expect(() => selectRuntime(c, { runtime: "host", phase: "Build" })).toThrow(/refused/);
  });
  it("the allow list is the one way to permit it", () => {
    const c = parseRuntimesToml(`allow = ["gv", "host"]\n` + toml, "t");
    expect(selectRuntime(c, { phase: "Build" })).toMatchObject({ name: "host", via: "phase" });
  });
  it("a phase that is MORE confined than the default is fine", () => {
    const c = parseRuntimesToml(`default = "host"\n[phases]\nReview = "gv"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t");
    expect(selectRuntime(c, { phase: "Review" })).toMatchObject({ name: "gv" });
  });
});

describe("r4: the codex harness is refused structurally, not only by the capacity gate", () => {
  const c = parseRuntimesToml(`default = "cx"\n[runtime.cx]\ntype = "host"\nharness = "codex"\n`, "t");
  it("without the test guard and without a codex seat the runner is never reached", async () => {
    const saved = process.env[TEST_SEAT_ENV];
    delete process.env[TEST_SEAT_ENV];
    try {
      const seen: Job[] = [];
      const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { cx: fakeRunner("cx", () => ({}), seen) } });
      const out = await b.run(call());
      expect(out.error).toMatch(/codex harness is bound to no capacity seat/);
      expect(seen).toHaveLength(0);
    } finally {
      if (saved !== undefined) process.env[TEST_SEAT_ENV] = saved;
    }
  });
});

describe("final verification: under the test guard, codex runs only a fake it can vouch for", () => {
  const withGuard = async (toml: string, path: string) => {
    const saved = { g: process.env[TEST_SEAT_ENV], p: process.env.PATH };
    process.env[TEST_SEAT_ENV] = "1";
    process.env.PATH = path;
    try {
      const seen: Job[] = [];
      const c = parseRuntimesToml(toml, "t");
      const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { cx: fakeRunner("cx", () => ({ stdout: '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}\n' }), seen) } });
      return { out: await b.run(call()), seen };
    } finally {
      if (saved.g === undefined) delete process.env[TEST_SEAT_ENV];
      else process.env[TEST_SEAT_ENV] = saved.g;
      process.env.PATH = saved.p;
    }
  };
  const fakeBin = () => {
    const d = join(tmp(), "bin");
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, "codex"), "#!/bin/sh\necho fake\n", { mode: 0o755 });
    return d;
  };
  it("ssh is refused even with a fake first on the local PATH", async () => {
    const { out, seen } = await withGuard(`default = "cx"\n[runtime.cx]\ntype = "ssh"\nhost = "worker"\nharness = "codex"\n`, fakeBin());
    expect(out.error).toMatch(/never runs over ssh/);
    expect(seen).toHaveLength(0);
  });
  it("a codex that resolves into /nix/store (an installed one) is refused", async () => {
    const d = join(tmp(), "profile");
    mkdirSync(d, { recursive: true });
    // node itself stands in for the installed codex when it lives in the store.
    const real = realpathSync(process.execPath);
    if (!real.startsWith("/nix/store/")) return;
    symlinkSync(real, join(d, "codex"));
    expect(fakeCodexProblem("host", d)).toMatch(/installed codex/);
    expect(fakeCodexProblem("gvisor", d)).toMatch(/installed codex/);
    const { out, seen } = await withGuard(`default = "cx"\n[runtime.cx]\ntype = "host"\nharness = "codex"\n`, d);
    expect(out.error).toMatch(/installed codex/);
    expect(seen).toHaveLength(0);
  });
  it("no codex on PATH is refused", () => {
    expect(fakeCodexProblem("host", join(tmp(), "empty"))).toMatch(/no codex on PATH/);
  });
  it("a fake outside the store, first on PATH, runs", async () => {
    const { out, seen } = await withGuard(`default = "cx"\n[runtime.cx]\ntype = "host"\nharness = "codex"\n`, fakeBin());
    expect(out.error).toBeUndefined();
    expect(seen).toHaveLength(1);
  });
});

describe("final verification: the ax seam renders the Task for the table's harness", () => {
  it("pi renders a Halogen Task on the halogen seat; codex is refused; claude stays Opus", async () => {
    const saved = process.env[TEST_SEAT_ENV];
    process.env[TEST_SEAT_ENV] = "1";
    try {
      const pi = parseRuntimesToml(`default = "a"\n[runtime.a]\ntype = "ax"\nharness = "pi"\nseat = "halogen"\n`, "t");
      const bp = new RunnerBackend(pi, { jobsRoot: tmp(), runId: "r" });
      expect(bp.route(call())).toMatchObject({ harness: "pi", model: "halogen-qwen3.8-flash-next", seat: "halogen" });
      const root = tmp();
      const outP = await new RunnerBackend(pi, { jobsRoot: root, runId: "r" }).run(call());
      expect(outP.error).toMatch(/spec-only|refused/);
      const task = JSON.parse(readFileSync(join(root, readdirSync(root).find((d) => !d.endsWith(".json"))!, "ax-task.json"), "utf8"));
      expect(task.spec.env.find((e: { name: string }) => e.name === "AX_CONWIP_MODEL").value).toBe("halogen-qwen3.8-flash-next");
      const cx = parseRuntimesToml(`default = "a"\n[runtime.a]\ntype = "ax"\nharness = "codex"\n`, "t");
      const outC = await new RunnerBackend(cx, { jobsRoot: tmp(), runId: "r", defaultSeat: "fake" }).run(call());
      expect(outC.error).toMatch(/renders Claude and Halogen Tasks only/);
      const cl = parseRuntimesToml(`default = "a"\n[runtime.a]\ntype = "ax"\n`, "t");
      expect(new RunnerBackend(cl, { jobsRoot: tmp(), runId: "r", defaultSeat: "cc" }).route(call())).toMatchObject({ harness: "ax", model: "claude-opus-5-5", seat: "cc" });
    } finally {
      if (saved === undefined) delete process.env[TEST_SEAT_ENV];
      else process.env[TEST_SEAT_ENV] = saved;
    }
  });
});

describe("final verification: a sandboxed pi gets the Halogen provider, generated, never copied", () => {
  it("gVisor and microvm get a models.json naming only halogen on the worker; host gets nothing", () => {
    const c = parseRuntimesToml(`default = "g"\n[runtime.g]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\nharness = "pi"\n`, "t");
    const shadow = join(tmp(), "shadow");
    const m = credentialMounts(c, c.runtimes["g"]!, "pi", shadow);
    expect(Array.isArray(m) && m).toMatchObject([{ target: "/home/agent/.pi/agent" }]);
    const models = JSON.parse(readFileSync(join(shadow, "pi-agent", "models.json"), "utf8"));
    expect(Object.keys(models.providers)).toEqual(["halogen"]);
    expect(models.providers.halogen.baseUrl).toBe("http://worker:8731/v1");
    expect(models.providers.halogen.models.map((x: { id: string }) => x.id)).toEqual(["halogen-qwen3.8-flash-next"]);
    const mv = parseRuntimesToml(`default = "v"\n[runtime.v]\ntype = "microvm"\nharness = "pi"\n`, "t");
    expect(credentialMounts(mv, mv.runtimes["v"]!, "pi", join(tmp(), "s2"))).toMatchObject([{ target: "/root/.pi/agent" }]);
    const h = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\nharness = "pi"\n`, "t");
    expect(credentialMounts(h, h.runtimes["h"]!, "pi", join(tmp(), "s3"))).toEqual([]);
  });
  it("a sandboxed pi job gets the provider mount and no CLAUDE_CONFIG_DIR", async () => {
    const c = parseRuntimesToml(`default = "g"\n[runtime.g]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\nharness = "pi"\n`, "t");
    const seen: Job[] = [];
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", seatShadowRoot: tmp(), runners: { g: fakeRunner("g", () => ({ stdout: "pong\n" }), seen) } });
    const out = await b.run(call());
    expect(out.text).toBe("pong");
    const job = seen[0] as Job & { env?: Record<string, string>; mounts?: { target: string }[] };
    expect(job.env?.["CLAUDE_CONFIG_DIR"]).toBeUndefined();
    expect(job.mounts?.map((m) => m.target)).toEqual(["/home/agent/.pi/agent"]);
  });
});

describe("r4 D10: a failed harness's usage is kept", () => {
  it("exit 1 with an is_error envelope carrying 5000 output tokens returns the usage beside the error", async () => {
    const c = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\n`, "t");
    const env = JSON.stringify({ type: "result", subtype: "error_max_turns", is_error: true, session_id: "s-9", result: "", usage: { input_tokens: 3, output_tokens: 5000 } });
    const b = new RunnerBackend(c, { jobsRoot: tmp(), runId: "r", runners: { h: fakeRunner("h", () => ({ exitCode: 1, stdout: env })) } });
    const out = await b.run(call());
    expect(out.error).toMatch(/claude exited 1/);
    expect(out.usage).toEqual({ inputTokens: 3, outputTokens: 5000 });
    expect(out.agentId).toBe("s-9");
  });
});

describe("r4: herdr pane mode, a lost workspace.create answer", () => {
  /** A fake herdr that makes the workspace and drops the connection before answering; list and close work unless `listDown`. */
  const fakeHerdr = async (root: string) => {
    const sock = join(root, "h.sock");
    const open = new Map<string, string>();
    const st = { n: 0, listDown: false };
    const server = createServer((c) => {
      let buf = "";
      c.on("data", (d) => {
        buf += d;
        const i = buf.indexOf("\n");
        if (i < 0) return;
        const req = JSON.parse(buf.slice(0, i)) as { id: unknown; method: string; params: Record<string, string> };
        if (req.method === "workspace.create") {
          open.set(`w${++st.n}`, req.params["label"]!);
          c.destroy();
          return;
        }
        if (req.method === "workspace.list") {
          if (st.listDown) return void c.destroy();
          return void c.end(JSON.stringify({ id: req.id, result: { type: "workspace_list", workspaces: [...open].map(([workspace_id, label]) => ({ workspace_id, label })) } }) + "\n");
        }
        if (req.method === "workspace.close") open.delete(req.params["workspace_id"]!);
        c.end(JSON.stringify({ id: req.id, result: {} }) + "\n");
      });
    });
    await new Promise<void>((r) => server.listen(sock, r));
    return { sock, open, st, server };
  };
  const attempt = async (runner: Runner, jobs: string, a: number) => {
    const id = `wf_x-1-a${a}`;
    const jobDir = join(jobs, id);
    mkdirSync(jobDir);
    return runner.run({ kind: "process", id, argv: ["true"], jobDir, agent: true, procFile: join(jobs, `${id}.proc.json`) });
  };
  it("three attempts leave 0 workspaces open: each lost create is closed by its label", async () => {
    const root = tmp();
    const h = await fakeHerdr(root);
    const jobs = join(root, "jobs");
    mkdirSync(jobs);
    const runner = herdrRunner("herdr", { socket: h.sock, mode: "pane", startGraceMs: 300, pollMs: 50 });
    try {
      for (const a of [1, 2, 3]) expect("refused" in (await attempt(runner, jobs, a))).toBe(true);
      expect([...h.open.keys()]).toEqual([]);
      expect(readdirSync(jobs).filter((f) => f.endsWith(".herdr.json"))).toEqual([]);
    } finally {
      h.server.close();
    }
  });
  it("when herdr cannot even list, the record keeps the label and the restart reaper closes it", async () => {
    const root = tmp();
    const h = await fakeHerdr(root);
    h.st.listDown = true;
    const jobs = join(root, "jobs");
    mkdirSync(jobs);
    const runner = herdrRunner("herdr", { socket: h.sock, mode: "pane", startGraceMs: 300, pollMs: 50 });
    try {
      await attempt(runner, jobs, 1);
      const recs = readdirSync(jobs).filter((f) => f.endsWith(".herdr.json"));
      expect(recs).toHaveLength(1);
      expect(JSON.parse(readFileSync(join(jobs, recs[0]!), "utf8"))).toMatchObject({ label: "axc-wf_x-1-a1" });
      expect(h.open.size).toBe(1);
      h.st.listDown = false;
      // The restart: the runner that wrote the record is dead.
      const rp = join(jobs, recs[0]!);
      writeFileSync(rp, JSON.stringify({ ...JSON.parse(readFileSync(rp, "utf8")), ...DEAD }));
      const lines = await reapHerdrRecords(jobs, -1);
      expect(lines.join("\n")).toMatch(/closed 1 workspace\(s\) labelled axc-wf_x-1-a1/);
      expect(h.open.size).toBe(0);
    } finally {
      h.server.close();
    }
  });
});

const git = (cwd: string, ...a: string[]) => spawnSync("git", ["-C", cwd, ...a], { encoding: "utf8", env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" } });

describe("r4: a kill -9 during an isolation:'worktree' call leaves no worktree unreported", () => {
  it("the restart removes a clean orphan worktree and keeps and reports a dirty one", () => {
    const root = tmp();
    const repo = join(root, "repo");
    mkdirSync(repo);
    git(repo, "init", "-q");
    writeFileSync(join(repo, "f"), "a\n");
    git(repo, "add", "f");
    git(repo, "commit", "-qm", "init");
    const base = git(repo, "rev-parse", "HEAD").stdout.trim();
    const top = git(repo, "rev-parse", "--show-toplevel").stdout.trim();
    const jobs = join(root, "jobs");
    mkdirSync(jobs);
    for (const id of ["clean-1-a1", "dirty-2-a1"]) {
      const path = join(jobs, id, "worktree");
      mkdirSync(join(jobs, id));
      expect(git(top, "worktree", "add", "--detach", path, "HEAD").status).toBe(0);
      writeFileSync(worktreeRecordFile(jobs, id), JSON.stringify({ top, path, base, ...DEAD }));
    }
    writeFileSync(join(jobs, "dirty-2-a1", "worktree", "f"), "half-done edit\n");
    const lines = reapWorktreeRecords(jobs);
    expect(lines.join("\n")).toMatch(/clean-1-a1\/worktree: clean, removed/);
    expect(lines.join("\n")).toMatch(/dirty-2-a1\/worktree: killed mid-edit, kept/);
    const list = git(top, "worktree", "list").stdout;
    expect(list).not.toMatch(/clean-1-a1/);
    expect(list).toMatch(/dirty-2-a1/);
    expect(readdirSync(jobs).filter((f) => f.endsWith(".worktree.json"))).toEqual([]);
  });
  it("a live runner's worktree record is left alone", () => {
    const jobs = tmp();
    writeFileSync(worktreeRecordFile(jobs, "x-1-a1"), JSON.stringify({ top: "/nonexistent", path: "/nonexistent/w", base: "0", runnerPid: process.pid, runnerStart: "any" }));
    expect(reapWorktreeRecords(jobs)).toEqual([]);
    expect(existsSync(worktreeRecordFile(jobs, "x-1-a1"))).toBe(true);
  });
});

describe("r4: a seat shadow whose owner is gone is swept by any later start", () => {
  it("another run's orphan shadow goes; a live owner's stays; the credential's link count returns to 1", () => {
    const home = tmp();
    const seat = join(home, ".claude");
    mkdirSync(seat);
    writeFileSync(join(seat, ".credentials.json"), "FAKE");
    const c = parseRuntimesToml(`default = "vm"\n[credentials]\nclaude = "${seat}"\n[runtime.vm]\ntype = "microvm"\n`, "t");
    const root = join(home, "shadows");
    // A microvm shadow made by this process for run A, then orphaned as if its runner died.
    const orphan = join(root, "wf_a-1-a1");
    expect(credentialMounts(c, c.runtimes["vm"]!, "claude", orphan)).not.toHaveProperty("refused");
    expect(statSync(join(seat, ".credentials.json")).nlink).toBe(2);
    writeFileSync(`${orphan}.owner.json`, JSON.stringify({ pid: DEAD.runnerPid, start: DEAD.runnerStart }));
    // A live owner's shadow (this process) for run B.
    const live = join(root, "wf_b-1-a1");
    mkdirSync(live, { recursive: true });
    writeFileSync(`${live}.owner.json`, JSON.stringify({ pid: 1, start: "not-this" }));
    writeFileSync(`${live}.owner.json`, JSON.stringify({ pid: process.pid, start: "x" }));
    // An unrelated run C starts: it sweeps A's orphan.
    const lines = sweepSeatShadows(c, "wf_c", join(home, "jobs"), root);
    expect(lines.join("\n")).toMatch(/seat shadow wf_a-1-a1 removed \(owner pid 4194305 is gone\)/);
    expect(existsSync(orphan)).toBe(false);
    expect(existsSync(live)).toBe(true);
    expect(statSync(join(seat, ".credentials.json")).nlink).toBe(1);
  });
});

describe("r4: the ssh reaper's failures are listed for the restart to refuse", () => {
  it("a dead runner's record is unreaped; a live runner's is not", () => {
    const jobs = tmp();
    writeFileSync(join(jobs, "a-1-a1.ssh.json"), JSON.stringify({ host: "worker", id: "a-1-a1", ...DEAD }));
    writeFileSync(join(jobs, "b-1-a1.ssh.json"), JSON.stringify({ host: "worker", id: "b-1-a1", runnerPid: process.pid, runnerStart: "x" }));
    expect(unreapedSshRecords(jobs)).toEqual([{ id: "a-1-a1", host: "worker" }]);
  });
});

describe("r3 finding 18 pinned (r4 mutant M24): herdr-job.mjs treats a zombie runner as gone", () => {
  it("a job whose runner is a zombie is killed by the watchdog", async () => {
    const d = tmp();
    // `exec sleep 5` never waits, so its child `sleep 0` stays a zombie: the dead runner.
    // The holder outlives the test window, so the zombie is never reaped by init mid-test.
    const holder = spawn("sh", ["-c", "sleep 0 & echo $! > " + join(d, "z") + "; exec sleep 30"], { stdio: "ignore" });
    try {
      await sleep(300);
      const z = Number(readFileSync(join(d, "z"), "utf8"));
      const fields = readFileSync(`/proc/${z}/stat`, "utf8").split(") ")[1]!.split(" ");
      expect(fields[0]).toBe("Z");
      const spec = join(d, "job.json");
      writeFileSync(spec, JSON.stringify({ jobDir: d, argv: ["sleep", "30"], quiet: true, runnerPid: z, runnerStart: fields[19] }));
      const job = spawn(process.execPath, [join(HERE, "..", "bin", "herdr-job.mjs"), spec], { stdio: "ignore" });
      // The watchdog polls every 200 ms: a live-looking runner would keep the job for its full 30 s.
      const code = await Promise.race([new Promise<number>((r) => job.on("close", (c) => r(c ?? -1))), sleep(3000).then(() => -2)]);
      if (code === -2) job.kill("SIGKILL");
      expect(code).toBe(137);
      expect(readFileSync(join(d, ".herdr-rc"), "utf8")).toBe("137");
    } finally {
      holder.kill("SIGKILL");
    }
  });
});
