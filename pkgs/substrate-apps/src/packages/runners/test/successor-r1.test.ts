/**
 * Successor review, fix round 1 (2026-09-23), runners half. Fake binaries and
 * fake sockets only; no seat, no real herdr, no real remote host.
 *  - a call's runtime cannot escape the file's sandbox;
 *  - a job's planted symlinks are never followed (receipt, microvm outputs);
 *  - a sandboxed job sees only the seat credential, not the whole config dir;
 *  - runProc records its group; ssh kills the remote group on timeout;
 *  - herdr: a dropped invoke is followed, not refused; stale rc files are cleared.
 */
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { credentialMounts, RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml, selectRuntime } from "../src/config.ts";
import { ENTRY, herdrRunner } from "../src/herdr.ts";
import { isRefusal, type Job, type ProcessJob, type RunOutcome, type Runner, type RunResult } from "../src/job.ts";
import { readJobFile } from "../src/microvm.ts";
import { liveGroups, PDEATHSIG_WRAPPER, runProc } from "../src/proc.ts";
import { sshRunner } from "../src/ssh.ts";
import { fakeBin, tmp } from "./helpers.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

describe("runtime confinement: agent({runtime}) cannot leave the file's sandbox", () => {
  const gv = `default = "gvisor"\n[phases]\n"Review" = "gvisor"\n[runtime.gvisor]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`;
  it("a gvisor default refuses a call naming host or ssh:<any host>", () => {
    const c = parseRuntimesToml(gv, "t", "/home/u");
    expect(() => selectRuntime(c, { runtime: "host" })).toThrow(/refused/);
    expect(() => selectRuntime(c, { runtime: "ssh:nas" })).toThrow(/refused/);
    expect(() => selectRuntime(c, { runtime: "host", phase: "Review" })).toThrow(/refused/);
    expect(selectRuntime(c, { runtime: "gvisor" })).toMatchObject({ name: "gvisor", via: "call" });
  });
  it("a declared host table is still no escape from a sandboxed default", () => {
    const c = parseRuntimesToml(`${gv}[runtime.h]\ntype = "host"\n`, "t", "/home/u");
    expect(() => selectRuntime(c, { runtime: "h" })).toThrow(/may not leave the sandboxed default/);
  });
  it("allow = [...] is the one way to permit it, and anything off the list is refused", () => {
    const c = parseRuntimesToml(`allow = ["host"]\n${gv}`, "t", "/home/u");
    expect(selectRuntime(c, { runtime: "host" })).toMatchObject({ name: "host", via: "call" });
    expect(() => selectRuntime(c, { runtime: "ssh:nas" })).toThrow(/allow list/);
  });
  it("a host default keeps the built-ins open to a call", () => {
    const c = parseRuntimesToml(``, "t", "/home/u");
    expect(selectRuntime(c, { runtime: "ssh:nas" })).toMatchObject({ name: "ssh:nas", via: "call" });
  });
});

/** A runner whose "job" plants a symlink in its job dir, then succeeds. */
function planter(link: string, target: string): Runner {
  return {
    name: "gv",
    type: "gvisor",
    refuses: () => undefined,
    run: async (j: Job): Promise<RunResult> => {
      symlinkSync(target, join((j as ProcessJob).jobDir, link));
      return { runtime: "gv", jobId: j.id, exitCode: 0, stdout: '{"type":"result","subtype":"success","is_error":false,"result":"ok"}', stderr: "", durationMs: 1 };
    },
  };
}

