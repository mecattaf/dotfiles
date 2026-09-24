// Critique pass 2026-09-24, red team durability-r2-8: a floor-wide 500 outage never turns a success into the final
// infra/verdict-undeliverable. Promoted from the audit probe audit-d-r2b-outage.test.ts and inverted; the harness is
// the review-r2 one.
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { cidrIsOpen, gatewayAllowsAll } from "../src/ax.ts"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { isFleetInternalUrl, runLink } from "../src/link.ts"
import type { LinkConfig } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"

const SEC = 20
const A = "ultracode.mecattaf.dev/"
const JK = `${"cd".repeat(32)}:1` // round 4: FIELD-MAP 5a journal key (jobs.ts refuses a grant without it)
const job = (n: string): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: { name: `wf-test-${n}`, labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: JK, [A + "phase-title"]: "Probe" } },
  spec: { "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" } }
})
const world = (o: Partial<FloorConfig> = {}) => ({
  floor: new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" }, ...o }),
  ax: new FakeAx()
})
type World = ReturnType<typeof world>
function start(w: World, dir: string, over: Partial<LinkConfig> = {}, fetch?: typeof globalThis.fetch) {
  const logs: Array<Record<string, unknown>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = {
    holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 1500, deleteAfterMs: 0, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, fenceTimeoutMs: 300, resultReadTries: 3, ...over
  }
  const fiber = Effect.runFork(Effect.scoped(Effect.gen(function*() {
    const floor = yield* rpcFloor({ url: "http://floor.test", token: "tok-nas", sessionId: `s:${dir}`, fetch: fetch ?? w.floor.fetch })
    return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ t: Date.now(), ev, ...f }), stop, floorUrl: "http://floor.test" })
  })))
  return {
    logs, fiber,
    has: (ev: string, leaseId?: string) => logs.some((l) => l.ev === ev && (leaseId === undefined || l.leaseId === leaseId)),
    trace: () => logs.filter((x) => typeof x.leaseId === "string" || typeof x.task === "string").map((x) => `${x.ev}:${x.leaseId ?? x.task}${x.why ? ":" + x.why : ""}`),
    crash: () => Effect.runPromise(Fiber.interrupt(fiber)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)]) }
  }
}
const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const J = (w: World, n = "1") => w.floor.jobs.get(`wf-test-${n}`)!
const bodyOf = async (input: unknown, init?: RequestInit) => {
  const b = init?.body
  if (typeof b === "string") return b
  if (b instanceof Uint8Array) return new TextDecoder().decode(b)
  if (b) return await new Response(b as ConstructorParameters<typeof Response>[0]).text()
  return (input instanceof Request) ? await input.clone().text() : ""
}
const rpcOf = async (input: unknown, init?: RequestInit) => { const b = await bodyOf(input, init); return b.includes('"Complete"') ? "Complete" : b.includes('"Lease"') ? "Lease" : b.includes('"Heartbeat"') ? "Heartbeat" : "?" }
/** A capacity race: Failed with ResourceExhausted, which the link maps to retryable pre-start/resource-exhausted. */
const failRetryable = (w: World, name: string) => {
  const t = w.ax.tasks.get(name)!
  t.exited = true; t.phase = "Failed"
  t.conditions = [{ type: "Ready", status: "False", reason: "ResourceExhausted", message: "ResourceExhausted: no free worker" }]
}
const why = (w: World, l: ReturnType<typeof start>) => JSON.stringify({ floor: J(w).history, link: l.trace() })

// A floor stub for the fail-closed tests (scratch-r2-1/repro.mts): hands out its grants once, renews everything.
const stats = { seq: 1, cap: 2, wip: 0, queued: 0, done: 0 }
const grantOf = (n: string, extra: Record<string, unknown> = {}) => ({ leaseId: `wf-test-${n}-a1`, attempt: 1, job: job(n),
  lease: { holderIdentity: "nas-link-1", leaseDurationSeconds: 30, acquireTime: Date.now(), renewTime: Date.now(), leaseTransitions: 0 }, ...extra })
