// Review round 1 (2026-09-23): the ten findings, each as a regression test that failed before its fix. The scratch
// repros are in /home/tom/today/evals-2026-09-23/link/scratch-r1-{0,1,2}; the log is link/REVIEW-LOG.md.
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
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"
import { ConfigInvalid, readLinkEnv } from "../src/config.ts"
import type { FloorApi } from "../src/floor.ts"
import { axTaskFromGrant } from "../src/jobs.ts"

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


const bodyOf = async (input: unknown, init?: RequestInit) => {
  const b = init?.body
  if (typeof b === "string") return b
  if (b instanceof Uint8Array) return new TextDecoder().decode(b)
  if (b) return await new Response(b as ConstructorParameters<typeof Response>[0]).text()
  return (input instanceof Request) ? await input.clone().text() : ""
}
const isComplete = async (input: unknown, init?: RequestInit) => (await bodyOf(input, init)).includes('"Complete"')
const stats = { seq: 1, cap: 2, wip: 0, queued: 0, done: 0 }
const grantOf = (n: string, extra: Record<string, unknown> = {}) => ({
  leaseId: `wf-test-${n}-a1`, attempt: 1, job: job(n),
  lease: { holderIdentity: "nas-link-1", leaseDurationSeconds: 30, acquireTime: Date.now(), renewTime: Date.now(), leaseTransitions: 0 }, ...extra
}) as any
/** A floor that hands out `grants` once and renews everything: for link-side properties the double cannot stage. */
const stubFloor = (grants: Array<any>) => {
  let sent = false
  const completes: Array<any> = []
  const api: FloorApi = {
    lease: (p) => Effect.sync(() => { const g = !sent && p.capacity > 0 ? grants : []; if (g.length) sent = true; return { grants: g, stats, nextPollSeconds: 1, heartbeatSeconds: 2 } }),
    heartbeat: (p) => Effect.succeed({ renewed: [...p.leaseIds], lost: [], cancelRequested: [], stats }),
    complete: (p) => Effect.sync(() => { completes.push(p); return { duplicate: false, stats } })
  }
  return { api, completes }
}
const cfgOf = (over: Partial<LinkConfig> = {}): LinkConfig => ({
  holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
  shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
  completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 60_000, deleteAfterMs: 60_000, deadlineBackstopMs: 300,
  createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3, ...over
})
const runStub = async (cfg: LinkConfig, ax: FakeAx, floor: FloorApi, ms: number) => {
  const d = mkdtempSync(join(tmpdir(), "conwip-link-r1s-"))
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const f = Effect.runFork(runLink(cfg, { ax, floor, journal: Journal.open(d), log: (ev, x) => logs.push({ ev, ...x }), stop }))
  await sleep(ms)
  Effect.runSync(Deferred.succeed(stop, undefined)); await Effect.runPromise(Fiber.await(f)); rmSync(d, { recursive: true, force: true })
  return logs
}

