/**
 * The lexicographic priority hierarchy.
 *
 * Volume II Part I encodes Tom's priorities as goal programming with preemptive
 * levels: an ordered list such that no amount of level-two value buys a
 * level-one slot; within a level, value density orders. The list is a hashed,
 * authored document in the Factory object, and re-ordering it is a data edit and
 * never a deploy. It is also the permanently evolving part of the design: skill
 * authoring, upstream contribution and local fine-tuning each get a level, or
 * they starve under any throughput objective.
 */
import { Option, Schema } from "effect";
import { FamilyName, LevelName } from "./ids.ts";

/** One preemptive level. */
export const Level = Schema.Struct({
  /** The level's name. */
  name: LevelName,
  /**
   * Position in the hierarchy; lower is stronger.
   *
   * Ordinals are compared and never arithmetically combined, because a
   * preemptive level is not a weight.
   */
  ordinal: Schema.Int,
  /** The goal families this level contains. */
  families: Schema.Array(FamilyName),
  /**
   * The level's CONWIP cap: how much work in progress this level may hold at
   * once, across every namespace and family in it.
   */
  wipCap: Schema.Int
});
/** One preemptive level. */
export type Level = typeof Level.Type;

/** The authored level list. */
export const LevelList = Schema.Struct({
  /** Hash over the authored document, so a release can cite the hierarchy it obeyed. */
  hash: Schema.String,
  /** The levels, which the engine sorts by ordinal rather than trusting input order. */
  levels: Schema.Array(Level)
});
/** The authored level list. */
export type LevelList = typeof LevelList.Type;

/**
 * Looks up one level.
 *
 * @returns the level, or `None` when an item names a level the list does not
 *   declare, which makes the item unreleasable rather than lowest priority.
 */
export const levelByName = (list: LevelList, name: LevelName): Option.Option<Level> => {
  for (const level of list.levels) {
    if (level.name === name) return Option.some(level);
  }
  return Option.none();
};

/** The levels in preemptive order, strongest first. */
export const orderedLevels = (list: LevelList): ReadonlyArray<Level> =>
  [...list.levels].sort((left, right) => left.ordinal - right.ordinal);
