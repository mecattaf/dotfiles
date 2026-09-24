// apps/uplink/src/seatCapacity.mjs: EVAL-CAPACITY. The seat-capacity pusher's
// library: build a `seat-capacity/2` snapshot from the feeders' files, decide
// whether it is worth sending, and send it outbound.
//
// THREE CLOCKS, KEPT APART (SCOUT.md, evals-2026-09-23/capacity). The feeder
// restamps meter rows every 30 s for the kernel; the provider is read far less
// often; the lake projects from the last reading. This module sits between the
// first two and the third: it reads LOCAL FILES ONLY and never calls a
// provider, so running it often costs nothing upstream. What it carries is the
// instant the PROVIDER answered (`observed_at`), never the restamp.
//
// SOURCES, IN ORDER OF AUTHORITY:
//   1. `<capacity-dir>/seats.json`, when the feeder writes the snapshot itself
//      (the proposed feeder change, not yet applied): carried as it is.
//   2. The meters directory: `<seat>.json` rows, and for a Claude seat the raw
//      usage cache `.window-cache-<seat>.json` beside it, which is the only
//      place the model-scoped rows (`weekly_scoped`, e.g. Fable) appear. Only
//      the `limits[]` rows and `observed_at` are read from the cache; nothing
//      else in it is copied anywhere.
//
// WHAT IT REFUSES TO INVENT. A cell the file does not state stays null
// (UNKNOWN, never headroom); a meter this module cannot classify is skipped
// with a named reason rather than guessed into a provider.

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { homedir, hostname } from "node:os"
import { dirname, join } from "node:path"

import { limitsComplete, readSeatUsage, windowsFromLimits, windowsFromUsage } from "./usageSource.mjs"

const SCHEMA_VERSION = "seat-capacity/2"

const MINUTES = { five_hour: 300, seven_day: 10080, model_scoped: 10080 }

/** The pusher's own state; nothing under a tally path is a default any more. */
export const defaultPusherDir = () => join(homedir(), ".local", "state", "substrate", "pusher")
export const defaultConfigPath = () => join(homedir(), ".config", "substrate", "seat-capacity.json")

/**
 * Refresh policy defaults, in seconds.
 *
 * `slotHeartbeatSeconds` is the beat for a dispatchable Halogen slot row. Its
 * `observed_at` is the kernel's own observation, and the lake grades a reading
 * STALE after 1200 s (MEASURED_MAX_AGE_S in packages/planning), so a slot row
 * re-sent only every 1800 s would be refused for half of every beat.
 */
export const DEFAULT_POLICY = { heartbeatSeconds: 1800, slotHeartbeatSeconds: 600, minIntervalSeconds: 60 }

/**
 * Seats Tom has ruled out of dispatch. Built in, so a missing or partial config
 * can never publish them as dispatchable; a config may add rulings and reword
 * these, never lift them. cc3: evicted. gpu-coordinator: Halogen is declared on
 * the coordinator but never resident there (ruling in ~/today/CLAUDE.md).
 */
const RULED_NOT_DISPATCHABLE = Object.freeze({
  cc3: "evicted",
  "gpu-coordinator": "halogen is declared but not resident on the coordinator"
})

const ZONED = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/

/** An instant the lake's schema will accept, or null. */
const instant = (value) =>
  typeof value === "string" && ZONED.test(value) && Number.isFinite(Date.parse(value)) ? value : null

const percent = (value) => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null)

const readJson = (path) => {
  if (!existsSync(path)) return { missing: true }
  try {
    return { value: JSON.parse(readFileSync(path, "utf8")) }
  } catch (error) {
    return { error: `${error.name}` }
  }
}

/**
 * Reads the pusher's config; a missing file is the defaults, a broken one is an
 * error. The built-in rulings always apply (`RULED_NOT_DISPATCHABLE`): a config
 * entry that is not a reason string is ignored, so it cannot lift one.
 */
