/**
 * Successor review round 3 (2026-09-23), runners half. Each block names the
 * finding it pins. Every external program is a fake: a fake ssh that runs the
 * "remote" locally under a scratch HOME, a fake herdr socket, a fake seat dir
 * holding the string FAKE. Nothing real is contacted or read.
 */
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RunnerBackend, seatShadowRoot, sweepSeatShadows } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { herdrRunner, reapHerdrRecords } from "../src/herdr.ts";
import { isRefusal, type Job, type Runner, type RunOutcome, type RunResult } from "../src/job.ts";
import { procStartTicks, reapProcFiles, runProc, sameProcess } from "../src/proc.ts";
import { sshRunner } from "../src/ssh.ts";
import { fakeBin, tmp } from "./helpers.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const alive = (pid: number) => {
  try {
    return !readFileSync(`/proc/${pid}/stat`, "utf8").includes(") Z ");
  } catch {
    return false;
  }
};

describe("r3: a dead but unreaped (zombie) runner is gone, not live", () => {
  it("sameProcess is false for a zombie, and reapProcFiles kills its orphan", async () => {
    const d = tmp();
    // `exec sleep 5` never waits, so its child `sleep 0` stays a zombie: the dead runner.
    const holder = spawn("sh", ["-c", "sleep 0 & echo $! > " + join(d, "z") + "; exec sleep 5"], { stdio: "ignore" });
    await sleep(300);
    const z = Number(readFileSync(join(d, "z"), "utf8"));
    expect(readFileSync(`/proc/${z}/stat`, "utf8").split(") ")[1]!.split(" ")[0]).toBe("Z");
    expect(procStartTicks(z)).toBeUndefined();
    expect(sameProcess(z, "1")).toBe(false);
    const job = spawn("sleep", ["30"], { stdio: "ignore", detached: true, env: { ...process.env, AX_CONWIP_JOB: "job-1" } });
    await sleep(100);
    // The record's runnerStart is any value: a zombie has no live start time.
    writeFileSync(join(d, "job-1.proc.json"), JSON.stringify({ pid: job.pid, pgid: job.pid, start: procStartTicks(job.pid!), job: "job-1", runnerPid: z, runnerStart: "12345" }));
    reapProcFiles(d, -1);
    await sleep(150);
    expect(alive(job.pid!)).toBe(false);
    holder.kill("SIGKILL");
  });
});

describe("r3: an already-aborted call is never spawned", () => {
  it("runProc answers without starting the program", async () => {
    const d = tmp();
    const marker = join(d, "ran");
    const ac = new AbortController();
    ac.abort();
    const r = await runProc({ argv: ["sh", "-c", `touch ${marker}`], timeoutMs: 5000, signal: ac.signal });
    await sleep(100);
    expect(r.exitCode).toBe(137);
    expect(existsSync(marker)).toBe(false);
  });
});

/** A fake ssh: runs the remote command locally under `rhome`. `down` present: the kill ssh fails with 255. */
function fakeSsh(d: string) {
  const rhome = join(d, "remote-home");
  mkdirSync(rhome);
  const down = join(d, "network-down");
  const log = join(d, "remote-runs.log");
  const ssh = join(d, "ssh");
  writeFileSync(ssh, `#!/bin/sh
for a; do last="$a"; done
cd ${rhome}; export HOME=${rhome}
case "$last" in
  *"kill -KILL"*) [ -e ${down} ] && { echo "ssh: Network is unreachable" >&2; exit 255; }; sh -c "$last"; exit $? ;;
esac
if [ -e ${down}.after-start ]; then
  setsid sh -c "$last" </dev/null >/dev/null 2>&1 &
  sleep 0.5; touch ${down}; rm -f ${down}.after-start
  echo "client_loop: send disconnect: Broken pipe" >&2; exit 255
fi
sh -c "$last"
`, { mode: 0o755 });
  return { ssh, down, log, rhome };
}

