// Successor review r4: the pusher placed limit rows the way capacity round 3
// placed them in src/capacity/tally-meters.ts. A row it cannot place (an
// unknown kind, a scoped row naming no model) is a binding seven_day window
// graded UNKNOWN with its reset kept, and model_windows_complete is withdrawn.
import { describe, expect, it } from "vitest"
import { windowsFromLimits, windowsFromUsage, limitsComplete } from "../src/usageSource.mjs"

const reset = "2026-09-23T09:59:59Z"
const limits = [
  { kind: "session", percent: 10, resets_at: reset, severity: "normal", scope: null },
  { kind: "weekly_all", percent: 20, resets_at: reset, severity: "normal", scope: null },
  { kind: "weekly_scoped", percent: 100, resets_at: reset, severity: "critical", scope: { model: null, surface: "claude_code" } },
  { kind: "something_new", percent: 100, resets_at: reset, severity: "critical", scope: null }
]

describe("r4: the pusher never drops a limit row it cannot place", () => {
  it("unknown kind and a model-less scoped row become UNKNOWN seven_day windows with their resets", () => {
    const { windows, unmapped } = windowsFromLimits(limits)
    expect(unmapped).toBe(2)
    const unknown = windows.filter((w) => w.grade === "UNKNOWN")
    expect(unknown).toHaveLength(2)
    for (const w of unknown) {
      expect(w).toMatchObject({ kind: "seven_day", model: null, binding: true, utilization_pct: null, resets_at: reset })
    }
    expect(windowsFromUsage({ limits })).toEqual(windows)
  })
  it("model_windows_complete is claimed only when every row was placed", () => {
    expect(limitsComplete({ limits })).toBe(false)
    expect(limitsComplete({ limits: limits.slice(0, 2) })).toBe(true)
    expect(limitsComplete({ five_hour: {}, seven_day: {} })).toBe(false)
  })
})
