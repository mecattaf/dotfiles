// apps/pusher/src/refreshPolicy.mjs: when a direct usage read is worth a
// network call. Pure: every instant is a parameter, nothing reads a clock.
//
// The values are the capacity scout's refresh policy (evals-2026-09-23
// capacity/SCOUT.md section 5.5), one enforcer per credential:
//
//   hard minimum between network calls     120 s  (sustained success spacing was
//                                                  MEASURED at 123 s; faster is 429s)
//   idle floor                             900 s
//   active cadence                         300 s
//   active and a binding window >= 85 %    180 s
//   pre-dispatch                           read if the reading is older than 300 s
//   reset boundary                         one read at resets_at + 90 s
//   429                                    one attempt, no in-tick retry; next
//                                          allowed = now + max(Retry-After,
//                                          min(120 s x 2^k, 960 s)); k resets on success
//   auth failure                           no call until the credentials file's
//                                          mtime changes

export const REFRESH_POLICY = Object.freeze({
  minSpacingSeconds: 120,
  idleSeconds: 900,
  activeSeconds: 300,
  nearCapSeconds: 180,
  nearCapPct: 85,
  preDispatchAgeSeconds: 300,
  resetGraceSeconds: 90,
  backoffBaseSeconds: 120,
  backoffMaxSeconds: 960
})

/** The state a fresh credential starts from. */
export const initialRefreshState = () => ({
  last_attempt_at: null,
  last_success_at: null,
  backoff_k: 0,
  next_allowed_at: null,
  auth_failed_mtime_ms: null
})

const ms = (iso) => {
  if (typeof iso !== "string") return null
  const value = Date.parse(iso)
  return Number.isFinite(value) ? value : null
}

const iso = (value) => new Date(value).toISOString()

/**
 * Decides whether a network read is due.
 *
 * @param state the credential's refresh state (initialRefreshState() shape).
 * @param input `{ nowMs, active, preDispatch, bindingMaxPct, resets, credentialsMtimeMs }`:
 *   `resets` are the binding windows' `resets_at` instants from the last reading;
 *   `bindingMaxPct` the highest binding utilization, or null when unknown.
 * @returns `{ due, reason, next_at }`, `next_at` an ISO instant or null.
 */
export const refreshDue = (state, input, policy = REFRESH_POLICY) => {
  const s = { ...initialRefreshState(), ...(state ?? {}) }
  const now = input.nowMs
  if (s.auth_failed_mtime_ms !== null && input.credentialsMtimeMs === s.auth_failed_mtime_ms) {
    return { due: false, reason: "auth-failed", next_at: null }
  }
  const allowed = ms(s.next_allowed_at)
  if (allowed !== null && now < allowed) return { due: false, reason: "backoff", next_at: iso(allowed) }
  const attempted = ms(s.last_attempt_at)
  const earliest = attempted === null ? null : attempted + policy.minSpacingSeconds * 1000
  if (earliest !== null && now < earliest) return { due: false, reason: "min-spacing", next_at: iso(earliest) }
  const succeeded = ms(s.last_success_at)
  if (succeeded === null) return { due: true, reason: "first-read", next_at: null }
  // A reset boundary read turns a PROJECTED window into a MEASURED one.
  const boundaries = (input.resets ?? [])
    .map(ms)
    .filter((value) => value !== null)
    .map((value) => value + policy.resetGraceSeconds * 1000)
  if (boundaries.some((at) => at > succeeded && at <= now)) {
    return { due: true, reason: "reset-boundary", next_at: null }
  }
  const ageSeconds = (now - succeeded) / 1000
  if (input.preDispatch === true && ageSeconds > policy.preDispatchAgeSeconds) {
    return { due: true, reason: "pre-dispatch", next_at: null }
  }
  const nearCap = typeof input.bindingMaxPct === "number" && input.bindingMaxPct >= policy.nearCapPct
  const cadence = input.active === true ? (nearCap ? policy.nearCapSeconds : policy.activeSeconds) : policy.idleSeconds
  if (ageSeconds >= cadence) return { due: true, reason: input.active === true ? "active" : "idle", next_at: null }
  const candidates = [succeeded + cadence * 1000, ...boundaries.filter((at) => at > now)]
  const next = Math.max(Math.min(...candidates), earliest ?? 0)
  return { due: false, reason: "fresh", next_at: iso(next) }
}

/**
 * The state after one attempt.
 *
 * @param outcome `{ kind: "success" }`, `{ kind: "rate-limited", retryAfterSeconds }`,
 *   `{ kind: "auth-failed" }` or `{ kind: "error" }`.
 */
export const afterAttempt = (state, outcome, nowMs, credentialsMtimeMs, policy = REFRESH_POLICY) => {
  const s = { ...initialRefreshState(), ...(state ?? {}), last_attempt_at: iso(nowMs) }
  if (outcome.kind === "success") {
    return { ...s, last_success_at: iso(nowMs), backoff_k: 0, next_allowed_at: null, auth_failed_mtime_ms: null }
  }
  if (outcome.kind === "rate-limited") {
    const k = Number.isInteger(s.backoff_k) && s.backoff_k >= 0 ? s.backoff_k : 0
    const exponential = Math.min(policy.backoffBaseSeconds * 2 ** k, policy.backoffMaxSeconds)
    const retryAfter =
      typeof outcome.retryAfterSeconds === "number" && Number.isFinite(outcome.retryAfterSeconds)
        ? outcome.retryAfterSeconds
        : 0
    return { ...s, backoff_k: k + 1, next_allowed_at: iso(nowMs + Math.max(retryAfter, exponential) * 1000) }
  }
  if (outcome.kind === "auth-failed") return { ...s, auth_failed_mtime_ms: credentialsMtimeMs ?? -1 }
  return s
}
