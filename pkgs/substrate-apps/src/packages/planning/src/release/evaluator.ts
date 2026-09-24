/**
 * The release evaluator.
 *
 * One pure function from object state plus exactly one capacity reading to a
 * list of admit proposals, a list of named deferrals, and a list of andons. It
 * reads nothing else: no clock, no randomness, no service, no input or output.
 * That is what makes it unit-testable against a fabricated capacity reading,
 * which is precisely what the code behind the mutex incident was not.
 *
 * One reading is one executor. A kernel is anything implementing the
 * admit-and-witness contract, the lake holds one Kernel object per executor, and
 * several may be reachable at once — so beside the single-reading function there
 * is an explicit fold across several, which threads what has been claimed so one
 * item is never proposed to two doors. Nothing here assumes there is one
 * executor, and an executor that declares no device rows and no seats simply
 * defers the items that need them, by the same rule that defers on a busy row.
 *
 * Volume I chapter 11.2 says what this is and what it is not. It is the release
 * station CONWIP was missing: cap the work in process, release into the cap from
 * a priority-ordered backlog, run deterministic routings inside. It is not a
 * second scheduler, because release is a policy evaluation and not a plan; it
 * does not violate the doctrine that tally never originates intent, because
 * every backlog item is human-scoped intent Tom already armed and the station
 * only times its entry — the rope, not the drum; and it is not a revival of the
 * old queues, because the backlog holds scoped work before release while the old
 * queues held submitted work inside the shop.
 *
 * Everything it returns is a proposal. The executor's admission door answers
 * accept, reject or not yet, and verifies the brief hash against the armed set
 * itself, in its own process, before anything runs.
 */
import { Option } from "effect";
import type { Andon, Admit, Deferral } from "../schema/admit.ts";
import type { BacklogItem, WipCount } from "../schema/backlog.ts";
import {
  rowHeadroom,
  rowReading,
  type CapacityReading
} from "../schema/capacity.ts";
import { membersForClass, type Catalog, type CatalogMember } from "../schema/catalog.ts";
import type { EstimateTable } from "../schema/estimate.ts";
import type { MemberId, PlanId, RowName, Sha256Hex, TaskId } from "../schema/ids.ts";
import type { LevelList } from "../schema/levels.ts";
import type { BufferPolicy, NamespaceTable } from "../schema/namespace.ts";
import type { PlanRow } from "../schema/plan.ts";
import type { PriceVector } from "../schema/prices.ts";
import type { PriorStamp } from "../schema/selection.ts";
import type { Rows, RowSet } from "../schema/rows.ts";
import { bufferAndons, type FamilyInventory } from "../heuristics/bufferAndon.ts";
import { conwipVerdict, type ConwipContext } from "../heuristics/conwip.ts";
import {
  deadlineCertificate,
  underDeadlinePressure,
  type DatedItem,
  type DeadlineCertificate
} from "../heuristics/eddCertificate.ts";
import { envelopeOf, grantChild, type Envelope } from "../heuristics/envelope.ts";
import {
  fillerSources,
  fillerTaskIds,
  fillerTurn,
  preemptibleHolders,
  promoteAgedFillers,
  type FillerLane
} from "../heuristics/fillerLane.ts";
import {
  applyLengthTerm,
  lengthTerm,
  DEFAULT_LENGTH_EXPONENT
} from "../heuristics/lengthTermFlip.ts";
import { DEFAULT_MEDIAN_MULTIPLE } from "../heuristics/killRedispatch.ts";
import { routeLocalFirst, type Routing } from "../heuristics/localFirst.ts";
import { roundRobinByNamespace } from "../heuristics/namespaceRoundRobin.ts";
import { fitsPaceLine, paceLine, type PaceLine } from "../heuristics/paceLine.ts";
import { type Diversity } from "../heuristics/redundancy.ts";
import { runtimeCap } from "../heuristics/runtimeCap.ts";
import {
  subassemblyBatches,
  type Subassembly
} from "../heuristics/subassemblyBatching.ts";
import { bindingRow, coversBidPrice, valueDensity } from "../heuristics/valueDensity.ts";
import { bucketByLevel, orderWithinLevel, undeclaredLevelItems } from "./ordering.ts";

/**
 * How the preference order over members is built for one item.
 *
 * The theory fixes the *first* choice and nothing after it: local-first is
 * optimal whenever local yield is positive, and escalation is licensed on
 * exactly three grounds. What order the remaining members should be tried in,
 * when the first is busy, has no source in the canon — so it is data.
 *
 * `routerOrder` asks the router repeatedly, removing what it chose, which yields
 * the router's own preference — warmth first, then yield, then service time —
 * all the way down. `catalogOrder` tries members in the order the authored
 * catalog declares them, which is the most predictable and the least adaptive:
 * Tom orders the catalog and the plant follows it. `warmFirst` is catalog order
 * with the members already resident lifted to the front, which buys avoided cold
 * loads without giving the router a say in the rest.
 *
 * Whether escalation is licensed is *not* one of these decisions. The router
 * answers that on its own, over the whole eligible set, whatever order the
 * candidates are then tried in.
 */
