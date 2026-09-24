// Final pass (2026-09-23): regression tests for the two link-side findings of wave/VERIFY-LINK.md that were still open at
// 3b036da, both reproduced there by the chaos harness against the prototype floor under wrangler dev --local
// (link/final-verify/chaos-fresh-3b036da: f1 ran as a1 and a2, OVERLAP 8 s).
//   FP-1 (R3-1): a heartbeat sleep begun at the 30 s default while nothing was held outlived a short lease granted
//                during it; the floor released the orphan and the job ran twice.
//   FP-2 (V1):   the link fenced only what Grant.supersedes named; a floor that omits it got attempt n+1 created beside
//                a still Running attempt n.
import { expect, it } from "vitest"
import { bodyOf, job, sleep, start, until, world } from "./review-r4-harness.ts"

it("FP-1 a short lease granted during the first long heartbeat sleep is renewed in time", async () => {
  // Lease 6 s and grace 2 s at SEC = 20 ms; the link starts with the production default heartbeat (30 s = 600 ms).
  const w = world({ leaseSeconds: 6, graceSeconds: 2, heartbeatSeconds: 2 })
  // Every Lease reply is held 30 ms, as a real HTTPS round trip is (the chaos run: wrangler dev --local), so the heartbeat
  // fiber sizes its first sleep before the first reply has set the server's interval. With an in-process reply the fiber
  // happened to start after it, which hid the defect from every earlier test.
  const slowLease: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (body.includes('"Lease"')) await sleep(30)
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l = start(w, undefined, { initialHeartbeatSeconds: 30 }, slowLease)
  await until("first Lease answered", () => w.floor.jobs.size === 0 && l.logs.some((x) => x.ev === "ax-up"), 2000).catch(() => {})
  await sleep(60) // the first heartbeat sleep has begun, sized from the 30 s default
  w.floor.enqueue(job("1"))
  const J = () => w.floor.jobs.get("wf-test-1")!
  await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1") !== undefined, 3000)
  await sleep(1200) // twice the default heartbeat: without the fix the lease expires and the grace runs out first
  const out = { history: J().history, attempt: J().attempt, a2: w.ax.updates.get("wf-test-1-a2") ?? 0 }
  console.log(JSON.stringify(out))
  await l.drain(); w.floor.close()
  expect(out.attempt).toBe(1)
  expect(out.a2).toBe(0)
  expect(out.history).not.toContain("requeue:omitted")
  expect(out.history.filter((h: string) => h.startsWith("requeue")).length).toBe(0)
})

it("FP-2 attempt n+1 is never created beside a live attempt n, even when the floor omits supersedes", async () => {
  // red team double-run-r1-1: a pin (rule 7b) long enough that the link's own lease-expired fence does not delete a1
  // before a2's dispatch; this case is about the dispatch fence set, which must still catch a1
  const w = world({ leaseSeconds: 6, graceSeconds: 2, heartbeatSeconds: 2, pinSeconds: 60 })
  let failHeartbeat = false
  const strip = (s: string) => s.replace(/,"supersedes":\[[^\]]*\]/g, "").replace(/"supersedes":\[[^\]]*\],/g, "")
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (failHeartbeat && body.includes('"Heartbeat"')) throw new TypeError("fetch failed")
    const res = await w.floor.fetch(input as any, { ...init, body })
    const text = await res.text()
    return new Response(strip(text), { status: res.status, headers: res.headers })
  }
  let a1LiveAtA2Create: boolean | undefined
  const create = w.ax.createTask
  ;(w.ax as any).createTask = (task: any) => {
    if (task.metadata.name === "wf-test-1-a2" && a1LiveAtA2Create === undefined) a1LiveAtA2Create = w.ax.live("wf-test-1-a1")
    return create(task)
  }
  w.floor.enqueue(job("1"))
  const l = start(w, undefined, {}, fetch)
  const J = () => w.floor.jobs.get("wf-test-1")!
  await until("a1 running", () => w.ax.live("wf-test-1-a1") && l.has("created", "wf-test-1-a1"), 3000)
  failHeartbeat = true // a1's lease expires and the grace runs out; the floor requeues attempt 2 and grants it on Lease
  await until("floor requeued attempt 2", () => J().attempt === 2, 4000)
  await until("a2 leased", () => l.has("leased", "wf-test-1-a2"), 4000)
  failHeartbeat = false
  await until("a2 created", () => (w.ax.updates.get("wf-test-1-a2") ?? 0) > 0, 4000)
  const out = { a1LiveAtA2Create, extended: l.has("fence-set-extended", "wf-test-1-a2"), events: (w.ax as any).events?.filter((e: string) => e.includes("wf-test-1")) }
  console.log(JSON.stringify(out))
  await l.drain(); w.floor.close()
  expect(out.extended).toBe(true)
  expect(out.a1LiveAtA2Create).toBe(false)
  expect(w.ax.upsertsOnExisting).toBe(0)
})
