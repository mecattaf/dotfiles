// Review round 3 (2026-09-23): the thirteen findings, each as a regression test. The scratch repros they restate are
// in /home/tom/today/evals-2026-09-23/link/scratch-r3-{0,1,2}; they failed against d582ead. The log is
// link/REVIEW-LOG.md. Test adequacy findings 11 to 13 also strengthen R1-4, R1-8 and R2-3d in place.
import { appendFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { AxError } from "../src/ax.ts"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { boundedSeconds, isFleetInternalUrl, runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"

const SEC = 20
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1` // round 4: FIELD-MAP 5a journal key (jobs.ts refuses a grant without it)
const job = (n: string, spec: Record<string, unknown> = {}): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: { name: `wf-test-${n}`, labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe" } },
  spec: { "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" }, ...spec } as AgentJob["spec"]
})
const world = (o: Partial<FloorConfig> = {}) => ({
  floor: new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" }, ...o }),
  ax: new FakeAx()
})
type World = ReturnType<typeof world>
function start(w: World, dir: string, over: Partial<LinkConfig> = {}, fetch?: typeof globalThis.fetch) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3, ...over
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: `s:${dir}`, fetch: fetch ?? w.floor.fetch })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ t: Date.now(), ev, ...f }), stop, floorUrl: "http://floor.test" })
  })))
  return {
    logs, fiber,
    has: (ev: string, leaseId?: string) => logs.some((l) => l.ev === ev && (leaseId === undefined || l.leaseId === leaseId)),
    trace: () => logs.filter((x) => typeof x.leaseId === "string" || typeof x.task === "string").map((x) => `${x.ev}:${x.leaseId ?? x.task}${x.why ? ":" + x.why : ""}`),
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
const bodyOf = async (input: unknown, init?: RequestInit) => {
  const b = init?.body
  if (typeof b === "string") return b
  if (b instanceof Uint8Array) return new TextDecoder().decode(b)
  if (b) return await new Response(b as ConstructorParameters<typeof Response>[0]).text()
  return (input instanceof Request) ? await input.clone().text() : ""
}
const rpcOf = async (input: unknown, init?: RequestInit) => { const b = await bodyOf(input, init); return b.includes('"Complete"') ? "Complete" : b.includes('"Lease"') ? "Lease" : b.includes('"Heartbeat"') ? "Heartbeat" : "?" }
const failRetryable = (w: World, name: string) => {
  const t = w.ax.tasks.get(name)!
  t.exited = true; t.phase = "Failed"
  t.conditions = [{ type: "Ready", status: "False", reason: "ResourceExhausted", message: "ResourceExhausted: no free worker" }]
}
const why = (w: World, l: ReturnType<typeof start>) => JSON.stringify({ floor: J(w).history, link: l.trace() })
/** Rewrite every JSON reply of one RPC with `patch` (a floor whose wire drifted from the link's). */
const rewriting = (w: World, rpc: string, patch: (x: any) => any): typeof globalThis.fetch => async (input, init) => {
  const b = await bodyOf(input, init)
  const res = await w.floor.fetch(input, init)
  if (!b.includes(`"${rpc}"`)) return res
  const txt = await res.text()
  let j: unknown; try { j = JSON.parse(txt) } catch { return new Response(txt, { status: res.status, headers: res.headers }) }
  return new Response(JSON.stringify(patch(j)), { status: res.status, headers: { "content-type": "application/json" } })
}
const deep = (f: (o: Record<string, unknown>) => void) => { const walk = (x: any): any => {
  if (Array.isArray(x)) return x.map(walk)
  if (x && typeof x === "object") { const o: Record<string, unknown> = {}; for (const [k, v] of Object.entries(x)) o[k] = walk(v); f(o); return o }
  return x
}; return walk }

// A floor stub that grants one lease named after a Task someone else owns (scratch-r3-1).
const stats = { seq: 1, cap: 2, wip: 0, queued: 0, done: 0 }
const foreignTask = (name: string) => ({ apiVersion: "ax.io/v1alpha1" as const, kind: "Task" as const, metadata: { name, atespace: "fleet" },
  spec: { image: "someone-else", command: ["long-job"], env: [{ name: "AX_CONWIP_HOLDER", value: "nas-link-2" }], gateway: { name: "halogen" } } })
const foreignGrant = (name: string) => ({ leaseId: name, attempt: 1, job: job("x"),
  lease: { holderIdentity: "nas-link-1", leaseDurationSeconds: 30, acquireTime: Date.now(), renewTime: Date.now(), leaseTransitions: 0 } })
const runStub = async (dir: string, ax: FakeAx, floor: any, ms: number, over: Partial<LinkConfig> = {}) => {
  const logs: Array<Record<string, any>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = { holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 60_000, deleteAfterMs: 600_000, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, ...over }
  const f = Effect.runFork(runLink(cfg, { ax, floor, journal: Journal.open(dir), log: (ev, x) => logs.push({ t: Date.now(), ev, ...x }), stop }))
  await sleep(ms)
  Effect.runSync(Deferred.succeed(stop, undefined)); await Effect.runPromise(Fiber.await(f))
  return logs
}

describe("review round 3", () => {
  let dir: string
  let worlds: Array<World> = []
  const W = (o: Partial<FloorConfig> = {}) => { const w = world(o); worlds.push(w); return w }
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "conwip-link-r3-")) })
  afterEach(() => { for (const w of worlds) w.floor.close(); worlds = []; rmSync(dir, { recursive: true, force: true }) })

  // ---------------------------------------------------------------- R3-1: a withdrawal names a generation
  for (const sendWithdrewGen of [true, false]) {
    it(`R3-1a (E) rule 4b withdraws a QUEUED a2 for a1's retryable verdict; the requeued a2 is created (floor names the generation: ${sendWithdrewGen})`, async () => {
      const w = W({ sendWithdrewGen }); w.floor.enqueue(job("1"))
      // Deterministic E: no Lease reaches the floor between its return and a1's verdict landing, so a2 gen 1 is withdrawn
      // while still QUEUED and this link never receives it (a Lease retried across the return could carry a capacity
      // computed before the verdict and receive gen 1 first: that is R2-5a's interleaving, not this one).
      let gate = false, landed = false
      const fetch: typeof globalThis.fetch = async (input, init) => {
        const rpc = await rpcOf(input, init)
        if (rpc === "Lease" && gate && !landed) throw new TypeError("fetch failed")
        const r = await w.floor.fetch(input, init)
        if (rpc === "Complete" && gate) landed = true
        return r
      }
      const l = start(w, dir, {}, fetch)
      await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
      gate = true
      w.floor.down = true
      await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
      failRetryable(w, "wf-test-1-a1")
      await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
      w.floor.down = false
      await until("a2 created", () => w.ax.updates.has("wf-test-1-a2"), 4000).catch(() => { throw new Error(why(w, l)) })
      expect(J(w).history).toContain("withdrawn:a2")
      expect(l.logs.some((x) => x.ev === "leased" && x.leaseId === "wf-test-1-a2" && l.logs.indexOf(x) < l.logs.findIndex((y) => y.ev === "complete"))).toBe(false)
      w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
      await until("floor done", () => J(w).state === "done", 4000)
      expect([J(w).result, J(w).attempt, w.ax.updates.get("wf-test-1-a2")]).toEqual(["success", 2, 1])
      await l.drain()
    })

    it(`R3-1b (C) kill -9 between the withdrawal and the regrant: the regrant of a2 is created after restart (floor names the generation: ${sendWithdrewGen})`, async () => {
      const w = W({ sendWithdrewGen }); w.floor.enqueue(job("1"))
      let holdLease = false, failHeartbeat = false, failComplete = false, holdAfterComplete = false
      const fetch: typeof globalThis.fetch = async (input, init) => {
        const rpc = await rpcOf(input, init)
        if (rpc === "Heartbeat" && failHeartbeat) throw new TypeError("fetch failed")
        if (rpc === "Complete" && failComplete) return new Response("upstream timeout", { status: 503 })
        if (rpc === "Lease") while (holdLease) await sleep(2)
        const r = await w.floor.fetch(input, init)
        if (rpc === "Complete" && holdAfterComplete) holdLease = true // the regrant never reaches this process
        return r
      }
      const over = { deleteAfterMs: 60_000 } // a1's record survives the restart's compaction; a2 gen 1 does not
      const l1 = start(w, dir, over, fetch)
      await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
      w.floor.down = true
      await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
      failHeartbeat = true; holdLease = true; failComplete = true
      w.floor.down = false
      await sleep(80)
      failRetryable(w, "wf-test-1-a1")
      await until("verdict written", () => l1.has("verdict", "wf-test-1-a1"))
      holdLease = false
      await until("a2 received", () => l1.has("leased", "wf-test-1-a2"), 4000)
      await until("dispatch waits for the verdict", () => l1.has("supersede-waits-for-verdict", "wf-test-1-a2"))
      holdAfterComplete = true; failComplete = false; failHeartbeat = false
      await until("floor withdrew a2 and the link journaled it", () => l1.has("withdrawn", "wf-test-1-a2"), 4000)
      await l1.crash()
      const l2 = start(w, dir, over)
      await until("a2 created", () => w.ax.updates.has("wf-test-1-a2"), 4000).catch(() => { throw new Error(why(w, l2)) })
      expect(w.ax.updates.get("wf-test-1-a2")).toBe(1)
      expect(J(w).history.filter((h) => h === "leased:a2").length).toBe(2) // gen 1 withdrawn, gen 2 run
      await l2.drain()
    })
  }

  // ---------------------------------------------------------------- R3-2: the cancel intent is journaled first
  it("R3-2 (A) a cancel whose DeleteTask lands but whose reply is lost is reported cancelled; no attempt 2 is started", async () => {
    const w = W({ leaseSeconds: 20, heartbeatSeconds: 6, graceSeconds: 40 }); w.floor.enqueue(job("1"))
    const l = start(w, dir, { initialHeartbeatSeconds: 6 })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const real = w.ax.deleteTask
    let lostReplies = 0
    w.ax.deleteTask = (name: string) => real(name).pipe(Effect.andThen(() => lostReplies++ === 0 ? Effect.fail(new AxError(4, "deadline exceeded")) : Effect.void))
    w.floor.cancel("wf-test-1")
    await until("floor done", () => J(w).state === "done", 4000).catch(() => { throw new Error(why(w, l)) })
    await sleep(200)
    const v = l.logs.find((x) => x.ev === "verdict" && x.leaseId === "wf-test-1-a1")!
    expect([v.result, J(w).result, J(w).attempt, J(w).infraSpent]).toEqual(["cancelled", "cancelled", 1, 0])
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false)
    expect(l.logs.some((x) => x.ev === "delete-deferred" && x.task === "wf-test-1-a1")).toBe(true)
    await l.drain()
  })

  it("R3-2b a journaled DeleteTask that did not land is sent again by the resync", async () => {
    const w = W({ leaseSeconds: 20, heartbeatSeconds: 6, graceSeconds: 40 }); w.floor.enqueue(job("1"))
    const l = start(w, dir, { initialHeartbeatSeconds: 6 })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const real = w.ax.deleteTask
    let refused = 0
    w.ax.deleteTask = (name: string) => refused++ === 0 ? Effect.fail(new AxError(14, "unavailable")) : real(name)
    w.floor.cancel("wf-test-1")
    await until("floor done", () => J(w).state === "done", 4000).catch(() => { throw new Error(why(w, l)) })
    expect([J(w).result, w.ax.deletes.filter((d) => d === "wf-test-1-a1").length]).toEqual(["cancelled", 1])
    await l.drain()
  })

  // ---------------------------------------------------------------- R3-3: finished leases are tombstoned
  for (const restart of [false, true]) it(`R3-3 (D) a redelivered grant of a finished lease is never run again (restart=${restart})`, async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("done", () => J(w).state === "done")
    await until("janitor deleted a1", () => !w.ax.tasks.has("wf-test-1-a1"), 3000)
    await sleep(100)
    let l = l1
    if (restart) { await l1.crash(); l = start(w, dir); await sleep(100) }
    w.floor.redeliver = ["wf-test-1-a1"]
    await until("duplicate-grant", () => l.has("duplicate-grant", "wf-test-1-a1"), 2000)
    await sleep(200)
    expect(w.ax.updates.get("wf-test-1-a1")).toBe(1)
    await l.drain()
  })

  it("R3-3b the tombstone survives compaction and expires after TOMB_MS; a later generation of the same leaseId is not refused", () => {
    const j = Journal.open(dir)
    const g = { leaseId: "x-a1", attempt: 1, job: job("x"), lease: { holderIdentity: "h", leaseDurationSeconds: 30, acquireTime: 1000, renewTime: 1000, leaseTransitions: 0 } }
    j.append({ ev: "grant", leaseId: "x-a1", grant: g })
    j.append({ ev: "report", leaseId: "x-a1", attempt: 1, result: "success" })
    j.append({ ev: "reported", leaseId: "x-a1", duplicate: false })
    j.compact()
    expect(j.recs.has("x-a1")).toBe(false)
    expect(Journal.open(dir).tombs.get("x-a1")?.gen).toEqual({ leaseTransitions: 0, acquireTime: 1000 })
    const keep = Journal.TOMB_MS
    try { Journal.TOMB_MS = -1; Journal.open(dir).compact(); expect(Journal.open(dir).tombs.has("x-a1")).toBe(false) } finally { Journal.TOMB_MS = keep }
  })

  // ---------------------------------------------------------------- R3-4: renewal does not wait for the first Lease
  it("R3-4 (B) a restart whose first Lease is rate-limited keeps heartbeating; the running a1 is not requeued", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    let leases = 0
    const hbAt: Array<number> = []
    const f: typeof globalThis.fetch = async (input, init) => {
      const rpc = await rpcOf(input, init)
      if (rpc === "Heartbeat") hbAt.push(Date.now())
      if (rpc === "Lease" && leases++ === 0) return new Response("slow down", { status: 429, headers: { "retry-after": "2" } })
      return w.floor.fetch(input, init)
    }
    const t0 = Date.now()
    const l2 = start(w, dir, {}, f)
    await sleep(2300)
    expect(hbAt.filter((t) => t - t0 > 200 && t - t0 < 2000).length).toBeGreaterThan(5)
    expect(J(w).history).not.toContain("requeue:grace")
    expect([J(w).attempt, w.ax.tasks.get("wf-test-1-a1")?.phase]).toEqual([1, "Running"])
    await l2.drain()
  })

  // ---------------------------------------------------------------- R3-5: a Task the link did not write is never touched
  for (const variant of ["janitor", "lost", "cancel"] as const) for (const phase of ["Running", "Completed"] as const)
    it(`R3-5a a grant named after a foreign ${phase} Task: refused name-conflict, never deleted or read (${variant})`, async () => {
      const ax = new FakeAx()
      ax.put(foreignTask("other-team-build"), "Running")
      if (phase === "Completed") ax.finish("other-team-build", 0, { secret: "other tenant's output" })
      let sent = false
      const completes: Array<any> = []
      const floor = {
        lease: (p: any) => Effect.sync(() => { const g = !sent && p.capacity > 0 ? [foreignGrant("other-team-build")] : []; if (g.length) sent = true; return { grants: g, invalid: [], stats, nextPollSeconds: 1, heartbeatSeconds: 2 } }),
        heartbeat: (p: any) => Effect.sync(() => {
          const lost = variant === "lost" ? p.leaseIds.filter((x: string) => x === "other-team-build") : []
          const cancel = variant === "cancel" ? p.leaseIds.filter((x: string) => x === "other-team-build") : []
          return { renewed: p.leaseIds.filter((x: string) => !lost.includes(x)), lost, cancelRequested: cancel, stats }
        }),
        complete: (p: any) => Effect.sync(() => { completes.push(p); return { duplicate: false, stats } })
      }
      const logs = await runStub(dir, ax, floor, 800)
      expect(ax.deletes).toEqual([])
      expect(ax.tasks.get("other-team-build")?.phase).toBe(phase)
      expect(completes.every((c) => c.result !== "success" && JSON.stringify(c).includes("secret") === false)).toBe(true)
      expect(logs.some((x) => x.ev === "not-mine" && x.leaseId === "other-team-build")).toBe(true)
    })

  it("R3-5b (salvage) a crash in the create window, then `lost`: a foreign finished Task's result is never reported, the Task never deleted", async () => {
    const g = foreignGrant("other-team-build")
    const t = Date.now()
    appendFileSync(join(dir, "journal.jsonl"), JSON.stringify({ t, ev: "grant", leaseId: g.leaseId, grant: g }) + "\n" + JSON.stringify({ t, ev: "creating", leaseId: g.leaseId }) + "\n")
    const ax = new FakeAx()
    ax.put(foreignTask("other-team-build"), "Running")
    ax.finish("other-team-build", 0, { secret: "other tenant's output" })
    const completes: Array<any> = []
    const floor = {
      lease: (_p: any) => Effect.succeed({ grants: [], invalid: [], stats, nextPollSeconds: 1, heartbeatSeconds: 2 }),
      heartbeat: (p: any) => Effect.succeed({ renewed: [], lost: p.leaseIds.filter((x: string) => x === "other-team-build"), cancelRequested: [], stats }),
      complete: (p: any) => Effect.sync(() => { completes.push(p); return { duplicate: false, stats } })
    }
    const logs = await runStub(dir, ax, floor, 600)
    expect([completes, ax.deletes]).toEqual([[], []])
    expect(logs.some((x) => x.ev === "not-mine")).toBe(true)
  })

  it("R3-5c the link's own Task under a `creating`-only record (crash before `created`) is still salvaged and deleted", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    w.ax.hangAfterCreate = true
    const l1 = start(w, dir)
    await until("created in ax", () => w.ax.tasks.has("wf-test-1-a1"))
    await l1.crash()
    w.ax.hangAfterCreate = false
    w.ax.tick()
    w.ax.finish("wf-test-1-a1", 0, { mine: true })
    const l2 = start(w, dir)
    await until("floor done", () => J(w).state === "done", 4000).catch(() => { throw new Error(why(w, l2)) })
    expect([J(w).result, J(w).output]).toEqual(["success", { mine: true }])
    await until("deleted", () => !w.ax.tasks.has("wf-test-1-a1"), 3000)
    expect(l2.has("not-mine")).toBe(false)
    await l2.drain()
  })

  // ---------------------------------------------------------------- R3-6 and R3-7: server-driven intervals are bounded
  for (const v of [0, -5]) it(`R3-6 a floor answering nextPollSeconds=${v} and heartbeatSeconds=${v} gets a bounded call rate (production secondMs)`, async () => {
    const w = W({ pollSeconds: v, heartbeatSeconds: v, secondMs: 1000, leaseSeconds: 60, graceSeconds: 60 })
    w.floor.enqueue(job("1"))
    const l = start(w, dir, { secondMs: 1000, resyncMs: 1000, initialPollSeconds: 15, initialHeartbeatSeconds: 30 })
    await sleep(1500)
    const n = (rpc: string) => w.floor.calls.filter((c) => c.rpc === rpc).length
    expect(n("Lease")).toBeLessThanOrEqual(4)
    expect(n("Heartbeat")).toBeLessThanOrEqual(4)
    expect(l.has("interval-clamped")).toBe(true)
    await l.drain()
  })

  it("R3-7 boundedSeconds: default for missing, non-finite and not positive; clamped to [1, hi]", () => {
    expect([boundedSeconds(undefined, 15, 300), boundedSeconds(0, 15, 300), boundedSeconds(-5, 15, 300), boundedSeconds(Number.NaN, 15, 300),
      boundedSeconds(0.2, 15, 300), boundedSeconds(10 / 3, 15, 300), boundedSeconds(1e9, 15, 300), boundedSeconds(60, 30, 10)]).toEqual([15, 15, 15, 15, 1, 10 / 3, 300, 10])
  })

  // ---------------------------------------------------------------- R3-8: the Lease envelope decodes leniently
  it("R3-8 a Lease reply with heartbeatSeconds 3.333, endpoint null and no stats is used; the job runs", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const fetch = rewriting(w, "Lease", deep((o) => { if ("heartbeatSeconds" in o) { o.heartbeatSeconds = 10 / 3; o.endpoint = null; delete o.stats } }))
    const l = start(w, dir, {}, fetch)
    await until("created", () => w.ax.updates.has("wf-test-1-a1"), 4000).catch(() => { throw new Error(why(w, l)) })
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done", 4000)
    expect([J(w).result, J(w).attempt, l.has("lease-error")]).toEqual(["success", 1, false])
    await l.drain()
  })

  it("R3-8b a Lease key whose replies never decode is abandoned after leaseKeyAttempts, not replayed for ever; the job then runs", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let broken = true
    const keys: Array<string> = []
    const inner = rewriting(w, "Lease", deep((o) => { if (broken && "grants" in o && "nextPollSeconds" in o) o.grants = "not-an-array" }))
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const b = await bodyOf(input, init)
      const k = /"requestKey":"([^"]+)"/.exec(b)?.[1]
      if (k && b.includes('"Lease"') && broken) keys.push(k)
      return inner(input, init)
    }
    const l = start(w, dir, { leaseKeyAttempts: 3 }, fetch)
    await until("key abandoned twice", () => l.logs.filter((x) => x.ev === "lease-key-abandoned").length >= 2, 4000).catch(() => { throw new Error(why(w, l)) })
    broken = false
    expect(new Set(keys).size).toBeGreaterThan(1) // before round 3: one key, `transient`, for as long as the floor answers so
    expect(l.logs.filter((x) => x.ev === "lease-error").every((x) => x.kind === "server-error")).toBe(true)
    await until("created", () => w.ax.updates.size > 0, 4000).catch(() => { throw new Error(why(w, l)) })
    await l.drain()
  })

  it("R3-8c (R1-9b scenario) a floor that cannot encode one job: the link stays up and a job enqueued later runs", async () => {
    // The good job co-granted with the bad one is only ever sent inside replies the strict floor cannot encode, so no
    // link-side change can deliver it (REFUTED for the link; the floor port must encode per grant, round 1 H).
    const w = W()
    w.floor.enqueue(job("bad", { "timeout-minutes": 1.5 }))
    w.floor.enqueue(job("good"))
    const l = start(w, dir)
    await sleep(500)
    w.floor.enqueue(job("later"))
    await until("later created", () => w.ax.updates.has("wf-test-later-a1"), 8000).catch(() => { throw new Error(why(w, l)) })
    expect(l.logs.filter((x) => x.ev === "lease-error").every((x) => x.kind === "server-error")).toBe(true)
    await l.drain()
  })

  // ---------------------------------------------------------------- R3-9: Complete's success decodes leniently
  it("R3-9 a Complete success reply with `withdrew: null` is reported once; the next jobs run", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.floor.enqueue(job("2"))
    let completes = 0
    const patch = deep((o) => { if ("duplicate" in o && "stats" in o && !("withdrew" in o)) o.withdrew = null })
    const inner = rewriting(w, "Complete", patch)
    const fetch: typeof globalThis.fetch = async (input, init) => { if (await rpcOf(input, init) === "Complete") completes++; return inner(input, init) }
    const l = start(w, dir, { maxInFlight: 1 }, fetch)
    await until("a1", () => w.ax.tasks.has("wf-test-1-a1"))
    w.ax.finish("wf-test-1-a1", 0, { ok: true })
    await until("job 2 created", () => w.ax.updates.has("wf-test-2-a1"), 4000).catch(() => { throw new Error(why(w, l)) })
    expect([J(w).state, J(w).result, completes, l.has("outbox-keep")]).toEqual(["done", "success", 1, false])
    await l.drain()
  })

  it("R3-9b a Complete success reply that is not the protocol at all is a server-error: bounded by verdictAttempts, never gates Lease", async () => {
    const w = W(); w.floor.enqueue(job("1")); w.floor.enqueue(job("2"))
    // the floor applies the verdict; its reply's success value is replaced by a number
    const fetch = rewriting(w, "Complete", deep((o) => { if (o.value && typeof o.value === "object" && "duplicate" in (o.value as object)) o.value = 7 }))
    const l = start(w, dir, { maxInFlight: 1, verdictAttempts: 2 }, fetch)
    await until("a1", () => w.ax.tasks.has("wf-test-1-a1"))
    w.ax.finish("wf-test-1-a1", 0, { ok: true })
    await until("job 2 created", () => w.ax.updates.has("wf-test-2-a1"), 4000).catch(() => { throw new Error(why(w, l)) })
    expect(l.logs.filter((x) => x.ev === "outbox-keep").every((x) => x.kind === "server-error")).toBe(true)
    await l.drain()
  })

  // ---------------------------------------------------------------- R3-10: B2 (n+1 only after NotFound for n)
  it("R3-10 (F8 shape) attempt n+1 is written only once attempt n is absent from ax; while n stays Terminating it is never written", async () => {
    const w = W()
    const create = w.ax.createTask
    const seenAtCreate: Array<string> = []
    w.ax.createTask = (t) => { if (t.metadata.name === "wf-test-1-a2") seenAtCreate.push(...[...w.ax.tasks].map(([n, x]) => `${n}:${x.phase}`)); return create(t) }
    w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    rmSync(dir, { recursive: true, force: true }) // the journal is lost: a2 is fenced on the Task's own marks
    await sleep(7 * SEC); w.floor.sweep()
    const tick = w.ax.tick.bind(w.ax)
    let hold = true
    w.ax.tick = () => { if (hold) { for (const t of w.ax.tasks.values()) if (t.phase === "Pending") t.phase = "Running" } else tick() }
    const l2 = start(w, mkdtempSync(join(tmpdir(), "conwip-link-r3-")), { fenceTimeoutMs: 4000 })
    await until("a1 Terminating", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Terminating", 4000).catch(() => { throw new Error(why(w, l2)) })
    await sleep(250)
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false) // the delete was asked, NotFound not yet seen
    hold = false
    await until("a2 written", () => w.ax.updates.has("wf-test-1-a2"), 6000).catch(() => { throw new Error(why(w, l2)) })
    expect(seenAtCreate.filter((x) => x.startsWith("wf-test-1-a1"))).toEqual([])
    await l2.drain()
  })

  // ---------------------------------------------------------------- R3-11: 429, Retry-After, endpoint and address rows
  it("R3-11 a Complete answered 429 Retry-After: 1 keeps the verdict and waits at least Retry-After before the next try", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const at: Array<number> = []
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (await rpcOf(input, init) !== "Complete") return w.floor.fetch(input, init)
      at.push(Date.now())
      if (at.length === 1) return new Response("slow down", { status: 429, headers: { "retry-after": "1" } })
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, fetch)
    await until("a1", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { v: 1 })
    await until("floor done", () => J(w).state === "done", 5000).catch(() => { throw new Error(why(w, l)) })
    expect([J(w).result, J(w).attempt, l.has("complete-dropped")]).toEqual(["success", 1, false])
    expect(l.logs.some((x) => x.ev === "outbox-keep" && x.kind === "rate-limited")).toBe(true)
    expect(at[1]! - at[0]!).toBeGreaterThanOrEqual(950)
    await l.drain()
  })

  it("R3-11b an http:// endpoint is ignored even when it is in the declared list; 100.x outside 100.64/10 is not fleet-internal", async () => {
    const w = W()
    const fetch = rewriting(w, "Lease", deep((o) => { if ("nextPollSeconds" in o) o.endpoint = "http://floor2.test" }))
    const switched: Array<string> = []
    const logs: Array<Record<string, unknown>> = []
    const stop = Effect.runSync(Deferred.make<void>())
    const cfg: LinkConfig = { holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
      shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
      completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
      createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, floorUrls: ["http://floor.test", "http://floor2.test"] }
    const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
      const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: "s", fetch })
      return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ ev, ...f }), stop, floorUrl: "http://floor.test", onEndpoint: (u) => switched.push(u) })
    })))
    await until("endpoint seen", () => logs.some((x) => x.ev === "endpoint-ignored" || x.ev === "endpoint-accepted"), 3000)
    Effect.runSync(Deferred.succeed(stop, undefined)); await Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)])
    expect([switched, logs.some((x) => x.ev === "endpoint-ignored")]).toEqual([[], true])
    expect(["http://100.1.2.3/c", "http://100.128.0.1/c", "http://100.63.255.255/c", "http://100.64.0.1/c", "http://100.127.255.254/c"].map((u) => isFleetInternalUrl(u)))
      .toEqual([false, false, false, true, true])
  })
})