type RoutingPreference = "routerOrder" | "warmFirst" | "catalogOrder";

/**
 * What an item does when congestion, rather than a licensed ground, is what is
 * stopping it.
 *
 * `Wait` is the conservative reading of the canon: a busy free row is not one of
 * the three grounds for escalation, so the item waits for the row it prefers and
 * the envelope is never spent merely because a device was occupied. `EscalateAfter`
 * says that after a run of passes have each passed the item over, congestion has
 * lasted long enough to be a fact about the plant rather than a moment, and the
 * item may take a metered lane. Neither is derivable from the theory, which is
 * why the choice is here and not in the code.
 */
type CongestionPolicy =
  | { readonly _tag: "Wait" }
  | {
      readonly _tag: "EscalateAfter";
      /** How many consecutive deferrals count as sustained congestion. */
      readonly deferrals: number;
    };

/**
 * The tunable half of the release rule, all of it data.
 *
 * Every field here is an edit in the left column of the data/code split: a
 * strategic change Tom makes is a change to one of these values, and nothing in
 * this module knows a product family by name. The fields fall into two kinds.
 * Some carry a number the theory names but does not fix — `kappa`, the median
 * multiple, the p99 floor and ceiling. The rest exist because a rule in the
 * evaluator had no source in the canon and was therefore a preference someone
 * had encoded as code: those are `routingPreference`, `dropMeteredWhenFreePreferred`,
 * `lengthExponent` and `congestion`, and `defaultReleasePolicy` below documents
 * what each defaults to and why.
 */
export interface ReleasePolicy {
  /** The burst allowance on the pace line, between one and three. */
  readonly kappa: number;
  /** How many class medians to allow before asking a holder to yield. */
  readonly medianMultiple: number;
  /** The shortest lane cap worth setting. */
  readonly runtimeFloorSeconds: number;
  /** The longest lane duration the host will permit. */
  readonly runtimeCeilingSeconds: number;
  /** How many redundant attempts to draw where the merge gate is mechanical. */
  readonly redundancyCount: number;
  /** Which axis redundant attempts are drawn distinct on. */
  readonly redundancyDiversity: Diversity;
  /** The smallest subassembly saving worth reordering the density sort for. */
  readonly minimumBatchSavingSeconds: number;
  /** Metered weight already committed in the current window. */
  readonly spentThisWindow: number;
  /**
   * How the preference order over members is built, past the router's first
   * choice.
   */
  readonly routingPreference: RoutingPreference;
  /**
   * Whether a preferred free routing removes the metered members from the order
   * entirely.
   *
   * True is the canon's reading: congestion never licenses escalation, so an
   * item whose preferred lane is free waits for a free lane. False lets the walk
   * fall through to a metered member the moment the free rows are busy, which
   * spends the envelope on congestion — legible here as a choice rather than as
   * an accident of how the loop was written.
   */
  readonly dropMeteredWhenFreePreferred: boolean;
  /** How steeply the length term grows with the length ratio. */
  readonly lengthExponent: number;
  /** Whether sustained congestion leaves an item waiting or lets it escalate. */
  readonly congestion: CongestionPolicy;
}

/**
 * The documented defaults.
 *
 * Every value here is a starting point Tom moves, and each is the weakest
 * setting that still does what the theory says. `kappa` at two allows a
 * deliberate burst to twice the pace line without letting a window be swept.
 * `medianMultiple` at three is the figure the decreasing-hazard argument uses.
 * The runtime floor at five minutes keeps a cap from killing ordinary work and
 * the ceiling at twelve hours is the host's own limit, which the class p99 is
 * meant to come in well under. `redundancyCount` at two with `pair` diversity is
 * the smallest set that decorrelates over both halves of the machine index.
 * `routingPreference` is `routerOrder` because that is what the router would say
 * if asked again. `dropMeteredWhenFreePreferred` is true because a busy row is
 * not one of the three grounds. `lengthExponent` is one, the linear preference.
 * `congestion` is `Wait`, because holding the envelope is the conservative error
 * and spending it on congestion is the expensive one.
 */
export const defaultReleasePolicy: ReleasePolicy = {
  kappa: 2,
  medianMultiple: DEFAULT_MEDIAN_MULTIPLE,
  runtimeFloorSeconds: 300,
  runtimeCeilingSeconds: 43200,
  redundancyCount: 2,
  redundancyDiversity: "pair",
  minimumBatchSavingSeconds: 60,
  spentThisWindow: 0,
  routingPreference: "routerOrder",
  dropMeteredWhenFreePreferred: true,
  lengthExponent: DEFAULT_LENGTH_EXPONENT,
  congestion: { _tag: "Wait" }
};

