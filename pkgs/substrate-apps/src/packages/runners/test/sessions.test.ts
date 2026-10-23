/**
 * Agent sessions (sessions chapter, 2026-10-12, Stage B, C2.1 to C2.11): agent({session}) resumes the harness session
 * by id, in a per-session dir and cwd under the transcript root that outlive the job, with the one project MCP.
 * Fake harness binaries only (node scripts that log argv, cwd and env, and keep a session file the way the real
 * harness does); codex runs under the test guard with an explicit runtime, never routed.
 */
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { COORDINATOR_TOOLS, RunnerBackend, TEST_SEAT_ENV } from "../src/backend.ts";
import { parseRuntimesToml, sessionRuntime } from "../src/config.ts";
import { DEFAULT_MODEL_ALLOWLIST } from "../src/models.ts";
import { tmp } from "./helpers.ts";

const SUMMARY = {
  type: "object", additionalProperties: false,
  required: ["title", "status_category", "status_detail", "needs_action", "recent_action", "is_noteworthy"],
  properties: {
    title: { type: "string" }, description: { type: "string" }, status_category: { enum: ["need_input", "in_progress", "completed"] },
    status_detail: { type: "string" }, needs_action: { type: "string" }, recent_action: { type: "string" }, is_noteworthy: { type: "boolean" },
  },
};
const REPLY = { title: "t", status_category: "in_progress", status_detail: "d", needs_action: "", recent_action: "r", is_noteworthy: false };
const HSID = "7a1c2d3e-4f50-4612-8a7b-9c0d1e2f3a4b";
const SID = "01k7ab3c4d5e6f7g8h9jkmnpqs";
/** The session id the fake claude reports for a call that names none (its own fresh session). */
const PLAIN = "11111111-2222-4333-8444-555555555555";

const bin = tmp("axc-sessions-bin-");
const log = join(bin, "calls.jsonl");
// One fake per harness, each a node script: it logs {harness, argv, cwd, env, stdin} and keeps the session file the
// real harness keeps (claude: <CLAUDE_CONFIG_DIR>/projects/<slug>/<id>.jsonl; pi: <session dir>/<ts>_<id>.jsonl;
// codex: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-<ts>-<thread id>.jsonl). A prompt containing FAIL-ONCE fails a
// claude call that started its session; SLEEP outlives any short timeout.
const FAKE = (harness: string) => `#!/usr/bin/env node
const fs = require("fs"), path = require("path")
const a = process.argv.slice(2)
const val = (f) => { const i = a.indexOf(f); return i >= 0 ? a[i + 1] : undefined }
const stdin = fs.readFileSync(0, "utf8")
const env = Object.fromEntries(["PROJECT_URL", "PROJECT_TOKEN_FILE", "PROJECT_SESSION_ID", "PROJECT_ROLE", "PI_CODING_AGENT_DIR", "CLAUDE_CONFIG_DIR"].filter((k) => process.env[k] !== undefined).map((k) => [k, process.env[k]]))
fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify({ harness: ${JSON.stringify(harness)}, argv: a, cwd: process.cwd(), env, stdin }) + "\\n")
const reply = ${JSON.stringify(JSON.stringify(REPLY))}
if (stdin.includes("SLEEP")) { setTimeout(() => {}, 60000); return }
if (${JSON.stringify(harness)} === "claude") {
  const id = val("--session-id") ?? val("--resume")
  if (id) { const d = path.join(process.env.CLAUDE_CONFIG_DIR, "projects", "-sess-slug"); fs.mkdirSync(d, { recursive: true }); fs.appendFileSync(path.join(d, id + ".jsonl"), JSON.stringify({ stdin }) + "\\n") }
  if (stdin.includes("FAIL-ONCE") && val("--session-id")) { process.stderr.write("partial first attempt\\n"); process.exit(3) }
  console.log(JSON.stringify({ type: "result", subtype: "success", is_error: false, session_id: id ?? ${JSON.stringify(PLAIN)}, result: "", structured_output: JSON.parse(reply), total_cost_usd: 0.25, usage: { input_tokens: 11, output_tokens: 7, cache_read_input_tokens: 5 } }))
} else if (${JSON.stringify(harness)} === "pi") {
  const d = val("--session-dir"), id = val("--session-id")
  if (d && id) { const f = fs.readdirSync(d).find((n) => n.endsWith("_" + id + ".jsonl")) ?? "2026-10-12T21-00-00-000Z_" + id + ".jsonl"; fs.appendFileSync(path.join(d, f), JSON.stringify({ stdin }) + "\\n") }
  console.log(reply)
} else {
  const resumed = a[1] === "resume" ? a[2] : undefined
  const tid = resumed ?? "0199c0de-fa4e-7c0d-9e00-00000000c0de"
  const d = path.join(process.env.CODEX_HOME, "sessions", "2026", "10", "12")
  fs.mkdirSync(d, { recursive: true })
  fs.appendFileSync(path.join(d, "rollout-2026-10-12T21-00-00-" + tid + ".jsonl"), JSON.stringify({ stdin }) + "\\n")
  console.log(JSON.stringify({ type: "thread.started", thread_id: tid }))
  console.log(JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: reply } }))
  console.log(JSON.stringify({ type: "turn.completed", usage: { input_tokens: 5, output_tokens: 2 } }))
}
`;

