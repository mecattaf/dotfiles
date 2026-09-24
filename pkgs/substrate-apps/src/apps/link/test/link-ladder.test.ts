// Critique D.2 (cp/link-ladder): the Terminating ladder, the provably-free slot, deletingAt through compaction, the
// fence on a stuck superseded attempt, the tunables through config.ts, the V2 Gateway log and `auto` falling back to
// guest. Each test is an audit probe (critique-pass AUDIT-link-ladder.md, P1 to P5) with its assertion inverted.
// FakeAx and FakeFloor only; ladder times are shrunk the way the rest of the suite shrinks seconds.
import { mkdtempSync, readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Effect, Fiber } from "effect"
import { describe, expect, it } from "vitest"
import { ConfigInvalid, readLinkEnv } from "../src/config.ts"
import { Journal } from "../src/journal.ts"
import type { SubstrateRead } from "../src/link.ts"
import { job, sleep, start, until, world } from "./review-r4-harness.ts"
import type { World } from "./review-r4-harness.ts"

/** DELETE-HANG run 2: the controller ACKs a delete event and drops it; a Terminating Task is never finished. */
const stickTerminating = (w: World) => {
  w.ax.tick = () => { for (const t of w.ax.tasks.values()) if (t.phase === "Pending") t.phase = "Running" }
}
const LADDER = { terminatingRetryMs: 150, terminatingEscalateMs: 600, terminatingGiveUpMs: 1200, terminatingRetries: 3 }
const journalLines = (dir: string) => readFileSync(join(dir, "journal.jsonl"), "utf8").trim().split("\n").map((x) => JSON.parse(x) as Record<string, unknown>)