export const readConfig = (path) => {
  const read = path === null ? { missing: true } : readJson(path)
  if (read.error) throw new Error(`cannot parse the seat-capacity config ${path}: ${read.error}`)
  const stated = read.value ?? {}
  const statedRulings =
    stated.not_dispatchable !== null && typeof stated.not_dispatchable === "object"
      ? Object.fromEntries(
          Object.entries(stated.not_dispatchable).filter(([, reason]) => typeof reason === "string" && reason !== "")
        )
      : {}
  return {
    present: read.value !== undefined,
    host: typeof stated.host === "string" ? stated.host : null,
    seats: Array.isArray(stated.seats) ? stated.seats.filter((seat) => typeof seat === "string") : null,
    notDispatchable: { ...RULED_NOT_DISPATCHABLE, ...statedRulings },
    plans: stated.plans !== null && typeof stated.plans === "object" ? stated.plans : {},
    // seat -> { kind: "oauth", credentials, token_pointer?, config_dir? } | { kind: "cache-file", path }
    usage: stated.usage !== null && typeof stated.usage === "object" ? stated.usage : {},
    owners: stated.owners !== null && typeof stated.owners === "object" ? stated.owners : {},
    providers: stated.providers !== null && typeof stated.providers === "object" ? stated.providers : {}
  }
}

/**
 * A reason as it leaves the box: local absolute paths are replaced by `<path>`.
 * The lake is on the public internet (behind a bearer); where a file lives on
 * the coordinator is none of its business.
 */
