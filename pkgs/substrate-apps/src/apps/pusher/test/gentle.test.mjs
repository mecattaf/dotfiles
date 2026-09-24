// The gentle pusher: seat-capacity/1 (the box's oracle, `seats --json`) to
// seat-capacity/2, the refresh policy it reads under, and the stale handling.
import { spawn } from "node:child_process"
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs"
import { createServer } from "node:http"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { Schema } from "effect"
import { afterEach, describe, expect, it } from "vitest"

import { SeatCapacitySnapshot } from "@substrate/planning/schema/seatCapacity.ts"
import { admitSeat } from "@substrate/planning/capacity/project.ts"
import { SeatsFormatError, snapshotFromSeatsV1 } from "../src/seatsOracle.mjs"
import { initialGentleState, planRead, tick } from "../src/gentle.mjs"

const FIXTURE = fileURLToPath(new URL("./fixtures/seats-v1.json", import.meta.url))
const BIN = fileURLToPath(new URL("../bin/substrate-pusher.mjs", import.meta.url))
const SRC = fileURLToPath(new URL("../src/", import.meta.url))
const v1 = () => JSON.parse(readFileSync(FIXTURE, "utf8"))
const NOW = "2026-09-23T20:00:05Z"
const decode = Schema.decodeUnknownSync(SeatCapacitySnapshot)
const convert = (config = {}, doc = v1(), now = NOW) => snapshotFromSeatsV1(doc, config, now)
const bySeat = (snapshot) => Object.fromEntries(snapshot.seats.map((seat) => [seat.seat, seat]))