const savedPath = process.env.PATH;
const savedGuard = process.env[TEST_SEAT_ENV];
const savedCodexHome = process.env.CODEX_HOME;
const codexHome = tmp("axc-sessions-codex-home-");
beforeAll(() => {
  for (const h of ["claude", "pi", "codex"]) {
    writeFileSync(join(bin, h), FAKE(h));
    chmodSync(join(bin, h), 0o755);
  }
  process.env.PATH = `${bin}:${savedPath}`;
  process.env.CODEX_HOME = codexHome;
});
afterAll(() => {
  process.env.PATH = savedPath;
  if (savedCodexHome === undefined) delete process.env.CODEX_HOME;
  else process.env.CODEX_HOME = savedCodexHome;
});

interface Logged { harness: string; argv: string[]; cwd: string; env: Record<string, string>; stdin: string }
const logged = (): Logged[] => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l) as Logged) : []);

const MODELS = `
[[models]]
id = "claude-opus-5-5"
harness = "claude"
default = true
[[models]]
id = "qwen3.8-flash-next"
harness = "pi"
default = true
[[models]]
id = "qwen3.8-max"
harness = "pi"
provider = "qwen-token-plan"
default = true
[[models]]
id = "gpt-5.5-codex"
harness = "codex"
`;

/** A runtimes file with [sessions] (unless `sessions: false`), a claude, a pi (Gufo) and a codex host runtime. */
function world(o: { sessions?: boolean; extra?: string } = {}) {
  const root = tmp("axc-sessions-");
  const seat = join(root, "seat");
  mkdirSync(seat);
  mkdirSync(join(root, "pihost"));
  writeFileSync(join(root, "pihost", "models.json"), JSON.stringify({ providers: { gufo: { baseUrl: "http://strix:8731/v1", models: [{ id: "qwen3.8-flash-next", contextWindow: 262144 }] } } }) + "\n");
  const sessions = o.sessions === false ? "" : `[sessions]\nproject_bin = "/opt/project/bin/project"\nproject_url = "https://project.test"\nproject_token_file = "${root}/token"\n`;
  const config = parseRuntimesToml(`default = "opus"\n${MODELS}\n[credentials]\nclaude = "${seat}"\n${sessions}
[runtime.opus]
type = "host"
[runtime.gufo]
type = "host"
harness = "pi"
[runtime.cx]
type = "host"
harness = "codex"
${o.extra ?? ""}`, "t", root);
  const transcriptRoot = join(root, "tx");
  const backend = new RunnerBackend(config, { jobsRoot: join(root, "jobs"), runId: "sess", seatShadowRoot: join(root, "shadows"), transcriptRoot, piHostAgentDir: join(root, "pihost") });
  const dir = (id = SID) => join(transcriptRoot, "sessions", id);
  const receipt = (index: number, attempt = 1) => JSON.parse(readFileSync(join(root, "jobs", `sess-${index}-a${attempt}`, "receipt.json"), "utf8"));
  return { root, seat, config, backend, dir, receipt, transcriptRoot };
}

