// Buildkite-family critique pass (2026-09-24), G-BK4 on the link: a drain leases nothing more, lets the Tasks it
// holds finish and deliver their verdicts, and then ends by itself; a drain past its timeout ends anyway.
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, describe, expect, it } from "vitest"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"

const SEC = 20
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1`
const job = (n: string): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: {
    name: `wf-test-${n}`,
    labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe" }
  },
  spec: {
    "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" }
  }
})

function start(floor: FakeFloor, ax: FakeAx, dir: string, drainTimeoutMs?: number) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const drain = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const f = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: "s1", fetch: (i, init) => floor.fetch(i, init) })
    return yield* runLink(cfg, { ax, floor: f, journal: Journal.open(dir), log: (ev, fl) => logs.push({ ev, ...fl }), stop, drain, ...(drainTimeoutMs !== undefined ? { drainTimeoutMs } : {}) })
  })))
  let ended = false
  void Effect.runPromise(Fiber.await(fiber)).then(() => { ended = true })
  return {
    logs, ended: () => ended,
    drain: () => Effect.runSync(Deferred.succeed(drain, undefined)),
    stop: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Effect.runPromise(Fiber.await(fiber)) }
  }
}
const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

describe("G-BK4 link drain", () => {
  const dirs: Array<string> = []
  const mk = () => { const d = mkdtempSync(join(tmpdir(), "bk-drain-")); dirs.push(d); return d }
  afterEach(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); dirs.length = 0 })

  it("leases nothing after the drain, delivers the held Task's verdict, then ends by itself", async () => {
    const floor = new FakeFloor({ cap: 4, leaseSeconds: 60, graceSeconds: 60, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" } })
    const ax = new FakeAx()
    floor.enqueue(job("1"))
    const l = start(floor, ax, mk())
    await until("a1 created", () => ax.tasks.has("wf-test-1-a1"))
    ax.tick()
    l.drain()
    floor.enqueue(job("2"))
    await sleep(6 * SEC)
    expect(ax.tasks.has("wf-test-2-a1")).toBe(false) // a draining link takes no new work
    expect(l.ended()).toBe(false) // it still holds a live Task
    ax.finish("wf-test-1-a1", 0, { text: "done" })
    await until("the link ends by itself", () => l.ended(), 8000)
    expect(l.logs.some((x) => x.ev === "drain-complete")).toBe(true)
    expect(floor.jobs.get("wf-test-1")!.state).toBe("done")
    expect(floor.jobs.get("wf-test-2")!.state).toBe("queued")
  }, 20000)

  it("a drain past its timeout ends with the Task still held (re-adopted by the next start)", async () => {
    const floor = new FakeFloor({ cap: 4, leaseSeconds: 60, graceSeconds: 60, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" } })
    const ax = new FakeAx()
    floor.enqueue(job("3"))
    const l = start(floor, ax, mk(), 200)
    await until("a1 created", () => ax.tasks.has("wf-test-3-a1"))
    ax.tick()
    l.drain()
    await until("the link ends at the drain timeout", () => l.ended(), 8000)
    expect(l.logs.some((x) => x.ev === "drain-timeout")).toBe(true)
    expect(ax.live("wf-test-3-a1")).toBe(true) // never deleted: a restart re-adopts it
  }, 20000)
})
