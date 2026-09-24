/**
 * Critique pass 2026-09-24 (AUDIT-runners-guardrails): seat-bound credentials
 * (RG-1), seat routing (RG-2), runtime `locked` (RG-4), read-only desk context
 * (RG-5), the receipt's session id and answering model (RG-6), per-call
 * timeouts, codex's sandbox mode and the output cap. Every harness here is a
 * recording fake runner or a fake binary: nothing real is spent.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RunnerBackend } from "../src/backend.ts";
import { credentialDirFor, parseRuntimesToml, selectForCall, type RuntimesConfig } from "../src/config.ts";
import { codexInvocation, parseClaude, parseCodex } from "../src/harness.ts";
import type { Job, ProcessJob, Runner } from "../src/job.ts";
import { runProc } from "../src/proc.ts";
import { tmp } from "./helpers.ts";

const ENVELOPE = JSON.stringify({ type: "result", subtype: "success", is_error: false, result: "ok", session_id: "sess-1", usage: { input_tokens: 1, output_tokens: 1 }, modelUsage: { "claude-opus-5-5": { inputTokens: 1 }, "claude-haiku-4-5": { inputTokens: 1 } } });
const CODEX_OUT = ['{"type":"thread.started","thread_id":"th-9"}', '{"type":"item.completed","item":{"type":"agent_message","text":"42"}}', '{"type":"turn.completed","usage":{"input_tokens":3,"output_tokens":2}}'].join("\n");

/** A runner that records every job and answers like the harness named in argv[0]. */
function recorder(name: string, type = "host"): Runner & { jobs: ProcessJob[] } {
  const jobs: ProcessJob[] = [];
  return {
    name, type, jobs,
    refuses: () => undefined,
    run: async (job: Job) => {
      const j = job as ProcessJob;
      jobs.push(j);
      const out = j.argv[0] === "codex" ? CODEX_OUT : j.argv[0] === "pi" ? "Au" : ENVELOPE;
      return { runtime: name, jobId: j.id, exitCode: 0, stdout: out, stderr: "", durationMs: 1 };
    },
  };
}

/** The live prove/runtimes.toml shape (three host runtimes, seats cc2/halogen/codex) plus `extra`. */
const PROVE = `default = "opus"
allow = ["opus", "halogen", "codex"]
[seats]
claude = "cc2"
pi = "halogen"
codex = "codex"
[runtime.opus]
type = "host"
harness = "claude"
seat = "cc2"
timeoutMs = 900000
[runtime.halogen]
type = "host"
harness = "pi"
seat = "halogen"
timeoutMs = 1800000
[runtime.codex]
type = "host"
harness = "codex"
seat = "codex"
timeoutMs = 900000
`;

const seatDirs = () => {
  const home = tmp("axc-guard-home-");
  for (const d of [".claude", ".claude-work"]) {
    mkdirSync(join(home, d));
    writeFileSync(join(home, d, ".credentials.json"), "{}\n", { mode: 0o600 });
  }
  return home;
};

const backendFor = (config: RuntimesConfig, runners: Record<string, Runner>, defaultSeat?: string) => {
  const root = tmp();
  return {
    root,
    b: new RunnerBackend(config, { jobsRoot: join(root, "jobs"), runId: "g", seatShadowRoot: join(root, "shadows"), runners, ...(defaultSeat ? { defaultSeat } : {}) }),
  };
};
let n = 0;
const call = (opts: Record<string, unknown>, prompt = "p") => ({ index: ++n, key: `k${n}`, prompt, opts, phase: undefined, attempt: 1 });
const receiptOf = (root: string, i: number) => JSON.parse(readFileSync(join(root, "jobs", `g-${i}-a1`, "receipt.json"), "utf8")) as Record<string, unknown>;

