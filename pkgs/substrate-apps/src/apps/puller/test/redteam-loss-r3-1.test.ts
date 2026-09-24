// Red team loss-and-wip r3-1 (critique pass KEEP-12): a failed start-up re-adoption never lets the puller hold more runs than maxRuns.
// CONTROL: an identical kill and restart with no Heartbeat failure must finish the run (so any failure below is the
// transient readopt error, not the harness). CASE A: one transient failure on the restart's first Heartbeat.
// CASE B: the same, then a second run is submitted; maxRuns is 1.
import { mkdtempSync, readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { FloorError } from "@substrate/link/floor.ts"
import { connectFloor } from "../src/connect.ts"
import { floorExecutor } from "../src/execute.ts"
import { Puller } from "../src/puller.ts"
import type { Executor, FloorPort } from "../src/puller.ts"
import { PullerState } from "../src/state.ts"

const T = { floor: "rf-floor", coord: "rf-coord", nas: "rf-nas" }
const URL_ = "http://floor.test"
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })
const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 15_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 20)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const TWO_STEP = `export const meta = { name: "two-step", description: "d" }
const a = await agent("first", { label: "a" })
const b = await agent("second after " + a, { label: "b" })
return { a, b }
`
const world = async () => {
  const f = localFloor({ floorToken: T.floor, links: [
    { token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] },
    { token: T.nas, holder: "nas", labels: ["seat:t", "runtime:*"] }
  ], vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "2", FLOOR_GRACE_SECONDS: "2", FLOOR_POLL_SECONDS: "1" } })
  cleanups.push(() => f.close())
  const client = new SubstrateClient({ url: URL_, token: T.floor, fetch: f.fetch })
  const stateDir = mkdtempSync(join(tmpdir(), "rf-puller-"))
  new PullerState(stateDir).sessionId()
  const nas = await connectFloor({ url: URL_, token: T.nas, sessionId: "nas-session", fetch: f.fetch })
  cleanups.push(() => nas.close())
  const serveNodes = async () => {
    const r = await nas.port.lease({ holderIdentity: "nas", capacity: 10, requestKey: crypto.randomUUID() })
    for (const g of r.grants) {
      const p = g.job.spec.with.prompt ?? ""
      const out = p === "first" ? "A" : p.startsWith("second") ? "B" : undefined
      if (out !== undefined) await nas.port.complete({ leaseId: g.leaseId, attempt: g.attempt, result: "success", output: out })
    }
  }
  const start = async (execute: Executor, wrap: (p: FloorPort) => FloorPort = (p) => p) => {
    const conn = await connectFloor({ url: URL_, token: T.coord, sessionId: readFileSync(join(stateDir, "session-id"), "utf8").trim(), fetch: f.fetch })
    const events: Array<{ ev: string; f?: Record<string, unknown> }> = []
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir, pollMs: 25, heartbeatMs: 150 }, { floor: wrap(conn.port), client, execute, log: (ev, fields) => { events.push({ ev, ...(fields ? { f: fields } : {}) }) } })
    const done = p.run().finally(() => conn.close())
    cleanups.push(async () => { p.stop(); await done.catch(() => undefined) })
    return { p, done, events }
  }
  return { client, serveNodes, start }
}
const failFirstHeartbeat = (port: FloorPort): FloorPort => {
  let failed = 0
  return { ...port, heartbeat: async (p) => { if (failed++ === 0) throw new FloorError("transient", "connection reset at boot"); return port.heartbeat(p) } }
}
const killAfterNode1 = async (w: Awaited<ReturnType<typeof world>>, id: string, exec: Executor) => {
  await w.client.submitScript(TWO_STEP, { id })
  const first = await w.start(exec)
  await until("node 1 enqueued", async () => (await w.client.runJobs(id)).filter((j: any) => j.kind === "agent").length >= 1)
  first.p.stop(); await first.done
}
const mkExec = (w: Awaited<ReturnType<typeof world>>) => floorExecutor({ client: w.client, defaultRunsOn: ["seat:t", "runtime:gvisor"], defaultModel: "test-model", pollMs: 25 })

