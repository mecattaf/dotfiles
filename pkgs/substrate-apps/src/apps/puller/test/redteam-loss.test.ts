// Red team loss-and-wip, the puller's leftovers (critique pass 2026-09-24, KEEP-3 and KEEP-7): the coordinator puller
// against the real floor (localFloor over node:sqlite). Each case failed on 2882545.
import { existsSync, mkdtempSync, readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { SubstrateClient, SubstrateError } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"

import { connectFloor } from "../src/connect.ts"
import { floorExecutor } from "../src/execute.ts"
import { Puller } from "../src/puller.ts"
import { FloorError } from "@substrate/link/floor.ts"
import type { Executor } from "../src/puller.ts"
import type { FloorPort } from "../src/puller.ts"
import { PullerState } from "../src/state.ts"

const T = { floor: "rt-floor", coord: "rt-coord", nas: "rt-nas" }
const URL_ = "http://floor.test"
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })

const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 15_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 20)) }
}

const world = async (vars: Record<string, string> = {}) => {
  const f = localFloor({ floorToken: T.floor, links: [
    { token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] },
    { token: T.nas, holder: "nas", labels: ["seat:t", "runtime:*"] }
  ], vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1", ...vars } as never })
  cleanups.push(() => f.close())
  const client = new SubstrateClient({ url: URL_, token: T.floor, fetch: f.fetch })
  const stateDir = mkdtempSync(join(tmpdir(), "substrate-rt-puller-"))
  new PullerState(stateDir).sessionId()
  const nas = await connectFloor({ url: URL_, token: T.nas, sessionId: "nas-session", fetch: f.fetch })
  cleanups.push(() => nas.close())
  const serveNodes = async (answer: (prompt: string) => unknown | undefined) => {
    const r = await nas.port.lease({ holderIdentity: "nas", capacity: 10, requestKey: crypto.randomUUID() })
    for (const g of r.grants) {
      const out = answer(g.job.spec.with.prompt ?? "")
      if (out !== undefined) await nas.port.complete({ leaseId: g.leaseId, attempt: g.attempt, result: "success", output: out })
    }
    return r.grants.length
  }
  const start = async (execute: Executor, o: { maxRuns?: number; verdictAttempts?: number; port?: (real: FloorPort) => FloorPort; client?: SubstrateClient } = {}) => {
    const conn = await connectFloor({ url: URL_, token: T.coord, sessionId: readFileSync(join(stateDir, "session-id"), "utf8").trim(), fetch: f.fetch })
    const events: Array<{ ev: string; f?: Record<string, unknown> }> = []
    const port = o.port ? o.port(conn.port) : conn.port
    const p = new Puller({ holder: "coord", maxRuns: o.maxRuns ?? 1, stateDir, pollMs: 25, heartbeatMs: 150, ...(o.verdictAttempts !== undefined ? { verdictAttempts: o.verdictAttempts } : {}) },
      { floor: port, client: o.client ?? client, execute, log: (ev, fields) => { if (process.env.PULLER_DEBUG) console.error(ev, JSON.stringify(fields)); events.push({ ev, ...(fields ? { f: fields } : {}) }) } })
    const done = p.run().finally(() => conn.close())
    cleanups.push(async () => { p.stop(); await done.catch(() => undefined) })
    return { p, done, events }
  }
  return { f, client, stateDir, serveNodes, start }
}

const ONE_STEP = `export const meta = { name: "one-step", description: "d" }
const a = await agent("first", { label: "a" })
return { a }
`


/** A server error for Complete calls carrying this lease's verdict of this result; everything else is the real floor. */
const refuse = (leaseId: string, result: string, status: number | undefined, counter: { n: number }) => (port: FloorPort): FloorPort => ({
  ...port, complete: async (p) => { if (p.leaseId === leaseId && p.result === result) { counter.n++; throw new FloorError("server-error", `floor answered ${status ?? "a Defect"}`, undefined, status) } return port.complete(p) }
})
const serveUntilDone = async (w: Awaited<ReturnType<typeof world>>, id: string, ms = 15_000) => {
  const end = Date.now() + ms
  let run: any
  while (Date.now() < end) { await w.serveNodes(() => "ok"); run = await w.client.run(id); if (run.state === "done") break; await new Promise((r) => setTimeout(r, 25)) }
  return run
}

describe("KEEP-3 (r2-2): a verdict the floor keeps refusing with a server error", () => {
  it("is replaced by a typed failure naming its output after verdictAttempts, and no new run is leased while it waits", async () => {
    const w = await world()
    const exec = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 25 })
    const hits = { n: 0 }
    const s = await w.start(exec, { verdictAttempts: 3, port: refuse("run-rlk3run001-a1", "success", 500, hits) })
    await w.client.submitScript(ONE_STEP, { id: "rlk3run001" })
    await until("run 1 node", async () => (await w.client.runJobs("rlk3run001")).filter((j: any) => j.kind === "agent").length >= 1)
    await w.client.submitScript(ONE_STEP.replace("one-step", "second"), { id: "rlk3run002" })
    await until("run 1 finished here", async () => { await w.serveNodes(() => "ok"); return s.events.some((e) => e.ev === "run-end" && e.f?.leaseId === "run-rlk3run001-a1") })
    const run1 = await serveUntilDone(w, "rlk3run001")
    const out = await w.client.output("run-rlk3run001") as { result: string; output: { reason?: string; replaces?: string; outputSha256?: string } }
    expect([run1.state, out.result, out.output.reason, out.output.replaces]).toEqual(["done", "failure", "infra/verdict-undeliverable", "success"])
    expect(out.output.outputSha256).toMatch(/^[0-9a-f]{64}$/)
    expect(hits.n).toBeGreaterThanOrEqual(3) // every send is refused; only those after a floor answer are charged
    // maxRuns 1: run 2 starts only after run 1's verdict left the outbox
    const idx = (ev: string, lease: string) => s.events.findIndex((e) => e.ev === ev && e.f?.leaseId === lease)
    expect(idx("verdict-replaced", "run-rlk3run001-a1")).toBeGreaterThanOrEqual(0)
    const run2 = await serveUntilDone(w, "rlk3run002")
    expect(run2.result).toBe("success")
    expect(idx("run-start", "run-rlk3run002-a1")).toBeGreaterThan(idx("verdict-replaced", "run-rlk3run001-a1"))
  }, 40_000)

  it("a later cancel never overwrites the success waiting in the outbox", async () => {
    const w = await world()
    const exec = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 25 })
    const hits = { n: 0 }
    const s = await w.start(exec, { verdictAttempts: 1_000_000, port: refuse("run-rlk3run003-a1", "success", 500, hits) })
    await w.client.submitScript(ONE_STEP, { id: "rlk3run003" })
    await until("run finished here", async () => { await w.serveNodes(() => "ok"); return s.events.some((e) => e.ev === "run-end" && e.f?.leaseId === "run-rlk3run003-a1") })
    await until("a few refusals", () => hits.n >= 3)
    await w.client.cancelJob("run-rlk3run003")
    await until("the cancel was heard", () => s.events.some((e) => e.ev === "cancel-requested" && e.f?.leaseId === "run-rlk3run003-a1"))
    await until("one more refusal", () => { const n = hits.n; return new Promise((r) => setTimeout(() => r(hits.n > n), 200)) })
    const file = JSON.parse(readFileSync(join(w.stateDir, "outbox", "run-rlk3run003-a1.json"), "utf8")) as { result: string }
    expect(file.result).toBe("success")
    expect((await w.client.job("run-rlk3run003")).state).not.toBe("done")
  }, 40_000)

  it("control: an HTTP 5xx with no floor answer since the last one is not charged (a floor-wide outage)", async () => {
    const w = await world()
    const exec = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 25 })
    let down = false, tripped = false, n = 0
    const outage = (port: FloorPort): FloorPort => {
      const gate = async <T>(f: () => Promise<T>) => { if (down) { n++; throw new FloorError("server-error", "floor answered 500", undefined, 500) } return f() }
      return { lease: (p) => gate(() => port.lease(p)), heartbeat: (p) => gate(() => port.heartbeat(p)), complete: (p) => { if (!tripped && p.result === "success" && p.leaseId === "run-rlk3run004-a1") { tripped = true; down = true } return gate(() => port.complete(p)) } }
    }
    const s = await w.start(exec, { verdictAttempts: 2, port: outage })
    await w.client.submitScript(ONE_STEP, { id: "rlk3run004" })
    await until("run finished here", async () => { await w.serveNodes(() => "ok"); return s.events.some((e) => e.ev === "run-end" && e.f?.leaseId === "run-rlk3run004-a1") })
    await until("many 500s", () => n >= 10)
    down = false
    const run = await serveUntilDone(w, "rlk3run004")
    expect([run.state, run.result]).toEqual(["done", "success"])
    expect(s.events.some((e) => e.ev === "verdict-replaced")).toBe(false)
  }, 40_000)
})

