/**
 * Capacity projection, staleness and admission: pure functions of a reading and
 * a moment.
 *
 * Nothing here reads a clock. Every function takes the moment it answers for
 * (`asOf`) as an argument, so the Durable Object can answer "how much is left,
 * and until when" for any instant from the last reading alone, and a test can
 * pin any instant it likes. Instants are compared with `Date.parse`, never as
 * text (the same moment spelled with two UTC offsets sorts wrongly as a string).
 *
 * The rules (SCOUT.md sections 3 and 4):
 *
 * - Once a window's reset has passed, `five_hour` goes to 0 percent with
 *   `resets_at` null (the next one opens on first use), and the weekly kinds go
 *   to 0 percent with `resets_at` moved forward by whole weeks. Such a window is
 *   PROJECTED: good for planning, never for admission.
 * - Otherwise the grade follows the age of the reading: under 1200 s MEASURED,
 *   under 7200 s STALE, from 7200 s on UNKNOWN (utilization dropped, reset
 *   instants still used). Every edge is inclusive of its later side, like a
 *   reset (`resets_at <= asOf` has reset): at exactly `observed_at + 1200 s`
 *   the reading is already STALE. So `nextTransitionAt` can name the edge
 *   itself, and the projection at that instant differs from the one before.
 * - Admission fails closed: an unknown seat, a stale or unknown reading, a
 *   projected or unknown binding window, a reading dated in the future beyond
 *   the skew tolerance, all refuse.
 */
import { Option } from "effect";
import type {
  CapacityGrade,
  CapacityWindow,
  SeatCapacity,
  SeatJob,
  WindowKind
} from "../schema/seatCapacity.ts";
import modelFamilyData from "./model-families.json" with { type: "json" };

/** A reading younger than this (seconds) is MEASURED: the 15 min idle floor plus 5 min slack. */
const MEASURED_MAX_AGE_S = 1200;
/** A reading younger than this (seconds) is STALE; from this age on it is UNKNOWN for utilization. */
const STALE_MAX_AGE_S = 7200;
/** How far (seconds) a reading may be dated ahead of the reader's clock. */
export const CLOCK_SKEW_TOLERANCE_S = 120;

const SECOND_MS = 1000;
const WEEK_MS = 7 * 24 * 3600 * SECOND_MS;

const parse = (instant: string): number => Date.parse(instant);
const iso = (ms: number): string => new Date(ms).toISOString();

const asOfMs = (asOf: string): number => {
  const ms = parse(asOf);
  if (!Number.isFinite(ms)) throw new RangeError(`asOf is not an instant: ${asOf}`);
  return ms;
};

/** The age classes of a reading, from the staleness table. */
type StalenessGrade = "MEASURED" | "STALE" | "UNKNOWN";

/** How old a reading is at one moment, and what that makes it. */
interface Staleness {
  readonly grade: StalenessGrade;
  /** Seconds since the provider answered, floored at zero. */
  readonly age_seconds: number;
  /** Seconds the reading is dated AHEAD of `asOf`; zero when it is not. */
  readonly skew_seconds: number;
  /** Whether the skew exceeds `CLOCK_SKEW_TOLERANCE_S`. */
  readonly skewed: boolean;
}

/**
 * Classifies a reading by age at `asOf`.
 *
 * A reading dated slightly ahead of `asOf` is clock skew and counts as age 0;
 * one dated further ahead is flagged `skewed`, which admission refuses. The
 * projection itself ignores skew, so projecting forward in time stays
 * consistent however the moments are chosen.
 */
export const classifyStaleness = (observedAt: string, asOf: string): Staleness => {
  const delta = asOfMs(asOf) - parse(observedAt);
  const age = Math.max(0, delta) / SECOND_MS;
  const skew = Math.max(0, -delta) / SECOND_MS;
  const grade: StalenessGrade =
    !Number.isFinite(delta) || age >= STALE_MAX_AGE_S
      ? "UNKNOWN"
      : age >= MEASURED_MAX_AGE_S
        ? "STALE"
        : "MEASURED";
  return {
    grade,
    age_seconds: Number.isFinite(age) ? age : Number.POSITIVE_INFINITY,
    skew_seconds: Number.isFinite(skew) ? skew : 0,
    skewed: skew > CLOCK_SKEW_TOLERANCE_S
  };
};

