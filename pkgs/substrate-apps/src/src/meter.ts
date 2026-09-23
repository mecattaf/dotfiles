/**
 * Seat meter rows, and the refusal rule that guards admission.
 *
 * Two halves, deliberately split:
 *
 *  - `readMeterRow` is impure. It opens a file, parses it with Effect `Schema`
 *    (never a cast), and may read a clock in exactly one place, named below.
 *  - `evaluateMeter` is pure. It is a function of (parsed row, bounds) and
 *    nothing else: no clock, no filesystem, no environment. That is what makes
 *    a fabricated row a complete test fixture, which is the single property
 *    carried over conceptually from tally-ts-sdk (see DESIGN.md section 10).
 *
 * The bounds are data. The staleness bound and the per-seat cap are passed in,
 * never derived here, so that either can be struck without editing this file.
 */
import { readFileSync } from "node:fs";
import { Schema } from "effect";

/**
 * The raw file, as the three real meter files are actually shaped
 * (MEASURED 2026-09-22 against cc.json, codex.json, gpu-worker.json).
 *
 * Only `schema_version` and `seat` are required. Everything else is optional
 * BECAUSE the three files genuinely disagree:
 *
 *  - `cc.json` carries `grade`, `reading_age_seconds`, `reading_observed_at`,
 *    `weekly_utilization_pct` and a nested `window`.
 *  - `codex.json` carries `grade` and `utilization_pct` but has NO
 *    `reading_age_seconds`, NO `reading_observed_at`, and no
 *    `weekly_utilization_pct` key at all (the brief said null; MEASURED it is
 *    absent). Its `window` is flat, `kind: "rolling"`.
 *  - `gpu-worker.json` carries NO top-level `grade` (it carries
 *    `running_grade`), no age field, no weekly field, and a slot row instead
 *    of a budget row: `capacity` and `holders`, with `window.kind: "none"`.
 *
 * A missing key is therefore a fact about the seat, not a parse failure. The
 * refusal rule, not the schema, decides what a missing key costs.
 */
export const MeterFile = Schema.Struct({
  schema_version: Schema.String,
  seat: Schema.String,
  grade: Schema.optionalKey(Schema.String),
  running_grade: Schema.optionalKey(Schema.String),
  observed_at: Schema.optionalKey(Schema.String),
  reading_age_seconds: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  reading_observed_at: Schema.optionalKey(Schema.NullOr(Schema.String)),
  utilization_pct: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  weekly_utilization_pct: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  window_remaining_pct: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  capacity: Schema.optionalKey(Schema.Number),
  holders: Schema.optionalKey(Schema.Number),
  window: Schema.optionalKey(Schema.Unknown),
});

export type MeterFile = typeof MeterFile.Type;

export const decodeMeterFile = Schema.decodeUnknownSync(MeterFile);

/** Where the grade in a normalized row came from. Reported, never guessed at. */
export type GradeSource = "grade" | "running_grade" | "absent";

/** Where the age in a normalized row came from. Reported, never guessed at. */
export type AgeSource = "reading_age_seconds" | "observed_at" | "absent";

/**
 * One meter row, normalized. This is the only thing the refusal rule sees.
 */
export interface MeterRow {
  readonly seat: string;
  readonly schemaVersion: string;
  readonly grade: string | undefined;
  readonly gradeSource: GradeSource;
  readonly observedAt: string | undefined;
  readonly readingAgeSeconds: number | undefined;
  readonly ageSource: AgeSource;
  readonly utilizationPct: number | undefined;
  readonly weeklyUtilizationPct: number | undefined;
  /** Slot rows only: gpu-worker declares capacity 1 and holders. */
  readonly capacity: number | undefined;
  readonly holders: number | undefined;
  /**
   * OI-2 of the 2026-09-23 evals. Every usage window the row's `window` object
   * carries: the nested cc shape gives `five_hour` (primary, 300 min) and
   * `seven_day` (secondary, 10080 min); the flat codex shape gives `seven_day`.
   * Optional so a fabricated row without it keeps its old meaning.
   */
  readonly windows?: readonly MeterWindow[];
}

