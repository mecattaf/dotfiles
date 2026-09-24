// Critique pass 2026-09-24, red team durability-r1-1 (and double-run-r2-4), promoted from the audit probe and inverted. A puller killed while a no-barrier pipeline's second stage is
// in flight: does attempt 2 of the run resume, as puller.ts promises ("finished agent() calls are cache hits and are
// never dispatched again")? The real floor (Worker entry and Floor object over node:sqlite), the real FloorBackend.
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { SubstrateClient } from "@substrate/api"
import { localFloor } from "@substrate/floor/local.ts"
import { connectFloor } from "../src/connect.ts"
import { FloorBackend, floorExecutor } from "../src/execute.ts"

const T = { floor: "rt-floor", nas: "rt-nas", interp: "rt-interp" }
const URL_ = "http://floor.test"
const cleanups: Array<() => unknown> = []
afterEach(async () => { for (const c of cleanups.splice(0).reverse()) await c() })
const until = async (what: string, f: () => Promise<boolean> | boolean, ms = 15_000) => {
  const end = Date.now() + ms
  while (!(await f())) { if (Date.now() > end) throw new Error(`timed out waiting for ${what}`); await new Promise((r) => setTimeout(r, 15)) }
}

const PIPELINE = `export const meta = { name: "pipe", description: "two independent two-stage chains, no barrier" }
const second = (tag) => (x) => agent("second " + tag + " " + x, { label: "s2-" + tag })
const pa = agent("first A", { label: "a" }).then(second("A"))
const pb = agent("first B", { label: "b" }).then(second("B"))
return await Promise.all([pa, pb])
`

describe("durability-r1: kill during a pipeline, then resume (puller attempt 2)", () => {
  it("durability-r1-1: stage-2 nodes resume under the same name and body, and the run ends success", async () => {
    const f = localFloor({ floorToken: T.floor, links: [{ token: T.nas, holder: "nas", labels: ["seat:t", "runtime:*"] }, { token: T.interp, holder: "coordinator", labels: ["runtime:interpreter"] }],
      vars: { FLOOR_UNGATED_SEATS: "*", FLOOR_INTERPRETER_SEAT: "interp", FLOOR_HEARTBEAT_SECONDS: "1", FLOOR_LEASE_SECONDS: "30", FLOOR_POLL_SECONDS: "1" } })
    cleanups.push(() => f.close())
    const client = new SubstrateClient({ url: URL_, token: T.floor, fetch: f.fetch })
    const nas = await connectFloor({ url: URL_, token: T.nas, sessionId: "nas-s", fetch: f.fetch })
    cleanups.push(() => nas.close())
    const id = "rtpipe0001"
    await client.submit({ id, script: PIPELINE })
    // G-BK5 (integrate 2026-09-24): node enqueues name the run's live interpreter lease, so the run is really leased
    const interp = await connectFloor({ url: URL_, token: T.interp, sessionId: "interp-s", fetch: f.fetch })
    cleanups.push(() => interp.close())
    const runGrant = (await interp.port.lease({ holderIdentity: "coordinator", capacity: 1, requestKey: crypto.randomUUID() })).grants.find((g) => g.leaseId === `run-${id}-a1`)
    expect(runGrant).toBeDefined()
    const dir = mkdtempSync(join(tmpdir(), "rt-pipe-"))
    const scriptPath = join(dir, "script.js")
    writeFileSync(scriptPath, PIPELINE)
    const backends: Array<FloorBackend> = []
    const exec = floorExecutor({ client, defaultRunsOn: ["seat:t"], defaultModel: "test-model", pollMs: 10, onBackend: (b) => backends.push(b) })
    // Both attempts run under the one live interpreter lease: attempt 2 is the puller re-adopting it after the kill.
    const task = (_attempt: number, signal: AbortSignal) => ({ runId: id, leaseId: runGrant!.leaseId, attempt: runGrant!.attempt, job: {} as never, workflowName: "pipe", args: undefined, dir, scriptPath, script: PIPELINE, signal })
    const promptOf = async (name: string) => ((await client.job(name)).job as { spec: { with: { prompt?: string } } }).spec.with.prompt ?? ""
    const names = async () => (await client.runJobs(id)).map((j) => j.name).filter((n) => n.startsWith("n"))
    /** The NAS link's part by hand: lease what is queued (the grants are kept), answer a prompt when told. */
    const granted = new Map<string, { leaseId: string; attempt: number }>()
    const serve = async () => {
      const r = await nas.port.lease({ holderIdentity: "nas", capacity: 10, requestKey: crypto.randomUUID() })
      for (const g of r.grants) granted.set(g.job.spec.with.prompt ?? "", { leaseId: g.leaseId, attempt: g.attempt })
    }
    const answer = async (prompt: string, out: string) => {
      const g = granted.get(prompt)
      if (!g) throw new Error(`no grant for ${prompt}`)
      await nas.port.complete({ leaseId: g.leaseId, attempt: g.attempt, result: "success", output: out, usage: { prompt_tokens: 1, completion_tokens: 1, tool_calls: 0 } })
    }

    // Attempt 1. Stage 1 is enqueued as n1 (first A) and n2 (first B); B finishes first, so "second B" is invoked
    // first and becomes n3; A finishes, "second A" becomes n4.
    const ac1 = new AbortController()
    const run1 = exec(task(1, ac1.signal))
    await until("stage 1 enqueued", async () => (await names()).length === 2)
    await serve()
    await answer("first B", "B")
    await until("second B enqueued", async () => (await names()).length === 3)
    await answer("first A", "A")
    await until("second A enqueued", async () => (await names()).length === 4)
    await serve() // the NAS link takes both stage-2 nodes: they are running when the puller dies
    // The kill, with both stage-2 nodes in flight (queued on the floor for the NAS link, which may already run them).
    ac1.abort()
    expect((await run1).result).toBe("cancelled")
    const journal1 = readFileSync(join(dir, "journal.jsonl"), "utf8")
    expect(journal1.split("\n").filter((l) => l.includes('"result"')).length).toBe(2) // stage 1 is finished work

    // Attempt 2 (the puller re-adopts the lease, or the floor requeues the run): the same directory, the journal
    // found, cacheIdentity content. Stage 1 is a cache hit, resolved in invocation order, so "second A" is now
    // invoked first and takes index 3: the name n3 carries a different prompt than the job the floor holds.
    const ac2 = new AbortController()
    const p2 = exec(task(2, ac2.signal))
    // audit: if the stage-2 names are stable, attempt 2 re-enqueues them as enqueued:false and waits on the NAS grants
    await new Promise((r) => setTimeout(r, 300))
    await answer("second A A", "AA").catch(() => undefined)
    await answer("second B B", "BB").catch(() => undefined)
    const run2 = await Promise.race([p2, new Promise<never>((_, no) => setTimeout(() => no(new Error("attempt 2 hung")), 8000))])
    // Fixed: the name and the body of every node are independent of invocation order, so attempt 2's re-enqueue is
    // enqueued:false and it waits on the NAS link's answers.
    expect((run2.output as { error: string | null }).error ?? null).toBeNull()
    expect(run2.result).toBe("success")
    expect(JSON.stringify(run2.output)).toContain("AA")
    expect(JSON.stringify(run2.output)).toContain("BB")
    for (const n of await names()) {
      const j = (await client.job(n)).job as { metadata: { annotations: Record<string, string> } }
      expect(j.metadata.annotations["ultracode.mecattaf.dev/call-index"]).toBeUndefined()
    }
  })
})