describe("the job dir is hostile once the job starts", () => {
  const cfg = (cred: string) => parseRuntimesToml(`default = "gv"\n[credentials]\nclaude = "${cred}"\nscope = "dir"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n`, "t", "/home/u");
  it("a planted receipt.json symlink is never written through; the outcome is not trusted", async () => {
    const d = tmp();
    const victim = join(d, "victim.txt");
    writeFileSync(victim, "untouched");
    const jobsRoot = join(d, "jobs");
    const b = new RunnerBackend(cfg(d), { jobsRoot, runId: "r", runners: { gv: planter("receipt.json", victim) } });
    const out = await b.run({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1 });
    expect(readFileSync(victim, "utf8")).toBe("untouched");
    expect(out.error).toMatch(/planted receipt\.json/);
    expect(JSON.parse(readFileSync(join(jobsRoot, "r-1-a1.receipt.json"), "utf8")).hostile).toMatch(/already existed/);
  });
  it("an existing job dir is refused, never reused", async () => {
    const d = tmp();
    const jobsRoot = join(d, "jobs");
    mkdirSync(join(jobsRoot, "r-1-a1"), { recursive: true });
    const b = new RunnerBackend(cfg(d), { jobsRoot, runId: "r", runners: { gv: planter("x", "/") } });
    expect((await b.run({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1 })).error).toMatch(/already exists/);
  });
  it("a later start of the same run gets its own job ids", async () => {
    const d = tmp();
    const jobsRoot = join(d, "jobs");
    const b = new RunnerBackend(cfg(d), { jobsRoot, runId: "r", start: 2, runners: { gv: planter("x", "/") } });
    await b.run({ index: 1, key: "k", prompt: "p", opts: {}, phase: undefined, attempt: 1 });
    expect(existsSync(join(jobsRoot, "r-s2-1-a1"))).toBe(true);
  });
  it("microvm outputs are read without following links, regular files only", () => {
    const d = tmp();
    writeFileSync(join(d, "secret"), "host-only bytes");
    symlinkSync(join(d, "secret"), join(d, "stdout"));
    writeFileSync(join(d, "stderr"), "real");
    expect(readJobFile(join(d, "stdout"))).not.toContain("host-only bytes");
    expect(readJobFile(join(d, "stdout"))).toMatch(/refused.*symlink/);
    expect(readJobFile(join(d, "stderr"))).toBe("real");
    expect(readJobFile(join(d, "absent"))).toBe("");
  });
});

describe("the seat mount of a sandboxed job is the credential only", () => {
  const cfgFor = (cred: string, extra = "") =>
    parseRuntimesToml(`default = "gv"\n[credentials]\nclaude = "${cred}"\n${extra}[runtime.gv]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\n[runtime.vm]\ntype = "microvm"\n`, "t", "/home/u");
  it("gvisor: a scratch config dir plus the credential file; the config dir itself is never bound", () => {
    const d = tmp();
    const seat = join(d, "seat");
    mkdirSync(seat);
    writeFileSync(join(seat, ".credentials.json"), "{}");
    writeFileSync(join(seat, "settings.json"), "{}");
    const c = cfgFor(seat);
    const m = credentialMounts(c, c.runtimes["gv"]!, "claude", join(d, "shadow"));
    expect(Array.isArray(m)).toBe(true);
    const mounts = m as { source: string; target: string; mode: string }[];
    expect(mounts.some((x) => x.source === seat)).toBe(false);
    expect(mounts[0]).toMatchObject({ source: join(d, "shadow"), target: "/home/agent/.claude", mode: "rw" });
    expect(mounts[1]).toMatchObject({ source: join(seat, ".credentials.json"), target: "/home/agent/.claude/.credentials.json", mode: "rw" });
  });
  it("microvm: the shared dir holds only a link to the credential", () => {
    const d = tmp();
    const seat = join(d, "seat");
    mkdirSync(seat);
    writeFileSync(join(seat, ".credentials.json"), "{}");
    const c = cfgFor(seat);
    const mounts = credentialMounts(c, c.runtimes["vm"]!, "claude", join(d, "shadow")) as { source: string }[];
    expect(mounts).toHaveLength(1);
    expect(mounts[0]!.source).toBe(join(d, "shadow"));
    expect(statSync(join(d, "shadow", ".credentials.json")).ino).toBe(statSync(join(seat, ".credentials.json")).ino);
  });
  it('scope = "dir" keeps the 09-21 whole-dir mount; a missing credential is refused', () => {
    const d = tmp();
    const c = cfgFor(d, `scope = "dir"\n`);
    expect(credentialMounts(c, c.runtimes["gv"]!, "claude", join(d, "s"))).toEqual([{ source: d, target: "/home/agent/.claude", mode: "rw", purpose: "credential" }]);
    const c2 = cfgFor(join(d, "none"));
    expect(credentialMounts(c2, c2.runtimes["gv"]!, "claude", join(d, "s"))).toMatchObject({ refused: /no seat credential/ });
  });
});

describe("processes: recorded, and killed with their runner", () => {
  it("runProc wraps the child in pdeathsig when setpriv exists, writes its proc file and tracks the group", async () => {
    const d = tmp();
    const pf = join(d, "p.json");
    const p = runProc({ argv: ["sleep", "0.3"], procFile: pf });
    await sleep(100);
    const rec = JSON.parse(readFileSync(pf, "utf8")) as { pid: number; runnerPid: number };
    expect(rec.runnerPid).toBe(process.pid);
    expect(liveGroups.has(rec.pid)).toBe(true);
    await p;
    expect(liveGroups.has(rec.pid)).toBe(false);
    expect(existsSync(pf)).toBe(false); // removed once the child exited (successor review r2)
  });
  it("a SIGKILLed parent takes its runProc child with it (pdeathsig)", async () => {
    if (PDEATHSIG_WRAPPER.length === 0) return;
    const d = tmp();
    // The parent is a shell that starts the wrapped child exactly as runProc does, then is killed -9.
    const parent = spawn("sh", ["-c", `${PDEATHSIG_WRAPPER.join(" ")} sleep 30 & echo $! > ${d}/pid; wait`], { stdio: "ignore" });
    for (let i = 0; i < 50 && !existsSync(join(d, "pid")); i++) await sleep(20);
    const pid = Number(readFileSync(join(d, "pid"), "utf8"));
    expect(alive(pid)).toBe(true);
    parent.kill("SIGKILL");
    for (let i = 0; i < 50 && alive(pid); i++) await sleep(20);
    expect(alive(pid)).toBe(false);
  });
});