/** Worse-of order for the non-projected grades. */
const RANK: Readonly<Record<Exclude<CapacityGrade, "PROJECTED">, number>> = {
  MEASURED: 0,
  STALE: 1,
  ESTIMATED: 2,
  UNKNOWN: 3
};

const worse = (
  left: Exclude<CapacityGrade, "PROJECTED">,
  right: Exclude<CapacityGrade, "PROJECTED">
): Exclude<CapacityGrade, "PROJECTED"> => (RANK[left] >= RANK[right] ? left : right);

/**
 * Projects one window to `asOf`, given when its reading was observed.
 *
 * `seatGrade` is the publisher's grade for the whole reading (PROJECTED counts
 * as MEASURED here; the seat level keeps it). A window is never better than the
 * reading it came in: a window of a reading graded UNKNOWN is UNKNOWN, with its
 * utilization dropped, however the publisher graded the window itself.
 *
 * Idempotent in time: projecting to t1 and then to t2 equals projecting to t2.
 * A passed reset never raises utilization.
 */
export const projectWindow = (
  window: CapacityWindow,
  observedAt: string,
  asOf: string,
  seatGrade: Exclude<CapacityGrade, "PROJECTED"> = "MEASURED"
): CapacityWindow => {
  const now = asOfMs(asOf);
  if (window.resets_at !== null) {
    const reset = parse(window.resets_at);
    if (reset <= now) {
      if (window.kind === "five_hour") {
        return { ...window, utilization_pct: 0, resets_at: null, severity: null, grade: "PROJECTED" };
      }
      const weeks = Math.floor((now - reset) / WEEK_MS) + 1;
      return {
        ...window,
        utilization_pct: 0,
        resets_at: iso(reset + weeks * WEEK_MS),
        severity: null,
        grade: "PROJECTED"
      };
    }
  }
  // A window already projected past a reset stays what the projection made it:
  // the reading's age says nothing about a window that has reset since.
  if (window.grade === "PROJECTED") return window;
  if (window.utilization_pct === null) return { ...window, grade: "UNKNOWN" };
  const grade = worse(worse(window.grade, seatGrade), classifyStaleness(observedAt, asOf).grade);
  return grade === "UNKNOWN"
    ? { ...window, utilization_pct: null, grade }
    : { ...window, grade };
};

/**
 * Projects a whole seat reading to `asOf`, keeping its shape.
 *
 * The seat-level grade is the worse of the publisher's grade and the age
 * class, and every window not projected past a reset is graded no better than
 * that publisher's grade (so an UNKNOWN reading reports no headroom). A seat that would otherwise be MEASURED is PROJECTED when any window
 * is projected past a reset, or when the publisher itself graded the reading
 * PROJECTED: a projection is for planning only and is never upgraded to a
 * measurement. Age still wins over it (an old projection is STALE or UNKNOWN).
 */
export const projectSeatReading = (seat: SeatCapacity, asOf: string): SeatCapacity => {
  const stated = seat.grade === "PROJECTED" ? "MEASURED" : seat.grade;
  const windows = seat.windows.map((window) => projectWindow(window, seat.observed_at, asOf, stated));
  const aged = worse(stated, classifyStaleness(seat.observed_at, asOf).grade);
  const grade: CapacityGrade =
    aged === "MEASURED" &&
    (seat.grade === "PROJECTED" || windows.some((window) => window.grade === "PROJECTED"))
      ? "PROJECTED"
      : aged;
  return { ...seat, windows, grade };
};

/** Unused capacity that expires at a reset. */
interface Lapse {
  readonly kind: WindowKind;
  readonly model: string | null;
  readonly unused_pct: number;
  readonly lapses_at: string;
}

