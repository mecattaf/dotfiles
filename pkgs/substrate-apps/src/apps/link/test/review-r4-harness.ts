// Round 4 fix pass: the reviewers' scratch harness (scratch-r4-0/1/2, identical but for the temp prefix), moved into
// the worktree. The only change: the job carries the FIELD-MAP 5a journal-key annotation jobs.ts now requires.
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Deferred, Effect, Fiber } from "effect"
import type { AgentJob } from "../src/contract.ts"
import { rpcFloor } from "../src/floor.ts"
import { Journal } from "../src/journal.ts"
import { runLink } from "../src/link.ts"
import type { LinkConfig, LinkDeps } from "../src/link.ts"
import { FakeAx } from "./fake-ax.ts"
import { FakeFloor } from "./fake-floor.ts"
import type { FloorConfig } from "./fake-floor.ts"
export const SEC = 20
const A = "ultracode.mecattaf.dev/"
export const job = (n: string, spec: Record<string, unknown> = {}): AgentJob => ({
  apiVersion: "ultracode.mecattaf.dev/v1alpha1", kind: "AgentJob",
  metadata: { name: `wf-test-${n}`, labels: { [A + "run-id"]: "wf-test", [A + "workflow"]: "link-test", [A + "phase-index"]: "1" },
    annotations: { [A + "run-id-raw"]: "wf_test", [A + "label"]: `probe:${n}`, [A + "item-key"]: `wf_test#${n}`, [A + "journal-key"]: `${"cd".repeat(32)}:1`, [A + "phase-title"]: "Probe" } },
  spec: { "runs-on": ["seat:halogen", "runtime:gvisor"],
    with: { prompt: `say ${n}`, prompt_ref: { sha256: "ab".repeat(32), bytes: 5, uri: `journal://wf_test/${n}/prompt.md` }, model: "halogen-qwen3.8-flash-next" }, ...spec } as any
})
export const world = (o: Partial<FloorConfig> = {}) => ({
  floor: new FakeFloor({ cap: 2, leaseSeconds: 6, graceSeconds: 15, pollSeconds: 1, heartbeatSeconds: 2, maxAttempts: 3, secondMs: SEC, tokens: { "tok-nas": "nas-link-1" }, ...o }),
  ax: new FakeAx()
})
export type World = ReturnType<typeof world>
export function start(w: World, dir = mkdtempSync(join(tmpdir(), "r4-fix-")), over: Partial<LinkConfig> = {}, fetch?: typeof globalThis.fetch, extra: Pick<LinkDeps, "substrate"> = {}) {
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
    return yield* runLink(cfg, { ax: w.ax, floor, journal: Journal.open(dir), log: (ev, f) => logs.push({ t: Date.now(), ev, ...f }), stop, floorUrl: "http://floor.test", ...extra })
  })))
  return {
    dir, logs, fiber,
    has: (ev: string, leaseId?: string) => logs.some((l) => l.ev === ev && (leaseId === undefined || l.leaseId === leaseId)),
    drain: () => { Effect.runSync(Deferred.succeed(stop, undefined)); return Promise.race([Effect.runPromise(Fiber.await(fiber)), sleep(1500)]) }
  }
}
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
export const until = async (what: string, pred: () => boolean, ms = 5000) => {
  const t0 = Date.now()
  while (!pred()) { if (Date.now() - t0 > ms) throw new Error(`timeout waiting for: ${what}`); await new Promise((r) => setTimeout(r, 5)) }
}
export const bodyOf = async (input: unknown, init?: RequestInit) => {
  const b = init?.body
  if (typeof b === "string") return b
  if (b instanceof Uint8Array) return new TextDecoder().decode(b)
  if (b) return await new Response(b as any).text()
  return (input instanceof Request) ? await input.clone().text() : ""
}
