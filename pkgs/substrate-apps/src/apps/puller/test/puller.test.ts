// The puller's lease loop against the real floor (the Worker entry and Floor object over node:sqlite,
// apps/floor/src/local.ts), through the link's own rpcFloor client: lease, run, heartbeat, complete; a kill and a
// restart that re-adopts the lease and resumes from the run's journal; a cancel; the local executor with the repo's
// runners (a fake claude binary) and the ax refusal; the pidfile.
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { parseRuntimesToml } from "@substrate/runners"
import { connectFloor } from "../src/connect.ts"
import { FloorBackend, floorExecutor, localExecutor, outcomeOf, transcriptPartName } from "../src/execute.ts"
import { acquirePidfile, PidfileHeld } from "../src/pidfile.ts"
import { Puller } from "../src/puller.ts"
import type { Executor } from "../src/puller.ts"
import { main } from "../src/main.ts"

const T = { floor: "puller-test-floor", coord: "puller-test-coord", nas: "puller-test-nas" }
const URL_ = "http://floor.test"
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })

const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 15_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 20)) }
}

const world = async () => {
  const f = localFloor({ floorToken: T.floor, links: [
    { token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] },
    { token: T.nas, holder: "nas", labels: ["seat:t", "runtime:*"] }
  ], vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1" } })
  cleanups.push(() => f.close())
  const client = new SubstrateClient({ url: URL_, token: T.floor, fetch: f.fetch })
  const stateDir = mkdtempSync(join(tmpdir(), "substrate-puller-"))
  const nas = await connectFloor({ url: URL_, token: T.nas, sessionId: "nas-session", fetch: f.fetch })
  cleanups.push(() => nas.close())
  /** The NAS link's part, by hand: lease what is queued for it and answer each node by its prompt. */
  const serveNodes = async (answer: (prompt: string) => unknown | undefined) => {
    const r = await nas.port.lease({ holderIdentity: "nas", capacity: 10, requestKey: crypto.randomUUID() })
    for (const g of r.grants) {
      const out = answer(g.job.spec.with.prompt ?? "")
      if (out !== undefined) await nas.port.complete({ leaseId: g.leaseId, attempt: g.attempt, result: "success", output: out, usage: { prompt_tokens: 3, completion_tokens: 1, tool_calls: 0 } })
    }
    return r.grants.length
  }
  const start = async (execute: Executor, o: { hbMs?: number } = {}) => {
    const conn = await connectFloor({ url: URL_, token: T.coord, sessionId: readFileSync(join(stateDir, "session-id"), "utf8").trim(), fetch: f.fetch })
    const events: Array<{ ev: string; f?: Record<string, unknown> }> = []
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, pollMs: 25, heartbeatMs: o.hbMs ?? 150 }, { floor: conn.port, client, execute, log: (ev, fields) => { if (process.env.PULLER_DEBUG) console.error(ev, JSON.stringify(fields)); events.push({ ev, ...(fields ? { f: fields } : {}) }) } })
    const done = p.run().finally(() => conn.close())
    cleanups.push(async () => { p.stop(); await done.catch(() => undefined) })
    return { p, done, events }
  }
  // The session id file is created by the first PullerState; make it exist before start() reads it.
  const { PullerState } = await import("../src/state.ts")
  new PullerState(stateDir).sessionId()
  return { f, client, stateDir, serveNodes, start }
}

const TWO_STEP = `export const meta = { name: "two-step", description: "d" }
const a = await agent("first", { label: "a" })
const b = await agent("second after " + a, { label: "b" })
return { a, b }
`

