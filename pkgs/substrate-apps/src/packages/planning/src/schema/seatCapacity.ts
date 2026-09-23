/**
 * `seat-capacity/2`: what one compute seat can still do, and until when.
 *
 * The capacity reading (`capacity.ts`) carries a coarse GO/SLOW/STOP signal per
 * row and nothing else, so the lake could not answer "how much is left on cc,
 * and when does it come back". This schema is the answer's input: one reading
 * per seat, pushed outbound from the fleet, carrying every usage window the
 * provider publishes with its own reset instant.
 *
 * THREE CLOCKS, KEPT APART. `observed_at` is when the PROVIDER answered, never
 * the instant a feeder restamped a meter row. The restamp is the kernel's
 * business (its 60 s row rule) and the network read is rate limited; the lake
 * works out capacity at any later moment by projection (`capacity/project.ts`),
 * which is pure and takes the moment as an argument.
 *
 * UNKNOWN IS A VALUE. A `null` utilization is UNKNOWN and never counts as
 * headroom; a `null` `resets_at` means the window opens on first use. A
 * provider's `severity` can only make an answer more cautious.
 *
 * Design: `/home/tom/today/evals-2026-09-23/capacity/SCOUT.md` section 2.
 */
import { Schema } from "effect";

/** The wire version this file decodes. */
export const SEAT_CAPACITY_SCHEMA_VERSION = "seat-capacity/2";

/**
 * An RFC 3339 instant with an explicit zone designator.
 *
 * A zone is required because an instant without one is a local time whose
 * meaning depends on the reader's clock, and this schema crosses from the fleet
 * to a Worker. Instants are compared with `Date.parse`, never as text: the same
 * moment spelled with two offsets orders wrongly as a string.
 */
export const Instant = Schema.String.pipe(
  Schema.check(
    Schema.makeFilter(
      (value: string) =>
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.test(value) &&
        Number.isFinite(Date.parse(value)),
      { expected: "an RFC 3339 instant with a zone designator" }
    )
  )
);
/** An RFC 3339 instant with an explicit zone designator. */
export type Instant = typeof Instant.Type;

/** A seat id: the same ids as `meters/<seat>.json`. */
const SeatId = Schema.String.pipe(
  Schema.check(Schema.isPattern(/^[a-z0-9][a-z0-9-]{0,62}$/))
);
/** A seat id: the same ids as `meters/<seat>.json`. */
type SeatId = typeof SeatId.Type;

/**
 * How much a number can be trusted, at the moment it is read.
 *
 * MEASURED: the provider answered within 1200 s. STALE: 1200 to 7200 s, used
 * for planning and flagged. PROJECTED: a reset has passed since the provider
 * answered, so the number is the projection's, for planning only. ESTIMATED:
 * derived from a local artefact rather than the provider (Codex rollouts).
 * UNKNOWN: no number.
 */
export const CapacityGrade = Schema.Literals([
  "MEASURED",
  "STALE",
  "PROJECTED",
  "ESTIMATED",
  "UNKNOWN"
]);
/** How much a number can be trusted, at the moment it is read. */
export type CapacityGrade = typeof CapacityGrade.Type;

/** The window kinds the providers publish. */
export const WindowKind = Schema.Literals(["five_hour", "seven_day", "model_scoped"]);
/** The window kinds the providers publish. */
export type WindowKind = typeof WindowKind.Type;

/** The window lengths, in minutes, that go with each kind. */
const WINDOW_MINUTES: Readonly<Record<WindowKind, 300 | 10080>> = {
  five_hour: 300,
  seven_day: 10080,
  model_scoped: 10080
};

/** A percentage the provider reports: finite and never negative. */
const Percent = Schema.Finite.pipe(Schema.check(Schema.isGreaterThanOrEqualTo(0)));

const CapacityWindowFields = Schema.Struct({
  /** Which window. */
  kind: WindowKind,
  /** The model a `model_scoped` window binds (for example `Fable`); null otherwise. */
  model: Schema.NullOr(Schema.String),
  /**
   * Whether exhausting this window stops the seat.
   *
   * A `model_scoped` window binds only jobs for its model, never the seat as a
   * whole: a seat whose Fable row is at 100 percent may still take Opus work.
   */
  binding: Schema.Boolean,
  /** Window length: 300 for five_hour, 10080 for the weekly kinds. */
  minutes: Schema.Literals([300, 10080]),
  /** Percent used; null is UNKNOWN and never headroom. */
  utilization_pct: Schema.NullOr(Percent),
  /** When the window resets; null means it opens on first use. */
  resets_at: Schema.NullOr(Instant),
  /** The provider's own label (normal, warning, critical); only ever more cautious. */
  severity: Schema.NullOr(Schema.String),
  /** The grade of this window's numbers. */
  grade: CapacityGrade
});

/** One usage window on one seat. */
export const CapacityWindow = CapacityWindowFields.pipe(
  Schema.check(
    Schema.makeFilter(
      (window: typeof CapacityWindowFields.Type) =>
        window.minutes === WINDOW_MINUTES[window.kind] &&
        (window.kind === "model_scoped") === (window.model !== null),
      {
        expected:
          "minutes matching the kind (300 five_hour, 10080 weekly) and a model exactly on model_scoped"
      }
    )
  )
);
/** One usage window on one seat. */
export type CapacityWindow = typeof CapacityWindow.Type;

