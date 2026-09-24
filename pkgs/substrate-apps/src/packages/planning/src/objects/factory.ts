/**
 * The Factory object: the release station, and the only object with a backlog.
 *
 * Cardinality one. It owns the four-state backlog, work-in-process counts, the
 * latest capacity readings and mirrored high-water marks. Every input that can
 * change admissibility re-runs the pure evaluator. The object never constructs
 * a verdict and never turns a proposal into authority: only the kernel's answer
 * moves `released` to `inflight`.
 *
 * The implementation is host-neutral. Durable Object SQLite and its alarm
 * binding belong to the Worker composition root; this service depends only on
 * `PlanningStore`, whose in-memory Layer is used by the tests and tools.
 */
import { Context, Effect, Layer, Option, Ref, Schema } from "effect";
import {
  evaluateRelease,
  evaluateReleaseAcross,
  type MultiReleaseDecision,
  type ReleaseDecision,
  type ReleaseState
} from "../release/evaluator.ts";
import type { Admit, AdmitOutcomeReport, Deferral } from "../schema/admit.ts";
import {
  BacklogItem as BacklogItemSchema,
  WipCount as WipCountSchema,
  type BacklogItem,
  type WipCount
} from "../schema/backlog.ts";
import {
  CapacityReading as CapacityReadingSchema,
  type CapacityReading
} from "../schema/capacity.ts";
import { FactoryError } from "../schema/errors.ts";
import {
  DedupKey,
  type ExecutorId,
  type PlanId,
  type Seq,
  type TaskId
} from "../schema/ids.ts";
import {
  PlanRow as PlanRowSchema,
  type PlanArm,
  type PlanRow
} from "../schema/plan.ts";
import {
  ContinuityGap as ContinuityGapSchema,
  ControlPlaneFact as ControlPlaneFactSchema,
  Verdict as VerdictSchema,
  type ContinuityGap,
  type ControlPlaneFact,
  type Verdict,
  type VerdictOutcome
} from "../schema/records.ts";
import type { Heartbeat } from "../schema/uplink.ts";
import { fillerTaskIds, passedOverBy } from "../heuristics/fillerLane.ts";
import {
  makeCapacityLedger,
  type CapacityView,
  type IngestReport,
  type StoredSeat
} from "../capacity/ledger.ts";
import { nextTransitionAt, type AdmissionDecision } from "../capacity/project.ts";
import type {
  SeatCapacity,
  SeatCapacitySnapshot,
  SeatJob
} from "../schema/seatCapacity.ts";
import { advanceMirror, emptyMirror, type MirrorState } from "./mirror.ts";
import { ArtifactHasher, type ArtifactBytes } from "./hasher.ts";
import {
  LogName,
  PlanningStore,
  planningStoreInMemoryLayer,
  StorageKey,
  type JsonValue
} from "./storage.ts";

/** The bytes handed to the object plus the acceptor's expansion of them. */
export interface ArmedArtifact {
  readonly planId: PlanId;
  readonly bytes: ArtifactBytes;
  readonly items: ReadonlyArray<BacklogItem>;
}

/** One recorded step of the arming workflow, replayable after a restart. */
const ArmingStep = Schema.Union([
  Schema.Struct({ _tag: Schema.tag("HashVerified"), planId: Schema.String }),
  Schema.Struct({ _tag: Schema.tag("PlanRowWritten"), planId: Schema.String }),
  Schema.Struct({
    _tag: Schema.tag("ItemsExpanded"),
    planId: Schema.String,
    count: Schema.Int
  }),
  Schema.Struct({ _tag: Schema.tag("EvaluatorWoken"), planId: Schema.String })
]);
type ArmingStep = typeof ArmingStep.Type;

/** One recorded step of the supersession workflow. */
const SupersessionStep = Schema.Union([
  Schema.Struct({ _tag: Schema.tag("PlanRetired"), planId: Schema.String }),
  Schema.Struct({
    _tag: Schema.tag("UnclaimedDropped"),
    planId: Schema.String,
    count: Schema.Int
  }),
  Schema.Struct({
    _tag: Schema.tag("CancelsAuthorised"),
    planId: Schema.String,
    tasks: Schema.Array(Schema.String)
  })
]);
type SupersessionStep = typeof SupersessionStep.Type;

const encodeArmingStep = Schema.encodeEffect(ArmingStep);
const encodeSupersessionStep = Schema.encodeEffect(SupersessionStep);

/** Logs and snapshot key owned by this object. */
const ARMING_LOG = LogName("factory/arming");
const SUPERSESSION_LOG = LogName("factory/supersession");
const FACTORY_EVENT_LOG = LogName("factory/events");
export const FACTORY_STATE_KEY = StorageKey("factory/state");

/** A proposal as the pull endpoint hands it to one executor. */
type FactoryProposal = Admit & {
  readonly row: string;
  readonly argv_ref: string;
  readonly mutation_hint?: string;
  readonly next_wake_at: string | null;
};

/** Strict receipt cells needed for an exact chain match after decoding. */
export interface ReceiptEvidence {
  readonly id: string;
  readonly oracle_rc: number;
  readonly mutation_rc?: number;
  readonly oracle_output_sha256: string;
  readonly verdict_hash: string;
}

interface OutcomeObservation {
  readonly idempotent: boolean;
  readonly decision: MultiReleaseDecision;
}

interface VerdictObservation {
  readonly idempotent: boolean;
  readonly continuous: boolean;
  readonly decision: MultiReleaseDecision;
}

export interface ReceiptObservation {
  readonly idempotent: boolean;
}

interface ChainHighWater {
  readonly last_seq: number;
  readonly last_hash: string;
}

interface HeartbeatState {
  readonly executor: string;
  readonly task_id: string | null;
  readonly last_seq: number;
  readonly status: "live";
  readonly observed_at?: string;
}

const ReceiptEvidenceState = Schema.Struct({
  id: Schema.String,
  oracle_rc: Schema.Int,
  mutation_rc: Schema.optionalKey(Schema.Int),
  oracle_output_sha256: Schema.String,
  verdict_hash: Schema.String
});

const HeartbeatStateRecord = Schema.Struct({
  executor: Schema.String,
  task_id: Schema.NullOr(Schema.String),
  last_seq: Schema.Int,
  status: Schema.Literal("live"),
  observed_at: Schema.optionalKey(Schema.String)
});

/**
 * The mutable half of the Factory object, encoded under `FACTORY_STATE_KEY`.
 *
 * Policy and catalog inputs remain constructor data; the snapshot owns every
 * value changed by an object request. Arrays carry maps and sets across the JSON
 * boundary without weakening their element schemas.
 */