describe("seat-capacity/1 to seat-capacity/2", () => {
  it("covers cc, cc2, codex, pi-qwencloud and halogen, and decodes as seat-capacity/2", () => {
    const { snapshot, skipped } = convert()
    expect(decode(snapshot)).toBeTruthy()
    expect(snapshot.seats.map((seat) => seat.seat)).toEqual(["cc", "cc2", "codex", "halogen", "pi-qwencloud"])
    expect(skipped).toEqual([])
    expect(snapshot.published_at).toBe(NOW)
    expect(snapshot.host).toBe("example-box")
  })

  it("places the 5h, 7d and model-scoped windows, with the reset instants and severities", () => {
    const cc2 = bySeat(convert().snapshot).cc2
    expect(cc2.windows.map((w) => [w.kind, w.model, w.minutes, w.utilization_pct, w.resets_at, w.severity])).toEqual([
      ["five_hour", null, 300, 14, "2026-09-23T23:40:00Z", "normal"],
      ["seven_day", null, 10080, 76, "2026-09-24T06:00:00Z", "warning"],
      ["model_scoped", "Fable", 10080, 100, "2026-09-24T06:00:00Z", "critical"]
    ])
    expect(cc2.model_windows_complete).toBe(true)
    // An empty reset is "opens on first use"; an empty severity is none.
    expect(bySeat(convert().snapshot).cc.windows[0]).toMatchObject({ kind: "five_hour", resets_at: null, utilization_pct: 0 })
  })

  it("dates each reading by the provider's answer, not by the oracle's run", () => {
    const seats = bySeat(convert().snapshot)
    expect(seats.cc.observed_at).toBe("2026-09-23T19:59:20.000Z") // generated_at - 40 s
    expect(seats.cc2.observed_at).toBe("2026-09-23T19:35:00.000Z") // a CACHED reading 1500 s old
    expect(seats.cc2.stale_reason).toMatch(/cached reading 1500 s old/)
    expect(seats.codex.observed_at).toBe("2026-09-23T19:50:00.000Z") // the rollout's own instant
  })

  it("a window it cannot place becomes a binding UNKNOWN weekly window and withdraws model_windows_complete", () => {
    const codex = bySeat(convert().snapshot).codex
    expect(codex.windows[1]).toMatchObject({ kind: "seven_day", binding: true, utilization_pct: null, grade: "UNKNOWN", resets_at: "2026-09-24T19:00:00Z" })
    expect(codex.model_windows_complete).toBe(false)
  })

  it("owners, rulings, slots and estimated providers follow the config; the oracle's owner field can be overridden", () => {
    const plain = bySeat(convert().snapshot)
    expect([plain.codex.owner, plain.codex.dispatchable, plain.codex.dispatchable_reason]).toEqual(["third-party", false, "third-party"])
    const ruled = bySeat(convert({ owners: { codex: "tom" }, slots: { halogen: 2 }, plans: { "pi-qwencloud": "2026-11-07T00:00:00Z" } }).snapshot)
    expect([ruled.codex.owner, ruled.codex.dispatchable]).toEqual(["tom", true])
    expect(ruled.halogen).toMatchObject({ provider: "halogen", owner: "tom", slots: { capacity: 2, holders: 0 }, grade: "MEASURED", dispatchable: true })
    expect(ruled["pi-qwencloud"]).toMatchObject({ grade: "ESTIMATED", plan: { expires_at: "2026-11-07T00:00:00Z" } })
    const cc3 = bySeat(convert({ seats: ["cc3"] }).snapshot).cc3
    expect([cc3.dispatchable, cc3.dispatchable_reason, cc3.grade]).toEqual([false, "evicted", "UNKNOWN"])
    const unauth = bySeat(convert({ seats: ["cc3"], not_dispatchable: {} }).snapshot).cc3
    expect(unauth.dispatchable_reason).toBe("evicted") // a config cannot lift a built-in ruling
    const skip = convert({ seats: ["gpu-coordinator", "cc"] })
    expect(skip.skipped).toEqual([{ seat: "gpu-coordinator", reason: "the oracle names no provider" }])
  })

  it("no local path, endpoint or credential location leaves the box", () => {
    const out = JSON.stringify(convert({ seats: ["cc", "cc2", "cc3", "codex", "pi-qwencloud", "halogen"] }).snapshot)
    expect(out).not.toMatch(/\/home\/|\/run\/|agenix|credentials|worker\.example|config_dir|key_source/)
    expect(out).toContain("<path>")
  })

  it("refuses a document that is not seat-capacity/1", () => {
    expect(() => convert({}, { schema_version: "seat-capacity/2", seats: [] })).toThrow(SeatsFormatError)
    expect(() => convert({}, null)).toThrow(SeatsFormatError)
  })

  it("the admit rule on the converted seats: model-scoped refusal, stale refusal, estimated refusal, slot admission", () => {
    const seats = bySeat(convert({ owners: { codex: "tom" }, slots: { halogen: 1 } }).snapshot)
    const at = NOW
    expect(admitSeat("cc", seats.cc, { model: "claude-fable-5-1", min_headroom_pct: 0 }, at)).toMatchObject({ admit: true })
    // cc2's reading is 1505 s old at NOW: STALE, which refuses and asks for a fresh read.
    expect(admitSeat("cc2", seats.cc2, { model: "claude-opus-5", min_headroom_pct: 0 }, at)).toMatchObject({ admit: false, reason: "stale", raise_demand: true })
    // The same reading when fresh: Fable refused by its own window, Opus admitted.
    const fresh = { ...seats.cc2, observed_at: "2026-09-23T20:00:00Z" }
    expect(admitSeat("cc2", fresh, { model: "claude-fable-5-1", min_headroom_pct: 0 }, at).admit).toBe(false)
    expect(admitSeat("cc2", fresh, { model: "claude-opus-5", min_headroom_pct: 0 }, at)).toMatchObject({ admit: true })
    expect(admitSeat("pi-qwencloud", seats["pi-qwencloud"], { model: null, min_headroom_pct: 0 }, at)).toMatchObject({ admit: false, reason: "estimated" })
    expect(admitSeat("halogen", seats.halogen, { model: null, min_headroom_pct: 0 }, at)).toMatchObject({ admit: true })
  })
})

