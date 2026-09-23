// The seat-capacity pusher: snapshot building from today's meter shapes, the
// refresh policy, the push, and a round trip into the real Factory handler.
import { spawnSync } from "node:child_process"
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync, mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { Schema } from "effect"
import { describe, expect, it } from "vitest"

import {
  buildSnapshot,
  decidePush,
  fingerprint,
  readConfig,
  readState,
  runOnce,
  stateAfterPush
} from "../src/seatCapacity.mjs"
import { SeatCapacitySnapshot } from "@substrate/planning/schema/seatCapacity.ts"
import { admitSeat } from "@substrate/planning/capacity/project.ts"
import {
  emptyFactory,
  artifactBytes,
  artifactDigest
} from "../../../packages/factory/test/fixtures.ts"
import { makeFactoryHttpHandler, makeTableArtifactHasher } from "@substrate/factory"

const decodeSnapshot = Schema.decodeUnknownSync(SeatCapacitySnapshot)
const PUSHER = fileURLToPath(new URL("../bin/seat-pusher.mjs", import.meta.url))
const EXAMPLE_CONFIG = fileURLToPath(new URL("../seat-capacity.example.json", import.meta.url))

const OBSERVED = "2026-09-23T04:52:18.363166+00:00"
const NOW = "2026-09-23T04:53:18.000Z"

// Shapes as MEASURED on 2026-09-23 (SCOUT.md section 2); values synthetic.
const ccCache = (observed = OBSERVED, fable = 100) => ({
  observed_at: observed,
  usage: {
    five_hour: { utilization: 8, resets_at: "2026-09-23T08:49:59.526442+00:00", used_dollars: 1.5 },
    seven_day: { utilization: 72, resets_at: "2026-09-23T09:59:59.526461+00:00" },
    limits: [
      { kind: "session", group: "session", percent: 8, severity: "normal", resets_at: "2026-09-23T08:49:59.526442+00:00", scope: null, is_active: false },
      { kind: "weekly_all", group: "weekly", percent: 72, severity: "normal", resets_at: "2026-09-23T09:59:59.526461+00:00", scope: null, is_active: false },
      { kind: "weekly_scoped", group: "weekly", percent: fable, severity: fable >= 100 ? "critical" : "warning", resets_at: "2026-09-23T09:59:59.526615+00:00", scope: { model: { id: null, display_name: "Fable" }, surface: null }, is_active: true }
      // An unknown kind ("something_new") is no longer dropped: it withdraws
      // model_windows_complete and refuses (successor review r4); that case
      // lives in unmappedLimits.test.mjs.
    ],
    spend: { limit_dollars: 999, used_dollars: 123 }
  }
})

const claudeMeter = (seat, overrides = {}) => ({
  schema_version: "seat-meter/1",
  seat,
  owner: "tom",
  grade: "MEASURED",
  observed_at: "2026-09-23T04:53:00Z",
  reading_observed_at: "2026-09-23T04:52:18Z",
  reading_age_seconds: 42,
  source: { kind: "oauth-usage-endpoint", reader: "stamp-receipt.py window", seat, source_observed_at: "2026-09-23T04:52:18Z" },
  utilization_pct: 8,
  weekly_utilization_pct: 72,
  window: {
    kind: "nested",
    primary: { minutes: 300, resets_at: "2026-09-23T08:49:59.526442+00:00", utilization_pct: 8 },
    secondary: { minutes: 10080, resets_at: "2026-09-23T09:59:59.526461+00:00", utilization_pct: 72 }
  },
  ...overrides
})

