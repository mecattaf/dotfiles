// apps/pusher/src/seatsOracle.mjs: the gentle pusher's one source. It reads the
// box's capacity oracle (`seats --json`, schema seat-capacity/1) and converts
// the answer to seat-capacity/2 for the floor. Pure: no clock, no file, no
// network; the process (bin/substrate-pusher.mjs) runs the oracle and posts.
//
// The pusher never calls a provider's usage endpoint itself. The oracle owns
// its own cache and its own 429 handling; the pusher only decides how often it
// asks the oracle (gentle.mjs, the repo's refresh policy).
//
// WHAT THE CONVERSION REFUSES TO INVENT (fail closed, as the /2 schema says):
//   - a window the /2 kinds cannot place (a length other than 300 or 10080
//     minutes, a scope naming no model) becomes a binding seven_day window
//     graded UNKNOWN with its reset kept, and the seat withdraws
//     model_windows_complete;
//   - a null or missing percentage stays null (UNKNOWN, never headroom);
//   - a seat the oracle did not report is named in `skipped`, never carried
//     forward; the floor's copy then ages to STALE and refuses on its own;
//   - local paths in any reason are replaced by `<path>` before they leave the
//     box, and no oracle field other than the few named here is copied.

import { hostname } from "node:os"

export const SOURCE_SCHEMA = "seat-capacity/1"
export const TARGET_SCHEMA = "seat-capacity/2"

/** The seats the pusher publishes unless its config says otherwise (the runs-on seat names). */
export const DEFAULT_SEATS = Object.freeze(["cc", "cc2", "codex", "pi-qwencloud", "halogen"])
/** Oracle seat ids onto runs-on seat names: the oracle calls the worker's Halogen server `gpu-worker`. */
export const DEFAULT_SEAT_IDS = Object.freeze({ "gpu-worker": "halogen" })
/** Providers whose percentages are the oracle's estimate, not a provider answer (Qwen Cloud: a credit count from local logs). */
export const DEFAULT_ESTIMATED_PROVIDERS = Object.freeze(["qwen"])
/** Seats ruled out of dispatch whatever a config says (a config may add rulings, never lift these). */
export const RULED_NOT_DISPATCHABLE = Object.freeze({
  cc3: "evicted",
  "gpu-coordinator": "halogen is declared but not resident on the coordinator"
})

export class SeatsFormatError extends Error {}

const ZONED = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/
const SEAT_ID = /^[a-z0-9][a-z0-9-]{0,62}$/
const PROVIDER = /^[a-z][a-z0-9-]{0,31}$/

export const instant = (value) =>
  typeof value === "string" && ZONED.test(value) && Number.isFinite(Date.parse(value)) ? value : null
const percent = (value) => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null)
const text = (value) => (typeof value === "string" && value.trim() !== "" ? value.trim() : null)