describe("RG-1: a claude job spends the dir of the seat it is gated on", () => {
  it("the live prove shape (seat cc2, no [credentials]) is refused at load, naming the missing binding", () => {
    expect(() => parseRuntimesToml(PROVE, "prove", "/home/u")).toThrow(/runtime\.opus: seat cc2 is bound to no Claude config dir: declare \[credentials\.seats\] cc2/);
  });

  it("with [credentials.seats] cc2 = ~/.claude-work the job's CLAUDE_CONFIG_DIR and mount are ~/.claude-work, and the receipt says so", async () => {
    const home = seatDirs();
    const c = parseRuntimesToml(`${PROVE}[credentials.seats]\ncc = "~/.claude"\ncc2 = "~/.claude-work"\n`, "prove", home);
    const opus = recorder("opus");
    const { b, root } = backendFor(c, { opus }, "cc2");
    const x = call({});
    expect(await b.run(x)).toMatchObject({ text: "ok" });
    expect(opus.jobs[0]!.env?.CLAUDE_CONFIG_DIR).toBe(join(home, ".claude-work"));
    expect(opus.jobs[0]!.mounts).toEqual([{ source: join(home, ".claude-work"), target: join(home, ".claude-work"), mode: "rw", purpose: "credential" }]);
    expect(receiptOf(root, x.index)).toMatchObject({ seat: "cc2", credentialDir: join(home, ".claude-work") });
  });

  it("a seat missing from a declared map is refused at load; an explicit [credentials].claude serves one bound seat only", () => {
    expect(() => parseRuntimesToml(`${PROVE}[credentials.seats]\ncc = "~/.claude"\n`, "t", "/home/u")).toThrow(/seat cc2 has no Claude config dir in \[credentials\.seats\] \(declared: cc\)/);
    const one = parseRuntimesToml(`${PROVE}[credentials]\nclaude = "~/.claude-work"\n`, "t", "/home/u");
    expect(credentialDirFor(one, "cc2")).toEqual({ dir: "/home/u/.claude-work" });
    const two = `${PROVE}[runtime.opus2]\ntype = "host"\nseat = "cc"\n[credentials]\nclaude = "~/.claude"\n`;
    expect(() => parseRuntimesToml(two, "t", "/home/u")).toThrow(/binds 2 claude seats \(cc2, cc\); declare \[credentials\.seats\]/);
  });

  it("the run's --seat with no map keeps the default dir, and the receipt marks the binding unverified", async () => {
    const home = seatDirs();
    const c = parseRuntimesToml("", "t", home);
    const host = recorder("host");
    const { b, root } = backendFor(c, { host }, "cc");
    const x = call({});
    await b.run(x);
    expect(host.jobs[0]!.env?.CLAUDE_CONFIG_DIR).toBe(join(home, ".claude"));
    expect(receiptOf(root, x.index)).toMatchObject({ seat: "cc", credentialBinding: expect.stringMatching(/^unverified/) });
  });

  it("on gVisor only the SEAT's credential file is bound into the shadow", async () => {
    const home = seatDirs();
    const c = parseRuntimesToml(`default = "gv"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/x/runsc"\nseat = "cc2"\n[credentials.seats]\ncc2 = "~/.claude-work"\n`, "t", home);
    const gv = recorder("gv", "gvisor");
    const { b } = backendFor(c, { gv });
    await b.run(call({}));
    const creds = gv.jobs[0]!.mounts!.filter((m) => m.purpose === "credential").map((m) => m.source);
    expect(creds).toContain(join(home, ".claude-work", ".credentials.json"));
    expect(creds.some((s) => s.startsWith(join(home, ".claude") + "/"))).toBe(false);
    expect(gv.jobs[0]!.env?.CLAUDE_CONFIG_DIR).toBe("/home/agent/.claude");
  });
});