const fleet = () => {
  const dir = mkdtempSync(join(tmpdir(), "seat-pusher-"))
  const meters = join(dir, "meters")
  mkdirSync(meters)
  const put = (name, value) => writeFileSync(join(meters, name), `${JSON.stringify(value)}\n`)
  put("cc.json", claudeMeter("cc"))
  put(".window-cache-cc.json", ccCache())
  put("cc2.json", claudeMeter("cc2", { grade: "STALE-MEASURED", stale_reason: "the reader could not be run: TimeoutExpired" }))
  put(".window-cache-cc2.json", ccCache(OBSERVED, 81))
  put("cc3.json", claudeMeter("cc3", {
    stale_reason: "token expired",
    reading_observed_at: "2026-09-11T15:15:00Z",
    source: { kind: "oauth-usage-endpoint", seat: "cc3", source_observed_at: "2026-09-11T15:15:00Z" },
    window: { kind: "nested", primary: { minutes: 300, resets_at: "2026-09-11T19:00:00Z", utilization_pct: 12 }, secondary: { minutes: 10080, resets_at: "2026-09-12T11:00:00.199042+00:00", utilization_pct: 80 } }
  }))
  put("codex.json", {
    schema_version: "seat-meter/1", seat: "codex", owner: "third-party", grade: "MEASURED", observed_at: "2026-09-23T04:52:18Z",
    source: { kind: "codex-rollout-rate-limits", path: "/elsewhere/rollout.jsonl" },
    window: { kind: "rolling", minutes: 10080, resets_at: "2026-09-28T19:07:31Z", utilization_pct: 3 }
  })
  put("pi-qwencloud.json", {
    schema_version: "exp002-meter/1", seat: "pi-qwencloud", owner: "tom", observed_at: "2026-09-23T04:52:18Z",
    capacity: { grade: "UNKNOWN", reason: "TL-17 is unset" },
    source: { hold_record: "/elsewhere/pi-hold.json", kind: "unavailable" },
    window: "UNKNOWN", window_reason: "the hold record at /home/someone/plan/pi-hold.json is not held"
  })
  put("gpu-worker.json", {
    schema_version: "seat-meter/1", seat: "gpu-worker", owner: "kernel", observed_at: "2026-09-23T04:47:32.509Z",
    holders: 0, capacity: 1, running_grade: "MEASURED", window: { kind: "none" }
  })
  put("mechanical.json", { schema_version: "seat-meter/1", seat: "mechanical", owner: "kernel", observed_at: "2026-09-23T04:47:32.509Z", window: { kind: "none" } })
  writeFileSync(join(meters, "broken.json"), "{")
  return { dir, meters, capacity: join(dir, "capacity"), state: join(dir, "capacity", "pusher-state.json") }
}

const config = () => readConfig(EXAMPLE_CONFIG)
const build = (paths, now = NOW) =>
  buildSnapshot({ metersDir: paths.meters, capacityDir: paths.capacity, config: config(), now, list: readdirSync(paths.meters) })

