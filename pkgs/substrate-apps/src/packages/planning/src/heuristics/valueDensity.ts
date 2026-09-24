/**
 * Value density: the release sort key.
 *
 * `v_j * yhat_jm / sum_r pi_r * a_jr` — value times first-pass yield over
 * bid-price-weighted consumption. Volume I section 7.3 gives the admission form:
 * accept a job if and only if its certainty-equivalent value covers the sum of
 * the bid prices of the resources it consumes. Volume II Part III section 2
 * gives the sort form and its two generalisations of Smith's rule: the numerator
 * replaces the raw weight with a certainty equivalent, and the denominator
 * replaces processing time with consumption of the binding resource. When the
 * binding resource is time on one machine this reduces to Smith's rule; when it
 * is a budget it reduces to Dantzig's greedy for the fractional knapsack, which
 * is bid-price control in disguise.
 *
 * The denominator is where the earlier form was wrong. `gamma_m * c_jm +
 * epsilon` degenerates on a free lane to a constant times value, so the sort
 * silently reverts to pure value ordering exactly when the local lanes are
 * saturated and the binding resource is lane-hours. The `epsilon` is a
 * placeholder for `pi_slot * tau`, and replacing it makes the free-lane sort
 * correct under load.
 *
 * The breakdown is returned rather than a bare scalar, so a deferral can name
 * the row that priced an item out.
 */
import { Option } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import type { Estimate } from "../schema/estimate.ts";
import type { RowName } from "../schema/ids.ts";
import { priceOf, type PriceVector } from "../schema/prices.ts";
import type { RowSet } from "../schema/rows.ts";

/** One row's contribution to the denominator. */
interface RowCost {
  /** The row consumed. */
  readonly row: RowName;
  /** Its bid price, `pi_r`. */
  readonly price: number;
  /** The job's consumption of it, `a_jr`. */
  readonly consumption: number;
  /** Their product. */
  readonly cost: number;
}

/** A value density, with the terms that produced it. */
interface Density {
  /** `v_j * yhat_jm`: value discounted by first-pass yield. */
  readonly numerator: number;
  /** `sum_r pi_r * a_jr`: bid-price-weighted consumption. */
  readonly denominator: number;
  /** The ratio, or positive infinity when every consumed row is priced at zero. */
  readonly value: number;
  /** Per-row breakdown, so a deferral can name the binding row. */
  readonly rows: ReadonlyArray<RowCost>;
  /**
   * Rows the price vector does not price.
   *
   * An unpriced row is never treated as free: the evaluator defers rather than
   * admitting against a price it does not have.
   */
  readonly unpriced: ReadonlyArray<RowName>;
}

/**
 * Consumption of one row, as the denominator weights it.
 *
 * A budget row is charged its expected weight at the p80 protection level. A
 * position row is charged its holder count times the estimated service interval,
 * because on a busy local lane the binding resource is lane-hours and `tau` is
 * the consumption that matters.
 */
const consumptionOf = (
  request: RowSet[number],
  metered: boolean,
  estimate: Estimate
): number => (metered ? request.consumption : request.holders * estimate.p80Seconds);

/**
 * Computes an item's value density against one resolved row set.
 *
 * @param item - The candidate, carrying `v_j` and its shrunk estimate.
 * @param rows - The rows the resolved member consumes.
 * @param meteredRows - Which of those rows are metered, from the row table.
 * @param prices - The published price vector.
 * @returns The density with its numerator, denominator and per-row breakdown.
 *   An item every one of whose rows is priced at zero has infinite density,
 *   which is complementary slackness stated as code: capacity priced at zero
 *   should be consumed by anything with positive value.
 */
export const valueDensity = (
  item: BacklogItem,
  rows: RowSet,
  meteredRows: ReadonlyArray<RowName>,
  prices: PriceVector
): Density => {
  const numerator = item.value * item.estimate.yieldRate;
  const breakdown: Array<RowCost> = [];
  const unpriced: Array<RowName> = [];
  let denominator = 0;

  for (const request of rows) {
    const price = priceOf(prices, request.row);
    if (Option.isNone(price)) {
      unpriced.push(request.row);
      continue;
    }
    const consumption = consumptionOf(request, meteredRows.includes(request.row), item.estimate);
    const cost = price.value * consumption;
    denominator += cost;
    breakdown.push({ row: request.row, price: price.value, consumption, cost });
  }

  const value = denominator > 0 ? numerator / denominator : Number.POSITIVE_INFINITY;
  return { numerator, denominator, value, rows: breakdown, unpriced };
};

/**
 * The bid-price admission test.
 *
 * Volume I section 7.3: admit when certainty-equivalent value covers the bid
 * prices of what is consumed. This is the same quantity as the density crossing
 * one, stated the way the admission rule states it.
 *
 * @param density - The item's density.
 * @returns Whether value covers cost. An item with an unpriced row never passes,
 *   because a missing price is not a zero price.
 */
export const coversBidPrice = (density: Density): boolean =>
  density.unpriced.length === 0 && density.numerator >= density.denominator;

/**
 * The row that priced an item out.
 *
 * @param density - The item's density.
 * @returns The most expensive row's name, or `None` when nothing was charged.
 */
export const bindingRow = (density: Density): Option.Option<RowName> => {
  let worst: Option.Option<RowCost> = Option.none();
  for (const row of density.rows) {
    if (Option.isNone(worst) || row.cost > worst.value.cost) worst = Option.some(row);
  }
  return Option.map(worst, (row) => row.row);
};