describe("loss-and-wip-r3-1: re-adoption and maxRuns", () => {
  it("CONTROL: a clean restart re-adopts and finishes the run", async () => {
    const w = await world(); const exec = mkExec(w)
    await killAfterNode1(w, "rfrun00000", exec)
    const second = await w.start(exec)
    const end = Date.now() + 8_000
    while (Date.now() < end && (await w.client.run("rfrun00000")).state !== "done") { await w.serveNodes(); await sleep(100) }
    const run = await w.client.run("rfrun00000")
    console.log("CONTROL", JSON.stringify({ runState: run.state, readopt: second.events.some((e) => e.ev === "readopt") }))
    expect(run.state).toBe("done")
  }, 30_000)

  it("CASE A: one transient first Heartbeat after restart; the run must still finish", async () => {
    const w = await world(); const exec = mkExec(w)
    await killAfterNode1(w, "rfrun00001", exec)
    const second = await w.start(exec, failFirstHeartbeat)
    const end = Date.now() + 10_000
    while (Date.now() < end && (await w.client.run("rfrun00001")).state !== "done") { await w.serveNodes(); await sleep(100) }
    const job = await w.client.job("run-rfrun00001"), run = await w.client.run("rfrun00001")
    console.log("CASE A", JSON.stringify({ runState: run.state, jobState: job.state, holder: job.holder, attempt: job.attempt,
      readopt: second.events.some((e) => e.ev === "readopt"), runStart: second.events.filter((e) => e.ev === "run-start").length,
      readoptErrors: second.events.filter((e) => e.ev === "readopt-error").length, heartbeatErrors: second.events.filter((e) => e.ev === "heartbeat-error").length,
      held: Object.keys(second.p.held), active: [...second.p.active.keys()] }))
    expect(run.state).toBe("done")
  }, 30_000)

  it("CASE B: with the un-readopted run held, maxRuns 1 must not hold a second run", async () => {
    const w = await world(); const exec = mkExec(w)
    await killAfterNode1(w, "rfrun00002", exec)
    const second = await w.start(exec, failFirstHeartbeat)
    await w.client.submitScript(TWO_STEP.replace("two-step", "other"), { id: "rfrun00003" })
    let leased = true
    try { await until("second run leased by coord", async () => (await w.client.job("run-rfrun00003")).holder === "coord", 2_000) } catch { leased = false }
    await sleep(1_000)
    const a = await w.client.job("run-rfrun00002"), b = await w.client.job("run-rfrun00003")
    console.log("CASE B", JSON.stringify({ leased, zombie: [a.state, a.holder, a.attempt], other: [b.state, b.holder], held: Object.keys(second.p.held), active: [...second.p.active.keys()] }))
    expect(Object.keys(second.p.held).length).toBeLessThanOrEqual(1)
  }, 30_000)
  it("CASE C: after CASE B, both runs finish one after the other, never both held", async () => {
    const w = await world(); const exec = mkExec(w)
    await killAfterNode1(w, "rfrun00012", exec)
    const second = await w.start(exec, failFirstHeartbeat)
    await w.client.submitScript(TWO_STEP.replace("two-step", "other"), { id: "rfrun00013" })
    let maxHeld = 0
    const end = Date.now() + 20_000
    while (Date.now() < end && ((await w.client.run("rfrun00012")).state !== "done" || (await w.client.run("rfrun00013")).state !== "done")) {
      maxHeld = Math.max(maxHeld, Object.keys(second.p.held).length); await w.serveNodes(); await sleep(100)
    }
    const a = await w.client.run("rfrun00012"), b = await w.client.run("rfrun00013")
    console.log("CASE C", JSON.stringify({ maxHeld, zombie: [a.state, a.result], other: [b.state, b.result] }))
    expect([a.state, b.state]).toEqual(["done", "done"])
    expect(maxHeld).toBeLessThanOrEqual(1)
  }, 40_000)
})