const scrubReason = (value) =>
  typeof value === "string" ? value.replace(/(?:~|\/(?:home|root|Users|nix|run|tmp|var|etc))\/[^\s,;:'"`)]+/g, "<path>") : null

const AUTH_FAILURE = /token expired|unauthori[sz]ed|\b401\b|invalid[_ ]grant|credentials/i

const dispatchOf = (seat, owner, staleReason, config) => {
  const ruled = config.notDispatchable[seat]
  if (typeof ruled === "string") return { dispatchable: false, dispatchable_reason: ruled }
  if (owner !== "tom") return { dispatchable: false, dispatchable_reason: "third-party" }
  if (typeof staleReason === "string" && AUTH_FAILURE.test(staleReason)) {
    return { dispatchable: false, dispatchable_reason: "auth-failed" }
  }
  return { dispatchable: true, dispatchable_reason: null }
}

const planOf = (seat, config) => {
  const expires = instant(config.plans[seat])
  return expires === null ? null : { expires_at: expires }
}

const later = (left, right) => {
  if (left === null) return right
  if (right === null) return left
  return Date.parse(right) > Date.parse(left) ? right : left
}

/** The pusher's one limits[] mapping (usageSource.mjs windowsFromLimits): an unplaceable row is a binding UNKNOWN seven_day window. */
const claudeWindowsFromLimits = (limits) => windowsFromLimits(limits).windows

const claudeWindowsFromMeter = (window) => {
  if (window === null || typeof window !== "object") return []
  return [
    ["five_hour", window.primary],
    ["seven_day", window.secondary]
  ].flatMap(([kind, entry]) =>
    entry === null || typeof entry !== "object"
      ? []
      : [
          {
            kind,
            model: null,
            binding: true,
            minutes: MINUTES[kind],
            utilization_pct: percent(entry.utilization_pct),
            resets_at: instant(entry.resets_at),
            severity: null,
            grade: "MEASURED"
          }
        ]
  )
}

/**
 * The model-scoped rows a cache last showed, carried forward as UNKNOWN when the
 * reading itself comes from the meter row: the model limit exists and was not
 * read with this reading, so its utilization and severity are not known. The
 * reset instant is kept (a passed one projects forward at the lake). The lake
 * refuses a job for that model `window-unknown`, never admits it as headroom.
 */
const carriedModelWindows = (limits) =>
  Array.isArray(limits)
    ? claudeWindowsFromLimits(limits)
        // An unplaceable row (UNKNOWN seven_day) is carried too: dropping it read as headroom.
        .filter((window) => window.kind === "model_scoped" || window.grade === "UNKNOWN")
        .map((window) => ({ ...window, utilization_pct: null, severity: null, grade: "UNKNOWN" }))
    : []

const claudeSeat = (seat, meter, cache, config) => {
  const meterObserved = later(instant(meter.reading_observed_at), instant(meter.source?.source_observed_at))
  const cacheObserved = instant(cache?.observed_at)
  const observed = later(meterObserved, cacheObserved)
  if (observed === null) return { skip: "the meter states no reading instant" }
  const limits = cache?.usage?.limits
  // The cache's limits[] are the reading only when the cache IS the latest read.
  // Otherwise (cache missing, torn mid-write, or behind the meter row) the
  // meter row gives the seat-wide windows and the model limits stay unread.
  const fromCache =
    Array.isArray(limits) && cacheObserved !== null && Date.parse(cacheObserved) === Date.parse(observed)
  const graded = meter.grade === "MEASURED" || meter.grade === "STALE-MEASURED"
  const staleReason = scrubReason(meter.stale_reason)
  return {
    seat: {
      seat,
      provider: "claude",
      owner: meter.owner === "tom" ? "tom" : "third-party",
      ...dispatchOf(seat, meter.owner, staleReason, config),
      plan: planOf(seat, config),
      slots: null,
      windows: fromCache
        ? claudeWindowsFromLimits(limits)
        : [...claudeWindowsFromMeter(meter.window), ...carriedModelWindows(limits)],
      observed_at: observed,
      source: {
        kind: "oauth-usage-endpoint",
        detail: fromCache ? "usage cache limits[]" : "meter row window"
      },
      // The reading's age is the lake's to judge from observed_at: a row the
      // feeder marked STALE-MEASURED is a MEASURED reading that has aged.
      grade: graded ? "MEASURED" : "UNKNOWN",
      stale_reason: staleReason,
      // Only limits[] read with this very reading, every row placed, lists every model limit.
      model_windows_complete: fromCache && windowsFromLimits(limits).unmapped === 0
    }
  }
}

const codexSeat = (seat, meter, config) => {
  const observed = instant(meter.observed_at)
  if (observed === null) return { skip: "the meter states no observed_at" }
  const window = meter.window
  const windows =
    window !== null && typeof window === "object" && window.minutes === 10080
      ? [
          {
            kind: "seven_day",
            model: null,
            binding: true,
            minutes: 10080,
            utilization_pct: percent(window.utilization_pct),
            resets_at: instant(window.resets_at),
            severity: null,
            grade: "ESTIMATED"
          }
        ]
      : []
  return {
    seat: {
      seat,
      provider: "codex",
      owner: meter.owner === "tom" ? "tom" : "third-party",
      ...dispatchOf(seat, meter.owner, null, config),
      plan: planOf(seat, config),
      slots: null,
      windows,
      observed_at: observed,
      // The meter row states no provider or rollout-event instant; observed_at
      // is the feeder's read of a local rollout. Said so, rather than implied.
      source: { kind: "codex-rollout-rate-limits", detail: "observed_at is the feeder's read instant" },
      // Read from a local rollout, not from the provider at a known instant.
      grade: "ESTIMATED",
      stale_reason: null
    }
  }
}

const qwenSeat = (seat, meter, config) => {
  const observed = instant(meter.observed_at)
  if (observed === null) return { skip: "the meter states no observed_at" }
  const window = meter.window
  const windows =
    window !== null && typeof window === "object" && instant(window.resets_at) !== null
      ? [
          {
            kind: "seven_day",
            model: null,
            binding: true,
            minutes: 10080,
            utilization_pct: null,
            resets_at: instant(window.resets_at),
            severity: null,
            grade: "UNKNOWN"
          }
        ]
      : []
  return {
    seat: {
      seat,
      provider: "qwen",
      owner: meter.owner === "tom" ? "tom" : "third-party",
      ...dispatchOf(seat, meter.owner, null, config),
      plan: planOf(seat, config),
      slots: null,
      windows,
      observed_at: observed,
      source: { kind: "hold-record", detail: "observed_at is the feeder's read instant" },
      grade: "UNKNOWN",
      stale_reason: scrubReason(meter.window_reason)
    }
  }
}

const halogenSeat = (seat, meter, config) => {
  const observed = instant(meter.observed_at)
  if (observed === null) return { skip: "the meter states no observed_at" }
  const capacity = Number.isInteger(meter.capacity) && meter.capacity >= 0 ? meter.capacity : null
  const holders = Number.isInteger(meter.holders) && meter.holders >= 0 ? meter.holders : null
  return {
    seat: {
      seat,
      provider: "halogen",
      owner: "tom",
      ...dispatchOf(seat, "tom", null, config),
      plan: planOf(seat, config),
      slots: capacity === null || holders === null ? null : { capacity, holders },
      windows: [],
      observed_at: observed,
      source: { kind: "kernel-row", detail: null },
      grade: meter.running_grade === "MEASURED" ? "MEASURED" : "UNKNOWN",
      stale_reason: null
    }
  }
}

/**
 * A seat read through its own usage source (usageSource.mjs), no meter row
 * needed. `read` is `{ reading, error }` from readSeatUsage.
 */
const seatFromUsage = (seat, read, sourceKind, config) => {
  const reading = read.reading
  if (reading === null) return { skip: read.error ?? "no usage reading yet" }
  const owner = config.owners[seat] === "third-party" ? "third-party" : "tom"
  const staleReason = scrubReason(read.error)
  return {
    seat: {
      seat,
      provider: typeof config.providers[seat] === "string" ? config.providers[seat] : "claude",
      owner,
      ...dispatchOf(seat, owner, staleReason, config),
      plan: planOf(seat, config),
      slots: null,
      windows: windowsFromUsage(reading.usage),
      // The reading lists every model limit only when limits[] is the reading;
      // without the claim, admission refuses a model job with no window.
      // An unplaceable row withdraws the claim (successor review r4).
      model_windows_complete: limitsComplete(reading.usage),
      observed_at: reading.observed_at,
      source: {
        kind: "oauth-usage-endpoint",
        detail: sourceKind === "oauth" ? "direct read" : "usage cache file"
      },
      grade: "MEASURED",
      stale_reason: staleReason
    }
  }
}

/** Classifies one meter file into a seat, or a named skip. */
const seatFromMeter = (seat, meter, cache, config) => {
  if (meter === null || typeof meter !== "object") return { skip: "the meter is not an object" }
  const kind = meter.source?.kind
  if (kind === "oauth-usage-endpoint") return claudeSeat(seat, meter, cache, config)
  if (kind === "codex-rollout-rate-limits") return codexSeat(seat, meter, config)
  if (typeof meter.source?.hold_record === "string" || seat.startsWith("pi-qwen")) {
    return qwenSeat(seat, meter, config)
  }
  if (seat.startsWith("gpu-") && meter.window?.kind === "none") return halogenSeat(seat, meter, config)
  return { skip: "not a compute seat this pusher knows" }
}

const METER_FILE = /^([a-z0-9][a-z0-9-]{0,62})\.json$/

/**
 * The feeder's own snapshot, held to the same local rules as one built here:
 * the config's seat filter, the rulings (which only ever take dispatch away),
 * and the path scrub on every reason that leaves the box.
 */
const governWritten = (snapshot, config) => ({
  ...snapshot,
  seats: snapshot.seats
    .filter((seat) => config.seats === null || config.seats.includes(seat?.seat))
    .map((seat) => {
      if (seat === null || typeof seat !== "object") return seat
      const staleReason = scrubReason(seat.stale_reason)
      const ruled = dispatchOf(seat.seat, seat.owner, staleReason, config)
      const dispatch =
        seat.dispatchable === true && ruled.dispatchable
          ? { dispatchable: true, dispatchable_reason: null }
          : {
              dispatchable: false,
              dispatchable_reason: ruled.dispatchable
                ? scrubReason(seat.dispatchable_reason)
                : ruled.dispatchable_reason
            }
      return { ...seat, ...dispatch, stale_reason: staleReason }
    })
})

/**
 * Builds the snapshot the lake ingests.
 *
 * @returns `{ snapshot, skipped }`: skipped names every meter file left out and why.
 */
export const buildSnapshot = ({ metersDir = null, capacityDir = null, config, now, list, usage = {} }) => {
  const host = config.host ?? hostname().split(".")[0]
  if (capacityDir !== null) {
    const written = readJson(join(capacityDir, "seats.json"))
    if (written.value?.schema_version === SCHEMA_VERSION && Array.isArray(written.value.seats)) {
      return { snapshot: governWritten(written.value, config), skipped: [], source: "seats.json" }
    }
  }
  const wanted = (name) => config.seats === null || config.seats.includes(name)
  const seats = []
  const skipped = []
  // Seats with their own usage source come first and win over a meter row.
  const direct = Object.keys(usage).filter(wanted).sort()
  for (const name of direct) {
    const built = seatFromUsage(name, usage[name], config.usage[name]?.kind ?? null, config)
    if (built.skip !== undefined) skipped.push({ seat: name, reason: scrubReason(built.skip) })
    else seats.push(built.seat)
  }
  const names = (metersDir === null ? [] : (list ?? []))
    .map((name) => METER_FILE.exec(name)?.[1])
    .filter((name) => name !== undefined)
    .filter((name) => wanted(name) && !direct.includes(name))
    .sort()
  for (const name of names) {
    const meter = readJson(join(metersDir, `${name}.json`))
    if (meter.value === undefined) {
      skipped.push({ seat: name, reason: meter.error ? `unreadable: ${meter.error}` : "missing" })
      continue
    }
    const cache = readJson(join(metersDir, `.window-cache-${name}.json`)).value ?? null
    const built = seatFromMeter(name, meter.value, cache, config)
    if (built.skip !== undefined) skipped.push({ seat: name, reason: built.skip })
    else seats.push(built.seat)
  }
  return {
    snapshot: { schema_version: SCHEMA_VERSION, host, published_at: now, seats },
    skipped,
    source: direct.length > 0 ? (metersDir === null ? "usage" : "usage+meters") : "meters"
  }
}

/** Key-sorted JSON. */
const canonical = (value) =>
  JSON.stringify(value, (_key, entry) =>
    entry !== null && typeof entry === "object" && !Array.isArray(entry)
      ? Object.fromEntries(Object.entries(entry).sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0)))
      : entry
  )

