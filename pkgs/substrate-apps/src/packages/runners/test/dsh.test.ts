import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RunnerBackend } from "../src/backend.ts";
import { parseRuntimesToml } from "../src/config.ts";
import { dshInvocation, parseDsh } from "../src/harness.ts";
import { dshPatch } from "../src/dsh.ts";
import type { ProcessJob, Runner } from "../src/job.ts";
import { tmp } from "./helpers.ts";

const ID = "session-11111111-2222-4333-8444-555555555555";
const events = (...rows: unknown[]) => rows.map(r => JSON.stringify(r)).join("\n") + "\n";
const stream = (text = '{"ok":true}') => events({ type: "session", sessionId: ID },
  { type: "status", phase: "step_end", usage: { inputTokens: 11, outputTokens: 3, cacheReadTokens: 5 } },
  { type: "status", phase: "turn_end", reason: { kind: "completed" } }, { type: "final", text });
const session = { id: ID, resume: true, mcp: { command: "/opt/project", env: { PROJECT_ROLE: "coordinator" } }, mcpConfig: "/state/mcp.json", tools: ["read"] };

describe("native DSH headless", () => {
  it("uses the real headless flags and a patch, with prompts on stdin", () => {
    const inv = dshInvocation({ prompt: "private prompt", dshHome: "/state/dsh", dshPatch: "/state/dsh.json", session });
    expect(inv.argv).toEqual(["dsh", "--profile", "headless", "--patch", "/state/dsh.json", "--json", "--session-id", ID, "-"]);
    expect(inv.argv.join(" ")).not.toContain("private prompt");
    expect(inv.stdin).toBe("private prompt");
    expect(dshInvocation({ prompt: "fresh", dshHome: "/s", dshPatch: "/p", session: { ...session, resume: false } }).argv).not.toContain("--session-id");
  });
  it("takes only the lossless final event, aggregates step usage and keeps failure spend", () => {
    expect(parseDsh(stream(), true)).toMatchObject({ object: { ok: true }, agentId: ID, usage: { inputTokens: 11, outputTokens: 3, cacheReadTokens: 5 } });
    const failed = stream() + events({ type: "status", phase: "step_end", usage: { inputTokens: 2, outputTokens: 1 } }, { type: "error", message: "provider unavailable" });
    expect(parseDsh(failed, false)).toMatchObject({ agentId: ID, usage: { inputTokens: 13, outputTokens: 4 }, error: "dsh reported a failure: provider unavailable" });
    expect(parseDsh(events({ type: "session", sessionId: ID }, { type: "text", text: "partial" }), false).error).toMatch(/no final/);
    expect(parseDsh(events({ type: "session", sessionId: ID }, { type: "status", phase: "turn_end", reason: { kind: "error" } }, { type: "final", text: "" }), false).error).toMatch(/turn ended/);
  });
  it("selects Gufo by model and role without a pi agent directory", () => {
    const rows = JSON.parse(dshPatch("/state/dsh", "qwen3.8-flash-next", "off", session));
    expect(rows).toContainEqual({ id: "agent-default-model", config: { provider: "gufo", model: "qwen3.8-flash-next" } });
    expect(rows.find((r: any) => r.insert)?.insert[0].config).toMatchObject({ transport: "stdio", serverName: "project", command: "/opt/project", args: ["mcp"], failOnStartupError: true });
    expect(rows).toContainEqual({ id: "tool-fs", config: { read: true, readImage: false, write: false, edit: false } });
    expect(rows).toContainEqual({ id: "tool-bash", disabled: true });
  });
  it("creates a native id, then resumes it in the same cwd and refuses missing or pi-bound histories", async () => {
    const root = tmp("substrate-dsh-");
    const config = parseRuntimesToml(`default = "gufo"\n[seats]\ndsh = "gufo"\n[runtime.gufo]\ntype = "host"\nharness = "dsh"\nprovider = "gufo"\n[sessions]\nproject_bin = "/opt/project"\nproject_url = "https://project.test"\nproject_token_file = "${root}/token"\n[[models]]\nid = "qwen3.8-flash-next"\nharness = "dsh"\nprovider = "gufo"\ndefault = true\nreasoning = false\n`);
    const calls: ProcessJob[] = [];
    const runner: Runner = { name: "gufo", type: "host", refuses: () => undefined, run: async job => {
      const j = job as ProcessJob; calls.push(j);
      const d = join(j.env!.DSH_HOME!, "sessions", "--cwd--", ID); mkdirSync(d, { recursive: true });
      writeFileSync(join(d, "v2.jsonl"), JSON.stringify({ type: "session", id: ID, cwd: j.cwd, delegationDepth: 0 }));
      return { runtime: "gufo", jobId: j.id, exitCode: 0, stdout: stream(), stderr: "", durationMs: 1 };
    } };
    const backend = new RunnerBackend(config, { jobsRoot: join(root, "jobs"), runId: "r", seatShadowRoot: join(root, "shadows"), transcriptRoot: join(root, "tx"), runners: { gufo: runner } });
    const call = (index: number, harness?: string, hsid = ID) => ({ index, key: `k${index}`, attempt: 1, phase: undefined, prompt: "Do it", opts: { model: "qwen3.8-flash-next", effort: "high", schema: { type: "object" }, session: { id: "substrate-session-1", harnessSessionId: hsid, role: "coordinator", ...(harness ? { harness } : {}) } } });
    expect(backend.route(call(1))).toMatchObject({ harness: "dsh", provider: "gufo", seatProvider: "gufo", seat: "gufo", model: "qwen3.8-flash-next" });
    const first = await backend.run(call(1));
    expect(first).toMatchObject({ agentId: ID, route: { harness: "dsh", runtime: "gufo", effort: { requested: "high", effective: "off", source: "model-capability" } }, object: { ok: true } });
    expect(first.sessionFile && existsSync(first.sessionFile)).toBe(true);
    // An unpinned first turn whose process died is recovered from the private Session header.
    expect(await backend.run(call(5, undefined, "floor-minted-uuid"))).toMatchObject({ agentId: ID });
    expect(calls[1]!.argv).toContain(ID);
    expect(calls[0]!.argv).not.toContain("--session-id");
    expect(await backend.run(call(2, "dsh"))).toMatchObject({ agentId: ID });
    expect(calls[1]!.argv).toContain(ID);
    expect(calls[1]!.cwd).toBe(calls[0]!.cwd);
    expect(calls[1]!.env!.DSH_HOME).toBe(calls[0]!.env!.DSH_HOME);
    expect(JSON.parse(readFileSync(calls[1]!.argv[4]!, "utf8")).find((r: any) => r.id === "session-persistence-jsonl").config.root).toBe(join(calls[1]!.env!.DSH_HOME!, "sessions"));
    expect((await backend.run(call(3, "dsh", "session-does-not-exist"))).error).toMatch(/persisted dsh session .* is missing/);
    expect((await backend.run(call(4, "pi"))).error).toMatch(/this session runs on pi/);
    expect(calls).toHaveLength(3);
  });
  it.each([false, true, undefined])("honors explicit reasoning capability %s without changing model or provider", async reasoning => {
    const root = tmp("substrate-dsh-effort-");
    // A different model id proves this is capability metadata, not a Gufo model-name special case.
    const config = parseRuntimesToml(`default="gufo"\n[runtime.gufo]\ntype="host"\nharness="dsh"\n[[models]]\nid="local-test-model"\nharness="dsh"\nprovider="gufo"\ndefault=true\n${reasoning === undefined ? "" : `reasoning=${reasoning}\n`}`);
    let modelConfig: unknown;
    const runner: Runner = { name: "gufo", type: "host", refuses: () => undefined, run: async job => {
      const j = job as ProcessJob;
      modelConfig = JSON.parse(readFileSync(j.argv[4]!, "utf8")).find((row: any) => row.id === "agent-default-model").config;
      return { runtime: "gufo", jobId: j.id, exitCode: 0, stdout: stream("ok"), stderr: "", durationMs: 1 };
    } };
    const backend = new RunnerBackend(config, { jobsRoot: join(root, "jobs"), runId: "r", seatShadowRoot: join(root, "shadows"), transcriptRoot: join(root, "tx"), runners: { gufo: runner } });
    const call = { index: 1, key: "k", attempt: 1, phase: undefined, prompt: "synthetic", opts: { model: "local-test-model", effort: "high" } };
    const adjustment = { requested: "high", effective: "off", source: "model-capability" };
    const route = backend.route(call);
    expect(route).toMatchObject({ harness: "dsh", model: "local-test-model", provider: "gufo" });
    expect(route.effort).toEqual(reasoning === false ? adjustment : undefined);
    expect((await backend.run(call)).error).toBeUndefined();
    expect(modelConfig).toEqual({ provider: "gufo", model: "local-test-model", ...(reasoning === false ? {} : { reasoningEffort: "high" }) });
    const receipt = JSON.parse(readFileSync(join(root, "jobs", "r-1-a1", "receipt.json"), "utf8"));
    expect(receipt.effort).toEqual(reasoning === false ? adjustment : undefined);
  });
  it("refuses unsupported confinement/provider combinations at configuration time", () => {
    expect(() => parseRuntimesToml('default="x"\n[runtime.x]\ntype="ssh"\nhost="compute"\nharness="dsh"')).toThrow(/needs host or runtime-test/);
    expect(() => parseRuntimesToml('default="x"\n[runtime.x]\ntype="host"\nharness="dsh"\nprovider="openrouter"')).toThrow(/provider gufo only/);
  });
});