const stubFloor = (grants: Array<any>, gate: () => boolean = () => true) => {
  let sent = false
  return {
    lease: (p: any) => Effect.sync(() => { const g = !sent && p.capacity > 0 && gate() ? grants : []; if (g.length) sent = true; return { grants: g, invalid: [], stats, nextPollSeconds: 1, heartbeatSeconds: 2 } }),
    heartbeat: (p: any) => Effect.succeed({ renewed: [...p.leaseIds], lost: [], cancelRequested: [], stats }),
    complete: (_p: any) => Effect.succeed({ duplicate: false, stats })
  }
}
const runStub = async (over: Partial<LinkConfig>, ax: FakeAx, floor: any, ms: number) => {
  const dir = mkdtempSync(join(tmpdir(), "conwip-link-r2s-"))
  const logs: Array<Record<string, any>> = []
  const stop = Effect.runSync(Deferred.make<void>())
  const cfg: LinkConfig = { holder: "nas-link-1", maxInFlight: 2, servedLabels: ["seat:halogen", "runtime:gvisor"],
    shape: { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"] },
    completion: "auto", secondMs: SEC, resyncMs: 30, pendingTimeoutMs: 60_000, deleteAfterMs: 60_000, deadlineBackstopMs: 300,
    createAttempts: 3, outboxBackoffMs: [20, 100], initialPollSeconds: 1, initialHeartbeatSeconds: 2, ...over }
  const f = Effect.runFork(runLink(cfg, { ax, floor, journal: Journal.open(dir), log: (ev, x) => logs.push({ t: Date.now(), ev, ...x }), stop }))
  await sleep(ms)
  Effect.runSync(Deferred.succeed(stop, undefined)); await Effect.runPromise(Fiber.await(f)); rmSync(dir, { recursive: true, force: true })
  return logs
}

describe("durability-r2-8 (fixed): a floor-wide 500 outage", () => {
  let dir: string
  let worlds: Array<World> = []
  const W = (o: Partial<FloorConfig> = {}) => { const w = world(o); worlds.push(w); return w }
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "rt-r2b-")) })
  afterEach(() => { for (const w of worlds) w.floor.close(); worlds = []; rmSync(dir, { recursive: true, force: true }) })

  it("every RPC answers 500 for a while: the success verdict waits it out and is delivered with its output", async () => {
    const w = W({ cap: 4 }); w.floor.enqueue(job("1"))
    let outage = false, refusedComplete = 0, refusedOther = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (outage) {
        const r = await rpcOf(input, init)
        if (r === "Complete") refusedComplete++; else refusedOther++
        return new Response("error code: 1101", { status: 500 })
      }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, { outboxBackoffMs: [20, 60], verdictAttempts: 4 }, fetch)
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    outage = true
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    await until("Complete refused well past verdictAttempts", () => refusedComplete >= 12, 8000)
    expect(l.has("verdict-replaced", "wf-test-1-a1")).toBe(false)
    expect(refusedOther).toBeGreaterThan(0) // Lease and Heartbeat were refused too: the outage was floor-wide
    outage = false
    await until("job 1 closed", () => J(w).state === "done", 4000)
    expect(J(w).result).toBe("success")
    expect(JSON.stringify(J(w).output)).toContain("42")
    await l.drain()
  })

  it("a verdict the floor alone refuses while Lease and Heartbeat succeed is still replaced at its ceiling", async () => {
    const w = W({ cap: 4 }); w.floor.enqueue(job("1"))
    let refuse = false
    const fetch: typeof globalThis.fetch = async (input, init) =>
      refuse && (await rpcOf(input, init)) === "Complete" ? new Response("SQLITE_TOOBIG", { status: 500 }) : w.floor.fetch(input, init)
    const l = start(w, dir, { outboxBackoffMs: [20, 60], verdictAttempts: 3 }, fetch)
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    refuse = true
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("replaced", () => l.has("verdict-replaced", "wf-test-1-a1"), 8000)
    refuse = false
    await until("job 1 closed", () => J(w).state === "done", 4000)
    expect([J(w).result, (J(w).output as any)?.reason]).toEqual(["failure", "infra/verdict-undeliverable"])
    await l.drain()
  })
})
