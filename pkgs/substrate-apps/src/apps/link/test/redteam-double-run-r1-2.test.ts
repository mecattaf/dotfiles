// Red team verify, double-run-r1-2 (2026-09-24). Scratch clone only, never merged as is.
// Two replicas of ONE link identity (same token, same holder), each with its OWN executor (its own FakeAx) and its
// own state directory (so its own session id). The asserted property is the one the finding says is missing: a link
// told 409 (another session holds its identity) fences the Tasks it created before it exits 75. It FAILS today.
// Place in apps/link/test/ and run from apps/link: vitest run test/double-run-r1-2.test.ts (no workerd needed).
// Corollary (rule 4b withdraws an n+1 the other replica created) is reproduced by the engine test R1-2 in
// redteam/scratch/double-run-r1/substrate/apps/floor/test/redteam-double-run.test.ts (its lines 104-105 pass; line 107 fails).
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Exit, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
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

function start(floor: FakeFloor, ax: FakeAx, dir: string, session: string, net: { down: boolean }) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2
  }
  const fetch: typeof globalThis.fetch = (i, init) => net.down ? Promise.reject(new TypeError("fetch failed: partitioned")) : floor.fetch(i, init)
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const f = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: session, fetch })
    return yield* runLink(cfg, { ax, floor: f, journal: Journal.open(dir), log: (ev, fl) => logs.push({ ev, ...fl }), stop })
  })))
  return {
    logs,
    exit: () => Effect.runPromise(Fiber.await(fiber)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Effect.runPromise(Fiber.await(fiber)) }
  }
}
const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

describe("double-run-r1-2 verify: a superseded session cannot hear `lost` and exits without fencing", () => {
  const dirs: Array<string> = []
  const mk = () => { const d = mkdtempSync(join(tmpdir(), "r1-2-")); dirs.push(d); return d }
  beforeEach(() => { dirs.length = 0 })
  afterEach(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }) })

  it("replica s1 comes back to a 409 while its attempt 1 still runs beside s2's attempt 2", async () => {
    const floor = new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" } })
    const ax1 = new FakeAx(), ax2 = new FakeAx()
    const net1 = { down: false }, net2 = { down: false }
    floor.enqueue(job("1"))
    const l1 = start(floor, ax1, mk(), "s1", net1)
    await until("a1 created on ax1", () => ax1.tasks.has("wf-test-1-a1"))
    ax1.tick()
    expect(ax1.live("wf-test-1-a1")).toBe(true)
    // s1 is cut off from the floor (partition, stall); its executor keeps running a1.
    net1.down = true
    await sleep(9 * SEC) // past the session (3 heartbeats = 6 s) and past the lease (6 s)
    // s2: a second replica of the same identity with a fresh state directory and its own executor.
    const l2 = start(floor, ax2, mk(), "s2", net2)
    await until("a2 created on ax2", () => ax2.tasks.has("wf-test-1-a2"))
    ax2.tick()
    // s1 comes back. Every call it makes is answered 409 before the engine runs.
    net1.down = false
    const exit1 = await Promise.race([l1.exit(), sleep(4000).then(() => "still-running" as const)])
    const s1Refused = exit1 !== "still-running" && Exit.isFailure(exit1) && JSON.stringify(exit1).includes("session-conflict")
    const observed = {
      s1Refused409: s1Refused,
      a1LiveOnS1Executor: ax1.live("wf-test-1-a1"),
      a2LiveOnS2Executor: ax2.live("wf-test-1-a2"),
      s1DeletesIssued: ax1.deletes.slice()
    }
    console.log("R1-2 observed", JSON.stringify(observed))
    await l2.drain()
    expect(s1Refused).toBe(true)
    expect(observed.a2LiveOnS2Executor).toBe(true)
    // The property: a link that loses its identity must fence what it created before it exits.
    expect(observed.a1LiveOnS1Executor, "attempt 1 still runs on s1's executor after s1 exited on 409 while attempt 2 runs on s2's").toBe(false)
  }, 20000)
})
