// Sessions chapter (2026-10-12, C2.14): a local run's verdict carries output.calls, and through it a session's turns
// end on the floor. End to end against the real floor routes (apps/floor/src/local.ts) and the repo's runners with a
// fake claude: a feed row starts a session, the floor makes one run of the embedded turn program, this puller leases
// it, the turn's one agent() call starts the harness session by id and the verdict's calls[0] (harness session id,
// usage with costUsd, route, session file) ends the turn; a second wake resumes the same session.
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { parseRuntimesToml } from "@substrate/runners"
import { connectFloor } from "../src/connect.ts"
import { floorExecutor, localExecutor } from "../src/execute.ts"
import { Puller } from "../src/puller.ts"
import { PullerState } from "../src/state.ts"

const T = { floor: "calls-test-floor", coord: "calls-test-coord" }
const URL_ = "http://floor.test"
const SID = "01k7ab3c4d5e6f7g8h9jkmnpqs"
const REPLY = { title: "canary", status_category: "in_progress", status_detail: "remembered", needs_action: "", recent_action: "replied", is_noteworthy: false }
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })

const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 20_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 25)) }
}

const bin = mkdtempSync(join(tmpdir(), "substrate-calls-bin-"))
const log = join(bin, "claude.jsonl")
const saved = process.env.PATH
beforeAll(() => {
  // A fake claude that keeps its session file by id, as the real one does, and answers the summary schema.
  writeFileSync(join(bin, "claude"), `#!/usr/bin/env node
const fs = require("fs"), path = require("path")
const a = process.argv.slice(2), val = (f) => { const i = a.indexOf(f); return i >= 0 ? a[i + 1] : undefined }
const stdin = fs.readFileSync(0, "utf8"), id = val("--session-id") ?? val("--resume")
fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify({ argv: a, cwd: process.cwd(), role: process.env.PROJECT_ROLE }) + "\\n")
const d = path.join(process.env.CLAUDE_CONFIG_DIR, "projects", "-calls")
fs.mkdirSync(d, { recursive: true })
fs.appendFileSync(path.join(d, id + ".jsonl"), JSON.stringify({ stdin }) + "\\n")
console.log(JSON.stringify({ type: "result", subtype: "success", is_error: false, session_id: id, result: "", structured_output: ${JSON.stringify(REPLY)},
  total_cost_usd: 0.5, usage: { input_tokens: 100, output_tokens: 10, cache_read_input_tokens: 40 } }))
`)
  chmodSync(join(bin, "claude"), 0o755)
  process.env.PATH = `${bin}:${saved}`
})
afterAll(() => { process.env.PATH = saved })

