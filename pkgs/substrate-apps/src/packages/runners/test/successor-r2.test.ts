/**
 * Successor review, fix round 2 (2026-09-23), runners half:
 *  - agent() options effort, agentType and isolation reach the harness or are
 *    refused, never dropped;
 *  - schema retries: a non-JSON reply is a missing object, and the retry's
 *    prompt carries the previous errors;
 *  - a claude call on ssh is not gated against the local seat;
 *  - undeclared built-ins are closed under a herdr default;
 *  - pdeathsig, orphan reaping (grandchildren, reused pids), the stdout-held
 *    timeout, ssh and herdr jobs of a dead runner, herdr pane socket drops.
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml, selectRuntime } from "../src/config.ts";
import { claudeInvocation, parseClaude, parseCodex, parsePi, piInvocation } from "../src/harness.ts";
import { ENTRY, herdrRunner, reapHerdrRecords } from "../src/herdr.ts";
import { isRefusal, type RunOutcome } from "../src/job.ts";
import { PDEATHSIG_WRAPPER, procStartTicks, reapProcFiles, runProc } from "../src/proc.ts";
import { reapSshRecords } from "../src/ssh.ts";
import { fakeBin, tmp } from "./helpers.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const alive = (pid: number) => procStartTicks(pid) !== undefined && !readFileSync(`/proc/${pid}/stat`, "utf8").includes(") Z ");
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

const ENVELOPE = `{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s1","usage":{"input_tokens":1,"output_tokens":1}}`;

/** A fake claude on PATH that logs argv|cwd|git top-level per call. */
function fakeClaude() {
  const d = tmp("axc-r2-claude-");
  const log = join(d, "calls.log");
  fakeBin(d, "claude", `p=$(cat); case "$p" in *edit*) echo changed > edited.txt;; esac
printf '%s|%s|%s\\n' "$*" "$PWD" "$(git rev-parse --show-toplevel 2>/dev/null || echo none)" >> ${log}
echo '${ENVELOPE}'`);
  return { bin: d, log, lines: () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : []) };
}
function withPath<T>(dir: string, f: () => Promise<T>): Promise<T> {
  const old = process.env.PATH;
  process.env.PATH = `${dir}:${old}`;
  return f().finally(() => (process.env.PATH = old));
}
const call = (index: number, prompt: string, opts: Record<string, unknown> = {}) => ({ index, key: `k${index}`, prompt, opts, phase: undefined, attempt: 1 });

function gitRepo(): string {
  const d = tmp("axc-r2-repo-");
  const g = (...a: string[]) => spawnSync("git", ["-C", d, "-c", "user.email=t@t", "-c", "user.name=t", ...a], { encoding: "utf8" });
  g("init", "-q");
  writeFileSync(join(d, "a.txt"), "a\n");
  g("add", ".");
  g("commit", "-qm", "init");
  return d;
}