/** What the lake answers about one seat at one moment. */
export interface SeatProjection {
  readonly as_of: string;
  readonly reading: SeatCapacity;
  readonly age_seconds: number;
  /** The lowest free share across binding seat windows; null if any is UNKNOWN. */
  readonly headroom_pct: number | null;
  readonly lapses: ReadonlyArray<Lapse>;
  readonly plan_lapses_at: string | null;
}

const free = (utilization: number): number => Math.min(100, Math.max(0, 100 - utilization));

/** Binding windows that bind the seat as a whole (never a model-scoped one). */
const seatWindows = (windows: ReadonlyArray<CapacityWindow>) =>
  windows.filter((window) => window.binding && window.kind !== "model_scoped");

/**
 * The lowest free share across the seat's binding windows.
 *
 * Null when the seat has no such window or any of them is UNKNOWN: an unknown
 * is never headroom. A model-scoped window never changes this number.
 */
export const headroomPct = (windows: ReadonlyArray<CapacityWindow>): number | null => {
  const binding = seatWindows(windows);
  if (binding.length === 0) return null;
  let lowest = 100;
  for (const window of binding) {
    if (window.utilization_pct === null) return null;
    lowest = Math.min(lowest, free(window.utilization_pct));
  }
  return lowest;
};

/** Projects a seat and derives its headroom and lapses at `asOf`. */
export const projectSeat = (seat: SeatCapacity, asOf: string): SeatProjection => {
  const reading = projectSeatReading(seat, asOf);
  const lapses = reading.windows
    .flatMap((window): Array<Lapse> =>
      window.resets_at === null || window.utilization_pct === null
        ? []
        : [
            {
              kind: window.kind,
              model: window.model,
              unused_pct: free(window.utilization_pct),
              lapses_at: window.resets_at
            }
          ]
    )
    .sort((left, right) => parse(left.lapses_at) - parse(right.lapses_at));
  return {
    as_of: asOf,
    reading,
    age_seconds: classifyStaleness(seat.observed_at, asOf).age_seconds,
    headroom_pct: headroomPct(reading.windows),
    lapses,
    plan_lapses_at: seat.plan?.expires_at ?? null
  };
};

/**
 * The earliest moment strictly after `asOf` at which any seat's projection or
 * admission may change: a reset, a staleness edge (observed_at + 1200 s,
 * + 7200 s), the end of a clock-skew refusal (observed_at - 120 s), or a plan
 * expiry. `None` when nothing is ahead.
 *
 * Every candidate is an instant at which the change has already happened (the
 * edges are inclusive of their later side), so a reader that re-asks at the
 * returned instant sees the new answer, and nothing changes strictly between
 * `asOf` and it. A candidate may change nothing for a seat whose grade is
 * already worse than the edge (an early wake, never a missed change).
 */
export const nextTransitionAt = (
  seats: ReadonlyArray<SeatCapacity>,
  asOf: string
): Option.Option<string> => {
  const now = asOfMs(asOf);
  let earliest = Number.POSITIVE_INFINITY;
  const consider = (ms: number) => {
    if (Number.isFinite(ms) && ms > now && ms < earliest) earliest = ms;
  };
  for (const seat of seats) {
    const observed = parse(seat.observed_at);
    // Before this instant the reading is dated too far ahead (admission says
    // `clock-skew`); from it on, the skew is within tolerance.
    consider(observed - CLOCK_SKEW_TOLERANCE_S * SECOND_MS);
    consider(observed + MEASURED_MAX_AGE_S * SECOND_MS);
    consider(observed + STALE_MAX_AGE_S * SECOND_MS);
    if (seat.plan !== null) consider(parse(seat.plan.expires_at));
    for (const window of projectSeatReading(seat, asOf).windows) {
      if (window.resets_at !== null) consider(parse(window.resets_at));
    }
  }
  return Number.isFinite(earliest) ? Option.some(iso(earliest)) : Option.none();
};

