// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-0/restart-replay.repro.ts (assertions kept; additions marked).
// Kill -9 mid-Lease (B8): the floor applied the Lease and granted a1, the link journaled the requestKey but died
// before the reply was journaled. The restart takes longer than the lease (orphaned) and less than lease + grace.
// B8 says the journaled key is replayed so the grant is recovered. At startup the link sends its first Heartbeat
// (held set without a1) BEFORE it replays the key, so the floor releases the omitted orphan (rule 7 / L3 a), and the
// replay then returns nothing: one infra release is spent and the job reruns as a2.
import { readFileSync } from "node:fs"
import { Effect, Fiber } from "effect"
import { expect, it } from "vitest"
import { job, SEC, sleep, start, until, world, bodyOf } from "./review-r4-harness.ts"

it("a journaled requestKey whose grant outlived the lease is recovered on restart", async () => {
  const w = world()
  w.floor.enqueue(job("r1"))
  // link #1: the first capacity>0 Lease reaches the floor, then the process "dies" before the reply lands
  let leased = false
  const dying: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (/"Lease"/.test(body) && /"capacity":[1-9]/.test(body)) {
      await w.floor.fetch(input as any, { ...init, body })
      leased = true
      return new Promise<Response>(() => {}) // the reply never reaches the journal
    }
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l1 = start(w, undefined, {}, dying)
  await until("floor granted a1", () => leased)
  Effect.runFork(Fiber.interrupt(l1.fiber)) // kill -9: nothing after this point runs in link #1
  await sleep(50)
  const journal1 = readFileSync(l1.dir + "/journal.jsonl", "utf8")
  const keyJournaled = /"ev":"lease-key"/.test(journal1) && !/"ev":"lease-replied"/.test(journal1)
  // downtime: past the lease (6 s * SEC = 120 ms) and well inside lease + grace (21 s * SEC = 420 ms)
  await sleep(8 * SEC)
  const stateAtRestart = w.floor.jobs.get("wf-test-r1")!.state
  const l2 = start(w, l1.dir)
  await until("a Task exists", () => w.ax.tasks.size > 0, 3000).catch(() => {})
  await sleep(200)
  const j = w.floor.jobs.get("wf-test-r1")!
  const out = { keyJournaled, stateAtRestart, history: j.history, infraSpent: j.infraSpent, tasks: [...w.ax.tasks.keys()],
    l2: l2.logs.filter((l) => ["leased", "duplicate-grant", "created", "resume"].includes(String(l.ev))).map((l) => `${l.ev}:${l.leaseId}`) }
  console.log(JSON.stringify(out))
  await l2.drain()
  w.floor.close()
  expect(keyJournaled).toBe(true)
  expect(stateAtRestart).toBe("orphaned")
  expect(j.history).not.toContain("requeue:omitted") // the grant under the journaled key was released by the first heartbeat
  expect(out.tasks).toContain("wf-test-r1-a1")
  expect(j.infraSpent).toBe(0) // round 4 addition
  expect(out.tasks).not.toContain("wf-test-r1-a2")
})

it("control: the same kill with a restart shorter than the lease recovers a1", async () => {
  const w = world()
  w.floor.enqueue(job("r2"))
  let leased = false
  const dying: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (/"Lease"/.test(body) && /"capacity":[1-9]/.test(body)) { await w.floor.fetch(input as any, { ...init, body }); leased = true; return new Promise<Response>(() => {}) }
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l1 = start(w, undefined, {}, dying)
  await until("floor granted a1", () => leased)
  Effect.runFork(Fiber.interrupt(l1.fiber))
  await sleep(2 * SEC)
  const l2 = start(w, l1.dir)
  await until("a Task exists", () => w.ax.tasks.size > 0, 3000).catch(() => {})
  const j = w.floor.jobs.get("wf-test-r2")!
  console.log(JSON.stringify({ control: true, history: j.history, tasks: [...w.ax.tasks.keys()] }))
  await l2.drain(); w.floor.close()
  expect([...w.ax.tasks.keys()]).toContain("wf-test-r2-a1")
})

