// The Claude usage source: the direct reader under the refresh policy, the
// cache-file adapter, and a snapshot built with no tally path at all.
import { spawnSync } from "node:child_process"
import { mkdirSync, mkdtempSync, readFileSync, statSync, utimesSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { Schema } from "effect"
import { describe, expect, it } from "vitest"

import { SeatCapacitySnapshot } from "@substrate/planning/schema/seatCapacity.ts"
import { admitSeat } from "@substrate/planning/capacity/project.ts"
import { buildSnapshot, defaultConfigPath, defaultPusherDir, readConfig, runOnce } from "../src/seatCapacity.mjs"
import {
  bearerFromCredentials,
  defaultUsageDir,
  readSeatUsage,
  USAGE_ENDPOINT,
  windowsFromUsage
} from "../src/usageSource.mjs"

const decode = Schema.decodeUnknownSync(SeatCapacitySnapshot)
const PUSHER = fileURLToPath(new URL("../bin/seat-pusher.mjs", import.meta.url))
const FAKE = "fake-bearer-for-tests-only"
const T0 = Date.parse("2026-09-23T06:00:00Z")

// The endpoint's answer shape as MEASURED in the feeder cache (SCOUT.md section 2); values synthetic.
const answer = (fable = 100) => ({
  five_hour: { utilization: 8, resets_at: "2026-09-23T08:49:59.526442+00:00" },
  seven_day: { utilization: 72, resets_at: "2026-09-23T09:59:59.526461+00:00" },
  limits: [
    { kind: "session", percent: 8, severity: "normal", resets_at: "2026-09-23T08:49:59.526442+00:00", scope: null },
    { kind: "weekly_all", percent: 72, severity: "normal", resets_at: "2026-09-23T09:59:59.526461+00:00", scope: null },
    { kind: "weekly_scoped", percent: fable, severity: "critical", resets_at: "2026-09-23T09:59:59.526615+00:00", scope: { model: { id: null, display_name: "Fable" } } }
  ],
  spend: { limit_dollars: 999, used_dollars: 123 }
})

const box = () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-source-"))
  const credentials = join(dir, "credentials.json")
  writeFileSync(credentials, JSON.stringify({ claudeAiOauth: { accessToken: FAKE } }))
  return { dir, credentials, usageDir: join(dir, "usage"), demandDir: join(dir, "demand") }
}

const fakeFetch = (responses) => {
  const calls = []
  const impl = async (url, init) => {
    calls.push({ url, init })
    const next = responses.shift() ?? { status: 200, body: answer() }
    return {
      status: next.status,
      headers: { get: (name) => (name === "retry-after" ? (next.retryAfter ?? null) : null) },
      text: async () => JSON.stringify(next.body ?? {})
    }
  }
  return { impl, calls }
}

const read = (b, fetchImpl, nowMs, extra = {}) =>
  readSeatUsage({
    seat: "cc",
    source: { kind: "oauth", credentials: b.credentials },
    usageDir: b.usageDir,
    demandDir: b.demandDir,
    nowMs,
    fetchImpl,
    ...extra
  })

describe("windowsFromUsage", () => {
  it("maps limits[] to five_hour, seven_day and a model-scoped row", () => {
    const windows = windowsFromUsage(answer())
    expect(windows.map((w) => [w.kind, w.model, w.utilization_pct])).toEqual([
      ["five_hour", null, 8],
      ["seven_day", null, 72],
      ["model_scoped", "Fable", 100]
    ])
  })
  it("falls back to the flat pair when limits[] is absent", () => {
    const { limits, ...flat } = answer()
    expect(windowsFromUsage(flat).map((w) => [w.kind, w.utilization_pct])).toEqual([
      ["five_hour", 8],
      ["seven_day", 72]
    ])
  })
})

describe("bearerFromCredentials", () => {
  it("reads the pointer and never puts the value in an error", () => {
    const b = box()
    expect(bearerFromCredentials(b.credentials)).toBe(FAKE)
    let message = ""
    try {
      bearerFromCredentials(b.credentials, ["claudeAiOauth", "refreshToken"])
    } catch (error) {
      message = error.message
    }
    expect(message).toMatch(/refreshToken/)
    expect(message).not.toContain(FAKE)
  })
})