describe("building the snapshot from today's meter shapes", () => {
  it("decodes against the lake's schema and classifies every seat", () => {
    const paths = fleet()
    const { snapshot, skipped } = build(paths)
    const decoded = decodeSnapshot(snapshot)
    expect(decoded.seats.map((seat) => [seat.seat, seat.provider, seat.dispatchable, seat.dispatchable_reason])).toEqual([
      ["cc", "claude", true, null],
      ["cc2", "claude", true, null],
      ["cc3", "claude", false, "evicted"],
      ["codex", "codex", false, "third-party"],
      ["gpu-worker", "halogen", true, null],
      ["pi-qwencloud", "qwen", true, null]
    ])
    expect(skipped).toEqual([
      { seat: "broken", reason: "unreadable: SyntaxError" },
      { seat: "mechanical", reason: "not a compute seat this pusher knows" }
    ])
  })

  it("carries the model-scoped Fable row from the usage cache, and the provider's instant", () => {
    const cc = build(fleet()).snapshot.seats.find((seat) => seat.seat === "cc")
    expect(cc.observed_at).toBe(OBSERVED)
    expect(cc.windows.map((window) => [window.kind, window.model, window.utilization_pct, window.severity])).toEqual([
      ["five_hour", null, 8, "normal"],
      ["seven_day", null, 72, "normal"],
      ["model_scoped", "Fable", 100, "critical"]
    ])
  })

  it("never copies spend, or anything else outside limits[], from the cache", () => {
    const text = JSON.stringify(build(fleet()).snapshot)
    expect(text).not.toMatch(/spend|dollars|123|999/)
    expect(text).not.toContain("/elsewhere/")
  })

  it("a STALE-MEASURED row is a MEASURED reading that has aged; the lake judges its age", () => {
    const cc2 = build(fleet()).snapshot.seats.find((seat) => seat.seat === "cc2")
    expect(cc2.grade).toBe("MEASURED")
    expect(cc2.stale_reason).toBe("the reader could not be run: TimeoutExpired")
  })

  it("falls back to the meter row when the cache is older than the reading", () => {
    const paths = fleet()
    writeFileSync(join(paths.meters, ".window-cache-cc.json"), JSON.stringify(ccCache("2026-09-23T03:00:00Z")))
    const cc = build(paths).snapshot.seats.find((seat) => seat.seat === "cc")
    expect(cc.source.detail).toBe("meter row window")
    expect(cc.observed_at).toBe("2026-09-23T04:52:18Z")
    // The cache's model rows are carried forward as UNKNOWN (review round 1).
    expect(cc.windows.map((window) => window.kind)).toEqual(["five_hour", "seven_day", "model_scoped"])
    expect(cc.model_windows_complete).toBe(false)
  })

  it("an auth failure makes a seat not dispatchable even without a config ruling", () => {
    const paths = fleet()
    // cc3 is ruled out by the built-in rulings; cc2 carries the auth failure here.
    writeFileSync(join(paths.meters, "cc2.json"), JSON.stringify(claudeMeter("cc2", { stale_reason: "token expired" })))
    const { snapshot } = buildSnapshot({
      metersDir: paths.meters, capacityDir: null, config: readConfig(null), now: NOW, list: readdirSync(paths.meters)
    })
    const cc2 = snapshot.seats.find((seat) => seat.seat === "cc2")
    expect([cc2.dispatchable, cc2.dispatchable_reason]).toEqual([false, "auth-failed"])
    expect(snapshot.seats.find((seat) => seat.seat === "pi-qwencloud").plan).toBeNull()
  })

  it("prefers the feeder's own seats.json when it writes one", () => {
    const paths = fleet()
    mkdirSync(paths.capacity, { recursive: true })
    const written = { ...build(paths).snapshot, host: "from-feeder", seats: [] }
    writeFileSync(join(paths.capacity, "seats.json"), JSON.stringify(written))
    expect(build(paths)).toMatchObject({ source: "seats.json", snapshot: { host: "from-feeder" } })
  })

  it("carries the qwen plan end from the config file", () => {
    const qwen = build(fleet()).snapshot.seats.find((seat) => seat.seat === "pi-qwencloud")
    expect(qwen.plan).toEqual({ expires_at: "2026-11-07T00:00:00Z" })
    expect(qwen.windows).toEqual([])
    expect(qwen.stale_reason).toBe("the hold record at <path> is not held")
  })
})