const FactoryStoredState = Schema.Struct({
  version: Schema.Literal(1),
  release: Schema.Struct({
    backlog: Schema.Array(BacklogItemSchema),
    plans: Schema.Array(PlanRowSchema),
    wip: Schema.Array(WipCountSchema)
  }),
  latestReadings: Schema.Array(CapacityReadingSchema),
  mirrored: Schema.Array(VerdictSchema),
  rejectedGaps: Schema.Array(ContinuityGapSchema),
  acceptedReceipts: Schema.Array(ReceiptEvidenceState),
  outcomeKeys: Schema.Array(Schema.String),
  alarmAt: Schema.OptionFromNullOr(Schema.String),
  alarmFiredAt: Schema.OptionFromNullOr(Schema.String),
  deferralsByRow: Schema.Array(
    Schema.Struct({ row: Schema.String, count: Schema.Int })
  ),
  heartbeats: Schema.Array(
    Schema.Struct({ lane: Schema.String, heartbeat: HeartbeatStateRecord })
  ),
  facts: Schema.Array(ControlPlaneFactSchema)
});
type FactoryStoredState = typeof FactoryStoredState.Type;

const parseFactoryStoredState = Schema.decodeUnknownEffect(FactoryStoredState);
const encodeFactoryStoredState = Schema.encodeEffect(FactoryStoredState);

/** JSON-facing state returned by `GET /state`. */
interface FactoryStateView {
  readonly backlog: ReadonlyArray<Record<string, unknown>>;
  readonly wip: {
    readonly level: Readonly<Record<string, number>>;
    readonly namespace: Readonly<Record<string, number>>;
    readonly family: Readonly<Record<string, number>>;
  };
  readonly chains: Readonly<Record<string, ChainHighWater>>;
  readonly latest_readings: Readonly<Record<string, Record<string, unknown>>>;
  readonly alarm_at: string | null;
  readonly alarm_fired_at: string | null;
  /** The latest reading held per seat (`seat-capacity/2`), unprojected. */
  readonly seat_readings: ReadonlyArray<StoredSeat>;
  /**
   * Null when the held seats were read; otherwise why they could not be
   * (`seat_readings` is then empty). The rest of the view is unaffected.
   */
  readonly seat_readings_error: string | null;
  readonly deferrals_by_row: Readonly<Record<string, number>>;
  readonly heartbeats_by_lane: Readonly<Record<string, HeartbeatState>>;
  readonly continuity_gaps: ReadonlyArray<ContinuityGap>;
  readonly mirrored_verdicts: number;
  readonly receipts: ReadonlyArray<ReceiptEvidence>;
  readonly facts: ReadonlyArray<ControlPlaneFact>;
  readonly price_hash: string;
}

/** The release station's Effect capability. */
export interface IFactory {
  readonly armPlan: (
    request: PlanArm,
    artifact: ArmedArtifact
  ) => Effect.Effect<PlanRow, FactoryError, ArtifactHasher>;
  readonly supersede: (
    planId: PlanId
  ) => Effect.Effect<ReadonlyArray<TaskId>, FactoryError>;
  readonly evaluate: (
    reading: CapacityReading
  ) => Effect.Effect<ReleaseDecision, FactoryError>;
  readonly evaluateAcross: (
    readings: ReadonlyArray<CapacityReading>
  ) => Effect.Effect<MultiReleaseDecision, FactoryError>;
  /**
   * Folds a capacity reading in. `asOf` is the host's clock; when given, the
   * alarm is only ever set strictly after it. Seats riding on the reading need
   * it: without `asOf` they are refused `NoClock` (a publisher's own
   * `published_at` is never the receiving clock).
   */
  readonly observeCapacity: (
    reading: CapacityReading,
    asOf?: string
  ) => Effect.Effect<boolean, FactoryError>;
  /** Folds a pushed seat snapshot into the capacity ledger (monotonic, idempotent). */
  readonly observeSeats: (
    snapshot: SeatCapacitySnapshot,
    receivedAt: string
  ) => Effect.Effect<IngestReport, FactoryError>;
  /** Every seat projected to `asOf`. */
  readonly capacityAt: (asOf: string) => Effect.Effect<CapacityView, FactoryError>;
  /** Can `seat` take a job of class `job` at `asOf`, and until when. */
  readonly admitSeat: (
    seat: string,
    job: SeatJob,
    asOf: string
  ) => Effect.Effect<AdmissionDecision, FactoryError>;
  /**
   * Recomputes `alarm_at` as the earliest transition strictly after `asOf`, so
   * the host never re-arms an instant that has already passed.
   */
  readonly rearm: (asOf: string) => Effect.Effect<Option.Option<string>, FactoryError>;
  readonly handOut: (
    executor: ExecutorId
  ) => Effect.Effect<ReadonlyArray<FactoryProposal>, FactoryError>;
  readonly observeOutcome: (
    report: AdmitOutcomeReport
  ) => Effect.Effect<OutcomeObservation, FactoryError>;
  readonly recordDeferrals: (
    deferrals: ReadonlyArray<Deferral>
  ) => Effect.Effect<void, FactoryError>;
  readonly observeVerdict: (
    verdict: Verdict
  ) => Effect.Effect<VerdictObservation, FactoryError>;
  readonly observeReceipt: (
    receipt: ReceiptEvidence
  ) => Effect.Effect<ReceiptObservation, FactoryError>;
  readonly observeHeartbeat: (
    heartbeat: Heartbeat,
    lane?: string,
    observedAt?: string
  ) => Effect.Effect<void, FactoryError>;
  readonly alarm: (firedAt: string) => Effect.Effect<MultiReleaseDecision, FactoryError>;
  readonly stateView: Effect.Effect<FactoryStateView, FactoryError>;
  readonly releaseState: Effect.Effect<ReleaseState, FactoryError>;
  readonly restore: (state: ReleaseState) => Effect.Effect<void, FactoryError>;
}

/** Provides the release station. */
export class Factory extends Context.Service<Factory, IFactory>()("@substrate/planning/Factory") {}

const optionJson = <A>(value: Option.Option<A>): A | null =>
  Option.match(value, { onNone: () => null, onSome: (entry) => entry });

const parseDedupKey = Schema.decodeUnknownSync(DedupKey);

/**
 * Identifies one run of one item under the exact bytes Tom armed.
 *
 * `planHash` is the identity of the armed script and arguments (including the
 * selected arm), while `attempt` distinguishes a retry of that same item.  A
 * NotYet keeps its key because no run happened; only a witnessed failed run
 * advances this identity.
 */