/** One usage window read off a meter row's `window` object. */
export interface MeterWindow {
  readonly kind: "five_hour" | "seven_day";
  /** Undefined when the file carries no number: never headroom. */
  readonly utilizationPct: number | undefined;
  readonly resetsAt: string | undefined;
}

/** Parse a row's `window` object into its usage windows. Pure; unknown shapes give none. */
export function meterWindows(raw: unknown): MeterWindow[] {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return [];
  const w = raw as Record<string, unknown>;
  const one = (x: unknown): MeterWindow | undefined => {
    if (x === null || typeof x !== "object" || Array.isArray(x)) return undefined;
    const o = x as Record<string, unknown>;
    const minutes = o["minutes"];
    const kind = minutes === 300 ? "five_hour" : minutes === 10080 ? "seven_day" : undefined;
    if (kind === undefined) return undefined;
    const u = o["utilization_pct"];
    const r = o["resets_at"];
    return {
      kind,
      utilizationPct: typeof u === "number" && Number.isFinite(u) ? u : undefined,
      resetsAt: typeof r === "string" ? r : undefined,
    };
  };
  if (w["kind"] === "nested") {
    return [one(w["primary"]), one(w["secondary"])].filter((x): x is MeterWindow => x !== undefined);
  }
  const flat = one(w);
  return flat === undefined ? [] : [flat];
}

/** Which figure a seat's cap is compared against. `none` means the seat has no budget row. */
export type UtilizationField = "weekly_utilization_pct" | "utilization_pct" | "none";

export interface MeterBounds {
  /** A row older than this is refused. Data, not a constant of this module. */
  readonly stalenessBoundSeconds: number;
  /**
   * The figure this seat's cap is read from.
   *  - `cc` uses `weekly_utilization_pct`.
   *  - `codex` uses `utilization_pct`, because its weekly figure is not a
   *    number in the file. The two are never compared and never added: they
   *    are two organizations on two clocks.
   *  - `halogen` uses `none`.
   */
  readonly utilizationField: UtilizationField;
  /** The cap, or null for a seat with no budget row. Data. */
  readonly capPct: number | null;
}

export type MeterRefusalReason =
  | "meter-missing"
  | "meter-schema-unknown"
  | "meter-not-measured"
  | "meter-stale"
  | "meter-at-cap"
  | "meter-window-at-cap";

export type MeterDecision =
  | { readonly kind: "ADMIT"; readonly detail: string }
  | { readonly kind: "REFUSE"; readonly reason: MeterRefusalReason; readonly detail: string };

export const METER_SCHEMA_VERSION = "seat-meter/1";

/**
 * The refusal rule. Pure: a function of (parsed row, bounds), reading no clock
 * and touching no filesystem. The caller reads the file and passes the row in,
 * passing null when the file is missing or does not parse.
 *
 * The six outcomes are evaluated in this fixed order.
 */