let n = 0;
const call = (opts: Record<string, unknown>, o: { prompt?: string; attempt?: number; index?: number } = {}) => {
  const index = o.index ?? ++n;
  return { index, key: `k${index}`, prompt: o.prompt ?? "<wake reason=\"spawn\">hello</wake>", opts, phase: undefined, attempt: o.attempt ?? 1 };
};
const session = (over: Record<string, unknown> = {}) => ({ id: SID, harnessSessionId: HSID, role: "thread", ...over });
const since = (k: number) => logged().slice(k);

describe("agent({session}) is honoured or refused, never dropped", () => {
  it("session option: a malformed value, isolation, no [sessions] table or another harness is refused with a reason in the receipt", async () => {
    const w = world();
    const k = logged().length;
    const refused = async (opts: Record<string, unknown>, re: RegExp, b = w.backend) => {
      const c = call(opts);
      const out = await b.run(c);
      expect(out.error).toMatch(re);
      return c.index;
    };
    const runtime = "opus", model = "claude-opus-5-5";
    let i = await refused({ runtime, model, session: "s1" }, /must be an object/);
    expect(w.receipt(i).refused).toMatch(/must be an object/);
    i = await refused({ runtime, model, session: session({ harnessSessionId: undefined }) }, /harnessSessionId must match/);
    expect(w.receipt(i).refused).toMatch(/harnessSessionId/);
    i = await refused({ runtime, model, session: session({ cwd: 5 }) }, /cwd must be a string/);
    i = await refused({ runtime, model, session: session({ project: "p" }) }, /unknown field\(s\) project/);
    i = await refused({ runtime, model, session: session({ role: "admin" }) }, /role must be coordinator or thread/);
    i = await refused({ runtime, model, session: session({ id: "../etc" }) }, /id must match/);
    i = await refused({ runtime, model, session: session(), isolation: "worktree" }, /cannot take isolation/);
    expect(w.receipt(i).refused).toMatch(/isolation/);
    const bare = world({ sessions: false });
    const c = call({ runtime, model, session: session() });
    expect((await bare.backend.run(c)).error).toMatch(/needs the \[sessions\] table/);
    expect(bare.receipt(c.index).refused).toMatch(/\[sessions\]/);
    i = await refused({ runtime: "gufo", model: "qwen3.8-flash-next", session: session({ harness: "claude" }) }, /pinned to the claude harness; runtime gufo runs pi/);
    expect(w.receipt(i).refused).toMatch(/pinned to the claude harness/);
    // EXCHANGE section 11: a session never changes harness, so a model the catalog serves elsewhere is refused too.
    i = await refused({ runtime: "opus", model: "qwen3.8-flash-next", session: session({ harness: "claude" }) }, /served by the pi harness; runtime opus runs claude/);
    expect(w.receipt(i).refused).toMatch(/served by the pi harness/);
    expect(since(k)).toEqual([]);
  });

  it("pinned runtime: a model it does not serve is refused, never swapped for the runtime's default (EXCHANGE section 7)", async () => {
    const w = world();
    const k = logged().length;
    // switch_model on a pi session pinned to gufo: qwen3.8-max is a pi model of another provider
    let c = call({ runtime: "gufo", model: "qwen3.8-max", schema: SUMMARY, session: session({ harness: "pi", role: "coordinator" }) });
    expect((await w.backend.run(c)).error).toMatch(/model qwen3.8-max is served by pi provider qwen-token-plan; runtime gufo runs pi provider gufo/);
    expect(w.receipt(c.index).refused).toMatch(/pi provider qwen-token-plan/);
    // a claude session pinned to opus and an id the catalog does not know
    c = call({ runtime: "opus", model: "nope-1", schema: SUMMARY, session: session({ harness: "claude" }) });
    expect((await w.backend.run(c)).error).toMatch(/model nope-1 has no catalog entry, so runtime opus cannot serve it/);
    expect(w.receipt(c.index).refused).toMatch(/no catalog entry/);
    // the route names why and keeps the runtime's own model and seat for admission, so the call reaches run() and its
    // receipt (CARRIED item 13); the integrated path's model policy keeps the declared model (test/integrated.test.ts "route:")
    expect(w.backend.route({ opts: { runtime: "gufo", model: "qwen3.8-max", session: session({ harness: "pi" }) }, phase: undefined }))
      .toMatchObject({ selection: { name: "gufo" }, model: "qwen3.8-flash-next", sessionRefused: expect.stringMatching(/pi provider qwen-token-plan/) });
    expect(w.backend.route({ opts: { runtime: "gufo", model: "qwen3.8-max", session: session({ harness: "claude" }) }, phase: undefined }).sessionRefused)
      .toMatch(/pinned to the claude harness; runtime gufo runs pi/);
    expect(w.backend.route({ opts: { runtime: "gufo", model: "qwen3.8-flash-next", session: session({ harness: "pi" }) }, phase: undefined }).sessionRefused).toBeUndefined();
    expect(since(k)).toEqual([]);
  });
});