describe("KEEP-7 (r2-1 residual): a host I/O error in the executor is retried, not final", () => {
  it("the executor throws ENOSPC once; the floor requeues and the run finishes success", async () => {
    const w = await world()
    await w.client.submitScript(ONE_STEP, { id: "rlk7run001" })
    const real = floorExecutor({ client: w.client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 25 })
    let n = 0
    const exec: Executor = async (x) => { if (n++ === 0) throw Object.assign(new Error("ENOSPC: no space left on device, write"), { code: "ENOSPC" }); return real(x) }
    await w.start(exec)
    const run = await serveUntilDone(w, "rlk7run001")
    const job = await w.client.job("run-rlk7run001")
    expect([run.state, run.result, job.attempt]).toEqual(["done", "success", 2])
  }, 30_000)
  it("control: any other executor exception stays final (infra/puller-defect)", async () => {
    const w = await world()
    await w.client.submitScript(ONE_STEP, { id: "rlk7run002" })
    await w.start(async () => { throw new TypeError("x is not a function") })
    await until("run done", async () => (await w.client.run("rlk7run002")).state === "done")
    const out = await w.client.output("run-rlk7run002") as { result: string; output: { reason: string } }
    expect([out.result, out.output.reason]).toEqual(["failure", "infra/puller-defect"])
  }, 30_000)
})