/** Job 1 runs, completes, is acknowledged and deleted by the janitor into a Terminating that never ends. */
const stuckAfterJob1 = async (w: World, l: ReturnType<typeof start>) => {
  await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
  w.ax.finish("wf-test-1-a1", 0, { ok: true })
  await until("floor done", () => w.floor.jobs.get("wf-test-1")!.state === "done", 5000)
  await until("a1 Terminating", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Terminating", 5000)
  await until("deleting journaled", () => l.has("delete"), 2000)
  // AUDIT section 2 side observation: until the next resync the snapshot still shows a1 Completed (free by design);
  // the ladder is about the steady state, so the snapshot is let catch up first (about 10 resyncs)
  await sleep(300)
}

describe("critique D.2: the Terminating ladder", () => {
  it("L1 (P1 inverted) a stuck delete is re-sent, escalated and journaled delete-stuck; with no Substrate read the slot stays taken", async () => {
    const w = world(); stickTerminating(w)
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, { maxInFlight: 1, ...LADDER })
    await stuckAfterJob1(w, l)
    w.floor.enqueue(job("2"))
    await until("delete-stuck", () => l.has("delete-stuck"), 4000)
    await sleep(600) // many more resyncs past the give-up: nothing further is sent
    const deletesOfA1 = w.ax.deletes.filter((n) => n === "wf-test-1-a1").length
    expect(deletesOfA1).toBe(1 + LADDER.terminatingRetries) // the first DeleteTask, then exactly `retries` re-sends
    expect(l.logs.filter((x) => x.ev === "delete-retry").map((x) => x.n)).toEqual([1, 2, 3])
    const esc = l.logs.filter((x) => x.ev === "ax-delete-escalate")
    expect(esc.length).toBe(1)
    expect(esc[0]).toMatchObject({ task: "wf-test-1-a1", atespace: "fleet", actor: "no-reader" })
    const stuck = l.logs.filter((x) => x.ev === "delete-stuck")
    expect(stuck.length).toBe(1)
    expect(stuck[0]).toMatchObject({ task: "wf-test-1-a1", freeProven: false })
    // ladder order and timing measured from deletingAt
    const at = (ev: string) => l.logs.find((x) => x.ev === ev)!.t as number
    expect(at("delete-retry")).toBeLessThan(at("ax-delete-escalate"))
    expect(at("ax-delete-escalate")).toBeLessThan(at("delete-stuck"))
    const lines = journalLines(l.dir)
    expect(lines.some((x) => x.ev === "delete-stuck" && x.freeProven === false)).toBe(true)
    // DELETE-HANG default: capacity lowered by one until an operator clears it; job 2 is never created on top of it
    expect(w.ax.updates.has("wf-test-2-a1")).toBe(false)
    await l.drain()
  }, 20000)

  it("L2 a Substrate read that proves the actor absent releases the slot after the give-up, and not before", async () => {
    const w = world(); stickTerminating(w)
    const asked: Array<string> = []
    const substrate: SubstrateRead = { actor: (task) => Effect.sync(() => { asked.push(task); return "absent" as const }) }
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, { maxInFlight: 1, ...LADDER }, undefined, { substrate })
    await stuckAfterJob1(w, l)
    const stuckFrom = Date.now()
    w.floor.enqueue(job("2"))
    await until("escalated", () => l.has("ax-delete-escalate"), 3000)
    expect(l.logs.find((x) => x.ev === "ax-delete-escalate")).toMatchObject({ actor: "absent" })
    expect(w.ax.updates.has("wf-test-2-a1")).toBe(false) // escalation alone releases nothing
    await until("job 2 created", () => w.ax.updates.has("wf-test-2-a1"), 5000)
    const stuck = l.logs.find((x) => x.ev === "delete-stuck")!
    expect(stuck).toMatchObject({ task: "wf-test-1-a1", freeProven: true })
    expect(Date.now() - stuckFrom).toBeGreaterThan(LADDER.terminatingGiveUpMs / 2) // the slot stayed taken until the give-up
    expect(w.ax.tasks.get("wf-test-1-a1")?.phase).toBe("Terminating") // ax still shows it; the read decided
    expect(asked.every((t) => t === "wf-test-1-a1")).toBe(true)
    await l.drain()
  }, 20000)

  it("L3 the ladder clock (deletingAt), retry count and delete-stuck survive compaction and reopen", () => {
    const dir = mkdtempSync(join(tmpdir(), "ladder-j-"))
    const grant = { leaseId: "wf-x-a1", attempt: 1, lease: { leaseTransitions: 1, acquireTime: 1, leaseDurationSeconds: 90 }, job: { metadata: { name: "wf-x" } } } as never
    const j = Journal.open(dir)
    j.append({ ev: "grant", leaseId: "wf-x-a1", grant }, 1000)
    j.append({ ev: "created", leaseId: "wf-x-a1", digest: "d" }, 2000)
    j.append({ ev: "report", leaseId: "wf-x-a1", attempt: 1, result: "success" }, 3000)
    j.append({ ev: "reported", leaseId: "wf-x-a1", duplicate: false }, 3500)
    j.append({ ev: "deleting", leaseId: "wf-x-a1", why: "janitor" }, 4000)
    j.append({ ev: "delete-retry", leaseId: "wf-x-a1", n: 1 }, 5000)
    j.append({ ev: "deleting", leaseId: "wf-x-a1", why: "again" }, 8000) // a later intent never moves the clock
    j.append({ ev: "delete-stuck", leaseId: "wf-x-a1", freeProven: false }, 9500)
    const before = j.recs.get("wf-x-a1")!
    expect([before.deletingAt, before.deleteRetries, before.deleteStuck, before.freeProven, before.at]).toEqual([4000, 1, true, false, 8000])
    for (let i = 0; i < 2; i++) { // open compacts; twice, so a compacted file compacts to itself
      const r = Journal.open(dir).recs.get("wf-x-a1")!
      expect([r.deletingAt, r.deleteRetries, r.deleteStuck, r.freeProven, r.deleting, r.at]).toEqual([4000, 1, true, false, "janitor", 8000])
    }
  })

  it("L4 (P2 inverted) a superseded attempt stuck Terminating: the fence re-sends DeleteTask and fails n+1 infra/delete-stuck, final; no attempt loop", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l1 = start(w, undefined, {})
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    Effect.runFork(Fiber.interrupt(l1.fiber)) // l1 dies without a drain: no more heartbeats, the journal is kept
    await sleep(1000); w.floor.sweep(); await sleep(7 * 20); w.floor.sweep()
    stickTerminating(w)
    const l2 = start(w, l1.dir, { fenceTimeoutMs: 1500, terminatingRetryMs: 300, terminatingEscalateMs: 60_000, terminatingGiveUpMs: 120_000 })
    await until("job done", () => w.floor.jobs.get("wf-test-1")!.state === "done", 10000)
    const hist = w.floor.jobs.get("wf-test-1")!.history
    expect(l2.logs.find((x) => x.ev === "fence-failed")).toMatchObject({ old: "wf-test-1-a1", why: "stuck" })
    expect(w.ax.updates.has("wf-test-1-a2")).toBe(false) // attempt n+1 never beside a possibly running n
    expect(hist).not.toContain("leased:a3")
    expect(hist.at(-1)).toBe("done:failure")
    expect(w.floor.jobs.get("wf-test-1")!.output).toMatchObject({ reason: "infra/delete-stuck" })
    expect(w.ax.deletes.filter((n) => n === "wf-test-1-a1").length).toBeGreaterThanOrEqual(2) // re-asked inside the fence
    expect(l2.logs.some((x) => x.ev === "delete-retry" && x.where === "fence")).toBe(true)
    await l2.drain()
  }, 20000)
})

