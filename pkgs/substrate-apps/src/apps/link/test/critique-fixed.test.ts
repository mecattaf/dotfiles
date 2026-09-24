// The nine defects the 2026-09-23 critique reproduced (LINK-DESIGN.md "Critique applied", section B), each INVERTED
// into the fixed behaviour now that its build item is in (commit history: the characterization versions are in
// 6342476 and b900624). Plus the new cases the build list names for B1, B6, B9 to B13, B15, B17 and B18.
// Same doubles as link.test.ts; the floor double implements section H's amended rules (B16).
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { AxError } from "../src/ax.ts"
import type { AgentJob, AxTask } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import type { FloorOptions } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { isFleetInternalUrl, runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"

const SEC = 20
const UNAVAILABLE = 14
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1` // round 4: FIELD-MAP 5a journal key (jobs.ts refuses a grant without it)
const job = (n: string, spec: Partial<AgentJob["spec"]> = {}): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: {
    name: `wf-test-${n}`,
    labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe" }
  },
  spec: {
    "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" },
    ...spec
  }
})
const world = (o: Partial<FloorConfig> = {}) => ({
  floor: new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" }, ...o }),
  ax: new FakeAx()
})
type World = ReturnType<typeof world>
const foreign = (name: string): AxTask => ({ apiVersion: "ax.io/v1alpha1", kind: "Task", metadata: { name, atespace: "fleet" }, spec: { image: "someone-else", command: ["true"], env: [] } })

interface Extra { fetch?: typeof globalThis.fetch; timeoutsMs?: FloorOptions["timeoutsMs"]; onEndpoint?: (u: string) => void }
function start(w: World, dir: string, over: Partial<LinkConfig> = {}, x: Extra = {}) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3, ...over
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: `s:${dir}`, fetch: x.fetch ?? w.floor.fetch, ...(x.timeoutsMs ? { timeoutsMs: x.timeoutsMs } : {}) })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ ev, ...f }), stop, floorUrl: "http://floor.test", ...(x.onEndpoint ? { onEndpoint: x.onEndpoint } : {}) })
  })))
  return {
    logs,
    has: (ev: string, leaseId?: string) => logs.some((l) => l.ev === ev && (leaseId === undefined || l.leaseId === leaseId)),
    verdict: (reason: string) => logs.some((l) => l.ev === "verdict" && l.reason === reason),
    crash: () => Effect.runPromise(Fiber.interrupt(fiber)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)]) }
  }
}
const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const J = (w: World, n = "1") => w.floor.jobs.get(`wf-test-${n}`)!
const liveOwn = (w: World) => [...w.ax.tasks.keys()].filter((k) => k.startsWith("wf-test-") && w.ax.live(k) && !["Completed", "Failed"].includes(w.ax.tasks.get(k)!.phase)).length

describe("critique 2026-09-23: the defects, fixed", () => {
  let dir: string
  let worlds: Array<World> = []
  const W = (o: Partial<FloorConfig> = {}) => { const w = world(o); worlds.push(w); return w }
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "conwip-link-critique-")) })
  afterEach(() => { for (const w of worlds) w.floor.close(); worlds = []; rmSync(dir, { recursive: true, force: true }) })

  it("C1 (B1) a live Task off ListTasks' first 50-row page is neither lost nor rerun", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    for (let i = 0; i < 50; i++) w.ax.put(foreign(`foreign-${i}`), "Completed") // newer than ours: ours is on page 2
    const calls = w.ax.listCalls
    await until("ten resyncs", () => w.ax.listCalls >= calls + 10)
    expect([l.verdict("infra/task-lost"), l.has("task-absent"), w.ax.tasks.has("wf-test-1-a2"), w.ax.deletes]).toEqual([false, false, false, []])
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    await l.drain()
  })

  it("C1b (B1) 120 Tasks: occupancy counts a live foreign Task on page 3, and a truly gone Task needs two NotFound resyncs", async () => {
    const w = W()
    for (let i = 0; i < 2; i++) w.ax.put(foreign(`busy-${i}`), "Running") // oldest: on the last page
    for (let i = 0; i < 118; i++) w.ax.put(foreign(`done-${i}`), "Completed")
    w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("a Lease was sent", () => w.floor.calls.some((c) => c.rpc === "Lease"))
    await sleep(10 * SEC)
    expect(w.floor.calls.filter((c) => c.rpc === "Lease").every((c) => c.capacity === 0)).toBe(true) // 2 busy of 2
    w.ax.tasks.delete("busy-0"); w.ax.tasks.delete("busy-1")
    await until("created once the sandboxes free", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.tasks.delete("wf-test-1-a1") // the store forgets it (F19)
    await until("task-lost after two NotFound resyncs", () => l.verdict("infra/task-lost"))
    const absent = l.logs.filter((x) => x.ev === "task-absent" && x.leaseId === "wf-test-1-a1")
    expect(absent.length).toBe(1)
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    await l.drain()
  })

  it("C2 (B2) a superseded attempt that will not delete blocks attempt n+1: retryable pre-start/ax-unavailable, never two at once", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.ax.holdPending.add("wf-test-1-a1")
    const del = w.ax.deleteTask
    w.ax.deleteTask = (name) => name === "wf-test-1-a1" ? Effect.fail(new AxError(UNAVAILABLE, "unavailable")) : del(name)
    const l = start(w, dir, { pendingTimeoutMs: 200 })
    // Critique pass 2026-09-24 (red team double-run-r3-1b): a1's pending-timeout verdict now waits for its delete to
    // land, so the floor never makes attempt 2 while a1 may still start. Never two at once still holds, one step earlier.
    await until("a1's verdict deferred", () => l.has("pre-start-deferred", "wf-test-1-a1"), 8000)
    await sleep(1000)
    expect(J(w).attempt).toBe(1)
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false)
    expect([...w.ax.updates.keys()]).toEqual(["wf-test-1-a1"]) // only ever one attempt in ax
    await l.drain()
  })

  it("C3 (B3) a cancel that lands while UpdateTask is retrying stops the create; nothing runs on", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let refusals = 2
    const create = w.ax.createTask
    w.ax.createTask = (t) => refusals-- > 0 ? Effect.fail(new AxError(UNAVAILABLE, "unavailable")) : create(t)
    const l = start(w, dir, { deleteAfterMs: 60_000, createAttempts: 5 })
    await until("leased", () => l.has("leased", "wf-test-1-a1"))
    w.floor.cancel("wf-test-1", "tom")
    await until("floor done", () => J(w).state === "done")
    expect(J(w).result).toBe("cancelled")
    await sleep(600)
    expect([w.ax.live("wf-test-1-a1"), l.has("abandoned-before-create", "wf-test-1-a1")]).toEqual([false, true])
    await l.drain()
  })

  it("C3b (B3) a cancel that lands while UpdateTask is in flight deletes the Task as soon as it returns, then reports cancelled", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let gate!: () => void
    const create = w.ax.createTask
    w.ax.createTask = (t) => create(t).pipe(Effect.andThen(Effect.callback<void>((resume) => { gate = () => resume(Effect.void) })))
    const l = start(w, dir, { deleteAfterMs: 60_000 })
    await until("create in flight", () => w.ax.tasks.has("wf-test-1-a1") && gate !== undefined)
    w.floor.cancel("wf-test-1", "tom")
    await until("cancel seen", () => l.has("cancel", "wf-test-1-a1"))
    gate()
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, w.ax.live("wf-test-1-a1")]).toEqual(["cancelled", false])
    await l.drain()
  })

  it("C4 (B4) one transient GetTaskResult error is retried at the next resync: the success lands, nothing reruns", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let blips = 1
    const res = w.ax.getTaskResult
    w.ax.getTaskResult = (n) => n === "wf-test-1-a1" && blips-- > 0 ? Effect.fail(new AxError(UNAVAILABLE, "unavailable")) : res(n)
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).output, J(w).attempt, l.has("result-read-retry", "wf-test-1-a1")]).toEqual(["success", { answer: 42 }, 1, true])
    expect(J(w).history.some((h) => h.startsWith("requeue"))).toBe(false)
    await l.drain()
  })

  it("C4b (B4) a result whose sha256 never matches is infra/result-unreadable after the bounded tries", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const res = w.ax.getTaskResult
    w.ax.getTaskResult = (n) => res(n).pipe(Effect.map((r) => r && r !== "unimplemented" && n === "wf-test-1-a1" ? { ...r, digestOk: false } : r))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect(J(w).history).toContain("requeue:infra/result-unreadable")
    expect(l.logs.filter((x) => x.ev === "result-read-retry" && x.leaseId === "wf-test-1-a1").length).toBe(2)
    await l.drain()
  })

  it("C5 (B5) Failed with ResourceExhausted is the retryable pre-start/resource-exhausted", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const t = w.ax.tasks.get("wf-test-1-a1")!
    t.phase = "Failed"
    t.conditions = [{ type: "Ready", status: "False", reason: "ActorCreateFailed", message: "ResourceExhausted: no free workers available" }]
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect(J(w).history).toContain("requeue:pre-start/resource-exhausted")
    await l.drain()
  })

  it("C6 (B6) configured p1 on a server without P1 leases nothing and says p1-missing", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.ax.p1 = false
    const l = start(w, dir, { completion: "p1" })
    await until("probe", () => l.has("p1-missing"))
    await sleep(10 * SEC)
    expect(w.floor.calls.filter((c) => c.rpc === "Lease").every((c) => c.capacity === 0)).toBe(true)
    expect([w.ax.updates.size, J(w).state]).toEqual([0, "queued"])
    await l.drain()
  })

  it("C6b (B6) auto never selects guest, and re-probes when ax comes back: P1 appears, work starts", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.ax.p1 = false
    const l = start(w, dir, { completion: "auto" })
    await until("probe", () => l.has("p1-missing"))
    await sleep(5 * SEC)
    expect(w.ax.updates.size).toBe(0)
    w.ax.up = false
    await until("ax down", () => l.has("ax-down"))
    w.ax.p1 = true; w.ax.up = true // the operator rolled out P1
    await until("created in p1 mode", () => w.ax.tasks.has("wf-test-1-a1"))
    const env = Object.fromEntries(w.ax.tasks.get("wf-test-1-a1")!.task.spec.env.map((e) => [e.name, e.value]))
    expect(env.AX_CONWIP_COMPLETE_URL).toBeUndefined()
    await l.drain()
  })

  it("C6c (B6, A5) guest mode with a workers.dev Complete URL leases nothing", async () => {
    expect([isFleetInternalUrl("https://conwip-floor.x.workers.dev/guest"), isFleetInternalUrl("http://link.fleet.internal/guest"), isFleetInternalUrl("http://10.201.0.9:8732/g"), isFleetInternalUrl("https://example.com/")]).toEqual([false, true, true, false])
    const w = W(); w.floor.enqueue(job("1")); w.ax.p1 = false
    const l = start(w, dir, { completion: "guest", shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "https://conwip-floor.x.workers.dev/guest" } })
    await until("refused", () => l.has("guest-url-invalid"))
    await sleep(5 * SEC)
    expect(w.floor.calls.filter((c) => c.rpc === "Lease").every((c) => c.capacity === 0)).toBe(true)
    await l.drain()
  })

  it("C7 (B7) an empty runs-on, or two seats, is refused by the link (and by the floor's enqueue)", async () => {
    const w = W({ cap: 3 })
    expect(w.floor.enqueue(job("1", { "runs-on": [] }))).toBe(false)
    w.floor.enqueueUnchecked(job("1", { "runs-on": [] }))
    w.floor.o.tokens["tok-nas"] = { holder: "nas-link-1", labels: ["seat:halogen", "seat:cc", "runtime:gvisor"] }
    w.floor.enqueueUnchecked(job("2", { "runs-on": ["seat:halogen", "seat:cc"] }))
    const l = start(w, dir, { maxInFlight: 3, servedLabels: ["seat:halogen", "seat:cc", "runtime:gvisor"] })
    await until("both done", () => J(w).state === "done" && J(w, "2").state === "done")
    expect([(J(w).output as { reason: string }).reason, (J(w, "2").output as { reason: string }).reason]).toEqual(["pre-start/runs-on-invalid", "pre-start/runs-on-invalid"])
    expect(w.ax.updates.size).toBe(0)
    await l.drain()
  })

  it("C8 (B8) a Lease reply lost on all three tries is replayed by the journaled requestKey: attempt 1 runs", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let lose = 3
    const lossy: typeof globalThis.fetch = async (input, init) => {
      const res = await w.floor.fetch(input, init)
      if (lose > 0 && (await res.clone().text()).includes("\"leaseId\":\"wf-test-1-a1\"")) { lose--; throw new TypeError("fetch failed: reply lost") }
      return res
    }
    const l = start(w, dir, {}, { fetch: lossy })
    await until("attempt 1 created", () => w.ax.tasks.has("wf-test-1-a1"), 8000)
    expect(J(w).history.some((h) => h.startsWith("requeue"))).toBe(false)
    expect(w.ax.tasks.has("wf-test-1-a2")).toBe(false)
    await l.drain()
  })

  it("C9 (B9) a hung Heartbeat times out; the next one renews; the running attempt survives", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let hang = false
    const hanging: typeof globalThis.fetch = async (input, init) => {
      const req = new Request(input as string | URL | Request, init)
      if (hang && (await req.clone().text()).includes("\"Heartbeat\"")) { hang = false; return new Promise<Response>(() => {}) }
      return w.floor.fetch(req)
    }
    const l = start(w, dir, {}, { fetch: hanging, timeoutsMs: { lease: 150, heartbeat: 150, complete: 300 } })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    hang = true
    await until("the hang timed out", () => l.logs.some((x) => x.ev === "heartbeat-error"))
    await sleep(25 * SEC) // past lease plus grace
    expect([J(w).history.includes("requeue:grace"), w.ax.deletes.includes("wf-test-1-a1"), J(w).attempt]).toEqual([false, false, 1])
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 1])
    await l.drain()
  })

  it("C9b (B9) concurrent 401 and 503 are each charged to their own call", async () => {
    const w = W()
    const f: typeof globalThis.fetch = async (input, init) => {
      const body = await new Request(input as string | URL | Request, init).text()
      if (body.includes("\"Lease\"")) { await sleep(30); return new Response("busy", { status: 503 }) }
      return new Response("no", { status: 401 })
    }
    const out = await Effect.runPromise(Effect.scoped(Effect.gen(function*() {
      const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: "s", fetch: f })
      return yield* Effect.all([
        floor.lease({ holderIdentity: "nas-link-1", capacity: 1, requestKey: "k" }).pipe(Effect.flip),
        floor.heartbeat({ holderIdentity: "nas-link-1", leaseIds: [] }).pipe(Effect.flip)
      ], { concurrency: "unbounded" })
    })))
    expect(out.map((e) => e.kind)).toEqual(["transient", "auth"])
    void w
  })

  it("B10 a missing Gateway, or one that allows everything, leases nothing; a restricted one does", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const halogen = w.ax.gateways.get("halogen")!
    w.ax.gateways.delete("halogen")
    const l = start(w, dir)
    await until("gateway-missing", () => l.has("gateway-missing"))
    w.ax.gateways.set("halogen", { hasAllowlist: true, hosts: [{ host: "*", port: 443 }] })
    await sleep(5 * SEC)
    expect([w.ax.updates.size, w.floor.calls.filter((c) => c.rpc === "Lease").every((c) => c.capacity === 0)]).toEqual([0, true])
    w.ax.gateways.set("halogen", halogen)
    await until("created", () => w.ax.tasks.has("wf-test-1-a1"))
    expect(l.has("gateway-ok")).toBe(true)
    await l.drain()
  })

  it("B11 a floor that over-grants never makes the link over-create: extra grants wait, journaled and heartbeated", async () => {
    const w = W({ cap: 10, overGrant: 2 })
    for (const n of ["1", "2", "3"]) w.floor.enqueue(job(n))
    const l = start(w, dir, { maxInFlight: 1 })
    let peak = 0
    const sample = setInterval(() => { peak = Math.max(peak, liveOwn(w)) }, 2)
    await until("three grants", () => ["1", "2", "3"].every((n) => J(w, n).state === "leased"))
    await until("waiting", () => l.has("waiting-for-slot"))
    for (const n of ["1", "2", "3"]) {
      await until(`job ${n} running`, () => w.ax.tasks.get(`wf-test-${n}-a1`)?.phase === "Running")
      w.ax.finish(`wf-test-${n}-a1`, 0, { n })
      await until(`job ${n} done`, () => J(w, n).state === "done")
    }
    clearInterval(sample)
    expect(peak).toBe(1)
    expect(["1", "2", "3"].map((n) => [J(w, n).result, J(w, n).attempt])).toEqual([["success", 1], ["success", 1], ["success", 1]])
    await l.drain()
  })

  it("B12 a Task that reads back with another spec is deleted and refused", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const create = w.ax.createTask
    w.ax.createTask = (t) => create({ ...t, spec: { ...t.spec, env: t.spec.env.slice(0, 3) } }) // the store dropped env rows
    const l = start(w, dir)
    await until("floor done", () => J(w).state === "done")
    expect([(J(w).output as { reason: string }).reason, w.ax.live("wf-test-1-a1")]).toEqual(["pre-start/readback-mismatch", false])
    await l.drain()
  })

  it("B13 a journaled grant the floor released while the link was dead is never created on restart", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.ax.blockCreate = true
    const l1 = start(w, dir)
    await until("grant journaled", () => l1.has("leased", "wf-test-1-a1"))
    await l1.crash()
    w.ax.blockCreate = false
    await until("requeued after the grace", () => J(w).history.includes("requeue:grace"), 3000)
    const l2 = start(w, dir)
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect([w.ax.updates.has("wf-test-1-a1"), l2.has("resume", "wf-test-1-a1")]).toEqual([false, false])
    w.ax.tick(); w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 2])
    await l2.drain()
  })

  it("B15 floor down past lease plus grace: the queued success goes out before the next Lease and is accepted (rule 4b)", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    w.ax.finish("wf-test-1-a1", 0, { v: 1 })
    await until("outbox keeps", () => l.has("outbox-keep", "wf-test-1-a1"))
    await until("the alarm requeued it while the floor was unreachable", () => J(w).history.includes("requeue:grace"), 3000)
    w.floor.down = false
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { v: 1 }, 1])
    expect(J(w).history).toContain("withdrawn:a2")
    expect(w.ax.tasks.has("wf-test-1-a2")).toBe(false)
    await l.drain()
  })

  it("B17 a verdict that frees a slot leases at once, not at the next poll", async () => {
    const w = W({ pollSeconds: 100 }) // 2 s between polls here
    w.floor.enqueue(job("1")); w.floor.enqueue(job("2"))
    const l = start(w, dir, { maxInFlight: 1 })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running", 4000)
    await sleep(200)
    const t0 = Date.now()
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("job 2 created", () => w.ax.tasks.has("wf-test-2-a1"), 1500)
    expect(Date.now() - t0).toBeLessThan(1000)
    await l.drain()
  })

  it("B18 a Lease endpoint is followed only when it is in the declared list", async () => {
    const w = W()
    let ep = "https://evil.example/floor"
    const f: typeof globalThis.fetch = async (input, init) => {
      const res = await w.floor.fetch(input, init)
      const text = await res.text()
      const h = new Headers(res.headers); h.delete("content-length")
      return new Response(text.replace("\"nextPollSeconds\":", `"endpoint":"${ep}","nextPollSeconds":`), { status: res.status, headers: h })
    }
    const seen: Array<string> = []
    const l = start(w, dir, { floorUrls: ["https://conwip-floor-2.example/"] }, { fetch: f, onEndpoint: (u) => seen.push(u) })
    await until("ignored", () => l.has("endpoint-ignored"))
    ep = "https://conwip-floor-2.example/"
    await until("accepted", () => l.has("endpoint-accepted"))
    expect(seen).toEqual(["https://conwip-floor-2.example/"])
    await l.drain()
  })
})
