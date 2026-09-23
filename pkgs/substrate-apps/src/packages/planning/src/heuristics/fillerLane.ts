/**
 * The filler lane: the lowest level, preemptive, and never starved.
 *
 * Spec §4.4 is the executor's side of Model E and this module is the station's
 * side of the same contract. Three sentences of it are code here and the rest is
 * the kernel's:
 *
 * 1. **The filler is the lowest level in the authored `levels` document, and it
 *    is preemptive.** A row saturated only by filler holders is not a closed
 *    door to a non-filler item: the station proposes against it, the executor's
 *    door answers `NotYet {preempt}` and starts the holder's yield, and the
 *    higher item is admitted on the next probe. `preemptibleHolders` below is
 *    the count that licenses that proposal, and it counts the station's OWN
 *    filler holders — never a holder it did not release.
 * 2. **It never starves** (D-B10, TL-10): a filler item passed over by ten
 *    non-filler releases on its row is proposed at level 1 for one release.
 *    `agedIntoPromotion` is that clause; the counter it reads is
 *    `BacklogItem.passedOver`, which the Factory maintains as it hands out.
 * 3. **The two fillers alternate by round-robin** (D-B10). The two fillers are
 *    the two goal families the filler level declares, in the order the levels
 *    document declares them, and `fillerTurn` names whose turn it is. The rule
 *    is a filter and not an ordering: at most one filler source is releasable in
 *    a pass, so alternation cannot be undone by a value density that happens to
 *    favour one source.
 *
 * NOTHING HERE IS DERIVED. The lane's row, its level, the promotion number and
 * the abort number are data on `ReleaseState.filler`, exactly as a `ConwipCap`
 * is data: Little's law never derives a cap and no throughput objective derives
 * an anti-starvation number. D-B10 is where these numbers come from and
 * `docs/levels.md` is the document that carries them.
 *
 * THE TURN IS DERIVED FROM THE BACKLOG AND NOT KEPT. A round-robin cursor held
 * beside the state would be a second source of truth that a restart loses; the
 * backlog already records how many times each filler item has been released
 * (`attempt` plus whether it is out right now), so the turn is a function of
 * state and survives every restart the snapshot survives.
 */
import { Option } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import type { FamilyName, LevelName, RowName, TaskId } from "../schema/ids.ts";
import { levelByName, type LevelList } from "../schema/levels.ts";

/**
 * The filler lane, as data.
 *
 * Absent from a `ReleaseState` the lane does not exist and every rule in this
 * module is inert, which is what lets a floor that declares no filler level
 * behave exactly as it did before this module was written.
 */
export interface FillerLane {
  /** The name of the filler level in the authored level list; the lowest one. */
  readonly level: LevelName;
  /**
   * The row the fillers run on.
   *
   * D-B10 names `gpu-coordinator`. It is written here rather than inferred from
   * the catalog because preemption is a statement about one row's holders, and
   * inferring the row from a routing would make the preemption rule depend on
   * which member the router happened to pick.
   */
  readonly row: RowName;
  /** How many non-filler releases on `row` promote a passed-over filler (D-B10: 10). */
  readonly promoteAfter: number;
  /** The level a promoted filler is proposed at for one release (D-B10: level 1). */
  readonly promoteTo: LevelName;
  /** Consecutive crashes that trip the lane's named abort (D-B10: 2). */
  readonly abortOnConsecutiveCrash: number;
}

/**
 * The two fillers, in the order the levels document declares them.
 *
 * They are the filler level's goal families and nothing else: `Level.families`
 * is already "the goal families this level contains", so the two fillers are
 * authored where every other level's families are authored, and adding a third
 * filler is a data edit in the same table.
 *
 * @param levels - The authored level list.
 * @param lane - The lane, or `undefined` when the floor declares none.
 * @returns The filler families in declared order, empty when the lane's level is
 *   not declared — an authoring error that must not be papered over with a
 *   default.
 */
export const fillerSources = (
  levels: LevelList,
  lane: FillerLane | undefined
): ReadonlyArray<FamilyName> => {
  if (lane === undefined) return [];
  return Option.match(levelByName(levels, lane.level), {
    onNone: () => [] as ReadonlyArray<FamilyName>,
    onSome: (level) => level.families
  });
};

/** The task ids the backlog holds at the filler level, before any promotion. */
export const fillerTaskIds = (
  backlog: ReadonlyArray<BacklogItem>,
  lane: FillerLane | undefined
): ReadonlySet<TaskId> => {
  const ids = new Set<TaskId>();
  if (lane === undefined) return ids;
  for (const item of backlog) {
    if (item.level === lane.level) ids.add(item.taskId);
  }
  return ids;
};

/**
 * How many times one item has been released, counting the release it is out on.
 *
 * `attempt` counts runs that ended badly and started again, so an item on its
 * second attempt has been released once already; an item that is out right now
 * has been released once more than that. Reading the count this way is what
 * makes the round-robin survive a preemption: a filler returned to the backlog
 * by a `preempted` verdict still carries the release it had.
 */
