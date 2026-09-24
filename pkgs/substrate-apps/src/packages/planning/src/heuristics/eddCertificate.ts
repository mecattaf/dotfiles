/**
 * Preemptive earliest-due-date as a feasibility certificate, not a sort.
 *
 * Volume II Part III section 2: Jackson's rule solves maximum lateness on one
 * machine by earliest due date, but almost nothing in this plant has a due date
 * — upstream windows and the occasional demo are the whole set — so sorting the
 * backlog by due date would drown value density in mostly-absent dates.
 *
 * The correct use is a gate on the dated subset. Horn's rule solves the
 * preemptive problem with release dates exactly, in `n log n`, and its maximum
 * lateness is a lower bound on the non-preemptive one. If the preemptive
 * relaxation says the dated set is infeasible, it is infeasible
 * non-preemptively too, and the answer is to renegotiate a date rather than to
 * schedule harder. Twenty lines over a handful of jobs, producing a certificate.
 *
 * Section 3 makes the same point about branch and bound: keep the bound and
 * discard the tree. The preemptive relaxation alone is the certificate.
 *
 * The module produces a certificate the release evaluator carries. It never
 * reorders the backlog.
 */
import type { TaskId, WindowIndex } from "../schema/ids.ts";

/** One dated item, in the units the certificate works in. */
export interface DatedItem {
  /** The item. */
  readonly taskId: TaskId;
  /** When the item becomes available, as a window index. */
  readonly releaseWindow: WindowIndex;
  /** Its duration, expressed in windows so release and duration share a scale. */
  readonly durationWindows: number;
  /** The window it is due by. */
  readonly dueWindow: WindowIndex;
}

/** The certificate. */
export interface DeadlineCertificate {
  /**
   * Maximum lateness under the preemptive relaxation.
   *
   * A lower bound on the non-preemptive value, so a positive number is a proof
   * of infeasibility and a non-positive one is not a proof of feasibility.
   */
  readonly lmax: number;
  /**
   * Whether the dated set is provably infeasible.
   *
   * True means renegotiate a date. False means the relaxation did not refute it,
   * which is weaker than a guarantee and the certificate says so by name.
   */
  readonly provablyInfeasible: boolean;
  /** The item that attained the maximum lateness. */
  readonly witness: ReadonlyArray<TaskId>;
}

/**
 * Runs Horn's preemptive rule over the dated subset.
 *
 * At each event the available item with the earliest due date runs; preemption
 * happens the instant an item with an earlier date is released. Maximum lateness
 * over the resulting schedule is the bound.
 *
 * @param items - The dated subset only. Undated items must not be passed here;
 *   they have no place in a deadline certificate and would drown it.
 * @returns The bound, whether it refutes feasibility, and which items attained
 *   it.
 */
export const deadlineCertificate = (
  items: ReadonlyArray<DatedItem>
): DeadlineCertificate => {
  if (items.length === 0) {
    return { lmax: Number.NEGATIVE_INFINITY, provablyInfeasible: false, witness: [] };
  }

  const remainingWork = new Map<TaskId, number>();
  for (const item of items) remainingWork.set(item.taskId, Math.max(0, item.durationWindows));

  const completion = new Map<TaskId, number>();
  const byRelease = [...items].sort((left, right) => left.releaseWindow - right.releaseWindow);

  let now = byRelease[0]?.releaseWindow ?? 0;
  let released: Array<DatedItem> = [];
  let cursor = 0;

  while (cursor < byRelease.length || released.length > 0) {
    while (cursor < byRelease.length) {
      const next = byRelease[cursor];
      if (next === undefined || next.releaseWindow > now) break;
      released.push(next);
      cursor += 1;
    }

    if (released.length === 0) {
      const next = byRelease[cursor];
      if (next === undefined) break;
      now = next.releaseWindow;
      continue;
    }

    // Run the released item with the earliest due date.
    let current = released[0];
    if (current === undefined) break;
    for (const candidate of released.slice(1)) {
      if (candidate.dueWindow < current.dueWindow) current = candidate;
    }

    // Run until either it finishes or something with an earlier date arrives.
    const work = remainingWork.get(current.taskId) ?? 0;
    const nextArrival = byRelease[cursor]?.releaseWindow ?? Number.POSITIVE_INFINITY;
    const slice = Math.min(work, Math.max(0, nextArrival - now));
    const advanced = slice > 0 ? slice : work;

    now += advanced;
    const left = work - advanced;
    remainingWork.set(current.taskId, left);
    if (left <= 0) {
      completion.set(current.taskId, now);
      const finished = current;
      released = released.filter((item) => item.taskId !== finished.taskId);
    }
  }

  let lmax = Number.NEGATIVE_INFINITY;
  const witness: Array<TaskId> = [];
  for (const item of items) {
    const finish = completion.get(item.taskId) ?? Number.POSITIVE_INFINITY;
    const lateness = finish - item.dueWindow;
    if (lateness > lmax) {
      lmax = lateness;
      witness.length = 0;
      witness.push(item.taskId);
    } else if (lateness === lmax) {
      witness.push(item.taskId);
    }
  }

  return { lmax, provablyInfeasible: lmax > 0, witness };
};

/**
 * Whether one item is under deadline pressure, which is one of the three grounds
 * that license escalation to a metered lane.
 *
 * @param certificate - The certificate over the dated subset.
 * @param taskId - The item in question.
 * @returns Whether this item is among those attaining a positive maximum
 *   lateness. Deadline pressure is a property of the certificate, not of the
 *   item alone.
 */
export const underDeadlinePressure = (
  certificate: DeadlineCertificate,
  taskId: TaskId
): boolean => certificate.provablyInfeasible && certificate.witness.includes(taskId);
