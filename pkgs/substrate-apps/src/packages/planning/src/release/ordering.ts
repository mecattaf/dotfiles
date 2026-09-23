/**
 * The lexicographic hierarchy, as an ordering.
 *
 * Volume II Part I encodes Tom's priorities as goal programming with preemptive
 * levels: an ordered list of levels, each naming the goal families it contains,
 * such that no amount of level-two value buys a level-one slot. Within a level,
 * value density orders. That "within" is the whole reason two rules can coexist:
 * the hierarchy is not a weight, and no arithmetic combines an ordinal with a
 * density.
 *
 * The list is a hashed, authored document. Re-ordering it is the strategic act
 * the queue expects most often, and it must remain a data edit and never a
 * deploy. It is also the permanently evolving part of the design: skill
 * authoring, upstream contribution and local fine-tuning each earn a level, or
 * they are dominated by every executable item under any throughput objective —
 * the exploitation trap operating mechanically rather than culturally.
 */
import { Option } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import { levelByName, orderedLevels, type Level, type LevelList } from "../schema/levels.ts";

/** One level's candidates, in preemptive order. */
interface LevelBucket {
  /** The level. */
  readonly level: Level;
  /** Its candidates, in the order they arrived. */
  readonly items: ReadonlyArray<BacklogItem>;
}

/**
 * Partitions candidates into preemptive levels, strongest first.
 *
 * Items naming an undeclared level are dropped rather than treated as lowest
 * priority, because a level the list does not declare is an authoring error and
 * silently demoting it would hide the error behind a plausible behaviour.
 *
 * @param items - The candidates.
 * @param levels - The authored level list.
 * @returns One bucket per declared level, in ordinal order, including empty
 *   ones so a caller can see which levels are starved.
 */
export const bucketByLevel = (
  items: ReadonlyArray<BacklogItem>,
  levels: LevelList
): ReadonlyArray<LevelBucket> =>
  orderedLevels(levels).map((level) => ({
    level,
    items: items.filter((item) => item.level === level.name)
  }));

/**
 * Items naming a level the list does not declare.
 *
 * Returned separately so the caller can defer them with a named reason rather
 * than losing them.
 */
export const undeclaredLevelItems = (
  items: ReadonlyArray<BacklogItem>,
  levels: LevelList
): ReadonlyArray<BacklogItem> =>
  items.filter((item) => Option.isNone(levelByName(levels, item.level)));

/**
 * Orders within a level by a computed sort key, then rank, then task id.
 *
 * The tiebreak chain is total and deterministic, which is what makes a recorded
 * replay assert an exact admit sequence rather than a set.
 *
 * @param items - One level's candidates.
 * @param keyOf - The sort key, normally value density with the length term
 *   applied. Higher is stronger.
 * @returns The ordered candidates.
 */
export const orderWithinLevel = (
  items: ReadonlyArray<BacklogItem>,
  keyOf: (item: BacklogItem) => number
): ReadonlyArray<BacklogItem> =>
  [...items].sort((left, right) => {
    const leftKey = keyOf(left);
    const rightKey = keyOf(right);
    if (leftKey !== rightKey) return rightKey - leftKey;
    if (left.rank !== right.rank) return left.rank - right.rank;
    return left.taskId < right.taskId ? -1 : left.taskId > right.taskId ? 1 : 0;
  });
