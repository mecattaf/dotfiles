// Red team verify, double-run-r1-1 (2026-09-24). Scratch clone only. Runs the REAL link (runLink) twice, as two
// Place in apps/link/test/ of a substrate clone (imports ./fake-ax.ts, ./fake-floor.ts, ./review-r4-harness.ts). Verified failing at substrate 0ba7550.
// holders serving the same runs-on labels, each with its own executor (FakeAx), against the in-process floor double.
// link-a leases attempt 1, then loses the floor (partition) while its executor keeps running the Task. The floor
// orphans, releases by grace, requeues attempt 2 with supersedes [a1] and grants it to link-b, whose fence finds a1
// absent on its own executor and creates a2. Asserts invariant I2 (at most one attempt executing); FAILS while the
// defect exists. Fixed 2026-09-24 (link.ts selfFence): it passes, and link-a logs lease-expired for a1.
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { expect, it } from "vitest"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import { job, SEC, sleep, until } from "./review-r4-harness.ts"

const labels = ["seat:halogen", "runtime:gvisor"]
function startLink(holder: string, token: string, ax: FakeAx, fetch: typeof globalThis.fetch, dir = mkdtempSync(join(tmpdir(), `rt-dbl-${holder}-`))) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder, maxInFlight: 2, servedLabels: labels,
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token, sessionId: `s:${dir}`, fetch })
    return yield* runLink(cfg, { ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ t: Date.now(), ev, ...f }), stop, floorUrl: "http://floor.test" })
  })))
  return { dir, logs, has: (ev: string, id?: string) => logs.some((l) => l.ev === ev && (id === undefined || l.leaseId === id)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)]) } }
}

it("double-run-r1-1: a partitioned holder's attempt 1 keeps running on its executor while attempt 2 runs on the other holder's", async () => {
  // lease 6 s, grace 15 s, heartbeat 2 s at SEC=20 ms per second
  const floor = new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC,
    tokens: { "tok-a": { holder: "link-a", labels }, "tok-b": { holder: "link-b", labels } } })
  const axA = new FakeAx(), axB = new FakeAx()
  let partitionA = false
  const fetchA: typeof globalThis.fetch = async (i, init) => { if (partitionA) throw new TypeError("fetch failed"); return floor.fetch(i, init) }
  floor.enqueue(job("dbl"))
  const A = startLink("link-a", "tok-a", axA, fetchA)
  await until("a1 created on link-a's executor", () => axA.live("wf-test-dbl-a1"), 3000)
  axA.tick() // Pending -> Running
  partitionA = true // link-a loses the floor; its ax keeps the Task running (the agent has not finished)
  const B = startLink("link-b", "tok-b", axB, floor.fetch)
  const J = floor.jobs.get("wf-test-dbl")!
  let overlapSeen = false, overlapMs = 0
  const t0 = Date.now()
  while (Date.now() - t0 < 2500) {
    const both = axA.live("wf-test-dbl-a1") && axB.live("wf-test-dbl-a2")
    if (both) { overlapSeen = true; overlapMs += 5 }
    await sleep(5)
  }
  const snapshot = { floorHistory: [...J.history], floorState: J.state, floorAttempt: J.attempt, floorHolder: J.holder,
    a1LiveOnA: axA.live("wf-test-dbl-a1"), a2LiveOnB: axB.live("wf-test-dbl-a2"), aDeletes: [...axA.deletes],
    aHbErrors: A.logs.filter((l) => l.ev === "heartbeat-error").length, bLeased: B.logs.filter((l) => l.ev === "leased").map((l) => [l.leaseId, l.supersedes]) }
  console.log("R1-1 real-link snapshot", JSON.stringify(snapshot), "overlapMs~", overlapMs)
  // heal the partition: link-a's next Heartbeat is answered lost and it deletes a1 (the only fence)
  partitionA = false
  // after the fix link-a fenced a1 itself (lease-expired) before the floor released it; before, `lost` was the only fence
  await until("link-a fenced a1", () => A.has("lost", "wf-test-dbl-a1") || A.has("lease-expired", "wf-test-dbl-a1"), 3000).catch(() => {})
  console.log("after heal: a lost logged", A.has("lost", "wf-test-dbl-a1"), "a deletes", axA.deletes)
  await A.drain(); await B.drain(); floor.close()
  expect(A.has("lease-expired", "wf-test-dbl-a1")).toBe(true)
  expect({ overlapSeen, a1LiveWhileA2Live: snapshot.a1LiveOnA && snapshot.a2LiveOnB }).toEqual({ overlapSeen: false, a1LiveWhileA2Live: false })
}, 20000)

it("double-run-r1-1 (fix): a link that was DOWN past reassignSeconds fences its Task at restart, before any floor call answers", async () => {
  const floor = new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC,
    tokens: { "tok-a": { holder: "link-a", labels } } })
  const axA = new FakeAx()
  let partitionA = false
  const fetchA: typeof globalThis.fetch = async (i, init) => { if (partitionA) throw new TypeError("fetch failed"); return floor.fetch(i, init) }
  floor.enqueue(job("down"))
  const A = startLink("link-a", "tok-a", axA, fetchA)
  await until("a1 created", () => axA.live("wf-test-down-a1"), 3000)
  axA.tick()
  await sleep(10 * SEC) // a few renewals, journaled
  await A.drain() // the unit stops; its ax Task keeps running (F18)
  partitionA = true // and the floor is unreachable when it comes back
  await sleep(40 * SEC) // past reassignSeconds (6 + 15 + 15 s) since the last renewal
  expect(axA.live("wf-test-down-a1")).toBe(true)
  const A2 = startLink("link-a", "tok-a", axA, fetchA, A.dir)
  await until("fenced at restart", () => A2.has("lease-expired", "wf-test-down-a1"), 3000)
  expect(axA.deletes).toContain("wf-test-down-a1")
  await A2.drain(); floor.close()
}, 20000)
