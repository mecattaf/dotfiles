// Review round 2 (2026-09-23): the twelve findings, each as a regression test. The scratch repros they restate are in
// /home/tom/today/evals-2026-09-23/link/scratch-r2-{0,1,2}; they failed against c5ed453. The log is link/REVIEW-LOG.md.
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { cidrIsOpen, gatewayAllowsAll } from "../src/ax.ts"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { isFleetInternalUrl, runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"

const SEC = 20
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1` // round 4: FIELD-MAP 5a journal key (jobs.ts refuses a grant without it)
const job = (n: string): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: { name: `wf-test-${n}`, labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe" } },
  spec: { "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" } }
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
/** A capacity race: Failed with ResourceExhausted, which the link maps to retryable pre-start/resource-exhausted. */
const failRetryable = (w: World, name: string) => {
  const t = w.ax.tasks.get(name)!
  t.exited = true; t.phase = "Failed"
  t.conditions = [{ type: "Ready", status: "False", reason: "ResourceExhausted", message: "ResourceExhausted: no free worker" }]
}
const why = (w: World, l: ReturnType<typeof start>) => JSON.stringify({ floor: J(w).history, link: l.trace() })

// A floor stub for the fail-closed tests (scratch-r2-1/repro.mts): hands out its grants once, renews everything.
const stats = { seq: 1, cap: 2, wip: 0, queued: 0, done: 0 }
const grantOf = (n: string, extra: Record<string, unknown> = {}) => ({ leaseId: `wf-test-${n}-a1`, attempt: 1, job: job(n),
  lease: { holderIdentity: "nas-link-1", leaseDurationSeconds: 30, acquireTime: Date.now(), renewTime: Date.now(), leaseTransitions: 0 }, ...extra })
const stubFloor = (grants: Array<any>, gate: () => boolean = () => true) => {
  let sent = false
  return {
    lease: (p: any) => Effect.sync(() => { const g = !sent && p.capacity > 0 && gate() ? grants : []; if (g.length) sent = true; return { grants: g, invalid: [], stats, nextPollSeconds: 1, heartbeatSeconds: 2 } }),
    heartbeat: (p: any) => Effect.succeed({ renewed: [...p.leaseIds], lost: [], cancelRequested: [], stats }),
    complete: (_p: any) => Effect.succeed({ duplicate: false, stats })
  }
}
const runStub = async (over: Partial<LinkConfig>, ax: FakeAx, floor: any, ms: number) => {
  const dir = mkdtempSync(join(tmpdir(), "conwip-link-r2s-"))
  const logs: Array<Record<string, any>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = { holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 60_000, deleteAfterMs: 60_000, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, ...over }
  const f = Effect.runFork(runLink(cfg, { ax, floor, journal: Journal.open(dir), log: (ev, x) => logs.push({ t: Date.now(), ev, ...x }), stop }))
  await sleep(ms)
  Effect.runSync(Deferred.succeed(stop, undefined)); await Effect.runPromise(Fiber.await(f)); rmSync(dir, { recursive: true, force: true })
  return logs
}

describe("review round 2: fixed", () => {
  let dir: string
  let worlds: Array<World> = []
  const W = (o: Partial<FloorConfig> = {}) => { const w = world(o); worlds.push(w); return w }
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "conwip-link-r2-")) })
  afterEach(() => { for (const w of worlds) w.floor.close(); worlds = []; rmSync(dir, { recursive: true, force: true }) })

  // ---------------------------------------------------------------- R2-1: heartbeat `lost` and the janitor read first
  it("R2-1a kill -9, the agent finishes, the floor requeues past grace, restart while ax is down: the success is delivered, a2 never runs", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("requeued by the alarm", () => J(w).history.includes("requeue:grace"), 3000)
    w.ax.up = false
    const l2 = start(w, dir)
    await until("heartbeat says lost", () => l2.has("lost", "wf-test-1-a1"))
    w.ax.up = true
    await until("floor settles", () => J(w).state === "done" || w.ax.updates.has("wf-test-1-a2"), 4000)
    await sleep(200)
    expect(w.ax.updates.has("wf-test-1-a2"), why(w, l2)).toBe(false)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    expect(l2.logs.findIndex((x) => x.ev === "verdict")).toBeLessThan(l2.logs.findIndex((x) => x.ev === "delete" && x.task === "wf-test-1-a1"))
    await l2.drain()
  })

  it("R2-1b no restart: the agent finishes as the partition heals and the heartbeat's lost beats the resync: the success is delivered", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    const l = start(w, dir, { resyncMs: 300 })
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    await until("requeued by the alarm", () => J(w).history.includes("requeue:grace"), 3000)
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    w.floor.down = false
    await until("floor settles", () => J(w).state === "done" || w.ax.updates.has("wf-test-1-a2"), 4000)
    await sleep(200)
    expect(w.ax.updates.has("wf-test-1-a2"), why(w, l)).toBe(false)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    await l.drain()
  })

  // ---------------------------------------------------------------- R2-2: the supersede fence reads first
  it("R2-2 the Lease wins the race (heartbeats failing): a2's fence reads a1's Completed result, the floor withdraws a2", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let failHeartbeat = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (failHeartbeat && await rpcOf(input, init) === "Heartbeat") throw new TypeError("fetch failed")
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, { resyncMs: 300 }, fetch)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    await until("requeued by the alarm", () => J(w).history.includes("requeue:grace"), 3000)
    failHeartbeat = true
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    w.floor.down = false
    await until("floor settles", () => J(w).state === "done" || w.ax.updates.has("wf-test-1-a2"), 4000)
    failHeartbeat = false
    await sleep(200)
    expect(w.ax.updates.has("wf-test-1-a2"), why(w, l)).toBe(false)
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { answer: 42 }, 1])
    await l.drain()
  })

  // ---------------------------------------------------------------- R2-3: one verdict never wedges the link
  it("R2-3a a result over the link's output cap is refused agent/output-too-large; later jobs are leased", async () => {
    const w = W({ cap: 4 }); w.floor.enqueue(job("1"))
    const l = start(w, dir, { maxInFlight: 2, outboxBackoffMs: [20, 60] })
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { report: "x".repeat(2 * 1024 * 1024 + 1000) })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    w.floor.enqueue(job("2")); w.floor.enqueue(job("3"))
    await until("job 2 leased", () => J(w, "2").state !== "queued", 3000)
    expect([J(w).result, (J(w).output as any)?.reason]).toEqual(["failure", "agent/output-too-large"])
    await l.drain()
  })

  it("R2-3b a verdict the floor answers 500 every time is replaced by infra/verdict-undeliverable, and never gates Lease", async () => {
    const w = W({ cap: 4 }); w.floor.enqueue(job("1"))
    let refused = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const b = await bodyOf(input, init)
      if (b.includes('"Complete"') && b.includes('"success"')) { refused++; return new Response("internal error", { status: 500 }) }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, { outboxBackoffMs: [20, 60], verdictAttempts: 4 }, fetch)
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    w.floor.enqueue(job("2"))
    await until("job 2 leased", () => J(w, "2").state !== "queued", 3000)
    await until("job 1 closed", () => J(w).state === "done", 3000)
    expect([J(w).result, (J(w).output as any)?.reason, refused]).toEqual(["failure", "infra/verdict-undeliverable", 4])
    expect(l.has("verdict-replaced", "wf-test-1-a1")).toBe(true)
    await l.drain()
  })

  it("R2-3c an RPC Defect reply (SQLITE_TOOBIG) is a server-error, not an encode defect", async () => {
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const req = JSON.parse(await bodyOf(input, init)), id = (Array.isArray(req) ? req[0] : req).id
      return new Response(JSON.stringify([{ _tag: "Exit", requestId: id, exit: { _tag: "Failure", cause: [{ _tag: "Die", defect: { message: "string or blob too big: SQLITE_TOOBIG" } }] } }]), { status: 200, headers: { "content-type": "application/json" } })
    }
    const e = await Effect.runPromise(Effect.scoped(Effect.gen(function*() {
      const floor = yield* rpcFloor({ url: "http://floor.test", token: "t", sessionId: "s", fetch })
      return yield* floor.complete({ leaseId: "x-a1", attempt: 1, result: "success", output: {} }).pipe(Effect.flip)
    })))
    expect([e._tag, (e as any).kind, /SQLITE_TOOBIG/.test((e as any).message ?? "")]).toEqual(["FloorError", "server-error", true])
  })

  it("R2-3d Complete classification: 413 and 422 drop the verdict, 404 is fatal misrouted (verdict kept), 500 is server-error, 503 transient", async () => {
    const out: Record<number, string> = {}
    for (const status of [413, 422, 404, 500, 503, 429]) {
      const e = await Effect.runPromise(Effect.scoped(Effect.gen(function*() {
        const floor = yield* rpcFloor({ url: "http://floor.test", token: "t", sessionId: "s", fetch: async () => new Response("x", { status, headers: { "retry-after": "7" } }) })
        return yield* floor.complete({ leaseId: "x-a1", attempt: 1, result: "success" }).pipe(Effect.flip)
      })))
      out[status] = e._tag === "CompleteRefused" ? `refused:${e.code}` : `${e.kind}:${e.fatal}${e.kind === "rate-limited" ? `:${e.retryAfterMs}` : ""}`
    }
    // round 3 (finding 13): 429 is rate-limited with its Retry-After, the verdict kept (not `rejected`, which drops it)
    expect(out).toEqual({ 413: "refused:http-413", 422: "refused:http-422", 404: "misrouted:true", 500: "server-error:false", 503: "transient:false", 429: "rate-limited:false:7000" })
  })

  // ---------------------------------------------------------------- R2-4: withdrawal is explicit on the wire
  it("R2-4a a Lease crosses a1's retryable verdict, whose reply is lost; the resend answers duplicate: a2 is created", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let holdLease = false, loseCompleteReply = false, failComplete = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const rpc = await rpcOf(input, init)
      if (rpc === "Lease") while (holdLease) await sleep(2)
      if (rpc === "Complete" && failComplete) return new Response("upstream timeout", { status: 503 })
      if (rpc === "Complete" && loseCompleteReply) { await w.floor.fetch(input, init); loseCompleteReply = false; failComplete = true; throw new TypeError("fetch failed") }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, fetch)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    holdLease = true
    await sleep(60)
    loseCompleteReply = true
    failRetryable(w, "wf-test-1-a1")
    await until("floor applied a1 and requeued a2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
    holdLease = false
    await until("a2 granted", () => l.has("leased", "wf-test-1-a2"), 4000)
    await until("dispatch waits for the verdict", () => l.has("supersede-waits-for-verdict", "wf-test-1-a2"))
    failComplete = false
    await until("a2 created or withdrawn", () => w.ax.updates.has("wf-test-1-a2") || l.has("withdrawn", "wf-test-1-a2"), 4000)
    await sleep(300)
    expect(l.has("withdrawn", "wf-test-1-a2"), why(w, l)).toBe(false)
    expect(w.ax.updates.get("wf-test-1-a2")).toBe(1)
    expect(J(w).history).not.toContain("requeue:omitted")
    await l.drain()
  })

  it("R2-4b the same race with an infrastructure budget of 2: the retry runs once, the job is not ended retry-budget-spent", async () => {
    const w = W({ infraAttempts: 2 }); w.floor.enqueue(job("1"))
    let armed = false, dropped = 0, committed!: () => void
    const done = new Promise<void>((r) => { committed = r })
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const body = await bodyOf(input, init)
      if (armed && body.includes('"Lease"') && /"capacity":[1-9]/.test(body)) { armed = false; await done }
      if (body.includes('"Complete"') && body.includes("wf-test-1-a1") && dropped > 0) await sleep(200)
      const res = await w.floor.fetch(input, init)
      if (body.includes('"Complete"') && body.includes("wf-test-1-a1") && dropped === 0) { dropped++; committed(); throw new TypeError("fetch failed: reply lost") }
      return res
    }
    const l = start(w, dir, { outboxBackoffMs: [150, 150], fenceTimeoutMs: 3000 }, fetch)
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    armed = true
    await until("a Lease with capacity is held", () => !armed, 3000)
    failRetryable(w, "wf-test-1-a1")
    await until("a2 leased", () => l.has("leased", "wf-test-1-a2"), 4000)
    await until("a2 created", () => w.ax.updates.has("wf-test-1-a2"), 4000).catch(() => {})
    expect(w.ax.updates.get("wf-test-1-a2") ?? 0, why(w, l)).toBe(1)
    expect(l.has("withdrawn", "wf-test-1-a2")).toBe(false)
    expect((J(w).output as any)?.reason).not.toBe("infra/retry-budget-spent")
    await l.drain()
  })

  // ---------------------------------------------------------------- R2-5: a regrant of a withdrawn leaseId is new work
  it("R2-5a rule 4b withdraws a2 for a1's retryable verdict and the floor grants a2 again: the new generation is created", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let holdLease = false, failHeartbeat = false, failComplete = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const rpc = await rpcOf(input, init)
      if (rpc === "Heartbeat" && failHeartbeat) throw new TypeError("fetch failed")
      if (rpc === "Complete" && failComplete) return new Response("upstream timeout", { status: 503 })
      if (rpc === "Lease") while (holdLease) await sleep(2)
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, fetch)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
    failHeartbeat = true; holdLease = true; failComplete = true
    w.floor.down = false
    await sleep(80)
    failRetryable(w, "wf-test-1-a1")
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    holdLease = false
    await until("a2 received", () => l.has("leased", "wf-test-1-a2"), 4000)
    await until("dispatch waits for the verdict", () => l.has("supersede-waits-for-verdict", "wf-test-1-a2"))
    failComplete = false; failHeartbeat = false
    await until("a2 created, or the floor gives up on a2", () => w.ax.updates.has("wf-test-1-a2") || J(w).attempt >= 3 || J(w).state === "done", 4000).catch(() => {})
    expect(w.ax.updates.get("wf-test-1-a2") ?? 0, why(w, l)).toBe(1)
    expect(l.has("duplicate-grant", "wf-test-1-a2")).toBe(false)
    await l.drain()
  })

  it("R2-5b the Lease reply carrying a2 is slow; a1's retryable verdict lands first and withdraws it; the regrant is created", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let holdLeaseReply = false, failHeartbeat = false
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const rpc = await rpcOf(input, init)
      if (rpc === "Heartbeat" && failHeartbeat) throw new TypeError("fetch failed")
      if (rpc === "Lease" && holdLeaseReply) { const r = await w.floor.fetch(input, init); while (holdLeaseReply) await sleep(2); return r }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, {}, fetch)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    await until("floor requeued attempt 2", () => J(w).state === "queued" && J(w).attempt === 2, 4000)
    failHeartbeat = true; holdLeaseReply = true
    w.floor.down = false
    await until("floor leased a2 to this link", () => J(w).state === "leased" && J(w).attempt === 2, 4000)
    failRetryable(w, "wf-test-1-a1")
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    holdLeaseReply = false
    await until("a2 received", () => l.has("leased", "wf-test-1-a2"), 4000)
    failHeartbeat = false
    await until("a2 created, or the floor gives up", () => w.ax.updates.has("wf-test-1-a2") || J(w).attempt >= 3 || J(w).state === "done", 4000).catch(() => {})
    expect(w.ax.updates.get("wf-test-1-a2") ?? 0, why(w, l)).toBe(1)
    await l.drain()
  })

  // ---------------------------------------------------------------- R2-6: redirects are never followed
  it("R2-6 the floor answers 307 to another origin: nothing is leased or created and the link stops fatal (redirect)", async () => {
    const w = W(); w.floor.enqueue(job("1"))
    let rogue = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if ((init as RequestInit | undefined)?.redirect !== "manual") { rogue++; return w.floor.fetch(input, init) } // a follower would land on the rogue origin
      return new Response(null, { status: 307, headers: { location: "http://127.0.0.1:9/rpc" } })
    }
    const l = start(w, dir, {}, fetch)
    const exit = await Promise.race([Effect.runPromise(Fiber.await(l.fiber)), sleep(1500).then(() => undefined)])
    expect([rogue, w.ax.tasks.size, l.has("leased")]).toEqual([0, 0, false])
    expect(exit?._tag).toBe("Failure")
    expect(JSON.stringify(exit)).toContain("redirect")
  })

  // ---------------------------------------------------------------- R2-7, R2-8: fail-closed checks
  it("R2-7 isFleetInternalUrl matches private ranges on IP literals only", () => {
    for (const u of ["https://10.evil.example/guest", "https://127.0.0.1.nip.io/guest", "https://192.168.0.1.attacker.com/c", "https://link/guest", "https://x.workers.dev/", "https://10.internal.example.com/"])
      expect([u, isFleetInternalUrl(u)]).toEqual([u, false])
    for (const u of ["http://10.201.0.80:8080/c", "http://127.0.0.1/c", "http://100.64.0.7/c", "http://[fd7a:115c:a1e0::1]/c", "http://[::1]/c", "http://link.fleet.internal/guest", "http://nas.lan/c", "http://localhost:1/c", "http://0x7f.1/c"])
      expect([u, isFleetInternalUrl(u)]).toEqual([u, true])
    expect(isFleetInternalUrl("http://link/guest", ["link"])).toBe(true)
  })

  it("R2-7b guest mode with a public name that starts with a private prefix: no Task, no token handed out", async () => {
    const ax = new FakeAx(); ax.p1 = false
    const logs = await runStub({ completion: "guest", shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "https://10.evil.example/guest" } },
      ax, stubFloor([grantOf("g", { leaseToken: "tok" })]), 400)
    expect([logs.some((l) => l.ev === "guest-url-invalid"), ax.tasks.has("wf-test-g-a1")]).toEqual([true, false])
  })

  it("R2-8 a Gateway open by CIDR arithmetic is refused: ::/0, 0.0.0.0/1 + 128.0.0.0/1, and unparseable CIDRs", async () => {
    const gw = (hosts: Array<string>) => ({ hasAllowlist: true, hosts: hosts.map((host) => ({ host, port: 443 })) })
    expect(gatewayAllowsAll(gw(["worker", "::/0"]))).toBe(true)
    expect(gatewayAllowsAll(gw(["0.0.0.0/1", "128.0.0.0/1"]))).toBe(true)
    expect(gatewayAllowsAll(gw([" * "]))).toBe(true)
    expect(gatewayAllowsAll(gw(["10.0.0.0/x"]))).toBe(true)
    expect(gatewayAllowsAll(gw(["worker", "10.201.0.0/24", "fd7a:115c:a1e0::/48"]))).toBe(false)
    expect([cidrIsOpen("8.0.0.0/8"), cidrIsOpen("10.1.0.0/16"), cidrIsOpen("2000::/3"), cidrIsOpen("fd00::/64")]).toEqual([true, false, true, false])
    const ax = new FakeAx()
    ax.gateways.set("halogen", gw(["worker", "::/0"]))
    const logs = await runStub({}, ax, stubFloor([grantOf("w")]), 400)
    expect([logs.some((l) => l.ev === "gateway-missing"), ax.tasks.has("wf-test-w-a1")]).toEqual([true, false])
  })

  // ---------------------------------------------------------------- R2-9: nothing from before an ax outage opens the gate
  it("R2-9 guest mode: ax returns without the Gateway and GetGateway is slow; nothing is created on pre-outage state", async () => {
    const ax = new FakeAx(); ax.p1 = false
    const origGw = ax.getGateway
    let outageOver = false, release = false
    ax.getGateway = (name: string) => outageOver ? Effect.sleep(300).pipe(Effect.andThen(origGw(name))) : origGw(name)
    setTimeout(() => { ax.up = false }, 150)
    setTimeout(() => { release = true }, 170)
    setTimeout(() => { ax.gateways.delete("halogen"); outageOver = true; ax.up = true }, 400)
    const logs = await runStub({ completion: "guest", shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "http://link.fleet.internal/guest" } },
      ax, stubFloor([grantOf("u", { leaseToken: "tok" })], () => release), 1200)
    expect(ax.tasks.has("wf-test-u-a1"), JSON.stringify(logs.map((l) => l.ev))).toBe(false)
    expect(logs.some((l) => l.ev === "gateway-missing")).toBe(true)
  })

  // ---------------------------------------------------------------- R2-11: a permanent Complete refusal is dropped
  for (const variant of ["http-413", "unknown-error-code"] as const)
    it(`R2-11 one Complete refused for good (${variant}) is dropped and job 2 is leased`, async () => {
      const w = W(); w.floor.enqueue(job("1"))
      const fetch: typeof globalThis.fetch = async (input, init) => {
        const body = await bodyOf(input, init)
        if (body.includes('"Complete"') && body.includes("wf-test-1-a1")) {
          if (variant === "http-413") return new Response("payload too large", { status: 413 })
          const req = JSON.parse(body), id = (Array.isArray(req) ? req[0] : req).id
          return new Response(JSON.stringify([{ _tag: "Exit", requestId: id, exit: { _tag: "Failure", cause: [{ _tag: "Fail", error: { code: "output-too-large" } }] } }]), { status: 200, headers: { "content-type": "application/json" } })
        }
        return w.floor.fetch(input, init)
      }
      const l = start(w, dir, { outboxBackoffMs: [20, 40] }, fetch)
      await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
      w.ax.finish("wf-test-1-a1", 0, { big: "x" })
      await until("verdict", () => l.has("verdict", "wf-test-1-a1"))
      w.floor.enqueue(job("2"))
      await until("job 2 leased", () => J(w, "2").state !== "queued", 3000)
      const d = l.logs.find((x) => x.ev === "complete-dropped" && x.leaseId === "wf-test-1-a1")
      expect(d?.code).toBe(variant === "http-413" ? "http-413" : "output-too-large")
      await l.drain()
    })
})