describe("r3: ssh drop with the remote kill failing", () => {
  const job = (jobsRoot: string, id: string, argv: string[]): Job => ({ kind: "process", id, argv, jobDir: join(jobsRoot, id), procFile: join(jobsRoot, `${id}.proc.json`) });

  it("keeps the record when the kill fails; the retry kills the earlier copy first, so only one copy runs", async () => {
    const d = tmp();
    const f = fakeSsh(d);
    const jobsRoot = join(d, "jobs");
    mkdirSync(jobsRoot);
    const argv = ["sh", "-c", `echo "start $$" >> ${f.log}; sleep 3; echo "done $$" >> ${f.log}`];
    const r = sshRunner("ssh:worker", { host: "worker", ssh: f.ssh, timeoutMs: 20000 });
    writeFileSync(`${f.down}.after-start`, "");
    const a1 = (await r.run(job(jobsRoot, "wf_s-1-a1", argv))) as RunOutcome;
    expect(a1.exitCode).toBe(255);
    expect(a1.detail?.["remoteMayStillRun"]).toBeDefined();
    expect(readdirSync(jobsRoot).filter((x) => x.endsWith(".ssh.json"))).toEqual(["wf_s-1-a1.ssh.json"]);

    // Still down at the retry: refused, nothing started.
    const refused = await r.run(job(jobsRoot, "wf_s-1-a2", argv));
    expect(isRefusal(refused)).toBe(true);

    rmSync(f.down);
    const a3 = (await r.run(job(jobsRoot, "wf_s-1-a3", argv))) as RunOutcome;
    expect(a3.exitCode).toBe(0);
    await sleep(300);
    const lines = readFileSync(f.log, "utf8").trim().split("\n");
    // Two starts (attempt 1 and attempt 3), one done: attempt 1 was killed before attempt 3 ran.
    expect(lines.filter((l) => l.startsWith("start"))).toHaveLength(2);
    expect(lines.filter((l) => l.startsWith("done"))).toHaveLength(1);
    expect(readdirSync(jobsRoot).filter((x) => x.endsWith(".ssh.json"))).toEqual([]);
  }, 30_000);

  it("writes <id>.ssh.json while the call runs and removes it once the outcome is judged", async () => {
    const d = tmp();
    const f = fakeSsh(d);
    const jobsRoot = join(d, "jobs");
    mkdirSync(jobsRoot);
    const r = sshRunner("ssh:worker", { host: "worker", ssh: f.ssh, timeoutMs: 20000 });
    const p = r.run(job(jobsRoot, "wf_r-1-a1", ["sh", "-c", "sleep 0.6; exit 4"]));
    await sleep(250);
    expect(existsSync(join(jobsRoot, "wf_r-1-a1.ssh.json"))).toBe(true);
    const out = (await p) as RunOutcome;
    expect(out.exitCode).toBe(4);
    expect(existsSync(join(jobsRoot, "wf_r-1-a1.ssh.json"))).toBe(false);
    // The remote wrapper removes its own pid file on a normal finish.
    const pids = join(f.rhome, ".local/state/substrate/jobs");
    expect(existsSync(pids) ? readdirSync(pids) : []).toEqual([]);
  });
});

/** A fake herdr socket that behaves like herdr for pane mode; `dropOn` loses that method's answer. */
function fakeHerdr(socket: string, jobDir: string, dropOn?: string, plantStaleRc = false) {
  const open = new Set<string>();
  let n = 0;
  const server: Server = createServer((s: Socket) => {
    let buf = "";
    s.on("data", (c) => {
      buf += c;
      const i = buf.indexOf("\n");
      if (i < 0) return;
      const req = JSON.parse(buf.slice(0, i)) as { id: unknown; method: string; params: Record<string, string> };
      buf = buf.slice(i + 1);
      const ok = (result: unknown) => s.end(JSON.stringify({ id: req.id, result }) + "\n");
      if (req.method === "workspace.create") {
        const id = `w${++n}`;
        open.add(id);
        return ok({ workspace: { workspace_id: id }, root_pane: { pane_id: `${id}:p1` } });
      }
      if (req.method === "workspace.close") {
        open.delete(req.params["workspace_id"]!);
        return ok({});
      }
      if (req.method === "pane.send_input") {
        if (plantStaleRc) {
          // An exit code left from long before this invocation (an hour old).
          writeFileSync(join(jobDir, ".herdr-rc"), "9\n");
          const old = new Date(Date.now() - 3600_000);
          utimesSync(join(jobDir, ".herdr-rc"), old, old);
        }
        spawn("sh", ["-c", req.params["text"]!], { cwd: jobDir, stdio: "ignore", detached: true }).unref();
        if (dropOn === "pane.send_input") return void s.destroy(); // typed; the answer is lost
        return ok({});
      }
      if (req.method === "pane.wait_for_output") {
        const t = setInterval(() => {
          if (existsSync(join(jobDir, ".herdr-rc"))) {
            clearInterval(t);
            ok({ matched: true });
          }
        }, 50);
        s.on("close", () => clearInterval(t));
        return;
      }
      s.destroy();
    });
  });
  return { server, open, listen: () => new Promise<void>((r) => server.listen(socket, r)) };
}