const releaseCount = (item: BacklogItem): number =>
  item.attempt - 1 + (item.state === "unclaimed" ? 0 : 1);

/**
 * Whose turn it is among the fillers.
 *
 * Round-robin by release count, ties broken by the declared order, so the first
 * filler in the levels document goes first and the two then alternate for as
 * long as both have work. A source with no items left simply never wins, which
 * is what makes the rule degrade to "the remaining filler runs" rather than to a
 * stall.
 *
 * @param backlog - The whole backlog; only filler-level items are read.
 * @param lane - The lane.
 * @param sources - The filler families, in declared order.
 * @returns The family whose turn it is, or `None` when no filler source has an
 *   item that could be released.
 */
export const fillerTurn = (
  backlog: ReadonlyArray<BacklogItem>,
  lane: FillerLane | undefined,
  sources: ReadonlyArray<FamilyName>
): Option.Option<FamilyName> => {
  if (lane === undefined || sources.length === 0) return Option.none();

  const releases = new Map<FamilyName, number>();
  const waiting = new Set<FamilyName>();
  for (const source of sources) releases.set(source, 0);
  for (const item of backlog) {
    if (item.level !== lane.level) continue;
    if (!releases.has(item.family)) continue;
    releases.set(item.family, (releases.get(item.family) ?? 0) + releaseCount(item));
    if (item.state === "unclaimed") waiting.add(item.family);
  }

  let turn = Option.none<FamilyName>();
  let fewest = Number.POSITIVE_INFINITY;
  for (const source of sources) {
    if (!waiting.has(source)) continue;
    const count = releases.get(source) ?? 0;
    if (count < fewest) {
      fewest = count;
      turn = Option.some(source);
    }
  }
  return turn;
};

/**
 * Whether one filler item has aged into its promotion.
 *
 * D-B10: *"a filler item that has been passed over by 10 non-filler releases on
 * its row is proposed at level 1 for one release"*. The comparison is `>=` and
 * not `==` because the counter moves by whole passes: a pass that released two
 * non-filler items onto the lane's row steps the counter by two, and a filler
 * that jumped the number must not be left un-promoted for ever.
 */
export const agedIntoPromotion = (
  item: BacklogItem,
  lane: FillerLane | undefined
): boolean =>
  lane !== undefined && item.level === lane.level && item.passedOver >= lane.promoteAfter;

/**
 * Rewrites an aged filler's level to the promotion level, for this pass only.
 *
 * The rewrite is a value and never a store write: the item in the backlog keeps
 * the level it was armed at, and the promotion lasts exactly as long as the
 * evaluation that produced it. What makes it "for one release" is the Factory
 * resetting `passedOver` when the item is handed out.
 *
 * @param candidates - The pass's candidates.
 * @param lane - The lane.
 * @returns The same candidates with aged fillers carrying `lane.promoteTo`.
 */
export const promoteAgedFillers = (
  candidates: ReadonlyArray<BacklogItem>,
  lane: FillerLane | undefined
): ReadonlyArray<BacklogItem> => {
  if (lane === undefined) return candidates;
  return candidates.map((item) =>
    agedIntoPromotion(item, lane) ? { ...item, level: lane.promoteTo } : item
  );
};

/**
 * How many of the lane's row's holders are the station's own filler items.
 *
 * Released and in-flight both count. A released item has an admit in flight the
 * door has not answered; if the door accepted it, it holds the row, and a
 * proposal that assumed otherwise would over-release. The number is a floor on
 * what a preemption could free and never a claim about what the door will do —
 * the door answers, and the answer is the authority (`apps/uplink/src/gate.mjs`).
 */
export const preemptibleHolders = (
  backlog: ReadonlyArray<BacklogItem>,
  lane: FillerLane | undefined
): number => {
  if (lane === undefined) return 0;
  let holders = 0;
  for (const item of backlog) {
    if (item.level !== lane.level) continue;
    if (item.state === "released" || item.state === "inflight") holders += 1;
  }
  return holders;
};

/**
 * How far one pass's admits move the filler lane's age counter.
 *
 * D-B10 counts *"non-filler releases on its row"*, so an admit counts when it is
 * not a filler item and when its row set names the lane's row. An admit onto
 * another row did not pass the filler over: the filler could not have run there.
 *
 * @param admits - The pass's proposals, each with the row set it consumes.
 * @param fillers - The task ids that are filler items, before promotion.
 * @param lane - The lane.
 */
export const passedOverBy = (
  admits: ReadonlyArray<{
    readonly taskId: TaskId;
    readonly rows: ReadonlyArray<{ readonly row: RowName }>;
  }>,
  fillers: ReadonlySet<TaskId>,
  lane: FillerLane | undefined
): number => {
  if (lane === undefined) return 0;
  let passes = 0;
  for (const admit of admits) {
    if (fillers.has(admit.taskId)) continue;
    if (admit.rows.some((request) => request.row === lane.row)) passes += 1;
  }
  return passes;
};