describe("the refresh policy", () => {
  const minute = 60_000
  const at = Date.parse(NOW)

  it("pushes the first time, then only on a changed reading or the 30 minute heartbeat", () => {
    const paths = fleet()
    const first = build(paths).snapshot
    expect(decidePush({}, first, at)).toMatchObject({ push: true, reason: "changed" })
    const state = stateAfterPush(first, NOW)
    // A restamp: the meter row's observed_at moves, the reading does not.
    writeFileSync(join(paths.meters, "cc.json"), JSON.stringify(claudeMeter("cc", { observed_at: "2026-09-23T04:55:00Z" })))
    const restamped = build(paths, new Date(at + 5 * minute).toISOString()).snapshot
    expect(decidePush(state, restamped, at + 5 * minute)).toMatchObject({ push: false, reason: "unchanged" })
    expect(decidePush(state, restamped, at + 30 * minute)).toMatchObject({ push: true, reason: "heartbeat" })
    // A new reading on one seat.
    writeFileSync(join(paths.meters, ".window-cache-cc.json"), JSON.stringify(ccCache("2026-09-23T04:57:18Z")))
    const read = build(paths, new Date(at + 5 * minute).toISOString()).snapshot
    expect(decidePush(state, read, at + 5 * minute)).toMatchObject({ push: true, reason: "changed", changed: ["cc"] })
  })

  it("never pushes twice within the minimum interval, and notices a removed seat", () => {
    const snapshot = build(fleet()).snapshot
    const state = stateAfterPush(snapshot, NOW)
    const fewer = { ...snapshot, seats: snapshot.seats.slice(1) }
    expect(decidePush(state, fewer, at + 30_000)).toMatchObject({ push: false, reason: "min-interval" })
    expect(decidePush(state, fewer, at + 2 * minute)).toMatchObject({ push: true, changed: ["cc"] })
  })

  it("the fingerprint ignores how an instant is spelled", () => {
    const cc = build(fleet()).snapshot.seats[0]
    expect(fingerprint({ ...cc, observed_at: "2026-09-23T06:52:18.363+02:00" })).toBe(
      fingerprint({ ...cc, observed_at: "2026-09-23T04:52:18.363Z" })
    )
  })
})

describe("pushing", () => {
  const recorder = (status = 200, body = { results: [], changed: true }) => {
    const calls = []
    const fetchImpl = async (url, init) => {
      calls.push({ url, init })
      return new Response(JSON.stringify(body), { status })
    }
    return { calls, fetchImpl }
  }
  const pass = (paths, fetchImpl, now = NOW) =>
    runOnce({
      metersDir: paths.meters, capacityDir: paths.capacity, statePath: paths.state, config: config(),
      base: "https://lake.invalid/", token: "secret-token-value", now: () => now,
      list: readdirSync(paths.meters), fetchImpl
    })

  it("posts once, keeps a 0600 state, and posts nothing on the next pass", async () => {
    const paths = fleet()
    const { calls, fetchImpl } = recorder()
    expect((await pass(paths, fetchImpl)).pushed).toBe(true)
    expect(calls).toHaveLength(1)
    expect(calls[0].url).toBe("https://lake.invalid/capacity/seats")
    expect(calls[0].init.headers.authorization).toBe("Bearer secret-token-value")
    expect(statSync(paths.state).mode & 0o777).toBe(0o600)
    const second = await pass(paths, fetchImpl, "2026-09-23T04:58:18.000Z")
    expect(second).toMatchObject({ pushed: false, decision: { reason: "unchanged" } })
    expect(calls).toHaveLength(1)
  })

  it("a refused push keeps no state and never prints the token", async () => {
    const paths = fleet()
    const { fetchImpl } = recorder(401, { error: "Unauthorized" })
    const failure = await pass(paths, fetchImpl).then(() => null, (error) => error)
    expect(failure.message).toContain("401")
    expect(failure.message).not.toContain("secret-token-value")
    expect(readState(paths.state)).toEqual({})
  })

  it("round trip: the pusher's snapshot lands in the real Factory handler and answers admission", async () => {
    const paths = fleet()
    const factory = await emptyFactory()
    const handler = makeFactoryHttpHandler({
      factory,
      token: "secret-token-value",
      artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]]),
      now: () => NOW
    })
    const fetchImpl = (url, init) => handler(new Request(url, init))
    const result = await pass(paths, fetchImpl)
    expect(result.results.every((entry) => entry.outcome === "accepted")).toBe(true)
    const ask = async (query) => (await handler(new Request(`https://lake.invalid/capacity/admit?${query}`))).json()
    expect(await ask("seat=cc&model=Opus")).toMatchObject({ admit: true, headroom_pct: 28 })
    expect(await ask("seat=cc&model=Fable")).toMatchObject({ admit: false, reason: "severity-critical" })
    expect(await ask("seat=cc2&model=Fable")).toMatchObject({ admit: true, signal: "SLOW" })
    expect(await ask("seat=cc3&model=Opus")).toMatchObject({ admit: false, reason: "not-dispatchable" })
    expect(await ask("seat=codex")).toMatchObject({ admit: false, reason: "not-dispatchable" })
    expect(await ask("seat=pi-qwencloud")).toMatchObject({ admit: false, reason: "unknown" })
    expect(await ask("seat=gpu-worker")).toMatchObject({ admit: true })
    // A repeat pass with --force is idempotent at the lake.
    const again = await runOnce({
      metersDir: paths.meters, capacityDir: paths.capacity, statePath: paths.state, config: config(),
      base: "https://lake.invalid", token: "secret-token-value", now: () => NOW,
      list: readdirSync(paths.meters), fetchImpl, force: true
    })
    expect(again.results.every((entry) => entry.outcome === "duplicate")).toBe(true)
  })
})