describe("r3: herdr pane mode", () => {
  it("a socket drop on the pane.send_input answer itself is an outcome followed through the job dir; the job runs once", async () => {
    const d = tmp();
    const jobDir = join(d, "jobs", "p-1");
    mkdirSync(jobDir, { recursive: true });
    const h = fakeHerdr(join(d, "h.sock"), jobDir, "pane.send_input");
    await h.listen();
    const log = join(d, "runs.log");
    const res = await herdrRunner("herdr", { socket: join(d, "h.sock"), mode: "pane" }).run({ kind: "process", id: "p-1", argv: ["sh", "-c", `echo attempt >> ${log}; sleep 0.5; exit 3`], jobDir, timeoutMs: 5000 });
    h.server.close();
    expect(isRefusal(res)).toBe(false);
    expect((res as RunOutcome).exitCode).toBe(3);
    expect(readFileSync(log, "utf8").trim().split("\n")).toHaveLength(1);
  });

  it("after a lost send_input answer, a stale .herdr-rc older than this invocation is not read as its exit code", async () => {
    const d = tmp();
    const jobDir = join(d, "jobs", "p-5");
    mkdirSync(jobDir, { recursive: true });
    const h = fakeHerdr(join(d, "h.sock"), jobDir, "pane.send_input", true);
    await h.listen();
    const res = await herdrRunner("herdr", { socket: join(d, "h.sock"), mode: "pane" }).run({ kind: "process", id: "p-5", argv: ["sh", "-c", "sleep 0.5; exit 3"], jobDir, timeoutMs: 5000 });
    h.server.close();
    expect((res as RunOutcome).exitCode).toBe(3);
  });

  it("an abort kills the pane job's group and returns at once; the workspace is closed", async () => {
    const d = tmp();
    const jobDir = join(d, "jobs", "p-2");
    mkdirSync(jobDir, { recursive: true });
    const h = fakeHerdr(join(d, "h.sock"), jobDir);
    await h.listen();
    const marker = join(d, "finished-after-abort");
    const ac = new AbortController();
    setTimeout(() => ac.abort(), 400);
    const t0 = Date.now();
    const res = await herdrRunner("herdr", { socket: join(d, "h.sock"), mode: "pane" }).run(
      { kind: "process", id: "p-2", argv: ["sh", "-c", `sleep 3; touch ${marker}`], jobDir, timeoutMs: 20000 },
      ac.signal,
    );
    const took = Date.now() - t0;
    await sleep(3200);
    h.server.close();
    expect(took).toBeLessThan(2500);
    expect((res as RunOutcome).exitCode).toBe(137);
    expect(existsSync(marker)).toBe(false);
    expect([...h.open]).toEqual([]);
  }, 15_000);

  it("writes <id>.herdr.json while the job runs and removes it after a clean workspace.close", async () => {
    const d = tmp();
    const jobsRoot = join(d, "jobs");
    const jobDir = join(jobsRoot, "p-3");
    mkdirSync(jobDir, { recursive: true });
    const h = fakeHerdr(join(d, "h.sock"), jobDir);
    await h.listen();
    const p = herdrRunner("herdr", { socket: join(d, "h.sock"), mode: "pane" }).run({ kind: "process", id: "p-3", argv: ["sh", "-c", "sleep 0.6"], jobDir, timeoutMs: 5000, procFile: join(jobsRoot, "p-3.proc.json") });
    await sleep(300);
    expect(existsSync(join(jobsRoot, "p-3.herdr.json"))).toBe(true);
    await p;
    h.server.close();
    expect(existsSync(join(jobsRoot, "p-3.herdr.json"))).toBe(false);
  });

  it("reapHerdrRecords kills a dead runner's live job group (proved by .herdr-pstart) and leaves a live runner's record alone", async () => {
    const d = tmp();
    const jobsRoot = join(d, "jobs");
    const deadDir = join(jobsRoot, "dead");
    const liveDir = join(jobsRoot, "live");
    mkdirSync(deadDir, { recursive: true });
    mkdirSync(liveDir, { recursive: true });
    const job = spawn("sleep", ["30"], { stdio: "ignore", detached: true });
    await sleep(100);
    writeFileSync(join(deadDir, ".herdr-pid"), String(job.pid));
    writeFileSync(join(deadDir, ".herdr-pstart"), procStartTicks(job.pid!)!);
    // Dead runner: a pid that is not running (a finished child).
    const gone = spawn("true");
    await new Promise((r) => gone.on("exit", r));
    writeFileSync(join(jobsRoot, "dead.herdr.json"), JSON.stringify({ jobDir: deadDir, runnerPid: gone.pid, runnerStart: "1" }));
    const job2 = spawn("sleep", ["30"], { stdio: "ignore", detached: true });
    await sleep(100);
    writeFileSync(join(liveDir, ".herdr-pid"), String(job2.pid));
    writeFileSync(join(liveDir, ".herdr-pstart"), procStartTicks(job2.pid!)!);
    writeFileSync(join(jobsRoot, "live.herdr.json"), JSON.stringify({ jobDir: liveDir, runnerPid: process.pid, runnerStart: procStartTicks(process.pid) }));
    const lines = await reapHerdrRecords(jobsRoot, -1);
    await sleep(150);
    expect(lines.join("\n")).toContain("dead: herdr job killed");
    expect(alive(job.pid!)).toBe(false);
    expect(alive(job2.pid!)).toBe(true);
    expect(existsSync(join(jobsRoot, "live.herdr.json"))).toBe(true);
    process.kill(-job2.pid!, "SIGKILL");
  });
});

