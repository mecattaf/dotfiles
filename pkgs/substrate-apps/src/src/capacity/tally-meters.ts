/**
 * ADAPTER, transitional: today's dotfiles feeder files onto `seat-capacity/2`.
 *
 * Tom, 2026-09-23: "tally is eventually to be removed from my dotfikes, let's
 * not build with it in mind." So this is the ONE module under `src/capacity/`
 * that knows the `seat-meter/1` row and the `.window-cache-<seat>.json` usage
 * cache. Admission never sees them: it sees the `SeatCapacity` built here, and
 * the day a publisher writes the snapshot, `snapshotFileSource` replaces this
 * file and nothing else moves.
 *
 * Mapping (field names MEASURED by the capacity scout, SCOUT.md section 2):
 *  - cc-shaped rows: `window.primary` (300 min) is `five_hour`,
 *    `window.secondary` (10080 min) is `seven_day`; `observed_at` of the
 *    reading is `reading_observed_at`, else the restamp minus the stated age.
 *    `STALE-MEASURED` with a stated age is a measurement of known age.
 *  - the usage cache's `usage.limits[]` rows of kind `weekly_scoped` become
 *    `model_scoped` windows (OI-3). Only `limits[]` is read; `usage.spend` is
 *    never touched. `model_windows_complete` is claimed only when the cache is
 *    at least as new as the meter's reading: an older cache may miss a limit.
 *  - slot rows (`gpu-worker.json`) become a halogen seat with `slots`.
 *  - `codex.json` is a third party's login: read, never dispatchable.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { decodeSeatCapacity, type SeatCapacity } from "@substrate/planning";
import type { CapacitySource, SeatCapacityRead } from "./source.ts";

type Provider = "claude" | "halogen" | "codex";

/** This scheduler's seat ids onto the feeder's file stems and providers. */
export const TALLY_SEAT_FILES: Readonly<Record<string, { readonly stem: string; readonly provider: Provider }>> = {
  cc: { stem: "cc", provider: "claude" },
  cc2: { stem: "cc2", provider: "claude" },
  halogen: { stem: "gpu-worker", provider: "halogen" },
  codex: { stem: "codex", provider: "codex" },
};

const obj = (v: unknown): Record<string, unknown> | undefined =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const toIso = (ms: number): string => new Date(ms).toISOString();

/** Normalize any parseable instant to UTC `Z`; null when it is not one. */
function instant(v: unknown): string | null {
  const s = str(v);
  if (s === null) return null;
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? toIso(ms) : null;
}

function window(kind: "five_hour" | "seven_day", w: Record<string, unknown> | undefined) {
  if (w === undefined) return undefined;
  return {
    kind,
    model: null,
    binding: true,
    minutes: kind === "five_hour" ? 300 : 10080,
    utilization_pct: num(w["utilization_pct"]),
    resets_at: instant(w["resets_at"]),
    severity: null,
    grade: "MEASURED" as const,
  };
}

/** The reading instant of a meter row, never the restamp. */
function readingObservedAt(m: Record<string, unknown>): string | null {
  const direct = instant(m["reading_observed_at"]);
  if (direct !== null) return direct;
  const restamp = instant(m["observed_at"]);
  const age = num(m["reading_age_seconds"]);
  if (restamp === null) return null;
  return age === null ? restamp : toIso(Date.parse(restamp) - age * 1000);
}