describe("the runtime of a session call that names none", () => {
  it("runtime from model: the first permitted host runtime of the model's catalog harness and pi provider, never codex", async () => {
    const w = world({ extra: `[runtime.opus2]\ntype = "host"\n[runtime.vm]\ntype = "gvisor"\nrunsc = "/nix/store/x/bin/runsc"\nharness = "pi"\n` });
    const cat = DEFAULT_MODEL_ALLOWLIST;
    expect(sessionRuntime(w.config, cat, "claude-opus-5-5", undefined)).toMatchObject({ name: "opus", via: "model" });
    expect(sessionRuntime(w.config, cat, "opus", "claude").name).toBe("opus");
    expect(sessionRuntime(w.config, cat, "qwen3.8-flash-next", "pi")).toMatchObject({ name: "gufo", runtime: { type: "host", harness: "pi" } });
    expect(() => sessionRuntime(w.config, cat, "qwen3.8-max", undefined)).toThrow(/no host runtime this file permits serves model qwen3.8-max \(harness pi, pi provider qwen-token-plan\)/);
    expect(() => sessionRuntime(w.config, cat, "nope-1", undefined)).toThrow(/model nope-1 has no catalog entry/);
    expect(() => sessionRuntime(w.config, cat, "qwen3.8-flash-next", "claude")).toThrow(/served by the pi harness; this session runs on claude/);
    expect(() => sessionRuntime(w.config, [...cat, { id: "gpt-5.5-codex", harness: "codex" }], "gpt-5.5-codex", undefined)).toThrow(/codex harness, which runs no session/);
    expect(() => sessionRuntime(w.config, cat, undefined, undefined)).toThrow(/must name its model/);

    // Through the backend: the route names the runtime, the outcome carries it; refusals are outcomes.
    expect(w.backend.route({ opts: { model: "claude-opus-5-5", session: session() }, phase: undefined }).selection.name).toBe("opus");
    expect(w.backend.route({ opts: { model: "qwen3.8-flash-next", session: session() }, phase: undefined })).toMatchObject({ harness: "pi", selection: { name: "gufo" } });
    const out = await w.backend.run(call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session({ id: "routefrommodel1" }) }));
    expect(out.route).toEqual({ runtime: "gufo", harness: "pi" });
    expect(out.object).toEqual(REPLY);
    expect((await w.backend.run(call({ model: "gpt-5.5-codex", session: session() }))).error).toMatch(/codex harness, which runs no session/);
    expect((await w.backend.run(call({ model: "qwen3.8-max", session: session() }))).error).toMatch(/no host runtime this file permits/);
    expect(w.backend.route({ opts: { runtime: "opus", model: "qwen3.8-flash-next", session: session() }, phase: undefined }))
      .toMatchObject({ model: "claude-opus-5-5", sessionRefused: expect.stringMatching(/served by the pi harness/) });
  });
});

