/**
 * Estimates over the `(model x harness x class)` matrix.
 *
 * Recorded at pair granularity always; estimated with shrinkage until cells
 * fill (Volume II Part III sections 1 and 9). Every field here arrives from the
 * collector's projections. Nothing in this package estimates from its own
 * history, so a cell with three observations cannot masquerade as knowledge:
 * `shrinkageWeight` says how much of the estimate is actually data.
 */
import { Schema } from "effect";
import { AgentKind, ClassName, ModelId, Seconds, UnitInterval, Weight } from "./ids.ts";

/**
 * One cell's estimate.
 *
 * Service times are quantiles rather than means because measured `c_s^2` is
 * around four, so no two-parameter family fits and the tails are policy
 * problems rather than forecast problems.
 */
export const Estimate = Schema.Struct({
  /** Median service interval for the class, the base of the kill-and-redispatch multiple. */
  medianSeconds: Seconds,
  /** The p80 service interval. */
  p80Seconds: Seconds,
  /** The p99 service interval, which is where `runtimeMaxSec` belongs. */
  p99Seconds: Seconds,
  /** Expected consumption at the p80 protection level; zero on a free lane. */
  p80Consumption: Weight,
  /** First-pass yield, `P(verdict = pass)`. */
  yieldRate: UnitInterval,
  /** How many closed observations back this cell. */
  observations: Schema.Int,
  /**
   * How much of this estimate is the cell's own data rather than the main
   * effects it was shrunk toward. One is fully unpooled.
   */
  shrinkageWeight: UnitInterval
});
/** One cell's estimate over the `(model x harness x class)` matrix. */
export type Estimate = typeof Estimate.Type;

/** One cell of the matrix, keyed by the pair and the class. */
const EstimateCell = Schema.Struct({
  /** The mounted model. */
  model: ModelId,
  /** The herdr agent kind. */
  agentKind: AgentKind,
  /** The capability class. */
  taskClass: ClassName,
  /** The estimate itself. */
  estimate: Estimate
});
/** One cell of the estimate matrix. */
type EstimateCell = typeof EstimateCell.Type;

/** The whole matrix as the collector publishes it. */
export const EstimateTable = Schema.Struct({
  /** The cells, recorded at pair granularity. */
  cells: Schema.Array(EstimateCell),
  /** The main effects a sparse cell is shrunk toward. */
  mainEffect: Estimate
});
/** The whole estimate matrix as the collector publishes it. */
export type EstimateTable = typeof EstimateTable.Type;

/**
 * The estimate for one member on one class.
 *
 * @returns the cell's estimate, or the main effects when the cell is empty.
 *   An empty cell is not an error: it is the case shrinkage exists for.
 */
export const estimateFor = (
  table: EstimateTable,
  member: { readonly model: ModelId; readonly agentKind: AgentKind },
  taskClass: ClassName
): Estimate => {
  for (const cell of table.cells) {
    if (
      cell.model === member.model &&
      cell.agentKind === member.agentKind &&
      cell.taskClass === taskClass
    ) {
      return cell.estimate;
    }
  }
  return table.mainEffect;
};
