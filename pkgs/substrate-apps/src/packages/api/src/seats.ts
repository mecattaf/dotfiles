// The `seats` CLI's oracle verbs, over the floor's seat rows (parity with the dotfiles `seats` CLI, 2026-09-24).
// Pure: every function reads SeatRow values the client already decoded, so the CLI and the MCP server answer alike.
//
//   pickSeat   the seat with the most headroom that the floor would admit now, or null (`seats --pick`, exit 1)
//   checkSeat  exit-code oracle for one seat: 0 headroom, 1 spent, 2 unmeasurable (`seats --check SEAT`)
//   bar        the ten-cell headroom bar the table prints
import type { SeatRow } from "./client.ts"

/** Grades that carry a number worth planning on. UNKNOWN never does. */
const NUMBERED = new Set(["MEASURED", "STALE", "PROJECTED", "ESTIMATED"])

/** A row with a number: a grade other than UNKNOWN and a headroom the floor computed. */
export const measurable = (r: SeatRow): boolean => NUMBERED.has(r.grade) && r.headroom_pct !== null

/**
 * Would this row take a job now. The floor's own admission decides when it answered (admit is boolean when the
 * view was asked for a model); without an answer, a measurable row with headroom above zero does, except a
 * STALE or UNKNOWN staleness, which fails closed as admitSeat does.
 */
export const admits = (r: SeatRow): boolean => {
  if (r.admit !== null) return r.admit
  return measurable(r) && (r.headroom_pct ?? 0) > 0 && r.staleness === "MEASURED"
}

/** The admitting seat with the most headroom; ties go to the fewer jobs in flight, then the seat name. */
export const pickSeat = (rows: ReadonlyArray<SeatRow>): SeatRow | null => {
  const ok = rows.filter(admits)
  if (ok.length === 0) return null
  return [...ok].sort((a, b) => (b.headroom_pct ?? -1) - (a.headroom_pct ?? -1) || a.wip - b.wip || a.seat.localeCompare(b.seat))[0]!
}

export interface SeatCheck { readonly code: 0 | 1 | 2; readonly line: string }

/** The `--check` oracle. 2 when the seat is absent or has no number; 1 when it would not admit; 0 otherwise. */
export const checkSeat = (rows: ReadonlyArray<SeatRow>, seat: string): SeatCheck => {
  const r = rows.find((x) => x.seat === seat)
  if (r === undefined) return { code: 2, line: `${seat}: no such seat` }
  if (!measurable(r)) return { code: 2, line: `${seat}: unmeasurable (grade ${r.grade}, staleness ${r.staleness})` }
  const resets = r.next_reset_at ?? "unknown"
  const head = `${seat}: ${r.headroom_pct!.toFixed(1)}% headroom, grade ${r.grade}, resets ${resets}`
  return admits(r) ? { code: 0, line: head } : { code: 1, line: `${head}, refused${r.reason ? `: ${r.reason}` : ""}` }
}

/** Ten cells, filled in proportion to the part of the window already used; `?` cells for no number. */
export const bar = (headroomPct: number | null, width = 10): string => {
  if (headroomPct === null) return "?".repeat(width)
  const used = Math.min(100, Math.max(0, 100 - headroomPct))
  const filled = Math.round((used / 100) * width)
  return "#".repeat(filled) + ".".repeat(width - filled)
}