describe("the session's own dir and cwd", () => {
  it("session dir: <transcript root>/sessions/<id>/ (0700) outlives the job; pi gets --session-dir <id>/pi, --session-id and its own agent dir", async () => {
    const w = world();
    const k = logged().length;
    const out = await w.backend.run(call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session() }));
    expect(out.error).toBeUndefined();
    const dir = w.dir();
    expect(statSync(dir).mode & 0o777).toBe(0o700);
    expect(existsSync(dir)).toBe(true);
    const [pi] = since(k);
    expect(pi!.argv.slice(0, 5)).toEqual(["-p", "--session-dir", join(dir, "pi"), "--session-id", HSID]);
    expect(pi!.env.PI_CODING_AGENT_DIR).toBe(join(dir, "pi-agent"));
    // the host's models.json, as a job-scoped agent dir has it (no [models.pi] table: copied as it is)
    expect(readFileSync(join(dir, "pi-agent", "models.json"), "utf8")).toBe(readFileSync(join(w.root, "pihost", "models.json"), "utf8"));
    expect(existsSync(join(dir, "pi-agent", "mcp.json"))).toBe(true);
    // nothing of the session went into the seat shadow, and the shadow is gone as before
    expect(readdirSync(join(dir, "pi")).filter((f) => f.endsWith(`_${HSID}.jsonl`))).toHaveLength(1);
    expect(existsSync(join(w.root, "shadows")) ? readdirSync(join(w.root, "shadows")) : []).toEqual([]);
  });

  it("cwd: two calls on one session run in the session's cwd, <id>/cwd by default, the same on every turn", async () => {
    const w = world();
    const k = logged().length;
    for (let t = 0; t < 2; t++) await w.backend.run(call({ model: "claude-opus-5-5", schema: SUMMARY, session: session() }));
    const [a, b] = since(k);
    expect(a!.cwd).toBe(join(w.dir(), "cwd"));
    expect(b!.cwd).toBe(a!.cwd);
    const own = join(w.root, "own-cwd");
    mkdirSync(own);
    await w.backend.run(call({ model: "claude-opus-5-5", schema: SUMMARY, session: session({ id: "owncwdsession1", cwd: own }) }));
    expect(since(k)[2]!.cwd).toBe(own);
  });
});