/** A reason as it leaves the box: local absolute paths become `<path>`. */
export const scrub = (value) =>
  typeof value === "string"
    ? value.replace(/(?:~|\/(?:home|root|Users|nix|run|tmp|var|etc|mnt|srv))\/[^\s,;:'"`)]+/g, "<path>").slice(0, 300)
    : null

/**
 * The conversion's settings, from the pusher config (defaults filled in).
 * `owners` overrides the oracle's owner field per seat (the oracle's own seat
 * table can lag a ruling); `slots` is the slot count of a slot-counted seat.
 */
export const conversionSettings = (config = {}) => {
  const object = (value) => (value !== null && typeof value === "object" && !Array.isArray(value) ? value : {})
  const stated = Object.fromEntries(
    Object.entries(object(config.not_dispatchable)).filter(([, reason]) => typeof reason === "string" && reason !== "")
  )
  return {
    host: typeof config.host === "string" && config.host !== "" ? config.host : null,
    seats: Array.isArray(config.seats) ? config.seats.filter((seat) => typeof seat === "string") : [...DEFAULT_SEATS],
    seatIds: { ...DEFAULT_SEAT_IDS, ...object(config.seatIds) },
    owners: object(config.owners),
    plans: object(config.plans),
    slots: object(config.slots),
    estimatedProviders: Array.isArray(config.estimatedProviders) ? config.estimatedProviders : [...DEFAULT_ESTIMATED_PROVIDERS],
    notDispatchable: { ...RULED_NOT_DISPATCHABLE, ...stated }
  }
}

/** When the provider (or the local artefact) answered, as best the oracle states it. */
const observedOf = (seat, generatedMs) => {
  const stated = instant(seat?.source?.observed_at)
  if (stated !== null) return new Date(Date.parse(stated)).toISOString()
  const age = seat?.source?.reading_age_seconds
  const ageS = typeof age === "number" && Number.isFinite(age) && age >= 0 ? age : 0
  return new Date(generatedMs - ageS * 1000).toISOString()
}

/** One oracle window as a /2 window, or an UNKNOWN binding weekly window when it cannot be placed. */
const windowOf = (entry, grade) => {
  const minutes = entry?.minutes
  const scope = text(entry?.scope)
  const base = {
    utilization_pct: percent(entry?.used_pct),
    resets_at: instant(entry?.resets_at),
    severity: text(entry?.severity),
    grade
  }
  if (scope !== null && minutes === 10080) return { placed: true, window: { kind: "model_scoped", model: scope, binding: true, minutes: 10080, ...base } }
  if (scope === null && minutes === 300) return { placed: true, window: { kind: "five_hour", model: null, binding: true, minutes: 300, ...base } }
  if (scope === null && minutes === 10080) return { placed: true, window: { kind: "seven_day", model: null, binding: true, minutes: 10080, ...base } }
  return {
    placed: false,
    window: { kind: "seven_day", model: null, binding: true, minutes: 10080, utilization_pct: null, resets_at: instant(entry?.resets_at), severity: null, grade: "UNKNOWN" }
  }
}

/** The /2 grade of an oracle seat. CACHED is a provider answer that has aged: MEASURED, dated by its age. */
const gradeOf = (seat, provider, settings) => {
  if (seat.grade === "UNKNOWN" || seat.grade === undefined) return "UNKNOWN"
  if (settings.estimatedProviders.includes(provider)) return "ESTIMATED"
  if (seat.grade === "MEASURED" || seat.grade === "CACHED") return "MEASURED"
  return "UNKNOWN"
}

const dispatchOf = (id, owner, seat, provider, settings) => {
  const ruled = settings.notDispatchable[id]
  if (typeof ruled === "string") return { dispatchable: false, dispatchable_reason: ruled }
  if (owner !== "tom") return { dispatchable: false, dispatchable_reason: "third-party" }
  if (seat.state === "unauth") return { dispatchable: false, dispatchable_reason: "auth-failed" }
  if (seat.state === "n/a") return { dispatchable: false, dispatchable_reason: scrub(text(seat.detail) ?? "not applicable") }
  if (provider === "halogen" && seat.state !== "open") return { dispatchable: false, dispatchable_reason: `down: ${scrub(text(seat.detail) ?? seat.state ?? "unknown")}` }
  return { dispatchable: true, dispatchable_reason: null }
}

/**
 * Converts one `seats --json` document to a seat-capacity/2 snapshot.
 *
 * @param doc the parsed oracle answer (schema seat-capacity/1).
 * @param config the pusher config (see conversionSettings).
 * @param now the publishing instant (ISO), the pusher's clock.
 * @returns `{ snapshot, skipped }`; skipped names every configured seat left out and why.
 * @throws SeatsFormatError when the document is not seat-capacity/1.
 */
export const snapshotFromSeatsV1 = (doc, config, now) => {
  if (doc === null || typeof doc !== "object" || doc.schema_version !== SOURCE_SCHEMA || !Array.isArray(doc.seats)) {
    throw new SeatsFormatError(`the oracle's answer is not ${SOURCE_SCHEMA}`)
  }
  if (instant(now) === null) throw new RangeError(`now is not an instant: ${now}`)
  const settings = conversionSettings(config)
  const generated = instant(doc.generated_at)
  const generatedMs = generated === null ? Date.parse(now) : Math.min(Date.parse(generated), Date.parse(now))
  const seats = []
  const skipped = []
  const seen = new Set()
  for (const raw of doc.seats) {
    if (raw === null || typeof raw !== "object" || typeof raw.id !== "string") continue
    const id = settings.seatIds[raw.id] ?? raw.id
    if (!settings.seats.includes(id) || seen.has(id)) continue
    seen.add(id)
    const provider = typeof raw.provider === "string" ? raw.provider : ""
    if (!SEAT_ID.test(id)) { skipped.push({ seat: id, reason: "not a seat id the floor accepts" }); continue }
    if (!PROVIDER.test(provider) || provider === "none") { skipped.push({ seat: id, reason: "the oracle names no provider" }); continue }
    const configured = settings.owners[id]
    const owner = configured === "tom" || configured === "third-party" ? configured : raw.owner === "tom" || raw.owner === "kernel" ? "tom" : "third-party"
    const grade = gradeOf(raw, provider, settings)
    const observed = observedOf(raw, generatedMs)
    let unmapped = 0
    const windows = (Array.isArray(raw.windows) ? raw.windows : []).map((entry) => {
      const placed = windowOf(entry, grade)
      if (!placed.placed) unmapped++
      return placed.window
    })
    const ageS = Math.round((generatedMs - Date.parse(observed)) / 1000)
    const staleReason =
      grade === "UNKNOWN"
        ? scrub(text(raw.detail) ?? "the oracle could not read this seat")
        : raw.grade === "CACHED"
          ? `the oracle served a cached reading ${ageS} s old`
          : null
    const slotCount = settings.slots[id]
    const slots =
      provider === "halogen" && raw.state === "open"
        ? { capacity: Number.isInteger(slotCount) && slotCount >= 0 ? slotCount : 1, holders: 0 }
        : null
    const plan = instant(settings.plans[id])
    seats.push({
      seat: id,
      provider,
      owner,
      ...dispatchOf(id, owner, raw, provider, settings),
      plan: plan === null ? null : { expires_at: plan },
      slots,
      windows,
      observed_at: observed,
      source: { kind: "seats-oracle", detail: scrub(`${SOURCE_SCHEMA} ${text(raw.source?.kind) ?? "no-source"}`) },
      grade,
      stale_reason: staleReason,
      model_windows_complete: grade !== "UNKNOWN" && unmapped === 0
    })
  }
  for (const id of settings.seats) {
    if (!seen.has(id)) skipped.push({ seat: id, reason: "the oracle did not report this seat" })
  }
  return {
    snapshot: {
      schema_version: TARGET_SCHEMA,
      host: settings.host ?? (typeof doc.host === "string" && doc.host !== "" ? doc.host : hostname().split(".")[0]),
      published_at: now,
      seats: seats.sort((a, b) => (a.seat < b.seat ? -1 : a.seat > b.seat ? 1 : 0))
    },
    skipped
  }
}

// ---- the oracle's environment (parity gap PT-01, 2026-09-24).
// The dotfiles `seats` oracle consults a peer cache before the network; its default is the tally-rewrite feeder's
// meters directory. The pusher points it at a substrate-owned directory instead, so no substrate process reads a
// tally-era path. `peerCacheDir: "inherit"` keeps the oracle's own default (the old behaviour), for a box where the
// tally feeder still runs and its readings are wanted to spare the rate-limited usage endpoint.
export const DEFAULT_PEER_CACHE_SUBDIR = "seats-peer-cache"

/** The environment the pusher runs `seats` with. Pure: `stateDir` is the substrate state directory. */
export const oracleEnv = (config = {}, stateDir, env = {}) => {
  const configured = config.peerCacheDir ?? undefined
  if (configured === "inherit") return { ...env }
  if (configured !== undefined && (typeof configured !== "string" || configured === "")) {
    throw new SeatsFormatError("peerCacheDir must be a non-empty path or \"inherit\"")
  }
  const dir = configured ?? `${stateDir.replace(/\/+$/, "")}/${DEFAULT_PEER_CACHE_SUBDIR}`
  if (/tally-rewrite/.test(dir)) throw new SeatsFormatError("peerCacheDir must not be a tally-rewrite path; use \"inherit\" to keep the oracle's own default")
  return { ...env, SEATS_PEER_CACHE_DIR: dir }
}