/** Everything the Factory object holds that a release decision reads. */
export interface ReleaseState {
  /** The unclaimed backlog. */
  readonly backlog: ReadonlyArray<BacklogItem>;
  /** Armed plan rows; an item whose plan is not armed is never a candidate. */
  readonly plans: ReadonlyArray<PlanRow>;
  /** The authored preemptive level list. */
  readonly levels: LevelList;
  /** The authored namespace table. */
  readonly namespaces: NamespaceTable;
  /** The published price vector. */
  readonly prices: PriceVector;
  /** The declared row table, which says which rows are metered. */
  readonly rows: Rows;
  /** The pinned catalog. */
  readonly catalog: Catalog;
  /** Estimates over the pair-and-class matrix, already shrunk. */
  readonly estimates: EstimateTable;
  /** Current released-or-in-flight counts. */
  readonly wip: ReadonlyArray<WipCount>;
  /** Declared caps on levels, namespaces and families. */
  readonly caps: ConwipContext["caps"];
  /** Outstanding envelopes, for items that are recursive children. */
  readonly envelopes: ReadonlyArray<Envelope>;
  /** Declared base-stock policies per family. */
  readonly buffers: ReadonlyArray<BufferPolicy>;
  /** Scoped-ready inventory per family. */
  readonly inventory: ReadonlyArray<FamilyInventory>;
  /** Declared warm prerequisites and their decay laws. */
  readonly subassemblies: ReadonlyArray<Subassembly>;
  /** The tunables. */
  readonly policy: ReleasePolicy;
  /**
   * The prior each item is released under, when a selection pass supplied one.
   *
   * U-A24, and it is deliberately a `Map` handed in rather than a file read
   * here: this package opens nothing. `release/selectorRead.ts` decodes
   * `cards/selection-<pass>.tsv` and `cards/bands.tsv` and builds it; the
   * evaluator copies the stamp onto the admit and reads nothing inside it. No
   * rule below branches on `prior_source` and no comparator touches the draw —
   * the selector chooses, the station times the entry (spec §4.4 rule 5).
   *
   * Absent for a state armed from cards rather than from a selection pass, which
   * is every state that existed before this field did.
   */
  readonly priors?: ReadonlyMap<TaskId, PriorStamp>;
  /**
   * The filler lane, when the floor declares one.
   *
   * Optional, and its absence is the whole of the backwards compatibility: a
   * floor with no filler level behaves exactly as it did before §4.4's contract
   * was code. Its numbers are D-B10's and its document is `docs/levels.md`.
   */
  readonly filler?: FillerLane;
}

/** What one pass against one executor produces. */
export interface ReleaseDecision {
  /** The proposals, in the order they should cross to the executor. */
  readonly admits: ReadonlyArray<Admit>;
  /** Every candidate that did not make it, with the rule that stopped it. */
  readonly deferrals: ReadonlyArray<Deferral>;
  /** Families below their reorder point. */
  readonly andons: ReadonlyArray<Andon>;
  /** The pace line this pass computed. */
  readonly pace: PaceLine;
  /** The deadline certificate over the dated subset. */
  readonly certificate: DeadlineCertificate;
}

/** What one fold across several executors produces. */
export interface MultiReleaseDecision {
  /** Every proposal, each stamped with the executor it is addressed to. */
  readonly admits: ReadonlyArray<Admit>;
  /**
   * Candidates no executor took, each with the rule that stopped it first.
   *
   * An item deferred on one executor and admitted on another is not deferred: it
   * ran. Reporting it both ways would make the deferral counts that feed the
   * congestion policy count congestion that did not happen.
   */
  readonly deferrals: ReadonlyArray<Deferral>;
  /** Families below their reorder point, computed once. */
  readonly andons: ReadonlyArray<Andon>;
  /** The pace line each executor's own envelope produced. */
  readonly paces: ReadonlyArray<readonly [CapacityReading["executor"], PaceLine]>;
  /** The deadline certificate over the dated subset, computed once. */
  readonly certificate: DeadlineCertificate;
}

const meteredRowNames = (rows: Rows): ReadonlyArray<RowName> =>
  rows.filter((row) => row.metered).map((row) => row.name);

const rowSetFor = (
  member: CatalogMember,
  item: BacklogItem,
  metered: ReadonlyArray<RowName>
): RowSet =>
  member.rows.map((row) => ({
    row,
    holders: 1,
    consumption: metered.includes(row) ? item.estimate.p80Consumption : 0
  }));

/**
 * One member the item could run on, with the rows that choice consumes.
 *
 * A preference order rather than a single choice, because two items of the same
 * class contend for the same member's rows within one pass. Walking the order
 * at the gate is what lets a second item take the second device row instead of
 * deferring behind the first, which is the concrete shape of the shipped
 * catalog's defect: two members naming one capacity-one row serialise a quorum
 * that was meant to be concurrent.
 */