/**
 * Providers whose `observed_at` is a provider's answer. For the others it is a
 * feeder or kernel restamp (codex: the feeder's re-read of a local rollout;
 * qwen: a hold record; halogen: the kernel's slot row), which moves every tick
 * without the reading changing, so it is left out of the fingerprint and the
 * heartbeats carry it instead.
 */
const PROVIDER_INSTANT = new Set(["claude"])

/** What decides a push: the reading's identity, not the instant it was restamped. */
export const fingerprint = (seat) =>
  canonical({
    observed_at: PROVIDER_INSTANT.has(seat.provider) ? Date.parse(seat.observed_at) : null,
    grade: seat.grade,
    windows: seat.windows,
    dispatchable: seat.dispatchable,
    dispatchable_reason: seat.dispatchable_reason,
    slots: seat.slots,
    plan: seat.plan
  })

/**
 * The refresh policy: push when any seat's reading changed, and at least every
 * `heartbeatSeconds` as a liveness beat (every `slotHeartbeatSeconds` while a
 * dispatchable Halogen slot row is published); never twice within
 * `minIntervalSeconds`.
 */
export const decidePush = (state, snapshot, nowMs, policy = DEFAULT_POLICY) => {
  const last = state?.last_push_at === undefined ? null : Date.parse(state.last_push_at)
  const since = last === null || !Number.isFinite(last) ? null : (nowMs - last) / 1000
  if (since !== null && since >= 0 && since < policy.minIntervalSeconds) {
    return { push: false, reason: "min-interval", changed: [] }
  }
  const held = state?.fingerprints ?? {}
  const current = Object.fromEntries(snapshot.seats.map((seat) => [seat.seat, fingerprint(seat)]))
  const changed = Object.keys(current).filter((seat) => held[seat] !== current[seat])
  const removed = Object.keys(held).filter((seat) => !(seat in current))
  if (changed.length > 0 || removed.length > 0) {
    return { push: true, reason: "changed", changed: [...changed, ...removed].sort() }
  }
  if (since === null || since < 0 || since >= policy.heartbeatSeconds) {
    return { push: true, reason: "heartbeat", changed: [] }
  }
  const slotBeat = policy.slotHeartbeatSeconds ?? DEFAULT_POLICY.slotHeartbeatSeconds
  const liveSlots = snapshot.seats.some((seat) => seat.provider === "halogen" && seat.dispatchable)
  if (liveSlots && since >= slotBeat) {
    return { push: true, reason: "heartbeat", changed: [] }
  }
  return { push: false, reason: "unchanged", changed: [] }
}

