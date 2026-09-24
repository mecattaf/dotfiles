// Buildkite-family critique pass (2026-09-24), puller side: self-fence (G-BK2, audit probe P2 inverted), graceful
// drain (G-BK4), nextPollSeconds with jitter (G-BK4), the loopback health endpoint (G-BK7) and signal_reason (G-BK1).
import { createHash } from "node:crypto"
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { FloorError } from "@substrate/link/floor.ts"
import { Puller } from "../src/puller.ts"
import type { FloorPort, RunTask } from "../src/puller.ts"
import { prometheusOf, serveHealth } from "../src/health.ts"

const script = "export const meta = {}"
const sha = createHash("sha256").update(script).digest("hex")
const grantOf = (id: string, o: { lease?: number; reassign?: number } = {}) => ({
  leaseId: `run-${id}-a1`, attempt: 1,
  lease: { holderIdentity: "coord", leaseDurationSeconds: o.lease ?? 1, acquireTime: Date.now(), renewTime: Date.now(), leaseTransitions: 0 },
  ...(o.reassign !== undefined ? { reassignSeconds: o.reassign } : {}),
  job: { apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
    metadata: { name: `run-${id}`, labels: {}, annotations: { "ultracode.mecattaf.dev/run-id-raw": id, "ultracode.mecattaf.dev/journal-key": "k" } },
    spec: { "runs-on": ["seat:interp", "runtime:interpreter"], with: { prompt_ref: { sha256: sha }, model: "m" } } }
})
const stats = { seq: 1, cap: 1, wip: 1, queued: 0, done: 0 }
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))
const stateDir = () => mkdtempSync(join(tmpdir(), "bk-pull-"))

type Fake = { floor: FloorPort; beats: number; leases: number; completes: Array<{ leaseId: string; result: string; output: unknown }> }
const fakeFloor = (grants: Array<ReturnType<typeof grantOf>>, o: { beat?: (ids: ReadonlyArray<string>) => Promise<{ renewed: string[]; lost: string[]; cancelRequested: string[] }>; nextPollSeconds?: number } = {}): Fake => {
  const f: Fake = { beats: 0, leases: 0, completes: [], floor: undefined as never }
  let given = false
  f.floor = {
    lease: async () => { f.leases++; const g = given ? [] : grants; given = true; return { grants: g, stats, ...(o.nextPollSeconds !== undefined ? { nextPollSeconds: o.nextPollSeconds } : {}), heartbeatSeconds: 1 } as never },
    heartbeat: async (p) => { f.beats++; return o.beat ? o.beat(p.leaseIds) : { renewed: [...p.leaseIds], lost: [], cancelRequested: [] } },
    complete: async (p) => { f.completes.push({ leaseId: p.leaseId, result: p.result, output: p.output }); return { duplicate: false } }
  }
  return f
}
const hanging = (seen: { aborted?: unknown }) => (t: RunTask) => new Promise<never>((_, no) => t.signal.addEventListener("abort", () => { seen.aborted = t.signal.reason; no(new Error("aborted")) }))

describe("G-BK2 puller self-fence (audit probe P2 inverted)", () => {
  it("a run whose heartbeats all fail is aborted as lost before reassignSeconds, with no verdict", async () => {
    const f = fakeFloor([grantOf("fence1", { lease: 1, reassign: 2 })], { beat: async () => { throw new Error("network down (partition)") } })
    const seen: { aborted?: unknown } = {}
    const events: string[] = []
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 50, heartbeatMs: 200 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: hanging(seen) as never, log: (ev) => events.push(ev) })
    const done = p.run().catch(() => undefined)
    const t0 = Date.now()
    while (!events.includes("lease-expired") && Date.now() - t0 < 5_000) await wait(50)
    const fencedAfter = Date.now() - t0
    await wait(100)
    expect(events).toContain("lease-expired")
    expect(fencedAfter).toBeLessThan(2_000) // reassignSeconds 2, lease 1: fence at 1.5 s after the grant
    expect(seen.aborted).toBe("lost")
    expect(p.active.size).toBe(0)
    expect(f.completes).toEqual([]) // lost: no verdict, the journal is kept for attempt n+1
    expect(p.status().counters["self_fences"]).toBe(1)
    p.stop(); await done
  }, 15_000)

  it("renewing heartbeats keep the run alive past the bound", async () => {
    const f = fakeFloor([grantOf("fence2", { lease: 1, reassign: 1 })])
    const seen: { aborted?: unknown } = {}
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 50, heartbeatMs: 100 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: hanging(seen) as never })
    const done = p.run().catch(() => undefined)
    await wait(1_500)
    expect(p.active.size).toBe(1)
    expect(seen.aborted).toBeUndefined()
    p.stop(); await done
    expect(seen.aborted).toBe("stop")
  }, 10_000)

  it("a 409 session conflict fences every run as lost before the puller exits", async () => {
    const f = fakeFloor([grantOf("fence3", { lease: 30, reassign: 300 })], { beat: async () => { throw new FloorError("session-conflict", "another session") } })
    const seen: { aborted?: unknown } = {}
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 50, heartbeatMs: 150 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: hanging(seen) as never })
    await expect(p.run()).rejects.toMatchObject({ kind: "session-conflict" })
    expect(seen.aborted).toBe("lost")
    expect(f.completes).toEqual([])
  }, 10_000)
})

