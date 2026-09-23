/**
 * ReplayBackend: answer every agent() call from a REAL journal.jsonl.
 *
 * A call's key is looked up in the journal's results. Two things make a replay
 * faithful rather than merely plausible:
 *
 *  1. Completion ORDER. A pipeline has no barrier, so the order in which later
 *     stages are invoked, and therefore every chained key after that point,
 *     depends on the order the earlier calls finished. The replay releases
 *     results in the journal's terminal order: a call whose result sits at
 *     position p is held until every earlier terminal event has been delivered
 *     or given up on. That reproduces the recorded interleaving exactly.
 *  2. Failures. A key the journal marks `failed` with no result replays as a
 *     terminal failure (`skipped`), which the interpreter turns into null.
 *
 *  3. Calls in flight at a kill. A key the journal STARTED but never ended (no
 *     result, no failed line) was running when the run was killed. It is
 *     parked: never answered, so the replay journals it as started-only, exactly
 *     as the killed run did, and a resume applies the in-flight rule to it. Once
 *     only parked calls remain and the script has gone idle, `killed` resolves:
 *     the replay has reached the kill (D08 of the 2026-09-23 naive evals; before
 *     this they were answered with an error, journaled `failed`, and a resume
 *     from the replay then threw away finished work).
 *
 * A call whose key is not in the journal is a DIVERGENCE: it is recorded in
 * `divergences` and answered with an error (so null), or, with `strict`, it
 * rejects the run.
 */
import type { AgentCall, AgentOutcome, Backend } from "./backend.ts";
import type { LoadedJournal } from "./journal.ts";

export interface ReplayOptions {
  readonly strict?: boolean;
  /**
   * How many event-loop turns to wait for the head-of-line key to be requested
   * before assuming the script will never request it (a divergence) and moving on.
   */
  readonly idleTurns?: number;
  /**
   * agentId -> why that call failed. A journal's `failed` line carries no reason
   * (MEASURED: 79 of 79 failed lines are {type, key, agentId}); the run record's
   * row does (`error`). Give the record's reasons here and a replayed failure
   * reproduces the harness's `[label] failed: <reason>` log line exactly.
   */
  readonly failureReasons?: ReadonlyMap<string, string>;
}

interface Waiter {
  readonly call: AgentCall;
  readonly resolve: (o: AgentOutcome) => void;
}

export class ReplayBackend implements Backend {
  readonly name = "replay";
  readonly divergences: { index: number; key: string; label?: string }[] = [];
  readonly requested: string[] = [];
  private readonly waiting = new Map<string, Waiter[]>();
  private readonly position = new Map<string, number>();
  private head = 0;
  private pumping = false;
  private readonly agentIds = new Map<string, string>();
  /** Calls in flight at the kill: requested, never answered. */
  readonly parked: { index: number; key: string; label?: string }[] = [];
  private resolveKilled!: () => void;
  /** Resolves when the replay reaches the kill: only parked calls remain and the script is idle. */
  readonly killed: Promise<void> = new Promise((r) => (this.resolveKilled = r));
  private watching = false;

  constructor(
    readonly journal: LoadedJournal,
    readonly options: ReplayOptions = {},
  ) {
    journal.terminalOrder.forEach((k, i) => this.position.set(k, i));
    for (const [k, list] of journal.started) {
      const last = list[list.length - 1];
      if (last) this.agentIds.set(k, last.agentId);
    }
  }

  run(call: AgentCall): Promise<AgentOutcome> {
    this.requested.push(call.key);
    if (!this.position.has(call.key) && this.journal.started.has(call.key)) {
      this.parked.push({ index: call.index, key: call.key, label: call.opts.label });
      void this.watchKill();
      return new Promise(() => {});
    }
    if (!this.position.has(call.key)) {
      this.divergences.push({ index: call.index, key: call.key, label: call.opts.label });
      if (this.options.strict) {
        return Promise.reject(new Error(`replay divergence: call #${call.index} (${call.opts.label ?? "unlabelled"}) key ${call.key} is not in the journal`));
      }
      return Promise.resolve({ error: `replay: key not in journal (${call.key})` });
    }
    return new Promise((resolve) => {
      const list = this.waiting.get(call.key) ?? [];
      list.push({ call, resolve });
      this.waiting.set(call.key, list);
      void this.pump();
    });
  }