describe("the CLI", () => {
  it("--dry-run prints the snapshot and touches no network and no state", () => {
    const paths = fleet()
    const run = spawnSync(process.execPath, [PUSHER, "--dry-run", "--meters", paths.meters, "--capacity-dir", "", "--config", EXAMPLE_CONFIG], { encoding: "utf8" })
    expect(run.status).toBe(0)
    const out = JSON.parse(run.stdout)
    expect(out.pushed).toBe(false)
    expect(out.snapshot.schema_version).toBe("seat-capacity/2")
    expect(out.snapshot.host).toBe("coordinator")
    expect(() => statSync(paths.state)).toThrow()
  })

  it("refuses to run without a url and a token file", () => {
    const run = spawnSync(process.execPath, [PUSHER], { encoding: "utf8" })
    expect(run.status).toBe(2)
    expect(run.stderr).toContain("--url and --token-file are required")
  })
})

describe("review round 1: the pusher never drops a model limit silently", () => {
  const FABLE = { model: "Fable", min_headroom_pct: 0 }
  const ANY = { model: null, min_headroom_pct: 0 }
  const AT = "2026-09-23T04:53:30Z"
  const ccOf = (paths) => decodeSnapshot(build(paths).snapshot).seats.find((seat) => seat.seat === "cc")

  it("the usage cache read from the same provider call states every model limit", () => {
    const cc = ccOf(fleet())
    expect(cc.model_windows_complete).toBe(true)
    expect(admitSeat("cc", cc, { model: "Opus", min_headroom_pct: 0 }, AT).admit).toBe(true)
  })

  it("a meter row newer than the cache carries the Fable row forward as UNKNOWN and refuses Fable", () => {
    const paths = fleet()
    // The cache (and its Fable row at 100 percent critical) is from 04:40; the
    // meter row's provider read is 04:52:18 (the feeder tests' shape).
    writeFileSync(join(paths.meters, ".window-cache-cc.json"), JSON.stringify(ccCache("2026-09-23T04:40:00Z")))
    const cc = ccOf(paths)
    expect(cc.model_windows_complete).toBe(false)
    expect(cc.windows.find((window) => window.kind === "model_scoped")).toMatchObject({
      model: "Fable",
      utilization_pct: null,
      severity: null,
      grade: "UNKNOWN"
    })
    expect(admitSeat("cc", cc, FABLE, AT)).toMatchObject({ admit: false, reason: "window-unknown", raise_demand: true })
    expect(admitSeat("cc", cc, ANY, AT).admit).toBe(true)
  })

  it("a cache 1 s behind the meter row refuses Fable", () => {
    const paths = fleet()
    writeFileSync(join(paths.meters, ".window-cache-cc.json"), JSON.stringify(ccCache("2026-09-23T04:52:17Z")))
    writeFileSync(join(paths.meters, "cc.json"), JSON.stringify(claudeMeter("cc", {
      reading_observed_at: "2026-09-23T04:52:18Z",
      source: { kind: "oauth-usage-endpoint", source_observed_at: "2026-09-23T04:52:18Z" }
    })))
    expect(admitSeat("cc", ccOf(paths), FABLE, AT)).toMatchObject({ admit: false, reason: "window-unknown" })
  })

  it("a torn (unparseable) or missing cache refuses every model job and still admits a job for no model", () => {
    for (const cache of ['{"observed_at": "2026-09-23T04:52:18.365', null]) {
      const paths = fleet()
      const cachePath = join(paths.meters, ".window-cache-cc.json")
      if (cache === null) rmSync(cachePath)
      else writeFileSync(cachePath, cache)
      const cc = ccOf(paths)
      expect(cc.model_windows_complete).toBe(false)
      expect(cc.windows.map((window) => window.kind)).toEqual(["five_hour", "seven_day"])
      expect(admitSeat("cc", cc, FABLE, AT)).toMatchObject({ admit: false, reason: "window-unknown" })
      expect(admitSeat("cc", cc, { model: "Opus", min_headroom_pct: 0 }, AT)).toMatchObject({ admit: false, reason: "window-unknown" })
      expect(admitSeat("cc", cc, ANY, AT).admit).toBe(true)
    }
  })
})