describe("G-BK4 graceful drain and server poll", () => {
  it("drain: no new leases, the in-flight run finishes and its verdict is sent, then run() resolves", async () => {
    const f = fakeFloor([grantOf("drain1", { lease: 30, reassign: 300 })])
    let finish!: () => void
    const exec = (t: RunTask) => new Promise<{ result: "success"; output: unknown }>((ok, no) => { finish = () => ok({ result: "success", output: { v: 1 } }); t.signal.addEventListener("abort", () => no(new Error("aborted"))) })
    const p = new Puller({ holder: "coord", maxRuns: 2, stateDir: stateDir(), pollMs: 30, heartbeatMs: 100 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: exec as never })
    const done = p.run()
    while (p.active.size === 0) await wait(20)
    p.drain(10_000)
    const leasesAtDrain = f.leases
    await wait(200)
    expect(f.leases).toBe(leasesAtDrain) // a draining puller leases nothing
    expect(p.status().state).toBe("draining")
    finish()
    await done
    expect(f.completes).toEqual([{ leaseId: "run-drain1-a1", result: "success", output: { v: 1 } }])
  }, 10_000)

  it("drain past its timeout aborts the run as stop (no verdict), then run() resolves", async () => {
    const f = fakeFloor([grantOf("drain2", { lease: 30, reassign: 300 })])
    const seen: { aborted?: unknown } = {}
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 30, heartbeatMs: 100 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: hanging(seen) as never })
    const done = p.run()
    while (p.active.size === 0) await wait(20)
    const t0 = Date.now()
    p.drain(300)
    await done
    expect(Date.now() - t0).toBeGreaterThanOrEqual(250)
    expect(seen.aborted).toBe("stop")
    expect(f.completes).toEqual([])
  }, 10_000)

  it("serverPoll honours nextPollSeconds (a paused holder polls slowly) within the bounds", async () => {
    const f = fakeFloor([], { nextPollSeconds: 2 })
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 20, heartbeatMs: 100, serverPoll: true, maxPollMs: 400 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: (async () => ({ result: "success", output: null })) as never })
    const done = p.run()
    await wait(1_000)
    p.stop(); await done
    expect(p.status().pollMs).toBe(400) // 2 s asked, capped at maxPollMs
    expect(f.leases).toBeLessThanOrEqual(4) // not the 50 a 20 ms poll would make
    const g = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 20, heartbeatMs: 100 },
      { floor: fakeFloor([], { nextPollSeconds: 2 }).floor, client: {} as never, execute: (async () => ({ result: "success", output: null })) as never })
    const gd = g.run(); await wait(200); g.stop(); await gd
    expect(g.status().pollMs).toBe(20) // off by default: the old fixed poll
  }, 10_000)
})