describe("critique D.2: the remaining wiring", () => {
  it("L5 (P3 inverted) gateway-ok carries the allowlist size and no allowsAll; an open Gateway is gateway-open", async () => {
    const w = world(); const l = start(w)
    await until("gateway-ok", () => l.has("gateway-ok"))
    const ok = l.logs.find((x) => x.ev === "gateway-ok")!
    expect(ok).toMatchObject({ gateway: "halogen", hosts: 1 })
    expect("allowsAll" in ok).toBe(false)
    w.ax.gateways.set("halogen", { hasAllowlist: true, hosts: [{ host: "*", port: 443 }] })
    await until("gateway-open", () => l.has("gateway-open"))
    expect(l.logs.find((x) => x.ev === "gateway-open")).toMatchObject({ gateway: "halogen", allowsAll: true })
    expect(l.logs.filter((x) => x.ev === "gateway-missing").length).toBe(0)
    w.ax.gateways.delete("halogen")
    await until("gateway-missing", () => l.has("gateway-missing"))
    expect(l.logs.find((x) => x.ev === "gateway-missing")).toMatchObject({ found: false })
    await l.drain()
  })

  const RELAY = { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "http://relay.internal:8787/complete" }
  it("L6 (P4 inverted) auto with a fleet-internal Complete URL on stock ax creates in guest mode with a per-lease token", async () => {
    const w = world({ tokens: { "tok-nas": { holder: "nas-link-1", guest: true } } }); w.ax.p1 = false; w.floor.enqueue(job("1"))
    const l = start(w, undefined, { completion: "auto", shape: RELAY })
    await until("created", () => w.ax.tasks.has("wf-test-1-a1"), 4000)
    expect(l.logs.find((x) => x.ev === "completion-probe")).toMatchObject({ serverP1: false, mode: "guest" })
    const env = new Map((w.ax.tasks.get("wf-test-1-a1")!.task.spec.env ?? []).map((e) => [e.name, e.value]))
    expect(env.get("AX_CONWIP_COMPLETE_URL")).toBe(RELAY.completeUrl)
    await l.drain()
  })

  it("L6b auto with a declared Complete URL still picks p1 when the server has P1; a public URL never enables guest", async () => {
    const w = world(); w.floor.enqueue(job("1"))
    const l = start(w, undefined, { completion: "auto", shape: RELAY })
    await until("created", () => w.ax.tasks.has("wf-test-1-a1"), 4000)
    expect(l.logs.find((x) => x.ev === "completion-probe")).toMatchObject({ serverP1: true, mode: "p1" })
    const env = new Map((w.ax.tasks.get("wf-test-1-a1")!.task.spec.env ?? []).map((e) => [e.name, e.value]))
    expect(env.has("AX_CONWIP_COMPLETE_URL")).toBe(false)
    await l.drain()
    const w2 = world(); w2.ax.p1 = false; w2.floor.enqueue(job("1"))
    const l2 = start(w2, undefined, { completion: "auto", shape: { ...RELAY, completeUrl: "https://conwip-floor.x.workers.dev/guest" } })
    await sleep(800)
    expect(l2.logs.find((x) => x.ev === "completion-probe")).toMatchObject({ mode: "none" })
    expect(l2.has("guest-url-invalid")).toBe(true)
    expect(w2.ax.updates.size).toBe(0)
    await l2.drain()
  })

  it("L7 (P5 inverted) LINK_LEASE_KEY_ATTEMPTS and the ladder keys are read, defaulted and ordered", () => {
    const d = readLinkEnv({})
    expect([d.leaseKeyAttempts, d.terminatingRetrySeconds, d.terminatingEscalateSeconds, d.terminatingGiveUpSeconds]).toEqual([5, 60, 300, 900])
    const c = readLinkEnv({ LINK_LEASE_KEY_ATTEMPTS: "2", LINK_TERMINATING_RETRY_SECONDS: "30", LINK_TERMINATING_ESCALATE_SECONDS: "120", LINK_TERMINATING_GIVE_UP_SECONDS: "600" })
    expect([c.leaseKeyAttempts, c.terminatingRetrySeconds, c.terminatingEscalateSeconds, c.terminatingGiveUpSeconds]).toEqual([2, 30, 120, 600])
    const bad = (env: Record<string, string>) => { try { readLinkEnv(env); return undefined } catch (e) { return e instanceof ConfigInvalid ? e.key : "other" } }
    expect(bad({ LINK_LEASE_KEY_ATTEMPTS: "0" })).toBe("LINK_LEASE_KEY_ATTEMPTS")
    expect(bad({ LINK_TERMINATING_RETRY_SECONDS: "300" })).toBe("LINK_TERMINATING_ESCALATE_SECONDS") // 300 is not above 300
    expect(bad({ LINK_TERMINATING_GIVE_UP_SECONDS: "200" })).toBe("LINK_TERMINATING_GIVE_UP_SECONDS")
    expect(bad({ LINK_TERMINATING_RETRY_SECONDS: "x" })).toBe("LINK_TERMINATING_RETRY_SECONDS")
  })
})