/** Build a SeatCapacity from one meter row and, for Claude, its usage cache. Pure. */
export function seatFromTallyFiles(
  seatId: string,
  provider: Provider,
  meterText: string,
  cacheText: string | undefined,
): { ok: true; seat: SeatCapacity } | { ok: false; error: string } {
  let m: Record<string, unknown> | undefined;
  try {
    m = obj(JSON.parse(meterText));
  } catch (e) {
    return { ok: false, error: `meter row is not JSON: ${(e as Error).message}` };
  }
  if (m === undefined) return { ok: false, error: "meter row is not an object" };
  if (m["schema_version"] !== "seat-meter/1") {
    return { ok: false, error: `meter row schema_version ${JSON.stringify(m["schema_version"] ?? null)} is not seat-meter/1` };
  }
  const grade = str(m["grade"]) ?? str(m["running_grade"]);
  const statedAge = num(m["reading_age_seconds"]) !== null || instant(m["reading_observed_at"]) !== null;
  const measured = grade === "MEASURED" || (grade === "STALE-MEASURED" && statedAge);
  const observed = provider === "halogen" ? instant(m["observed_at"]) : readingObservedAt(m);
  if (observed === null) return { ok: false, error: "meter row carries no reading instant" };

  const draft: Record<string, unknown> = {
    seat: seatId,
    provider,
    owner: provider === "codex" ? "third-party" : "tom",
    dispatchable: provider !== "codex",
    dispatchable_reason: provider === "codex" ? "third-party login" : null,
    plan: null,
    slots: null,
    windows: [],
    observed_at: observed,
    source: { kind: "tally-seat-meter/1", detail: null },
    grade: measured ? "MEASURED" : "UNKNOWN",
    stale_reason: str(m["stale_reason"]),
  };

  if (provider === "halogen") {
    const capacity = num(m["capacity"]);
    const holders = num(m["holders"]);
    draft["slots"] = capacity !== null && holders !== null ? { capacity, holders } : null;
  } else {
    const w = obj(m["window"]);
    const windows: unknown[] = [];
    if (w !== undefined && w["kind"] === "nested") {
      const five = window("five_hour", obj(w["primary"]));
      const week = window("seven_day", obj(w["secondary"]));
      if (five !== undefined) windows.push(five);
      if (week !== undefined) windows.push(week);
    } else if (w !== undefined && w["minutes"] === 10080) {
      windows.push(window("seven_day", w));
    }
    let complete = false;
    if (provider === "claude" && cacheText !== undefined) {
      try {
        const c = obj(JSON.parse(cacheText));
        const limits = obj(c?.["usage"])?.["limits"];
        const cacheObserved = instant(c?.["observed_at"]);
        // A scoped row is never fresher than the file it came from (successor
        // review 2026-09-23: a days-old cache's row was admitted as MEASURED
        // under the meter's fresh observed_at). A cache older than the meter's
        // reading, or undated, gives STALE rows, which admission refuses as
        // window-unknown with raise_demand.
        const cacheFresh = cacheObserved !== null && Date.parse(cacheObserved) >= Date.parse(observed);
        if (Array.isArray(limits)) {
          // Capacity review round 3 (ported): a limit row this adapter cannot
          // place (a kind it does not know, or a scoped row naming no model,
          // such as one scoped by surface only) is never dropped. It becomes a
          // binding seven_day window graded UNKNOWN with its reset kept, so the
          // gate refuses window-unknown instead of reading a missing row as
          // headroom, and the reading withdraws model_windows_complete.
          let unmapped = 0;
          for (const l of limits) {
            const row = obj(l);
            const kind = row?.["kind"];
            if (kind === "session" || kind === "weekly_all") continue; // the meter row carries these
            const scopeModel = obj(obj(row?.["scope"])?.["model"]);
            const model = kind === "weekly_scoped" ? (str(scopeModel?.["display_name"]) ?? str(scopeModel?.["id"])) : null;
            if (model === null) {
              unmapped++;
              windows.push({
                kind: "seven_day",
                model: null,
                binding: true,
                minutes: 10080,
                utilization_pct: null,
                resets_at: instant(row?.["resets_at"]),
                severity: null,
                grade: "UNKNOWN",
              });
              continue;
            }
            windows.push({
              kind: "model_scoped",
              model,
              binding: true,
              minutes: 10080,
              utilization_pct: num(row!["percent"]),
              resets_at: instant(row!["resets_at"]),
              severity: str(row!["severity"]),
              grade: cacheFresh ? "MEASURED" : "STALE",
            });
          }
          complete = cacheFresh && unmapped === 0;
        }
      } catch {
        complete = false;
      }
    }
    draft["windows"] = windows;
    draft["model_windows_complete"] = complete;
  }

  try {
    return { ok: true, seat: decodeSeatCapacity(draft) };
  } catch (e) {
    return { ok: false, error: `the adapted reading does not decode: ${(e as Error).message.slice(0, 300)}` };
  }
}

/** The adapter as a CapacitySource over one meters directory. */
export function tallyMeterSource(
  metersDir: string,
  opts: { readonly readFile?: (p: string) => string } = {},
): CapacitySource {
  const read = opts.readFile ?? ((p: string) => readFileSync(p, "utf8"));
  return {
    name: `tally-meters:${metersDir}`,
    read(seatId): SeatCapacityRead {
      const known = TALLY_SEAT_FILES[seatId];
      if (known === undefined) return { ok: false, error: `no meter file is known for seat ${JSON.stringify(seatId)}`, from: metersDir };
      const meterPath = join(metersDir, `${known.stem}.json`);
      let meterText: string;
      try {
        meterText = read(meterPath);
      } catch (e) {
        return { ok: false, error: `meter row unreadable: ${(e as Error).message}`, from: meterPath };
      }
      let cacheText: string | undefined;
      if (known.provider === "claude") {
        try {
          cacheText = read(join(metersDir, `.window-cache-${known.stem}.json`));
        } catch {
          cacheText = undefined;
        }
      }
      const r = seatFromTallyFiles(seatId, known.provider, meterText, cacheText);
      return r.ok ? { ok: true, seat: r.seat, from: meterPath } : { ok: false, error: r.error, from: meterPath };
    },
  };
}