it("running process: the reply is lost and Lease stays unanswered past the lease while Heartbeat works", async () => {
  const w = world()
  w.floor.enqueue(job("r3"))
  let first = true, blockUntil = 0
  const f: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (/"Lease"/.test(body)) {
      if (first && /"capacity":[1-9]/.test(body)) { first = false; await w.floor.fetch(input as any, { ...init, body }); blockUntil = Date.now() + 10 * SEC; throw new TypeError("fetch failed") }
      if (Date.now() < blockUntil) throw new TypeError("fetch failed")
    }
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l = start(w, undefined, {}, f)
  await until("a Task exists", () => w.ax.tasks.size > 0, 4000).catch(() => {})
  await sleep(100)
  const j = w.floor.jobs.get("wf-test-r3")!
  console.log(JSON.stringify({ running: true, history: j.history, infraSpent: j.infraSpent, tasks: [...w.ax.tasks.keys()] }))
  await l.drain(); w.floor.close()
  expect(j.history).not.toContain("requeue:omitted")
  expect([...w.ax.tasks.keys()]).toEqual(["wf-test-r3-a1"]) // round 4 addition
})

// Round 4 addition: the running-process half needs the floor's rule 6b. Against an L1-only floor (vouchByKey false)
// the residual is still there; this pins that the link-side fix alone does not claim it.
it("control: an L1-only floor that ignores pendingRequestKey still releases the omitted orphan", async () => {
  const w = world()
  w.floor.vouchByKey = false
  w.floor.enqueue(job("r4"))
  let first = true, blockUntil = 0
  const f: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (/"Lease"/.test(body)) {
      if (first && /"capacity":[1-9]/.test(body)) { first = false; await w.floor.fetch(input as any, { ...init, body }); blockUntil = Date.now() + 10 * SEC; throw new TypeError("fetch failed") }
      if (Date.now() < blockUntil) throw new TypeError("fetch failed")
    }
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l = start(w, undefined, {}, f)
  await until("a Task exists", () => w.ax.tasks.size > 0, 4000).catch(() => {})
  const j = w.floor.jobs.get("wf-test-r4")!
  await l.drain(); w.floor.close()
  expect(j.history).toContain("requeue:omitted")
})

// Round 4 addition: the startup half does not depend on the floor. Against an L1-only floor (no rule 6b) the journaled
// key is still answered before the first Heartbeat, so the orphan granted under it is listed and re-adopted.
it("restart past the lease against an L1-only floor: the startup replay recovers a1", async () => {
  const w = world()
  w.floor.vouchByKey = false
  w.floor.enqueue(job("r5"))
  let leased = false
  const dying: typeof globalThis.fetch = async (input, init) => {
    const body = await bodyOf(input, init)
    if (/"Lease"/.test(body) && /"capacity":[1-9]/.test(body)) { await w.floor.fetch(input as any, { ...init, body }); leased = true; return new Promise<Response>(() => {}) }
    return w.floor.fetch(input as any, { ...init, body })
  }
  const l1 = start(w, undefined, {}, dying)
  await until("floor granted a1", () => leased)
  Effect.runFork(Fiber.interrupt(l1.fiber))
  await sleep(8 * SEC)
  const stateAtRestart = w.floor.jobs.get("wf-test-r5")!.state
  const l2 = start(w, l1.dir)
  await until("a Task exists", () => w.ax.tasks.size > 0, 3000).catch(() => {})
  await sleep(100)
  const j = w.floor.jobs.get("wf-test-r5")!
  await l2.drain(); w.floor.close()
  expect(stateAtRestart).toBe("orphaned")
  expect(l2.has("lease-key-replayed")).toBe(true)
  expect(j.history).not.toContain("requeue:omitted")
  expect([...w.ax.tasks.keys()]).toEqual(["wf-test-r5-a1"])
})
