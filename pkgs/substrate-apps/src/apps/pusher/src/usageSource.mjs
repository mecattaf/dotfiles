// apps/pusher/src/usageSource.mjs: the Claude usage source, read directly or
// through an adapter, so the pusher needs no tally-rewrite feeder.
//
// TWO ADAPTERS, ONE READING SHAPE `{ observed_at, usage }`:
//
//   "oauth"       the direct reader. It calls the usage endpoint Claude Code's
//                 own /usage view calls, with the seat's OAuth bearer read from
//                 the seat's credentials file at call time. The bearer is held
//                 in memory for the one request and never written, logged or
//                 put in an error. Calls obey refreshPolicy.mjs.
//                 (Endpoint, headers and the token's place in the file are
//                 REPORTED from research-methods bin/stamp-receipt.py:103-126.)
//   "cache-file"  a file some other reader already wrote in the endpoint's
//                 answer shape: the tally feeder's `.window-cache-<seat>.json`
//                 while it still exists, or this module's own cache.
//
// THE CACHE KEEPS ONLY WHAT IS READ. The direct reader writes `observed_at`
// and `usage.{five_hour, seven_day, limits}`; spend and every other field of
// the answer are dropped before anything touches the disk.
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"

import { afterAttempt, initialRefreshState, REFRESH_POLICY, refreshDue } from "./refreshPolicy.mjs"

export const USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
const USAGE_HEADERS = { "content-type": "application/json", "anthropic-beta": "oauth-2025-04-20" }
/** Where the bearer sits in a Claude credentials file. */
export const DEFAULT_TOKEN_POINTER = ["claudeAiOauth", "accessToken"]

export const defaultStateDir = () => join(homedir(), ".local", "state", "substrate")
export const defaultUsageDir = () => join(defaultStateDir(), "usage")
export const defaultDemandDir = () => join(defaultStateDir(), "demand")

/** The usage endpoint's `limits[].kind`, mapped to the floor's window kinds. */
const LIMIT_KINDS = { session: "five_hour", weekly_all: "seven_day", weekly_scoped: "model_scoped" }
const MINUTES = { five_hour: 300, seven_day: 10080, model_scoped: 10080 }
const ZONED = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/

export const instant = (value) =>
  typeof value === "string" && ZONED.test(value) && Number.isFinite(Date.parse(value)) ? value : null
const percent = (value) => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null)

export class CredentialError extends Error {}

/**
 * The one mapping from the endpoint's `limits[]` to windows, for every pusher
 * path (capacity review round 3, ported here by successor review r4: the
 * pusher dropped rows it could not place and still claimed
 * model_windows_complete, so the gate admitted past a 100 percent limit the
 * tally adapter refused). A row it cannot place (a kind it does not know, or
 * a scoped row naming no model, such as one scoped by surface only) is never
 * dropped: it becomes a binding seven_day window graded UNKNOWN with its reset
 * kept, and `unmapped` counts it, so the reading withdraws
 * model_windows_complete. src/capacity/tally-meters.ts maps the same way; a
 * root test pins the two together.
 */
export const windowsFromLimits = (limits) => {
  let unmapped = 0
  const windows = limits.flatMap((limit) => {
    const kind = LIMIT_KINDS[limit?.kind]
    const model =
      kind === "model_scoped" ? (limit.scope?.model?.display_name ?? limit.scope?.model?.id ?? null) : null
    if (kind === undefined || (kind === "model_scoped" && typeof model !== "string")) {
      unmapped++
      return [
        {
          kind: "seven_day",
          model: null,
          binding: true,
          minutes: MINUTES.seven_day,
          utilization_pct: null,
          resets_at: instant(limit?.resets_at),
          severity: null,
          grade: "UNKNOWN"
        }
      ]
    }
    return [
      {
        kind,
        model,
        binding: true,
        minutes: MINUTES[kind],
        utilization_pct: percent(limit.percent),
        resets_at: instant(limit.resets_at),
        severity: typeof limit.severity === "string" ? limit.severity : null,
        grade: "MEASURED"
      }
    ]
  })
  return { windows, unmapped }
}

/** A usage answer lists every model limit: limits[] is present and every row was placed. */
export const limitsComplete = (usage) =>
  usage !== null && typeof usage === "object" && Array.isArray(usage.limits) && windowsFromLimits(usage.limits).unmapped === 0

/**
 * The windows a usage answer states: `limits[]` when present (the only place
 * model-scoped rows appear), else the flat `five_hour` / `seven_day` pair.
 */