/** Why a seat may not take a job. */
type RefusalReason =
  | "invalid-as-of"
  | "unknown-seat"
  | "not-dispatchable"
  | "plan-expired"
  | "clock-skew"
  | "stale"
  | "unknown"
  | "estimated"
  | "no-binding-window"
  | "projected"
  | "window-unknown"
  | "severity-critical"
  | "window-exhausted"
  | "slots-unknown"
  | "slots-full";

/** The headroom oracle's coarse signal, as `capacity.ts` spells it. */
type SeatSignal = "GO" | "SLOW" | "STOP";

/** A yes, with how long it holds. */
interface Admitted {
  readonly admit: true;
  readonly seat: string;
  /** The instant after which this answer must be asked again. */
  readonly until: string;
  /** The lowest free share across the windows checked; null for a slot row. */
  readonly headroom_pct: number | null;
  readonly signal: Exclude<SeatSignal, "STOP">;
  readonly checked: ReadonlyArray<{ readonly kind: WindowKind; readonly model: string | null }>;
}

/** A no, with why, and what would change it. */
interface Refused {
  readonly admit: false;
  readonly seat: string;
  readonly reason: RefusalReason;
  readonly detail: string;
  /** The earliest moment asking again could help; null when only a new reading can. */
  readonly retry_at: string | null;
  /** Whether a fresh provider read would help (the demand marker). */
  readonly raise_demand: boolean;
  readonly signal: Exclude<SeatSignal, "GO">;
}

/** The admission answer. */
export type AdmissionDecision = Admitted | Refused;

/** The model families a model-scoped limit is published under. */
const MODEL_FAMILIES: ReadonlySet<string> = new Set(modelFamilyData.families.map((family) => family.toLowerCase()));

/**
 * Every model family a model name mentions.
 *
 * The provider publishes a model-scoped limit under its display name ("Fable",
 * or a shared "Opus and Sonnet") or its id; a job names its model by id
 * ("claude-fable-5-1", "claude-opus-5[1m]") or alias ("fable"). All of them
 * reduce to families, so a spelling difference can never make a limit vanish.
 */
const modelFamilies = (model: string): ReadonlySet<string> =>
  // Splitting on anything that is not a letter or digit also drops a context
  // suffix such as "[1m]": its token, "1m", is no family.
  new Set(
    model
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((token) => MODEL_FAMILIES.has(token))
  );

/** The one family a JOB's model belongs to, or null when it names none or several. */
const modelFamily = (model: string): string | null => {
  const families = [...modelFamilies(model)];
  return families.length === 1 ? (families[0] ?? null) : null;
};

/**
 * Whether a model-scoped window binds a job of model `job`.
 *
 * Verbatim (case-insensitive), or by family: the window binds when the job's
 * one family is ANY of the families the window names, so a limit shared by
 * two families ("Opus and Sonnet") binds both.
 */
const bindsJob = (windowModel: string | null, job: string | null): boolean => {
  if (windowModel === null || job === null) return false;
  if (windowModel.toLowerCase() === job.toLowerCase()) return true;
  const family = modelFamily(job);
  return family !== null && modelFamilies(windowModel).has(family);
};

/** A model-scoped window whose model this reader cannot place in any family. */
const unplaceable = (window: CapacityWindow): boolean =>
  window.kind === "model_scoped" && (window.model === null || modelFamilies(window.model).size === 0);

/**
 * Can `seat` take a job of class `job` at `asOf`, and until when?
 *
 * Fails closed. The windows checked are the seat's binding windows (five-hour
 * and weekly) plus any model-scoped window whose model is the job's, matched
 * by model family (`claude-fable-5-1`, `fable` and `Fable` are one model; a
 * window naming two families, `Opus and Sonnet`, binds both): a seat whose
 * Fable row is at 100 percent refuses Fable work and may still take Opus work.
 * A job model that names no known family refuses unless a window names it
 * verbatim, and a model-scoped window whose name no family covers refuses
 * every model job it does not name verbatim. A third party's seat is never admitted. Every checked window must be MEASURED (a projected reset needs a new
 * reading before it admits), carry a utilization, not be `critical`, and leave
 * more than `min_headroom_pct` free.
 */