describe("ssh: a timeout kills the remote job, not only the local client", () => {
  it("the remote group is killed over a second ssh; the job never finishes", async () => {
    const d = tmp();
    // A fake ssh that runs the remote command locally, in $d as the remote $HOME.
    // Like a real ssh client, it alone holds the local pipes: the "remote" side
    // writes to a file the client relays, so killing the client closes them.
    const ssh = fakeBin(d, "ssh", `for last; do :; done; cd ${d}; sh -c "$last" > ${d}/remote.out 2>&1 < /dev/null & wait $!; rc=$?; cat ${d}/remote.out; exit $rc`);
    const marker = join(d, "marker");
    const r = await sshRunner("ssh:fake", { host: "fake", ssh }).run(
      { kind: "process", id: "j1", argv: ["sh", "-c", `sleep 1.5; echo remote-still-ran >> ${marker}`], jobDir: d, timeoutMs: 400 },
    );
    const o = r as RunOutcome;
    expect(o.timedOut).toBe(true);
    expect(o.detail?.remoteKill).toBe("remote group killed");
    await sleep(2000);
    expect(existsSync(marker)).toBe(false);
  });
});

/** A fake herdr whose invoke spawns the real job entry, then answers per `mode`. */
function herdrFake(socket: string, mode: "drop" | "evicted") {
  let n = 0;
  const server = createServer((s) => {
    let buf = "";
    s.on("data", (c) => {
      buf += c;
      const i = buf.indexOf("\n");
      if (i < 0) return;
      const req = JSON.parse(buf.slice(0, i)) as { id: string; method: string; params: { context: unknown } };
      if (req.method === "plugin.action.list") return void s.end(JSON.stringify({ id: req.id, result: { actions: [{ action_id: "job" }] } }) + "\n");
      if (req.method === "plugin.action.invoke") {
        spawn(process.execPath, [ENTRY], { env: { ...process.env, HERDR_PLUGIN_CONTEXT_JSON: JSON.stringify(req.params.context) }, stdio: "ignore" });
        if (mode === "drop") return void s.destroy();
        return void s.end(JSON.stringify({ id: req.id, result: { log: { log_id: `L${++n}` } } }) + "\n");
      }
      s.end(JSON.stringify({ id: req.id, result: { logs: [] } }) + "\n"); // evicted: our entry is never listed
    });
  });
  return new Promise<typeof server>((r) => server.listen(socket, () => r(server)));
}

describe("herdr action mode", () => {
  it("a socket dropped after the invoke started the job is followed to its rc, fast, not refused", async () => {
    const d = tmp();
    const server = await herdrFake(join(d, "h.sock"), "drop");
    const jobDir = join(d, "job");
    mkdirSync(jobDir);
    const t0 = Date.now();
    const res = await herdrRunner("herdr", { socket: join(d, "h.sock"), pollMs: 20 }).run({ kind: "process", id: "j", argv: ["sh", "-c", "echo job-ran; exit 3"], jobDir });
    server.close();
    expect(isRefusal(res)).toBe(false);
    expect((res as RunOutcome).exitCode).toBe(3);
    expect((res as RunOutcome).stdout).toContain("job-ran");
    expect(Date.now() - t0).toBeLessThan(8000);
  });
  it("a stale .herdr-rc from an earlier start is not this invocation's exit code", async () => {
    const d = tmp();
    const server = await herdrFake(join(d, "h.sock"), "evicted");
    const jobDir = join(d, "job");
    mkdirSync(jobDir);
    writeFileSync(join(jobDir, ".herdr-rc"), "0");
    writeFileSync(join(jobDir, ".herdr-pid"), "999999");
    const res = (await herdrRunner("herdr", { socket: join(d, "h.sock"), pollMs: 20 }).run({ kind: "process", id: "j", argv: ["sh", "-c", "sleep 0.5; echo fresh; exit 5"], jobDir })) as RunOutcome;
    server.close();
    expect(res.exitCode).toBe(5);
    expect(res.stdout).toContain("fresh");
  });
});