describe("r3: the microvm seat shadow never lives in the run dir and never outlives the job", () => {
  const env = JSON.stringify({ type: "result", subtype: "success", is_error: false, session_id: "s", result: "ok", usage: { input_tokens: 1, output_tokens: 1 } });
  const setup = () => {
    const root = tmp();
    const seat = join(root, "fake-seat");
    mkdirSync(seat);
    const cred = join(seat, ".credentials.json");
    writeFileSync(cred, "FAKE\n", { mode: 0o600 });
    const config = parseRuntimesToml(`default = "vm"\n[credentials]\nclaude = "${seat}"\n[runtime.vm]\ntype = "microvm"\n`, "t", "/home/u");
    return { root, cred, config, jobsRoot: join(root, "run", "jobs") };
  };
  const inodesUnder = (dir: string, out: number[] = []): number[] => {
    if (!existsSync(dir)) return out;
    for (const f of readdirSync(dir)) {
      const p = join(dir, f);
      const st = statSync(p);
      if (st.isDirectory()) inodesUnder(p, out);
      else out.push(st.ino);
    }
    return out;
  };

  it("after 3 calls, done or refused, no file under the run dir shares the credential's inode and nlink is back to 1", async () => {
    const { root, cred, config, jobsRoot } = setup();
    let sawShadow = "";
    let n = 0;
    const vm: Runner = {
      name: "vm", type: "microvm", refuses: () => undefined,
      run: async (j: Job) => {
        n++;
        if (j.kind === "process") sawShadow = j.mounts?.[0]?.source ?? "";
        expect(statSync(cred).nlink).toBe(2);
        return n === 2
          ? ({ runtime: "vm", jobId: j.id, refused: "kvm refused (fake)" } as RunResult)
          : ({ runtime: "vm", jobId: j.id, exitCode: 0, stdout: env, stderr: "", durationMs: 1 } as RunResult);
      },
    };
    const b = new RunnerBackend(config, { jobsRoot, runId: "wf_seat", runners: { vm } });
    for (let i = 1; i <= 3; i++) await b.run({ index: i, key: `k${i}`, prompt: "P", opts: {}, phase: undefined, attempt: 1 } as never);
    expect(sawShadow.startsWith(join(root, "run"))).toBe(false);
    expect(sawShadow.startsWith(seatShadowRoot(config))).toBe(true);
    expect(statSync(cred).nlink).toBe(1);
    expect(inodesUnder(join(root, "run"))).not.toContain(statSync(cred).ino);
    expect(readdirSync(seatShadowRoot(config))).toEqual([]);
  });

  it("a restart sweeps this run's leftover shadows and any legacy <jobsRoot>/*.seat dir", () => {
    const { config, jobsRoot } = setup();
    const left = join(seatShadowRoot(config), "wf_seat-s2-1-a1");
    const other = join(seatShadowRoot(config), "wf_other-1-a1");
    mkdirSync(left, { recursive: true });
    mkdirSync(other, { recursive: true });
    mkdirSync(join(jobsRoot, "wf_seat-1-a1.seat"), { recursive: true });
    const lines = sweepSeatShadows(config, "wf_seat", jobsRoot);
    expect(lines).toHaveLength(2);
    expect(existsSync(left)).toBe(false);
    expect(existsSync(other)).toBe(true);
    expect(existsSync(join(jobsRoot, "wf_seat-1-a1.seat"))).toBe(false);
  });
});

void fakeBin;
