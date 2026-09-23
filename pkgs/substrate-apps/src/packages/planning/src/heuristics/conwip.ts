/**
 * CONWIP: cap the work in process, release into the cap from a priority-ordered
 * backlog, run deterministic routings inside.
 *
 * Volume I chapter 11 names this the exact middle between the queues tally once
 * had and the flows that replaced them. Chapter 11.2 is precise about what is
 * missing: tally already holds the cap, because a capacity-k pool is a k-CONWIP
 * loop, and it already holds the in-cap routings, because that is what a flow
 * is. The absent third part is the release station, and this module is its gate.
 *
 * Caps are data, not derived. Chapter 11.3 sets them by Little's law: pick the
 * cycle time you can tolerate per family, multiply by observed throughput. So a
 * cap arrives on the level list or the campaign, and nothing here computes one.
 *
 * Constraint R8 of the chapter-6 LP is the same statement inside the linear
 * program, and its dual is the price of the cap.
 */
import { Option } from "effect";
import type { BacklogItem, WipCount } from "../schema/backlog.ts";
import type { FamilyName, LevelName, NamespaceName } from "../schema/ids.ts";

/** A declared work-in-process cap on one axis. */
export interface ConwipCap {
  /** Which axis this cap runs on. */
  readonly axis: "level" | "namespace" | "family";
  /** The name of the level, namespace or family capped. */
  readonly subject: string;
  /** The cap itself, set by Little's law at the planning level. */
  readonly cap: number;
}

/** The three counts an item is charged against. */
export interface ConwipContext {
  /** Declared caps on every axis. */
  readonly caps: ReadonlyArray<ConwipCap>;
  /** Current released-or-in-flight counts. */
  readonly wip: ReadonlyArray<WipCount>;
}

/** Whether an item fits under every cap it is charged against. */
interface ConwipVerdict {
  /** True when every cap has slack. */
  readonly admissible: boolean;
  /**
   * The single binding cap, when one binds.
   *
   * Naming the binding cap is what makes a deferral legible; a boolean alone
   * reproduces the condition the mutex incident was found under.
   */
  readonly binding: Option.Option<ConwipCap>;
  /** Slack remaining on the tightest cap, floored at zero. */
  readonly slack: number;
}

const capFor = (
  caps: ReadonlyArray<ConwipCap>,
  axis: ConwipCap["axis"],
  subject: string
): Option.Option<ConwipCap> => {
  for (const cap of caps) {
    if (cap.axis === axis && cap.subject === subject) return Option.some(cap);
  }
  return Option.none();
};

/**
 * Counts current work in process against one axis.
 *
 * @param wip - Per-triple counts as the Factory maintains them.
 * @param axis - Which of the three axes to sum over.
 * @param subject - The level, namespace or family name.
 * @returns The number of released or in-flight items charged to that subject.
 */
export const wipOn = (
  wip: ReadonlyArray<WipCount>,
  axis: ConwipCap["axis"],
  subject: string
): number => {
  let total = 0;
  for (const entry of wip) {
    const key =
      axis === "level" ? entry.level : axis === "namespace" ? entry.namespace : entry.family;
    if (key === subject) total += entry.count;
  }
  return total;
};

/**
 * Tests one item against every cap it is charged against.
 *
 * Charges are additive along three axes at once: the item's level, its
 * namespace, and its family. An undeclared cap does not block; a declared cap
 * with no slack does, and the verdict names it.
 *
 * @param item - The candidate.
 * @param context - Declared caps and current counts.
 * @param pendingAdmits - Admits already proposed in this same pass, so a single
 *   evaluation cannot release past a cap by counting only what the kernel has.
 * @returns Whether the item fits, the binding cap when it does not, and the
 *   slack on the tightest cap.
 */
export const conwipVerdict = (
  item: BacklogItem,
  context: ConwipContext,
  pendingAdmits: ReadonlyArray<BacklogItem>
): ConwipVerdict => {
  const axes: ReadonlyArray<readonly [ConwipCap["axis"], string]> = [
    ["level", item.level],
    ["namespace", item.namespace],
    ["family", item.family]
  ];

  let tightest = Number.POSITIVE_INFINITY;
  let binding: Option.Option<ConwipCap> = Option.none();

  for (const [axis, subject] of axes) {
    const declared = capFor(context.caps, axis, subject);
    if (Option.isNone(declared)) continue;

    const pending = pendingAdmits.filter((candidate) => {
      const key =
        axis === "level"
          ? candidate.level
          : axis === "namespace"
            ? candidate.namespace
            : candidate.family;
      return key === subject;
    }).length;

    const used = wipOn(context.wip, axis, subject) + pending;
    const slack = declared.value.cap - used;
    if (slack < tightest) {
      tightest = slack;
      if (slack <= 0) binding = declared;
    }
  }

  const slack = Number.isFinite(tightest) ? Math.max(0, tightest) : Number.POSITIVE_INFINITY;
  return { admissible: Option.isNone(binding), binding, slack };
};

/**
 * Derives the cap list from a level list and a set of family and namespace caps.
 *
 * @param levelCaps - The `wipCap` declared on each level.
 * @param familyCaps - Per-family caps, set by Little's law at the planning level.
 * @param namespaceCaps - Per-namespace caps, where a namespace declares one.
 * @returns One flat cap list for `conwipVerdict`.
 */
export const conwipCaps = (
  levelCaps: ReadonlyArray<readonly [LevelName, number]>,
  familyCaps: ReadonlyArray<readonly [FamilyName, number]>,
  namespaceCaps: ReadonlyArray<readonly [NamespaceName, number]>
): ReadonlyArray<ConwipCap> => [
  ...levelCaps.map(([subject, cap]): ConwipCap => ({ axis: "level", subject, cap })),
  ...familyCaps.map(([subject, cap]): ConwipCap => ({ axis: "family", subject, cap })),
  ...namespaceCaps.map(([subject, cap]): ConwipCap => ({ axis: "namespace", subject, cap }))
];