describe("the refresh policy the pusher reads under", () => {
  const T0 = Date.parse("2026-09-23T20:00:00Z")
  const S = 1000
  const read = (state, nowMs, extra = {}) => tick(state, { nowMs, config: {}, runOracle: async () => v1(), post: async () => ({ report: { results: [] } }), ...extra })

  it("first read at once; never again within 120 s; idle every 900 s", async () => {
    expect(planRead(initialGentleState(), { nowMs: T0 })).toMatchObject({ due: true, reason: "first-read" })
    const first = await read(initialGentleState(), T0)
    expect(first.events.map((e) => e.event)).toEqual(["read", "pushed"])
    expect(planRead(first.state, { nowMs: T0 + 60 * S })).toMatchObject({ due: false, reason: "min-spacing" })
    expect(planRead(first.state, { nowMs: T0 + 60 * S, preDispatch: true })).toMatchObject({ due: false, reason: "min-spacing" })
    expect(planRead(first.state, { nowMs: T0 + 899 * S })).toMatchObject({ due: false, reason: "fresh" })
    expect(planRead(first.state, { nowMs: T0 + 900 * S })).toMatchObject({ due: true, reason: "idle" })
  })

  it("active every 300 s (a demand marker, or readings that move); 180 s near a cap; pre-dispatch after 300 s", async () => {
    const first = await read(initialGentleState(), T0)
    expect(planRead(first.state, { nowMs: T0 + 300 * S, demandAtMs: T0 + 250 * S })).toMatchObject({ due: true, reason: "active" })
    expect(planRead(first.state, { nowMs: T0 + 299 * S, demandAtMs: T0 + 250 * S }).due).toBe(false)
    expect(planRead(first.state, { nowMs: T0 + 301 * S, preDispatch: true })).toMatchObject({ due: true, reason: "pre-dispatch" })
    // Two reads whose utilization differs: the box is active without a marker. cc2's 7d is 76 %, below 85.
    const moved = v1()
    moved.seats[0].windows[1].used_pct = 7.0
    const second = await read(first.state, T0 + 900 * S, { runOracle: async () => moved })
    expect(planRead(second.state, { nowMs: T0 + 1200 * S })).toMatchObject({ due: true, reason: "active" })
    const hot = v1()
    hot.seats[1].windows[1].used_pct = 90.0
    const third = await read(second.state, T0 + 1200 * S, { runOracle: async () => hot })
    expect(planRead(third.state, { nowMs: T0 + 1380 * S })).toMatchObject({ due: true, reason: "active" })
    expect(planRead(third.state, { nowMs: T0 + 1379 * S }).due).toBe(false)
  })

  it("an unchanged reading is not re-posted until the heartbeat", async () => {
    const claudeOnly = { config: { seats: ["cc", "cc2"] } }
    const first = await read(initialGentleState(), T0, claudeOnly)
    const again = await read(first.state, T0 + 900 * S, claudeOnly)
    expect(again.events.map((e) => e.event)).toEqual(["read", "not-pushed"])
    const beat = await read(again.state, T0 + 1800 * S, claudeOnly)
    expect(beat.events.at(-1)).toMatchObject({ event: "pushed", reason: "heartbeat" })
    // A published Halogen slot row beats every 600 s, so the floor never grades it STALE (1200 s).
    const slots = await read((await read(initialGentleState(), T0)).state, T0 + 900 * S)
    expect(slots.events.at(-1)).toMatchObject({ event: "pushed", reason: "heartbeat" })
  })
})

describe("stale and failed reads", () => {
  const T0 = Date.parse("2026-09-23T20:00:00Z")
  const S = 1000

  it("a failed oracle run posts nothing, keeps the 120 s spacing, and the next due read recovers", async () => {
    const posts = []
    const failed = await tick(initialGentleState(), { nowMs: T0, config: {}, runOracle: async () => { throw new Error("the oracle failed: 1") }, post: async (s) => posts.push(s) })
    expect(failed.events.at(-1)).toMatchObject({ event: "read-failed" })
    expect(posts).toEqual([])
    expect(planRead(failed.state, { nowMs: T0 + 119 * S })).toMatchObject({ due: false, reason: "min-spacing" })
    const wrong = await tick(failed.state, { nowMs: T0 + 120 * S, config: {}, runOracle: async () => ({ schema_version: "nope" }), post: async (s) => posts.push(s) })
    expect(wrong.events.at(-1)).toMatchObject({ event: "read-failed" })
    const ok = await tick(wrong.state, { nowMs: T0 + 240 * S, config: {}, runOracle: async () => v1(), post: async (s) => { posts.push(s); return {} } })
    expect(ok.events.map((e) => e.event)).toEqual(["read", "pushed"])
    expect(posts).toHaveLength(1)
  })

  it("a seat the oracle stops reporting is named, not carried forward", async () => {
    const doc = v1()
    doc.seats = doc.seats.filter((seat) => seat.id !== "cc")
    const r = await tick(initialGentleState(), { nowMs: T0, config: {}, runOracle: async () => doc, post: async () => ({}) })
    expect(r.events[0].skipped).toEqual([{ seat: "cc", reason: "the oracle did not report this seat" }])
    expect(r.state.last.seats.map((seat) => seat.seat)).not.toContain("cc")
  })

  it("a failed post is retried with the same snapshot after 60 s, without a new read", async () => {
    let reads = 0
    const runOracle = async () => { reads++; return v1() }
    const down = await tick(initialGentleState(), { nowMs: T0, config: {}, runOracle, post: async () => { throw new Error("answered 503") } })
    expect(down.events.at(-1)).toMatchObject({ event: "push-failed" })
    const early = await tick(down.state, { nowMs: T0 + 30 * S, config: {}, runOracle, post: async () => ({}) })
    expect(early.events).toEqual([expect.objectContaining({ event: "wait", reason: "push-retry" })])
    const sent = []
    const retry = await tick(down.state, { nowMs: T0 + 60 * S, config: {}, runOracle, post: async (s) => { sent.push(s); return {} } })
    expect(retry.events[0]).toMatchObject({ event: "pushed", reason: "retry" })
    expect(sent[0]).toEqual(down.state.pending.snapshot)
    expect(reads).toBe(1)
  })
})