describe("the direct reader", () => {
  it("reads once, sends the bearer only in the header, caches 0600 without spend", async () => {
    const b = box()
    const f = fakeFetch([{ status: 200, body: answer() }])
    const r = await read(b, f.impl, T0)
    expect(r.attempted).toBe(true)
    expect(f.calls).toHaveLength(1)
    expect(f.calls[0].url).toBe(USAGE_ENDPOINT)
    expect(f.calls[0].init.headers.authorization).toBe(`Bearer ${FAKE}`)
    expect(f.calls[0].init.headers["anthropic-beta"]).toBe("oauth-2025-04-20")
    const cache = readFileSync(join(b.usageDir, "cc.json"), "utf8")
    expect(cache).not.toContain("spend")
    expect(cache).not.toContain(FAKE)
    expect(readFileSync(join(b.usageDir, "cc.state.json"), "utf8")).not.toContain(FAKE)
    expect(statSync(join(b.usageDir, "cc.json")).mode & 0o777).toBe(0o600)
    expect(r.reading.observed_at).toBe(new Date(T0).toISOString())
  })

  it("is gentle: no second call inside the idle floor, one at 900 s, 300 s when active", async () => {
    const b = box()
    const f = fakeFetch([])
    await read(b, f.impl, T0)
    for (const after of [30, 119, 120, 600, 899]) await read(b, f.impl, T0 + after * 1000)
    expect(f.calls).toHaveLength(1)
    const idle = await read(b, f.impl, T0 + 900_000)
    expect(idle.decision.reason).toBe("idle")
    expect(f.calls).toHaveLength(2)
    mkdirSync(b.demandDir, { recursive: true })
    writeFileSync(join(b.demandDir, "cc"), "")
    const markerAt = (T0 + 1_200_000) / 1000
    utimesSync(join(b.demandDir, "cc"), markerAt, markerAt)
    const active = await read(b, f.impl, T0 + 1_200_000)
    expect(active.decision.reason).toBe("active")
    expect(f.calls).toHaveLength(3)
  })

  it("backs off after a 429, honouring Retry-After, and keeps serving the cached reading", async () => {
    const b = box()
    const f = fakeFetch([{ status: 200, body: answer() }, { status: 429, retryAfter: "1500" }])
    await read(b, f.impl, T0)
    const limited = await read(b, f.impl, T0 + 900_000)
    expect(limited.attempted).toBe(true)
    expect(limited.error).toMatch(/429/)
    expect(limited.reading.observed_at).toBe(new Date(T0).toISOString())
    await read(b, f.impl, T0 + (900 + 1499) * 1000)
    expect(f.calls).toHaveLength(2)
    await read(b, f.impl, T0 + (900 + 1500) * 1000)
    expect(f.calls).toHaveLength(3)
  })

  it("after an auth failure, calls again only once the credentials file changes", async () => {
    const b = box()
    const f = fakeFetch([{ status: 401 }])
    const failed = await read(b, f.impl, T0)
    expect(failed.error).toMatch(/401/)
    await read(b, f.impl, T0 + 86_400_000)
    expect(f.calls).toHaveLength(1)
    const later = (T0 + 90_000_000) / 1000
    utimesSync(b.credentials, later, later)
    await read(b, f.impl, T0 + 90_000_000)
    expect(f.calls).toHaveLength(2)
  })

  it("a dry run never calls the network, even with a first read due", async () => {
    const b = box()
    const f = fakeFetch([])
    const config = readConfig(null)
    config.usage = { cc: { kind: "oauth", credentials: b.credentials } }
    const dry = await runOnce({
      metersDir: null,
      capacityDir: null,
      statePath: join(b.dir, "state.json"),
      config,
      base: "",
      token: "",
      now: () => new Date(T0).toISOString(),
      fetchImpl: f.impl,
      dryRun: true,
      usageDir: b.usageDir,
      demandDir: b.demandDir
    })
    expect(f.calls).toHaveLength(0)
    expect(dry.skipped.map((entry) => entry.seat)).toEqual(["cc"])
  })

  it("never calls the network when told not to", async () => {
    const b = box()
    const f = fakeFetch([])
    const r = await read(b, f.impl, T0, { allowNetwork: false })
    expect(f.calls).toHaveLength(0)
    expect(r.reading).toBeNull()
  })
})