describe("lease loop, floor dispatch", () => {
  it("leases the run, dispatches its nodes to the floor, completes; after a kill it re-adopts the lease and resumes from the journal", async () => {
    const w = await world()
    await w.client.submitScript(TWO_STEP, { id: "pullrun0001" })
    const backends: Array<FloorBackend> = []
    const exec = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t", "runtime:gvisor"], defaultModel: "test-model", pollMs: 25, onBackend: (b) => backends.push(b) })

    const first = await w.start(exec)
    await until("node 1 enqueued", async () => (await w.client.runJobs("pullrun0001")).filter((j) => j.kind === "agent").length >= 1)
    expect((await w.client.job("run-pullrun0001")).holder).toBe("coord")
    expect(await w.serveNodes((p) => (p === "first" ? "A" : undefined))).toBe(1)
    await until("node 2 enqueued", async () => (await w.client.runJobs("pullrun0001")).filter((j) => j.kind === "agent").length >= 2)
    // The kill: the process stops with node 2 in flight. No verdict is sent; the lease is kept for re-adoption.
    first.p.stop(); await first.done
    expect(Object.keys(JSON.parse(readFileSync(join(w.stateDir, "held.json"), "utf8")))).toEqual(["run-pullrun0001-a1"])
    const journal = readFileSync(join(w.stateDir, "runs", "pullrun0001", "journal.jsonl"), "utf8")
    expect(journal.split("\n").filter((l) => l.includes("\"result\"")).length).toBe(1)
    expect((await w.client.run("pullrun0001")).state).toBe("running")

    const second = await w.start(exec)
    await until("re-adopted", () => second.events.some((e) => e.ev === "readopt"))
    await until("node 2 served", async () => (await w.serveNodes((p) => (p.startsWith("second") ? "B" : undefined))) > 0)
    const run = await w.client.waitRun("pullrun0001", { timeoutMs: 15_000, pollMs: 25 })
    expect([run.state, run.result]).toEqual(["done", "success"])
    const out = await w.client.output("run-pullrun0001")
    expect(out).toMatchObject({ result: "success", attempt: 1, output: { resumed: true, status: "completed", result: { a: "A", b: "B" } } })
    // Node 1 was a journal hit on the resume: never enqueued again. Node 2 was re-enqueued under the same name.
    expect(backends[1]!.enqueued).toEqual([backends[0]!.enqueued[1]])
    expect((await w.client.runJobs("pullrun0001")).filter((j) => j.kind === "agent").map((j) => j.name)).toHaveLength(2)
    await until("verdict flushed", () => !existsSync(join(w.stateDir, "outbox", "run-pullrun0001-a1.json")) && Object.keys(second.p.held).length === 0)
    const pullers = await w.client.pullers()
    expect(pullers.map((p) => p.holder).sort()).toEqual(["coord", "nas"])
  })

  it("a cancel reaches the running run through the heartbeat and is completed as cancelled", async () => {
    const w = await world()
    await w.client.submitScript(TWO_STEP, { id: "pullrun0002" })
    const exec = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 25 })
    const s = await w.start(exec)
    await until("node 1 enqueued", async () => (await w.client.runJobs("pullrun0002")).filter((j) => j.kind === "agent").length >= 1)
    await w.client.cancelRun("pullrun0002")
    await until("cancel requested", () => s.events.some((e) => e.ev === "cancel-requested"))
    await until("interpreter job done", async () => (await w.client.job("run-pullrun0002")).state === "done")
    expect((await w.client.output("run-pullrun0002")).result).toBe("cancelled")
    expect(s.events.find((e) => e.ev === "run-end")?.f).toMatchObject({ aborted: "cancel" })
  })

  it("refuses a script that does not hash to the grant's content address", async () => {
    const w = await world()
    await w.client.submitScript(TWO_STEP, { id: "pullrun0003" })
    const s = await w.start(async () => { throw new Error("must not run") })
    // Tamper with what the floor serves: the grant still carries the original sha256.
    const orig = w.client.runScript.bind(w.client)
    ;(s.p.deps.client as { runScript: (id: string) => Promise<string> }).runScript = async (id) => (await orig(id)) + "\n// tampered"
    await until("done", async () => (await w.client.job("run-pullrun0003")).state === "done")
    expect((await w.client.output("run-pullrun0003")).output).toMatchObject({ reason: "pre-start/script-mismatch" })
  })
})