export const windowsFromUsage = (usage) => {
  if (usage === null || typeof usage !== "object") return []
  if (Array.isArray(usage.limits)) return windowsFromLimits(usage.limits).windows
  return [
    ["five_hour", usage.five_hour],
    ["seven_day", usage.seven_day]
  ].flatMap(([kind, entry]) =>
    entry === null || typeof entry !== "object"
      ? []
      : [
          {
            kind,
            model: null,
            binding: true,
            minutes: MINUTES[kind],
            utilization_pct: percent(entry.utilization),
            resets_at: instant(entry.resets_at),
            severity: null,
            grade: "MEASURED"
          }
        ]
  )
}

/** Only the fields the pusher reads; spend and the rest never reach the disk. */
export const minimalUsage = (usage) => {
  const pick = (entry) =>
    entry !== null && typeof entry === "object"
      ? { utilization: percent(entry.utilization), resets_at: instant(entry.resets_at) }
      : null
  const limits = Array.isArray(usage?.limits)
    ? usage.limits.map((limit) => ({
        kind: typeof limit?.kind === "string" ? limit.kind : null,
        percent: percent(limit?.percent),
        severity: typeof limit?.severity === "string" ? limit.severity : null,
        resets_at: instant(limit?.resets_at),
        scope:
          typeof limit?.scope?.model?.display_name === "string" || typeof limit?.scope?.model?.id === "string"
            ? {
                model: {
                  display_name: limit.scope.model.display_name ?? null,
                  id: limit.scope.model.id ?? null
                }
              }
            : null
      }))
    : undefined
  return {
    five_hour: pick(usage?.five_hour),
    seven_day: pick(usage?.seven_day),
    ...(limits === undefined ? {} : { limits })
  }
}

const readJson = (path) => {
  if (!existsSync(path)) return { missing: true }
  try {
    return { value: JSON.parse(readFileSync(path, "utf8")) }
  } catch (error) {
    return { error: `${error.name}` }
  }
}

/** Atomic, 0600, directory 0700. */
export const writePrivateJson = (path, value) => {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 })
  const temporary = `${path}.tmp-${process.pid}`
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 })
  renameSync(temporary, path)
}

/** A reading `{ observed_at, usage }` from a file in the endpoint's answer shape, or null. */
export const readUsageFile = (path) => {
  const read = readJson(path)
  const value = read.value
  if (value === null || typeof value !== "object") return null
  const observed = instant(value.observed_at)
  if (observed === null || value.usage === null || typeof value.usage !== "object") return null
  return { observed_at: observed, usage: value.usage }
}

/**
 * The bearer from a credentials file. The value is returned and never shown:
 * every error names the path and the pointer only.
 */
export const bearerFromCredentials = (path, pointer = DEFAULT_TOKEN_POINTER) => {
  let parsed
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"))
  } catch (error) {
    throw new CredentialError(`cannot read the credentials file ${path}: ${error.code ?? error.name}`)
  }
  let node = parsed
  for (const key of pointer) node = node !== null && typeof node === "object" ? node[key] : undefined
  if (typeof node !== "string" || node.length === 0) {
    throw new CredentialError(`the credentials file ${path} has no string at ${pointer.join(".")}`)
  }
  return node
}

const mtimeMs = (path) => {
  try {
    return statSync(path).mtimeMs
  } catch {
    return null
  }
}

/**
 * Whether a seat is in active use: a demand marker touched within the window
 * (dispatch touches it), or a transcript under the seat's config directory
 * written within the window (interactive use). Looks at the 5 most recently
 * touched project directories only, to keep a pass cheap.
 */
export const seatActive = ({ seat, demandDir, configDir, nowMs, windowSeconds = 600 }) => {
  const recent = (value) => value !== null && nowMs - value <= windowSeconds * 1000
  if (demandDir !== null && demandDir !== undefined && recent(mtimeMs(join(demandDir, seat)))) return true
  if (configDir === null || configDir === undefined) return false
  const projects = join(configDir, "projects")
  let dirs
  try {
    dirs = readdirSync(projects, { withFileTypes: true }).filter((entry) => entry.isDirectory())
  } catch {
    return false
  }
  const newest = dirs
    .map((entry) => ({ path: join(projects, entry.name), at: mtimeMs(join(projects, entry.name)) ?? 0 }))
    .sort((left, right) => right.at - left.at)
    .slice(0, 5)
  for (const dir of newest) {
    if (recent(dir.at)) return true
    try {
      for (const name of readdirSync(dir.path)) {
        if (name.endsWith(".jsonl") && recent(mtimeMs(join(dir.path, name)))) return true
      }
    } catch {
      // unreadable directory: not evidence of activity
    }
  }
  return false
}