describe("review round 1: fixed", () => {
  let dir: string
  let worlds: Array<World> = []
  const W = (o: Partial<FloorConfig> = {}) => { const w = world(o); worlds.push(w); return w }
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "conwip-link-r1-")) })
  afterEach(() => { for (const w of worlds) w.floor.close(); worlds = []; rmSync(dir, { recursive: true, force: true }) })

  // ------------------------------------------------------------------ findings 1 and 2: one verdict, one application
  it("R1-1 no fault: every verdict costs exactly one Complete (single-flight outbox)", async () => {
    const w = W({ cap: 8 })
    for (let i = 1; i <= 8; i++) w.floor.enqueue(job(String(i)))
    const l = start(w, dir, { maxInFlight: 8, resyncMs: 5 })
    await until("all running", () => [1, 2, 3, 4, 5, 6, 7, 8].every((i) => w.ax.tasks.get(`wf-test-${i}-a1`)?.phase === "Running"))
    for (let i = 1; i <= 8; i++) w.ax.finish(`wf-test-${i}-a1`, 0, { i })
    await until("all done", () => [1, 2, 3, 4, 5, 6, 7, 8].every((i) => J(w, String(i)).state === "done"))
    await sleep(100)
    const per = new Map<string, number>()
    for (const c of w.floor.calls.filter((c) => c.rpc === "Complete")) per.set(c.leaseIds![0]!, (per.get(c.leaseIds![0]!) ?? 0) + 1)
    expect([...per.values()]).toEqual([1, 1, 1, 1, 1, 1, 1, 1])
    expect(l.logs.filter((x) => x.ev === "complete").length).toBe(8)
    await l.drain()
  })

  it("R1-1 (D5) one retryable failure with a budget of two releases leases attempt 2", async () => {
    const w = W({ infraAttempts: 2 }); w.floor.enqueue(job("1")); w.ax.holdPending.add("wf-test-1-a1")
    const l = start(w, dir, { pendingTimeoutMs: 150 })
    await until("attempt 2 leased", () => J(w).state === "leased" && J(w).attempt === 2, 4000)
    expect(J(w).infraSpent).toBe(1)
    expect(J(w).history).not.toContain("withdrawn:a2")
    await l.drain()
  })

  it("R1-2 (D2) a Complete whose reply is lost after the floor committed is resent and answered duplicate, not applied twice", async () => {
    const w = W({ infraAttempts: 2 }); w.floor.enqueue(job("1")); w.ax.holdPending.add("wf-test-1-a1")
    let dropped = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const c = await isComplete(input, init)
      const res = await w.floor.fetch(input, init)
      if (c && dropped === 0) { dropped++; throw new TypeError("fetch failed: reply lost after the floor committed") }
      return res
    }
    const l = start(w, dir, { pendingTimeoutMs: 150 }, { fetch })
    await until("attempt 2 leased", () => J(w).state === "leased" && J(w).attempt === 2, 4000)
    await until("the resend is acknowledged", () => l.logs.some((x) => x.ev === "complete" && x.leaseId === "wf-test-1-a1"))
    expect(dropped).toBe(1)
    expect(J(w).infraSpent).toBe(1)
    expect(l.logs.find((x) => x.ev === "complete" && x.leaseId === "wf-test-1-a1")!.duplicate).toBe(true)
    await l.drain()
  })

  // ------------------------------------------------------------------ finding 3: the create window is write-ahead
  it("R1-3 (D1) crash after UpdateTask landed, before `created`, then a cancel: the Task is deleted and NotFound precedes `cancelled`", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.ax.hangAfterCreate = true
    const l1 = start(w, dir)
    await until("Task written to ax", () => w.ax.tasks.has("wf-test-1-a1"))
    await l1.crash()
    w.ax.hangAfterCreate = false
    w.floor.cancel("wf-test-1")
    const l2 = start(w, dir)
    await until("floor done", () => J(w).state === "done")
    expect(J(w).result).toBe("cancelled")
    expect(w.ax.deletes).toContain("wf-test-1-a1")
    expect(w.ax.tasks.has("wf-test-1-a1")).toBe(false) // NotFound before the verdict (reconcile reports on gone)
    const evs = l2.logs.filter((x) => x.leaseId === "wf-test-1-a1" || x.task === "wf-test-1-a1").map((x) => x.ev)
    expect(evs.indexOf("delete")).toBeLessThan(evs.indexOf("verdict"))
    await l2.drain()
    expect(Journal.open(dir).recs.has("wf-test-1-a1")).toBe(false) // compacted only once ax is clean
  })

  it("R1-3 (D1 lost variant) crash in the create window, the floor gives up on the job: `lost` deletes the maybe-created Task", async () => {
    const w = W({ infraAttempts: 1 }); w.floor.enqueue(job("1")); w.ax.hangAfterCreate = true
    const l1 = start(w, dir)
    await until("Task written to ax", () => w.ax.tasks.has("wf-test-1-a1"))
    await l1.crash()
    w.ax.hangAfterCreate = false
    await sleep(7 * SEC); w.floor.sweep(); await sleep(16 * SEC); w.floor.sweep()
    expect(J(w).state).toBe("done") // budget spent at the first release: no re-grant
    const l2 = start(w, dir)
    await until("lost", () => l2.has("lost", "wf-test-1-a1"))
    await until("Task gone", () => !w.ax.tasks.has("wf-test-1-a1"))
    expect(w.ax.deletes).toContain("wf-test-1-a1")
    await l2.drain()
  })

  // ------------------------------------------------------------------ findings 4 and 8: B15
  it("R1-8 (B15 deterministic) the first Complete after the floor returns is lost in transit: no Lease runs before it lands", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let failCompletes = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (failCompletes > 0 && await isComplete(input, init)) { failCompletes--; throw new TypeError("fetch failed") }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, { fetch })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    w.ax.finish("wf-test-1-a1", 0, { v: 1 })
    await until("outbox keeps", () => l.has("outbox-keep", "wf-test-1-a1"))
    await until("requeued", () => J(w).history.includes("requeue:grace"), 3000)
    failCompletes = 1
    const mark = w.floor.calls.length
    w.floor.down = false
    await until("floor done", () => J(w).state === "done", 4000)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { v: 1 }, 1])
    // round 3 (finding 12): the gate is asserted on the floor's side, not on the log line
    const after = w.floor.calls.slice(mark), landed = after.findIndex((c) => c.rpc === "Complete")
    expect(after.slice(0, landed).filter((c) => c.rpc === "Lease").map((c) => c.capacity).filter((c) => c !== 0)).toEqual([])
    expect(J(w).history).not.toContain("leased:a2")
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false)
    expect(l.has("complete-dropped", "wf-test-1-a1")).toBe(false)
    await l.drain()
  })

  it("R1-4 (D3) Complete answers 503 while Lease answers: the gate asks for nothing until the success lands", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let failComplete = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (failComplete && await isComplete(input, init)) return new Response("upstream timeout", { status: 503 })
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, { fetch })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
    failComplete = true
    const mark = w.floor.calls.length
    w.floor.down = false
    await sleep(400) // several polls while only Complete fails
    expect(l.has("lease-gated-by-outbox")).toBe(true)
    // round 3 (finding 12): every Lease while the success is undelivered asks for nothing, and nothing is leased
    const leases = w.floor.calls.slice(mark).filter((c) => c.rpc === "Lease")
    expect([leases.length > 0, leases.filter((c) => c.capacity !== 0).length, J(w).history.includes("leased:a2")]).toEqual([true, 0, false])
    expect(w.ax.tasks.has("wf-test-1-a2")).toBe(false)
    // a1 may be deleted as `lost` (its verdict is already journaled); it is never fenced as `superseded`
    expect(l.logs.some((x) => x.ev === "delete" && x.task === "wf-test-1-a1" && x.why === "superseded")).toBe(false)
    failComplete = false
    await until("floor done", () => J(w).state === "done", 4000)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    await l.drain()
  })

  it("R1-4 (D3 at dispatch) a grant that supersedes an undelivered success is withdrawn, never fenced or created", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let failComplete = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (failComplete && await isComplete(input, init)) return new Response("upstream timeout", { status: 503 })
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, { fetch, })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
    failComplete = true
    w.floor.o.overGrant = 1 // a floor that grants on a capacity-0 Lease: the link's own defence must hold
    w.floor.down = false
    await until("a2 granted", () => l.has("leased", "wf-test-1-a2"), 4000)
    w.floor.o.overGrant = 0
    await until("dispatch waits for the verdict", () => l.has("supersede-waits-for-verdict", "wf-test-1-a2"))
    failComplete = false
    await until("floor done", () => J(w).state === "done", 4000)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    expect(J(w).history).toContain("withdrawn:a2")
    await until("a2 withdrawn locally", () => l.has("withdrawn", "wf-test-1-a2"))
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false)
    // the finished Task was not fenced before its verdict (a `lost` delete is fine: the verdict is already journaled)
    expect(l.logs.some((x) => x.ev === "delete" && x.task === "wf-test-1-a1" && x.why === "superseded")).toBe(false)
    await l.drain()
  })

  // ------------------------------------------------------------------ finding 5: supersedes is scoped to own Tasks
  it("R1-5 supersedes naming a Task this link never created: no DeleteTask, the grant is refused", async () => {
    const ax = new FakeAx()
    ax.put(foreign("someone-elses-task"), "Running")
    const f = stubFloor([grantOf("1", { attempt: 2, leaseId: "wf-test-1-a2", supersedes: ["someone-elses-task"] })])
    const logs = await runStub(cfgOf(), ax, f.api, 600)
    expect(ax.deletes).toEqual([])
    expect(ax.live("someone-elses-task")).toBe(true)
    expect(ax.tasks.has("wf-test-1-a2")).toBe(false)
    expect(f.completes.map((c) => [c.leaseId, c.output?.reason])).toEqual([["wf-test-1-a2", "pre-start/supersedes-foreign"]])
    expect(logs.some((x) => x.ev === "supersedes-foreign")).toBe(true)
  })

  it("R1-5 an earlier attempt of the same job that carries another holder's mark is not deleted either", async () => {
    const ax = new FakeAx()
    const built = axTaskFromGrant(grantOf("1"), { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], holder: "other-link" })
    if (built._tag !== "ok") throw new Error("build")
    ax.put(built.task, "Running")
    const f = stubFloor([grantOf("1", { attempt: 2, leaseId: "wf-test-1-a2", supersedes: ["wf-test-1-a1"] })])
    await runStub(cfgOf(), ax, f.api, 600)
    expect(ax.deletes).toEqual([])
    expect(f.completes.map((c) => c.output?.reason)).toEqual(["pre-start/supersedes-foreign"])
  })

  // ------------------------------------------------------------------ finding 6: the gate is checked per UpdateTask
  it("R1-6 the Gateway disappears during the UpdateTask retry window: nothing is created while it is missing", async () => {
    const ax = new FakeAx()
    let failed = false
    const orig = ax.createTask
    ax.createTask = (task) => { if (!failed) { failed = true; ax.gateways.delete("halogen"); return Effect.fail(new AxError(UNAVAILABLE, "transient")) } return orig(task) }
    const f = stubFloor([grantOf("3")])
    const logs = await runStub(cfgOf(), ax, f.api, 1000)
    expect(logs.some((x) => x.ev === "gateway-missing")).toBe(true)
    expect(ax.tasks.has("wf-test-3-a1")).toBe(false)
    expect(logs.some((x) => x.ev === "gate-closed-before-create")).toBe(true)
  })

  it("R1-6 ax returns without P1 during the retry window: nothing is created in p1 mode", async () => {
    const ax = new FakeAx()
    let failed = false
    const orig = ax.createTask
    ax.createTask = (task) => {
      if (!failed) { failed = true; ax.up = false; setTimeout(() => { ax.p1 = false; ax.up = true }, 60); return Effect.fail(new AxError(UNAVAILABLE, "transient")) }
      return orig(task)
    }
    const f = stubFloor([grantOf("4")])
    const logs = await runStub(cfgOf(), ax, f.api, 1200)
    expect(logs.some((x) => x.ev === "p1-missing")).toBe(true)
    expect(ax.tasks.has("wf-test-4-a1")).toBe(false)
  })

  // ------------------------------------------------------------------ finding 7: guest mode fails closed
  it("R1-7 guest mode with no leaseToken in the grant: refused before UpdateTask, logged once", async () => {
    const ax = new FakeAx(); ax.p1 = false
    const f = stubFloor([grantOf("2")])
    const logs = await runStub(cfgOf({ completion: "guest", shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "http://link.fleet.internal/guest" } }), ax, f.api, 600)
    expect(ax.tasks.has("wf-test-2-a1")).toBe(false)
    expect(f.completes.map((c) => c.output?.reason)).toEqual(["pre-start/lease-token-missing"])
    expect(logs.filter((x) => x.ev === "guest-token-missing").length).toBe(1)
  })

  // ------------------------------------------------------------------ finding 9: one bad grant is refused alone
  it("R1-9 one undecodable grant next to a good one: the good one runs, the bad one is refused, no crash loop", async () => {
    const w = W({ skewedEncode: true }) // the floor sends what the link's contract calls malformed
    w.floor.enqueue(job("good"))
    w.floor.enqueue(job("bad", { "timeout-minutes": 1.5 } as any)) // a float where the contract says Schema.Int
    const l = start(w, dir)
    await until("good created", () => w.ax.tasks.has("wf-test-good-a1"))
    await until("bad refused", () => w.floor.jobs.get("wf-test-bad")!.state === "done")
    expect((w.floor.jobs.get("wf-test-bad")!.output as any).reason).toBe("pre-start/invalid-spec")
    expect(l.has("grant-invalid", "wf-test-bad-a1")).toBe(true)
    await l.drain()
    const j = Journal.open(dir)
    expect(j.pendingLeaseKey).toBeUndefined()
    expect(j.invalid.size).toBe(0) // told and compacted
  })

  it("R1-9 a Lease reply the floor cannot even encode is a typed transient error: the link stays up and heartbeats", async () => {
    const w = W() // strict floor: its own encode of the float fails
    w.floor.enqueue(job("bad", { "timeout-minutes": 1.5 } as any))
    const l = start(w, dir)
    await until("lease errors", () => l.logs.filter((x) => x.ev === "lease-error").length >= 2)
    await until("still heartbeating", () => w.floor.calls.filter((c) => c.rpc === "Heartbeat").length >= 2)
    expect(l.logs.some((x) => String(x.ev).endsWith("-died"))).toBe(false)
    expect(await l.drain()).toBeDefined() // exits on the stop signal, not on a defect
  })

  // ------------------------------------------------------------------ finding 10: configuration fails closed
  it("R1-10 numeric and enum configuration is validated: a typo is ConfigInvalid naming the key, never a NaN interval", () => {
    const bad = (env: Record<string, string>) => { try { readLinkEnv(env); return undefined } catch (e) { return e instanceof ConfigInvalid ? e.key : "other" } }
    expect(bad({ LINK_RESYNC_SECONDS: "15s" })).toBe("LINK_RESYNC_SECONDS")
    expect(bad({ LINK_MAX_IN_FLIGHT: "0" })).toBe("LINK_MAX_IN_FLIGHT")
    expect(bad({ LINK_CREATE_ATTEMPTS: "NaN" })).toBe("LINK_CREATE_ATTEMPTS")
    expect(bad({ LINK_PENDING_TIMEOUT_SECONDS: "1.5" })).toBe("LINK_PENDING_TIMEOUT_SECONDS")
    expect(bad({ LINK_COMPLETION: "gues" })).toBe("LINK_COMPLETION")
    expect(bad({ LINK_SEAT_COMMANDS: "{halogen:[ax-agent]}" })).toBe("LINK_SEAT_COMMANDS")
    expect(bad({ LINK_SEAT_COMMANDS: '{"halogen":[]}' })).toBe("LINK_SEAT_COMMANDS")
    expect(bad({ LINK_OUTBOX_BACKOFF_MIN_SECONDS: "900", LINK_OUTBOX_BACKOFF_MAX_SECONDS: "60" })).toBe("LINK_OUTBOX_BACKOFF_MAX_SECONDS")
    const ok = readLinkEnv({})
    expect([ok.resyncSeconds, ok.maxInFlight, ok.createAttempts, ok.completion, ok.seatCommands]).toEqual([15, 2, 7, "auto", { halogen: ["ax-agent", "pi"] }])
    try { readLinkEnv({ LINK_RESYNC_SECONDS: "secret-looking-value" }) } catch (e) { expect(String((e as Error).message)).not.toContain("secret-looking-value") }
  })
})
