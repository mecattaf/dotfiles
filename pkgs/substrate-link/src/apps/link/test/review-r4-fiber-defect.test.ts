// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-2/fiber-defect.repro.ts (assertions kept; additions marked).
// Effect idiom: dispatch ends in `Effect.catchCause(... log("job-fiber-died"))`, so a defect in one job fiber is logged
// and swallowed while the process lives on. Here one journal write fails once (ENOSPC, then the disk recovers). The
// grant stays in `held()`, every Heartbeat renews it on the floor, nothing re-dispatches it, and nothing reports it:
// the job never runs and never ends, and it holds a floor WIP slot and a local slot until the process restarts.
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { expect, it } from "vitest"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { job, sleep, until, world, SEC } from "./review-r4-harness.ts"

it("one failed journal write in a dispatch fiber strands the lease for the life of the process", async () => {
  const w = world({ cap: 1 })
  w.floor.enqueue(job("1"))
  w.floor.enqueue(job("2"))
  const dir = mkdtempSync(join(tmpdir(), "r4-2-defect-"))
  const j = Journal.open(dir)
  const orig = j.append.bind(j)
  let failed = 0
  ;(j as any).append = (e: any, t?: number) => {
    if (e.ev === "creating" && failed === 0) { failed++; throw Object.assign(new Error("ENOSPC: no space left on device, write"), { code: "ENOSPC" }) }
    return orig(e, t)
  }
  const logs: Array<any> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 1, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: "s:defect", fetch: w.floor.fetch })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: j, log: (ev, f) => logs.push({ ev, ...f }), stop, floorUrl: "http://floor.test" })
  })))
  try {
    await until("fiber died", () => logs.some((x) => x.ev === "job-fiber-died"))
    await sleep(3000) // 25 lease durations (6 s x 20 ms); the disk is fine again
    const J1 = w.floor.jobs.get("wf-test-1")!, J2 = w.floor.jobs.get("wf-test-2")!
    const out = {
      linkAlive: fiber.pollUnsafe() === undefined, failedWrites: failed,
      job1: { state: J1.state, attempt: J1.attempt, history: J1.history, task: w.ax.tasks.get("wf-test-1-a1")?.phase ?? "absent" },
      job2: { state: J2.state, history: J2.history },
      held: j.held(), heartbeats: w.floor.calls.filter((c) => c.rpc === "Heartbeat").length,
      completes: w.floor.calls.filter((c) => c.rpc === "Complete").length,
      events: logs.map((x) => x.ev).filter((e, i, a) => a.indexOf(e) === i)
    }
    console.log(JSON.stringify(out))
    // Expected: the lease is failed back (retryable) or the process crashes and systemd restarts it; either frees job 1.
    expect(J1.state === "done" || J1.attempt > 1 || w.ax.tasks.has("wf-test-1-a1") || !out.linkAlive).toBe(true)
  } finally {
    Effect.runSync(Deferred.succeed(stop, undefined))
    await Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)])
    w.floor.close()
  }
})

// Round 4 addition (finding 7): when even the fail-back cannot be journaled, the process dies (exit 1 under systemd)
// instead of renewing a lease nothing will ever run.
it("R4-7b: a dispatch defect whose fail-back also fails ends the link", async () => {
  const w = world({ cap: 1 })
  w.floor.enqueue(job("1"))
  const dir = mkdtempSync(join(tmpdir(), "r4-fix-defect-"))
  const j = Journal.open(dir)
  const orig = j.append.bind(j)
  ;(j as any).append = (e: any, t?: number) => {
    if (e.ev === "creating" || e.ev === "report") throw Object.assign(new Error("ENOSPC: no space left on device, write"), { code: "ENOSPC" })
    return orig(e, t)
  }
  const logs: Array<any> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 1, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: "s:defect2", fetch: w.floor.fetch })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: j, log: (ev, f) => logs.push({ ev, ...f }), stop, floorUrl: "http://floor.test" })
  })))
  try {
    const exit = await Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(3000).then(() => undefined)])
    expect(exit).toBeDefined()
    expect(exit!._tag).toBe("Failure")
    expect(logs.some((x) => x.ev === "link-defect-fatal")).toBe(true)
  } finally {
    Effect.runSync(Deferred.succeed(stop, undefined))
    w.floor.close()
  }
})
