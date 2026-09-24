// The seats oracle verbs (parity with the dotfiles `seats --pick` and `--check`).
import { describe, expect, it } from "vitest"
import { admits, bar, checkSeat, pickSeat } from "../src/seats.ts"
import type { SeatRow } from "../src/client.ts"

const row = (seat: string, o: Partial<SeatRow> = {}): SeatRow => ({
  seat, grade: "MEASURED", staleness: "MEASURED", headroom_pct: 50, next_reset_at: "2026-09-24T12:00:00Z", wip: 0, admit: null, reason: null, ...o
})

describe("pickSeat", () => {
  it("takes the most headroom among admitting seats", () => {
    expect(pickSeat([row("a", { headroom_pct: 20 }), row("b", { headroom_pct: 70 }), row("c", { headroom_pct: 90, admit: false })])!.seat).toBe("b")
  })
  it("breaks a headroom tie by fewer jobs in flight, then by name", () => {
    expect(pickSeat([row("z", { wip: 2 }), row("y", { wip: 1 }), row("x", { wip: 1 })])!.seat).toBe("x")
  })
  it("returns null when nothing admits: an empty floor, all refused, all unknown or stale", () => {
    expect(pickSeat([])).toBeNull()
    expect(pickSeat([row("a", { admit: false }), row("b", { grade: "UNKNOWN", headroom_pct: null }), row("c", { staleness: "STALE" }), row("d", { headroom_pct: 0 })])).toBeNull()
  })
  it("defers to the floor's own admission when it answered", () => {
    expect(admits(row("a", { staleness: "STALE", admit: true }))).toBe(true)
    expect(admits(row("a", { headroom_pct: 99, admit: false }))).toBe(false)
  })
})

describe("checkSeat", () => {
  const rows = [row("cc", { headroom_pct: 42.25 }), row("cc2", { admit: false, reason: "headroom 3% below 10%", headroom_pct: 3 }), row("qwen", { grade: "UNKNOWN", headroom_pct: null })]
  it("0 with headroom, 1 when refused, 2 when unmeasurable or absent", () => {
    expect(checkSeat(rows, "cc")).toEqual({ code: 0, line: "cc: 42.3% headroom, grade MEASURED, resets 2026-09-24T12:00:00Z" })
    expect(checkSeat(rows, "cc2")).toMatchObject({ code: 1, line: expect.stringContaining("refused: headroom 3% below 10%") })
    expect(checkSeat(rows, "qwen")).toMatchObject({ code: 2, line: expect.stringContaining("unmeasurable") })
    expect(checkSeat(rows, "nope")).toEqual({ code: 2, line: "nope: no such seat" })
  })
})

describe("bar", () => {
  it("fills in proportion to the used part of the window", () => {
    expect(bar(100)).toBe("..........")
    expect(bar(0)).toBe("##########")
    expect(bar(35)).toBe("#######...")
    expect(bar(null)).toBe("??????????")
    expect(bar(-5)).toBe("##########")
  })
})
