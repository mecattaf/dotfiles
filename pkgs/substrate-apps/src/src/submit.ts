/**
 * The seam the interpreter calls: one ready agent() at a time.
 *
 * CR-03/CR-04 of the 2026-09-23 evals: record replay reaches 7.0% of real
 * prompts, because control flow, schema data flow and branches live in the
 * script. The interpreter (`packages/interpreter` on eval/2026-09-23-interpreter)
 * executes the script and owns the key chain, the journal, the retries and the
 * return value; each agent() it reaches is READY, with its real prompt. This
 * module is what it submits that call to. The CONWIP keeps what it is for:
 * a fixed WIP cap, a fail-closed capacity gate per call model, the FM-2 Task
 * spec with its size check, and a ledger. It never sees the script.
 *
 * `Conwip.asBackend()` returns an object structurally compatible with the
 * interpreter's `Backend` (`run(call) => Promise<AgentOutcome>`, never throwing
 * for an ordinary failure), so the interpreter can take a CONWIP wherever it
 * takes a backend. The types below mirror `packages/interpreter/src/backend.ts`
 * at 08585e1 on purpose rather than importing across branches.
 *
 * Who runs the Task is a `Runner`: the seam where a seat spawn or an ax
 * runner with a result channel (FIELD-MAP P1) plugs in. None ships here.
 */
import type { AxTask } from "./axclient.ts";
import type { MachineSlots, SlotHold } from "./slots.ts";
import type { CapacityGate } from "./capacity/gate.ts";
import { Ledger, type LedgerEntry } from "./ledger.ts";
import { defaultSleep } from "./loop.ts";
import type { WorkItem } from "./schema.ts";
import { buildTask, journalKey, taskNameFor, type TaskContext } from "./taskspec.ts";

/* Mirrors of the interpreter's Backend seam (backend.ts at 08585e1). */
export interface AgentOpts {
  readonly label?: string;
  readonly phase?: string;
  readonly schema?: Record<string, unknown>;
  readonly model?: string;
  readonly effort?: string;
  readonly isolation?: string;
  readonly agentType?: string;
  readonly [k: string]: unknown;
}
export interface AgentCall {
  readonly index: number;
  readonly key: string;
  readonly prompt: string;
  readonly opts: AgentOpts;
  readonly phase: string | undefined;
  readonly attempt: number;
  readonly previousErrors?: readonly string[];
  readonly signal?: AbortSignal;
  /** The interpreter's occurrence of this content in the run, fixed at invocation (same on every attempt and resume). */
  readonly occurrence?: number;
  readonly cid?: string;
  /** The run's budget at admission: a reason when it is spent (asked again when the call leaves the slot queue). */
  readonly budgetExhausted?: () => string | undefined;
}
export interface AgentOutcome {
  readonly text?: string;
  readonly object?: unknown;
  readonly usage?: { readonly inputTokens: number; readonly outputTokens: number };
  readonly error?: string;
  readonly agentId?: string;
  readonly skipped?: boolean;
  readonly budgetExhausted?: boolean;
}
export interface Backend {
  readonly name: string;
  run(call: AgentCall): Promise<AgentOutcome>;
}

/**
 * Where a call will run and what it spends, known BEFORE admission: the model
 * the harness actually runs and the seat that pays for it. With a route the
 * gate, the Task, the ledger and the runner all see the same model and seat
 * (successor review 2026-09-23: the gate judged the script's declared model on
 * the run's --seat while the runner ran claude-opus-5-5, or codex, elsewhere).
 */
export interface CallRoute {
  readonly model: string;
  /** The model allowlist's per-window ceilings for this model (runners models.ts). */
  readonly ceilings?: { readonly five_hour?: number; readonly seven_day?: number; readonly model_scoped?: number };
  /** The capacity seat; undefined when nothing binds this harness to one (refused under a gate). */
  readonly seat: string | undefined;
  readonly harness: string;
  readonly runtime: string;
}