describe("the pusher never calls a usage endpoint itself", () => {
  it("its modules name no provider endpoint and do not import the legacy direct reader", () => {
    for (const file of ["seatsOracle.mjs", "gentle.mjs"]) {
      const text = readFileSync(join(SRC, file), "utf8")
      expect(text, file).not.toMatch(/api\.anthropic\.com|oauth\/usage|usageSource/)
    }
    const bin = readFileSync(BIN, "utf8")
    expect(bin).not.toMatch(/api\.anthropic\.com|oauth\/usage|usageSource|seatCapacity\.mjs"/)
  })
})

describe("the process", () => {
  const dirs = []
  afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }) })
  const run = (args, env = {}) => new Promise((resolve) => {
    const child = spawn(process.execPath, [BIN, ...args], { env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] })
    let out = "", err = ""
    child.stdout.on("data", (b) => { out += b })
    child.stderr.on("data", (b) => { err += b })
    child.on("exit", (code) => resolve({ code, out, err, child }))
  })

  it("--once posts to /capacity/snapshots with the bearer, keeps 0600 state, and releases its pidfile", async () => {
    const dir = mkdtempSync(join(tmpdir(), "gentle-")); dirs.push(dir)
    writeFileSync(join(dir, "token"), "test-token-value\n", { mode: 0o600 })
    const seen = []
    const server = createServer((req, res) => {
      let body = ""
      req.on("data", (b) => { body += b })
      req.on("end", () => {
        seen.push({ method: req.method, url: req.url, auth: req.headers.authorization, body: JSON.parse(body) })
        res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ report: { results: [], changed: true } }))
      })
    })
    await new Promise((r) => server.listen(0, "127.0.0.1", r))
    const port = server.address().port
    const pid = join(dir, "pusher.pid")
    const r = await run(["--once", "--url", `http://127.0.0.1:${port}`, "--token-file", join(dir, "token"), "--seats-json", FIXTURE,
      "--state", join(dir, "state.json"), "--pidfile", pid, "--demand-dir", join(dir, "demand"), "--config", join(dir, "absent.json")].slice(0, -2))
    server.close()
    expect(r.code, r.err).toBe(0)
    expect(seen).toHaveLength(1)
    expect([seen[0].method, seen[0].url, seen[0].auth]).toEqual(["POST", "/capacity/snapshots", "Bearer test-token-value"])
    expect(decode(seen[0].body).seats.length).toBe(5)
    expect(r.out).not.toContain("test-token-value")
    expect(existsSync(pid)).toBe(false)
    expect(statSync(join(dir, "state.json")).mode & 0o777).toBe(0o600)
  })

  it("a second pusher refuses while the first holds the pidfile; a stale pidfile is replaced", async () => {
    const dir = mkdtempSync(join(tmpdir(), "gentle-")); dirs.push(dir)
    const pid = join(dir, "pusher.pid")
    const common = ["--dry-run", "--seats-json", FIXTURE, "--pidfile", pid, "--demand-dir", join(dir, "demand")]
    const first = spawn(process.execPath, [BIN, ...common], { stdio: "ignore" })
    for (let i = 0; i < 100 && !existsSync(pid); i++) await new Promise((r) => setTimeout(r, 50))
    expect(readFileSync(pid, "utf8").trim()).toBe(String(first.pid))
    const second = await run([...common, "--once"])
    expect(second.code).toBe(3)
    expect(second.err).toMatch(/another pusher/)
    const exited = new Promise((r) => first.on("exit", r))
    first.kill("SIGTERM")
    await exited
    expect(existsSync(pid)).toBe(false)
    writeFileSync(pid, "999999999\n")
    const third = await run([...common, "--once"])
    expect(third.code, third.err).toBe(0)
    expect(JSON.parse(third.out.trim().split("\n").at(-1))).toMatchObject({ event: "dry-run" })
    expect(readdirSync(dir)).not.toContain("pusher.pid")
  })
})
