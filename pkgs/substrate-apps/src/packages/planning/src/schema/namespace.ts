/**
 * Namespaces, their fair share, and the value vector.
 *
 * The thesis's Appendix C.2 corrects the per-repo framing: tally is already one
 * singleton daemon with per-repo content riding every job row, so what was
 * missing is namespace as a first-class dimension — a query filter, release
 * fairness, and per-namespace configuration. The value vector stays two numbers
 * per namespace and one per level, which is the smallest thing that can express
 * "what is this worth" without inviting a solver into the object.
 */
import { Option, Schema } from "effect";
import { FamilyName, MemberId, NamespaceName } from "./ids.ts";

/** One namespace's declared configuration. */
const NamespaceConfig = Schema.Struct({
  /** The namespace, which is `workspace.repo`. */
  name: NamespaceName,
  /**
   * This namespace's share of within-level work in progress.
   *
   * Unnamespaced work gets its own declared share rather than a synthesised
   * repo. Shares are relative and need not sum to one.
   */
  wipShare: Schema.Finite,
  /** Value per completed unit, `v`. Chosen by Tom; no substitute exists. */
  value: Schema.Finite,
  /**
   * Holding cost per unit per window for work sitting in this namespace.
   *
   * High-decay namespaces want small buffers replenished near release; low-decay
   * ones can carry deep buffers cheaply, which is what makes them sweep fodder.
   */
  holdingCost: Schema.Finite,
  /**
   * The member a bare node resolves to when the plan states no default.
   *
   * tally has no ambient session model, so this is the fallback under a
   * per-plan default and never a guess made at release.
   */
  defaultMember: Schema.OptionFromNullOr(MemberId)
});
/** One namespace's declared configuration. */
type NamespaceConfig = typeof NamespaceConfig.Type;

/** The namespace table. */
export const NamespaceTable = Schema.Struct({
  /** Hash over the authored document. */
  hash: Schema.String,
  /** The declared namespaces. */
  namespaces: Schema.Array(NamespaceConfig)
});
/** The namespace table. */
export type NamespaceTable = typeof NamespaceTable.Type;

/**
 * Looks up one namespace's configuration.
 *
 * @returns the configuration, or `None` when the namespace is undeclared, which
 *   defers its items rather than releasing them at an invented share.
 */
export const namespaceByName = (
  table: NamespaceTable,
  name: NamespaceName
): Option.Option<NamespaceConfig> => {
  for (const config of table.namespaces) {
    if (config.name === name) return Option.some(config);
  }
  return Option.none();
};

/**
 * A family's base-stock policy over scoped-ready inventory.
 *
 * Volume I section 10.2: below the reorder point the factory requests scoping,
 * up to the order-up-to level. Sizing is classical and by family, because
 * holding cost differs sharply between a scoped dotfiles task and a scoped
 * Chromium task.
 */
export const BufferPolicy = Schema.Struct({
  /** The family this policy governs. */
  family: FamilyName,
  /** The reorder point `s`: below this, the andon fires. */
  reorderPoint: Schema.Int,
  /** The order-up-to level `S`: the shortfall is measured against this. */
  orderUpTo: Schema.Int
});
/** A family's base-stock policy over scoped-ready inventory. */
export type BufferPolicy = typeof BufferPolicy.Type;