interface RoutingCandidate {
  /** The routing, carrying the member and why it was escalated to if it was. */
  readonly routing: Routing;
  /** The rows that member consumes for this item. */
  readonly rows: RowSet;
}

const memberById = (
  catalog: Catalog,
  id: MemberId
): Option.Option<CatalogMember> => {
  for (const member of catalog.members) {
    if (member.id === id) return Option.some(member);
  }
  return Option.none();
};

/**
 * The armed plans, by id, carrying the digest that authorises their items.
 *
 * The hash is read from the plan row rather than from the item, so an admit
 * cites the authority as the arming act recorded it. An item whose plan is not
 * armed is not a candidate at all.
 */
const armedPlans = (plans: ReadonlyArray<PlanRow>): ReadonlyMap<PlanId, Sha256Hex> => {
  const armed = new Map<PlanId, Sha256Hex>();
  for (const plan of plans) {
    if (plan.status === "armed") armed.set(plan.planId, plan.planHash);
  }
  return armed;
};

const datedSubset = (items: ReadonlyArray<BacklogItem>): ReadonlyArray<DatedItem> => {
  const dated: Array<DatedItem> = [];
  for (const item of items) {
    if (Option.isNone(item.dueBy)) continue;
    dated.push({
      taskId: item.taskId,
      releaseWindow: item.dueBy.value,
      durationWindows: 1,
      dueWindow: item.dueBy.value
    });
  }
  return dated;
};

/**
 * Reorders candidates so items sharing a warm prerequisite run contiguously.
 *
 * Applied before the capacity gate rather than after it. Batching is a release
 * ordering decision, so it must not depend on how much headroom happens to
 * exist: making the order a function of the reading would break the monotone
 * deferral property, under which a strictly better reading admits a superset.
 */
const applyBatching = (
  ordered: ReadonlyArray<BacklogItem>,
  state: ReleaseState
): ReadonlyArray<BacklogItem> => {
  const batches = subassemblyBatches(
    ordered,
    state.subassemblies,
    state.policy.minimumBatchSavingSeconds
  );
  if (batches.length === 0) return ordered;

  const grouped = new Set<TaskId>();
  const result: Array<BacklogItem> = [];
  for (const batch of batches) {
    for (const item of batch.items) {
      if (grouped.has(item.taskId)) continue;
      grouped.add(item.taskId);
      result.push(item);
    }
  }
  for (const item of ordered) {
    if (grouped.has(item.taskId)) continue;
    result.push(item);
  }
  return result;
};

/** One item's candidates, and whether the router licensed a metered lane. */
interface ItemRouting {
  /** The members to try, in the order the policy asks for. */
  readonly order: ReadonlyArray<RoutingCandidate>;
  /**
   * Whether the router, over the whole eligible set, chose a metered member.
   *
   * Computed independently of the ordering, so re-ordering the candidates can
   * never quietly license an escalation the three grounds did not license.
   */
  readonly licensed: boolean;
}

/**
 * Builds one item's preference order over members, under the declared policy.
 *
 * The router always answers the licensing question; the policy answers only what
 * order the candidates are tried in.
 */
const preferenceOrder = (
  item: BacklogItem,
  state: ReleaseState,
  reading: CapacityReading,
  certificate: DeadlineCertificate,
  metered: ReadonlyArray<RowName>
): ItemRouting => {
  const context = {
    needs: item.needs,
    estimates: state.estimates,
    residentMembers: reading.residentMembers,
    deadlinePressure: underDeadlinePressure(certificate, item.taskId),
    priorFailure: false
  };

  const candidateFor = (
    eligible: ReadonlyArray<CatalogMember>
  ): Option.Option<RoutingCandidate> =>
    Option.flatMap(routeLocalFirst(eligible, context), (routing) =>
      Option.map(memberById(state.catalog, routing.member), (member) => ({
        routing,
        rows: rowSetFor(member, item, metered)
      }))
    );

  const eligibleMembers = membersForClass(state.catalog, item.needs);

  // The router's own answer over the whole set: which member it would take, and
  // therefore whether one of the three grounds licensed a metered lane.
  const licensed = Option.match(routeLocalFirst(eligibleMembers, context), {
    onNone: () => false,
    onSome: (routing) => routing.metered
  });

  if (state.policy.routingPreference !== "routerOrder") {
    const declared: Array<RoutingCandidate> = [];
    for (const member of eligibleMembers) {
      const candidate = candidateFor([member]);
      if (Option.isSome(candidate)) declared.push(candidate.value);
    }
    // Stable in both halves: warm candidates keep the catalog's relative order
    // among themselves, and so do cold ones.
    const order =
      state.policy.routingPreference === "warmFirst"
        ? [
            ...declared.filter((candidate) => candidate.routing.warm),
            ...declared.filter((candidate) => !candidate.routing.warm)
          ]
        : declared;
    return { order, licensed };
  }

  const order: Array<RoutingCandidate> = [];
  let remaining = eligibleMembers;
  while (remaining.length > 0) {
    const candidate = candidateFor(remaining);
    if (Option.isNone(candidate)) break;
    order.push(candidate.value);
    const chosen = candidate.value.routing.member;
    remaining = remaining.filter((member) => member.id !== chosen);
  }
  return { order, licensed };
};