export const admitSeat = (
  seatId: string,
  seat: SeatCapacity | undefined,
  job: SeatJob,
  asOf: string
): AdmissionDecision => {
  const refuse = (
    reason: RefusalReason,
    detail: string,
    options: { retry_at?: string | null; raise_demand?: boolean; signal?: "SLOW" | "STOP" } = {}
  ): Refused => ({
    admit: false,
    seat: seatId,
    reason,
    detail,
    retry_at: options.retry_at ?? null,
    raise_demand: options.raise_demand ?? false,
    signal: options.signal ?? "STOP"
  });

  const now = parse(asOf);
  if (!Number.isFinite(now)) return refuse("invalid-as-of", `asOf is not an instant: ${asOf}`);
  if (seat === undefined) return refuse("unknown-seat", "no reading has been received for this seat");
  // Checked here as well as by the publisher: any bearer-holding publisher can
  // write a seat, and a third party's seat is read, never dispatched onto.
  if (seat.owner !== "tom") {
    return refuse("not-dispatchable", "third-party: a third party's seat is read, never dispatched onto");
  }
  if (!seat.dispatchable) {
    return refuse("not-dispatchable", seat.dispatchable_reason ?? "the publisher marked it not dispatchable");
  }
  if (seat.plan !== null && parse(seat.plan.expires_at) <= now) {
    return refuse("plan-expired", `the plan lapsed at ${seat.plan.expires_at}`);
  }
  const staleness = classifyStaleness(seat.observed_at, asOf);
  if (staleness.skewed) {
    return refuse(
      "clock-skew",
      `the reading is dated ${Math.round(staleness.skew_seconds)} s ahead of asOf`,
      { retry_at: iso(parse(seat.observed_at) - CLOCK_SKEW_TOLERANCE_S * SECOND_MS) }
    );
  }
  const projected = projectSeatReading(seat, asOf);
  const age = `the reading is ${Math.round(staleness.age_seconds)} s old`;
  if (projected.grade === "UNKNOWN") {
    return refuse("unknown", staleness.grade === "UNKNOWN" ? age : (seat.stale_reason ?? "the publisher graded it UNKNOWN"), {
      raise_demand: true
    });
  }
  if (projected.grade === "STALE") {
    return refuse("stale", staleness.grade === "STALE" ? age : (seat.stale_reason ?? "the publisher graded it STALE"), {
      raise_demand: true,
      signal: "SLOW"
    });
  }
  if (projected.grade === "ESTIMATED") return refuse("estimated", "an estimate never admits a metered job");
  if (seat.grade === "PROJECTED") {
    return refuse("projected", "the publisher graded the reading PROJECTED: for planning only", {
      raise_demand: true
    });
  }

  const measuredUntil = parse(seat.observed_at) + MEASURED_MAX_AGE_S * SECOND_MS;
  const planUntil = seat.plan === null ? Number.POSITIVE_INFINITY : parse(seat.plan.expires_at);

  if (seat.provider === "halogen") {
    if (seat.slots === null) return refuse("slots-unknown", "a slot row published no slots");
    if (seat.slots.holders >= seat.slots.capacity) {
      return refuse("slots-full", `${seat.slots.holders} of ${seat.slots.capacity} slots held`, {
        raise_demand: true
      });
    }
    return {
      admit: true,
      seat: seatId,
      until: iso(Math.min(measuredUntil, planUntil)),
      headroom_pct: null,
      signal: "GO",
      checked: []
    };
  }

  const checked = projected.windows.filter(
    (window) =>
      (window.binding && window.kind !== "model_scoped") ||
      (window.kind === "model_scoped" && bindsJob(window.model, job.model))
  );
  if (!checked.some((window) => window.kind !== "model_scoped")) {
    return refuse("no-binding-window", "a metered seat published no binding five-hour or weekly window");
  }
  // A job model that reduces to no known family can match no limit by family,
  // so even a reading that lists every model limit cannot say it has none.
  if (
    job.model !== null &&
    modelFamily(job.model) === null &&
    !checked.some((window) => window.kind === "model_scoped")
  ) {
    return refuse(
      "window-unknown",
      `the job's model ${job.model} names no known model family, so its limit cannot be matched`,
      { raise_demand: true }
    );
  }
  // A model-scoped limit under a name no family covers may or may not be the
  // job's model: it cannot be read as "not this model", so it refuses rather
  // than being skipped (a window that names the job's model verbatim is checked
  // like any other).
  if (job.model !== null) {
    const jobModel = job.model;
    const opaque = projected.windows.find(
      (window) => unplaceable(window) && !bindsJob(window.model, jobModel)
    );
    if (opaque !== undefined) {
      return refuse(
        "window-unknown",
        `model_scoped(${opaque.model}) names no known model family, so it cannot be ruled out for ${jobModel}`,
        { raise_demand: true }
      );
    }
  }
  // A model job needs the seat's word on that model's limit. A missing
  // model-scoped window is "no limit" only when the publisher says its windows
  // list every model limit; otherwise the limit was not read, and an unread
  // limit is UNKNOWN, never headroom (a Fable row last seen at 100 percent must
  // not vanish because the usage cache lagged the meter row).
  if (
    job.model !== null &&
    seat.model_windows_complete !== true &&
    !checked.some((window) => window.kind === "model_scoped")
  ) {
    return refuse(
      "window-unknown",
      `model_scoped(${job.model}) is not stated: the reading does not claim to list every model limit`,
      { raise_demand: true }
    );
  }
  const label = (window: CapacityWindow) =>
    window.kind === "model_scoped" ? `model_scoped(${window.model})` : window.kind;

  const projectedWindow = checked.find((window) => window.grade === "PROJECTED");
  if (projectedWindow !== undefined) {
    return refuse("projected", `${label(projectedWindow)} has reset since the reading; a new reading is needed`, {
      raise_demand: true
    });
  }
  const unknown = checked.find(
    (window) => window.utilization_pct === null || window.grade !== "MEASURED"
  );
  if (unknown !== undefined) {
    return refuse("window-unknown", `${label(unknown)} is ${unknown.grade}`, { raise_demand: true });
  }
  // A window refuses when it is critical or leaves too little free. Asking
  // again helps only once EVERY refusing window has reset, so retry_at is the
  // latest of their resets on both refusal paths (null when any has none).
  const exhausted = (window: CapacityWindow) => free(window.utilization_pct ?? 100) <= job.min_headroom_pct;
  const refusing = checked.filter((window) => window.severity === "critical" || exhausted(window));
  // Normalised to ISO milliseconds, like `until`: the lake compares instants
  // at millisecond precision, so this is the instant the reset is seen.
  const retryAt = (): string | null =>
    refusing.some((window) => window.resets_at === null)
      ? null
      : iso(Math.max(...refusing.map((window) => parse(window.resets_at ?? ""))));
  const critical = refusing.find((window) => window.severity === "critical");
  if (critical !== undefined) {
    return refuse("severity-critical", `${label(critical)} is critical at ${critical.utilization_pct} percent`, {
      retry_at: retryAt()
    });
  }
  if (refusing.length > 0) {
    return refuse(
      "window-exhausted",
      refusing.map((window) => `${label(window)} at ${window.utilization_pct} percent`).join(", "),
      { retry_at: retryAt() }
    );
  }

  let until = Math.min(measuredUntil, planUntil);
  let headroom = 100;
  for (const window of checked) {
    if (window.resets_at !== null) until = Math.min(until, parse(window.resets_at));
    headroom = Math.min(headroom, free(window.utilization_pct ?? 100));
  }
  return {
    admit: true,
    seat: seatId,
    until: iso(until),
    headroom_pct: headroom,
    signal: checked.some((window) => window.severity === "warning") ? "SLOW" : "GO",
    checked: checked.map((window) => ({ kind: window.kind, model: window.model }))
  };
};