describe("RG-2: a seat is honoured or refused, never dropped (seat routing)", () => {
  const home = seatDirs();
  const c = parseRuntimesToml(`${PROVE}[credentials.seats]\ncc2 = "~/.claude-work"\n`, "prove", home);

  it("seat:codex runs codex exec, seat:halogen runs pi, seat:cc2 runs claude -p; each on the runtime that spends it", async () => {
    const opus = recorder("opus"), halogen = recorder("halogen"), codex = recorder("codex");
    const { b, root } = backendFor(c, { opus, halogen, codex }, "cc2");
    const a = call({ seat: "codex" }), h = call({ runsOn: ["seat:halogen"] }), o = call({ seat: "cc2" });
    expect(await b.run(a)).toMatchObject({ text: "42", agentId: "th-9" });
    expect(await b.run(h)).toMatchObject({ text: "Au" });
    expect(await b.run(o)).toMatchObject({ text: "ok" });
    expect(codex.jobs.map((j) => j.argv.slice(0, 2))).toEqual([["codex", "exec"]]);
    expect(halogen.jobs.map((j) => j.argv.slice(0, 2))).toEqual([["pi", "-p"]]);
    expect(opus.jobs.map((j) => j.argv.slice(0, 2))).toEqual([["claude", "-p"]]);
    // No Claude wrapper and no Claude credential around codex or pi.
    for (const j of [...codex.jobs, ...halogen.jobs]) {
      expect(j.mounts ?? []).toEqual([]);
      expect(j.env?.CLAUDE_CONFIG_DIR).toBeUndefined();
    }
    expect(receiptOf(root, a.index)).toMatchObject({ runtime: "codex", via: "seat", seat: "codex", sessionId: "th-9" });
    expect(receiptOf(root, o.index)).toMatchObject({ runtime: "opus", via: "default", seat: "cc2" });
    // The capacity gate reads the same route.
    expect(b.route({ opts: { seat: "codex" }, phase: undefined })).toMatchObject({ harness: "codex", seat: "codex" });
    expect(b.route({ opts: { runsOn: ["seat:halogen"] }, phase: undefined })).toMatchObject({ harness: "pi", seat: "halogen" });
  });

  it("an unserved seat, a foreign label, a contradiction and an ambiguous seat are refused before anything runs", async () => {
    const opus = recorder("opus");
    const { b } = backendFor(c, { opus }, "cc2");
    expect((await b.run(call({ seat: "cc" }))).error).toMatch(/no runtime this file permits the call spends seat cc \(runtime=seat: opus=cc2, halogen=halogen, codex=codex\)/);
    expect((await b.run(call({ runsOn: ["gpu:1"] }))).error).toMatch(/neither seat:<id> nor runtime:<name>/);
    expect((await b.run(call({ runtime: "codex", seat: "halogen" }))).error).toMatch(/runtime codex spends seat codex, not halogen/);
    expect((await b.run(call({ runsOn: ["runtime:codex", "runtime:opus"] }))).error).toMatch(/contradicts/);
    expect(opus.jobs).toHaveLength(0);
    const two = parseRuntimesToml(`${PROVE}[runtime.halogen2]\ntype = "host"\nharness = "pi"\nseat = "halogen"\n[credentials.seats]\ncc2 = "~/.claude-work"\n`.replace(`allow = ["opus", "halogen", "codex"]`, `allow = ["opus", "halogen", "halogen2", "codex"]`), "t", home);
    expect(() => selectForCall(two, { seat: "halogen" }, "cc2")).toThrow(/seat halogen is spent by 2 permitted runtimes \(halogen, halogen2\)/);
  });

  it("a seat never escapes the confinement rules: a sandboxed default cannot be left for a host runtime by naming its seat", () => {
    const g = parseRuntimesToml(`default = "gv"\n[seats]\npi = "halogen"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/x/runsc"\nharness = "claude"\nseat = "cc2"\n[runtime.hp]\ntype = "host"\nharness = "pi"\n[credentials.seats]\ncc2 = "~/.claude-work"\n`, "t", home);
    expect(() => selectForCall(g, { seat: "halogen" })).toThrow(/no runtime this file permits the call spends seat halogen/);
  });
});

