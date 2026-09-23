/**
 * Subassembly batching under decaying setup carryover.
 *
 * Volume II Part III section 8 inverts the classical setup assumption. Expertise
 * changeover is free: retooling an agent from one domain to another is injecting
 * a different prompt or skill, so the skill component of the setup matrix is
 * identically zero. Material-state changeover is not. What carries between jobs
 * is warm state — a prompt cache keyed to a context, a worktree at a base
 * revision — and it decays whether or not the machine is used:
 *
 *     s_jk(t) = sum_r s_r * (1 - phi_r(k,j) * exp(-t / T_r))
 *
 * with `phi_r` the affinity between the outgoing class and the incoming job, `t`
 * the idle interval, and `T_r` the resource's decay constant. This is setup
 * carryover with the carryover perishing rather than persisting, and that one
 * modification changes every conclusion.
 *
 * The two warm resources have decay constants three orders of magnitude apart
 * and neither is a machine property. A prompt cache is short and sharp. A
 * worktree's constant is not a timer at all: it goes stale because the base
 * branch moves, so its carryover decays at the repository's merge rate. The same
 * physical fact — upstream churn — is setup decay measured on the machine side
 * and holding cost measured on the inventory side.
 *
 * The arithmetic gives a sharp negative result. Grouping saves
 * `(n - 1) * (s_cold - s_warm) * E[exp(-delta / T)]`, and since a job occupies
 * its lane for its full duration, the gap between consecutive family jobs is at
 * least the service interval. With a short cache constant and full-length jobs
 * that expectation is essentially zero: campaign batching saves essentially no
 * prompt-cache setup. What survives is worktree warmth, which is large, and
 * short filler where the service interval is genuinely below the constant.
 *
 * Decay makes the optimum bimodal rather than smooth: carryover collapses once
 * the gap exceeds the constant, so a batch is either inside the warm window or
 * entirely outside it, with no partial credit. Hence the hard no-gap rule. A
 * group that cannot honour it is abandoned for value density alone, and this
 * module returns `None`. Half measures buy nothing.
 */
import { Option } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import type { SubassemblyKey } from "../schema/ids.ts";

/** A named warm prerequisite and its decay law. */
export interface Subassembly {
  /** The key items share when they share this warm state. */
  readonly key: SubassemblyKey;
  /** Setup cost when cold. */
  readonly coldSeconds: number;
  /** Setup cost when fully warm. */
  readonly warmSeconds: number;
  /**
   * The decay constant.
   *
   * For a prompt cache this is a short wall-clock interval. For a worktree it is
   * derived from the repository's merge rate, and it is not a timer: it is
   * readable from any repository's history and belongs in the same data as the
   * family holding costs, because it is the same physical fact.
   */
  readonly decayConstantSeconds: number;
}

/** A contiguous group and what warmth it is expected to realise. */
interface Batch {
  /** The shared prerequisite. */
  readonly key: SubassemblyKey;
  /** The items, in the order they should be released. */
  readonly items: ReadonlyArray<BacklogItem>;
  /** Realised setup saving, after decay. */
  readonly savingSeconds: number;
  /** The gap the group must not exceed, which is the decay constant. */
  readonly noGapSeconds: number;
}

/**
 * Carryover surviving an idle interval.
 *
 * @param subassembly - The prerequisite and its decay constant.
 * @param gapSeconds - The measured interval between consecutive uses, supplied
 *   by the caller. Nothing here reads a clock.
 * @param affinity - How well the outgoing state matches the incoming job, in
 *   `[0, 1]`.
 * @returns The fraction of the cold-to-warm saving that survives.
 */
const carryover = (
  subassembly: Subassembly,
  gapSeconds: number,
  affinity: number
): number => {
  if (subassembly.decayConstantSeconds <= 0) return 0;
  const clamped = Math.min(1, Math.max(0, affinity));
  return clamped * Math.exp(-Math.max(0, gapSeconds) / subassembly.decayConstantSeconds);
};

/**
 * The realised saving from running `n` items contiguously.
 *
 * @returns `(n - 1) * (s_cold - s_warm) * carryover`. Zero or fewer items, or a
 *   collapsed carryover, gives zero.
 */
const batchSaving = (
  subassembly: Subassembly,
  count: number,
  gapSeconds: number,
  affinity: number
): number => {
  if (count < 2) return 0;
  const delta = Math.max(0, subassembly.coldSeconds - subassembly.warmSeconds);
  return (count - 1) * delta * carryover(subassembly, gapSeconds, affinity);
};

/**
 * Groups a candidate list by shared subassembly, keeping only the groups whose
 * warmth actually survives.
 *
 * The expected gap between consecutive items of a group on one lane is at least
 * the items' own service interval, so that interval is what the decay is
 * evaluated at. This is the arithmetic that kills prompt-cache batching for
 * full-length jobs and keeps it for short filler.
 *
 * @param candidates - The surviving head of the density order.
 * @param subassemblies - Declared prerequisites with their decay laws.
 * @param minimumSavingSeconds - The smallest saving worth reordering for. Below
 *   this, value density alone is the better rule.
 * @returns The batches worth forming, strongest saving first. An empty array
 *   means release in density order and forget warmth.
 */
export const subassemblyBatches = (
  candidates: ReadonlyArray<BacklogItem>,
  subassemblies: ReadonlyArray<Subassembly>,
  minimumSavingSeconds: number
): ReadonlyArray<Batch> => {
  const byKey = new Map<SubassemblyKey, Array<BacklogItem>>();
  for (const item of candidates) {
    if (Option.isNone(item.subassembly)) continue;
    const key = item.subassembly.value;
    const group = byKey.get(key) ?? [];
    group.push(item);
    byKey.set(key, group);
  }

  const batches: Array<Batch> = [];
  for (const subassembly of subassemblies) {
    const group = byKey.get(subassembly.key);
    if (group === undefined || group.length < 2) continue;

    // A job holds its lane for its full duration, so the gap between two members
    // of the group is at least the median service interval of the group.
    const gapSeconds = group.reduce(
      (longest, item) => Math.max(longest, item.estimate.medianSeconds),
      0
    );
    const saving = batchSaving(subassembly, group.length, gapSeconds, 1);
    if (saving < minimumSavingSeconds) continue;

    batches.push({
      key: subassembly.key,
      items: group,
      savingSeconds: saving,
      noGapSeconds: subassembly.decayConstantSeconds
    });
  }

  return batches.sort((left, right) => right.savingSeconds - left.savingSeconds);
};
