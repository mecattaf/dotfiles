// The failure matrix of LINK-DESIGN.md section 8, one test per row, against the two doubles (fake ax with v0.3.0
// upsert semantics and an optional P1; fake floor served through Effect's HTTP RPC server). Every server-set
// interval is scaled so one "second" is SEC ms. A crash is a fiber interrupt: nothing after it runs, and only what the
// journal fsynced survives, which is what kill -9 leaves.
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Exit, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"

const SEC = 20
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1` // round 4: FIELD-MAP 5a journal key (jobs.ts refuses a grant without it)
const job = (n: string, spec: Partial<AgentJob["spec"]> = {}, ann: Record<string, string> = {}, w: Partial<AgentJob["spec"]["with"]> = {}): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: {
    name: `wf-test-${n}`,
    labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe", ...ann }
  },
  spec: {
    "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next", ...w },
    ...spec
  }
})
const world = (o: Partial<FloorConfig> = {}) => ({
  floor: new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" }, ...o }),
  ax: new FakeAx()
})
type World = ReturnType<typeof world>

const GUEST = { completion: "guest" as const, shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "http://link.fleet.internal/guest" } }
const guestWorld = () => { const w = world({ tokens: { "tok-nas": { holder: "nas-link-1", guest: true } } }); w.ax.p1 = false; return w }

function start(w: World, dir: string, over: Partial<LinkConfig> = {}, session = `s:${dir}`) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, ...over
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: session, fetch: w.floor.fetch })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ ev, ...f }), stop })
  })))
  return {
    logs,
    has: (ev: string, leaseId?: string) => logs.some((l) => l.ev === ev && (leaseId === undefined || l.leaseId === leaseId)),
    crash: () => Effect.runPromise(Fiber.interrupt(fiber)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Effect.runPromise(Fiber.await(fiber)) },
    exit: () => Effect.runPromise(Fiber.await(fiber))
  }
}
const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const J = (w: World, n = "1") => w.floor.jobs.get(`wf-test-${n}`)!

describe("conwip link failure matrix", () => {
  let dir: string
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "conwip-link-")) })
  afterEach(() => rmSync(dir, { recursive: true, force: true }))

  it("F0 happy path on P1: one create, typed verdict with usage, Task deleted after the floor acknowledged", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const env = Object.fromEntries(w.ax.tasks.get("wf-test-1-a1")!.task.spec.env.map((e) => [e.name, e.value]))
    expect(env.AX_CONWIP_ITEM_KEY).toBe("wf_test#1"); expect(env.AX_CONWIP_ATTEMPT).toBe("1"); expect(env.AX_CONWIP_PROMPT).toBe("say 1")
    expect(env.AX_CONWIP_LEASE_TOKEN).toBeUndefined() // P1 present: the guest carries no token at all
    expect(w.ax.tasks.get("wf-test-1-a1")!.task.apiVersion).toBe("ax.io/v1alpha1")
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).output, J(w).usage]).toEqual(["success", { answer: 42 }, { prompt_tokens: 11, completion_tokens: 7, tool_calls: 3 }])
    await until("janitor deleted the Task", () => !w.ax.tasks.has("wf-test-1-a1"))
    expect(w.ax.updates.get("wf-test-1-a1")).toBe(1); expect(w.ax.upsertsOnExisting).toBe(0)
    await l.drain()
  })

  it("F1 duplicate delivery: a redelivered grant creates nothing twice", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.redeliver = ["wf-test-1-a1"]
    await until("duplicate seen", () => l.has("duplicate-grant", "wf-test-1-a1"))
    w.ax.finish("wf-test-1-a1", 0, { ok: true })
    await until("floor done", () => J(w).state === "done")
    expect(w.ax.updates.get("wf-test-1-a1")).toBe(1); expect(w.ax.upsertsOnExisting).toBe(0)
    await l.drain()
  })

  it("F2 crash after Lease, before UpdateTask: the restart creates exactly once", async () => {
    const w = world(); w.floor.enqueue(job("1")); w.ax.blockCreate = true
    const l1 = start(w, dir)
    await until("grant journaled", () => l1.has("leased", "wf-test-1-a1"))
    await l1.crash()
    w.ax.blockCreate = false
    const l2 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt, w.ax.updates.get("wf-test-1-a1")]).toEqual(["success", 1, 1])
    await l2.drain()
  })

  it("F3 crash after UpdateTask, before the journal said created: the restart adopts, no second UpdateTask", async () => {
    const w = world(); w.floor.enqueue(job("1")); w.ax.hangAfterCreate = true
    const l1 = start(w, dir)
    await until("task exists", () => w.ax.tasks.has("wf-test-1-a1"))
    await l1.crash()
    w.ax.hangAfterCreate = false
    const l2 = start(w, dir)
    await until("adopted", () => l2.has("adopted", "wf-test-1-a1"))
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, w.ax.updates.get("wf-test-1-a1"), w.ax.upsertsOnExisting]).toEqual(["success", 1, 0])
    await l2.drain()
  })

  it("F4 crash while running; the agent finishes while the link is down; the restart reports once", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    w.ax.finish("wf-test-1-a1", 0, { late: true })
    const l2 = start(w, dir)
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).output, J(w).attempt]).toEqual(["success", { late: true }, 1])
    expect(w.floor.calls.filter((c) => c.rpc === "Complete").length).toBe(1)
    await l2.drain()
  })

  it("F5 floor unreachable: the verdict waits in the outbox across a crash, the lease is orphaned not requeued, then lands", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    w.ax.finish("wf-test-1-a1", 0, { v: 1 })
    await until("outbox keeps", () => l1.has("outbox-keep", "wf-test-1-a1"))
    await l1.crash()
    await sleep(7 * SEC) // past the 6 s lease, well inside the 15 s grace
    const l2 = start(w, dir)
    await sleep(3 * SEC)
    w.floor.down = false
    w.floor.sweep() // the DO alarm fires
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 1])
    expect(J(w).history.some((h) => h.startsWith("requeue"))).toBe(false)
    await l2.drain()
  })

  it("F6 ax unreachable: capacity 0 on every poll, held leases still renewed, work resumes when ax returns", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.up = false
    await until("link saw ax down", () => l.has("ax-down"))
    const mark = w.floor.calls.length
    w.floor.enqueue(job("2"))
    await sleep(10 * SEC) // longer than the 6 s lease
    if (process.env.LINK_DEBUG) console.log(JSON.stringify({ history: J(w).history, calls: w.floor.calls.slice(mark).map((c) => [c.rpc, c.capacity, c.leaseIds]), logs: l.logs.slice(-15) }))
    const during = w.floor.calls.slice(mark).filter((c) => c.rpc === "Lease")
    expect(during.length).toBeGreaterThan(0)
    expect(during.every((c) => c.capacity === 0 && c.granted === 0)).toBe(true)
    expect([J(w).state, J(w, "2").state]).toEqual(["leased", "queued"])
    w.ax.up = true
    await until("second job created", () => w.ax.tasks.has("wf-test-2-a1"))
    await l.drain()
  })

  it("F7 lease expiry, link back inside the grace: the orphaned lease is re-adopted, same attempt, no second Task", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    await sleep(7 * SEC); w.floor.sweep()
    expect([J(w).state, w.floor.wip()]).toEqual(["orphaned", 1]) // L3: never reclaim a live slot
    const l2 = start(w, dir)
    await until("re-adopted", () => J(w).history.includes("re-adopted"))
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt, w.ax.updates.get("wf-test-1-a1")]).toEqual(["success", 1, 1])
    await l2.drain()
  })

  it("F8 journal lost: the holder's complete heartbeat omits the orphan, attempt 2 supersedes it, old Task deleted first", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    rmSync(dir, { recursive: true, force: true })
    await sleep(7 * SEC); w.floor.sweep()
    const l2 = start(w, dir, {}, "s:fresh-state")
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect(J(w).history).toContain("requeue:omitted")
    expect(w.ax.events.indexOf("delete:wf-test-1-a1")).toBeGreaterThanOrEqual(0)
    expect(w.ax.events.indexOf("delete:wf-test-1-a1")).toBeLessThan(w.ax.events.indexOf("update:wf-test-1-a2"))
    w.ax.tick(); w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 2])
    await l2.drain()
  })

  it("F9 link dead past the grace: the alarm requeues; the returning link drops attempt 1 (lost) and runs attempt 2", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    await l1.crash()
    await sleep(7 * SEC); w.floor.sweep()
    await sleep(16 * SEC); w.floor.sweep()
    expect(J(w).history).toContain("requeue:grace")
    const l2 = start(w, dir)
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect(w.ax.deletes).toContain("wf-test-1-a1")
    w.ax.tick(); w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 2])
    // the late verdict of attempt 1 can never be recorded: the floor fences on the attempt
    expect(w.floor.complete({ leaseId: "wf-test-1-a1", attempt: 1, result: "success" })).toEqual({ code: "stale-attempt" })
    await l2.drain()
  })

  it("F10 cancel: carried in the heartbeat reply, DeleteTask, then Complete(cancelled) once the Task is gone", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.cancel("wf-test-1")
    await until("floor done", () => J(w).state === "done")
    if (process.env.LINK_DEBUG) console.log(JSON.stringify({ history: J(w).history, events: w.ax.events, phase: w.ax.tasks.get("wf-test-1-a1")?.phase, logs: l.logs }))
    expect([J(w).result, J(w).attempt, w.ax.tasks.has("wf-test-1-a1")]).toEqual(["cancelled", 1, false])
    await l.drain()
  })

  it("F11 stock v0.3.0 (no P1), guest mode configured: the Task stays Running after exit; the guest completes with its lease token; the link deletes on lost", async () => {
    const w = guestWorld(); w.floor.enqueue(job("1"))
    const l = start(w, dir, GUEST)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const env = Object.fromEntries(w.ax.tasks.get("wf-test-1-a1")!.task.spec.env.map((e) => [e.name, e.value]))
    expect(env.AX_CONWIP_COMPLETE_URL).toBe("http://link.fleet.internal/guest")
    expect(Object.values(env).some((v) => v.includes("tok-nas"))).toBe(false) // the fleet bearer never enters the sandbox
    w.ax.finish("wf-test-1-a1", 0)
    await sleep(5 * SEC)
    expect(w.ax.tasks.get("wf-test-1-a1")!.phase).toBe("Running") // FIELD-MAP D3: no terminal phase without P1
    expect(w.floor.guestComplete("wf-test-1-a1", env.AX_CONWIP_LEASE_TOKEN!, "success", { guest: true })).toMatchObject({ duplicate: false })
    expect(w.floor.guestComplete("wf-test-1-a1", env.AX_CONWIP_LEASE_TOKEN!, "success", { guest: true })).toEqual({ refused: "token" })
    await until("link deleted the still-Running Task", () => !w.ax.tasks.has("wf-test-1-a1"))
    expect([J(w).result, J(w).output]).toEqual(["success", { guest: true }])
    await l.drain()
  })

  it("F12 stuck Running (no P1, the guest never reports): the floor's deadline cancels it and ax frees the worker", async () => {
    const w = guestWorld(); w.floor.enqueue(job("1", { "timeout-minutes": 1 })) // 60 s = 1200 ms here
    const l = start(w, dir, GUEST)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.finish("wf-test-1-a1", 0) // exited, invisible to ax without P1
    await until("floor done", () => J(w).state === "done", 8000)
    expect([J(w).result, J(w).output]).toEqual(["cancelled", { reason: "deadline" }])
    await until("Task gone", () => !w.ax.tasks.has("wf-test-1-a1"))
    await l.drain()
  })

  it("F13 deadline passes while the floor is unreachable: the local backstop deletes the Task and queues the verdict", async () => {
    // red team double-run-r1-1: a pin (rule 7b) long enough that the grant's reassignSeconds outlasts the deadline, so the
    // deadline backstop acts before the self-fence would (lease 6 + grace 15 + pin 300 s against timeout 60 + 15 s)
    const w = world({ tokens: { "tok-nas": { holder: "nas-link-1", guest: true } }, pinSeconds: 300 }); w.ax.p1 = false
    w.floor.enqueue(job("1", { "timeout-minutes": 1 }))
    const l = start(w, dir, GUEST)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.floor.down = true
    await until("backstop verdict", () => l.logs.some((x) => x.ev === "verdict" && x.reason === "deadline-exceeded"), 8000)
    await until("Task deleted", () => !w.ax.tasks.has("wf-test-1-a1") || w.ax.tasks.get("wf-test-1-a1")!.phase === "Terminating")
    await l.crash()
  })

  it("F14 stuck Pending: pre-start failure at the timeout, retried by the floor as attempt 2 superseding attempt 1", async () => {
    const w = world(); w.floor.enqueue(job("1")); w.ax.holdPending.add("wf-test-1-a1")
    const l = start(w, dir, { pendingTimeoutMs: 200 })
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"), 8000)
    expect(J(w).history).toContain("requeue:pre-start/pending-timeout")
    expect(w.ax.deletes).toContain("wf-test-1-a1")
    w.ax.tick(); w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 2])
    await l.drain()
  })

  it("F15 name conflict: a foreign Task with the lease's name is never overwritten (create-only, L4)", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    w.ax.put({ apiVersion: "ax.io/v1alpha1", kind: "Task", metadata: { name: "wf-test-1-a1", atespace: "fleet" }, spec: { image: "someone-else", command: ["sleep"], env: [] } })
    const l = start(w, dir)
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, (J(w).output as { reason: string }).reason]).toEqual(["failure", "pre-start/name-conflict"])
    expect([w.ax.updates.get("wf-test-1-a1"), w.ax.tasks.get("wf-test-1-a1")?.task.spec.image]).toEqual([undefined, "someone-else"])
    await l.drain()
  })

  it("F16 deterministic refusals are final and touch nothing in ax: env over budget, unresolved prompt, prompt too big to inline (B12)", async () => {
    const w = world({ cap: 3 })
    w.floor.enqueue(job("1", {}, {}, { schema: { description: "x".repeat(20000) } }))
    w.floor.enqueue(job("2", {}, { [A + "prompt-unresolved"]: "no agent() call carries label" }))
    w.floor.enqueue(job("3", {}, {}, { prompt: "p".repeat(17000) }))
    const l = start(w, dir, { maxInFlight: 3 })
    await until("all done", () => J(w).state === "done" && J(w, "2").state === "done" && J(w, "3").state === "done")
    expect([(J(w, "3").output as { reason: string }).reason, J(w, "3").attempt]).toEqual(["pre-start/prompt-file-route-missing", 1])
    expect([(J(w).output as { reason: string }).reason, J(w).attempt]).toEqual(["pre-start/env-over-budget", 1])
    expect([(J(w, "2").output as { reason: string }).reason, J(w, "2").attempt]).toEqual(["pre-start/prompt-unresolved", 1])
    expect(w.ax.updates.size).toBe(0)
    await l.drain()
  })

  it("F17 a second replica with the same identity is refused (409) and exits; the first keeps its session", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const dir2 = mkdtempSync(join(tmpdir(), "conwip-link-b-"))
    const l2 = start(w, dir2, {}, "s:second-replica")
    const exit = await l2.exit()
    rmSync(dir2, { recursive: true, force: true })
    expect(Exit.isFailure(exit)).toBe(true)
    expect(JSON.stringify(exit)).toContain("session-conflict")
    w.ax.finish("wf-test-1-a1", 0, { ok: 1 })
    await until("floor done", () => J(w).state === "done")
    await l1.drain()
  })

  it("F19 ax lost a Task it had created (Redis loss): infra/task-lost, the floor retries as attempt 2", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    w.ax.tasks.delete("wf-test-1-a1") // gone without a DeleteTask: the store forgot it
    await until("attempt 2 created", () => w.ax.tasks.has("wf-test-1-a2"))
    expect(J(w).history).toContain("requeue:infra/task-lost")
    w.ax.tick(); w.ax.finish("wf-test-1-a2", 0, { ok: 2 })
    await until("floor done", () => J(w).state === "done")
    expect([J(w).result, J(w).attempt]).toEqual(["success", 2])
    await l.drain()
  })

  it("F18 drain on SIGTERM: stop leasing, flush the outbox, leave running Tasks to be re-adopted", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, dir)
    await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const exit = await l.drain()
    expect(Exit.isSuccess(exit)).toBe(true)
    expect([w.ax.tasks.get("wf-test-1-a1")?.phase, J(w).state]).toEqual(["Running", "leased"])
  })
})