/** The state to keep after a successful push. */
export const stateAfterPush = (snapshot, now) => ({
  last_push_at: now,
  fingerprints: Object.fromEntries(snapshot.seats.map((seat) => [seat.seat, fingerprint(seat)]))
})

export const readState = (path) => {
  const read = readJson(path)
  return read.value !== null && typeof read.value === "object" ? read.value : {}
}

/** Atomic, 0600: a partial state file must never make the next run skip a push. */
const writeState = (path, state) => {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 })
  const temporary = `${path}.tmp-${process.pid}`
  writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 })
  renameSync(temporary, path)
}

class PushError extends Error {}

/**
 * Sends the snapshot to `POST <base>/capacity/seats`. The token is sent and
 * never echoed: an error names the status and the route, not the header.
 */
const pushSnapshot = async ({ base, token, snapshot, fetchImpl = fetch, instance = "" }) => {
  const url = `${base.replace(/\/+$/, "")}/capacity/seats`
  let response
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        ...(instance === "" ? {} : { "x-conwip-factory-instance": instance })
      },
      body: JSON.stringify(snapshot)
    })
  } catch (error) {
    throw new PushError(`POST /capacity/seats did not complete: ${error?.name ?? "Error"}`)
  }
  const text = await response.text()
  if (response.status !== 200) {
    throw new PushError(`POST /capacity/seats answered ${response.status}: ${text.slice(0, 200)}`)
  }
  try {
    return JSON.parse(text)
  } catch {
    throw new PushError("POST /capacity/seats answered 200 with a body that is not JSON")
  }
}