export function evaluateMeter(
  row: MeterRow | null | undefined,
  bounds: MeterBounds,
): MeterDecision {
  // 1. The file is missing or does not parse.
  if (row === null || row === undefined) {
    return { kind: "REFUSE", reason: "meter-missing", detail: "no row: file missing or unparsable" };
  }

  // 2. An unknown schema version is not read optimistically.
  if (row.schemaVersion !== METER_SCHEMA_VERSION) {
    return {
      kind: "REFUSE",
      reason: "meter-schema-unknown",
      detail: `schema_version ${JSON.stringify(row.schemaVersion)} is not ${JSON.stringify(METER_SCHEMA_VERSION)}`,
    };
  }

  // 3. Anything other than a MEASURED grade is refused, quoting the grade.
  //
  // Capacity scout 2026-09-23: the feeder publishes STALE-MEASURED on about
  // half its ticks when a network read times out, while `reading_age_seconds`
  // still states the true age of the reading it holds. Such a row is a
  // measurement of known age, so it is admitted when that age is within the
  // bound (step 4). A STALE-MEASURED row whose age is only derivable from a
  // restamped `observed_at` is still refused: its reading age is unknown.
  const knownAgeStale = row.grade === "STALE-MEASURED" && row.ageSource === "reading_age_seconds";
  if (row.grade !== "MEASURED" && !knownAgeStale) {
    return {
      kind: "REFUSE",
      reason: "meter-not-measured",
      detail: `grade ${JSON.stringify(row.grade ?? null)} is not "MEASURED"`,
    };
  }

  // 4. An absent age is as bad as an old one: an unknown age is not a fresh one.
  if (row.readingAgeSeconds === undefined || !Number.isFinite(row.readingAgeSeconds)) {
    return {
      kind: "REFUSE",
      reason: "meter-stale",
      detail: `reading_age_seconds absent, bound ${bounds.stalenessBoundSeconds}s`,
    };
  }
  // A-08 of the 2026-09-23 review. A `observed_at` in the FUTURE of the instant
  // the caller passed produces a NEGATIVE age, which is not greater than any
  // bound, so the least trustworthy row there is was admitted as the freshest
  // one. `evaluateRelease` already refuses a reading from the future of `asOf`;
  // this rule now agrees with it. A refusal is never a rounding error.
  if (row.readingAgeSeconds < 0) {
    return {
      kind: "REFUSE",
      reason: "meter-stale",
      detail: `age ${row.readingAgeSeconds}s is negative: the reading is from the future of the instant it was compared against`,
    };
  }
  if (row.readingAgeSeconds > bounds.stalenessBoundSeconds) {
    return {
      kind: "REFUSE",
      reason: "meter-stale",
      detail: `age ${row.readingAgeSeconds}s exceeds bound ${bounds.stalenessBoundSeconds}s`,
    };
  }

  // 5. The cap. Skipped only for a seat whose bounds declare no budget figure.
  //    `halogen` is exactly that seat: it declares a slot row of capacity one
  //    and NO budget row. It is not metered for spend, so a missing budget
  //    figure is not a refusal for it. Every other seat with `utilizationField`
  //    set must produce a number here or it is refused as at cap, because an
  //    unreadable budget is not an open door.
  if (bounds.utilizationField !== "none" && bounds.capPct !== null) {
    const used =
      bounds.utilizationField === "weekly_utilization_pct"
        ? row.weeklyUtilizationPct
        : row.utilizationPct;
    if (used === undefined || !Number.isFinite(used)) {
      return {
        kind: "REFUSE",
        reason: "meter-at-cap",
        detail: `${bounds.utilizationField} is absent, cap ${bounds.capPct}`,
      };
    }
    if (used >= bounds.capPct) {
      return {
        kind: "REFUSE",
        reason: "meter-at-cap",
        detail: `${bounds.utilizationField} ${used} is at or above cap ${bounds.capPct}`,
      };
    }
  }

  // 5b. OI-2: every usage window the row carries binds a budget seat, not just
  //     the one figure `utilizationField` names. A five-hour window at 100
  //     percent used to be admitted because the cc bounds read the weekly
  //     figure alone. A window with no number is refused: unknown is not headroom.
  if (bounds.utilizationField !== "none" && bounds.capPct !== null) {
    for (const w of row.windows ?? []) {
      if (w.utilizationPct === undefined) {
        return {
          kind: "REFUSE",
          reason: "meter-window-at-cap",
          detail: `${w.kind} window has no utilization_pct, cap ${bounds.capPct}`,
        };
      }
      if (w.utilizationPct >= bounds.capPct) {
        return {
          kind: "REFUSE",
          reason: "meter-window-at-cap",
          detail: `${w.kind} window ${w.utilizationPct} is at or above cap ${bounds.capPct}`,
        };
      }
    }
  }

  // 6. Otherwise admit.
  const used =
    bounds.utilizationField === "none"
      ? "no budget row"
      : `${bounds.utilizationField} ${
          bounds.utilizationField === "weekly_utilization_pct"
            ? row.weeklyUtilizationPct
            : row.utilizationPct
        } under cap ${bounds.capPct}`;
  return { kind: "ADMIT", detail: `age ${row.readingAgeSeconds}s, ${used}` };
}

