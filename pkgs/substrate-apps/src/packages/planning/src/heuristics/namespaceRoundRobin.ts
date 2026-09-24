/**
 * Per-namespace fairness within a level.
 *
 * A namespace is `workspace.repo`, and the thesis's Appendix C.2 corrects the
 * earlier per-repo framing: tally is already one factory daemon with one socket,
 * one state directory and one row table, with per-repo content riding every job
 * row as workspace metadata. There is nothing to federate. What is actually
 * missing is namespace as a first-class dimension — a query filter, release
 * fairness, and per-namespace configuration.
 *
 * Within a level the station round-robins across namespaces, each with a
 * declared share. Unnamespaced work gets its own declared share rather than a
 * synthesised repository, because synthesising one would make it compete as if
 * it had an owner.
 *
 * The rule is deliberately weak. It interleaves; it does not reorder within a
 * namespace, and it never lets fairness override a level. Fairness is the last
 * tiebreak before value density, not a competing objective.
 */
import { Option } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import type { NamespaceName } from "../schema/ids.ts";
import { namespaceByName, type NamespaceTable } from "../schema/namespace.ts";

/** How far ahead of its share a namespace is running. */
interface NamespaceDebt {
  /** The namespace. */
  readonly namespace: NamespaceName;
  /** Its declared relative share. */
  readonly share: number;
  /** Its current released-or-in-flight count. */
  readonly wip: number;
  /**
   * Work in process divided by share.
   *
   * Lower is more owed. A namespace with no declared configuration is treated as
   * infinitely indebted, which sends it to the back rather than giving it an
   * invented share.
   */
  readonly ratio: number;
}

/**
 * Computes each namespace's debt against its declared share.
 *
 * @param table - The namespace table.
 * @param wipByNamespace - Current counts.
 * @returns One debt per namespace present in the counts, most owed first.
 */
const namespaceDebts = (
  table: NamespaceTable,
  wipByNamespace: ReadonlyArray<readonly [NamespaceName, number]>
): ReadonlyArray<NamespaceDebt> =>
  wipByNamespace
    .map(([namespace, wip]): NamespaceDebt => {
      const config = namespaceByName(table, namespace);
      const share = Option.match(config, {
        onNone: () => 0,
        onSome: (value) => value.wipShare
      });
      return {
        namespace,
        share,
        wip,
        ratio: share > 0 ? wip / share : Number.POSITIVE_INFINITY
      };
    })
    .sort((left, right) => left.ratio - right.ratio);

/**
 * Interleaves candidates across namespaces, most-owed namespace first.
 *
 * Order within a namespace is preserved exactly, so whatever ordering the caller
 * applied — value density, rank — survives the interleave.
 *
 * @param candidates - The level's candidates, already ordered within namespace.
 * @param table - The namespace table.
 * @param wipByNamespace - Current counts, which set the starting debts.
 * @returns The interleaved order.
 */
export const roundRobinByNamespace = (
  candidates: ReadonlyArray<BacklogItem>,
  table: NamespaceTable,
  wipByNamespace: ReadonlyArray<readonly [NamespaceName, number]>
): ReadonlyArray<BacklogItem> => {
  const queues = new Map<NamespaceName, Array<BacklogItem>>();
  for (const item of candidates) {
    const queue = queues.get(item.namespace) ?? [];
    queue.push(item);
    queues.set(item.namespace, queue);
  }

  const counts = new Map<NamespaceName, number>();
  for (const [namespace, wip] of wipByNamespace) counts.set(namespace, wip);
  for (const namespace of queues.keys()) {
    if (!counts.has(namespace)) counts.set(namespace, 0);
  }

  const ordered: Array<BacklogItem> = [];
  while (queues.size > 0) {
    const debts = namespaceDebts(
      table,
      [...queues.keys()].map((namespace) => [namespace, counts.get(namespace) ?? 0] as const)
    );

    let taken = false;
    for (const debt of debts) {
      const queue = queues.get(debt.namespace);
      if (queue === undefined || queue.length === 0) {
        queues.delete(debt.namespace);
        continue;
      }
      const next = queue.shift();
      if (next === undefined) {
        queues.delete(debt.namespace);
        continue;
      }
      ordered.push(next);
      counts.set(debt.namespace, (counts.get(debt.namespace) ?? 0) + 1);
      if (queue.length === 0) queues.delete(debt.namespace);
      taken = true;
      break;
    }
    if (!taken) break;
  }

  return ordered;
};