describe("the verdict's calls[] ends a session's turn on the floor", () => {
  it("calls: a turn run on the local executor reports calls[0], and the floor stores its harness, usage and transcript; the next wake resumes", async () => {
    const f = localFloor({ floorToken: T.floor, links: [{ token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] }],
      vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1" } })
    cleanups.push(() => f.close())
    const client = new SubstrateClient({ url: URL_, token: T.floor, fetch: f.fetch })
    const root = mkdtempSync(join(tmpdir(), "substrate-calls-"))
    const stateDir = join(root, "state"), seat = join(root, "seat")
    mkdirSync(seat)
    const runtimes = parseRuntimesToml(`default = "opus"\n[credentials]\nclaude = "${seat}"\n[sessions]\nproject_url = "https://project.test"\nproject_token_file = "${root}/token"\n[runtime.opus]\ntype = "host"\n`, "test")
    const conn = await connectFloor({ url: URL_, token: T.coord, sessionId: new PullerState(stateDir).sessionId(), fetch: f.fetch })
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, pollMs: 25, heartbeatMs: 150 },
      { floor: conn.port, client, execute: localExecutor({ runtimes, seat: "fake", defaultModel: "claude-opus-5-5", cap: 1, maxAttempts: 1 }), log: () => undefined })
    const done = p.run().finally(() => conn.close())
    cleanups.push(async () => { p.stop(); await done.catch(() => undefined) })

    // the feed's first row for the session carries start; the floor mints the harness session id and starts a turn
    const deliver = (seq: number, row: Record<string, unknown>) =>
      f.floor.ctx.storage.transactionSync(() => f.floor.engine.receive([{ id: `01K7WAKE00000000000000000${seq}`, seq, session: SID, ...row }], seq))
    deliver(1, { start: { project: "desk", thread: "T-9", model: "claude-opus-5-5", effort: "low" }, envelope: "<wake reason=\"spawn\">remember canary-41</wake>" })
    const minted = (await client.session(SID)).harness_session_id
    await until("turn 1", async () => (await client.session(SID)).turn === 1)

    const out = (await client.output(`run-s${SID}r1`)).output as { calls: Array<Record<string, unknown>>; result: unknown }
    const sessionFile = join(seat, "projects", "-calls", `${minted}.jsonl`)
    expect(out.calls).toEqual([{ harnessSessionId: minted, usage: { inputTokens: 100, outputTokens: 10, cacheReadTokens: 40, costUsd: 0.5 },
      route: { runtime: "opus", harness: "claude" }, sessionFile }])
    expect(out.result).toEqual({ post_turn_summary: REPLY })
    const s1 = await client.session(SID)
    expect(s1).toMatchObject({ harness: "claude", harness_session_id: minted, worker_status: "idle", turn: 1, post_turn_summary: REPLY, transcript: sessionFile,
      usage: { input_tokens: 100, output_tokens: 10, cache_read_tokens: 40, cache_write_tokens: 0, cost_usd: 0.5 } })

    // a wake past the Task's 16384-byte inline env budget (whole bodies, EXCHANGE 9.4): the turn runs on the prompt-file
    // route, its prompt written under the run dir (CARRIED item 16)
    const long = `<wake reason="mention">repeat the canary ${"x".repeat(20_000)}</wake>`
    deliver(2, { envelope: long })
    await until("turn 2", async () => (await client.session(SID)).turn === 2)
    const prompts = join(stateDir, "runs", `s${SID}r2`, "prompts")
    expect(readdirSync(prompts).map((n) => readFileSync(join(prompts, n), "utf8"))).toEqual([long])
    const s2 = await client.session(SID)
    expect(s2).toMatchObject({ harness_session_id: minted, transcript: sessionFile, usage: { input_tokens: 200, cost_usd: 1 } })
    const calls = readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { argv: Array<string>; cwd: string; role: string })
    expect(calls.map((c) => c.argv.slice(c.argv.findIndex((x) => x === "--session-id" || x === "--resume"), -3))).toEqual([["--session-id", minted], ["--resume", minted]])
    expect(calls[0]!.argv).toEqual(expect.arrayContaining(["--effort", "low", "--strict-mcp-config"]))
    expect(new Set(calls.map((c) => c.cwd)).size).toBe(1)
    expect(calls.map((c) => c.role)).toEqual(["thread", "thread"])
    expect(readFileSync(sessionFile, "utf8").trim().split("\n")).toHaveLength(2)
    expect(existsSync(join(calls[0]!.cwd, ".."))).toBe(true)

    // switch_model to a model the pinned runtime does not serve: the next turn fails with the runner's reason, no call runs
    await client.patchSession(SID, { model: "nope-1" })
    deliver(3, { envelope: "<wake reason=\"mention\">again</wake>" })
    await until("turn 3 failed", async () => (await client.session(SID)).post_turn_summary?.status_category === "failed")
    const s3 = await client.session(SID)
    expect(s3).toMatchObject({ turn: 2, worker_status: "idle", harness: "claude", model: "nope-1" })
    expect(s3.post_turn_summary!.status_detail).toMatch(/model nope-1 has no catalog entry, so runtime opus cannot serve it/)
    expect(readFileSync(log, "utf8").trim().split("\n")).toHaveLength(2)
    // the runner refused it, with its receipt (C2.1 on the integrated path, CARRIED item 13)
    const jobs = join(stateDir, "runs", `s${SID}r3`, "jobs")
    const receipts = readdirSync(jobs, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => JSON.parse(readFileSync(join(jobs, d.name, "receipt.json"), "utf8")) as { refused?: string })
    expect(receipts.map((r) => r.refused)).toEqual([expect.stringMatching(/model nope-1 has no catalog entry/)])
  })
})

describe("node_dispatch = \"floor\"", () => {
  it("a turn's agent({session}) is refused before any node is enqueued, so no fresh harness runs and no model call is spent", async () => {
    let enqueued = 0
    const client = { enqueue: async () => { enqueued++; return { enqueued: [] } }, job: async () => { throw new Error("no job") }, output: async () => { throw new Error("no output") } }
    const dir = mkdtempSync(join(tmpdir(), "substrate-calls-floor-"))
    const script = readFileSync(new URL("../../../programs/turn.workflow.js", import.meta.url), "utf8")
    writeFileSync(join(dir, "script.js"), script)
    const args = { session: { id: SID, harnessSessionId: "7a1c2d3e-4f50-4612-8a7b-9c0d1e2f3a4b", role: "thread" }, model: "claude-opus-5-5", effort: "low", runtime: null, envelopes: ["<wake/>"] }
    const v = await floorExecutor({ client: client as never, defaultRunsOn: ["seat:t"], defaultModel: "m", pollMs: 5 })(
      { runId: `s${SID}r1`, leaseId: `run-s${SID}r1-a1`, attempt: 1, job: {} as never, workflowName: "turn", args, dir, scriptPath: join(dir, "script.js"), script, signal: new AbortController().signal })
    expect(v.result).toBe("failure")
    expect(enqueued).toBe(0)
    expect(readFileSync(join(dir, "journal.jsonl"), "utf8")).toMatch(/agent\(\{session\}\) runs only with \[puller\] node_dispatch = \\"local\\"/)
  })
})