describe("review round 1: the ruled seats are never dispatchable, config or not", () => {
  const withCoordinatorGpu = () => {
    const paths = fleet()
    writeFileSync(join(paths.meters, "gpu-coordinator.json"), JSON.stringify({
      schema_version: "seat-meter/1", seat: "gpu-coordinator", owner: "kernel", observed_at: "2026-09-23T04:52:18Z",
      holders: 0, capacity: 1, running_grade: "MEASURED", window: { kind: "none" }
    }))
    // cc3 after a re-login: no auth failure left to catch it.
    writeFileSync(join(paths.meters, "cc3.json"), JSON.stringify(claudeMeter("cc3")))
    writeFileSync(join(paths.meters, ".window-cache-cc3.json"), JSON.stringify(ccCache()))
    return paths
  }
  const dispatch = (snapshot) =>
    Object.fromEntries(snapshot.seats.map((seat) => [seat.seat, [seat.dispatchable, seat.dispatchable_reason]]))

  it("with no config file, cc3 and gpu-coordinator are published not dispatchable and refused", () => {
    const paths = withCoordinatorGpu()
    const { snapshot } = buildSnapshot({
      metersDir: paths.meters, capacityDir: null, config: readConfig(null), now: NOW, list: readdirSync(paths.meters)
    })
    const seats = decodeSnapshot(snapshot).seats
    expect(dispatch(snapshot)["cc3"]).toEqual([false, "evicted"])
    expect(dispatch(snapshot)["gpu-coordinator"][0]).toBe(false)
    for (const id of ["cc3", "gpu-coordinator"]) {
      expect(admitSeat(id, seats.find((seat) => seat.seat === id), { model: null, min_headroom_pct: 0 }, NOW)).toMatchObject({
        admit: false,
        reason: "not-dispatchable"
      })
    }
  })

  it("a config can extend the rulings but never lift one", () => {
    const dir = mkdtempSync(join(tmpdir(), "seat-config-"))
    const path = join(dir, "seat-capacity.json")
    writeFileSync(path, JSON.stringify({ not_dispatchable: { cc3: null, "gpu-coordinator": false, cc2: "paused" } }))
    const ruled = readConfig(path).notDispatchable
    expect(typeof ruled.cc3).toBe("string")
    expect(typeof ruled["gpu-coordinator"]).toBe("string")
    expect(ruled.cc2).toBe("paused")
  })

  it("the feeder's seats.json is held to the same rulings, seat filter and path scrub", () => {
    const paths = fleet()
    mkdirSync(paths.capacity, { recursive: true })
    const built = build(paths).snapshot
    const written = {
      ...built,
      seats: built.seats.map((seat) =>
        seat.seat === "cc3"
          ? { ...seat, dispatchable: true, dispatchable_reason: null, stale_reason: "read /home/tom/.claude/x failed" }
          : seat
      )
    }
    writeFileSync(join(paths.capacity, "seats.json"), JSON.stringify(written))
    const cfg = { ...readConfig(EXAMPLE_CONFIG), seats: ["cc", "cc3"] }
    const { snapshot, source } = buildSnapshot({
      metersDir: paths.meters, capacityDir: paths.capacity, config: cfg, now: NOW, list: readdirSync(paths.meters)
    })
    expect(source).toBe("seats.json")
    expect(snapshot.seats.map((seat) => seat.seat)).toEqual(["cc", "cc3"])
    const cc3 = snapshot.seats.find((seat) => seat.seat === "cc3")
    expect([cc3.dispatchable, cc3.dispatchable_reason]).toEqual([false, "evicted"])
    expect(cc3.stale_reason).toBe("read <path> failed")
    expect(() => decodeSnapshot(snapshot)).not.toThrow()
  })

  it("--dry-run reads the same default config path as a real run", () => {
    const paths = fleet()
    const home = mkdtempSync(join(tmpdir(), "seat-home-"))
    mkdirSync(join(home, ".config", "substrate"), { recursive: true })
    writeFileSync(join(home, ".config", "substrate", "seat-capacity.json"), JSON.stringify({ host: "from-default-config" }))
    const run = spawnSync(process.execPath, [PUSHER, "--dry-run", "--meters", paths.meters, "--capacity-dir", ""], {
      encoding: "utf8",
      env: { ...process.env, HOME: home }
    })
    expect(run.status).toBe(0)
    expect(JSON.parse(run.stdout).snapshot.host).toBe("from-default-config")
  })
})

