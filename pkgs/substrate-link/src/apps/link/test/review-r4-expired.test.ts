// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-1/expired.repro.ts (assertions kept; additions marked).
// Round 4, lens fail-closed and capacity gate: a grant that waits at the slot gate (B11: gate closed, e.g. the Gateway
// check failing) is created whenever the gate reopens, with no check that its lease is still live. The floor, which
// the link could not reach (heartbeats failing), has already expired it, requeued it, and may grant attempt 2.
// Buildkite's pattern the design adopts (row 8, "reserve with expiry, finish -1 before start") would refuse it.
import { expect, it } from "vitest"
import { bodyOf, job, sleep, start, until, world } from "./review-r4-harness.ts"

it("a grant whose lease expired while it waited at the gate is still created", async () => {
  const w = world({ leaseSeconds: 6, graceSeconds: 15 }) // at secondMs 20: lease 120 ms, grace 300 ms
  w.floor.enqueue(job("1"))
  const gw = w.ax.gateways.get("halogen")!
  let holdOnce = true
  let l: ReturnType<typeof start>
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const b = await bodyOf(input, init)
    const res = await w.floor.fetch(input, init)
    if (holdOnce && b.includes('"Lease"')) {
      const txt = await res.clone().text()
      if (txt.includes("wf-test-1-a1")) {
        holdOnce = false
        // the Gateway is edited away while the reply is in flight; the next resync closes the gate (B10)
        w.ax.gateways.delete("halogen")
        await until("gateway-missing", () => l.has("gateway-missing"), 3000)
      }
    }
    return res
  }
  l = start(w, undefined, { maxInFlight: 1 }, fetch)
  await until("waiting-for-slot", () => l.has("waiting-for-slot", "wf-test-1-a1"), 3000)
  // the NAS loses its route to Cloudflare; ax stays reachable
  w.floor.down = true
  const J = w.floor.jobs.get("wf-test-1")!
  await until("floor requeued a1 after lease + grace", () => J.state === "queued" && J.attempt === 2, 3000)
  const floorStateAtReopen = { state: J.state, attempt: J.attempt, history: [...J.history] }
  w.ax.gateways.set("halogen", gw) // the Gateway is back; the floor is still unreachable
  await until("a1 created", () => (w.ax.updates.get("wf-test-1-a1") ?? 0) > 0, 3000).catch(() => {})
  const createdA1WhileExpired = (w.ax.updates.get("wf-test-1-a1") ?? 0) > 0
  await sleep(200)
  const a1BeforeFloorReturned = w.ax.updates.get("wf-test-1-a1") ?? 0 // round 4 addition
  w.floor.down = false
  await until("a2 created", () => w.ax.tasks.has("wf-test-1-a2"), 3000).catch(() => {})
  await sleep(300)
  const out = {
    floorStateAtReopen, createdA1WhileExpired, axEvents: w.ax.events,
    linkTrace: l!.logs.filter((x) => typeof x.leaseId === "string" || typeof x.task === "string").map((x) => `${x.ev}:${x.leaseId ?? x.task}${x.why ? ":" + x.why : ""}`),
    heartbeatErrors: l!.logs.filter((x) => x.ev === "heartbeat-error").length, floorHistory: J.history
  }
  console.log(JSON.stringify(out))
  await l!.drain(); w.floor.close()
  expect(createdA1WhileExpired).toBe(false) // fail closed: a lease known to be past renewTime + duration is not started
  expect(a1BeforeFloorReturned).toBe(0) // round 4 addition: nothing of a1 before the floor returns
  expect([...w.ax.updates.keys()]).toEqual(["wf-test-1-a2"]) // exactly one created attempt, a2, afterwards
  expect(l!.has("lease-unconfirmed", "wf-test-1-a1")).toBe(true)
})

// Round 4 addition (finding 5, deadline half): a grant whose deadline has passed is refused with no create. The gate
// closes while the grant is in flight and the Heartbeats fail, so the floor cannot cancel at its deadline (the lease is
// orphaned, grace is long); only the link's own check can end it.
it("R4-5b: a grant past its deadline is failed deadline-exceeded before any UpdateTask", async () => {
  const w = world({ graceSeconds: 400 })
  w.floor.enqueue(job("d", { "timeout-minutes": 1 })) // 60 s x 20 ms = 1.2 s deadline
  const gw = w.ax.gateways.get("halogen")!
  let hbDown = false
  let l: ReturnType<typeof start>
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const b = await bodyOf(input, init)
    if (hbDown && b.includes('"Heartbeat"')) throw new TypeError("fetch failed")
    const res = await w.floor.fetch(input, init)
    if (!hbDown && b.includes('"Lease"') && (await res.clone().text()).includes("wf-test-d-a1")) {
      hbDown = true
      w.ax.gateways.delete("halogen")
      await until("gateway-missing", () => l.has("gateway-missing"), 3000)
    }
    return res
  }
  l = start(w, undefined, { maxInFlight: 1 }, fetch)
  await until("waiting", () => l.has("waiting-for-slot", "wf-test-d-a1") || l.has("lease-unconfirmed", "wf-test-d-a1"), 3000)
  await sleep(1400)
  w.ax.gateways.set("halogen", gw)
  await until("verdict", () => l.has("verdict", "wf-test-d-a1"), 3000)
  const v = l.logs.find((x) => x.ev === "verdict" && x.leaseId === "wf-test-d-a1")!
  await l.drain(); w.floor.close()
  expect(v.reason).toBe("deadline-exceeded")
  expect(w.ax.updates.get("wf-test-d-a1") ?? 0).toBe(0)
})
