/**
 * What a finished run did, as one word and one exit code (gap G3,
 * FINAL-2026-09-23). The interpreter's `status` only says whether the SCRIPT
 * finished: agent() returns null for a failed or refused call by the dialect,
 * so a run whose every call failed still ends `completed`. This module looks
 * at the calls.
 *
 *   0  all-done       every call done or cached (or the script made no call)
 *   1  script-failed  the script threw (the interpreter's status is failed)
 *   2  (conwip-run)   bad arguments or a run dir held by another process
 *   3  partial        at least one call done, at least one failed, none refused
 *   4  all-failed     no call done, at least one failed
 *   4  refused        any call refused (admission, route, runtime), whatever
 *                     the others did: a refusal needs an operator's change,
 *                     not a retry
 */

export const EXIT = {
  allDone: 0,
  scriptFailed: 1,
  usage: 2,
  partial: 3,
  allFailedOrRefused: 4,
} as const;

export type Outcome = "all-done" | "script-failed" | "partial" | "all-failed" | "refused";

export interface CallCounts {
  readonly total: number;
  /** Ran live in this process and returned a value. */
  readonly done: number;
  /** Returned a value from the journal of an earlier start. */
  readonly cached: number;
  /** Returned null (or never finished) for any reason but a refusal. */
  readonly failed: number;
  /** Returned null because CONWIP or the runtime refused it. */
  readonly refused: number;
  /**
   * parallel() thunks and pipeline() stages that threw, so the dialect nulled
   * their item although no call failed (the interpreter's item_null events).
   * A run with any is at best partial (successor review r5).
   */
  readonly nulledItems: number;
}

/**
 * The error texts of a refusal, as src/submit.ts and @substrate/runners
 * backend.ts write them: "conwip refused ...", "conwip capacity refused ...",
 * "runtime <name> refused: ...".
 */
const REFUSAL = /^(conwip (capacity )?refused\b|runtime \S+ refused\b)/;

export function isRefusal(error: string | undefined): boolean {
  return error !== undefined && REFUSAL.test(error);
}

export function countCalls(
  calls: readonly { readonly state: string; readonly error?: string | undefined }[],
  events: readonly { readonly type: string }[] = [],
): CallCounts {
  let done = 0;
  let cached = 0;
  let failed = 0;
  let refused = 0;
  for (const c of calls) {
    if (c.state === "done") done++;
    else if (c.state === "cached") cached++;
    else if (isRefusal(c.error)) refused++;
    else failed++; // "null", or "queued"/"running" when the run ended around it
  }
  const nulledItems = events.filter((e) => e.type === "item_null").length;
  return { total: calls.length, done, cached, failed, refused, nulledItems };
}

export function runOutcome(
  status: "completed" | "failed",
  calls: readonly { readonly state: string; readonly error?: string | undefined }[],
  events: readonly { readonly type: string }[] = [],
  value?: unknown,
): { readonly outcome: Outcome; readonly code: number; readonly counts: CallCounts } {
  const counts = countCalls(calls, events);
  if (status === "failed") return { outcome: "script-failed", code: EXIT.scriptFailed, counts };
  if (counts.refused > 0) return { outcome: "refused", code: EXIT.allFailedOrRefused, counts };
  if (counts.failed === 0 && counts.nulledItems > 0) {
    // Every item of the final value null: nothing the script returns is work.
    const allNull = Array.isArray(value) && value.length > 0 && value.every((v) => v === null);
    return allNull ? { outcome: "all-failed", code: EXIT.allFailedOrRefused, counts } : { outcome: "partial", code: EXIT.partial, counts };
  }
  if (counts.failed === 0) return { outcome: "all-done", code: EXIT.allDone, counts };
  if (counts.done + counts.cached === 0) return { outcome: "all-failed", code: EXIT.allFailedOrRefused, counts };
  return { outcome: "partial", code: EXIT.partial, counts };
}

/** The one line conwip-run prints on stderr when a run ends. */
export function summaryLine(runId: string, o: ReturnType<typeof runOutcome>): string {
  const n = o.counts;
  return `conwip-run: ${o.outcome} exit=${o.code} calls=${n.total} done=${n.done} cached=${n.cached} failed=${n.failed} refused=${n.refused}${n.nulledItems ? ` nulled=${n.nulledItems}` : ""} run=${runId}`;
}