describe("resume by id, per harness", () => {
  it("claude argv: --session-id on the first turn, --resume after it, with the schema, model, effort and the strict project MCP", async () => {
    const w = world();
    const k = logged().length;
    const first = await w.backend.run(call({ model: "claude-opus-5-5", effort: "high", schema: SUMMARY, session: session() }));
    expect(first).toMatchObject({ object: REPLY, agentId: HSID });
    await w.backend.run(call({ model: "claude-opus-5-5", schema: SUMMARY, session: session({ harness: "claude" }) }));
    const [a, b] = since(k).map((l) => l.argv);
    const mcp = ["--mcp-config", join(w.dir(), "mcp.json"), "--strict-mcp-config"];
    expect(a).toEqual(["-p", "--model", "claude-opus-5-5", "--output-format", "json", "--dangerously-skip-permissions", "--effort", "high", "--json-schema", JSON.stringify(SUMMARY), "--session-id", HSID, ...mcp]);
    expect(b).toEqual(["-p", "--model", "claude-opus-5-5", "--output-format", "json", "--dangerously-skip-permissions", "--json-schema", JSON.stringify(SUMMARY), "--resume", HSID, ...mcp]);

    // a retry after a partial first attempt (the session file exists) resumes instead of colliding on --session-id
    const s = session({ id: "retrysession01", harnessSessionId: "0b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f00" });
    const c = call({ model: "claude-opus-5-5", schema: SUMMARY, session: s }, { prompt: "FAIL-ONCE" });
    expect((await w.backend.run(c)).error).toMatch(/claude exited 3/);
    expect((await w.backend.run({ ...c, attempt: 2, previousErrors: ["claude exited 3"] })).object).toEqual(REPLY);
    const [r1, r2] = since(k + 2).map((l) => l.argv);
    expect(r1).toContain("--session-id");
    expect(r2).toEqual(expect.arrayContaining(["--resume", "0b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f00"]));
    expect(r2).not.toContain("--session-id");
  });

  it("retry: a schema retry of a turn the harness session holds sends the corrections alone; one it does not hold sends the prompt too", async () => {
    // CARRIED item 9: the interpreter retries only a reply the schema rejected, so attempt 1 ran in the session and its
    // tool calls have run; resending the envelopes would make the session see each wake twice.
    const w = world();
    const k = logged().length;
    const errors = ["/status_category must be equal to one of the allowed values"];
    const fix = `Your previous reply was rejected: ${errors[0]}.\nReply again, correcting exactly that.`;
    const suffix = `\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(SUMMARY)}`;
    const cl = call({ model: "claude-opus-5-5", schema: SUMMARY, session: session({ id: "retryheld01", harnessSessionId: "1b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f01" }) }, { prompt: "ENVELOPES" });
    await w.backend.run(cl);
    await w.backend.run({ ...cl, attempt: 2, previousErrors: errors });
    const pi = call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session({ id: "retryheldpi01", harnessSessionId: "2b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f02" }) }, { prompt: "ENVELOPES" });
    await w.backend.run(pi);
    await w.backend.run({ ...pi, attempt: 2, previousErrors: errors });
    // a session nothing has run in yet (no transcript found by id): the prompt and the corrections, as any retry
    const fresh = call({ model: "claude-opus-5-5", schema: SUMMARY, session: session({ id: "retryfresh01", harnessSessionId: "3b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f03" }) }, { prompt: "ENVELOPES", attempt: 2 });
    await w.backend.run({ ...fresh, previousErrors: errors });
    const [c1, c2, p1, p2, f1] = since(k);
    expect([c1!.stdin, c2!.stdin]).toEqual(["ENVELOPES", fix]);
    expect(c2!.argv).toEqual(expect.arrayContaining(["--resume", "1b0e7a9c-1d2e-4f30-8a41-5b6c7d8e9f01"]));
    expect([p1!.stdin, p2!.stdin]).toEqual([`ENVELOPES${suffix}`, `${fix}${suffix}`]);
    expect(f1!.stdin).toBe(`ENVELOPES\n\n${fix}`);
    expect(f1!.argv).toContain("--session-id");
  });

  it("pi argv: effort becomes --thinking; a coordinator gets read and the project tools only, no skills or context files; a thread no --tools; the schema rides in the prompt", async () => {
    const w = world();
    const k = logged().length;
    await w.backend.run(call({ model: "qwen3.8-flash-next", effort: "low", schema: SUMMARY, session: session({ role: "coordinator" }) }, { prompt: "WAKE" }));
    await w.backend.run(call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session({ id: "threadsession01" }) }));
    const [coord, thread] = since(k);
    const dir = w.dir();
    expect(coord!.argv).toEqual(["-p", "--session-dir", join(dir, "pi"), "--session-id", HSID, "--provider", "gufo", "--model", "qwen3.8-flash-next",
      "--thinking", "low", "--tools", COORDINATOR_TOOLS.join(","), "--no-skills", "--no-context-files", "--mode", "text"]);
    expect(COORDINATOR_TOOLS.join(",")).toBe("read,mcp__project__start_thread_session,mcp__project__message_thread,mcp__project__list_thread_sessions,mcp__project__fetch_thread,mcp__project__fetch_project_timeline,mcp__project__fetch_messages,mcp__project__post_message,mcp__project__read_memory,mcp__project__update_memory,mcp__project__send_later,mcp__project__list_triggers,mcp__project__create_trigger,mcp__project__update_trigger,mcp__project__delete_trigger");
    expect(thread!.argv).not.toContain("--tools");
    expect(thread!.argv).not.toContain("--no-skills");
    expect(thread!.argv).not.toContain("--thinking");
    expect(coord!.stdin).toBe(`WAKE\n\nReply with one JSON value only, no prose and no code fence, valid against this JSON Schema:\n${JSON.stringify(SUMMARY)}`);
  });

  it("codex argv: a fresh thread with the project MCP as -c entries, then exec resume <thread id> with sandbox_mode; effort refused as before", async () => {
    process.env[TEST_SEAT_ENV] = "1";
    try {
      const w = world();
      const k = logged().length;
      const first = await w.backend.run(call({ runtime: "cx", schema: SUMMARY, session: session() }));
      // codex mints its own thread id: the outcome carries it in place of the floor-minted UUID
      expect(first).toMatchObject({ object: REPLY, agentId: "0199c0de-fa4e-7c0d-9e00-00000000c0de", route: { runtime: "cx", harness: "codex" } });
      const later = await w.backend.run(call({ runtime: "cx", model: "gpt-5.5-codex", schema: SUMMARY, session: session({ harnessSessionId: first.agentId, harness: "codex" }) }));
      expect(later.agentId).toBe(first.agentId);
      const mcp = ["-c", "mcp_servers.project.command=/opt/project/bin/project", "-c", "mcp_servers.project.args=[\"mcp\"]",
        "-c", "mcp_servers.project.env.PROJECT_URL=https://project.test", "-c", `mcp_servers.project.env.PROJECT_TOKEN_FILE=${w.root}/token`,
        "-c", `mcp_servers.project.env.PROJECT_SESSION_ID=${SID}`, "-c", "mcp_servers.project.env.PROJECT_ROLE=thread"];
      const [a, b] = since(k).map((l) => l.argv);
      expect(a).toEqual(["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", ...mcp, "-"]);
      expect(b).toEqual(["exec", "resume", first.agentId, "--json", "--skip-git-repo-check", "-c", "sandbox_mode=\"read-only\"", "-m", "gpt-5.5-codex", ...mcp, "-"]);
      expect((await w.backend.run(call({ runtime: "cx", effort: "low", session: session() }))).error).toMatch(/harness codex cannot honour agent\(\{effort/);
    } finally {
      if (savedGuard === undefined) delete process.env[TEST_SEAT_ENV];
      else process.env[TEST_SEAT_ENV] = savedGuard;
    }
  });
});