describe("G-BK1 signal_reason and G-BK7 health", () => {
  it("a cancelled run's verdict names signal_reason cancel", async () => {
    let n = 0
    const f = fakeFloor([grantOf("cancel1", { lease: 30, reassign: 300 })], { beat: async (ids) => ({ renewed: [...ids], lost: [], cancelRequested: n++ > 0 ? [...ids] : [] }) })
    const exec = (t: RunTask) => new Promise((ok) => t.signal.addEventListener("abort", () => ok({ result: "cancelled", output: { reason: "aborted" } })))
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 30, heartbeatMs: 80 },
      { floor: f.floor, client: { runScript: async () => script } as never, execute: exec as never })
    const done = p.run()
    while (f.completes.length === 0) await wait(20)
    p.stop(); await done
    expect(f.completes[0]).toMatchObject({ result: "cancelled", output: { reason: "aborted", signal_reason: "cancel" } })
  }, 10_000)

  it("the loopback health endpoint serves status.json and Prometheus text; a public address is refused", async () => {
    const status = { holder: "coord", state: "running" as const, held: 1, active: [{ leaseId: "run-x-a1", attempt: 1, runningMs: 5, fenceInMs: 100 }], outbox: 0,
      lastHeartbeatOkMs: 1, heartbeatFailures: 0, pollMs: 5000, counters: { grants: 3, self_fences: 1 } }
    const h = await serveHealth("127.0.0.1:0", { status: () => status })
    try {
      const js = await (await fetch(`http://${h.addr}/status.json`)).json()
      expect(js).toMatchObject({ holder: "coord", held: 1, counters: { grants: 3 } })
      const text = await (await fetch(`http://${h.addr}/metrics`)).text()
      expect(text).toContain('substrate_puller_events_total{holder="coord",event="self_fences"} 1')
      expect(text).toBe(prometheusOf(status))
    } finally { h.close() }
    await expect(serveHealth("0.0.0.0:9", { status: () => status })).rejects.toThrow(/loopback/)
  })
})

describe("G-BK3 live log shipping", () => {
  const { appendFileSync, writeFileSync: wf } = require("node:fs") as typeof import("node:fs")
  it("ships whole lines in order, resumes after a transient failure without a gap or a copy, and stops on 409", async () => {
    const { LogShipper } = await import("../src/logship.ts")
    const dir = stateDir()
    const got: Array<{ seq: number; data: string }> = []
    let fail = 0, gone = false
    const append = async (_n: string, c: { seq: number; data: string }) => {
      if (gone) throw Object.assign(new Error("lease-not-live"), { status: 409, code: "lease-not-live" })
      if (fail > 0) { fail--; throw Object.assign(new Error("502"), { status: 502 }) }
      got.push({ seq: c.seq, data: c.data })
    }
    const s = new LogShipper({ append, name: "run-x", leaseId: "run-x-a1", attempt: 1, dir, maxChunkBytes: 16 })
    wf(join(dir, "events.jsonl"), "one\ntwo\npart")
    await s.tick()
    expect(got.map((g) => g.data).join("")).toBe("one\ntwo\n") // the partial line waits
    fail = 1
    appendFileSync(join(dir, "events.jsonl"), "ial\nthree\n")
    await s.tick() // fails transiently
    await s.tick()
    expect(got.map((g) => g.data).join("")).toBe("one\ntwo\npartial\nthree\n")
    expect(got.map((g) => g.seq)).toEqual(got.map((_, i) => i))
    // a restart of the same attempt continues from the persisted cursor
    const again = new LogShipper({ append, name: "run-x", leaseId: "run-x-a1", attempt: 1, dir, maxChunkBytes: 16 })
    expect(again.shipped.offset).toBe(Buffer.byteLength("one\ntwo\npartial\nthree\n"))
    gone = true
    appendFileSync(join(dir, "events.jsonl"), "four\n")
    await again.tick()
    expect(again.stoppedWhy).toBe("lease-not-live")
  })

  it("the puller streams the run's events.jsonl while it runs and flushes the tail before the verdict", async () => {
    const f = fakeFloor([grantOf("log1", { lease: 30, reassign: 300 })])
    const chunks: string[] = []
    let verdictAt = -1
    const floor = { ...f.floor, complete: async (p: any) => { verdictAt = chunks.length; return f.floor.complete(p) } }
    const exec = async (t: RunTask) => {
      wf(join(t.dir, "events.jsonl"), `{"ev":"call-start","i":1}\n`)
      await wait(250)
      appendFileSync(join(t.dir, "events.jsonl"), `{"ev":"call-end","i":1}\n`)
      return { result: "success" as const, output: null }
    }
    const p = new Puller({ holder: "coord", maxRuns: 1, stateDir: stateDir(), pollMs: 30, heartbeatMs: 100, logIntervalMs: 50 },
      { floor, client: { runScript: async () => script } as never, execute: exec as never, appendLog: async (name, c) => { expect([name, c.leaseId, c.attempt]).toEqual(["run-log1", "run-log1-a1", 1]); chunks.push(c.data) } })
    const done = p.run()
    while (f.completes.length === 0) await wait(20)
    p.stop(); await done
    expect(chunks.length).toBeGreaterThanOrEqual(2) // the first line went out while the run was still running
    expect(chunks.join("")).toBe(`{"ev":"call-start","i":1}\n{"ev":"call-end","i":1}\n`)
    expect(verdictAt).toBe(chunks.length) // every chunk before the verdict
  }, 10_000)
})
