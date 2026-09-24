// HF link-ladder (critique-pass VERIFY-link-ladder.md): the four sub-claims no test pinned. Each test here fails when
// the hunk behind its claim is reverted (the mutation named in its title, from the VERIFY mutation table):
//   M1  busy() counts a delete-stuck, proven-free name        -> L8 (and L2, now that busy() is fixed)
//   M10 `auto` picks guest while the probe is unanswered       -> L9
//   M11 main.ts drops the four new keys on the way to runLink  -> L10
//   M15 the ladder is timed from the last touch, not deletingAt -> L11
// FakeAx and FakeFloor only; nothing spawns workerd or wrangler.
import { appendFileSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { Effect, Fiber } from "effect"
import { describe, expect, it } from "vitest"
import { AxError } from "../src/ax.ts"
import { linkConfigOf, readLinkEnv } from "../src/config.ts"
import type { SubstrateRead } from "../src/link.ts"
import { job, sleep, start, until, world } from "./review-r4-harness.ts"
import type { World } from "./review-r4-harness.ts"

const stickTerminating = (w: World) => {
  w.ax.tick = () => { for (const t of w.ax.tasks.values()) if (t.phase === "Pending") t.phase = "Running" }
}
const LADDER = { terminatingRetryMs: 150, terminatingEscalateMs: 600, terminatingGiveUpMs: 1200, terminatingRetries: 3 }
const journalLines = (dir: string) => readFileSync(join(dir, "journal.jsonl"), "utf8").trim().split("\n").map((x) => JSON.parse(x) as Record<string, unknown>)
const tOf = (logs: ReadonlyArray<Record<string, unknown>>, ev: string, leaseId?: string) =>
  logs.find((x) => x.ev === ev && (leaseId === undefined || x.leaseId === leaseId))?.t as number | undefined

const stuckAfterJob1 = async (w: World, l: ReturnType<typeof start>) => {
  await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
  w.ax.finish("wf-test-1-a1", 0, { ok: true })
  await until("floor done", () => w.floor.jobs.get("wf-test-1")!.state === "done", 5000)
  await until("a1 Terminating", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Terminating", 5000)
  await until("deleting journaled", () => l.has("delete"), 2000)
  await sleep(300) // the snapshot catches up (AUDIT section 2 side observation)
}

describe("HF link-ladder: the sub-claims VERIFY found untested", () => {
  it("L8 (M1, LL-4 busy half) with a floor that over-grants, the admission gate alone holds a stuck slot until a read proves it free", async () => {
    // overGrant makes the floor hand out job 2 whatever capacity the link asks for, so occupancy() is not a gate
    // here and busy() in admit() is the binding one. Root cause of M1 surviving in VERIFY: busy() dropped a
    // finished admitted lease's name from the set even while ax listed its Task live, so a1 never counted.
    const w = world({ overGrant: 1 }); stickTerminating(w)
    let answer: "absent" | "present" = "present"
    const substrate: SubstrateRead = { actor: () => Effect.sync(() => answer) }
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, { maxInFlight: 1, ...LADDER }, undefined, { substrate })
    await stuckAfterJob1(w, l)
    w.floor.enqueue(job("2"))
    await until("job 2 leased", () => l.has("leased", "wf-test-2-a1"), 3000)
    await until("job 2 waits", () => l.has("waiting-for-slot", "wf-test-2-a1"), 3000)
    await until("delete-stuck, actor present", () => l.has("delete-stuck"), 4000)
    expect(l.logs.find((x) => x.ev === "delete-stuck")).toMatchObject({ task: "wf-test-1-a1", freeProven: false })
    await sleep(300)
    expect(w.ax.updates.has("wf-test-2-a1")).toBe(false) // a stuck, not-proven-free Task keeps its slot in admit()
    answer = "absent"
    await until("job 2 created", () => w.ax.updates.has("wf-test-2-a1"), 4000)
    expect(l.logs.filter((x) => x.ev === "delete-stuck").at(-1)).toMatchObject({ task: "wf-test-1-a1", freeProven: true })
    expect(tOf(l.logs, "created", "wf-test-2-a1")!).toBeGreaterThanOrEqual(l.logs.filter((x) => x.ev === "delete-stuck").at(-1)!.t as number)
    expect(w.ax.tasks.get("wf-test-1-a1")?.phase).toBe("Terminating")
    await l.drain()
  }, 20000)

  it("L8b (the busy() fix) a reported lease whose Task ax still lists Running keeps its admission slot against an over-granting floor", async () => {
    // Stock ax (no P1): the agent's verdict arrives by relay while the Task stays Running until deleted. Here the
    // controller also never finishes the delete, so the Task is live for the whole test.
    const w = world({ overGrant: 1 }); stickTerminating(w)
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, { maxInFlight: 1, terminatingRetryMs: 60_000, terminatingEscalateMs: 120_000, terminatingGiveUpMs: 180_000 })
    await stuckAfterJob1(w, l)
    w.floor.enqueue(job("2"))
    await until("job 2 waits", () => l.has("waiting-for-slot", "wf-test-2-a1"), 3000)
    await sleep(600) // twenty resyncs and many admit() calls
    expect(w.ax.updates.has("wf-test-2-a1")).toBe(false)
    expect([...w.ax.tasks.values()].filter((t) => t.phase !== "Completed" && t.phase !== "Failed").length).toBe(1)
    await l.drain()
  }, 20000)

  it("L9 (M10, LL-7) auto creates nothing while the P1 probe is unanswered, even with ListTasks and GetGateway up; guest once it answers", async () => {
    const w = world({ tokens: { "tok-nas": { holder: "nas-link-1", guest: true } } }); w.ax.p1 = false
    const real = w.ax.getTaskResult
    let probeDown = true
    w.ax.getTaskResult = (name: string) => probeDown && name === "conwip-link-capability-probe"
      ? Effect.fail(new AxError(14, "probe timed out")) : real(name)
    w.floor.enqueue(job("1"))
    const RELAY = { atespace: "fleet", image: "ax-agent", gateway: "halogen", command: () => ["ax-agent", "pi"], completeUrl: "http://relay.internal:8787/complete" }
    const l = start(w, undefined, { completion: "auto", shape: RELAY })
    await until("ax-up", () => l.has("ax-up"))
    await until("gateway-ok", () => l.has("gateway-ok"))
    await sleep(800)
    expect(l.has("completion-probe")).toBe(false) // never answered, so never decided
    expect(w.ax.updates.size).toBe(0)
    expect(w.floor.calls.filter((c) => c.rpc === "Lease").every((c) => c.capacity === 0)).toBe(true)
    probeDown = false
    await until("created", () => w.ax.tasks.has("wf-test-1-a1"), 4000)
    expect(l.logs.find((x) => x.ev === "completion-probe")).toMatchObject({ serverP1: false, mode: "guest" })
    await l.drain()
  })

  it("L10 (M11, LL-5) main.ts's mapping carries the four new keys, in milliseconds, to runLink", () => {
    const c = linkConfigOf(readLinkEnv({ LINK_LEASE_KEY_ATTEMPTS: "2", LINK_TERMINATING_RETRY_SECONDS: "30", LINK_TERMINATING_ESCALATE_SECONDS: "120", LINK_TERMINATING_GIVE_UP_SECONDS: "600" }), ["https://a.example"])
    expect([c.leaseKeyAttempts, c.terminatingRetryMs, c.terminatingEscalateMs, c.terminatingGiveUpMs]).toEqual([2, 30_000, 120_000, 600_000])
    const d = linkConfigOf(readLinkEnv({}), [])
    expect([d.leaseKeyAttempts, d.terminatingRetryMs, d.terminatingEscalateMs, d.terminatingGiveUpMs]).toEqual([5, 60_000, 300_000, 900_000])
    expect(d.secondMs).toBe(1000)
    expect(c.floorUrls).toEqual(["https://a.example"])
    const src = readFileSync(new URL("../src/main.ts", import.meta.url), "utf8")
    expect(src).toMatch(/runLink\(linkConfigOf\(c, floorUrls\)/) // main.ts uses this mapping, not a copy of it
  })

  it("L11 (M15, LL-1/LL-3) a touch after `deleting` does not restart the ladder clock: steps are due from deletingAt", async () => {
    const w = world(); stickTerminating(w)
    w.floor.enqueue(job("1"))
    const quiet = { terminatingRetryMs: 60_000, terminatingEscalateMs: 120_000, terminatingGiveUpMs: 180_000 }
    const l1 = start(w, undefined, { maxInFlight: 1, ...quiet })
    await stuckAfterJob1(w, l1)
    Effect.runFork(Fiber.interrupt(l1.fiber)) // no drain: the journal is kept as it is
    await sleep(100)
    const deletingAt = journalLines(l1.dir).find((x) => x.ev === "deleting" && x.leaseId === "wf-test-1-a1")!.t as number
    const ladder = { terminatingRetryMs: 300, terminatingEscalateMs: 900, terminatingGiveUpMs: 60_000, terminatingRetries: 5 }
    await sleep(Math.max(0, deletingAt + ladder.terminatingEscalateMs + 100 - Date.now()))
    const touch = Date.now()
    appendFileSync(join(l1.dir, "journal.jsonl"), JSON.stringify({ t: touch, ev: "deleting", leaseId: "wf-test-1-a1", why: "janitor" }) + "\n")
    const l2 = start(w, l1.dir, { maxInFlight: 1, ...ladder })
    await until("escalated", () => l2.has("ax-delete-escalate"), 3000)
    const esc = l2.logs.find((x) => x.ev === "ax-delete-escalate")!
    expect(esc.since).toBe(deletingAt)
    // from the last touch it would be due at touch + 900 ms; from deletingAt it is already due at the first resync
    expect((esc.t as number) - touch).toBeLessThan(ladder.terminatingEscalateMs / 2)
    const r1 = l2.logs.find((x) => x.ev === "delete-retry")!
    expect(r1).toMatchObject({ n: 1, since: deletingAt })
    await l2.drain()
  }, 20000)
})
