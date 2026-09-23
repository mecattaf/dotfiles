// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-0/overtake.repro.ts (assertions kept; additions marked).
// Reply ordering: the regrant of a2 (gen 2) overtakes the Complete reply that withdrew a2 (gen 1). Set-up is R2-5a
// (review-r2.test.ts): a1 fails retryable while a2 gen 1 is leased to this link and waits for a1's verdict. a1's first
// Complete answers 500 once (server-error), which by design stops gating Lease (round 2), so a Lease with capacity 1 is
// in flight while the retried Complete is applied. The floor withdraws gen 1, requeues gen 2 and grants it on that
// Lease; the Lease reply lands before the Complete reply. The link still holds gen 1 unreleased, so gen 2 is dropped as
// `duplicate-grant`; the Complete reply then releases gen 1. Nothing of a2 is ever created, although the floor has
// gen 2 leased to this link: the job waits for lease expiry and is released `omitted` (an infra release).
import { expect, it } from "vitest"
import { bodyOf, job, sleep, start, until, world } from "./review-r4-harness.ts"
import type { World } from "./review-r4-harness.ts"

const rpcOf = async (input: unknown, init?: RequestInit) => { const b = await bodyOf(input, init); return b.includes('"Complete"') ? "Complete" : b.includes('"Lease"') ? "Lease" : b.includes('"Heartbeat"') ? "Heartbeat" : "?" }
const failRetryable = (w: World, name: string) => {
  const t = w.ax.tasks.get(name)!
  t.exited = true; t.phase = "Failed"
  t.conditions = [{ type: "Ready", status: "False", reason: "ResourceExhausted", message: "ResourceExhausted: no free worker" }]
}

// Round 4 addition: also against a floor that omits withdrewTransitions (the link then uses the generation of a2 it
// held when it SENT a1's verdict, not the regrant it holds when the reply lands).
for (const sendWithdrewGen of [true, false])
it(`the regrant of a2 is created even when its Lease reply lands before the Complete reply that withdrew gen 1 (withdrewTransitions ${sendWithdrewGen ? "sent" : "omitted"})`, async () => {
  const w = world({ sendWithdrewGen }); w.floor.enqueue(job("1"))
  const J = () => w.floor.jobs.get("wf-test-1")!
  let holdLease = false, failHeartbeat = false, failComplete = false, fiveHundredOnce = false
  let l: ReturnType<typeof start>
  let armed = false, leaseHeld = false
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    const rpc = await rpcOf(input, init)
    if (rpc === "Heartbeat" && (failHeartbeat || armed)) throw new TypeError("fetch failed") // no Heartbeat in the window
    if (rpc === "Complete" && failComplete) return new Response("upstream timeout", { status: 503 })
    if (rpc === "Complete" && fiveHundredOnce) { fiveHundredOnce = false; armed = true; return new Response("internal error", { status: 500 }) }
    if (rpc === "Lease") while (holdLease) await sleep(2)
    if (rpc === "Lease" && armed && /"capacity":[1-9]/.test(body) && !leaseHeld) {
      leaseHeld = true // a Lease sent before the retried Complete, delivered after it (network reordering)
      await until("the retried Complete was applied", () => J().history.includes("withdrawn:a2"), 3000).catch(() => {})
      // Round 4 addition: longer than the dispatch wait period (at most 2 x SEC), so the gen-1 dispatch is inside, or
      // waiting on, the outbox lock when the Complete reply lands, and reaches its withdrawn branch deterministically
      await sleep(80)
    }
    const res = await w.floor.fetch(input as any, { ...init, body })
    if (rpc === "Complete" && armed) {
      await until("the Lease reply reached the link", () => l.has("duplicate-grant", "wf-test-1-a2") || l.has("regrant", "wf-test-1-a2"), 1500).catch(() => {})
      armed = false
    }
    return res
  }
  l = start(w, undefined, {}, fetch)
  await until("running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
  w.floor.down = true
  await until("floor requeued attempt 2", () => J().state === "queued" && J().attempt === 2, 4000)
  failHeartbeat = true; holdLease = true; failComplete = true
  w.floor.down = false
  await sleep(80)
  failRetryable(w, "wf-test-1-a1")
  await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
  holdLease = false
  await until("a2 received", () => l.has("leased", "wf-test-1-a2"), 4000)
  await until("dispatch waits for the verdict", () => l.has("supersede-waits-for-verdict", "wf-test-1-a2"))
  fiveHundredOnce = true
  failComplete = false; failHeartbeat = false
  await until("a2 created, or 1.5 s", () => w.ax.updates.has("wf-test-1-a2"), 1500).catch(() => {})
  await sleep(300)
  const trace = l.logs.filter((x) => x.leaseId === "wf-test-1-a2" || x.task === "wf-test-1-a2" || x.ev === "complete" || x.ev === "outbox-keep" || x.ev === "lease-gated-by-outbox").map((x) => `${x.ev}:${x.leaseId ?? x.task}${x.why ? ":" + x.why : ""}${x.withdrew ? ":withdrew=" + x.withdrew : ""}`)
  const out = { leaseHeld, floor: J().history, state: J().state, attempt: J().attempt, infraSpent: J().infraSpent, a2Updates: w.ax.updates.get("wf-test-1-a2") ?? 0, trace }
  console.log(JSON.stringify(out))
  if (out.a2Updates !== 1 || out.floor.includes("requeue:omitted")) console.log("FULL", JSON.stringify(l.logs.map((x) => ({ ...x, cause: undefined }))), JSON.stringify(w.floor.calls.slice(-40)))
  await l.drain(); w.floor.close()
  expect(out.a2Updates).toBe(1)
  expect(out.floor).not.toContain("requeue:omitted") // round 4 addition: no infra release spent on the stall
  expect(out.leaseHeld).toBe(true)
  // Round 4 addition: the gen-1 dispatch never releases the regrant (the withdrawn branch is bound to its own grant)
  const a2 = l.logs.filter((x) => x.leaseId === "wf-test-1-a2").map((x) => String(x.ev))
  expect(a2.slice(a2.indexOf("regrant"))).not.toContain("withdrawn")
  expect(w.ax.deletes).not.toContain("wf-test-1-a2")
})
