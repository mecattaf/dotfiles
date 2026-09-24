// Round 4 regression test, ported from /home/tom/today/evals-2026-09-23/link/scratch-r4-2/heartbeat-envelope.repro.ts (assertions kept; additions marked).
// Schema compatibility: the round-3 fix made the Lease and Complete success envelopes lenient ("a changed stats shape
// would otherwise fail the decode"), but Heartbeat still decodes with the strict L1 schema. The same drift on the
// Heartbeat reply (here `stats: null`, which Lease tolerates) makes every heartbeat a transient error: held leases are
// never renewed, the floor requeues a healthy running attempt as a2, and the link fences a1 and runs the job again.
import { expect, it } from "vitest"
import { job, start, until, world, bodyOf, sleep } from "./review-r4-harness.ts"

const drift = (rpc: string, floorFetch: typeof globalThis.fetch): typeof globalThis.fetch => async (input, init) => {
  const body = await bodyOf(input, init)
  const res = await floorFetch(input, init)
  if (!body.includes(`"${rpc}"`)) return res
  const text = await res.text()
  let m: any
  try { m = JSON.parse(text) } catch { return new Response(text, { status: res.status, headers: res.headers }) }
  const walk = (x: any) => { if (x && typeof x === "object") { if ("stats" in x && "seq" in (x.stats ?? {})) x.stats = null; for (const v of Object.values(x)) walk(v) } }
  walk(m)
  return new Response(JSON.stringify(m), { status: res.status, headers: res.headers })
}

for (const rpc of ["Lease", "Heartbeat"]) {
  it(`stats: null on every ${rpc} reply`, async () => {
    const w = world()
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, {}, drift(rpc, w.floor.fetch))
    try {
      await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
      await sleep(1500) // about 12 lease durations (6 s x 20 ms) with a1 healthy and running
      const J = w.floor.jobs.get("wf-test-1")!
      const hbErr = l.logs.filter((x) => x.ev === "heartbeat-error").length
      const out = { rpc, floorState: J.state, attempt: J.attempt, history: J.history, heartbeatErrors: hbErr,
        a1: w.ax.tasks.get("wf-test-1-a1")?.phase ?? "deleted", a2: w.ax.tasks.get("wf-test-1-a2")?.phase ?? "absent",
        events: l.logs.map((x) => x.ev).filter((e, i, a) => a.indexOf(e) === i) }
      console.log(JSON.stringify(out))
      // The expected behaviour, as for the Lease drift: a healthy a1 keeps its lease and nothing reruns.
      expect(J.attempt).toBe(1)
      expect(w.ax.tasks.get("wf-test-1-a2")).toBeUndefined()
    } finally { await l.drain(); w.floor.close() }
  })
}

// The consequence: the floor renews on its side, but the link never reads `cancelRequested`, `lost` or `renewed`.
for (const rpc of ["Lease", "Heartbeat"]) {
  it(`cancel with stats: null on every ${rpc} reply`, async () => {
    const w = world()
    w.floor.enqueue(job("1"))
    const l = start(w, undefined, {}, drift(rpc, w.floor.fetch))
    try {
      await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
      w.floor.cancel("wf-test-1")
      await sleep(1500)
      const J = w.floor.jobs.get("wf-test-1")!
      const out = { rpc, floorState: J.state, result: J.result ?? null, cancel: J.cancel ?? null, history: J.history,
        a1: w.ax.tasks.get("wf-test-1-a1")?.phase ?? "deleted", cancelLogged: l.has("cancel") }
      console.log(JSON.stringify(out))
      expect(J.state).toBe("done")
      expect(J.result).toBe("cancelled")
    } finally { await l.drain(); w.floor.close() }
  })
}

