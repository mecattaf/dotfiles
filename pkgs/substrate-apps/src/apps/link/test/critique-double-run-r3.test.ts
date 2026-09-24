// Critique pass 2026-09-24, red team double-run-r3-1: promoted from the audit probe audit-dr-r3.test.ts and inverted. Two links (two holders, two executors) serve the same labels, the topology round 1's r1-1 names.
// Unlike r1-1 there is no partition: link A is in contact with the floor throughout and itself tells the floor that
// attempt 1 never started (a pre-start/* verdict), while attempt 1's Task exists in A's ax.
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, describe, expect, it } from "vitest"
import { AxError } from "../src/ax.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import { job, sleep, SEC, until } from "./review-r4-harness.ts"

const UNAVAILABLE = 14, DEADLINE_EXCEEDED = 4

/** ax whose UpdateTask fails without landing on the first tries and, on the last try, lands and then answers
 *  DEADLINE_EXCEEDED (the write committed, the reply was lost). After that the API is down (`up = false`) for a while:
 *  the realistic reason a create's reply is lost is an ax-server that is going away. The controller keeps running. */
class LandsOnLastTry extends FakeAx {
  creates = 0
  constructor(readonly lastTry: number) {
    super()
    const base = this.createTask // the parent's field, wrapped
    this.createTask = (task): ReturnType<FakeAx["createTask"]> => {
      this.creates++
      if (this.creates < this.lastTry) return Effect.fail(new AxError(UNAVAILABLE, "connection reset"))
      if (this.creates === this.lastTry) {
        this.tasks.set(task.metadata.name, { task, phase: "Running", conditions: [] })
        this.events.push(`update:${task.metadata.name}`)
        this.up = false
        return Effect.fail(new AxError(DEADLINE_EXCEEDED, "deadline exceeded"))
      }
      return base(task)
    }
  }
}
/** ax whose DeleteTask fails (UNAVAILABLE) until `deleteOk`; everything else answers. */
class DeleteFails extends FakeAx {
  deleteOk = false
  deleteTries = 0
  override deleteTask = (name: string) => {
    this.deleteTries++
    if (!this.deleteOk) return Effect.fail(new AxError(UNAVAILABLE, "delete: connection reset"))
    const t = this.tasks.get(name)
    if (t) { t.phase = "Terminating"; this.deletes.push(name); this.events.push(`delete:${name}`) }
    return Effect.void
  }
}

const running: Array<{ drain: () => Promise<unknown> }> = []
afterEach(async () => { for (const l of running.splice(0)) await l.drain() })

function startLink(floor: FakeFloor, ax: FakeAx, token: string, holder: string, over: Partial<LinkConfig> = {}) {
  const dir = mkdtempSync(join(tmpdir(), `r3-dbl-${holder}-`))
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder, maxInFlight: 1, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3, ...over
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const f = yield* rpcFloor({ url: "http://floor.test", token, sessionId: `s:${dir}`, fetch: floor.fetch })
    return yield* runLink(cfg, { ax, floor: f, journal: Journal.open(dir), log: (ev, x) => logs.push({ t: Date.now(), ev, ...x }), stop, floorUrl: "http://floor.test" })
  })))
  const l = {
    logs,
    has: (ev: string, leaseId?: string) => logs.some((x) => x.ev === ev && (leaseId === undefined || x.leaseId === leaseId)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)]) }
  }
  running.push(l)
  return l
}

describe("double-run r3-1 (fixed): no retryable pre-start verdict for a Task that may exist", () => {
  it("R3-1 create lands on the last try: A waits (create-unconfirmed), B never gets an attempt, A adopts a1 once ax answers", async () => {
    const floor = new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC,
      tokens: { "tok-a": "nas-link-a", "tok-b": "nas-link-b" } })
    const axA = new LandsOnLastTry(3), axB = new FakeAx()
    floor.enqueue(job("1"))
    const a = startLink(floor, axA, "tok-a", "nas-link-a")
    await until("A cannot confirm its create", () => a.has("create-unconfirmed", "wf-test-1-a1"), 8000)
    expect(axA.live("wf-test-1-a1")).toBe(true)
    const b = startLink(floor, axB, "tok-b", "nas-link-b")
    await sleep(40 * SEC)
    expect(floor.jobs.get("wf-test-1")!.history.some((h) => h.startsWith("requeue:pre-start"))).toBe(false)
    expect([...axB.tasks.keys()].some((n) => n.startsWith("wf-test-1-a"))).toBe(false)
    expect(b.has("leased")).toBe(false)
    axA.up = true
    await until("A adopts a1 once ax answers", () => a.has("adopted", "wf-test-1-a1"), 5000)
    expect(axA.deletes).not.toContain("wf-test-1-a1")
    floor.close()
  }, 30_000)

  it("R3-1b pending timeout with a DeleteTask that did not land: no verdict until the delete lands; B never runs a2 beside a1", async () => {
    const floor = new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC,
      tokens: { "tok-a": "nas-link-a", "tok-b": "nas-link-b" } })
    const axA = new DeleteFails(), axB = new FakeAx()
    axA.holdPending.add("wf-test-1-a1")
    floor.enqueue(job("1"))
    const a = startLink(floor, axA, "tok-a", "nas-link-a", { pendingTimeoutMs: 200 })
    await until("A defers its pre-start verdict", () => a.has("pre-start-deferred", "wf-test-1-a1"), 8000)
    expect(floor.jobs.get("wf-test-1")!.history.includes("requeue:pre-start/pending-timeout")).toBe(false)
    axA.holdPending.delete("wf-test-1-a1"); axA.tick() // a1 starts after all
    const b = startLink(floor, axB, "tok-b", "nas-link-b")
    await sleep(20 * SEC)
    expect(axB.live("wf-test-1-a2")).toBe(false)
    // the delete lands: a1 goes, and only then is the retryable verdict sent
    axA.deleteOk = true
    await until("the floor hears pre-start/pending-timeout after a1 is gone", () => floor.jobs.get("wf-test-1")!.history.includes("requeue:pre-start/pending-timeout"), 8000)
    expect(axA.live("wf-test-1-a1")).toBe(false)
    floor.close()
  }, 30_000)
})
