// The gentle refresh policy (SCOUT.md 5.5), pinned case by case and by property.
import fc from "fast-check"
import { describe, expect, it } from "vitest"

import { afterAttempt, initialRefreshState, REFRESH_POLICY, refreshDue } from "../src/refreshPolicy.mjs"

const T0 = Date.parse("2026-09-23T06:00:00Z")
const s = (seconds) => T0 + seconds * 1000
const ok = (at) => afterAttempt(initialRefreshState(), { kind: "success" }, at, 1)
const due = (state, input) => refreshDue(state, { active: false, preDispatch: false, bindingMaxPct: null, resets: [], credentialsMtimeMs: 1, ...input })

describe("refreshDue", () => {
  it("P1 the first read is due", () => {
    expect(due(initialRefreshState(), { nowMs: T0 })).toMatchObject({ due: true, reason: "first-read" })
  })

  it("P2 idle: 900 s between reads", () => {
    const state = ok(T0)
    expect(due(state, { nowMs: s(899) }).due).toBe(false)
    expect(due(state, { nowMs: s(900) })).toMatchObject({ due: true, reason: "idle" })
    expect(due(state, { nowMs: s(600) }).next_at).toBe(new Date(s(900)).toISOString())
  })

  it("P3 active: 300 s, and 180 s once a binding window is at 85 percent", () => {
    const state = ok(T0)
    expect(due(state, { nowMs: s(299), active: true }).due).toBe(false)
    expect(due(state, { nowMs: s(300), active: true }).due).toBe(true)
    expect(due(state, { nowMs: s(179), active: true, bindingMaxPct: 85 }).due).toBe(false)
    expect(due(state, { nowMs: s(180), active: true, bindingMaxPct: 85 }).due).toBe(true)
    expect(due(state, { nowMs: s(180), active: false, bindingMaxPct: 99 }).due).toBe(false)
  })

  it("P4 the hard 120 s minimum holds over every other reason", () => {
    const failed = afterAttempt(ok(T0 - 3600_000), { kind: "error" }, T0, 1)
    expect(due(failed, { nowMs: s(119), active: true, preDispatch: true }).reason).toBe("min-spacing")
    expect(due(failed, { nowMs: s(120), active: true }).due).toBe(true)
  })

  it("P5 a reset boundary is read at resets_at + 90 s", () => {
    const state = ok(T0)
    const resets = [new Date(s(200)).toISOString()]
    expect(due(state, { nowMs: s(289), resets }).due).toBe(false)
    expect(due(state, { nowMs: s(290), resets })).toMatchObject({ due: true, reason: "reset-boundary" })
    expect(due(state, { nowMs: s(150), resets }).next_at).toBe(new Date(s(290)).toISOString())
    // a boundary already covered by a later read is not read again
    expect(due(ok(s(300)), { nowMs: s(500), resets }).due).toBe(false)
  })

  it("P6 pre-dispatch reads a reading older than 300 s", () => {
    const state = ok(T0)
    expect(due(state, { nowMs: s(300), preDispatch: true }).due).toBe(false)
    expect(due(state, { nowMs: s(301), preDispatch: true })).toMatchObject({ due: true, reason: "pre-dispatch" })
  })

  it("P7 429: Retry-After or 120 s x 2^k capped at 960 s, reset on success", () => {
    let state = initialRefreshState()
    const waits = []
    let at = T0
    for (let k = 0; k < 5; k += 1) {
      state = afterAttempt(state, { kind: "rate-limited", retryAfterSeconds: null }, at, 1)
      const next = Date.parse(state.next_allowed_at)
      waits.push((next - at) / 1000)
      expect(due(state, { nowMs: next - 1 }).reason).toBe("backoff")
      at = next
    }
    expect(waits).toEqual([120, 240, 480, 960, 960])
    const honoured = afterAttempt(initialRefreshState(), { kind: "rate-limited", retryAfterSeconds: 700 }, T0, 1)
    expect(Date.parse(honoured.next_allowed_at) - T0).toBe(700_000)
    expect(afterAttempt(state, { kind: "success" }, at, 1).backoff_k).toBe(0)
  })

  it("P8 an auth failure makes no call until the credentials file changes", () => {
    const state = afterAttempt(ok(T0 - 3600_000), { kind: "auth-failed" }, T0, 42)
    expect(due(state, { nowMs: s(100000), credentialsMtimeMs: 42 }).reason).toBe("auth-failed")
    expect(due(state, { nowMs: s(100000), credentialsMtimeMs: 43 }).due).toBe(true)
  })

  it("property: two network attempts are never closer than the hard minimum", () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            step: fc.integer({ min: 1, max: 400 }),
            active: fc.boolean(),
            pre: fc.boolean(),
            pct: fc.option(fc.integer({ min: 0, max: 100 })),
            outcome: fc.constantFrom("success", "rate-limited", "error")
          }),
          { maxLength: 60 }
        ),
        (steps) => {
          let state = initialRefreshState()
          let now = T0
          let last = null
          for (const step of steps) {
            now += step.step * 1000
            const d = due(state, { nowMs: now, active: step.active, preDispatch: step.pre, bindingMaxPct: step.pct })
            if (!d.due) continue
            if (last !== null && now - last < REFRESH_POLICY.minSpacingSeconds * 1000) return false
            last = now
            state = afterAttempt(state, { kind: step.outcome, retryAfterSeconds: null }, now, 1)
          }
          return true
        }
      )
    )
  })

  it("property: next_at is never at or before now when a read is not due", () => {
    fc.assert(
      fc.property(fc.integer({ min: 0, max: 5000 }), fc.boolean(), fc.integer({ min: -2000, max: 5000 }), (after, active, reset) => {
        const d = due(ok(T0), { nowMs: s(after), active, resets: [new Date(s(reset)).toISOString()] })
        return d.due || d.next_at === null || Date.parse(d.next_at) > s(after)
      })
    )
  })
})