// B13: a grant journaled by a previous process and never created is resumed only once a Heartbeat reply renews it.
for (const rpc of ["Lease", "Heartbeat"]) {
  it(`restart resume with stats: null on every ${rpc} reply`, async () => {
    const { Effect } = await import("effect")
    const w = world()
    w.floor.enqueue(job("1"))
    const orig = w.ax.createTask
    ;(w.ax as any).createTask = () => Effect.never // first process: UpdateTask never answers, then the process stops
    const l1 = start(w)
    const dir = l1.dir
    await until("a1 creating", () => l1.has("leased"))
    await sleep(100)
    await l1.drain()
    ;(w.ax as any).createTask = orig
    const J = w.floor.jobs.get("wf-test-1")!
    const l2 = start(w, dir, {}, drift(rpc, w.floor.fetch))
    try {
      await sleep(2000)
      const out = { rpc, floorState: J.state, attempt: J.attempt, history: J.history, result: J.result ?? null,
        a1: w.ax.tasks.get("wf-test-1-a1")?.phase ?? "absent", resumed: l2.has("resume"),
        heartbeatErrors: l2.logs.filter((x) => x.ev === "heartbeat-error").length,
        events: l2.logs.map((x) => x.ev).filter((e, i, a) => a.indexOf(e) === i) }
      console.log(JSON.stringify(out))
      expect(J.state === "done" || w.ax.tasks.get("wf-test-1-a1") !== undefined).toBe(true)
    } finally { await l2.drain(); w.floor.close() }
  })
}

// Round 4 addition (finding 6): a Heartbeat reply that omits `cancelRequested` (or has it null) is read for the rest.
const omit = (key: string, value: "omit" | null, floorFetch: typeof globalThis.fetch): typeof globalThis.fetch => async (input, init) => {
  const body = await bodyOf(input, init)
  const res = await floorFetch(input, init)
  if (!body.includes('"Heartbeat"')) return res
  const text = await res.text()
  let m: any
  try { m = JSON.parse(text) } catch { return new Response(text, { status: res.status, headers: res.headers }) }
  const walk = (x: any) => { if (x && typeof x === "object") { if (key in x && "renewed" in x) { if (value === "omit") delete x[key]; else x[key] = value } for (const v of Object.values(x)) walk(v) } }
  walk(m)
  return new Response(JSON.stringify(m), { status: res.status, headers: res.headers })
}
for (const value of ["omit", null] as const) {
  it(`R4-6b: restart resume with cancelRequested ${value === "omit" ? "omitted" : "null"} on every Heartbeat reply`, async () => {
    const { Effect } = await import("effect")
    const w = world()
    w.floor.enqueue(job("1"))
    const orig = w.ax.createTask
    ;(w.ax as any).createTask = () => Effect.never
    const l1 = start(w)
    await until("a1 creating", () => l1.has("leased"))
    await sleep(100)
    await l1.drain()
    ;(w.ax as any).createTask = orig
    const l2 = start(w, l1.dir, {}, omit("cancelRequested", value, w.floor.fetch))
    try {
      await until("a1 resumed and created", () => w.ax.tasks.get("wf-test-1-a1") !== undefined, 3000)
      expect(l2.has("resume", "wf-test-1-a1")).toBe(true)
      expect(l2.logs.filter((x) => x.ev === "heartbeat-error").length).toBe(0)
    } finally { await l2.drain(); w.floor.close() }
  })
}
it("R4-6c: a lost lease is still acted on when the Heartbeat reply omits stats and cancelRequested", async () => {
  const w = world()
  w.floor.enqueue(job("1"))
  const both: typeof globalThis.fetch = omit("cancelRequested", "omit", drift("Heartbeat", w.floor.fetch))
  const l = start(w, undefined, {}, both)
  try {
    await until("a1 running", () => w.ax.tasks.get("wf-test-1-a1")?.phase === "Running")
    const J = w.floor.jobs.get("wf-test-1")!
    J.holder = "someone-else" // the floor answers lost:[a1] from now on
    await until("lost", () => l.has("lost", "wf-test-1-a1"), 2000)
    await until("a1 deleted", () => w.ax.deletes.includes("wf-test-1-a1"), 2000)
  } finally { await l.drain(); w.floor.close() }
})
