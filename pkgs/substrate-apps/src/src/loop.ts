/**
 * The CONWIP loop. A fixed work-in-progress cap over admitted Tasks; admission
 * only on a free slot and only when every dependency edge into the item is
 * satisfied; release only when the release rule says so.
 *
 * The scheduler never originates a command line. A WorkItem carries a name; the
 * seat adapter carries the command.
 */
import type { AxClient, AxTask } from "./axclient.ts";
import { Ledger, type LedgerEntry } from "./ledger.ts";
import { evaluateRelease, type Reading, type SlotState } from "./release.ts";
import { fixtureOutcome, type WorkItem } from "./schema.ts";
import { buildTask, taskNameFor, type TaskContext } from "./taskspec.ts";

export interface LoopOptions {
  /** The cap is data, passed in, never derived. */
  readonly cap: number;
  /** Refuse a reading older than this. */
  readonly maxReadingAgeMs: number;
  /** Bound on how long one WatchTask stream is drained. */
  readonly watchTimeoutMs: number;
  /** Returns the current instant as ISO-8601 UTC. Read outside the release rule. */
  readonly now: () => string;
  /** Default image for the dispatched Task. */
  readonly image: string;
  /**
   * How an admitted item produces its outcome.
   *
   * ABSENT, the loop keeps the fixture behaviour item 11 documented and item
   * 11's own receipt flagged: it posts the source record's HISTORICAL outcome,
   * because a mock stack runs no `ax-task-runner` and nothing would ever
   * advance a Task past Running on its own.
   *
   * PRESENT, the loop dispatches for real and posts what came back. The two
   * are the arms of one `if`/`else` on this field, so the historical branch is
   * not merely skipped on the live path: it is the other arm of an exclusive
   * choice, and there is exactly one read of `sourceStatus` for an outcome in
   * this file, inside the `else`. Fixture support cannot be reached from a run
   * that supplies a hook.
   *
   * `Terminating` is deliberately not in the return type. It is in the CONWIP's
   * releasing set because ax writes it on delete, and a seat has no business
   * claiming it.
   */
  readonly outcomeOf?: (item: WorkItem) => Promise<{
    readonly phase: "Completed" | "Failed";
    readonly reason: string;
  }>;
  /**
   * Durable sink for this ledger, one line per event, flushed per line. Absent,
   * as it is for every caller that existed before this item, nothing is written
   * and the bytes this loop produces are unchanged.
   */
  readonly ledgerSink?: { append(entry: LedgerEntry): void };
  /** The seat id written into AX_CONWIP_SEAT. Default "unknown". */
  readonly seat?: string;
  /** A-15: the bounded wait on HOLD. Default `DEFAULT_HOLD_BUDGET`. */
  readonly holdBudget?: HoldBudget;
}

/**
 * `abandoned` (A-15/A-18): the hold budget ran out with the Task still not
 * terminal. The slot is NOT handed back to admission, because the Task may
 * still be running; the ledger's `abandon` line says so out loud.
 */
export type Disposition = "pending" | "admitted" | "released" | "refused" | "abandoned";

/**
 * A-15/A-18: how long a HOLD is waited on. `attempts` extra release passes,
 * `delayMs` apart, both data. `sleep` is injected so a test waits for nothing.
 */
export interface HoldBudget {
  readonly attempts: number;
  readonly delayMs: number;
  readonly sleep?: (ms: number) => Promise<void>;
}

export const DEFAULT_HOLD_BUDGET: HoldBudget = { attempts: 3, delayMs: 1000 };

export const defaultSleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

export interface ItemState {
  readonly item: WorkItem;
  readonly key: string;
  readonly taskName: string;
  disposition: Disposition;
}

export interface LoopResult {
  readonly ledger: Ledger;
  readonly derived: number;
  readonly admitted: number;
  readonly released: number;
  readonly refused: number;
  readonly unresolved: number;
  /** A-15: items whose hold budget ran out with the Task not terminal. */
  readonly abandoned: number;
}

export function itemKey(i: WorkItem): string {
  return `${i.runId}#${i.index}`;
}

export { taskNameFor } from "./taskspec.ts";

/**
 * The Task this scheduler dispatches, with the FIELD-MAP env keys (FM-2).
 * `spec.command` is left empty on purpose. Throws when the size check refuses;
 * the loops call `buildTask` BEFORE admission so a refusal costs no slot.
 */
export function taskFor(i: WorkItem, atespace: string, image: string, ctx: TaskContext = { seat: "unknown" }): AxTask {
  const b = buildTask(i, atespace, image, ctx);
  if (!b.ok) throw new Error(`task spec refused for ${i.runId}#${i.index}: ${b.reason}`);
  return b.task;
}