/** Runs ONE admitted Task to its end and reports what came back. */
export interface Runner {
  readonly name: string;
  run(task: AxTask, item: WorkItem, call: AgentCall): Promise<AgentOutcome>;
}

export interface ConwipOptions {
  readonly runId: string;
  readonly workflowName: string;
  /** The model when agent() names none (the interpreter's policy has already applied). */
  readonly defaultModel: string;
  /** The WIP cap. Data. */
  readonly cap: number;
  readonly seat: string;
  readonly atespace: string;
  readonly image: string;
  readonly runner: Runner;
  /** Absent means no capacity gate (a slot-only seat under test); present, it fails closed. */
  readonly capacity?: CapacityGate;
  /** How long a call waits for capacity before it is answered with an error. */
  readonly capacityWait?: { readonly delayMs: number; readonly maxWaitMs: number };
  readonly promptFile?: TaskContext["promptFile"];
  readonly now?: () => string;
  readonly nowMs?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
  readonly ledgerSink?: { append(entry: LedgerEntry): void };
  /**
   * The 1-based index of a phase title in the script's meta. Without it phases
   * are numbered in order of first sight in THIS process, which is wrong on a
   * resume: cached calls never reach the CONWIP, so a later phase is seen first
   * (MEASURED in the integration E2E, 2026-09-23: the resumed judge was
   * admitted as phase 1 instead of 2). A title the meta does not list falls
   * back to first-sight order.
   */
  readonly phaseIndexOf?: (title: string) => number | undefined;
  /** The route of one call (runtime, harness, model that runs, seat). Throws to refuse the call. */
  readonly route?: (call: AgentCall) => CallRoute;
  /**
   * Machine-wide holds for slot seats (successor review r4): a call to a seat
   * whose reading is a slot row takes a kernel-held slot file before it
   * dispatches, so two processes never hold Halogen's one slot together.
   * conwip-run always passes one; absent (unit tests), only this process's
   * in-flight calls are counted.
   */
  readonly machineSlots?: MachineSlots;
}

export class Conwip {
  readonly ledger = new Ledger();
  #inUse = 0;
  readonly #waiters: Array<() => void> = [];
  readonly #phases = new Map<string, number>();
  readonly #occurrences = new Map<string, number>();
  /** Chained call key -> the occurrence it was given, so a retry keeps its identity. */
  readonly #occurrenceOfCall = new Map<string, number>();
  /** Calls admitted per seat and not yet answered: slots the seat's reading cannot see yet. */
  readonly #seatInflight = new Map<string, number>();

  constructor(private readonly opts: ConwipOptions) {
    if (!Number.isInteger(opts.cap) || opts.cap < 1) throw new Error(`cap must be an integer of 1 or more, got ${String(opts.cap)}`);
  }