describe("the one project MCP", () => {
  it("mcp.json names the project server with its four variables; pi's copy adds direct exposure; the harness gets the same four", async () => {
    const w = world();
    const k = logged().length;
    await w.backend.run(call({ model: "claude-opus-5-5", schema: SUMMARY, session: session() }));
    await w.backend.run(call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session({ id: "pisession00001", role: "coordinator" }) }));
    const env = { PROJECT_URL: "https://project.test", PROJECT_TOKEN_FILE: `${w.root}/token`, PROJECT_SESSION_ID: SID, PROJECT_ROLE: "thread" };
    expect(JSON.parse(readFileSync(join(w.dir(), "mcp.json"), "utf8"))).toEqual({ mcpServers: { project: { command: "/opt/project/bin/project", args: ["mcp"], env } } });
    const piEnv = { ...env, PROJECT_SESSION_ID: "pisession00001", PROJECT_ROLE: "coordinator" };
    expect(JSON.parse(readFileSync(join(w.dir("pisession00001"), "pi-agent", "mcp.json"), "utf8"))).toEqual({ mcpServers: { project: { command: "/opt/project/bin/project", args: ["mcp"], env: piEnv, exposure: "direct" } } });
    expect(statSync(join(w.dir(), "mcp.json")).mode & 0o777).toBe(0o600);
    const [claude, pi] = since(k);
    expect(claude!.env).toMatchObject(env);
    expect(pi!.env).toMatchObject(piEnv);
  });
});

