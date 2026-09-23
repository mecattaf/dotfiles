// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-0/stale-lost.repro.ts (assertions kept; additions marked).
// Duplicate/stale delivery: a Heartbeat reply is applied to whatever record holds that leaseId when the reply lands,
// not to the generation the Heartbeat vouched for. Set-up is R2-5a (review-r2.test.ts): a1 fails retryable while a2
// gen 1 is leased to this link and waits for a1's verdict. One Heartbeat carrying [a2] (gen 1) reaches the floor
// after rule 4b withdrew a2 gen 1 and requeued a2 gen 2, so the floor answers lost:[a2]. Its reply lands after the
// link took the regrant of a2 (gen 2). The link then releases gen 2 as `lost` and never creates it, although the floor
// has gen 2 leased to it: the job is stranded until the lease expires, then released `omitted` (an infra release).
import { Effect } from "effect"
import { expect, it } from "vitest"
import { bodyOf, job, sleep, start, until, world } from "./review-r4-harness.ts"
import type { World } from "./review-r4-harness.ts"

const rpcOf = async (input: unknown, init?: RequestInit) => { const b = await bodyOf(input, init); return b.includes('"Complete"') ? "Complete" : b.includes('"Lease"') ? "Lease" : b.includes('"Heartbeat"') ? "Heartbeat" : "?" }
const failRetryable = (w: World, name: string) => {
  const t = w.ax.tasks.get(name)!
  t.exited = true; t.phase = "Failed"
  t.conditions = [{ type: "Ready", status: "False", reason: "ResourceExhausted", message: "ResourceExhausted: no free worker" }]
}

it("a Heartbeat reply computed for a2 gen 1 does not release a2 gen 2", async () => {
  const w = world(); w.floor.enqueue(job("1"))
  const J = () => w.floor.jobs.get("wf-test-1")!
  let holdLease = false, failHeartbeat = false, failComplete = false
  let armed = false, hbForwarded = false, hbIntercepted = false
  let l: ReturnType<typeof start>
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    const rpc = await rpcOf(input, init)
    if (rpc === "Heartbeat" && failHeartbeat) throw new TypeError("fetch failed")
    if (rpc === "Complete" && failComplete) return new Response("upstream timeout", { status: 503 })
    if (rpc === "Complete" && armed) await until("a Heartbeat vouching for a2 gen 1 is in flight", () => hbIntercepted, 4000)
    if (rpc === "Lease") { while (holdLease) await sleep(2); while (armed && !hbForwarded) await sleep(2) }
    if (rpc === "Heartbeat" && armed && !hbIntercepted && body.includes("wf-test-1-a2")) {
      hbIntercepted = true
      await until("floor withdrew a2 gen 1 and requeued a2 gen 2", () => J().history.includes("withdrawn:a2") && J().state === "queued", 4000)
      const res = await w.floor.fetch(input as any, { ...init, body })
      hbForwarded = true // Lease may go now: the floor regrants a2 (gen 2)
      await until("link took the regrant", () => l.has("regrant", "wf-test-1-a2"), 4000).catch(() => {})
      return res // the reply (lost:[a2]) lands after the regrant
    }
    return w.floor.fetch(input as any, { ...init, body })
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
  armed = true
  failComplete = false; failHeartbeat = false
  await until("a2 created, or 1 s", () => w.ax.updates.has("wf-test-1-a2"), 1000).catch(() => {})
  await sleep(300)
  const trace = l.logs.filter((x) => x.leaseId === "wf-test-1-a2" || x.task === "wf-test-1-a2").map((x) => `${x.ev}${x.why ? ":" + x.why : ""}`)
  const out = { hbIntercepted, floor: J().history, state: J().state, attempt: J().attempt, infraSpent: J().infraSpent, a2Updates: w.ax.updates.get("wf-test-1-a2") ?? 0, a2trace: trace }
  console.log(JSON.stringify(out))
  await l.drain(); w.floor.close()
  expect(hbIntercepted).toBe(true)
  expect(out.a2Updates).toBe(1)
  expect(out.floor).not.toContain("requeue:omitted") // round 4 addition
  expect(out.a2trace).toContain("stale-heartbeat-reply")
})