describe("the snapshot without tally-rewrite", () => {
  it("builds from usage sources alone, decodes, and admission honours the model-scoped row", async () => {
    const b = box()
    const cacheFile = join(b.dir, "feeder-cache.json")
    writeFileSync(cacheFile, JSON.stringify({ observed_at: "2026-09-23T05:59:00Z", usage: answer(81) }))
    const config = readConfig(null)
    config.host = "coordinator"
    config.usage = { cc: { kind: "oauth", credentials: b.credentials }, cc2: { kind: "cache-file", path: cacheFile } }
    const f = fakeFetch([{ status: 200, body: answer(100) }])
    const result = await runOnce({
      metersDir: null,
      capacityDir: null,
      statePath: join(b.dir, "state.json"),
      config,
      base: "http://floor.invalid",
      token: "floor-token",
      now: () => new Date(T0).toISOString(),
      fetchImpl: f.impl,
      dryRun: false,
      usageDir: b.usageDir,
      demandDir: b.demandDir
    }).catch((error) => ({ error: error.message }))
    // The push itself fails against the fake (it answers usage JSON, not the floor's);
    // what matters here is the usage read, below, and the dry-run snapshot.
    expect(f.calls[0].url).toBe(USAGE_ENDPOINT)
    const dry = await runOnce({
      metersDir: null,
      capacityDir: null,
      statePath: join(b.dir, "state.json"),
      config,
      base: "",
      token: "",
      now: () => new Date(T0 + 1000).toISOString(),
      fetchImpl: f.impl,
      dryRun: true,
      usageDir: b.usageDir,
      demandDir: b.demandDir
    })
    expect(result).toBeDefined()
    expect(f.calls).toHaveLength(2) // the failed push, never a second usage read
    expect(dry.source).toBe("usage")
    const snapshot = decode(dry.snapshot)
    expect(snapshot.seats.map((seat) => [seat.seat, seat.source.detail])).toEqual([
      ["cc", "direct read"],
      ["cc2", "usage cache file"]
    ])
    expect(JSON.stringify(snapshot)).not.toContain("spend")
    const asOf = new Date(T0 + 2000).toISOString()
    const cc = snapshot.seats[0]
    expect(admitSeat("cc", cc, { model: "opus-class", min_headroom_pct: 0 }, asOf).admit).toBe(true)
    expect(admitSeat("cc", cc, { model: "Fable", min_headroom_pct: 0 }, asOf).admit).toBe(false)
    expect(cc.model_windows_complete).toBe(true)
  })

  it("a reading without limits[] does not claim every model limit, so a model job is refused", () => {
    const b = box()
    const { limits, ...flat } = answer()
    const cacheFile = join(b.dir, "flat.json")
    writeFileSync(cacheFile, JSON.stringify({ observed_at: new Date(T0).toISOString(), usage: flat }))
    const config = readConfig(null)
    config.usage = { cc: { kind: "cache-file", path: cacheFile } }
    const usage = { cc: { reading: { observed_at: new Date(T0).toISOString(), usage: flat }, error: null } }
    const seat = decode(buildSnapshot({ config, now: new Date(T0).toISOString(), usage }).snapshot).seats[0]
    expect(seat.model_windows_complete).toBe(false)
    const asOf = new Date(T0 + 1000).toISOString()
    const refused = admitSeat("cc", seat, { model: "Fable", min_headroom_pct: 0 }, asOf)
    expect(refused.admit).toBe(false)
    expect(refused.reason).toBe("window-unknown")
    expect(admitSeat("cc", seat, { model: null, min_headroom_pct: 0 }, asOf).admit).toBe(true)
  })

  it("the example configs name no real credentials path (tests load the first one)", () => {
    const example = fileURLToPath(new URL("../seat-capacity.example.json", import.meta.url))
    expect(readConfig(example).usage).toEqual({})
    const usageExample = readConfig(fileURLToPath(new URL("../seat-capacity.usage.example.json", import.meta.url)))
    for (const source of Object.values(usageExample.usage)) {
      for (const value of Object.values(source)) expect(String(value).startsWith("/")).toBe(false)
    }
  })

  it("names no tally path in any default", () => {
    for (const path of [defaultConfigPath(), defaultPusherDir(), defaultUsageDir()]) {
      expect(path).not.toMatch(/tally/)
    }
    const built = buildSnapshot({ config: readConfig(null), now: new Date(T0).toISOString(), list: ["cc.json"] })
    expect(built.snapshot.seats).toEqual([])
  })

  it("the CLI dry run reads a cache-file source and calls no network", () => {
    const b = box()
    const cacheFile = join(b.dir, "cache.json")
    writeFileSync(cacheFile, JSON.stringify({ observed_at: "2026-09-23T05:59:00Z", usage: answer() }))
    const configPath = join(b.dir, "config.json")
    writeFileSync(configPath, JSON.stringify({ host: "coordinator", usage: { cc: { kind: "cache-file", path: cacheFile } } }))
    const run = spawnSync(process.execPath, [PUSHER, "--dry-run", "--config", configPath], { encoding: "utf8" })
    expect(run.status).toBe(0)
    const out = JSON.parse(run.stdout)
    expect(out.pushed).toBe(false)
    expect(decode(out.snapshot).seats.map((seat) => seat.seat)).toEqual(["cc"])
  })
})