const dedupKeyForAttempt = (item: BacklogItem, attempt: number) =>
  parseDedupKey(
    `arm=${item.planHash};task=${encodeURIComponent(item.taskId)};attempt=${attempt}`
  );

/**
 * Encodes the report fields that distinguish one observed kernel answer.
 *
 * A fixed JSON tuple is injective over these string/null cells. In particular,
 * embedded NUL characters cannot move a boundary as they can in a delimiter-
 * joined key.
 */
const outcomeIdentity = (report: AdmitOutcomeReport): string =>
  JSON.stringify([
    report.taskId,
    report.dedupKey,
    report.outcome,
    report.lease_id ?? null,
    report.row
  ]);

/**
 * The object's next wake: the earliest row `next_window_at` or seat transition.
 *
 * Instants are compared with `Date.parse`, never as text, and with `asOf` given
 * only instants strictly after it count, so a reset that has already passed can
 * never be handed back to the runtime as an alarm. Without `asOf` (a host that
 * passes no clock) rows are taken as they come and seat transitions are
 * measured from the newest seat observation. A row keeps its own spelling.
 */
const minimumNextWindow = (
  readings: ReadonlyMap<ExecutorId, CapacityReading>,
  seats: ReadonlyArray<SeatCapacity>,
  asOf: Option.Option<string>
): Option.Option<string> => {
  const floor = Option.match(asOf, {
    onNone: () => Number.NEGATIVE_INFINITY,
    onSome: (instant) => Date.parse(instant)
  });
  let best: { readonly ms: number; readonly spelling: string } | undefined;
  const consider = (spelling: string) => {
    const ms = Date.parse(spelling);
    if (!Number.isFinite(ms) || ms <= floor) return;
    if (best === undefined || ms < best.ms) best = { ms, spelling };
  };
  for (const reading of readings.values()) {
    for (const row of reading.rows) {
      if (row.next_window_at !== undefined) consider(row.next_window_at);
    }
  }
  const seatAsOf = Option.isSome(asOf)
    ? Option.some(asOf.value)
    : seats.reduce<Option.Option<string>>(
        (latest, seat) =>
          Option.isNone(latest) || Date.parse(seat.observed_at) > Date.parse(latest.value)
            ? Option.some(seat.observed_at)
            : latest,
        Option.none()
      );
  if (Option.isSome(seatAsOf)) {
    const transition = nextTransitionAt(seats, seatAsOf.value);
    if (Option.isSome(transition)) consider(transition.value);
  }
  return best === undefined ? Option.none() : Option.some((best as { spelling: string }).spelling);
};

const changeWip = (
  current: ReadonlyArray<WipCount>,
  item: BacklogItem,
  delta: 1 | -1
): ReadonlyArray<WipCount> => {
  const at = current.findIndex(
    (entry) =>
      entry.level === item.level &&
      entry.namespace === item.namespace &&
      entry.family === item.family
  );
  if (at < 0) {
    return delta < 0
      ? current
      : [
          ...current,
          {
            level: item.level,
            namespace: item.namespace,
            family: item.family,
            count: 1
          }
        ];
  }
  const previous = current[at];
  if (previous === undefined) return current;
  const count = Math.max(0, previous.count + delta);
  if (count === 0) return current.filter((_, index) => index !== at);
  return current.map((entry, index) => (index === at ? { ...entry, count } : entry));
};

const orderedReadings = (
  readings: ReadonlyMap<ExecutorId, CapacityReading>
): ReadonlyArray<CapacityReading> =>
  [...readings.values()].sort((left, right) => left.executor.localeCompare(right.executor));

/** Constructs the release station while preserving its storage requirement. */
/**
 * Whether two digest cells name the same digest.
 *
 * A digest is its 64 hex characters; `sha256:` is a spelling of it, and §2.3's
 * `Sha256Ref` accepts a cell with the prefix and a cell without it as equally
 * valid (`packages/schema/src/Common.ts`). The kernel writes the cell without
 * the prefix and refuses one with it
 * (`tally_kernel::verdict::digest_cell`), while an evaluator that writes a
 * `Sha256Ref` writes one with it — so a receipt and the very verdict it was
 * derived from can carry the same digest in two spellings, and a comparison on
 * the characters alone would refuse it. MEASURED 2026-09-07 by E2E-1: two
 * verdicts on the chain, two complete receipts, and zero receipts accepted.
 *
 * NOTHING IS RECOMPUTED HERE. `POST /receipts` is still an exact match on the
 * evidence and this object still hashes nothing: what is compared is the same
 * 64 characters, read past a prefix that §2.3 says carries no information.
 */
const sameDigest = (left: string | undefined, right: string | undefined): boolean => {
  if (left === undefined || right === undefined) return left === right;
  const bare = (value: string) => (value.startsWith("sha256:") ? value.slice("sha256:".length) : value);
  return bare(left) === bare(right);
};