/** What one pass carries into the next, when several executors are folded. */
interface PassCarry {
  /** Items already proposed to an earlier executor in this fold. */
  readonly claimed: ReadonlySet<TaskId>;
  /** Every item accepted so far, which the caps count. */
  readonly accepted: ReadonlyArray<BacklogItem>;
  /** Envelopes as earlier passes left them. */
  readonly envelopes: ReadonlyArray<Envelope>;
  /**
   * Metered weight committed so far in this window.
   *
   * Carried across executors even though metered rows belong to one of them:
   * carrying it can only tighten the pace line, and tightening is always safe.
   */
  readonly spent: number;
}

/** One pass's result, plus what it hands on. */
interface PassResult {
  readonly admits: ReadonlyArray<Admit>;
  readonly deferrals: ReadonlyArray<Deferral>;
  readonly pace: PaceLine;
  readonly carry: PassCarry;
}

const emptyCarry = (state: ReleaseState): PassCarry => ({
  claimed: new Set<TaskId>(),
  // A proposal handed out but not answered is a reservation against the cap.
  // `wip` itself starts only at Accepted, as the state-machine contract says;
  // carrying released items here prevents a second pull from reserving the
  // same slack while the first answer is in flight.
  accepted: state.backlog.filter((item) => item.state === "released"),
  envelopes: state.envelopes,
  spent: state.policy.spentThisWindow
});

/**
 * Evaluates one pass against one executor's reading.
 *
 * The composition order is itself the policy: armed only, then preemptive
 * levels, then namespace fairness, then the work-in-process caps, then routing
 * and redundancy, then the envelope, then value density with the length term,
 * then subassembly grouping, then the capacity gate.
 */