describe("RG-4: runtime locked carries no seat credential", () => {
  const home = seatDirs();
  const LOCKED = `[runtime.locked]\ntype = "gvisor"\nrunsc = "/x/runsc"\nharness = "pi"\ncredential = false\nnetwork = "isolated"\n`;

  it("runs-on runtime:locked reaches it past the allow list, and the job gets no credential and no CLAUDE_CONFIG_DIR", async () => {
    const c = parseRuntimesToml(`${PROVE}[credentials.seats]\ncc2 = "~/.claude-work"\n${LOCKED}`, "t", home);
    const locked = recorder("locked", "gvisor");
    const { b } = backendFor(c, { locked }, "cc2");
    expect(await b.run(call({ runsOn: ["runtime:locked"] }))).toMatchObject({ text: "Au" });
    expect((locked.jobs[0]!.mounts ?? []).filter((m) => m.purpose === "credential")).toEqual([]);
    expect(locked.jobs[0]!.env?.CLAUDE_CONFIG_DIR).toBeUndefined();
  });

  it("the reserved name refuses any other shape, and credential = false refuses the claude harness", () => {
    expect(() => parseRuntimesToml(`[runtime.locked]\ntype = "host"\nharness = "pi"\n`, "t", home)).toThrow(/runtime\.locked must be type = "gvisor"/);
    expect(() => parseRuntimesToml(`[runtime.locked]\ntype = "gvisor"\nrunsc = "/x/runsc"\nharness = "pi"\n`, "t", home)).toThrow(/runtime\.locked must set credential = false/);
    expect(() => parseRuntimesToml(`[runtime.locked]\ntype = "gvisor"\nrunsc = "/x/runsc"\nharness = "pi"\ncredential = false\nnetwork = "host"\n`, "t", home)).toThrow(/must not use network = "host"/);
    expect(() => parseRuntimesToml(`[runtime.lk]\ntype = "gvisor"\nrunsc = "/x/runsc"\ncredential = false\n`, "t", home)).toThrow(/credential = false with the claude harness/);
  });
});

describe("RG-5: desk context is bound read-only into gVisor jobs", () => {
  it("CLAUDE.md, skills and the runtime rules land ro in the job's config dir; a missing entry refuses the job", async () => {
    const home = seatDirs();
    writeFileSync(join(home, "CLAUDE.md"), "# desk\n");
    mkdirSync(join(home, "skills"));
    writeFileSync(join(home, "agent-runtime-rules.md"), "rules\n");
    const toml = (ctx: string) => `default = "gv"\n[runtime.gv]\ntype = "gvisor"\nrunsc = "/x/runsc"\nseat = "cc2"\n[credentials]\ncontext = [${ctx}]\n[credentials.seats]\ncc2 = "~/.claude-work"\n`;
    const c = parseRuntimesToml(toml(`"~/CLAUDE.md", "~/skills", "~/agent-runtime-rules.md"`), "t", home);
    const gv = recorder("gv", "gvisor");
    const { b, root } = backendFor(c, { gv });
    const x = call({});
    await b.run(x);
    const ro = gv.jobs[0]!.mounts!.filter((m) => m.mode === "ro" && m.purpose === "other");
    expect(ro.map((m) => [m.source, m.target])).toEqual([
      [join(home, "CLAUDE.md"), "/home/agent/.claude/CLAUDE.md"],
      [join(home, "skills"), "/home/agent/.claude/skills"],
      [join(home, "agent-runtime-rules.md"), "/home/agent/.claude/agent-runtime-rules.md"],
    ]);
    expect(receiptOf(root, x.index).context).toEqual(ro.map((m) => m.source));
    const missing = parseRuntimesToml(toml(`"~/nope.md"`), "t", home);
    const { b: b2 } = backendFor(missing, { gv: recorder("gv", "gvisor") });
    expect((await b2.run(call({}))).error).toMatch(/desk context .*nope\.md .* does not exist/);
    expect(() => parseRuntimesToml(toml(`"~/a/CLAUDE.md", "~/b/CLAUDE.md"`), "t", home)).toThrow(/two entries named CLAUDE\.md/);
  });
});