export const makeFactory = (initial: ReleaseState) =>
  Effect.gen(function* () {
    const store = yield* PlanningStore;
    const ledger = yield* makeCapacityLedger;

    const factoryError = (
      reason: FactoryError["reason"],
      operation: string,
      subject: string
    ) => new FactoryError({ reason, operation, subject });
    const stored = yield* store.get(FACTORY_STATE_KEY).pipe(
      Effect.mapError(() =>
        factoryError("PersistenceFailed", "Factory.make", FACTORY_STATE_KEY)
      )
    );
    const storedSnapshot: FactoryStoredState | undefined = Option.isNone(stored)
      ? undefined
      : yield* parseFactoryStoredState(stored.value).pipe(
          Effect.mapError(() =>
            factoryError("StoredStateInvalid", "Factory.make", FACTORY_STATE_KEY)
          )
        );
    const loadedState: ReleaseState =
      storedSnapshot === undefined
        ? initial
        : {
            ...initial,
            backlog: storedSnapshot.release.backlog,
            plans: storedSnapshot.release.plans,
            wip: storedSnapshot.release.wip
          };
    const restoredReadings = new Map(
      (storedSnapshot?.latestReadings ?? []).map(
        (reading) => [reading.executor, reading] as const
      )
    ) as ReadonlyMap<ExecutorId, CapacityReading>;
    const restoredVerdicts = storedSnapshot?.mirrored ?? [];
    let restoredMirror: MirrorState = emptyMirror;
    for (const verdict of restoredVerdicts) {
      const previous = restoredMirror.get(verdict.executor);
      const advanced = advanceMirror(restoredMirror, verdict);
      if ((previous === undefined && verdict.seq > 1) || !advanced.continuous) {
        return yield* Effect.fail(
          factoryError("StoredStateInvalid", "Factory.make", FACTORY_STATE_KEY)
        );
      }
      restoredMirror = advanced.mirror;
    }

    const state = yield* Ref.make(loadedState);
    const latestReadings = yield* Ref.make(restoredReadings);
    const mirror = yield* Ref.make<MirrorState>(restoredMirror);
    const mirrored = yield* Ref.make<ReadonlyArray<Verdict>>(restoredVerdicts);
    const rejectedGaps = yield* Ref.make<ReadonlyArray<ContinuityGap>>(
      storedSnapshot?.rejectedGaps ?? []
    );
    const acceptedReceipts = yield* Ref.make<ReadonlyArray<ReceiptEvidence>>(
      storedSnapshot?.acceptedReceipts ?? []
    );
    const outcomeKeys = yield* Ref.make<ReadonlySet<string>>(
      new Set(storedSnapshot?.outcomeKeys ?? [])
    );
    const alarmAt = yield* Ref.make<Option.Option<string>>(
      storedSnapshot?.alarmAt ?? Option.none()
    );
    const alarmFiredAt = yield* Ref.make<Option.Option<string>>(
      storedSnapshot?.alarmFiredAt ?? Option.none()
    );
    const deferralsByRow = yield* Ref.make<ReadonlyMap<string, number>>(
      new Map(
        (storedSnapshot?.deferralsByRow ?? []).map(({ row, count }) => [row, count])
      )
    );
    const heartbeats = yield* Ref.make<ReadonlyMap<string, HeartbeatState>>(
      new Map(
        (storedSnapshot?.heartbeats ?? []).map(({ lane, heartbeat }) => [lane, heartbeat])
      )
    );
    const facts = yield* Ref.make<ReadonlyArray<ControlPlaneFact>>(
      storedSnapshot?.facts ?? []
    );
    const lastDecision = yield* Ref.make<MultiReleaseDecision>(
      evaluateReleaseAcross(loadedState, orderedReadings(restoredReadings))
    );

    const fail = (
      reason: FactoryError["reason"],
      operation: string,
      subject: string
    ): Effect.Effect<never, FactoryError> =>
      Effect.fail(factoryError(reason, operation, subject));

    const persist = Effect.fn("Factory.persist")(function* (
      operation: string,
      subject: string
    ) {
      const current = yield* Ref.get(state);
      const readings = yield* Ref.get(latestReadings);
      const snapshot = {
        version: 1 as const,
        release: {
          backlog: current.backlog,
          plans: current.plans,
          wip: current.wip
        },
        latestReadings: orderedReadings(readings),
        mirrored: yield* Ref.get(mirrored),
        rejectedGaps: yield* Ref.get(rejectedGaps),
        acceptedReceipts: yield* Ref.get(acceptedReceipts),
        outcomeKeys: [...(yield* Ref.get(outcomeKeys))].sort(),
        alarmAt: yield* Ref.get(alarmAt),
        alarmFiredAt: yield* Ref.get(alarmFiredAt),
        deferralsByRow: [...(yield* Ref.get(deferralsByRow))]
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([row, count]) => ({ row, count })),
        heartbeats: [...(yield* Ref.get(heartbeats))]
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([lane, heartbeat]) => ({ lane, heartbeat })),
        facts: yield* Ref.get(facts)
      } satisfies FactoryStoredState;
      const encoded = yield* encodeFactoryStoredState(snapshot).pipe(
        Effect.mapError(() => factoryError("StoredStateInvalid", operation, subject))
      );
      yield* store.put(FACTORY_STATE_KEY, encoded).pipe(
        Effect.mapError(() => factoryError("PersistenceFailed", operation, subject))
      );
    });

    if (storedSnapshot === undefined) {
      yield* persist("Factory.make", FACTORY_STATE_KEY);
    }

    const appendEvent = (
      operation: string,
      subject: string,
      value: Record<string, JsonValue>
    ): Effect.Effect<void, FactoryError> =>
      store
        .append(FACTORY_EVENT_LOG, { operation, subject, ...value } as JsonValue)
        .pipe(
          Effect.asVoid,
          Effect.catchTag("PlanningStoreError", () =>
            fail("PersistenceFailed", operation, subject)
          )
        );

    const appendFact = (
      kind: ControlPlaneFact["kind"],
      subject: string,
      detail: string
    ) =>
      Ref.update(facts, (current) => [
        ...current,
        {
          _tag: "ControlPlaneFact" as const,
          kind,
          subject,
          seq: current.length as Seq,
          detail
        }
      ]);

    const recordArming = (step: ArmingStep) =>
      encodeArmingStep(step).pipe(
        Effect.flatMap((encoded) => store.append(ARMING_LOG, encoded)),
        Effect.asVoid,
        Effect.catchTag(["SchemaError", "PlanningStoreError"], () =>
          fail("PersistenceFailed", "Factory.armPlan", step.planId)
        )
      );

    const recordSupersession = (step: SupersessionStep) =>
      encodeSupersessionStep(step).pipe(
        Effect.flatMap((encoded) => store.append(SUPERSESSION_LOG, encoded)),
        Effect.asVoid,
        Effect.catchTag(["SchemaError", "PlanningStoreError"], () =>
          fail("PersistenceFailed", "Factory.supersede", step.planId)
        )
      );

    const wake = Effect.fn("Factory.wake")(function* () {
      const current = yield* Ref.get(state);
      const readings = yield* Ref.get(latestReadings);
      const decision = evaluateReleaseAcross(current, orderedReadings(readings));
      yield* Ref.set(lastDecision, decision);
      return decision;
    });

    /**
     * The held seats, or none when they cannot be read.
     *
     * Contained on purpose: the alarm and the state view serve every route, and
     * a seat ledger that no longer decodes (a schema bump) must not turn a
     * kernel reading, a verdict or `GET /state` into an error. With no seats
     * the alarm falls back to the rows' own windows, and admission, which reads
     * the ledger itself, still refuses: a storage failure only ever refuses work.
     */
    const heldSeatsOrNone = ledger.latest.pipe(
      Effect.map((held) => ({ held, error: null as string | null })),
      Effect.orElseSucceed(() => ({
        held: [] as ReadonlyArray<StoredSeat>,
        error: "PersistenceFailed: capacity/seats could not be read" as string | null
      }))
    );

    /** Recomputes `alarm_at`; true when it moved. */
    const recomputeAlarm = Effect.fn("Factory.recomputeAlarm")(function* (
      asOf: Option.Option<string>
    ) {
      const seats = (yield* heldSeatsOrNone).held.map((entry) => entry.seat);
      const next = minimumNextWindow(yield* Ref.get(latestReadings), seats, asOf);
      const previous = yield* Ref.get(alarmAt);
      yield* Ref.set(alarmAt, next);
      return optionJson(previous) !== optionJson(next);
    });

    const ingestSeats = Effect.fn("Factory.ingestSeats")(function* (
      snapshot: SeatCapacitySnapshot,
      receivedAt: string
    ) {
      return yield* ledger.ingest(snapshot, receivedAt).pipe(
        Effect.mapError(() =>
          factoryError("PersistenceFailed", "Factory.observeSeats", "capacity/seats")
        )
      );
    });

    const countRowDeferral = (row: string) =>
      Ref.update(deferralsByRow, (current) => {
        const next = new Map(current);
        next.set(row, (next.get(row) ?? 0) + 1);
        return next;
      });

    const applyDeferrals = Effect.fn("Factory.applyDeferrals")(function* (
      deferrals: ReadonlyArray<Deferral>
    ) {
      if (deferrals.length === 0) return;
      const passed = new Set<TaskId>(deferrals.map((entry) => entry.taskId));
      yield* Ref.update(state, (current) => ({
        ...current,
        backlog: current.backlog.map((item) =>
          passed.has(item.taskId) ? { ...item, deferrals: item.deferrals + 1 } : item
        )
      }));
      for (const deferral of deferrals) {
        if (deferral.rule === "capacityRow") yield* countRowDeferral(deferral.detail);
      }
      yield* appendEvent("Factory.recordDeferrals", "release-pass", {
        count: deferrals.length
      });
    });

    const proposalFor = (
      admit: Admit,
      item: BacklogItem,
      nextWake: string | null
    ): FactoryProposal => {
      // `level_rank` — the door's number for the lake's level NAME.
      //
      // The two documents rank in opposite directions and neither is wrong: the
      // levels document is ordered strongest-first (`ordinal: 0` is the
      // strongest), and the kernel compares levels as ranks where higher
      // outranks lower and "a grant with no admit before it is level 0, which
      // outranks nobody" (`docs/socket.md` §2). So the rank published here is
      // the ordinal turned around, which puts the filler — the lowest level of
      // the document (§4.4) — at 0, outranking nobody, which is exactly what the
      // filler lane is.
      //
      // It is published rather than derived on the box because the box has no
      // levels document: the uplink would have to invent a rank, and a rank
      // invented on the box is a preemption order the floor never declared.
      // MEASURED 2026-09-07 by E2E-1: without it, a filler item's `admit`
      // carries the name `filler` and the door refuses the message as a decode
      // error, which is a real ordering fact arriving as a parse failure.
      const ordinalOf = initial.levels.levels.findIndex((level) => level.name === admit.level);
      const base = {
        ...admit,
        row: admit.rows[0]?.row ?? "",
        argv_ref: item.argv_ref ?? item.taskId,
        ...(ordinalOf < 0 ? {} : { level_rank: initial.levels.levels.length - 1 - ordinalOf }),
        next_wake_at: nextWake
      };
      return item.mutation_hint === undefined
        ? base
        : { ...base, mutation_hint: item.mutation_hint };
    };

    return Factory.of({
      armPlan: Effect.fn("Factory.armPlan")(function* (
        request: PlanArm,
        artifact: ArmedArtifact
      ) {
        const hasher = yield* ArtifactHasher;
        const digest = yield* hasher.hash(artifact.bytes, request.label).pipe(
          Effect.catchTag("ArtifactHashError", () =>
            fail("PlanHashMismatch", "Factory.armPlan", artifact.planId)
          )
        );
        if (digest !== request.planHash) {
          return yield* fail("PlanHashMismatch", "Factory.armPlan", artifact.planId);
        }
        yield* recordArming({ _tag: "HashVerified", planId: artifact.planId });

        const current = yield* Ref.get(state);
        const existing = current.plans.find((plan) => plan.planId === artifact.planId);
        if (existing !== undefined && existing.planHash !== digest) {
          return yield* fail("PlanHashMismatch", "Factory.armPlan", artifact.planId);
        }

        const row: PlanRow =
          existing ?? {
            planId: artifact.planId,
            planHash: digest,
            arm: request,
            status: "armed",
            attemptCap: Option.none()
          };

        const existingRanks = new Set(
          current.backlog
            .filter((item) => item.planId === artifact.planId)
            .map((item) => item.rank)
        );
        const existingTasks = new Set(current.backlog.map((item) => item.taskId));
        const additions: Array<BacklogItem> = [];
        for (const candidate of artifact.items) {
          if (existingRanks.has(candidate.rank) || existingTasks.has(candidate.taskId)) continue;
          existingRanks.add(candidate.rank);
          existingTasks.add(candidate.taskId);
          additions.push(candidate);
        }

        if (existing === undefined) {
          yield* recordArming({ _tag: "PlanRowWritten", planId: artifact.planId });
        }
        yield* Ref.update(state, (previous) => ({
          ...previous,
          plans: existing === undefined ? [...previous.plans, row] : previous.plans,
          backlog: [...previous.backlog, ...additions]
        }));
        yield* recordArming({
          _tag: "ItemsExpanded",
          planId: artifact.planId,
          count: additions.length
        });
        yield* recordArming({ _tag: "EvaluatorWoken", planId: artifact.planId });
        yield* appendFact("armed", artifact.planId, `append:${additions.length}`);
        yield* persist("Factory.armPlan", artifact.planId);
        yield* wake();
        return row;
      }),

      supersede: Effect.fn("Factory.supersede")(function* (planId: PlanId) {
        const current = yield* Ref.get(state);
        if (!current.plans.some((plan) => plan.planId === planId)) {
          return yield* fail("PlanNotArmed", "Factory.supersede", planId);
        }
        const unclaimed = current.backlog.filter(
          (item) => item.planId === planId && item.state === "unclaimed"
        );
        const active = current.backlog
          .filter(
            (item) =>
              item.planId === planId &&
              (item.state === "released" || item.state === "inflight")
          )
          .map((item) => item.taskId);

        yield* recordSupersession({ _tag: "PlanRetired", planId });
        yield* Ref.update(state, (previous) => ({
          ...previous,
          plans: previous.plans.map((plan) =>
            plan.planId === planId ? { ...plan, status: "superseded" as const } : plan
          ),
          backlog: previous.backlog.filter(
            (item) => !(item.planId === planId && item.state === "unclaimed")
          )
        }));
        yield* recordSupersession({
          _tag: "UnclaimedDropped",
          planId,
          count: unclaimed.length
        });
        yield* recordSupersession({
          _tag: "CancelsAuthorised",
          planId,
          tasks: active
        });
        yield* appendFact("superseded", planId, `active:${active.length}`);
        yield* persist("Factory.supersede", planId);
        yield* wake();
        return active;
      }),

      evaluate: Effect.fn("Factory.evaluate")(function* (reading: CapacityReading) {
        return evaluateRelease(yield* Ref.get(state), reading);
      }),

      evaluateAcross: Effect.fn("Factory.evaluateAcross")(function* (
        readings: ReadonlyArray<CapacityReading>
      ) {
        return evaluateReleaseAcross(yield* Ref.get(state), readings);
      }),

      observeCapacity: Effect.fn("Factory.observeCapacity")(function* (
        incoming: CapacityReading,
        asOf?: string
      ) {
        // The seats ride along but are the ledger's, not the reading's: they are
        // folded in on their own monotonic rule (a repeated `seq` may still carry
        // a newer seat observation) and never stored inside the reading.
        const { seats, ...reading } = incoming;
        if (seats !== undefined && asOf === undefined) {
          return yield* Effect.fail(
            factoryError("NoClock", "Factory.observeCapacity", "capacity/seats")
          );
        }
        const clock = asOf === undefined ? Option.none<string>() : Option.some(asOf);
        const seatReport =
          seats === undefined || asOf === undefined ? undefined : yield* ingestSeats(seats, asOf);
        const readings = yield* Ref.get(latestReadings);
        const previous = readings.get(reading.executor);
        if (previous !== undefined && reading.seq <= previous.seq) {
          if (seatReport?.changed === true) {
            yield* recomputeAlarm(clock);
            yield* persist("Factory.observeCapacity", reading.executor);
          }
          return false;
        }
        const next = new Map(readings);
        next.set(reading.executor, reading);
        yield* Ref.set(latestReadings, next);
        yield* recomputeAlarm(clock);
        const nextAlarm = yield* Ref.get(alarmAt);
        yield* appendEvent("Factory.observeCapacity", reading.executor, {
          seq: reading.seq,
          alarm_at: optionJson(nextAlarm)
        });
        yield* persist("Factory.observeCapacity", reading.executor);
        yield* wake();
        return true;
      }),

      observeSeats: Effect.fn("Factory.observeSeats")(function* (
        snapshot: SeatCapacitySnapshot,
        receivedAt: string
      ) {
        const report = yield* ingestSeats(snapshot, receivedAt);
        if (!report.changed) return report;
        yield* recomputeAlarm(Option.some(receivedAt));
        yield* appendEvent("Factory.observeSeats", snapshot.host, {
          published_at: snapshot.published_at,
          accepted: report.results
            .filter((result) => result.outcome === "accepted")
            .map((result) => result.seat),
          alarm_at: optionJson(yield* Ref.get(alarmAt))
        });
        yield* persist("Factory.observeSeats", snapshot.host);
        yield* wake();
        return report;
      }),

      capacityAt: Effect.fn("Factory.capacityAt")(function* (asOf: string) {
        return yield* ledger.at(asOf).pipe(
          Effect.mapError(() => factoryError("PersistenceFailed", "Factory.capacityAt", asOf))
        );
      }),

      admitSeat: Effect.fn("Factory.admitSeat")(function* (
        seat: string,
        job: SeatJob,
        asOf: string
      ) {
        return yield* ledger.admit(seat, job, asOf).pipe(
          Effect.mapError(() => factoryError("PersistenceFailed", "Factory.admitSeat", seat))
        );
      }),

      rearm: Effect.fn("Factory.rearm")(function* (asOf: string) {
        if (yield* recomputeAlarm(Option.some(asOf))) {
          yield* persist("Factory.rearm", asOf);
        }
        return yield* Ref.get(alarmAt);
      }),

      handOut: Effect.fn("Factory.handOut")(function* (executor: ExecutorId) {
        const readings = yield* Ref.get(latestReadings);
        const reading = readings.get(executor);
        if (reading === undefined) return [];

        const current = yield* Ref.get(state);
        const decision = evaluateRelease(current, reading);
        yield* Ref.set(lastDecision, {
          admits: decision.admits,
          deferrals: decision.deferrals,
          andons: decision.andons,
          paces: [[reading.executor, decision.pace]],
          certificate: decision.certificate
        });
        yield* applyDeferrals(decision.deferrals);

        const handed = new Set(decision.admits.map((admit) => admit.taskId));
        for (const admit of decision.admits) {
          yield* appendEvent("Factory.handOut", admit.taskId, {
            state: "released",
            executor: admit.executor,
            dedupKey: admit.dedupKey
          });
          yield* appendFact("released", admit.taskId, admit.executor);
        }
        // The filler lane's age counter (spec §4.4 clause 3, D-B10). This is the
        // one writer of `passedOver`: every non-filler admit that took the
        // lane's row in this pass passes over every filler item that stayed in
        // the backlog, and an item that WAS handed out was not passed over, so
        // its counter goes back to zero. That reset is what makes a promotion
        // last "for one release" rather than for ever.
        const lane = current.filler;
        const fillers = fillerTaskIds(current.backlog, lane);
        const passes = passedOverBy(decision.admits, fillers, lane);
        yield* Ref.update(state, (previous) => ({
          ...previous,
          backlog: previous.backlog.map((item) => {
            const released = handed.has(item.taskId)
              ? { ...item, state: "released" as const }
              : item;
            if (lane === undefined || !fillers.has(item.taskId)) return released;
            if (handed.has(item.taskId)) return { ...released, passedOver: 0 };
            return passes === 0
              ? released
              : { ...released, passedOver: released.passedOver + passes };
          })
        }));
        yield* persist("Factory.handOut", executor);

        const nextWake = optionJson(yield* Ref.get(alarmAt));
        const byTask = new Map(current.backlog.map((item) => [item.taskId, item] as const));
        return decision.admits.flatMap((admit) => {
          const item = byTask.get(admit.taskId);
          return item === undefined ? [] : [proposalFor(admit, item, nextWake)];
        });
      }),

      observeOutcome: Effect.fn("Factory.observeOutcome")(function* (
        report: AdmitOutcomeReport
      ) {
        const current = yield* Ref.get(state);
        const item = current.backlog.find((candidate) => candidate.taskId === report.taskId);
        if (item === undefined) {
          return yield* fail("UnknownTask", "Factory.observeOutcome", report.taskId);
        }
        if (item.dedupKey !== report.dedupKey) {
          return yield* fail("DedupMismatch", "Factory.observeOutcome", report.taskId);
        }
        const key = outcomeIdentity(report);
        const seen = yield* Ref.get(outcomeKeys);
        // Applying an outcome always leaves `released`. An exact replay while
        // in that resulting state is idempotent. If a later hand-out has moved
        // the item back to `released`, however, it is a new proposal cycle even
        // when NotYet intentionally retained the same dedupKey and report.
        if (seen.has(key) && item.state !== "released") {
          return { idempotent: true, decision: yield* wake() };
        }
        if (item.state !== "released") {
          return yield* fail("InvalidTransition", "Factory.observeOutcome", report.taskId);
        }

        yield* appendEvent("Factory.observeOutcome", report.taskId, {
          outcome: report.outcome,
          row: report.row
        });
        yield* Ref.update(outcomeKeys, (keys) => new Set(keys).add(key));
        if (report.outcome === "Accepted") {
          yield* Ref.update(state, (previous) => ({
            ...previous,
            backlog: previous.backlog.map((candidate) =>
              candidate.taskId === item.taskId
                ? { ...candidate, state: "inflight" as const }
                : candidate
            ),
            wip: changeWip(previous.wip, item, 1)
          }));
        } else if (report.outcome === "NotYet") {
          yield* Ref.update(state, (previous) => ({
            ...previous,
            backlog: previous.backlog.map((candidate) =>
              candidate.taskId === item.taskId
                ? {
                    ...candidate,
                    state: "unclaimed" as const,
                    deferrals: candidate.deferrals + 1
                  }
                : candidate
            )
          }));
          yield* countRowDeferral(report.row);
          yield* appendFact("deferred", report.taskId, report.row);
        } else {
          yield* Ref.update(state, (previous) => ({
            ...previous,
            backlog: previous.backlog.map((candidate) =>
              candidate.taskId === item.taskId
                ? { ...candidate, state: "closed" as const }
                : candidate
            )
          }));
          yield* appendFact("rejected", report.taskId, report.code ?? report.row);
        }
        yield* persist("Factory.observeOutcome", report.taskId);
        return { idempotent: false, decision: yield* wake() };
      }),

      recordDeferrals: Effect.fn("Factory.recordDeferrals")(function* (
        deferrals: ReadonlyArray<Deferral>
      ) {
        yield* applyDeferrals(deferrals);
        yield* persist("Factory.recordDeferrals", "release-pass");
      }),

      observeVerdict: Effect.fn("Factory.observeVerdict")(function* (verdict: Verdict) {
        const records = yield* Ref.get(mirrored);
        const duplicate = records.some(
          (candidate) =>
            candidate.executor === verdict.executor &&
            candidate.seq === verdict.seq &&
            candidate.hash === verdict.hash
        );
        if (duplicate) {
          return {
            idempotent: true,
            continuous: true,
            decision: yield* wake()
          };
        }

        const current = yield* Ref.get(state);
        const item = current.backlog.find((candidate) => candidate.taskId === verdict.taskId);
        if (item !== undefined && item.state !== "inflight") {
          return yield* fail(
            "InvalidTransition",
            "Factory.observeVerdict",
            `${verdict.taskId} (state ${item.state})`
          );
        }

        const mirrors = yield* Ref.get(mirror);
        const chain = mirrors.get(verdict.executor);
        const firstHasGap = chain === undefined && verdict.seq > 1;
        const advanced = advanceMirror(mirrors, verdict);
        if (firstHasGap || !advanced.continuous) {
          const after =
            chain === undefined || Option.isNone(chain.last)
              ? (0 as Seq)
              : chain.last.value.seq;
          const gap: ContinuityGap = {
            executor: verdict.executor,
            after,
            before: verdict.seq
          };
          yield* Ref.update(rejectedGaps, (current) => [...current, gap]);
          yield* appendEvent("Factory.observeVerdict", verdict.taskId, {
            result: "continuity-gap",
            executor: verdict.executor,
            seq: verdict.seq
          });
          yield* persist("Factory.observeVerdict", verdict.taskId);
          return yield* fail("ContinuityGap", "Factory.observeVerdict", verdict.taskId);
        }

        yield* appendEvent("Factory.observeVerdict", verdict.taskId, {
          executor: verdict.executor,
          seq: verdict.seq,
          hash: verdict.hash,
          outcome: verdict.outcome
        });
        yield* Ref.set(mirror, advanced.mirror);
        yield* Ref.update(mirrored, (currentRecords) => [...currentRecords, verdict]);

        if (item !== undefined) {
          const plan = current.plans.find((candidate) => candidate.planId === item.planId);
          const mayRetry =
            verdict.outcome !== "pass" &&
            (plan === undefined ||
              Option.isNone(plan.attemptCap) ||
              item.attempt < plan.attemptCap.value);
          const nextState: BacklogItem["state"] = mayRetry ? "unclaimed" : "closed";
          const nextOutcome: Option.Option<VerdictOutcome> = Option.some(verdict.outcome);
          yield* Ref.update(state, (previous) => ({
            ...previous,
            backlog: previous.backlog.map((candidate) =>
              candidate.taskId === item.taskId
                ? {
                    ...candidate,
                    state: nextState,
                    outcome: nextOutcome,
                    attempt: mayRetry ? candidate.attempt + 1 : candidate.attempt,
                    dedupKey: mayRetry
                      ? dedupKeyForAttempt(candidate, candidate.attempt + 1)
                      : candidate.dedupKey,
                    deferrals: mayRetry ? candidate.deferrals + 1 : candidate.deferrals
                  }
                : candidate
            ),
            wip:
              item.state === "inflight"
                ? changeWip(previous.wip, item, -1)
                : previous.wip
          }));
        }
        yield* persist("Factory.observeVerdict", verdict.taskId);
        return {
          idempotent: false,
          continuous: true,
          decision: yield* wake()
        };
      }),

      observeReceipt: Effect.fn("Factory.observeReceipt")(function* (
        receipt: ReceiptEvidence
      ) {
        const current = yield* Ref.get(acceptedReceipts);
        if (
          current.some(
            (candidate) =>
              candidate.id === receipt.id &&
              candidate.verdict_hash === receipt.verdict_hash &&
              candidate.oracle_rc === receipt.oracle_rc &&
              candidate.mutation_rc === receipt.mutation_rc &&
              sameDigest(candidate.oracle_output_sha256, receipt.oracle_output_sha256)
          )
        ) {
          return { idempotent: true };
        }
        const records = yield* Ref.get(mirrored);
        const match = records.find(
          (verdict) =>
            verdict.hash === receipt.verdict_hash &&
            verdict.unit_id === receipt.id &&
            verdict.oracle_rc === receipt.oracle_rc &&
            verdict.mutation_rc === receipt.mutation_rc &&
            sameDigest(verdict.oracle_output_sha256, receipt.oracle_output_sha256)
        );
        if (match === undefined) {
          return yield* fail("ReceiptMismatch", "Factory.observeReceipt", receipt.id);
        }
        const event: Record<string, JsonValue> = {
          verdict_hash: receipt.verdict_hash,
          oracle_rc: receipt.oracle_rc,
          oracle_output_sha256: receipt.oracle_output_sha256
        };
        if (receipt.mutation_rc !== undefined) event["mutation_rc"] = receipt.mutation_rc;
        yield* appendEvent("Factory.observeReceipt", receipt.id, event);
        yield* Ref.update(acceptedReceipts, (receipts) => [...receipts, receipt]);
        yield* persist("Factory.observeReceipt", receipt.id);
        return { idempotent: false };
      }),

      observeHeartbeat: Effect.fn("Factory.observeHeartbeat")(function* (
        heartbeat: Heartbeat,
        lane?: string,
        observedAt?: string
      ) {
        const laneName = lane ?? optionJson(heartbeat.taskId) ?? heartbeat.executor;
        const current = yield* Ref.get(heartbeats);
        const previous = current.get(laneName);
        if (previous !== undefined && heartbeat.seq <= previous.last_seq) return;
        const base: HeartbeatState = {
          executor: heartbeat.executor,
          task_id: optionJson(heartbeat.taskId),
          last_seq: heartbeat.seq,
          status: "live"
        };
        const nextHeartbeat: HeartbeatState =
          observedAt === undefined ? base : { ...base, observed_at: observedAt };
        const next = new Map(current);
        next.set(laneName, nextHeartbeat);
        yield* Ref.set(heartbeats, next);
        yield* appendEvent("Factory.observeHeartbeat", laneName, {
          executor: heartbeat.executor,
          seq: heartbeat.seq
        });
        yield* persist("Factory.observeHeartbeat", laneName);
      }),

      alarm: Effect.fn("Factory.alarm")(function* (firedAt: string) {
        yield* Ref.set(alarmFiredAt, Option.some(firedAt));
        // The instant that fired is spent: the next alarm is strictly after it,
        // so a reading whose window already passed cannot re-arm itself.
        yield* recomputeAlarm(Option.some(firedAt));
        yield* appendEvent("Factory.alarm", firedAt, {
          result: "fired",
          alarm_at: optionJson(yield* Ref.get(alarmAt))
        });
        yield* persist("Factory.alarm", firedAt);
        return yield* wake();
      }),

      stateView: Effect.gen(function* () {
        const seatView = yield* heldSeatsOrNone;
        const current = yield* Ref.get(state);
        const mirrors = yield* Ref.get(mirror);
        const readings = yield* Ref.get(latestReadings);
        const rowDeferrals = yield* Ref.get(deferralsByRow);
        const laneHeartbeats = yield* Ref.get(heartbeats);
        const gaps = yield* Ref.get(rejectedGaps);
        const records = yield* Ref.get(mirrored);
        const receipts = yield* Ref.get(acceptedReceipts);
        const currentFacts = yield* Ref.get(facts);

        const level: Record<string, number> = {};
        const namespace: Record<string, number> = {};
        const family: Record<string, number> = {};
        for (const cap of current.caps) {
          if (cap.axis === "level") level[cap.subject] ??= 0;
          if (cap.axis === "namespace") namespace[cap.subject] ??= 0;
          if (cap.axis === "family") family[cap.subject] ??= 0;
        }
        for (const item of current.backlog) {
          level[item.level] ??= 0;
          namespace[item.namespace] ??= 0;
          family[item.family] ??= 0;
        }
        for (const entry of current.wip) {
          level[entry.level] = (level[entry.level] ?? 0) + entry.count;
          namespace[entry.namespace] = (namespace[entry.namespace] ?? 0) + entry.count;
          family[entry.family] = (family[entry.family] ?? 0) + entry.count;
        }

        const chains: Record<string, ChainHighWater> = {};
        for (const [executor, chain] of mirrors) {
          if (Option.isNone(chain.last)) continue;
          chains[executor] = {
            last_seq: chain.last.value.seq,
            last_hash: chain.last.value.hash
          };
        }

        const latest: Record<string, Record<string, unknown>> = {};
        for (const [executor, reading] of readings) {
          latest[executor] = {
            ...reading,
            rows: reading.rows.map((row) => ({
              ...row,
              remainingBudget: optionJson(row.remainingBudget)
            }))
          };
        }
        const backlog = current.backlog.map((item) => ({
          ...item,
          dependsOn: [...item.dependsOn],
          outcome: optionJson(item.outcome),
          subassembly: optionJson(item.subassembly),
          dueBy: optionJson(item.dueBy),
          float: optionJson(item.float),
          envelopeParent: optionJson(item.envelopeParent)
        }));

        return {
          backlog,
          wip: { level, namespace, family },
          chains,
          latest_readings: latest,
          alarm_at: optionJson(yield* Ref.get(alarmAt)),
          alarm_fired_at: optionJson(yield* Ref.get(alarmFiredAt)),
          seat_readings: seatView.held,
          seat_readings_error: seatView.error,
          deferrals_by_row: Object.fromEntries(rowDeferrals),
          heartbeats_by_lane: Object.fromEntries(laneHeartbeats),
          continuity_gaps: gaps,
          mirrored_verdicts: records.length,
          receipts,
          facts: currentFacts,
          price_hash: current.prices.hash
        } satisfies FactoryStateView;
      }),

      releaseState: Ref.get(state),

      restore: Effect.fn("Factory.restore")(function* (next: ReleaseState) {
        yield* Ref.set(state, next);
        yield* appendEvent("Factory.restore", "factory/state", { result: "restored" });
        yield* persist("Factory.restore", FACTORY_STATE_KEY);
        yield* wake();
      })
    });
  });

/** Provides the release station without selecting a storage implementation. */
const factoryLayerWithoutDependencies = (
  initial: ReleaseState
): Layer.Layer<Factory, FactoryError, PlanningStore> => Layer.effect(Factory, makeFactory(initial));

/** Provides the release station over the in-memory PlanningStore. */
export const factoryTestLayer = (
  initial: ReleaseState
): Layer.Layer<Factory, FactoryError> =>
  factoryLayerWithoutDependencies(initial).pipe(Layer.provide(planningStoreInMemoryLayer));