const releasePass = (
  state: ReleaseState,
  reading: CapacityReading,
  certificate: DeadlineCertificate,
  incoming: PassCarry
): PassResult => {
  const deferrals: Array<Deferral> = [];
  const admits: Array<Admit> = [];
  const accepted: Array<BacklogItem> = [...incoming.accepted];

  const pace = paceLine(reading.envelope, state.policy.kappa);
  const metered = meteredRowNames(state.rows);
  const armed = armedPlans(state.plans);

  const unclaimed = state.backlog.filter(
    (item) => item.state === "unclaimed" && !incoming.claimed.has(item.taskId)
  );

  for (const item of unclaimed) {
    if (!armed.has(item.planId)) {
      deferrals.push({ taskId: item.taskId, rule: "planNotArmed", detail: item.planId });
    }
  }
  for (const item of undeclaredLevelItems(unclaimed, state.levels)) {
    deferrals.push({ taskId: item.taskId, rule: "levelPreemption", detail: item.level });
  }

  // --- the dependencyUnmet rule -------------------------------------------
  // The dependency edge as a rule in the candidate filter, and the only place
  // a predecessor is read. An item is met by a predecessor that closed AND
  // closed `pass`; a predecessor that closed `fail`, was cancelled, preempted
  // or expired has not been met, and neither has one the backlog does not hold
  // at all. Deleting this block is the unit's own negative control: B is then
  // proposed beside A and `tools/depends-on-replay.mjs` goes red.
  const dependenciesMet = new Set<TaskId>(
    state.backlog
      .filter(
        (item) =>
          item.state === "closed" &&
          Option.isSome(item.outcome) &&
          item.outcome.value === "pass"
      )
      .map((item) => item.taskId)
  );
  const firstUnmet = (item: BacklogItem): Option.Option<TaskId> => {
    for (const predecessor of item.dependsOn) {
      if (!dependenciesMet.has(predecessor)) return Option.some(predecessor);
    }
    return Option.none<TaskId>();
  };
  const dependencyBlocked = new Set<TaskId>();
  for (const item of unclaimed) {
    if (!armed.has(item.planId)) continue;
    const unmet = firstUnmet(item);
    if (Option.isNone(unmet)) continue;
    dependencyBlocked.add(item.taskId);
    deferrals.push({
      taskId: item.taskId,
      rule: "dependencyUnmet",
      detail: unmet.value
    });
  }
  // --- end of the dependencyUnmet rule -------------------------------------

  // --- the filler lane ------------------------------------------------------
  // Spec §4.4 and D-B10, in the two places the station owns. The lane's own
  // module says why each clause is here rather than in the kernel; what happens
  // here is only the wiring, and it is inert when no lane is declared.
  //
  // ALTERNATION IS A FILTER AND NOT AN ORDERING. At most one filler source is
  // releasable in a pass — the one whose turn the round-robin names — so the
  // other's items are deferred with the turn named. Ordering the filler bucket
  // instead would let a value density that favours one source undo the
  // alternation the moment both sources had work.
  //
  // PROMOTION IS A VALUE AND NOT A STORE WRITE. An aged filler is proposed at
  // the promotion level for this evaluation only; the item keeps the level it
  // was armed at, and "for one release" is the Factory resetting the counter
  // when it hands the item out.
  const lane = state.filler;
  const fillers = fillerTaskIds(state.backlog, lane);
  const preemptibleFillers = preemptibleHolders(state.backlog, lane);
  const turn = fillerTurn(state.backlog, lane, fillerSources(state.levels, lane));

  const alternating = unclaimed.filter((item) => {
    if (lane === undefined || item.level !== lane.level) return true;
    if (Option.isNone(turn) || turn.value === item.family) return true;
    deferrals.push({
      taskId: item.taskId,
      rule: "fillerAlternation",
      detail: turn.value
    });
    return false;
  });

  const candidates = promoteAgedFillers(
    alternating.filter(
      (item) => armed.has(item.planId) && !dependencyBlocked.has(item.taskId)
    ),
    lane
  );
  const conwipContext: ConwipContext = { caps: state.caps, wip: state.wip };

  // Envelopes are threaded through the pass so two children of one parent cannot
  // both be granted against the same headroom.
  let envelopes: ReadonlyArray<Envelope> = incoming.envelopes;

  // Metered spend accumulates within the pass for the same reason.
  let spent = incoming.spent;

  // Row holders accumulate so a single pass cannot over-release one row. Rows
  // belong to one executor, so this starts empty for each reading.
  const takenHolders = new Map<RowName, number>();
  const claimed = new Set<TaskId>(incoming.claimed);

  for (const bucket of bucketByLevel(candidates, state.levels)) {
    if (bucket.items.length === 0) continue;

    const wipByNamespace = [
      ...new Set(bucket.items.map((item) => item.namespace))
    ].map(
      (namespace) =>
        [
          namespace,
          state.wip
            .filter((count) => count.namespace === namespace && count.level === bucket.level.name)
            .reduce((sum, count) => sum + count.count, 0)
        ] as const
    );

    // Resolve a preference order once per item, so the sort key and the admit
    // agree and so the order does not depend on how much headroom happens to
    // exist. Which member of the order is taken is decided at the gate.
    const preferences = new Map<TaskId, ReadonlyArray<RoutingCandidate>>();

    for (const item of bucket.items) {
      const routed = preferenceOrder(item, state, reading, certificate, metered);
      if (routed.order.length === 0) {
        deferrals.push({ taskId: item.taskId, rule: "localFirst", detail: item.needs });
        continue;
      }

      // Escalation is licensed by the router, not by congestion — unless the
      // policy says a run of deferrals has made the congestion a standing fact.
      // Both halves are data: the filter itself, and the run length.
      const licensedByCongestion =
        state.policy.congestion._tag === "EscalateAfter" &&
        item.deferrals >= state.policy.congestion.deferrals;
      const dropMetered =
        state.policy.dropMeteredWhenFreePreferred &&
        !routed.licensed &&
        !licensedByCongestion;

      preferences.set(
        item.taskId,
        dropMetered
          ? routed.order.filter((candidate) => !candidate.routing.metered)
          : routed.order
      );
    }

    const routable = bucket.items.filter((item) => preferences.has(item.taskId));

    const keyOf = (item: BacklogItem): number => {
      const rows = preferences.get(item.taskId)?.[0]?.rows ?? [];
      const density = valueDensity(item, rows, metered, state.prices);
      // The reference is the class scale from the estimate table's main effects,
      // not the item's own median: comparing an item against itself makes the
      // term a constant and the regime flip a no-op.
      const timeWeighted = density.rows.some(
        (row) => !metered.includes(row.row) && row.cost > 0
      );
      const term = lengthTerm(
        reading.regime,
        item.estimate,
        state.estimates.mainEffect.medianSeconds,
        timeWeighted,
        state.policy.lengthExponent
      );
      return applyLengthTerm(density.value, term);
    };

    const ordered = orderWithinLevel(routable, keyOf);
    const fair = roundRobinByNamespace(ordered, state.namespaces, wipByNamespace);
    const batched = applyBatching(fair, state);

    for (const item of batched) {
      const order = preferences.get(item.taskId);
      if (order === undefined) continue;

      const caps = conwipVerdict(item, conwipContext, accepted);
      if (!caps.admissible) {
        const detail = Option.match(caps.binding, {
          onNone: () => "cap",
          onSome: (cap) => `${cap.axis}:${cap.subject}`
        });
        deferrals.push({ taskId: item.taskId, rule: "conwip", detail });
        continue;
      }

      // Walk the preference order and take the first member that clears every
      // per-member gate. The first candidate's refusal is the one reported, so a
      // deferral names the rule that stopped the item's preferred routing rather
      // than the last one tried.
      let chosen = Option.none<RoutingCandidate>();
      let chosenConsumption = 0;
      let firstRefusal = Option.none<Deferral>();

      for (const candidate of order) {
        const refuse = (rule: Deferral["rule"], detail: string): void => {
          if (Option.isNone(firstRefusal)) {
            firstRefusal = Option.some({ taskId: item.taskId, rule, detail });
          }
        };

        const density = valueDensity(item, candidate.rows, metered, state.prices);
        if (density.unpriced.length > 0) {
          refuse("valueDensity", `unpriced:${density.unpriced.join(",")}`);
          continue;
        }
        if (!coversBidPrice(density)) {
          refuse(
            "valueDensity",
            Option.match(bindingRow(density), {
              onNone: () => "bidPrice",
              onSome: (row) => row
            })
          );
          continue;
        }

        if (reading.freshness === "stale" && candidate.routing.metered) {
          refuse("oracleFreshness", "stale");
          continue;
        }

        // The capacity gate. A row this executor does not declare, a row at
        // capacity, or a stop signal all defer; none of them admits. The first
        // of those is also how an item that needs a seat or a device row falls
        // out on an executor that has neither: it is the ordinary rule, not a
        // special case.
        let blockedRow = Option.none<RowName>();
        for (const request of candidate.rows) {
          const measured = rowReading(reading, request.row);
          if (Option.isNone(measured)) {
            blockedRow = Option.some(request.row);
            break;
          }

          const alreadyTaken = takenHolders.get(request.row) ?? 0;
          const headroom = rowHeadroom(measured.value) - alreadyTaken;

          // The filler lane's preemption (spec §4.4 clause 1). A row the
          // station's OWN filler items have filled is not a closed door to a
          // non-filler item: the station proposes against it, the door answers
          // `NotYet {preempt}` and starts the holder's yield, and the higher
          // item is admitted on the next probe. So the row's headroom is widened
          // by the filler holders the station released onto it, and only while
          // the reading agrees the row is saturated — a STOP that is not
          // saturation (a shut window) is left binding, and a refusal the door
          // then makes is one NotYet round trip and never a run.
          //
          // It is never widened for a filler item: a filler does not preempt a
          // filler, and `fillers` is read before the promotion rewrite so a
          // promoted filler cannot either.
          const preemptible =
            lane !== undefined &&
            request.row === lane.row &&
            !fillers.has(item.taskId) &&
            headroom < request.holders &&
            measured.value.holders >= measured.value.capacity
              ? Math.min(preemptibleFillers, request.holders - headroom)
              : 0;

          // SLOW is a refusal at the kernel's door.  Proposing against it would
          // only create a NotYet round trip, so the lake treats it as STOP.
          if (measured.value.signal !== "GO" && preemptible === 0) {
            blockedRow = Option.some(request.row);
            break;
          }
          if (headroom + preemptible < request.holders) {
            blockedRow = Option.some(request.row);
            break;
          }
        }
        if (Option.isSome(blockedRow)) {
          refuse("capacityRow", blockedRow.value);
          continue;
        }

        const meteredConsumption = candidate.rows
          .filter((request) => metered.includes(request.row))
          .reduce((sum, request) => sum + request.consumption, 0);

        if (meteredConsumption > 0 && !fitsPaceLine(pace, spent, meteredConsumption)) {
          refuse("paceLine", "windowBudget");
          continue;
        }

        chosen = Option.some(candidate);
        chosenConsumption = meteredConsumption;
        break;
      }

      if (Option.isNone(chosen)) {
        deferrals.push(
          Option.getOrElse(firstRefusal, () => ({
            taskId: item.taskId,
            rule: "localFirst" as const,
            detail: item.needs
          }))
        );
        continue;
      }

      const candidate = chosen.value;

      // A recursive child debits its parent's envelope, and can only reduce it.
      let childEnvelope = chosenConsumption;
      if (Option.isSome(item.envelopeParent)) {
        const parent = envelopeOf(envelopes, item.envelopeParent.value);
        if (Option.isNone(parent)) {
          deferrals.push({ taskId: item.taskId, rule: "envelope", detail: "unknownParent" });
          continue;
        }
        const grant = grantChild(parent.value, item.taskId, chosenConsumption);
        if (grant._tag === "Refused") {
          deferrals.push({
            taskId: item.taskId,
            rule: "envelope",
            detail: `shortfall:${grant.shortfall}`
          });
          continue;
        }
        envelopes = [
          ...envelopes.filter((envelope) => envelope.owner !== grant.parent.owner),
          grant.parent,
          grant.child
        ];
        childEnvelope = grant.child.allocated;
      }

      const cap = runtimeCap(
        item.estimate,
        state.policy.runtimeFloorSeconds,
        state.policy.runtimeCeilingSeconds
      );

      const prior = state.priors?.get(item.taskId);
      admits.push({
        taskId: item.taskId,
        planId: item.planId,
        executor: reading.executor,
        briefHash: item.briefHash,
        // The authority, taken from the armed plan row rather than from the
        // item, so a proposal cites the arming act itself.
        planHash: armed.get(item.planId) ?? item.planHash,
        rows: candidate.rows,
        member: candidate.routing.member,
        evidence: item.evidence,
        dedupKey: item.dedupKey,
        level: item.level,
        runtimeMaxSec: cap.seconds,
        yieldAtMedianMultiple: state.policy.medianMultiple,
        envelope: childEnvelope,
        // The prior this release is a bet on, carried verbatim from the
        // selection pass. `...(x ? {prior: x} : {})` and not `prior: x ?? undefined`
        // because the key is optional on the wire: an item with no selection
        // behind it carries no `prior` key at all rather than a null one.
        ...(prior === undefined ? {} : { prior })
      });

      accepted.push(item);
      claimed.add(item.taskId);
      spent += chosenConsumption;
      for (const request of candidate.rows) {
        takenHolders.set(request.row, (takenHolders.get(request.row) ?? 0) + request.holders);
      }
    }
  }

  return {
    admits,
    deferrals,
    pace,
    carry: { claimed, accepted, envelopes, spent }
  };
};

