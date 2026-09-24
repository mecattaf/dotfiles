// Codex review 3 (2026-09-24): each confirmed finding as the test that failed before its fix.
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { contentHash, FileJournal, parseJournal } from "@substrate/interpreter"
import { connectFloor } from "../src/connect.ts"
import { floorExecutor, nodeJob } from "../src/execute.ts"
import { Puller } from "../src/puller.ts"
import type { Executor, FloorPort, RunTask } from "../src/puller.ts"
import { PullerState } from "../src/state.ts"

const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 10_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 20)) }
}
const T = { floor: "r3-floor", coord: "r3-coord" }
const world = async () => {
  const f = localFloor({ floorToken: T.floor, links: [{ token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] }],
    vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1" } })
  const client = new SubstrateClient({ url: "http://floor.test", token: T.floor, fetch: f.fetch })
  const stateDir = mkdtempSync(join(tmpdir(), "substrate-r3-"))
  const sid = new PullerState(stateDir).sessionId()
  const conns: Array<{ close: () => unknown }> = []
  const start = async (execute: Executor, wrap: (p: FloorPort) => FloorPort = (p) => p) => {
    const conn = await connectFloor({ url: "http://floor.test", token: T.coord, sessionId: sid, fetch: f.fetch }); conns.push(conn)
    const events: Array<string> = []
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, pollMs: 25, heartbeatMs: 100 }, { floor: wrap(conn.port), client, execute, log: (ev) => events.push(ev) })
    const done = p.run().catch(() => undefined)
    return { p, done, events }
  }
  const close = async () => { for (const c of conns) await c.close(); f.close() }
  return { f, client, stateDir, start, close }
}
const SCRIPT = `export const meta = { name: "r3", description: "d" }\nreturn "ok"\n`
/** A run leased by a first puller whose executor never ends, then that puller stopped: the grant stays in held.json. */
const heldRun = async (w: Awaited<ReturnType<typeof world>>, id: string) => {
  await w.client.submitScript(SCRIPT, { id })
  const first = await w.start((t) => new Promise((ok) => t.signal.addEventListener("abort", () => ok({ result: "failure", output: null }), { once: true })))
  await until("leased", () => Object.keys(first.p.held).length === 1)
  first.p.stop(); await first.done
  return Object.keys(JSON.parse(readFileSync(join(w.stateDir, "held.json"), "utf8")))[0]!
}

describe("codex review 3: the puller", () => {
  it("C3-1: a failed start-up heartbeat does not strand a held run; the next renewal launches it", async () => {
    const w = await world()
    try {
      await heldRun(w, "r3run0001")
      let runs = 0, first = true
      const s = await w.start(async () => { runs++; return { result: "success", output: "ok" } },
        (p) => ({ ...p, heartbeat: (q) => { if (first) { first = false; return Promise.reject(new Error("socket hang up")) } return p.heartbeat(q) } }))
      await until("the run executed", () => runs === 1)
      await until("done", async () => (await w.client.job("run-r3run0001")).state === "done")
      expect((await w.client.output("run-r3run0001")).result).toBe("success")
      s.p.stop(); await s.done
    } finally { await w.close() }
  })
  it("C3-2: a held run whose verdict waits in the outbox is never executed again, and that verdict is the one delivered", async () => {
    const w = await world()
    try {
      const leaseId = await heldRun(w, "r3run0002")
      new PullerState(w.stateDir).putVerdict({ leaseId, attempt: 1, result: "failure", output: { reason: "agent/script-failed", message: "the first execution" } })
      let runs = 0, fails = 2
      const s = await w.start(async () => { runs++; return { result: "success", output: "second execution" } },
        (p) => ({ ...p, complete: (q) => fails-- > 0 ? Promise.reject(new Error("socket hang up")) : p.complete(q) }))
      await until("done", async () => (await w.client.job("run-r3run0002")).state === "done")
      expect(runs).toBe(0)
      expect((await w.client.output("run-r3run0002")).result).toBe("failure")
      s.p.stop(); await s.done
    } finally { await w.close() }
  })
})

// ---------------------------------------------------------------- the floor executor with a scripted client
type J = { name: string; state: string; result?: { result: string; output: unknown } }
const fakeClient = (answer: (prompt: string) => { result: string; output: unknown } | "hold", hooks: { enqueueFailures?: number; jobGate?: Promise<void> } = {}) => {
  const jobs = new Map<string, J & { prompt: string }>()
  let enqueueFailures = hooks.enqueueFailures ?? 0
  const client = {
    enqueued: 0,
    async enqueue(_run: string, list: Array<any>) {
      for (const j of list) if (!jobs.has(j.metadata.name)) { client.enqueued++; jobs.set(j.metadata.name, { name: j.metadata.name, state: "queued", prompt: j.spec.with.prompt }) }
      if (enqueueFailures-- > 0) throw new TypeError("fetch failed") // committed, then the answer was lost
      return { enqueued: [] }
    },
    async job(name: string) {
      if (hooks.jobGate) await hooks.jobGate
      const j = jobs.get(name)!
      const a = answer(j.prompt)
      if (a !== "hold") { j.state = "done"; j.result = a }
      return { name, state: j.state } as never
    },
    async output(name: string) { const j = jobs.get(name)!; return { ...j.result!, usage: null, attempt: 1, leaseId: "", bytes: 0 } as never }
  }
  return client
}
const task = (script: string, signal: AbortSignal): RunTask => {
  const dir = mkdtempSync(join(tmpdir(), "substrate-r3-run-"))
  const scriptPath = join(dir, "script.js"); writeFileSync(scriptPath, script)
  return { runId: "r3x", leaseId: "run-r3x-a1", attempt: 1, job: {} as never, workflowName: "r3", args: undefined, dir, scriptPath, script, signal }
}