/**
 * One pass: build, decide, push when due, and keep the state only after the
 * lake has answered 200.
 */
export const runOnce = async ({
  metersDir,
  capacityDir,
  statePath,
  config,
  base,
  token,
  now = () => new Date().toISOString(),
  list,
  fetchImpl = fetch,
  policy = DEFAULT_POLICY,
  force = false,
  dryRun = false,
  instance = "",
  allowNetwork = true,
  preDispatch = false,
  usageDir,
  demandDir
}) => {
  const at = now()
  // Each seat's usage source first. A dry run never calls the network.
  const usage = {}
  for (const seat of Object.keys(config.usage ?? {}).sort()) {
    usage[seat] = await readSeatUsage({
      seat,
      source: config.usage[seat],
      nowMs: Date.parse(at),
      allowNetwork: allowNetwork && !dryRun,
      preDispatch,
      fetchImpl,
      ...(usageDir === undefined ? {} : { usageDir }),
      ...(demandDir === undefined ? {} : { demandDir })
    })
  }
  const { snapshot, skipped, source } = buildSnapshot({ metersDir, capacityDir, config, now: at, list, usage })
  const state = readState(statePath)
  const decision = force
    ? { push: true, reason: "forced", changed: [] }
    : decidePush(state, snapshot, Date.parse(at), policy)
  const summary = { at, source, seats: snapshot.seats.map((seat) => seat.seat), skipped, decision }
  if (dryRun) return { ...summary, pushed: false, snapshot }
  if (!decision.push) return { ...summary, pushed: false }
  const answer = await pushSnapshot({ base, token, snapshot, fetchImpl, instance })
  writeState(statePath, stateAfterPush(snapshot, at))
  return { ...summary, pushed: true, results: answer.results ?? null }
}
