// apps/pusher/src/gentle.mjs: the gentle pusher's loop, one tick at a time.
// Pure decisions plus one `tick` that takes every effect as a parameter
// (run the oracle, post, read the clock), so the tests drive it on a fake clock.
//
// WHEN THE ORACLE IS ASKED (refreshPolicy.mjs, the policy already in the repo):
//   never twice within 120 s; every 900 s when idle; every 300 s when active;
//   every 180 s when active and a binding window is at or above 85 percent;
//   once at each reset + 90 s; a pre-dispatch ask (SIGUSR1) when the reading is
//   older than 300 s. "Active" means a demand marker younger than 300 s, or the
//   last two readings differed in any utilization (someone is spending).
// WHEN THE FLOOR IS TOLD (seatCapacity.mjs decidePush): after a read, when a
//   seat's reading changed, or as a heartbeat (1800 s; 600 s while a Halogen
//   slot row is published); never twice within 60 s. A failed post is retried
//   on the next tick after 60 s with the same snapshot, without a new read.
// A failed oracle run (non-zero exit, timeout, not seat-capacity/1) counts as
// an attempt: the 120 s spacing holds, nothing is posted, and the floor's copy
// ages to STALE on its own, which refuses admission (fail closed).

import { REFRESH_POLICY, afterAttempt, initialRefreshState, refreshDue } from "./refreshPolicy.mjs"
import { DEFAULT_POLICY, decidePush, stateAfterPush } from "./seatCapacity.mjs"
import { snapshotFromSeatsV1 } from "./seatsOracle.mjs"

export const PUSH_RETRY_SECONDS = 60

export const initialGentleState = () => ({ refresh: initialRefreshState(), push: {}, last: null, previous_utilization: null, pending: null })

/** Utilization per (seat, window) of a snapshot, for "is anyone spending". */
export const utilizationKey = (snapshot) =>
  snapshot === null
    ? null
    : JSON.stringify(
        snapshot.seats.map((seat) => [seat.seat, seat.windows.map((w) => [w.kind, w.model, w.utilization_pct])])
      )

/** The highest utilization over binding seat-wide windows of dispatchable seats; null when none is known. */
export const bindingMaxPct = (snapshot) => {
  if (snapshot === null) return null
  const known = snapshot.seats
    .filter((seat) => seat.dispatchable)
    .flatMap((seat) => seat.windows)
    .filter((w) => w.binding && w.kind !== "model_scoped" && typeof w.utilization_pct === "number")
    .map((w) => w.utilization_pct)
  return known.length === 0 ? null : Math.max(...known)
}

/** Every reset instant the last snapshot states. */
export const resetsOf = (snapshot) =>
  snapshot === null ? [] : snapshot.seats.flatMap((seat) => seat.windows.map((w) => w.resets_at)).filter((r) => r !== null)

/**
 * Whether the oracle is due now.
 * @param input `{ nowMs, demandAtMs, preDispatch }`; demandAtMs is the newest demand marker's mtime or null.
 */
export const planRead = (state, input, policy = REFRESH_POLICY) => {
  const s = state ?? initialGentleState()
  const demand = typeof input.demandAtMs === "number" && input.nowMs - input.demandAtMs < policy.activeSeconds * 1000
  const moving = s.previous_utilization !== null && s.last !== null && utilizationKey(s.last) !== s.previous_utilization
  return refreshDue(s.refresh, {
    nowMs: input.nowMs,
    active: demand || moving,
    preDispatch: input.preDispatch === true,
    bindingMaxPct: bindingMaxPct(s.last),
    resets: resetsOf(s.last)
  }, policy)
}

/**
 * One tick. Effects:
 *   runOracle() -> Promise<unknown>  the parsed `seats --json` answer (throws on failure)
 *   post(snapshot) -> Promise<unknown>  the floor's answer (throws on failure)
 * @returns `{ state, events }`; events are log lines with no secret in them.
 */