describe("agent() options reach the harness or are refused, never dropped", () => {
  const host = parseRuntimesToml("", "t", "/home/u");
  it("effort and agentType become claude's --effort and --agent; a plain call has neither", async () => {
    const f = fakeClaude();
    const b = new RunnerBackend(host, { jobsRoot: join(tmp(), "jobs"), runId: "r2o" });
    await withPath(f.bin, async () => {
      await b.run(call(1, "plain call"));
      await b.run(call(2, "reviewed", { effort: "low", agentType: "code-reviewer" }));
    });
    const [plain, opts] = f.lines().map((l) => l.split("|")[0]!);
    expect(plain).not.toMatch(/--effort|--agent/);
    expect(opts).toContain("--effort low");
    expect(opts).toContain("--agent code-reviewer");
  });
  it("isolation:'worktree' runs the call in a fresh git worktree, removed when unchanged and kept when changed", async () => {
    const f = fakeClaude();
    const repo = gitRepo();
    const jobs = join(tmp(), "jobs");
    const b = new RunnerBackend(host, { jobsRoot: jobs, runId: "r2w", repoDir: repo });
    await withPath(f.bin, async () => {
      await b.run(call(1, "look only", { isolation: "worktree" }));
      await b.run(call(2, "edit file A", { isolation: "worktree" }));
    });
    const [look, edit] = f.lines().map((l) => l.split("|"));
    expect(look![1]).toBe(join(jobs, "r2w-1-a1", "worktree"));
    expect(look![2]).toBe(join(jobs, "r2w-1-a1", "worktree"));
    expect(existsSync(join(jobs, "r2w-1-a1", "worktree"))).toBe(false);
    expect(edit![2]).toBe(join(jobs, "r2w-2-a1", "worktree"));
    expect(existsSync(join(jobs, "r2w-2-a1", "worktree", "edited.txt"))).toBe(true);
    expect(JSON.parse(readFileSync(join(jobs, "r2w-2-a1", "receipt.json"), "utf8")).worktree).toMatchObject({ kept: true });
  });
  it("an option the harness or runtime cannot honour is refused as an outcome, and nothing runs", async () => {
    const f = fakeClaude();
    const cfg = parseRuntimesToml(`[runtime.pi]\ntype = "host"\nharness = "pi"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t", "/home/u");
    const b = new RunnerBackend(cfg, { jobsRoot: join(tmp(), "jobs"), runId: "r2x", repoDir: tmp() });
    await withPath(f.bin, async () => {
      expect((await b.run(call(1, "p", { runtime: "pi", effort: "high" }))).error).toMatch(/harness pi cannot honour agent\(\{effort/);
      expect((await b.run(call(2, "p", { isolation: "container" }))).error).toMatch(/not supported/);
      expect((await b.run(call(3, "p", { isolation: "worktree" }))).error).toMatch(/needs a git repository/);
    });
    expect(f.lines()).toEqual([]);
  });
});

describe("schema retries", () => {
  it("a non-JSON schema reply is a missing object (retried by the interpreter), not a terminal error", () => {
    expect(parsePi(`Sure! {"n": 3}`, true)).not.toHaveProperty("error");
    expect(parsePi(`Sure! {"n": 3}`, true)).not.toHaveProperty("object");
    const env = JSON.stringify({ type: "result", subtype: "success", result: `Sure! {"n": 3}` });
    expect(parseClaude(env, true)).not.toHaveProperty("error");
    const codex = [JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: "nope" } })].join("\n");
    expect(parseCodex(codex, true)).not.toHaveProperty("error");
  });
  it("attempt 2 and later carry the previous errors in the prompt, for every harness", () => {
    const errs = ["/n: must be integer"];
    expect(claudeInvocation({ prompt: "count", previousErrors: errs }).stdin).toMatch(/count[\s\S]*rejected: \/n: must be integer/);
    expect(piInvocation({ prompt: "count", schema: { type: "object" }, previousErrors: errs }).stdin).toMatch(/rejected: \/n: must be integer/);
    expect(claudeInvocation({ prompt: "count" }).stdin).toBe("count");
  });
  it("RunnerBackend passes call.previousErrors to the harness", async () => {
    const d = tmp();
    const log = join(d, "stdin.log");
    fakeBin(d, "claude", `cat >> ${log}; echo '${ENVELOPE}'`);
    const b = new RunnerBackend(parseRuntimesToml("", "t", "/home/u"), { jobsRoot: join(d, "jobs"), runId: "r2p" });
    await withPath(d, () => b.run({ ...call(1, "count things"), attempt: 2, previousErrors: ["no structured output"] }));
    expect(readFileSync(log, "utf8")).toMatch(/count things[\s\S]*rejected: no structured output/);
  });
});

describe("the seat of a call is a property of (runtime, harness)", () => {
  it("a claude call on ssh:<host> is bound to no seat unless the runtime table names one", () => {
    const allow = parseRuntimesToml(`allow = ["ssh:worker"]\n[seats]\nclaude = "cc"\n[credentials.seats]\ncc = "~/.claude"\n`, "t", "/home/u"); // RG-1: a bound claude seat names its dir
    expect(new RunnerBackend(allow, { jobsRoot: "/x", runId: "r", defaultSeat: "cc" }).route({ opts: { runtime: "ssh:worker" }, phase: undefined }).seat).toBeUndefined();
    const dflt = parseRuntimesToml(`default = "ssh:worker"\n`, "t", "/home/u");
    expect(new RunnerBackend(dflt, { jobsRoot: "/x", runId: "r", defaultSeat: "cc" }).route({ opts: {}, phase: undefined }).seat).toBeUndefined();
    const named = parseRuntimesToml(`default = "w"\n[runtime.w]\ntype = "ssh"\nhost = "worker"\nseat = "worker-cc"\n`, "t", "/home/u");
    expect(new RunnerBackend(named, { jobsRoot: "/x", runId: "r", defaultSeat: "cc" }).route({ opts: {}, phase: undefined }).seat).toBe("worker-cc");
    // Local runtimes keep [seats] and the run's seat.
    expect(new RunnerBackend(allow, { jobsRoot: "/x", runId: "r", defaultSeat: "cc" }).route({ opts: {}, phase: undefined }).seat).toBe("cc");
  });
});

describe("undeclared built-ins are closed unless the default is host", () => {
  it("a herdr default refuses host and ssh:<any>; a declared host table is allowed", () => {
    const c = parseRuntimesToml(`default = "hd"\n[runtime.hd]\ntype = "herdr"\n[runtime.h]\ntype = "host"\n`, "t", "/home/u");
    expect(() => selectRuntime(c, { runtime: "host" })).toThrow(/not declared/);
    expect(() => selectRuntime(c, { runtime: "ssh:attacker.example" })).toThrow(/not declared/);
    expect(selectRuntime(c, { runtime: "h" })).toMatchObject({ name: "h", via: "call" });
  });
});

/** Start a node parent that calls runProc(argv) with a proc file; resolves once the record is written. */
async function parentWithChild(argv: string[], d: string) {
  const pf = join(d, "job-1.proc.json");
  const src = `import { runProc } from ${JSON.stringify(join(ROOT, "packages/runners/src/proc.ts"))};\nawait runProc({ argv: ${JSON.stringify(argv)}, procFile: ${JSON.stringify(pf)} });`;
  writeFileSync(join(d, "parent.mts"), src);
  // node itself, with the tsx loader: the tsx CLI would put a wrapper process between.
  const parent = spawn(process.execPath, ["--import", "tsx", join(d, "parent.mts")], { stdio: "ignore", cwd: ROOT });
  for (let i = 0; i < 200 && !existsSync(pf); i++) await sleep(25);
  const rec = JSON.parse(readFileSync(pf, "utf8")) as { pid: number; start: string; runnerPid: number };
  return { parent, pf, rec };
}

describe("processes of a dead runner", () => {
  it("SIGKILL of the node parent that called runProc takes the harness with it (pdeathsig, on runProc itself)", async () => {
    expect(PDEATHSIG_WRAPPER.length, "setpriv must exist on this host for the kill -9 fix").toBeGreaterThan(0);
    const d = tmp();
    const { parent, rec } = await parentWithChild(["sleep", "30"], d);
    expect(alive(rec.pid)).toBe(true);
    parent.kill("SIGKILL");
    for (let i = 0; i < 100 && alive(rec.pid); i++) await sleep(20);
    expect(alive(rec.pid)).toBe(false);
  });
  it("a grandchild left in the dead job's group is reaped (leader gone), by start time and job marker", async () => {
    const d = tmp();
    const gpid = join(d, "gpid");
    const { parent, rec } = await parentWithChild(["sh", "-c", `sleep 30 & echo $! > ${gpid}; wait`], d);
    for (let i = 0; i < 100 && !existsSync(gpid); i++) await sleep(20);
    const g = Number(readFileSync(gpid, "utf8"));
    // Wait for the parent to be reaped, so this test does not depend on the
    // zombie window (that case is pinned by successor-r3's zombie test).
    const exited = new Promise((r) => (parent.exitCode !== null || parent.signalCode !== null ? r(undefined) : parent.once("exit", r)));
    parent.kill("SIGKILL");
    await exited;
    for (let i = 0; i < 100 && alive(rec.pid); i++) await sleep(20);
    expect(alive(rec.pid)).toBe(false); // pdeathsig took the leader
    expect(alive(g)).toBe(true); // ... but not its child
    const lines = reapProcFiles(d);
    for (let i = 0; i < 100 && alive(g); i++) await sleep(20);
    expect(alive(g)).toBe(false);
    expect(lines.join("\n")).toMatch(/killed 1 process/);
    expect(existsSync(join(d, "job-1.proc.json"))).toBe(false);
  });
  it("a recorded pid now held by a stranger (another start time, no marker) is never killed", async () => {
    const d = tmp();
    // detached: the stranger leads its own group and session, like a reused pid would.
    const stranger = spawn("sleep", ["30"], { stdio: "ignore", detached: true });
    await sleep(100);
    const pid = stranger.pid!;
    writeFileSync(join(d, "old-1-a1.proc.json"), JSON.stringify({ pid, pgid: pid, start: "1", job: "old-1-a1", runnerPid: 999999, runnerStart: "1" }));
    const lines = reapProcFiles(d);
    await sleep(100);
    expect(alive(pid)).toBe(true);
    expect(lines.join("\n")).not.toMatch(/killed/);
    process.kill(pid, "SIGKILL");
  });
  it("a record with no start time is refused, never acted on", () => {
    const d = tmp();
    writeFileSync(join(d, "x.proc.json"), JSON.stringify({ pid: process.pid, pgid: process.pid, runnerPid: 999999 }));
    expect(reapProcFiles(d)).toEqual(["x: record has no start time; refused to kill anything"]);
  });
  it("a finished job leaves no proc file", async () => {
    const d = tmp();
    await runProc({ argv: ["true"], procFile: join(d, "f.proc.json") });
    expect(existsSync(join(d, "f.proc.json"))).toBe(false);
  });
});

describe("a detached helper holding the harness's stdout", () => {
  it("does not hold the call: the harness's exit 0 and output are kept, well before the timeout", async () => {
    const t0 = Date.now();
    const r = await runProc({ argv: ["sh", "-c", "echo Au; setsid sleep 20 & exit 0"], timeoutMs: 3000, drainGraceMs: 300 });
    expect(Date.now() - t0).toBeLessThan(2500);
    expect(r).toMatchObject({ exitCode: 0, timedOut: false });
    expect(r.stdout).toMatch(/^Au/);
  });
});

describe("remote and herdr jobs of a dead runner", () => {
  it("reapSshRecords kills the remote group of a record whose runner is gone, and forgets it", async () => {
    const d = tmp();
    const log = join(d, "ssh.log");
    const ssh = fakeBin(d, "ssh", `printf '%s\\n' "$*" >> ${log}`);
    const jobs = join(d, "jobs");
    mkdirSync(jobs);
    writeFileSync(join(jobs, "r-1-a1.ssh.json"), JSON.stringify({ host: "worker", ssh, id: "r-1-a1", runnerPid: 999999, runnerStart: "1" }));
    writeFileSync(join(jobs, "live.ssh.json"), JSON.stringify({ host: "worker", ssh, id: "live", runnerPid: process.pid, runnerStart: procStartTicks(process.pid) }));
    const lines = await reapSshRecords(jobs, -1);
    expect(lines).toEqual(["r-1-a1: ssh worker remote group killed"]);
    expect(readFileSync(log, "utf8")).toMatch(/worker -- test -s .*r-1-a1\.pid && kill -KILL/);
    expect(existsSync(join(jobs, "r-1-a1.ssh.json"))).toBe(false);
    expect(existsSync(join(jobs, "live.ssh.json"))).toBe(true);
  });
  it("herdr-job.mjs kills its job when the runner it names is gone", async () => {
    const d = tmp();
    const runner = spawn("sleep", ["30"], { stdio: "ignore" });
    await sleep(50);
    const marker = join(d, "side-effect");
    writeFileSync(join(d, ".herdr-stdin"), "");
    writeFileSync(join(d, "spec.json"), JSON.stringify({ argv: ["sh", "-c", `sleep 1.5; echo ran > ${marker}`], env: {}, jobDir: d, stdinFile: join(d, ".herdr-stdin"), timeoutMs: 10000, runnerPid: runner.pid, runnerStart: procStartTicks(runner.pid!), quiet: true }));
    const job = spawn(process.execPath, [ENTRY, join(d, "spec.json")], { stdio: "ignore" });
    const rc = new Promise<number | null>((r) => job.on("close", (c) => r(c)));
    await sleep(300);
    runner.kill("SIGKILL");
    await rc;
    await sleep(1600);
    expect(existsSync(marker)).toBe(false);
  });
  it("reapHerdrRecords closes the pane workspace a dead runner left open", async () => {
    const d = tmp();
    const socket = join(d, "h.sock");
    const seen: string[] = [];
    const server = createServer((s) => {
      let buf = "";
      s.on("data", (c) => {
        buf += c;
        const i = buf.indexOf("\n");
        if (i < 0) return;
        const req = JSON.parse(buf.slice(0, i)) as { id: unknown; method: string; params: { workspace_id?: string } };
        seen.push(`${req.method}:${req.params.workspace_id ?? ""}`);
        s.end(JSON.stringify({ id: req.id, result: {} }) + "\n");
      });
    });
    await new Promise<void>((r) => server.listen(socket, r));
    const jobs = join(d, "jobs");
    mkdirSync(join(jobs, "r-1-a1"), { recursive: true });
    writeFileSync(join(jobs, "r-1-a1.herdr.json"), JSON.stringify({ socket, jobDir: join(jobs, "r-1-a1"), workspace: "w1", runnerPid: 999999, runnerStart: "1" }));
    const lines = await reapHerdrRecords(jobs, -1);
    server.close();
    expect(seen).toEqual(["workspace.close:w1"]);
    expect(lines[0]).toMatch(/workspace w1 closed/);
    expect(existsSync(join(jobs, "r-1-a1.herdr.json"))).toBe(false);
  });
});

describe("herdr pane mode: a socket drop after pane.send_input", () => {
  it("is an outcome followed through the job dir, not a refusal; the job runs once", async () => {
    const d = tmp();
    const socket = join(d, "h.sock");
    const jobDir = join(d, "jobs", "p-1");
    mkdirSync(jobDir, { recursive: true });
    const server = createServer((s) => {
      let buf = "";
      s.on("data", (c) => {
        buf += c;
        const i = buf.indexOf("\n");
        if (i < 0) return;
        const req = JSON.parse(buf.slice(0, i)) as { id: unknown; method: string; params: { text?: string } };
        const ok = (result: unknown) => s.end(JSON.stringify({ id: req.id, result }) + "\n");
        if (req.method === "workspace.create") return ok({ workspace: { workspace_id: "w1" }, root_pane: { pane_id: "w1:p1" } });
        if (req.method === "pane.send_input") {
          spawn("sh", ["-c", req.params.text!], { cwd: jobDir, stdio: "ignore", detached: true });
          return ok({});
        }
        s.destroy(); // the drop: wait_for_output and workspace.close get no answer
      });
    });
    await new Promise<void>((r) => server.listen(socket, r));
    const log = join(d, "runs.log");
    const res = await herdrRunner("herdr", { socket, mode: "pane" }).run({ kind: "process", id: "p-1", argv: ["sh", "-c", `echo attempt >> ${log}; sleep 0.5; echo done; exit 3`], jobDir, timeoutMs: 5000 });
    server.close();
    expect(isRefusal(res)).toBe(false);
    expect((res as RunOutcome).exitCode).toBe(3);
    expect((res as RunOutcome).stdout).toMatch(/done/);
    expect(readFileSync(log, "utf8").trim().split("\n")).toHaveLength(1);
  });
});
