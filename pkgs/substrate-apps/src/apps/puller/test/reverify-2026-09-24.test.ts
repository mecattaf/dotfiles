// Critique pass 2026-09-24 (AUDIT-reverify-interp): C3-4 and C3-5 on the floor-dispatch path against the REAL floor
// (the Worker entry and Floor object over node:sqlite, apps/floor/src/local.ts), not a double. The floor must keep a
// finished node's name and verdict for as long as a run can resume, so a resumed executor adopts it by name.
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { connectFloor } from "../src/connect.ts"
import { floorExecutor } from "../src/execute.ts"
import type { RunTask } from "../src/puller.ts"

const T = { floor: "rv-floor", nas: "rv-nas", coord: "rv-coord" }
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })
const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 10_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 20)) }
}
const S = `export const meta = { name: "rv", description: "d" }\nconst a = await agent("prep")\nconst b = await agent("act " + a)\nreturn b\n`

const world = async (id: string) => {
  const f = localFloor({ floorToken: T.floor, links: [
    { token: T.coord, holder: "coord", labels: ["runtime:interpreter", "seat:interp"] },
    { token: T.nas, holder: "nas", labels: ["seat:t", "runtime:*"] }
  ], vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1" } })
  cleanups.push(() => f.close())
  const client = new SubstrateClient({ url: "http://floor.test", token: T.floor, fetch: f.fetch })
  const nas = await connectFloor({ url: "http://floor.test", token: T.nas, sessionId: "rv-nas-session", fetch: f.fetch })
  cleanups.push(() => nas.close())
  await client.submitScript(S, { id })
  // G-BK5 (merged after this test was written): node enqueues name the run's live interpreter lease, so the run is
  // really leased. Both executors run under that one lease: the second is the puller re-adopting it after the kill
  // (the node name carries the CALL's attempt, not the run's, so adoption by name is what is tested either way).
  const interp = await connectFloor({ url: "http://floor.test", token: T.coord, sessionId: "rv-coord-session", fetch: f.fetch })
  cleanups.push(() => interp.close())
  const runGrant = (await interp.port.lease({ holderIdentity: "coord", capacity: 1, requestKey: crypto.randomUUID() })).grants.find((g) => g.leaseId === `run-${id}-a1`)
  if (!runGrant) throw new Error("the run was not leased to the interpreter link")
  const dir = mkdtempSync(join(tmpdir(), "substrate-rv-run-"))
  const scriptPath = join(dir, "script.js"); writeFileSync(scriptPath, S)
  const task = (_attempt: number, signal: AbortSignal): RunTask =>
    ({ runId: id, leaseId: runGrant.leaseId, attempt: runGrant.attempt, job: {} as never, workflowName: "rv", args: undefined, dir, scriptPath, script: S, signal })
  /** The NAS link by hand: lease what is queued and answer each node by its prompt; counts grants. */
  let grants = 0
  const serve = async (answer: (prompt: string) => { result: "success" | "failure"; output: unknown } | undefined) => {
    const r = await nas.port.lease({ holderIdentity: "nas", capacity: 10, requestKey: crypto.randomUUID() })
    for (const g of r.grants) {
      grants++
      const a = answer(g.job.spec.with.prompt ?? "")
      if (a) await nas.port.complete({ leaseId: g.leaseId, attempt: g.attempt, result: a.result, output: a.output, usage: { prompt_tokens: 3, completion_tokens: 1, tool_calls: 0 } })
    }
    return r.grants.length
  }
  const agentJobs = async () => (await client.runJobs(id)).filter((j) => j.kind === "agent")
  const exec = floorExecutor({ client, defaultRunsOn: ["seat:t"], defaultModel: "m", pollMs: 20, maxAttempts: 2 })
  return { client, task, serve, agentJobs, exec, grants: () => grants }
}

describe("floor retention: a resumed executor adopts finished nodes by name", () => {
  it("C3-4: a node that finished while no executor watched is adopted, with no new node and no new lease", async () => {
    const w = await world("rvrun0034")
    const ac = new AbortController()
    const p1 = w.exec(w.task(1, ac.signal))
    await until("prep enqueued", async () => (await w.agentJobs()).length >= 1)
    await until("prep served", async () => (await w.serve((p) => (p === "prep" ? { result: "success", output: "A" } : undefined))) === 1)
    await until("act enqueued", async () => (await w.agentJobs()).length >= 2)
    ac.abort() // the executor is killed with act in flight; act keeps its lease on the NAS link
    await p1.catch(() => undefined)
    await until("act served", async () => (await w.serve((p) => (p.startsWith("act") ? { result: "success", output: "B" } : undefined))) === 1)
    const grantsBefore = w.grants()
    const v2 = await w.exec(w.task(2, new AbortController().signal))
    expect(v2.result).toBe("success")
    expect((v2.output as { result?: unknown }).result).toBe("B")
    expect(await w.agentJobs()).toHaveLength(2)
    expect(await w.serve(() => undefined)).toBe(0)
    expect(w.grants()).toBe(grantsBefore)
  })

  it("C3-5: a node that failed is the same failure on the next run attempt, with no new node", async () => {
    const w = await world("rvrun0035")
    const p1 = w.exec(w.task(1, new AbortController().signal))
    await until("prep enqueued", async () => (await w.agentJobs()).length >= 1)
    await until("prep served", async () => (await w.serve((p) => (p === "prep" ? { result: "success", output: "A" } : undefined))) === 1)
    await until("act enqueued", async () => (await w.agentJobs()).length >= 2)
    await until("act failed", async () => (await w.serve((p) => (p.startsWith("act") ? { result: "failure", output: { reason: "agent/x", message: "boom" } } : undefined))) >= 1)
    const v1 = await p1
    expect(v1.result).toBe("failure")
    const nodes = (await w.agentJobs()).length
    const v2 = await w.exec(w.task(2, new AbortController().signal))
    expect(v2.result).toBe("failure")
    expect(await w.agentJobs()).toHaveLength(nodes)
    expect(await w.serve(() => undefined)).toBe(0)
  })
})