  get slotsInUse(): number { return this.#inUse; }

  #now(): string { return (this.opts.now ?? (() => new Date().toISOString()))(); }
  #nowMs(): number { return (this.opts.nowMs ?? Date.now)(); }
  #rec(e: Omit<LedgerEntry, "seq" | "at" | "runId" | "cap" | "slotsInUse">): void {
    const entry = this.ledger.append({ ...e, at: this.#now(), runId: this.opts.runId, cap: this.opts.cap, slotsInUse: this.#inUse });
    this.opts.ledgerSink?.append(entry);
  }

  /** The interpreter's view: a Backend. */
  asBackend(): Backend {
    return { name: `conwip:${this.opts.seat}`, run: (call) => this.submit(call) };
  }

  /** The WorkItem one ready call becomes. Phases get 1-based indexes in order of first sight. */
  itemFor(call: AgentCall, route?: CallRoute): WorkItem {
    const title = call.opts.phase ?? call.phase ?? "";
    if (!this.#phases.has(title)) this.#phases.set(title, this.opts.phaseIndexOf?.(title) ?? this.#phases.size + 1);
    const item: Record<string, unknown> = {
      runId: this.opts.runId,
      workflowName: this.opts.workflowName,
      label: call.opts.label ?? `agent-${call.index}`,
      index: call.index,
      phaseIndex: this.#phases.get(title)!,
      phaseTitle: title,
      model: route?.model ?? call.opts.model ?? this.opts.defaultModel,
      prompt: call.prompt,
      promptResolved: true,
      sourceStatus: "live",
      attempt: call.attempt,
    };
    if (call.opts.effort !== undefined) item["effort"] = call.opts.effort;
    return item as unknown as WorkItem;
  }

  async #acquire(signal: AbortSignal | undefined): Promise<boolean> {
    // Aborted is checked after EVERY wake, and an abort wakes the waiter
    // (successor review r3: a call queued for a slot was dispatched with an
    // already-aborted signal after the script had failed).
    while (this.#inUse >= this.opts.cap) {
      if (signal?.aborted) return false;
      await new Promise<void>((r) => {
        const wake = () => {
          const i = this.#waiters.indexOf(wake);
          if (i >= 0) this.#waiters.splice(i, 1);
          signal?.removeEventListener("abort", wake);
          r();
        };
        this.#waiters.push(wake);
        signal?.addEventListener("abort", wake, { once: true });
      });
    }
    if (signal?.aborted) return false;
    this.#inUse++;
    return true;
  }

  readonly #seatWaiters = new Map<string, Array<() => void>>();

  /** Resolves when a call on `seat` answers, or on abort. */
  #seatFreed(seat: string, signal: AbortSignal | undefined): Promise<void> {
    return new Promise<void>((r) => {
      const list = this.#seatWaiters.get(seat) ?? [];
      const wake = () => {
        const i = list.indexOf(wake);
        if (i >= 0) list.splice(i, 1);
        signal?.removeEventListener("abort", wake);
        r();
      };
      list.push(wake);
      this.#seatWaiters.set(seat, list);
      signal?.addEventListener("abort", wake, { once: true });
    });
  }

  #releaseSlot(): void {
    this.#inUse--;
    this.#waiters.shift()?.();
  }