const retryAfterSeconds = (response) => {
  const raw = response.headers?.get?.("retry-after")
  if (raw === null || raw === undefined) return null
  const seconds = Number(raw)
  if (Number.isFinite(seconds)) return seconds
  const at = Date.parse(raw)
  return Number.isFinite(at) ? Math.max(0, (at - Date.now()) / 1000) : null
}

/** One GET of the usage endpoint. The bearer is only in the request header. */
export const fetchUsage = async ({ token, fetchImpl = fetch, timeoutMs = 12000 }) => {
  let response
  try {
    response = await fetchImpl(USAGE_ENDPOINT, {
      method: "GET",
      headers: { ...USAGE_HEADERS, authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(timeoutMs)
    })
  } catch (error) {
    return { kind: "error", detail: `the usage read did not complete: ${error?.name ?? "Error"}` }
  }
  if (response.status === 429) {
    return { kind: "rate-limited", retryAfterSeconds: retryAfterSeconds(response), detail: "usage endpoint 429" }
  }
  if (response.status === 401 || response.status === 403) {
    return { kind: "auth-failed", detail: `usage endpoint ${response.status} unauthorized` }
  }
  if (response.status !== 200) return { kind: "error", detail: `usage endpoint answered ${response.status}` }
  try {
    return { kind: "success", usage: JSON.parse(await response.text()) }
  } catch {
    return { kind: "error", detail: "usage endpoint answered 200 with a body that is not JSON" }
  }
}

const bindingFacts = (reading) => {
  const windows = reading === null ? [] : windowsFromUsage(reading.usage).filter((w) => w.kind !== "model_scoped")
  const known = windows.map((w) => w.utilization_pct).filter((value) => value !== null)
  return {
    bindingMaxPct: known.length === 0 ? null : Math.max(...known),
    resets: windows.map((w) => w.resets_at).filter((value) => value !== null)
  }
}

/**
 * Reads one seat's usage through its configured source.
 *
 * @param source `{ kind: "oauth", credentials, token_pointer?, config_dir? }` or
 *   `{ kind: "cache-file", path }`.
 * @returns `{ reading, attempted, decision, error }`; `reading` is
 *   `{ observed_at, usage }` or null, `error` a line safe to publish or null.
 */
export const readSeatUsage = async ({
  seat,
  source,
  usageDir = defaultUsageDir(),
  demandDir = defaultDemandDir(),
  nowMs = Date.now(),
  allowNetwork = true,
  preDispatch = false,
  fetchImpl = fetch,
  policy = REFRESH_POLICY
}) => {
  if (source?.kind === "cache-file") {
    const reading = typeof source.path === "string" ? readUsageFile(source.path) : null
    return { reading, attempted: false, decision: null, error: reading === null ? "no usage cache file reading" : null }
  }
  if (source?.kind !== "oauth" || typeof source.credentials !== "string") {
    return { reading: null, attempted: false, decision: null, error: "no usage source configured" }
  }
  const cachePath = join(usageDir, `${seat}.json`)
  const statePath = join(usageDir, `${seat}.state.json`)
  const cached = readUsageFile(cachePath)
  const stored = readJson(statePath).value
  const state = stored !== null && typeof stored === "object" ? stored : initialRefreshState()
  const credentialsMtimeMs = mtimeMs(source.credentials)
  const decision = refreshDue(
    state,
    {
      nowMs,
      active: seatActive({ seat, demandDir, configDir: source.config_dir ?? null, nowMs }),
      preDispatch,
      credentialsMtimeMs,
      ...bindingFacts(cached)
    },
    policy
  )
  const lastError = typeof state.last_error === "string" ? state.last_error : null
  if (!decision.due || !allowNetwork) {
    return { reading: cached, attempted: false, decision, error: lastError }
  }
  let outcome
  try {
    const token = bearerFromCredentials(source.credentials, source.token_pointer ?? DEFAULT_TOKEN_POINTER)
    outcome = await fetchUsage({ token, fetchImpl })
  } catch (error) {
    outcome = { kind: "auth-failed", detail: error instanceof CredentialError ? "credentials unreadable" : "credentials error" }
  }
  const next = { ...afterAttempt(state, outcome, nowMs, credentialsMtimeMs, policy), last_error: outcome.kind === "success" ? null : outcome.detail }
  if (outcome.kind === "success") {
    const reading = { observed_at: new Date(nowMs).toISOString(), usage: minimalUsage(outcome.usage) }
    writePrivateJson(cachePath, reading)
    writePrivateJson(statePath, next)
    return { reading, attempted: true, decision, error: null }
  }
  writePrivateJson(statePath, next)
  return { reading: cached, attempted: true, decision, error: outcome.detail }
}