/** Parse an ISO-8601 instant to epoch milliseconds, or undefined. */
function instantMs(iso: string | undefined): number | undefined {
  if (typeof iso !== "string" || iso.length === 0) return undefined;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? undefined : ms;
}

export interface NormalizeOptions {
  /**
   * When the file carries no `reading_age_seconds`, derive one from
   * `observed_at` against this instant, in epoch milliseconds.
   *
   * This is the ONLY place a clock enters, it is supplied by the caller rather
   * than read here, and it is off by default: with it unset, a file that omits
   * the field is refused `meter-stale` exactly as the rule states. It exists
   * because `codex.json` and `gpu-worker.json` genuinely omit the field while
   * both carry `observed_at` (MEASURED 2026-09-22), so the age is derivable
   * from the file itself rather than assumed.
   */
  readonly deriveAgeFromObservedAtMs?: number | undefined;
}

/**
 * Map one parsed file onto the canonical row. Pure.
 *
 * `grade` falls back to `running_grade`, which is the field name the slot row
 * `gpu-worker.json` uses for the same fact (MEASURED). The fallback is
 * reported in `gradeSource` so a receipt can say which field it read.
 */
export function normalizeMeterRow(file: MeterFile, opts: NormalizeOptions = {}): MeterRow {
  const gradeSource: GradeSource =
    file.grade !== undefined ? "grade" : file.running_grade !== undefined ? "running_grade" : "absent";
  const grade = file.grade ?? file.running_grade;

  let readingAgeSeconds: number | undefined;
  let ageSource: AgeSource = "absent";
  if (typeof file.reading_age_seconds === "number" && Number.isFinite(file.reading_age_seconds)) {
    readingAgeSeconds = file.reading_age_seconds;
    ageSource = "reading_age_seconds";
  } else if (opts.deriveAgeFromObservedAtMs !== undefined) {
    const observed = instantMs(file.observed_at);
    if (observed !== undefined) {
      readingAgeSeconds = (opts.deriveAgeFromObservedAtMs - observed) / 1000;
      ageSource = "observed_at";
    }
  }

  return {
    seat: file.seat,
    schemaVersion: file.schema_version,
    grade,
    gradeSource,
    observedAt: file.observed_at,
    readingAgeSeconds,
    ageSource,
    utilizationPct: file.utilization_pct ?? undefined,
    weeklyUtilizationPct: file.weekly_utilization_pct ?? undefined,
    capacity: file.capacity,
    holders: file.holders,
    windows: meterWindows(file.window),
  };
}

export interface MeterRead {
  readonly path: string;
  readonly row: MeterRow | null;
  /** Why there is no row, when there is none. */
  readonly error: string | undefined;
}

/**
 * Read one meter file. Impure, and the only function here that touches disk.
 * A missing file, unreadable file or parse failure all yield `row: null`,
 * which the pure rule turns into `meter-missing`. Nothing under
 * /home/tom/.local/state/tally-rewrite/ is ever written.
 */
export function readMeterRow(
  path: string,
  opts: NormalizeOptions & { readonly readFile?: (p: string) => string } = {},
): MeterRead {
  const read = opts.readFile ?? defaultReadFile;
  let text: string;
  try {
    text = read(path);
  } catch (e) {
    return { path, row: null, error: `unreadable: ${(e as Error).message}` };
  }
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    return { path, row: null, error: `not JSON: ${(e as Error).message}` };
  }
  try {
    const file = decodeMeterFile(raw);
    return { path, row: normalizeMeterRow(file, opts), error: undefined };
  } catch (e) {
    return { path, row: null, error: `schema decode failed: ${(e as Error).message}` };
  }
}

function defaultReadFile(p: string): string {
  return readFileSync(p, "utf8");
}