  /**
   * Submit one ready agent() call. Resolves with its outcome; never throws for
   * an ordinary failure (a refusal is an `error` outcome, as the Backend seam
   * requires). The slot is held from admission to the runner's answer and is
   * always given back, so there is nothing to leak on this path.
   */
  async submit(call: AgentCall): Promise<AgentOutcome> {
    let route: CallRoute | undefined;
    try {
      route = this.opts.route?.(call);
    } catch (e) {
      const label = call.opts.label ?? `agent-${call.index}`;
      this.#rec({ label, taskName: label, event: "refuse", reason: `route refused: ${(e as Error).message}` });
      return { error: `conwip refused the route: ${(e as Error).message}` };
    }
    const item = this.itemFor(call, route);
    const taskName = taskNameFor(item);
    const base = { label: item.label, taskName };
    const seat = route ? route.seat : this.opts.seat;
    const where = route ? `, ${route.harness} on ${route.runtime}, seat ${route.seat ?? "none"}` : "";

    const schemaJson = call.opts.schema === undefined ? undefined : JSON.stringify(call.opts.schema);
    // The Task's resume identity is the interpreter's occurrence, fixed at
    // invocation (successor review r3: counting submits here gave a retry a
    // new occurrence, and a resumed call the identity of a cached one).
    // Without one (a caller that is not the interpreter) it is counted per
    // call key, once, so a retry of the same call keeps it.
    let occurrence = call.occurrence ?? this.#occurrenceOfCall.get(call.key);
    if (occurrence === undefined) {
      const jk = journalKey(item.prompt, { model: item.model, effort: item.effort, schema: schemaJson }, 1);
      occurrence = (this.#occurrences.get(jk) ?? 0) + 1;
      this.#occurrences.set(jk, occurrence);
    }
    this.#occurrenceOfCall.set(call.key, occurrence);
    const ctx: TaskContext = {
      seat: seat ?? this.opts.seat, attempt: call.attempt, occurrence, schemaJson,
      isolation: call.opts.isolation, agentType: call.opts.agentType, promptFile: this.opts.promptFile,
    };
    const built = buildTask(item, this.opts.atespace, this.opts.image, ctx);
    if (!built.ok) {
      this.#rec({ ...base, event: "refuse", reason: `task spec refused: ${built.reason}` });
      return { error: `conwip refused the task spec: ${built.reason}` };
    }

    const gate = this.opts.capacity;
    if (gate !== undefined && route !== undefined && route.seat === undefined) {
      const why = `harness ${route.harness} on ${route.runtime} is bound to no capacity seat ([seats] in runtimes.toml)`;
      this.#rec({ ...base, event: "refuse", reason: why });
      return { error: `conwip refused: ${why}` };
    }
    const wait = this.opts.capacityWait ?? { delayMs: 30_000, maxWaitMs: 0 };
    const sleep = this.opts.sleep ?? defaultSleep;
    // Waited time is counted in delays slept, not read off a clock, so the
    // bound holds even under a frozen test clock.
    let waited = 0;
    let admitted = "no capacity gate";
    const seatKey = seat ?? gate?.seatId ?? this.opts.seat;
    const gateCtx = () => ({
      ...(route ? { harness: route.harness } : {}),
      ...(route?.ceilings ? { ceilings: route.ceilings } : {}),
      inflight: this.#seatInflight.get(seatKey) ?? 0,
    });
    /** Capacity, without a slot: waiting on a seat must not hold WIP. undefined = admitted. */
    const capacity = async (): Promise<AgentOutcome | undefined> => {
      if (gate === undefined) return undefined;
      for (;;) {
        // A remote source (the floor) fetches for this job first; `?.` keeps a
        // gate-shaped stub without refresh working (a local source is a no-op).
        await gate.refresh?.(item.model, this.#nowMs(), seat ?? gate.seatId);
        const d = gate.decide(item.model, this.#nowMs(), seat ?? gate.seatId, gateCtx());
        if (d.kind === "ADMIT") {
          admitted = `capacity ADMIT ${d.detail}`;
          return undefined;
        }
        // A slot seat full of this CONWIP's own calls frees when one of them
        // answers: wait for that, not for the capacity clock.
        if (d.reason === "slots-full" && (this.#seatInflight.get(seatKey) ?? 0) > 0 && !call.signal?.aborted) {
          await this.#seatFreed(seatKey, call.signal);
          continue;
        }
        if (call.signal?.aborted || waited + wait.delayMs > wait.maxWaitMs) {
          this.#rec({ ...base, event: "refuse", reason: `capacity ${d.reason}: ${d.detail}` });
          return { error: `conwip capacity refused (${d.reason}): ${d.detail}` };
        }
        await sleep(wait.delayMs);
        waited += wait.delayMs;
      }
    };

    // The decision must still hold at DISPATCH: a call that waited for a slot
    // is asked again once it has one, and gives the slot back on a refusal
    // (successor review 2026-09-23: an ADMIT taken before a 25-minute slot
    // wait let a call dispatch after the seat reached 100 percent).
    let refused = await capacity();
    if (refused) return refused;
    let hold: SlotHold | undefined;
    for (;;) {
      const waitedForSlot = this.#inUse >= this.opts.cap;
      if (!(await this.#acquire(call.signal))) {
        this.#rec({ ...base, event: "refuse", reason: "aborted while waiting for a slot" });
        return { error: "conwip: aborted while waiting for a slot" };
      }
      // The budget ceiling where the call is actually admitted to the runner
      // (successor review r3: calls that passed the interpreter's check
      // waited here for a slot and then ran after the budget was spent).
      const spent = call.budgetExhausted?.();
      if (spent !== undefined) {
        this.#releaseSlot();
        this.#rec({ ...base, event: "refuse", reason: `budget: ${spent}` });
        return { error: spent, budgetExhausted: true };
      }
      if (call.signal?.aborted) {
        this.#releaseSlot();
        this.#rec({ ...base, event: "refuse", reason: "aborted before dispatch" });
        return { error: "conwip: aborted before dispatch" };
      }
      if (gate === undefined) break;
      // A slot seat: take a machine-wide hold before dispatch. Held by another
      // process: give the WIP slot back and wait like any capacity refusal.
      // A remote source's answer may have aged past its bound during the slot
      // wait; fetch again so the slot count is read, not missed.
      if (this.opts.machineSlots !== undefined) await gate.refresh?.(item.model, this.#nowMs(), seat ?? gate.seatId);
      const slotRead = this.opts.machineSlots !== undefined ? gate.slotStatus(seat ?? gate.seatId) : ({ kind: "none" } as const);
      // An unreadable source is never "not a slot seat": no hold, no dispatch
      // (successor review r5). Give the WIP slot back and wait, then refuse.
      if (slotRead.kind === "unreadable") {
        this.#releaseSlot();
        if (call.signal?.aborted || waited + wait.delayMs > wait.maxWaitMs) {
          this.#rec({ ...base, event: "refuse", reason: `capacity unreadable: the slot count for ${seatKey} could not be read (${slotRead.reason})` });
          return { error: `conwip capacity refused (unreadable): the slot count for ${seatKey} could not be read (${slotRead.reason})` };
        }
        await sleep(wait.delayMs);
        waited += wait.delayMs;
        continue;
      }
      const slotCap = slotRead.kind === "slots" ? slotRead.capacity : undefined;
      if (slotCap !== undefined) {
        hold = await this.opts.machineSlots!.take(seatKey, slotCap);
        if (hold === undefined) {
          this.#releaseSlot();
          if (call.signal?.aborted || waited + wait.delayMs > wait.maxWaitMs) {
            this.#rec({ ...base, event: "refuse", reason: `capacity slots-full: every ${seatKey} slot is held machine-wide by another process` });
            return { error: `conwip capacity refused (slots-full): every ${seatKey} slot is held machine-wide by another process` };
          }
          await sleep(wait.delayMs);
          waited += wait.delayMs;
          continue;
        }
      }
      // A slot seat is always asked again with this CONWIP's own in-flight
      // count for it; a metered seat only when the call waited for a slot.
      if (!waitedForSlot && (this.#seatInflight.get(seatKey) ?? 0) === 0) {
        if (hold !== undefined) admitted += `; machine slot ${hold.path}`;
        break;
      }
      await gate.refresh?.(item.model, this.#nowMs(), seat ?? gate.seatId);
      const d = gate.decide(item.model, this.#nowMs(), seat ?? gate.seatId, gateCtx());
      if (d.kind === "ADMIT") {
        admitted = `capacity ADMIT ${d.detail} (re-checked at dispatch)`;
        break;
      }
      await hold?.release();
      hold = undefined;
      this.#releaseSlot();
      this.#rec({ ...base, event: "release", reason: `capacity changed while waiting for a slot: ${d.reason}` });
      refused = await capacity();
      if (refused) return refused;
    }
    this.#rec({ ...base, event: "admit", reason: `phase ${item.phaseIndex}, attempt ${call.attempt}, ${built.route} prompt, model ${item.model}${where}; ${admitted}` });
    this.#seatInflight.set(seatKey, (this.#seatInflight.get(seatKey) ?? 0) + 1);
    try {
      this.#rec({ ...base, event: "dispatch", reason: `runner ${this.opts.runner.name}` });
      let out: AgentOutcome;
      try {
        out = await this.opts.runner.run(built.task, item, call);
      } catch (e) {
        out = { error: `runner threw: ${(e as Error).message}` };
      }
      this.#rec({ ...base, event: "outcome", reason: out.error === undefined ? "ok" : `error: ${out.error.slice(0, 200)}` });
      return out;
    } finally {
      await hold?.release();
      this.#seatInflight.set(seatKey, (this.#seatInflight.get(seatKey) ?? 1) - 1);
      for (const w of [...(this.#seatWaiters.get(seatKey) ?? [])]) w();
      this.#releaseSlot();
      this.#rec({ ...base, event: "release", reason: "runner answered" });
    }
  }
}
