/**
 * The scoped buffer under a base-stock policy, and the andon that replenishes it.
 *
 * Volume I chapter 10 maps drum-buffer-rope without residue. The drum is the
 * human's scoping cadence, the plant's true beat. The buffer is inventory of
 * scoped-ready work standing before the machines, sized so the factory never
 * starves during the drum's silent stretches. The rope ties release to the
 * buffer, and it already exists: it is the admission door plus the doctrine that
 * tally never originates intent. The buffer was the missing managed object, and
 * this module is its monitor.
 *
 * Section 10.2 gives the policy. Run each family's scoped inventory under
 * `(s, S)`: when it falls below the reorder point, request scoping up to the
 * order-up-to level. The reorder point covers expected machine consumption over
 * the drum's replenishment lead time — the realistic gap until the human next
 * sits down to scope — plus safety stock scaled to consumption variance. The
 * spread between the two levels reflects the economics of scoping in batches,
 * which is setup-heavy: several related items scoped in one sitting cost far
 * less of the constraint each than the same items scattered.
 *
 * Section 10.3 is why this is per family and not global. Scoped work rots, and
 * it rots at different rates: a low-churn family keeps for a long time, a
 * high-churn one decays against upstream movement. High holding cost therefore
 * wants a small buffer replenished near release; low holding cost can carry a
 * deep buffer cheaply, which is exactly what makes those families good sweep
 * fodder.
 *
 * The blueprint's section 1.3(4) states the degenerate geometry: nothing is
 * upstream of the human, so the buffer sits downstream of the drum and the rope
 * runs backward as a replenishment signal. This andon is that signal. It is the
 * only output of the engine addressed to a human rather than to a kernel, and it
 * is a notification and not a nag.
 */
import type { Andon } from "../schema/admit.ts";
import type { FamilyName } from "../schema/ids.ts";
import type { BufferPolicy } from "../schema/namespace.ts";

/** Scoped-ready inventory on hand for one family. */
export interface FamilyInventory {
  /** The family. */
  readonly family: FamilyName;
  /** How many unclaimed, armed, scoped-ready items it holds. */
  readonly onHand: number;
}

/**
 * Raises an andon for every family below its reorder point.
 *
 * @param inventories - Scoped-ready counts per family.
 * @param policies - The declared `(s, S)` policy per family.
 * @returns One andon per family below its reorder point, naming the family and
 *   the shortfall that brings it to the order-up-to level. Families with no
 *   declared policy raise nothing: an undeclared buffer is not an empty one.
 */
export const bufferAndons = (
  inventories: ReadonlyArray<FamilyInventory>,
  policies: ReadonlyArray<BufferPolicy>
): ReadonlyArray<Andon> => {
  const andons: Array<Andon> = [];
  for (const policy of policies) {
    const inventory = inventories.find((entry) => entry.family === policy.family);
    if (inventory === undefined) continue;
    if (inventory.onHand >= policy.reorderPoint) continue;
    andons.push({
      family: policy.family,
      onHand: inventory.onHand,
      shortfall: Math.max(0, policy.orderUpTo - inventory.onHand)
    });
  }
  return andons;
};