describe("RG-6: the receipt carries the session id and the model that answered", () => {
  it("claude modelUsage keys become answeringModel; codex thread_id becomes sessionId", async () => {
    expect(parseClaude(ENVELOPE, false)).toMatchObject({ agentId: "sess-1", answeringModel: "claude-haiku-4-5,claude-opus-5-5" });
    expect(parseCodex(CODEX_OUT, false)).toMatchObject({ agentId: "th-9", text: "42" });
    const home = seatDirs();
    const c = parseRuntimesToml(`${PROVE}[credentials.seats]\ncc2 = "~/.claude-work"\n`, "t", home);
    const opus = recorder("opus");
    const { b, root } = backendFor(c, { opus }, "cc2");
    const x = call({});
    const out = await b.run(x);
    expect(out).not.toHaveProperty("answeringModel"); // the interpreter's outcome shape is unchanged
    expect(receiptOf(root, x.index)).toMatchObject({ sessionId: "sess-1", answeringModel: "claude-haiku-4-5,claude-opus-5-5", argv: expect.arrayContaining(["--model", "claude-opus-5-5"]) });
  });
});

describe("limits: per-call timeouts, codex sandbox, the output cap", () => {
  const home = seatDirs();
  const c = parseRuntimesToml(`${PROVE}[credentials.seats]\ncc2 = "~/.claude-work"\n`, "t", home);

  it("a call may shorten its runtime's wall clock, never extend it", async () => {
    const opus = recorder("opus");
    const { b } = backendFor(c, { opus }, "cc2");
    await b.run(call({ timeoutMs: 60_000 }));
    expect(opus.jobs[0]!.timeoutMs).toBe(60_000);
    expect((await b.run(call({ timeoutMs: 900_001 }))).error).toMatch(/exceeds runtime opus's ceiling of 900000 ms/);
    expect((await b.run(call({ timeoutMs: "1m" }))).error).toMatch(/positive integer/);
    expect(opus.jobs).toHaveLength(1);
  });

  it("codexSandbox = workspace-write reaches codex's argv; read-only stays the default; only a codex table may carry it", async () => {
    expect(codexInvocation({ prompt: "x" }).argv).toContain("read-only");
    const w = parseRuntimesToml(`${PROVE}codexSandbox = "workspace-write"\n[credentials.seats]\ncc2 = "~/.claude-work"\n`, "t", home);
    const codex = recorder("codex");
    const { b } = backendFor(w, { codex }, "cc2");
    await b.run(call({ runtime: "codex" }));
    expect(codex.jobs[0]!.argv.join(" ")).toContain("--sandbox workspace-write");
    expect(() => parseRuntimesToml(`[runtime.o]\ntype = "host"\ncodexSandbox = "workspace-write"\n`, "t", home)).toThrow(/codexSandbox applies to the codex harness only/);
  });

  it("output above the cap is dropped and marked, at a small cap and at the 16 MiB default", async () => {
    const small = await runProc({ argv: ["sh", "-c", "head -c 5000 /dev/zero | tr '\\0' a"], env: process.env, maxBytes: 1024, timeoutMs: 20_000 });
    expect(small.stdout.startsWith("a".repeat(1024) + "\n[runner: stdout truncated at 1024 of 5000 bytes]")).toBe(true);
    const big = 16 * 1024 * 1024 + 10;
    const dflt = await runProc({ argv: ["sh", "-c", `head -c ${big} /dev/zero | tr '\\0' b`], env: process.env, timeoutMs: 60_000 });
    expect(dflt.stdout.endsWith(`[runner: stdout truncated at ${16 * 1024 * 1024} of ${big} bytes]`)).toBe(true);
  }, 90_000);
});