/**
 * Evaluates one release pass against one capacity reading.
 *
 * @param state - Everything the Factory object holds.
 * @param reading - Exactly one capacity reading from exactly one executor.
 * @returns The proposals, the named deferrals, the andons, the pace line and the
 *   deadline certificate.
 */
export const evaluateRelease = (
  state: ReleaseState,
  reading: CapacityReading
): ReleaseDecision => {
  const certificate = deadlineCertificate(datedSubset(state.backlog));
  const pass = releasePass(state, reading, certificate, emptyCarry(state));
  return {
    admits: pass.admits,
    deferrals: pass.deferrals,
    andons: bufferAndons(state.inventory, state.buffers),
    pace: pass.pace,
    certificate
  };
};

/**
 * Evaluates the release rule against several executors, in the caller's order.
 *
 * The fold is what makes the plural case honest. Each pass sees only the items
 * no earlier pass claimed, so one item is proposed to at most one door; the
 * accepted set carries forward, so the work-in-process caps count the whole fold
 * rather than each executor separately; the envelopes carry forward, so two
 * children of one parent cannot be granted twice against the same headroom; and
 * the metered spend carries forward, which can only tighten a later pace line.
 *
 * A deferral is reported only for an item that no executor took. An item the
 * local rail could not fit and a cloud-side executor ran was not deferred, and
 * counting it as deferred would inflate exactly the number the congestion policy
 * reads.
 *
 * @param state - Everything the Factory object holds.
 * @param readings - One reading per reachable executor. An executor that has
 *   not reported simply is not here: its work waits, which is the same outcome
 *   as a full row and needs no separate rule. Order is the caller's and the
 *   result is deterministic in it.
 * @returns The proposals stamped per executor, the deferrals no executor
 *   resolved, the andons, each executor's pace line, and the certificate.
 */
export const evaluateReleaseAcross = (
  state: ReleaseState,
  readings: ReadonlyArray<CapacityReading>
): MultiReleaseDecision => {
  const certificate = deadlineCertificate(datedSubset(state.backlog));
  const admits: Array<Admit> = [];
  const paces: Array<readonly [CapacityReading["executor"], PaceLine]> = [];
  // Keyed by task, so the reason kept is the one the first executor gave and a
  // later pass cannot overwrite it with a less informative refusal.
  const refusals = new Map<TaskId, Deferral>();

  let carry = emptyCarry(state);
  for (const reading of readings) {
    const pass = releasePass(state, reading, certificate, carry);
    admits.push(...pass.admits);
    paces.push([reading.executor, pass.pace]);
    for (const deferral of pass.deferrals) {
      if (!refusals.has(deferral.taskId)) refusals.set(deferral.taskId, deferral);
    }
    carry = pass.carry;
  }

  const deferrals: Array<Deferral> = [];
  for (const [taskId, deferral] of refusals) {
    if (carry.claimed.has(taskId)) continue;
    deferrals.push(deferral);
  }

  return {
    admits,
    deferrals,
    andons: bufferAndons(state.inventory, state.buffers),
    paces,
    certificate
  };
};