describe("review round 1: a restamp is not a change for any provider", () => {
  const minute = 60_000
  const at = Date.parse(NOW)
  const restampAll = (paths, instant) => {
    for (const name of ["codex.json", "pi-qwencloud.json", "gpu-worker.json"]) {
      const path = join(paths.meters, name)
      const row = JSON.parse(readFileSync(path, "utf8"))
      writeFileSync(path, JSON.stringify({ ...row, observed_at: instant }))
    }
  }

  it("moving only the codex, qwen and halogen rows' observed_at does not push", () => {
    const paths = fleet()
    const first = build(paths).snapshot
    const state = stateAfterPush(first, NOW)
    restampAll(paths, "2026-09-23T04:57:48Z")
    const later = build(paths, new Date(at + 5 * minute).toISOString()).snapshot
    expect(decidePush(state, later, at + 5 * minute)).toMatchObject({ push: false, reason: "unchanged" })
    // No provider instant exists in those rows; the snapshot says so.
    for (const id of ["codex", "pi-qwencloud"]) {
      expect(later.seats.find((seat) => seat.seat === id).source.detail).toBe("observed_at is the feeder's read instant")
    }
  })

  it("a changed codex utilization or halogen holder count still pushes", () => {
    const paths = fleet()
    const state = stateAfterPush(build(paths).snapshot, NOW)
    const path = join(paths.meters, "gpu-worker.json")
    writeFileSync(path, JSON.stringify({ ...JSON.parse(readFileSync(path, "utf8")), holders: 1 }))
    expect(decidePush(state, build(paths).snapshot, at + 2 * minute)).toMatchObject({ push: true, changed: ["gpu-worker"] })
  })

  it("a dispatchable slot row is re-sent before the lake would grade it STALE (1200 s)", () => {
    const paths = fleet()
    const state = stateAfterPush(build(paths).snapshot, NOW)
    restampAll(paths, "2026-09-23T05:03:18Z")
    const snapshot = build(paths).snapshot
    expect(decidePush(state, snapshot, at + 9 * minute)).toMatchObject({ push: false })
    expect(decidePush(state, snapshot, at + 10 * minute)).toMatchObject({ push: true, reason: "heartbeat" })
    // Without a dispatchable slot row, the 1800 s heartbeat stands.
    const noSlots = { ...snapshot, seats: snapshot.seats.filter((seat) => seat.provider !== "halogen") }
    const stateNoSlots = stateAfterPush({ ...build(paths).snapshot, seats: noSlots.seats }, NOW)
    expect(decidePush(stateNoSlots, noSlots, at + 10 * minute)).toMatchObject({ push: false, reason: "unchanged" })
  })
})
