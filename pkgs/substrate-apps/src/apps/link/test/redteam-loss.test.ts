// Red team loss-and-wip r3-3 (critique pass KEEP-4): a floor-wide HTTP 500 is not charged to each verdict.
// Both cases failed on 2882545: the Task success ended failure infra/verdict-undeliverable.
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

describe("KEEP-4 (r3-3): a floor-wide 500 is not charged to each verdict", () => {
  let dir: string
  const worlds: Array<World> = []
  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "rl-link-")) })
  afterEach(() => { rmSync(dir, { recursive: true, force: true }) })
  const scenario = async (over: Partial<LinkConfig>, bursts: number) => {
    const w = world({ cap: 4 }); worlds.push(w); w.floor.enqueue(job("1"))
    let outage = false, served500 = 0
    const fetch: typeof globalThis.fetch = async (input, init) => {
      if (outage) { await bodyOf(input, init); served500++; return new Response(JSON.stringify({ error: "LinkTokensInvalid" }) + "\n", { status: 500 }) }
      return w.floor.fetch(input, init)
    }
    const l = start(w, dir, over, fetch)
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    outage = true // every /rpc answers 500 before any RPC runs, as index.ts did for LinkTokensInvalid
    w.ax.finish("wf-test-1-a1", 0, { answer: 42 })
    await until("verdict written", () => l.has("verdict", "wf-test-1-a1"))
    await until("the outage served many 500s", () => served500 >= bursts, 8000)
    outage = false
    await until("job 1 closed", () => J(w).state === "done", 8000)
    const out = { result: J(w).result, reason: (J(w).output as any)?.reason, served500, replaced: l.has("verdict-replaced", "wf-test-1-a1") }
    await l.drain()
    return out
  }
  it("A: a short outage (verdictAttempts 4, backoff [20,60] ms)", async () => {
    expect(await scenario({ outboxBackoffMs: [20, 60], verdictAttempts: 4 }, 16)).toMatchObject({ result: "success", replaced: false })
  }, 20_000)
  it("B: default verdictAttempts (8), an outage longer than grace", async () => {
    expect(await scenario({ outboxBackoffMs: [20, 60] }, 32)).toMatchObject({ result: "success", replaced: false })
  }, 20_000)
})
