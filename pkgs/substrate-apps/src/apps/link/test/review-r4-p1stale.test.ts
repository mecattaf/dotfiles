// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-1/p1stale.repro.ts (assertions kept; additions marked).
// Round 4, lens capacity gate: canCreate() needs "P1 proven", but the probe runs only on an ax-up transition
// (link.ts resync: `if (wasDown) serverP1 = undefined`). ax-server is a replicas:1 Deployment with the default
// RollingUpdate strategy (upstream deploy/ax-server.yaml), so a rollout to a server without P1 happens with no failed
// ListTasks, and the link keeps creating Tasks it can never read a verdict from.
import { Effect } from "effect"
import { expect, it } from "vitest"
import { job, sleep, start, until, world } from "./review-r4-harness.ts"

it("A: ax rolled to stock v0.3.0 (server and controller) with no ListTasks failure", async () => {
  const w = world()
  w.floor.enqueue(job("1"))
  const l = start(w)
  await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
  const probesBefore = l.logs.filter((x) => x.ev === "completion-probe").length
  w.ax.p1 = false // the rollout: GetTaskResult is now UNIMPLEMENTED and no terminal phase is ever written
  await until("p1-missing logged", () => l.has("p1-missing"), 1000) // round 4 fix: the probe runs on every resync
  const leasesAtFlip = w.floor.calls.filter((c) => c.rpc === "Lease").length
  await sleep(100) // several resyncs (30 ms) and Lease polls pass; none fails
  w.floor.enqueue(job("2"))
  await sleep(1500) // round 4: job 2 is never created on the stock server (the repro waited for its create here)
  const J2 = w.floor.jobs.get("wf-test-2")!
  const out = {
    probesBefore, probesAfter: l.logs.filter((x) => x.ev === "completion-probe").length,
    p1MissingLogged: l.has("p1-missing"),
    job2: { state: J2.state, attempt: J2.attempt, history: J2.history },
    task2Phase: w.ax.tasks.get("wf-test-2-a1")?.phase, task2Exited: (w.ax.tasks.get("wf-test-2-a1") as any)?.exited,
    verdictJob2: l.has("verdict", "wf-test-2-a1"),
    leaseCapacitiesAfterRollout: [...new Set(w.floor.calls.filter((c) => c.rpc === "Lease").slice(-10).map((c) => c.capacity))]
  }
  console.log("A", JSON.stringify(out))
  const leasesAfter = w.floor.calls.filter((c) => c.rpc === "Lease").slice(leasesAtFlip + 1) // round 4 addition
  await l.drain(); w.floor.close()
  // Fail-closed expectation: after the P1 route disappears the link leases and creates nothing new.
  expect(w.ax.updates.get("wf-test-2-a1") ?? 0).toBe(0)
  expect(out.p1MissingLogged).toBe(true)
  expect(leasesAfter.length).toBeGreaterThan(0)
  expect(leasesAfter.every((c) => c.capacity === 0)).toBe(true)
  expect(J2.state).toBe("queued")
})

it("B: ax-server rolled to stock, the P1 controller still writes Completed", async () => {
  const w = world()
  w.floor.enqueue(job("1"))
  const l = start(w)
  await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
  let stockServer = false
  const orig = w.ax.getTaskResult
  ;(w.ax as any).getTaskResult = (n: string) => stockServer ? Effect.succeed("unimplemented" as const) : orig(n)
  stockServer = true
  w.ax.finish("wf-test-1-a1", 0, { answer: 1 }) // Completed, result stored by the controller, unreadable via ax-server
  for (let i = 0; i < 40; i++) { // every attempt the floor grants finishes with a success the link cannot read
    for (const [name, t] of w.ax.tasks) if (t.phase === "Running" && !t.exited) w.ax.finish(name, 0, { answer: name })
    await sleep(50)
  }
  const J = w.floor.jobs.get("wf-test-1")!
  const out = {
    probes: l.logs.filter((x) => x.ev === "completion-probe").length, p1MissingLogged: l.has("p1-missing"),
    creates: [...w.ax.updates.keys()], job1: { state: J.state, result: (J as any).result, output: (J as any).output, history: J.history },
    verdicts: l.logs.filter((x) => x.ev === "verdict").map((x) => `${x.leaseId}:${x.result}:${x.reason ?? ""}`)
  }
  console.log("B", JSON.stringify(out))
  // Round 4 addition: the Task is kept, uncharged, and read once P1 is back: the success is reported, not thrown away
  stockServer = false
  await until("job 1 done", () => J.state === "done", 3000)
  const leasesUnimpl = w.floor.calls.filter((c) => c.rpc === "Lease")
  await l.drain(); w.floor.close()
  expect(out.creates.length).toBe(1) // fail closed: nothing created once the server answered UNIMPLEMENTED
  expect(out.p1MissingLogged).toBe(true)
  expect(out.verdicts.some((v) => v.includes("result-unreadable"))).toBe(false)
  expect((J as any).result).toBe("success")
  expect((J as any).output).toEqual({ answer: 1 })
  expect(leasesUnimpl.length).toBeGreaterThan(0)
})
