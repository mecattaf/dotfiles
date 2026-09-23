/**
 * Seat capacity fixtures, built from the shapes the fleet published on
 * 2026-09-23 (SCOUT.md section 2, MEASURED at 04:52Z): cc at five-hour 8
 * percent, weekly 72 percent, the Fable weekly-scoped row at 100 percent
 * `critical`; cc3 11.6 days old with both resets in the past. Every value is
 * parsed through the schema, so a fixture that would not survive the wire
 * cannot survive a test.
 */
import { Schema } from "effect";
import {
  SeatCapacity,
  SeatCapacitySnapshot,
  type CapacityWindow
} from "../src/schema/seatCapacity.ts";

const decodeSeat = Schema.decodeUnknownSync(SeatCapacity);
const decodeSnapshot = Schema.decodeUnknownSync(SeatCapacitySnapshot);

/** The instant cc's reading was observed. */
export const CC_OBSERVED = "2026-09-23T04:52:18.363166+00:00";
/** cc's five-hour reset. */
export const CC_FIVE_HOUR_RESET = "2026-09-23T08:49:59.526442+00:00";
/** cc's weekly reset. */
export const CC_WEEKLY_RESET = "2026-09-23T09:59:59.526461+00:00";

/** One window, with defaults for everything not given. */
export const window = (
  overrides: Partial<{ -readonly [K in keyof CapacityWindow]: CapacityWindow[K] }> & {
    readonly kind: CapacityWindow["kind"];
  }
): Record<string, unknown> => ({
  model: overrides.kind === "model_scoped" ? "Fable" : null,
  binding: true,
  minutes: overrides.kind === "five_hour" ? 300 : 10080,
  utilization_pct: 0,
  resets_at: null,
  severity: "normal",
  grade: "MEASURED",
  ...overrides
});

/** A Claude seat shaped like cc's live reading; every cell overridable. */
export const claudeSeat = (
  overrides: Record<string, unknown> = {}
): SeatCapacity =>
  decodeSeat({
    seat: "cc",
    provider: "claude",
    owner: "tom",
    dispatchable: true,
    dispatchable_reason: null,
    plan: null,
    slots: null,
    windows: [
      window({ kind: "five_hour", utilization_pct: 8, resets_at: CC_FIVE_HOUR_RESET }),
      window({ kind: "seven_day", utilization_pct: 72, resets_at: CC_WEEKLY_RESET }),
      window({
        kind: "model_scoped",
        model: "Fable",
        utilization_pct: 100,
        resets_at: "2026-09-23T09:59:59.526615+00:00",
        severity: "critical"
      })
    ],
    observed_at: CC_OBSERVED,
    source: { kind: "oauth-usage-endpoint", detail: "stamp-receipt.py window" },
    grade: "MEASURED",
    stale_reason: null,
    // Read from the usage cache's limits[]: every model limit is stated.
    model_windows_complete: true,
    ...overrides
  });

/** cc3 as it was republished: 11.6 days old, both resets passed, evicted. */
export const cc3Seat = (): SeatCapacity =>
  claudeSeat({
    seat: "cc3",
    dispatchable: false,
    dispatchable_reason: "evicted",
    observed_at: "2026-09-11T15:15:00Z",
    stale_reason: "token expired",
    windows: [
      window({ kind: "five_hour", utilization_pct: 12, resets_at: "2026-09-11T19:00:00Z" }),
      window({ kind: "seven_day", utilization_pct: 80, resets_at: "2026-09-12T11:00:00.199042+00:00" })
    ]
  });

/** A Halogen slot row. */
export const halogenSeat = (holders: number, capacity = 1): SeatCapacity =>
  decodeSeat({
    seat: "gpu-worker",
    provider: "halogen",
    owner: "tom",
    dispatchable: true,
    dispatchable_reason: null,
    plan: null,
    slots: { capacity, holders },
    windows: [],
    observed_at: CC_OBSERVED,
    source: { kind: "kernel-row", detail: null },
    grade: "MEASURED",
    stale_reason: null
  });

/** The Qwen plan seat: no utilization, a plan end date. */
export const qwenSeat = (): SeatCapacity =>
  decodeSeat({
    seat: "pi-qwencloud",
    provider: "qwen",
    owner: "tom",
    dispatchable: true,
    dispatchable_reason: null,
    plan: { expires_at: "2026-11-07T00:00:00Z" },
    slots: null,
    windows: [window({ kind: "seven_day", utilization_pct: null, resets_at: null })],
    observed_at: CC_OBSERVED,
    source: { kind: "hold-record", detail: null },
    grade: "MEASURED",
    stale_reason: null
  });

/** A snapshot around the given seats. */
export const snapshot = (
  seats: ReadonlyArray<SeatCapacity>,
  publishedAt = "2026-09-23T04:52:30Z",
  host = "coordinator"
): SeatCapacitySnapshot =>
  decodeSnapshot({
    schema_version: "seat-capacity/2",
    host,
    published_at: publishedAt,
    seats
  });

/** Adds seconds to an instant, returning ISO. */
export const plus = (instant: string, seconds: number): string =>
  new Date(Date.parse(instant) + seconds * 1000).toISOString();
