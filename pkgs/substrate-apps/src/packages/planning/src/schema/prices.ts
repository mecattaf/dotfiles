/**
 * The price vector: the duals of Volume I chapter 7, published as data.
 *
 * The always-on plane never solves anything. Level one solves the aggregate
 * planning LP at leisure and publishes a few dozen numbers; the engine
 * evaluates one inequality per candidate against them. Prices are carried as
 * entries rather than as a map so a deferral can name the row that priced an
 * item out.
 */
import { Option, Schema } from "effect";
import { FamilyName, RowName } from "./ids.ts";

/** The bid price of one row, `pi_r`. */
const RowPrice = Schema.Struct({
  /** The row priced. */
  row: RowName,
  /**
   * The dual.
   *
   * On a metered row this is `lambda + mu`; on a local lane it is `gamma`,
   * usually near zero, and a near-zero price is the formal statement of
   * "saturate the small lanes". Capacity priced at zero should be consumed by
   * anything with positive value.
   */
  price: Schema.Finite
});
/** The bid price of one row. */
type RowPrice = typeof RowPrice.Type;

/** The internal value of one family's work in progress, a dual of the flow balances. */
const StagePrice = Schema.Struct({
  /** The family whose work in progress is priced. */
  family: FamilyName,
  /** Holding cost per unit per window; staleness and rot, and it is real. */
  holdingCost: Schema.Finite
});
/** The internal value of one family's work in progress. */
type StagePrice = typeof StagePrice.Type;

/** The published price vector. */
export const PriceVector = Schema.Struct({
  /** Hash over the authored price document, so a decision can cite its prices. */
  hash: Schema.String,
  /** Per-row bid prices. */
  rows: Schema.Array(RowPrice),
  /**
   * The drum's price, `sigma`.
   *
   * Theory predicts this dominates every machine price by an order of
   * magnitude; that domination is what "the human is the constraint" means,
   * stated as a number. It is what a failed metered attempt actually costs,
   * which is why redundancy on a metered lane is priced against it.
   */
  drum: Schema.Finite,
  /** Per-family holding costs. */
  stage: Schema.Array(StagePrice)
});
/** The published price vector. */
export type PriceVector = typeof PriceVector.Type;

/**
 * The bid price of one row.
 *
 * @returns the price, or `None` when the vector does not price that row. An
 *   unpriced row is treated as a deferral by the evaluator, never as free.
 */
export const priceOf = (prices: PriceVector, row: RowName): Option.Option<number> => {
  for (const entry of prices.rows) {
    if (entry.row === row) return Option.some(entry.price);
  }
  return Option.none();
};