/**
 * A dependency edge from every item at phaseIndex n to every item at
 * phaseIndex n+1 in the same runId. An edge is satisfied when the predecessor
 * was RELEASED. A predecessor that was REFUSED propagates the refusal, so a
 * refused phase can never deadlock the phase behind it.
 */
export function dependencyStatus(
  item: WorkItem,
  states: ReadonlyMap<string, ItemState>,
): "satisfied" | "waiting" | "refused" {
  // Lineage, not a phase barrier (D06, successor review r2): wait only on the
  // items this item provably waited on in its source run (`after`, from the
  // journal). An item with no `after` is independent.
  let sawRefused = false;
  for (const i of item.after ?? []) {
    const st = states.get(`${item.runId}#${i}`);
    if (st === undefined || st.disposition === "released") continue;
    if (st.disposition === "refused") { sawRefused = true; continue; }
    return "waiting";
  }
  return sawRefused ? "refused" : "satisfied";
}

/** Run the loop over the derived items against a live ax server. */
export async function runLoop(
  items: readonly WorkItem[],
  client: AxClient,
  opts: LoopOptions,
): Promise<LoopResult> {
  const ledger = new Ledger();
  /** Append to the in-memory ledger and, when one is configured, to disk. */
  const rec = (e: Omit<LedgerEntry, "seq">): void => {
    const entry = ledger.append(e);
    opts.ledgerSink?.append(entry);
  };
  const ordered = [...items].sort((a, b) =>
    a.runId === b.runId ? a.index - b.index : a.runId < b.runId ? -1 : 1,
  );
  const states = new Map<string, ItemState>();
  for (const item of ordered) {
    states.set(itemKey(item), {
      item,
      key: itemKey(item),
      taskName: taskNameFor(item),
      disposition: "pending",
    });
  }

  let unresolved = 0;
  for (const st of states.values()) {
    rec({
      event: "derive",
      at: opts.now(),
      runId: st.item.runId,
      label: st.item.label,
      taskName: st.taskName,
      cap: opts.cap,
      slotsInUse: 0,
      reason: st.item.promptResolved
        ? `prompt ${st.item.prompt.length} chars, phase ${st.item.phaseIndex}`
        : `prompt unresolved: ${st.item.promptUnresolvedReason ?? "unknown"}`,
    });
    if (!st.item.promptResolved) unresolved++;
  }

  let slotsInUse = 0;
  let progressed = true;
  const tasks = new Map<string, AxTask>();

  const budget = opts.holdBudget ?? DEFAULT_HOLD_BUDGET;
  const sleep = budget.sleep ?? defaultSleep;
  let holdRounds = 0;

  while (progressed) {
    progressed = false;

    // One admission pass. Slots about to be filled are reserved within the
    // pass so the same slot is never handed out twice.
    let reserved = 0;
    const admittedThisPass: ItemState[] = [];

    for (const st of states.values()) {
      if (st.disposition !== "pending") continue;

      // Refusals that cost no slot, in a fixed order.
      if (st.item.sourceStatus === "killed") {
        st.disposition = "refused";
        progressed = true;
        rec({
          event: "refuse", at: opts.now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: "source run record has status killed",
        });
        continue;
      }
      if (!st.item.promptResolved) {
        st.disposition = "refused";
        progressed = true;
        rec({
          event: "refuse", at: opts.now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: `prompt unresolved: ${st.item.promptUnresolvedReason ?? "unknown"}`,
        });
        continue;
      }
      const dep = dependencyStatus(st.item, states);
      if (dep === "refused") {
        st.disposition = "refused";
        progressed = true;
        rec({
          event: "refuse", at: opts.now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: `a dependency in phase ${st.item.phaseIndex - 1} was refused`,
        });
        continue;
      }
      if (dep === "waiting") continue;

      if (slotsInUse + reserved >= opts.cap) continue;
      // FM-2: the size check runs before a slot is taken.
      const built = buildTask(st.item, client.atespace, opts.image, { seat: opts.seat ?? "unknown", model: "claude-opus-5-5" });
      if (!built.ok) {
        st.disposition = "refused";
        progressed = true;
        rec({
          event: "refuse", at: opts.now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: `task spec refused: ${built.reason}`,
        });
        continue;
      }
      tasks.set(st.key, built.task);
      reserved++;
      admittedThisPass.push(st);
    }

    for (const st of admittedThisPass) {
      st.disposition = "admitted";
      slotsInUse++;
      progressed = true;
      rec({
        event: "admit", at: opts.now(), runId: st.item.runId, label: st.item.label,
        taskName: st.taskName, cap: opts.cap, slotsInUse,
        reason: `phase ${st.item.phaseIndex} dependencies satisfied`,
      });

      await client.updateTask(tasks.get(st.key)!);
      rec({
        event: "dispatch", at: opts.now(), runId: st.item.runId, label: st.item.label,
        taskName: st.taskName, cap: opts.cap, slotsInUse,
        reason: "UpdateTask",
      });
    }

    // Release pass over everything currently admitted.
    for (const st of states.values()) {
      if (st.disposition !== "admitted") continue;

      // ax closes the watch stream on Running, Completed or Failed. Drain it,
      // then read the phase again, because Running still holds a slot.
      await client.watchTaskToEnd(st.taskName, opts.watchTimeoutMs);

      // Where the outcome comes from. Exactly two arms, and they are exclusive.
      //
      //  - With a hook, the item is dispatched for real and the loop posts what
      //    came back. The fixture branch below is the OTHER arm of this `if`,
      //    so it does not execute, cannot execute, and is not reachable by any
      //    ordering of events on the live path.
      //  - Without one, the loop keeps item 11's fixture behaviour: a mock
      //    stack runs no ax-task-runner, so nothing would ever advance a Task
      //    past Running, and the historical outcome is read off the source
      //    record. This is the ONLY read of `sourceStatus` for an outcome in
      //    this file.
      let outcome: "Completed" | "Failed";
      if (opts.outcomeOf !== undefined) {
        const produced = await opts.outcomeOf(st.item);
        outcome = produced.phase;
        rec({
          event: "outcome", at: opts.now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: `${produced.phase}: ${produced.reason}`,
        });
      } else {
        outcome = fixtureOutcome(st.item);
      }

      // The scheduler posts that outcome and then reads the server back. The
      // reading the release rule consumes is what the server returned.
      const current = await client.getTask(st.taskName);
      if ((current.status?.phase ?? "") !== outcome) {
        await client.updateTask({
          ...current,
          metadata: { name: st.taskName, atespace: client.atespace },
          status: { ...(current.status ?? {}), phase: outcome },
        });
      }

      const observedAt = opts.now();
      const after = await client.getTask(st.taskName);
      const reading: Reading = {
        taskName: st.taskName,
        phase: after.status?.phase ?? "",
        observedAt,
        action: "GET",
      };
      const state: SlotState = {
        runId: st.item.runId,
        label: st.item.label,
        taskName: st.taskName,
        asOf: opts.now(),
        maxReadingAgeMs: opts.maxReadingAgeMs,
      };
      const decision = evaluateRelease(state, reading);
      if (decision.kind === "RELEASE") {
        st.disposition = "released";
        slotsInUse--;
        progressed = true;
        rec({
          event: "release", at: observedAt, runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse, reason: decision.reason,
        });
      } else if (decision.kind === "REFUSE") {
        st.disposition = "refused";
        slotsInUse--;
        progressed = true;
        rec({
          event: "refuse", at: observedAt, runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: opts.cap, slotsInUse,
          reason: `release refused: ${decision.reason}`,
        });
      }
      // HOLD keeps the slot; the bounded wait below reads it again.
    }

    // A-15 (track conwip-fixes, 2026-09-23). A pass in which nothing moved but
    // something is still admitted used to END the loop with the slot held and
    // no ledger line. Now it waits `delayMs` and reads again, up to `attempts`
    // times; when the budget runs out every still-held item gets an `abandon`
    // line. Real progress resets the budget.
    if (progressed) {
      holdRounds = 0;
    } else {
      const held = [...states.values()].filter((st) => st.disposition === "admitted");
      if (held.length > 0 && holdRounds < budget.attempts) {
        holdRounds++;
        await sleep(budget.delayMs);
        progressed = true;
      } else {
        for (const st of held) {
          st.disposition = "abandoned";
          rec({
            event: "abandon", at: opts.now(), runId: st.item.runId, label: st.item.label,
            taskName: st.taskName, cap: opts.cap, slotsInUse,
            reason: `still not terminal after ${budget.attempts} extra reads ${budget.delayMs} ms apart; the slot is not handed back because the Task may still be running`,
          });
        }
      }
    }
  }

  return {
    ledger,
    derived: states.size,
    admitted: ledger.count("admit"),
    released: ledger.count("release"),
    refused: ledger.count("refuse"),
    unresolved,
    abandoned: ledger.count("abandon"),
  };
}