/**
 * The provider a seat belongs to, as data: a lower-case slug such as the
 * pusher's config names it. The floor never enumerates product names (the house
 * fence, tools/check-fences.mjs F1); only `halogen` is read here, because a
 * slot-counted seat projects differently from a windowed one.
 */
const SeatProvider = Schema.String.pipe(Schema.check(Schema.isPattern(/^[a-z][a-z0-9-]{0,31}$/)));
/** The providers a seat can belong to. */
type SeatProvider = typeof SeatProvider.Type;

/** One seat's capacity, as the fleet observed it. */
export const SeatCapacity = Schema.Struct({
  /** The seat id, as in `meters/<seat>.json`. */
  seat: SeatId,
  /** The provider behind the seat. */
  provider: SeatProvider,
  /** Whose login it is. A third party's seat is read, never dispatched onto. */
  owner: Schema.Literals(["tom", "third-party"]),
  /** Whether work may be dispatched onto this seat at all. */
  dispatchable: Schema.Boolean,
  /** Why not, when it may not (evicted, third-party, auth-failed). */
  dispatchable_reason: Schema.NullOr(Schema.String),
  /** A plan with an end date (the Qwen cloud plan); null when none is known. */
  plan: Schema.NullOr(Schema.Struct({ expires_at: Instant })),
  /** Slot capacity, for a Halogen row only. */
  slots: Schema.NullOr(
    Schema.Struct({
      capacity: Schema.Int.pipe(Schema.check(Schema.isGreaterThanOrEqualTo(0))),
      holders: Schema.Int.pipe(Schema.check(Schema.isGreaterThanOrEqualTo(0)))
    })
  ),
  /** Every usage window the provider published. */
  windows: Schema.Array(CapacityWindow),
  /** When the provider answered; not the instant a meter row was restamped. */
  observed_at: Instant,
  /** Where the reading came from. */
  source: Schema.Struct({ kind: Schema.String, detail: Schema.NullOr(Schema.String) }),
  /** The seat-level grade the publisher assigned. */
  grade: CapacityGrade,
  /** Why the publisher's last read failed, when it did. */
  stale_reason: Schema.NullOr(Schema.String),
  /**
   * Whether `windows` states EVERY model-scoped window the provider has.
   *
   * `true`: a model with no `model_scoped` window here has no model limit on
   * this seat. Absent or `false`: the publisher could not state them (the
   * Claude usage cache was missing, unreadable, or behind the meter row), so a
   * job for a model that has no window here is refused `window-unknown`: an
   * unread model limit is UNKNOWN, never headroom.
   */
  model_windows_complete: Schema.optionalKey(Schema.Boolean)
});
/** One seat's capacity, as the fleet observed it. */
export type SeatCapacity = typeof SeatCapacity.Type;

const SeatCapacitySnapshotFields = Schema.Struct({
  /** Always `seat-capacity/2`. */
  schema_version: Schema.Literal(SEAT_CAPACITY_SCHEMA_VERSION),
  /** The host that published it (`coordinator`). */
  host: Schema.String,
  /** When the snapshot was written; orders two snapshots of one reading. */
  published_at: Instant,
  /** One entry per seat. */
  seats: Schema.Array(SeatCapacity)
});

/** What the fleet pushes: every seat it knows, at one instant. */
export const SeatCapacitySnapshot = SeatCapacitySnapshotFields.pipe(
  Schema.check(
    Schema.makeFilter(
      (snapshot: typeof SeatCapacitySnapshotFields.Type) =>
        new Set(snapshot.seats.map((seat) => seat.seat)).size === snapshot.seats.length,
      { expected: "each seat at most once per snapshot" }
    )
  )
);
/** What the fleet pushes: every seat it knows, at one instant. */
export type SeatCapacitySnapshot = typeof SeatCapacitySnapshot.Type;

/** Decodes an untrusted snapshot arriving over the uplink or the pusher. */
export const parseSeatCapacitySnapshot = Schema.decodeUnknownEffect(SeatCapacitySnapshot);

/**
 * The same decoders, synchronous (throw on failure), for the host-side gate
 * and the tally-meter adapter. One schema for the whole workspace: the root
 * package's second copy drifted (its SeatProvider was a closed list, so one
 * unfamiliar seat failed every seat closed; successor review 2026-09-23).
 */
export const decodeSeatCapacitySnapshot = Schema.decodeUnknownSync(SeatCapacitySnapshot);
export const decodeSeatCapacity = Schema.decodeUnknownSync(SeatCapacity);

/**
 * The class of job an admission question is about.
 *
 * `model` selects the model-scoped windows that bind this job (compared
 * case-insensitively; null binds none). `min_headroom_pct` is how much of every
 * binding window must remain free.
 */
export const SeatJob = Schema.Struct({
  model: Schema.NullOr(Schema.String),
  min_headroom_pct: Percent
});
/** The class of job an admission question is about. */
export type SeatJob = typeof SeatJob.Type;