describe("local executor (the repo's runners)", () => {
  const bin = mkdtempSync(join(tmpdir(), "substrate-puller-bin-"))
  const saved = process.env.PATH
  beforeAll(() => {
    writeFileSync(join(bin, "claude"), `#!/bin/sh\np=$(cat)\ncase "$p" in\n  *gold*) echo '{"type":"result","subtype":"success","is_error":false,"session_id":"s-gold","result":"Au","usage":{"input_tokens":3,"output_tokens":1}}' ;;\nesac\n`)
    chmodSync(join(bin, "claude"), 0o755)
    process.env.PATH = `${bin}:${saved}`
  })
  afterAll(() => { process.env.PATH = saved })

  it("runs a leased run with runIntegrated on a host runtime and completes it with the return value", async () => {
    const w = await world()
    await w.client.submitScript(`export const meta = { name: "gold", description: "d" }\nreturn await agent("say gold")\n`, { id: "pullrun0004" })
    const runtimes = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\nharness = "claude"\n`, "test")
    await w.start(localExecutor({ runtimes, seat: "fake", defaultModel: "fake-model", cap: 1, maxAttempts: 1 }))
    const run = await w.client.waitRun("pullrun0004", { timeoutMs: 30_000, pollMs: 25 })
    expect([run.state, run.result]).toEqual(["done", "success"])
    expect((await w.client.output("run-pullrun0004")).output).toMatchObject({ status: "completed", result: "Au", outcome: "all-done" })
    expect(existsSync(join(w.stateDir, "runs", "pullrun0004", "journal.jsonl"))).toBe(true)
  })

  it("AUDIT-transcripts TX2: every node's archived transcript reaches the floor under the run's job before the verdict", async () => {
    const w = await world()
    await w.client.submitScript(`export const meta = { name: "txs", description: "d" }\nreturn await agent("say gold")\n`, { id: "pullrun0006" })
    const runtimes = parseRuntimesToml(`default = "h"\n[runtime.h]\ntype = "host"\nharness = "claude"\n`, "test")
    await w.start(localExecutor({ runtimes, seat: "fake", defaultModel: "fake-model", cap: 1, maxAttempts: 1, transcripts: { client: w.client } }))
    const run = await w.client.waitRun("pullrun0006", { timeoutMs: 30_000, pollMs: 25 })
    expect([run.state, run.result]).toEqual(["done", "success"])
    const out = (await w.client.output("run-pullrun0006")).output as { transcripts: { uploaded: number; failed: Array<unknown> } }
    expect(out.transcripts.uploaded).toBeGreaterThan(0)
    expect(out.transcripts.failed).toEqual([])
    const m = await w.client.transcripts("run-pullrun0006")
    const stdout = m.parts.find((p) => p.part.endsWith("__harness.stdout"))!
    expect(stdout.committed).toBe(true)
    expect(await w.client.transcript("run-pullrun0006", stdout.part)).toContain("Au")
  })

  it("the floor-dispatch outcome carries a reported session id as agentId (TX3)", () => {
    expect(outcomeOf({ result: "success", output: { text: "x", sessionId: "sess-1" }, usage: null }, false)).toEqual({ text: "x", agentId: "sess-1" })
    expect(outcomeOf({ result: "success", output: { text: "x" }, usage: null }, false)).toEqual({ text: "x" })
    expect(transcriptPartName("wf_a-1-a1", "claude-x/y.jsonl")).toBe("wf_a-1-a1__claude-x_y.jsonl")
    expect(transcriptPartName("j", "f".repeat(300)).length).toBe(200)
  })

  it("an ax runtime is refused with the reason, and the run fails with it", async () => {
    const w = await world()
    await w.client.submitScript(`export const meta = { name: "axed", description: "d" }\nconst r = await agent("say gold")\nif (r === null) throw new Error("the ax node was refused")\nreturn r\n`, { id: "pullrun0005" })
    const runtimes = parseRuntimesToml(`default = "axr"\n[runtime.axr]\ntype = "ax"\n`, "test")
    await w.start(localExecutor({ runtimes, seat: "fake", defaultModel: "fake-model", cap: 1, maxAttempts: 1, axServer: "127.0.0.1:1" }))
    const run = await w.client.waitRun("pullrun0005", { timeoutMs: 30_000, pollMs: 25 })
    expect([run.state, run.result]).toEqual(["done", "failure"])
    expect((await w.client.output("run-pullrun0005")).output).toMatchObject({ reason: "agent/script-failed" })
    const ledger = readFileSync(join(w.stateDir, "runs", "pullrun0005", "ledger.jsonl"), "utf8")
    expect(ledger).toMatch(/ax-server 127\.0\.0\.1:1 is not reachable/)
  })
})

describe("process", () => {
  it("holds a pidfile: a live holder refuses a second copy, a dead one is replaced", () => {
    const dir = mkdtempSync(join(tmpdir(), "substrate-pid-"))
    const path = join(dir, "puller.pid")
    writeFileSync(path, `${process.pid}\n`)
    expect(() => acquirePidfile(path, "node", 2_000_000_000)).toThrow(PidfileHeld)
    writeFileSync(path, "2000000001\n")
    const release = acquirePidfile(path, "node", 2_000_000_000)
    expect(readFileSync(path, "utf8").trim()).toBe("2000000000")
    release()
    expect(existsSync(path)).toBe(false)
  })

  it("main refuses to start without a [puller] config (exit 78)", async () => {
    const dir = mkdtempSync(join(tmpdir(), "substrate-pcfg-"))
    writeFileSync(join(dir, "config.toml"), `floor_url = "http://floor.test"\n`)
    const writes: Array<string> = []
    const orig = process.stdout.write.bind(process.stdout)
    process.stdout.write = ((s: string) => { writes.push(s); return true }) as typeof process.stdout.write
    try { expect(await main({ SUBSTRATE_CLIENT_CONFIG: join(dir, "config.toml") })).toBe(78) } finally { process.stdout.write = orig }
    expect(writes.join("")).toMatch(/config-invalid.*holder is required/)
  })
})