export const tick = async (state, { nowMs, demandAtMs = null, preDispatch = false, config, runOracle, post, dryRun = false, pushPolicy = DEFAULT_POLICY, refreshPolicy = REFRESH_POLICY }) => {
  let s = { ...initialGentleState(), ...(state ?? {}) }
  const now = new Date(nowMs).toISOString()
  const events = []
  // A post that failed is retried with the same snapshot before any new read.
  if (s.pending !== null && !dryRun) {
    if (nowMs < Date.parse(s.pending.retry_at)) return { state: s, events: [{ at: now, event: "wait", reason: "push-retry", next_at: s.pending.retry_at }] }
    try {
      await post(s.pending.snapshot)
      s = { ...s, push: stateAfterPush(s.pending.snapshot, now), pending: null }
      events.push({ at: now, event: "pushed", reason: "retry", seats: s.last?.seats.map((seat) => seat.seat) ?? [] })
    } catch (error) {
      s = { ...s, pending: { ...s.pending, retry_at: new Date(nowMs + PUSH_RETRY_SECONDS * 1000).toISOString() } }
      return { state: s, events: [{ at: now, event: "push-failed", error: String(error?.message ?? error).slice(0, 200) }] }
    }
  }
  const due = planRead(s, { nowMs, demandAtMs, preDispatch }, refreshPolicy)
  if (!due.due) return { state: s, events: [...events, { at: now, event: "wait", reason: due.reason, next_at: due.next_at }] }
  let built
  try {
    const doc = await runOracle()
    built = snapshotFromSeatsV1(doc, config, now)
  } catch (error) {
    s = { ...s, refresh: afterAttempt(s.refresh, { kind: "error" }, nowMs, null, refreshPolicy) }
    return { state: s, events: [...events, { at: now, event: "read-failed", reason: due.reason, error: String(error?.message ?? error).slice(0, 200) }] }
  }
  s = {
    ...s,
    refresh: afterAttempt(s.refresh, { kind: "success" }, nowMs, null, refreshPolicy),
    previous_utilization: utilizationKey(s.last),
    last: built.snapshot
  }
  events.push({ at: now, event: "read", reason: due.reason, seats: built.snapshot.seats.map((seat) => seat.seat), skipped: built.skipped })
  const decision = decidePush(s.push, built.snapshot, nowMs, pushPolicy)
  if (dryRun) return { state: s, events: [...events, { at: now, event: "dry-run", decision, snapshot: built.snapshot }] }
  if (!decision.push) return { state: s, events: [...events, { at: now, event: "not-pushed", reason: decision.reason }] }
  try {
    const answer = await post(built.snapshot)
    s = { ...s, push: stateAfterPush(built.snapshot, now) }
    const results = answer?.report?.results ?? answer?.results ?? null
    events.push({ at: now, event: "pushed", reason: decision.reason, changed: decision.changed, results })
  } catch (error) {
    s = { ...s, pending: { snapshot: built.snapshot, retry_at: new Date(nowMs + PUSH_RETRY_SECONDS * 1000).toISOString() } }
    events.push({ at: now, event: "push-failed", error: String(error?.message ?? error).slice(0, 200) })
  }
  return { state: s, events }
}

/**
 * Posts a snapshot to `<base>/capacity/snapshots` with the bearer. The token is
 * sent and never echoed: an error names the status, not the header.
 */
export const postSnapshot = async ({ base, token, snapshot, fetchImpl = fetch }) => {
  const url = `${base.replace(/\/+$/, "")}/capacity/snapshots`
  let response
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(snapshot),
      signal: AbortSignal.timeout(20_000)
    })
  } catch (error) {
    throw new Error(`POST /capacity/snapshots did not complete: ${error?.name ?? "Error"}`)
  }
  const body = await response.text()
  if (response.status !== 200) throw new Error(`POST /capacity/snapshots answered ${response.status}: ${body.slice(0, 200)}`)
  try {
    return JSON.parse(body)
  } catch {
    throw new Error("POST /capacity/snapshots answered 200 with a body that is not JSON")
  }
}