  /** Resolve `killed` once parked calls exist and nothing else moves for `idleTurns` x 4 turns. */
  private async watchKill(): Promise<void> {
    if (this.watching) return;
    this.watching = true;
    try {
      const turns = (this.options.idleTurns ?? 50) * 4;
      for (;;) {
        const seen = this.requested.length;
        for (let t = 0; t < turns; t++) await new Promise((r) => setImmediate(r));
        const busy = this.pumping || [...this.waiting.values()].some((l) => l.length > 0);
        if (!busy && this.requested.length === seen) {
          this.resolveKilled();
          return;
        }
      }
    } finally {
      this.watching = false;
    }
  }

  private outcome(key: string): AgentOutcome {
    const agentId = this.agentIds.get(key) ?? "";
    // The tokens the recorded run spent on this call (output tokens, what
    // budget.spent() counts), so a budgeted run replays as the same run
    // (successor review r2: a replay spent 0 and ran 20 calls instead of 4).
    const t = this.journal.tokens.get(key);
    const usage = t !== undefined ? { usage: { inputTokens: 0, outputTokens: t } } : {};
    if (this.journal.results.has(key)) {
      const r = this.journal.results.get(key);
      return typeof r === "string" ? { text: r, agentId, ...usage } : { object: r, agentId, ...usage };
    }
    // A budget refusal replays as a refusal (successor review r4): read as a
    // plain failure it became null and the replay completed, exit 0.
    if (this.journal.budgetFailed?.has(key) === true) {
      return { budgetExhausted: true, agentId, ...usage, error: this.journal.failReasons?.get(key) ?? "agent(): budget exhausted (journal)" };
    }
    return { skipped: true, agentId, ...usage, error: this.journal.failReasons?.get(key) ?? this.options.failureReasons?.get(agentId) ?? "journal: failed" };
  }

  private async pump(): Promise<void> {
    if (this.pumping) return;
    this.pumping = true;
    try {
      const order = this.journal.terminalOrder;
      while (this.head < order.length) {
        const key = order[this.head]!;
        let w = this.waiting.get(key);
        if (!w || w.length === 0) {
          // Give the script a chance to request it: the head call may be about
          // to be made by a continuation that is still in the microtask queue.
          const turns = this.options.idleTurns ?? 50;
          for (let t = 0; t < turns && !(this.waiting.get(key)?.length); t++) {
            await new Promise((r) => setImmediate(r));
          }
          w = this.waiting.get(key);
          if (!w || w.length === 0) {
            // Nothing waiting at all: the script is still computing; the next
            // run() restarts the pump. Something else waiting: the head will
            // never be requested (divergence, or a cache hit on resume), skip it.
            if (![...this.waiting.values()].some((l) => l.length > 0)) return;
            this.head++;
            continue;
          }
        }
        const next = w.shift()!;
        next.resolve(this.outcome(key));
        this.head++;
        // Let the continuation of that result run (it may invoke the next call).
        await new Promise((r) => setImmediate(r));
      }
      // Past the end of the recorded order: release anything still waiting (repeat keys).
      for (const [key, list] of this.waiting) while (list.length) list.shift()!.resolve(this.outcome(key));
    } finally {
      this.pumping = false;
      if ([...this.waiting.values()].some((l) => l.length > 0) && this.head < this.journal.terminalOrder.length) {
        const key = this.journal.terminalOrder[this.head]!;
        if (this.waiting.get(key)?.length) void this.pump();
      }
    }
  }
}