describe("codex review 3: the floor executor", () => {
  it("C3-9: a node that failed and a script that returned anyway is a failed run, not a success", async () => {
    const c = fakeClient(() => ({ result: "failure", output: { reason: "agent/failed" } }))
    const v = await floorExecutor({ client: c as never, defaultRunsOn: ["seat:t"], defaultModel: "m", pollMs: 5 })(
      task(`export const meta = { name: "r3", description: "d" }\nconst a = await agent("x")\nreturn a\n`, new AbortController().signal))
    expect(v.result).toBe("failure")
  })
  it("C3-10: a lost enqueue answer is retried, not a failed run", async () => {
    const c = fakeClient(() => ({ result: "success", output: "A" }), { enqueueFailures: 1 })
    const v = await floorExecutor({ client: c as never, defaultRunsOn: ["seat:t"], defaultModel: "m", pollMs: 5 })(
      task(`export const meta = { name: "r3", description: "d" }\nreturn await agent("x")\n`, new AbortController().signal))
    expect([v.result, (v.output as any).result, c.enqueued]).toEqual(["success", "A", 1])
  })
  it("C3-11: after an abort the interpreter dispatches no continuation", async () => {
    let open!: () => void
    const gate = new Promise<void>((ok) => { open = ok })
    const c = fakeClient(() => ({ result: "success", output: "A" }), { jobGate: gate })
    const ac = new AbortController()
    const p = floorExecutor({ client: c as never, defaultRunsOn: ["seat:t"], defaultModel: "m", pollMs: 5 })(
      task(`export const meta = { name: "r3", description: "d" }\nconst a = await agent("x")\nconst b = await agent("y " + a)\nreturn b\n`, ac.signal))
    await until("node 1 enqueued", () => c.enqueued === 1)
    ac.abort(); await p
    open(); await new Promise((r) => setTimeout(r, 100))
    expect(c.enqueued).toBe(1)
  })
  it("C3-7: a node's floor name and body do not depend on its invocation index", () => {
    const call = (index: number, key: string) => ({ index, key, prompt: "act A", opts: {}, phase: undefined, attempt: 1, occurrence: 1, cid: `c1:${contentHash("act A", {})}#1` })
    const o = { runId: "r3x", workflow: "w", defaultRunsOn: ["seat:t"], defaultModel: "m" }
    const a = nodeJob(call(4, "v2:" + "a".repeat(64)) as never, o), b = nodeJob(call(3, "v2:" + "b".repeat(64)) as never, o)
    expect(a.metadata.name).toBe(b.metadata.name)
    // critique pass 2026-09-24 (durability-r1-1): the whole body, not only the name, since the floor compares bodies
    expect(JSON.stringify(a)).toBe(JSON.stringify(b))
    expect(a.metadata.annotations!["ultracode.mecattaf.dev/journal-key"]).toMatch(/^[0-9a-f]{64}:1$/) // the NAS link's JOURNAL_KEY form
  })
  it("C3-8: one prompt on two runtimes is two contents; without a route the content hash is unchanged", () => {
    expect(contentHash("act", { runtime: "a" })).not.toBe(contentHash("act", { runtime: "b" }))
    expect(contentHash("act", { label: "x" })).toBe(contentHash("act", {}))
  })
  it("C3-6: a journal whose last line lost its newline keeps that event after the next append", () => {
    const dir = mkdtempSync(join(tmpdir(), "substrate-r3-j-"))
    const path = join(dir, "journal.jsonl")
    const k = (c: string) => "v2:" + c.repeat(64)
    writeFileSync(path, JSON.stringify({ type: "launched" }) + "\n" + JSON.stringify({ type: "started", key: k("a"), agentId: "x" }) + "\n" + JSON.stringify({ type: "result", key: k("a"), agentId: "x", result: "A" }))
    expect(parseJournal(readFileSync(path, "utf8")).results.size).toBe(1)
    new FileJournal(path).append({ type: "started", key: k("b"), agentId: "y" } as never)
    const after = parseJournal(readFileSync(path, "utf8"))
    expect(after.results.size).toBe(1)
    expect(after.skippedLines ?? 0).toBe(0)
    expect(existsSync(path)).toBe(true)
  })
})