describe("#26: a killed turn still names its session", () => {
  it("timeout keeps the session id: exit 124, the outcome's agentId is the harness session id and the receipt names it", async () => {
    const w = world({ extra: `[runtime.slow]\ntype = "host"\ntimeoutMs = 400\n` });
    const c = call({ runtime: "slow", model: "claude-opus-5-5", schema: SUMMARY, session: session() }, { prompt: "SLEEP" });
    const out = await w.backend.run(c);
    expect(out.error).toMatch(/claude exited 124 \(timeout\)/);
    expect(out.agentId).toBe(HSID);
    const r = w.receipt(c.index);
    expect([r.exitCode, r.timedOut, r.sessionId]).toEqual([124, true, HSID]);
  });
});

describe("what a session call reports", () => {
  it("costUsd, route and sessionFile: claude's total_cost_usd is in usage, the route names runtime and harness, the session file is found by id", async () => {
    const w = world();
    const out = await w.backend.run(call({ model: "claude-opus-5-5", schema: SUMMARY, session: session() }));
    expect(out.usage).toEqual({ inputTokens: 11, outputTokens: 7, cacheReadTokens: 5, costUsd: 0.25 });
    expect(out.route).toEqual({ runtime: "opus", harness: "claude" });
    expect(out.sessionFile).toBe(join(w.seat, "projects", "-sess-slug", `${HSID}.jsonl`));
    const pi = await w.backend.run(call({ model: "qwen3.8-flash-next", schema: SUMMARY, session: session({ id: "pisession00002" }) }));
    expect(pi.route).toEqual({ runtime: "gufo", harness: "pi" });
    expect(pi.sessionFile).toBe(join(w.dir("pisession00002"), "pi", `2026-10-12T21-00-00-000Z_${HSID}.jsonl`));
    // a call without a session reports neither
    const plain = await w.backend.run(call({ model: "claude-opus-5-5" }));
    expect(plain.route).toBeUndefined();
    expect(plain.sessionFile).toBeUndefined();
  });

  it("archive: a session call keeps stdout and stderr only, and the receipt names the session file instead of copying it", async () => {
    const w = world();
    const c = call({ model: "claude-opus-5-5", schema: SUMMARY, session: session() });
    await w.backend.run(c);
    const r = w.receipt(c.index);
    const file = join(w.seat, "projects", "-sess-slug", `${HSID}.jsonl`);
    expect(r.sessionFile).toBe(file);
    expect(r.session).toBe(SID);
    expect(r.transcripts.map((t: { name: string }) => t.name)).toEqual(["harness.stdout"]);
    expect(readdirSync(r.transcriptDir)).toEqual(["harness.stdout"]);
    // a call without a session archives the claude transcript it finds by id, as before
    mkdirSync(join(w.seat, "projects", "-plain"), { recursive: true });
    writeFileSync(join(w.seat, "projects", "-plain", `${PLAIN}.jsonl`), "{}\n");
    const p = call({ model: "claude-opus-5-5" });
    await w.backend.run(p);
    expect(w.receipt(p.index).transcripts.map((t: { source: string }) => t.source)).toEqual(["stdout", "host-session"]);
    expect(w.receipt(p.index).sessionFile).toBeUndefined();
  });
});
