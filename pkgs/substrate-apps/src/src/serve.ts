/**
 * `serve`: the CONWIP as the long-running service the dotfiles module declares.
 *
 *   tsx src/serve.ts --records <dir> [--addr host:port] [--cap N] [--meters <dir>]
 *                    [--seat <id>] [--poll-interval-ms MS] [--max-ticks N]
 *                    [--staleness-bound-seconds S] [--live] [--print-flags]
 *
 * This is a NEW entry point rather than a flag on `src/cli.ts`, for the three
 * reasons `src/e2e-live.ts` gave: a long-running process has a different
 * failure surface from a batch run; `src/cli.ts` must stay unable to dispatch
 * anything, so a typo on the ordinary command line cannot become a live
 * dispatch; and one way in is reviewable where a flag matrix is not.
 * `src/cli.ts` is not edited by this item and does not import this module.
 *
 * Dispatch is DRY RUN by default. The live path is gated three ways: `--live`,
 * then AX_CONWIP_LIVE_HALOGEN=1 through `assertLiveEnabled` (reused from
 * `src/live.ts`, not reimplemented), then the seat's membership of
 * `DEFAULT_LIVE_SPAWN_SEATS`, which is ["halogen"]. All three are checked at
 * startup, so a watcher that would refuse later never starts.
 *
 * The engine below is exported and takes an injected client, so a test drives
 * ticks without a socket. The `main` at the bottom runs only when this file is
 * the process entry point, which is how a test can import the engine without
 * the top level parsing argv and exiting.
 */
import { existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AxClient, type AxTask } from "./axclient.ts";
import { HALOGEN_MODEL, procStartTicks, sameProcess } from "@substrate/runners";
import {
  SEAT_LEDGER_KEYS,
  SPAWN_LEDGER_KEYS,
  SeatLedger,
  type LedgerSink,
  type SeatLedgerEntry,
  type SpawnLedgerEntry,
} from "./dispatch.ts";
import { JsonlSink, defaultLedgerPath } from "./jsonl.ts";
import { AppendOnlyLog, LEDGER_KEYS, Ledger, type LedgerEntry } from "./ledger.ts";
import {
  SUGGESTED_CHILD_TIMEOUT_MS,
  SUGGESTED_STALENESS_BOUND_SECONDS,
  SUGGESTED_WRAPPER_TIMEOUT_SECONDS,
  assertLiveEnabled,
  makeHalogenOutcomeOf,
} from "./live.ts";
import { DEFAULT_HOLD_BUDGET, defaultSleep, dependencyStatus, itemKey, taskNameFor, type HoldBudget, type ItemState } from "./loop.ts";
import { buildTask } from "./taskspec.ts";
/** gRPC NOT_FOUND (code 5), or a fake's "not found": the Task was never posted. */
function isNotFound(e: unknown): boolean {
  const x = e as { code?: unknown; message?: unknown };
  if (x?.code === 5) return true;
  if (typeof x?.code === "number") return false;
  return typeof x?.message === "string" && /\bnot[ _]found\b/i.test(x.message);
}
/** The ax Task is run by ultracode-agent's claude: pinned by full id, whatever the record's model was (successor review r3). */
const TASK_MODEL = "claude-opus-5-5";
/**
 * The model a Task posted for `seat` runs, and the harness that spends it
 * (successor review r4: on seat halogen serve posted claude-opus-5-5 Tasks,
 * admitted on the Halogen slot row, while the halogen adapter runs Halogen).
 * Halogen's pinned id comes from runners harness.ts HALOGEN_MODEL.
 */
export function taskRouteForSeat(seat: string): { readonly model: string; readonly harness: "ax" | "pi" } {
  return seat === "halogen" ? { model: HALOGEN_MODEL, harness: "pi" } : { model: TASK_MODEL, harness: "ax" };
}

/**
 * The mark a watcher posts on a Task (status.actor) before its outcomeOf
 * dispatches anything: this process's pid and start time.
 */
const WATCHER_PREFIX = "substrate-serve:";
/** Errors thrown by the outcomeOf hook: they leave tick(), unlike ax errors. */
const FROM_OUTCOME = new WeakSet<object>();
const WATCHER_MARK = () => `${WATCHER_PREFIX}${process.pid}:${procStartTicks(process.pid) ?? "?"}`;
/** A Task carrying another watcher's mark whose process is gone. */
function deadWatcherMark(actor: string | undefined): boolean {
  if (actor === undefined || !actor.startsWith(WATCHER_PREFIX)) return false;
  const [pid, start] = actor.slice(WATCHER_PREFIX.length).split(":");
  const n = Number(pid);
  if (!Number.isInteger(n) || n <= 0) return true;
  if (n === process.pid && start === procStartTicks(process.pid)) return false;
  return !sameProcess(n, start);
}
import { evaluateMeter, readMeterRow, type MeterBounds, type MeterRead } from "./meter.ts";
import { CapacityGate, type GateDecision } from "./capacity/gate.ts";
import { capacitySourceFrom, configuredFloorSource, defaultCapacitySource } from "./capacity/config.ts";
import type { CapacitySource } from "./capacity/source.ts";
import { deriveOnly } from "./derive-only.ts";

/** What the tick-level gate said: the legacy meter rule's answer or the capacity gate's. */
export type ServeGateDecision =
  | { readonly kind: "ADMIT"; readonly detail: string }
  | { readonly kind: "REFUSE"; readonly reason: string; readonly detail: string };
import { deriveFromFile } from "./record.ts";
import { evaluateRelease, type Reading, type SlotState } from "./release.ts";
import {
  DEFAULT_LIVE_SPAWN_SEATS,
  METERS_DIR,
  ccAdapter,
  codexAdapter,
  executeDispatch,
  halogenAdapter,
  renderArgv,
  type SeatAdapter,
} from "./seats.ts";
import { fixtureOutcome, type WorkItem } from "./schema.ts";
import { MachineSlots, type SlotHold } from "./slots.ts";

/**
 * The accepted flag names, one per line under `--print-flags`.
 *
 * This list exists so that the dotfiles module's rendered `ExecStart` can be
 * checked against the program by MEASUREMENT rather than by reading. It is two
 * lines of behaviour and it is the whole of `--print-flags`.
 */
export const SERVE_FLAGS: readonly string[] = [
  "--records",
  "--addr",
  "--cap",
  "--meters",
  "--seat",
  "--poll-interval-ms",
  "--max-ticks",
  "--staleness-bound-seconds",
  "--live",
  "--print-flags",
  "--derive-only",
  "--capacity-snapshot",
  "--capacity-floor",
];

export const SERVE_USAGE =
  "usage: serve.ts --records <dir> [--addr host:port] [--cap N] [--meters <dir>]" +
  " [--seat <id>] [--poll-interval-ms MS] [--max-ticks N]" +
  " [--staleness-bound-seconds S] [--live] [--print-flags] [--derive-only]" +
  " [--capacity-snapshot <seat-capacity/2 file> | --capacity-floor <url>]";

/** Defaults. Every one of them is data at the call site, never derived here. */
export const DEFAULT_ADDR = "127.0.0.1:8080";
export const DEFAULT_CAP = 1;
export const DEFAULT_SEAT = "halogen";
export const DEFAULT_POLL_INTERVAL_MS = 2000;
export const DEFAULT_IMAGE = "substrate/placeholder:v1";
export const DEFAULT_MAX_READING_AGE_MS = 60_000;
export const DEFAULT_WATCH_TIMEOUT_MS = 5_000;
/** How long the startup probe waits for the ax server before giving up. */
export const STARTUP_PROBE_MS = 5_000;

/**
 * The bounds each seat is admitted under, as data, copied from the same table
 * `src/seats-cli.ts` declares. `halogen` declares a slot row of capacity one
 * and NO budget row, so a missing budget figure is not a refusal for it.
 */
export const SEAT_BOUNDS: Readonly<Record<string, MeterBounds>> = {
  cc: { stalenessBoundSeconds: SUGGESTED_STALENESS_BOUND_SECONDS, utilizationField: "weekly_utilization_pct", capPct: 95 },
  codex: { stalenessBoundSeconds: SUGGESTED_STALENESS_BOUND_SECONDS, utilizationField: "utilization_pct", capPct: 90 },
  halogen: { stalenessBoundSeconds: SUGGESTED_STALENESS_BOUND_SECONDS, utilizationField: "none", capPct: null },
};

/** The run log: a FOURTH representation, with its own key list. */
export interface ServeLedgerEntry {
  readonly seq: number;
  readonly event: "start" | "tick" | "stop";
  readonly at: string;
  readonly tick: number;
  readonly cap: number;
  readonly slotsInUse: number;
  readonly filesDerived: number;
  readonly admitted: number;
  readonly released: number;
  readonly refused: number;
  readonly reason: string;
}

/**
 * Its own key list rather than extra columns on an existing log. The item 11
 * ledger's key order is a pinned format contract, the seat log of item 12 is
 * one too, and the spawn log of item 26 is a third. A `stop` line has no column
 * in any of them, so this item declares a fourth rather than widening a first.
 */
export const SERVE_LEDGER_KEYS = [
  "seq",
  "event",
  "at",
  "tick",
  "cap",
  "slotsInUse",
  "filesDerived",
  "admitted",
  "released",
  "refused",
  "reason",
] as const;

/** Everything the engine needs from an ax client. A fake satisfies it. */
export interface ServeClient {
  readonly atespace: string;
  updateTask(task: AxTask): Promise<AxTask>;
  getTask(name: string): Promise<AxTask>;
  watchTaskToEnd(name: string, timeoutMs: number): Promise<unknown>;
}

export interface ServeOptions {
  readonly recordsDir: string;
  readonly client: ServeClient;
  readonly adapter: SeatAdapter;
  readonly bounds: MeterBounds;
  /** The cap. It holds for the LIFE OF THE PROCESS, not per tick. */
  readonly cap: number;
  readonly image?: string;
  readonly maxReadingAgeMs?: number;
  readonly watchTimeoutMs?: number;
  /** Absent, dispatch is dry run and nothing is executed. */
  readonly outcomeOf?: (item: WorkItem) => Promise<{ readonly phase: "Completed" | "Failed"; readonly reason: string }>;
  /**
   * Machine-wide slot holds (the same flock files conwip-run takes). On a slot
   * seat (halogen) an item is admitted only with a hold, kept until it is
   * released or refused (successor review r5: serve dispatched while a
   * conwip-run held the one Halogen slot).
   */
  readonly machineSlots?: MachineSlots;
  /** Machine-wide slot count for the seat. Default 1 (Halogen's one slot). */
  readonly machineSlotCapacity?: number;
  readonly now?: () => string;
  readonly nowMs?: () => number;
  readonly print?: (line: string) => void;
  /** Injected so a test drives ticks over a fabricated directory. */
  readonly listRecords?: () => readonly string[];
  readonly deriveFile?: (path: string) => ReturnType<typeof deriveFromFile>;
  /** Injected so a test supplies a fabricated meter row without a fixture tree. */
  readonly readFile?: (p: string) => string;
  /**
   * OI-2/OI-3: the fail-closed capacity gate. Present, it REPLACES the legacy
   * meter rule: the tick asks it about the seat (model null), and every item is
   * asked again for its own model, so a scoped Fable row at 100 percent holds
   * Fable items pending while Opus items on the same seat go ahead.
   */
  readonly capacity?: CapacityGate;
  readonly loopSink?: LedgerSink<LedgerEntry>;
  readonly seatSink?: LedgerSink<SeatLedgerEntry>;
  readonly runSink?: LedgerSink<ServeLedgerEntry>;
}

/**
 * The watcher.
 *
 * `runLoop` could NOT be reused as is, and the reason is structural rather than
 * cosmetic. `runLoop` takes its whole item set up front and drives it to
 * quiescence inside a `while (progressed)` before it returns, so its slot
 * counter cannot outlive one call: at every boundary where serve would decide
 * whether to admit, `runLoop` has already released everything. Serve discovers
 * items over time and must hold a slot ACROSS ticks, including across a tick in
 * which the release rule says HOLD. So the accounting lives here, over the same
 * pure rules `runLoop` uses and over its exported helpers (`itemKey`,
 * `taskNameFor`, `taskFor`, `dependencyStatus`), and `src/loop.ts` is not
 * touched: every existing test stays green and a run with no `outcomeOf` still
 * produces the ledger bytes it produced before this item.
 */
export class Serve {
  readonly loopLedger = new Ledger();
  readonly seatLedger = new SeatLedger();
  readonly runLedger = new AppendOnlyLog<ServeLedgerEntry>([...SERVE_LEDGER_KEYS]);

  /** Absolute paths already derived. A file is derived ONCE, ever. */
  readonly derivedPaths = new Set<string>();
  readonly states = new Map<string, ItemState>();

  #slotsInUse = 0;
  #ticks = 0;
  /** Built at admission (FM-2), sent at dispatch. */
  readonly #tasks = new Map<string, AxTask>();
  #admitted = 0;
  #released = 0;
  #refused = 0;
  #lastMeterRead: MeterRead | undefined;
  #lastMeterDecision: ServeGateDecision | undefined;

  constructor(private readonly opts: ServeOptions) {
    // A-03 of the 2026-09-23 review. `--cap notanumber` produced NaN, and
    // `slotsInUse + n >= NaN` is false for every n, so the process-wide cap
    // silently stopped existing and every pending item was admitted at once.
    // The cap is the whole invariant of a CONWIP: an unreadable one is refused.
    if (!Number.isFinite(opts.cap) || opts.cap < 0) {
      throw new Error(`cap must be a finite number of zero or more, got ${String(opts.cap)}`);
    }
  }

  get slotsInUse(): number { return this.#slotsInUse; }
  get ticks(): number { return this.#ticks; }
  get admitted(): number { return this.#admitted; }
  get released(): number { return this.#released; }
  get refused(): number { return this.#refused; }
  get filesDerived(): number { return this.derivedPaths.size; }
  get lastMeterRead(): MeterRead | undefined { return this.#lastMeterRead; }
  get lastMeterDecision(): ServeGateDecision | undefined { return this.#lastMeterDecision; }

  #now(): string { return (this.opts.now ?? (() => new Date().toISOString()))(); }
  #nowMs(): number { return (this.opts.nowMs ?? (() => Date.now()))(); }
  #print(line: string): void { (this.opts.print ?? ((l: string) => console.log(l)))(line); }

  #recLoop(e: Omit<LedgerEntry, "seq">): void {
    const entry = this.loopLedger.append(e);
    this.opts.loopSink?.append(entry);
  }
  #recSeat(e: Omit<SeatLedgerEntry, "seq">): void {
    const entry = this.seatLedger.append(e);
    this.opts.seatSink?.append(entry);
  }
  #recRun(e: Omit<ServeLedgerEntry, "seq">): void {
    const entry = this.runLedger.append(e);
    this.opts.runSink?.append(entry);
  }

  /** The `start` line, written once before the first tick. */
  start(reason: string): void {
    this.#recRun({
      event: "start", at: this.#now(), tick: 0, cap: this.opts.cap,
      slotsInUse: this.#slotsInUse, filesDerived: 0,
      admitted: 0, released: 0, refused: 0, reason,
    });
  }

  /** The `stop` line, written once on the way out. */
  stop(reason: string): void {
    this.#recRun({
      event: "stop", at: this.#now(), tick: this.#ticks, cap: this.opts.cap,
      slotsInUse: this.#slotsInUse, filesDerived: this.derivedPaths.size,
      admitted: this.#admitted, released: this.#released, refused: this.#refused, reason,
    });
  }

  /**
   * List the records directory and derive every file not seen before.
   *
   * ONCE ONLY, keyed by absolute path. A file that appears, is derived and then
   * changes on disk is NOT re-derived: re-deriving on an mtime change would
   * re-admit work that may already be running, and a run record is written once
   * by its producer. See DESIGN.md section 17.
   */
  #scan(): number {
    const names = this.opts.listRecords
      ? this.opts.listRecords()
      : readdirSync(this.opts.recordsDir).filter((f) => f.startsWith("wf_") && f.endsWith(".json")).sort();
    const derive = this.opts.deriveFile ?? deriveFromFile;
    let newFiles = 0;
    for (const name of [...names].sort()) {
      const abs = resolve(this.opts.recordsDir, name);
      if (this.derivedPaths.has(abs)) continue;
      // Recorded BEFORE the derive, so a file that cannot be read is attempted
      // once and never retried, and a directory holding one bad record does not
      // become a tight loop.
      this.derivedPaths.add(abs);
      newFiles++;
      // A-04 of the 2026-09-23 review. An uncaught throw here left `tick()`
      // rejecting, which took the watcher down through `runTick`'s catch: ONE
      // unparsable file in the records directory stopped the whole service. A
      // bad record is a diagnostic about that record and nothing more.
      let d: ReturnType<typeof deriveFromFile>;
      try {
        d = derive(abs);
      } catch (e) {
        this.#print(`SCAN file=${name} SKIPPED: ${(e as Error).message}`);
        continue;
      }
      this.#print(
        `SCAN file=${name} runId=${d.summary.runId} status=${d.summary.status}` +
          ` items=${d.items.length} resolved=${d.items.filter((i) => i.promptResolved).length}`,
      );
      for (const item of d.items) {
        const key = itemKey(item);
        if (this.states.has(key)) continue;
        this.states.set(key, { item, key, taskName: taskNameFor(item), disposition: "pending" });
        this.#recLoop({
          event: "derive", at: this.#now(), runId: item.runId, label: item.label,
          taskName: taskNameFor(item), cap: this.opts.cap, slotsInUse: this.#slotsInUse,
          reason: item.promptResolved
            ? `prompt ${item.prompt.length} chars, phase ${item.phaseIndex}`
            : `prompt unresolved: ${item.promptUnresolvedReason ?? "unknown"}`,
        });
      }
    }
    return newFiles;
  }

  /**
   * Read the seat's meter row and let the PURE rule decide, once per tick,
   * BEFORE any admission. A REFUSE admits nothing this tick and takes no slot:
   * pending items stay pending and the next tick reads the row again, so a row
   * that goes stale between feeder writes costs throughput and never a slot.
   *
   * Nothing under the meters directory is written. `readMeterRow` opens the
   * file and `assertLedgerPathAllowed` refuses to put a ledger anywhere under
   * it, which is what makes the unit's AX_CONWIP_METERS meaningful without
   * making it writable.
   */
  #meterDecision(): ServeGateDecision {
    if (this.opts.capacity !== undefined) {
      const g = this.opts.capacity.decide(null, this.#nowMs());
      const decision: ServeGateDecision =
        g.kind === "ADMIT" ? { kind: "ADMIT", detail: g.detail } : { kind: "REFUSE", reason: g.reason, detail: g.detail };
      this.#lastMeterDecision = decision;
      this.#recSeat({
        event: "meter", seat: this.opts.adapter.seatId, runId: "", label: "",
        cap: this.opts.cap, seatsInUse: this.#slotsInUse,
        reason: decision.kind === "ADMIT" ? "ADMIT" : decision.reason,
        detail: `${this.opts.capacity.source.name}: ${decision.detail}`,
        argv: "",
      });
      return decision;
    }
    const read = readMeterRow(this.opts.adapter.meterPath, {
      // gpu-worker.json and codex.json carry no `reading_age_seconds` and both
      // carry `observed_at`, so the age is derived from the file itself rather
      // than assumed. This is the only place a clock enters the meter path.
      deriveAgeFromObservedAtMs: this.#nowMs(),
      readFile: this.opts.readFile,
    });
    const decision = evaluateMeter(read.row, this.opts.bounds);
    this.#lastMeterRead = read;
    this.#lastMeterDecision = decision;
    this.#recSeat({
      event: "meter", seat: this.opts.adapter.seatId, runId: "", label: "",
      cap: this.opts.cap, seatsInUse: this.#slotsInUse,
      reason: decision.kind === "ADMIT" ? "ADMIT" : decision.reason,
      detail: `${read.path}: ${read.error ?? decision.detail}`,
      argv: "",
    });
    return decision;
  }

  /**
   * One tick: scan, RELEASE what finished, read the meter, then admit under
   * the process-wide cap.
   *
   * Release runs BEFORE admission, deliberately. `runLoop` admits first and
   * releases second, but it sits inside a `while (progressed)` that comes
   * straight back round and admits into the slot it just freed. Serve has no
   * inner loop, so admitting first would leave a slot that came free in this
   * tick idle until the NEXT poll interval: one whole `--poll-interval-ms` of
   * dead time on every handoff. The cap is never exceeded either way; this
   * order simply does not waste the slot.
   */
  async tick(): Promise<void> {
    this.#ticks++;
    const newFiles = this.#scan();
    await this.#reconcile();
    await this.#releasePass();
    // A remote capacity source (the floor) fetches here, once per tick, for
    // the seat-level question and for the model this seat's Tasks run; a
    // local source is untouched. The decisions below stay synchronous.
    if (this.opts.capacity !== undefined) {
      const nowMs = this.#nowMs();
      await this.opts.capacity.refresh?.(null, nowMs);
      await this.opts.capacity.refresh?.(taskRouteForSeat(this.opts.adapter.seatId).model, nowMs);
    }
    const decision = this.#meterDecision();

    if (decision.kind === "ADMIT") {
      await this.#admissionPass();
    } else {
      this.#print(
        `METER REFUSE seat=${this.opts.adapter.seatId} ${decision.reason}: ${decision.detail}` +
          ` (slots stay free, slotsInUse=${this.#slotsInUse})`,
      );
    }

    this.#recRun({
      event: "tick", at: this.#now(), tick: this.#ticks, cap: this.opts.cap,
      slotsInUse: this.#slotsInUse, filesDerived: this.derivedPaths.size,
      admitted: this.#admitted, released: this.#released, refused: this.#refused,
      reason: `newFiles ${newFiles}, meter ${decision.kind === "ADMIT" ? "ADMIT" : decision.reason}`,
    });
    this.#print(
      `TICK ${this.#ticks} newFiles=${newFiles} pending=${this.#count("pending")}` +
        ` slotsInUse=${this.#slotsInUse}/${this.opts.cap} admitted=${this.#admitted}` +
        ` released=${this.#released} refused=${this.#refused}`,
    );
  }

  #count(d: ItemState["disposition"]): number {
    let n = 0;
    for (const st of this.states.values()) if (st.disposition === d) n++;
    return n;
  }

  /** Per-item capacity: asked once per model per pass, refusals logged once per model. */
  #itemGate(item: WorkItem, cache: Map<string, GateDecision>): GateDecision | undefined {
    const gate = this.opts.capacity;
    if (gate === undefined) return undefined;
    // The Task runs its seat's pinned model, so that is the model gated, and
    // the seat must be one that model's harness spends (successor review r4: serve gated
    // the record's model, and a halogen seat admitted Opus Tasks).
    const route = taskRouteForSeat(this.opts.adapter.seatId);
    const hit = cache.get(route.model);
    if (hit !== undefined) return hit;
    const d = gate.decide(route.model, this.#nowMs(), gate.seatId, { harness: route.harness });
    cache.set(route.model, d);
    if (d.kind === "REFUSE") {
      this.#recSeat({
        event: "refuse", seat: this.opts.adapter.seatId, runId: item.runId, label: item.label,
        cap: this.opts.cap, seatsInUse: this.#slotsInUse,
        reason: d.reason, detail: `Task model ${route.model} (record model ${item.model}): ${d.detail} (items stay pending)`, argv: "",
      });
    }
    return d;
  }

  /** Items already read against ax once (see #reconcile). */
  readonly #reconciled = new Set<string>();
  /** Items found running in ax at start: held, read back, never dispatched by this process. */
  readonly #adopted = new Set<string>();

  /**
   * A restart re-derives every item as pending (successor review r2: an item
   * whose ax Task was already Completed was dispatched a second time). Before
   * an item is first considered, its Task is read: a terminal Task is released
   * as it stands, a running one is adopted and holds a slot, and only an
   * absent or never-started Task goes through admission.
   */
  async #reconcile(): Promise<void> {
    for (const st of this.states.values()) {
      if (st.disposition !== "pending" || this.#reconciled.has(st.key)) continue;
      let phase = "";
      let actor: string | undefined;
      try {
        const t = await this.opts.client.getTask(st.taskName);
        phase = t.status?.phase ?? "";
        actor = t.status?.actor;
      } catch (e) {
        // Only NOT_FOUND means "no Task yet". Any other error (UNAVAILABLE, a
        // dropped tunnel) leaves the item unreconciled: it is read again next
        // tick and is not admitted until one read succeeds (successor review
        // r3: a transient error at start re-dispatched a Completed Task).
        if (isNotFound(e)) this.#reconciled.add(st.key);
        continue;
      }
      this.#reconciled.add(st.key);
      // Terminating releases, as CONWIP_RELEASING_PHASES does.
      if (phase === "Completed" || phase === "Failed" || phase === "Terminating") {
        st.disposition = "released";
        this.#released++;
        this.#recLoop({
          event: "release", at: this.#now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
          reason: `already terminal at start: ${phase} (not dispatched again)`,
        });
      } else if (phase === "Running" && deadWatcherMark(actor)) {
        // A watcher marked this Task Running before its outcomeOf dispatched,
        // then died (kill -9, a crash): the call may have run, or may still
        // be running. It is never dispatched again (successor review r4: the
        // restart ran it a second time); the Task is closed as Failed with
        // "outcome unknown" and its slot is not taken.
        st.disposition = "released";
        this.#released++;
        try {
          const t = await this.opts.client.getTask(st.taskName);
          await this.opts.client.updateTask({ ...t, metadata: { name: st.taskName, atespace: this.opts.client.atespace }, status: { ...(t.status ?? {}), phase: "Failed" } });
        } catch {
          /* the ledger line below still says what happened */
        }
        this.#recLoop({
          event: "release", at: this.#now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
          reason: `outcome unknown: the watcher that dispatched it (${actor}) is gone; not dispatched again, closed Failed`,
        });
      } else if (phase === "Running" || phase === "Suspended") {
        // Only a Task some runner is driving is adopted. Pending (ax's phase
        // on create) or no phase means this watcher posted it and was stopped
        // before its outcomeOf ran it: nothing else will ever run it, so it
        // goes back through admission under the same Task name (successor
        // review r3: an adopted Pending Task held its slot forever).
        st.disposition = "admitted";
        this.#adopted.add(st.key);
        this.#slotsInUse++;
        this.#admitted++;
        this.#recLoop({
          event: "admit", at: this.#now(), runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
          reason: `already ${phase} at start: adopted, holds a slot, not dispatched again`,
        });
      }
    }
  }

  #holds = new Map<string, SlotHold>();
  async #dropHold(key: string): Promise<void> {
    const h = this.#holds.get(key);
    this.#holds.delete(key);
    await h?.release();
  }

  async #admissionPass(): Promise<void> {
    const admittedNow: ItemState[] = [];
    const gateCache = new Map<string, GateDecision>();
    for (const st of this.states.values()) {
      if (st.disposition !== "pending") continue;
      // Never admitted before its Task has been read once (see #reconcile).
      if (!this.#reconciled.has(st.key)) continue;

      // Refusals that cost no slot, in the same fixed order `runLoop` uses.
      if (st.item.sourceStatus === "killed") {
        this.#refuse(st, "source run record has status killed");
        continue;
      }
      if (!st.item.promptResolved) {
        this.#refuse(st, `prompt unresolved: ${st.item.promptUnresolvedReason ?? "unknown"}`);
        continue;
      }
      const dep = dependencyStatus(st.item, this.states);
      if (dep === "refused") {
        this.#refuse(st, `a dependency in phase ${st.item.phaseIndex - 1} was refused`);
        continue;
      }
      if (dep === "waiting") continue;

      // The cap, held process-wide. A full cap leaves the item PENDING for a
      // later tick rather than refusing it.
      if (this.#slotsInUse + admittedNow.length >= this.opts.cap) continue;
      // Capacity for THIS item's model. A refusal leaves it pending: capacity
      // comes back at a reset, a prompt does not.
      const g = this.#itemGate(st.item, gateCache);
      if (g !== undefined && g.kind === "REFUSE") continue;
      // FM-2: the size check runs before a slot is taken.
      const built = buildTask(st.item, this.opts.client.atespace, this.opts.image ?? DEFAULT_IMAGE, { seat: this.opts.adapter.seatId, model: taskRouteForSeat(this.opts.adapter.seatId).model });
      if (!built.ok) {
        this.#refuse(st, `task spec refused: ${built.reason}`);
        continue;
      }
      if (this.opts.machineSlots !== undefined && taskRouteForSeat(this.opts.adapter.seatId).harness === "pi") {
        const hold = await this.opts.machineSlots.take(this.opts.adapter.seatId, this.opts.machineSlotCapacity ?? 1);
        // Held by another process: the item stays pending, like a capacity refusal.
        if (hold === undefined) continue;
        this.#holds.set(st.key, hold);
      }
      this.#tasks.set(st.key, built.task);
      admittedNow.push(st);
    }

    for (const st of admittedNow) {
      st.disposition = "admitted";
      this.#slotsInUse++;
      this.#admitted++;
      this.#recLoop({
        event: "admit", at: this.#now(), runId: st.item.runId, label: st.item.label,
        taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
        reason: `phase ${st.item.phaseIndex} dependencies satisfied`,
      });

      const d = this.opts.adapter.render(st.item);
      this.#recSeat({
        event: "admit", seat: this.opts.adapter.seatId, runId: st.item.runId, label: st.item.label,
        cap: this.opts.cap, seatsInUse: this.#slotsInUse,
        reason: "admitted under the process-wide cap",
        detail: `${this.#lastMeterDecision?.detail ?? ""}`,
        argv: renderArgv(d),
      });

      // Dry run: `executeDispatch` prints the argv and the first 200 characters
      // of stdin and executes NOTHING. On the live path the one real dispatch
      // happens in the release pass, inside the `outcomeOf` hook, so there is
      // never a second one here.
      if (this.opts.outcomeOf === undefined) {
        const r = executeDispatch(this.opts.adapter, d, { mode: "dry-run", print: (l) => this.#print(l) });
        this.#recSeat({
          event: "dryrun", seat: this.opts.adapter.seatId, runId: st.item.runId, label: st.item.label,
          cap: this.opts.cap, seatsInUse: this.#slotsInUse,
          reason: "dry run: nothing executed",
          detail: `stdin ${d.stdin.length} chars, spawned ${String(r.spawned)}`,
          argv: renderArgv(d),
        });
      }

      await this.opts.client.updateTask(this.#tasks.get(st.key)!);
      this.#recLoop({
        event: "dispatch", at: this.#now(), runId: st.item.runId, label: st.item.label,
        taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
        reason: "UpdateTask",
      });
    }
  }

  #refuse(st: ItemState, reason: string): void {
    st.disposition = "refused";
    this.#refused++;
    this.#recLoop({
      event: "refuse", at: this.#now(), runId: st.item.runId, label: st.item.label,
      taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse, reason,
    });
  }

  /**
   * A-18 (track conwip-fixes, 2026-09-23): the drain on the way out. Up to
   * `budget.attempts` release passes, `delayMs` apart, over what is still
   * admitted; on the live path the drain starts NO new dispatch (it only reads
   * the Task back). Whatever is still held after that gets an `abandon` line
   * in the loop ledger, so a stop is never silent about a slot. Returns the
   * number abandoned.
   */
  async drain(budget: HoldBudget = DEFAULT_HOLD_BUDGET): Promise<number> {
    const sleep = budget.sleep ?? defaultSleep;
    const held = () => [...this.states.values()].filter((st) => st.disposition === "admitted");
    for (let i = 0; i <= budget.attempts && held().length > 0; i++) {
      if (i > 0) await sleep(budget.delayMs);
      await this.#releasePass({ drain: true });
    }
    const left = held();
    for (const st of left) {
      st.disposition = "abandoned";
      this.#recLoop({
        event: "abandon", at: this.#now(), runId: st.item.runId, label: st.item.label,
        taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
        reason: `stop: still not terminal after the drain (${budget.attempts} extra reads ${budget.delayMs} ms apart); the Task may still be running`,
      });
    }
    return left.length;
  }

  /** Outcomes already produced by outcomeOf whose post to ax has not landed yet: never produced twice. */
  readonly #produced = new Map<string, { readonly phase: "Completed" | "Failed"; readonly reason: string }>();

  async #releasePass(mode: { readonly drain?: boolean } = {}): Promise<void> {
    for (const st of this.states.values()) {
      if (st.disposition !== "admitted") continue;
      // An ax error on one item holds its slot for the next tick; it never
      // throws out of tick() (successor review r4: one UNAVAILABLE after the
      // outcome stopped the service, and the restart ran the call again).
      try {
        await this.#releaseOne(st, mode);
      } catch (e) {
        if (e !== null && typeof e === "object" && FROM_OUTCOME.has(e)) throw e;
        this.#print(`HOLD ${st.taskName}: ax error in the release pass, slot kept, retried next tick: ${(e as Error).message}`);
      }
    }
  }

  async #releaseOne(st: ItemState, mode: { readonly drain?: boolean }): Promise<void> {
    {
      await this.opts.client.watchTaskToEnd(st.taskName, this.opts.watchTimeoutMs ?? DEFAULT_WATCH_TIMEOUT_MS);
      // A drain on the live path never starts a dispatch: it only reads back.
      const readOnly = (mode.drain === true && this.opts.outcomeOf !== undefined) || this.#adopted.has(st.key);

      // Exactly the two arms `src/loop.ts` documents. Without a hook this is
      // the FIXTURE behaviour: the mock stack runs no ax-task-runner, so the
      // source record's HISTORICAL outcome is posted. That is honest in a
      // proof and it is labelled as fixture support wherever it is quoted.
      let outcome: "Completed" | "Failed" | undefined;
      if (readOnly) {
        outcome = undefined;
      } else if (this.opts.outcomeOf !== undefined) {
        let produced = this.#produced.get(st.key);
        if (produced === undefined) {
          // The watcher's mark goes on the Task BEFORE anything is spawned: a
          // restart finds Running with this mark and never dispatches again.
          const t = await this.opts.client.getTask(st.taskName);
          await this.opts.client.updateTask({
            ...t,
            metadata: { name: st.taskName, atespace: this.opts.client.atespace },
            status: { ...(t.status ?? {}), phase: "Running", actor: WATCHER_MARK() },
          });
          try {
            produced = await this.opts.outcomeOf(st.item);
          } catch (e) {
            // A refusal inside the dispatch hook (the live gates) still stops
            // the service: only ax errors are held for the next tick.
            if (e !== null && typeof e === "object") FROM_OUTCOME.add(e);
            throw e;
          }
          this.#produced.set(st.key, produced);
          this.#recLoop({
            event: "outcome", at: this.#now(), runId: st.item.runId, label: st.item.label,
            taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
            reason: `${produced.phase}: ${produced.reason}`,
          });
        }
        outcome = produced.phase;
      } else {
        outcome = fixtureOutcome(st.item);
      }

      const current = await this.opts.client.getTask(st.taskName);
      if (outcome !== undefined && (current.status?.phase ?? "") !== outcome) {
        await this.opts.client.updateTask({
          ...current,
          metadata: { name: st.taskName, atespace: this.opts.client.atespace },
          status: { ...(current.status ?? {}), phase: outcome },
        });
      }

      const observedAt = this.#now();
      const after = await this.opts.client.getTask(st.taskName);
      const reading: Reading = {
        taskName: st.taskName,
        phase: after.status?.phase ?? "",
        observedAt,
        action: "GET",
      };
      const state: SlotState = {
        runId: st.item.runId, label: st.item.label, taskName: st.taskName,
        asOf: this.#now(), maxReadingAgeMs: this.opts.maxReadingAgeMs ?? DEFAULT_MAX_READING_AGE_MS,
      };
      const decision = evaluateRelease(state, reading);
      if (decision.kind !== "HOLD") this.#produced.delete(st.key);
      if (decision.kind !== "HOLD") await this.#dropHold(st.key);
      if (decision.kind === "RELEASE") {
        st.disposition = "released";
        this.#slotsInUse--;
        this.#released++;
        this.#recLoop({
          event: "release", at: observedAt, runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse, reason: decision.reason,
        });
      } else if (decision.kind === "REFUSE") {
        st.disposition = "refused";
        this.#slotsInUse--;
        this.#refused++;
        this.#recLoop({
          event: "refuse", at: observedAt, runId: st.item.runId, label: st.item.label,
          taskName: st.taskName, cap: this.opts.cap, slotsInUse: this.#slotsInUse,
          reason: `release refused: ${decision.reason}`,
        });
      }
      // HOLD keeps the slot, ACROSS the tick boundary. That is the whole of
      // what "the cap holds for the life of the process" means.
    }
  }
}

/** Which adapter renders the dispatch, and which meter row gates it. */
/**
 * The process exit code for a stop with this reason.
 *
 * A-25 of the 2026-09-23 review. `stop` ended in `process.exit(0)`
 * unconditionally, so `stop("tick-failed")` -- the reason `runTick`'s catch
 * passes when a tick THREW -- exited with the same code a deliberate stop uses,
 * and a supervisor could not tell a crash from a clean shutdown. With
 * `Restart = no` the service is simply gone and the journal says exit 0.
 *
 * DESIGN section 17 already spends 2 (usage), 3 (the live gate) and 4 (connect
 * unreachable), so 1 is the free code and is the conventional "the program
 * failed". Every DELIBERATE reason -- a signal, a max-ticks stop -- keeps 0,
 * which is the thing dotfiles#413's halogen-switch fix cared about.
 */
export const TICK_FAILED_REASON = "tick-failed";

export function stopExitCode(reason: string): number {
  return reason === TICK_FAILED_REASON ? 1 : 0;
}

export function adapterForSeat(seat: string, metersDir: string, repoRoot: string): SeatAdapter {
  if (seat === "halogen") return halogenAdapter(join(metersDir, "gpu-worker.json"), SUGGESTED_WRAPPER_TIMEOUT_SECONDS);
  if (seat === "cc") return ccAdapter(join(metersDir, "cc.json"));
  if (seat === "codex") return codexAdapter(repoRoot, join(metersDir, "codex.json"));
  throw new Error(`unknown seat ${JSON.stringify(seat)}: known seats are halogen, cc, codex`);
}

/**
 * The three gates on `--live`, checked together at startup.
 *
 * Gate one is the flag itself. Gate two is AX_CONWIP_LIVE_HALOGEN=1, through
 * item 32's own `assertLiveEnabled`, which is reused rather than reimplemented.
 * Gate three is `DEFAULT_LIVE_SPAWN_SEATS`, which is ["halogen"]; nothing here
 * can widen it, and `makeHalogenOutcomeOf` passes no `allowSpawnSeats` either,
 * so `executeDispatch` enforces the same list again at the point of spawn.
 */
export function assertServeLiveAllowed(
  env: Readonly<Record<string, string | undefined>>,
  seat: string,
): void {
  assertLiveEnabled(env);
  if (!DEFAULT_LIVE_SPAWN_SEATS.includes(seat)) {
    throw new Error(
      `refusing to serve live on seat ${seat}: not on the live-spawn allow list` +
        ` [${DEFAULT_LIVE_SPAWN_SEATS.join(", ")}]`,
    );
  }
}

/* ------------------------------------------------------------------------ */
/* The thin main. It runs only when this file is the process entry point.    */
/* ------------------------------------------------------------------------ */

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1]! : fallback;
}
const flag = (name: string): boolean => process.argv.includes(`--${name}`);

async function main(): Promise<void> {
  if (flag("print-flags")) {
    for (const f of SERVE_FLAGS) console.log(f);
    process.exit(0);
  }

  const recordsDir = arg("records", "");
  // CR-08: derive offline, dial nothing. Checked before any other flag.
  if (flag("derive-only")) {
    if (recordsDir === "" || !existsSync(recordsDir)) {
      console.error(recordsDir === "" ? SERVE_USAGE : `refusing to derive: records directory does not exist: ${recordsDir}`);
      process.exit(2);
    }
    deriveOnly(recordsDir, (l) => console.log(l));
    process.exit(0);
  }
  const addr = arg("addr", DEFAULT_ADDR);
  const cap = Number(arg("cap", String(DEFAULT_CAP)));
  const metersDir = arg("meters", METERS_DIR);
  const seat = arg("seat", DEFAULT_SEAT);
  const pollIntervalMs = Number(arg("poll-interval-ms", String(DEFAULT_POLL_INTERVAL_MS)));
  const maxTicks = Number(arg("max-ticks", "0"));
  const stalenessBoundSeconds = Number(
    arg("staleness-bound-seconds", String(SUGGESTED_STALENESS_BOUND_SECONDS)),
  );
  const live = flag("live");

  // A-03 of the 2026-09-23 review. `Number("notanumber")` is NaN, and every
  // comparison against NaN is false, so an unreadable --cap defeated the cap
  // rather than being refused. Checked here, before anything is dialled.
  for (const [name, value, min] of [
    ["cap", cap, 0],
    ["poll-interval-ms", pollIntervalMs, 1],
    ["max-ticks", maxTicks, 0],
    ["staleness-bound-seconds", stalenessBoundSeconds, 0],
  ] as const) {
    if (!Number.isFinite(value) || value < min) {
      console.error(`refusing to serve: --${name} must be a number of ${min} or more, got ${JSON.stringify(arg(name, ""))}`);
      process.exit(2);
    }
  }

  if (recordsDir === "") {
    console.error(SERVE_USAGE);
    process.exit(2);
  }
  // The module's `recordsDir` default deliberately points at a path that does
  // not exist, so that an accidental enable fails legibly. A watcher that
  // silently polled a missing directory forever would defeat that.
  if (!existsSync(recordsDir)) {
    console.error(`refusing to serve: records directory does not exist: ${recordsDir}`);
    process.exit(2);
  }

  const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  let adapter: SeatAdapter;
  try {
    adapter = adapterForSeat(seat, metersDir, REPO_ROOT);
  } catch (e) {
    console.error((e as Error).message);
    process.exit(2);
    return;
  }
  const bounds: MeterBounds = {
    ...(SEAT_BOUNDS[seat] ?? SEAT_BOUNDS.halogen!),
    stalenessBoundSeconds,
  };

  // The live gate first: it refuses before any source is built or reached.
  if (live) {
    try {
      assertServeLiveAllowed(process.env, seat);
    } catch (e) {
      console.error((e as Error).message);
      process.exit(3);
    }
  }

  // OI-2/OI-3: admission goes through the fail-closed capacity gate. The floor
  // is the default (the substrate config's capacityFloorUrl, G4); a snapshot is
  // for offline runs; the tally meter adapter is read only when --meters is
  // passed explicitly, and is the only code that knows the feeder's files.
  const snapshotPath = arg("capacity-snapshot", "");
  const floorUrl = arg("capacity-floor", "");
  if (snapshotPath !== "" && floorUrl !== "") {
    console.error("refusing to serve: --capacity-snapshot and --capacity-floor are exclusive");
    process.exit(2);
  }
  let capacitySource: CapacitySource;
  try {
    capacitySource = snapshotPath !== ""
      ? capacitySourceFrom({ kind: "snapshot", path: snapshotPath, seatIds: { halogen: "gpu-worker" } })
      : floorUrl !== ""
        ? configuredFloorSource(floorUrl)
        : process.argv.includes("--meters")
          ? capacitySourceFrom({ kind: "meters", dir: metersDir })
          : defaultCapacitySource();
  } catch (e) {
    console.error(`refusing to serve: ${(e as Error).message}`);
    process.exit(2);
    return;
  }
  const capacity = new CapacityGate(capacitySource, seat, {
    dispatchMaxAgeSeconds: stalenessBoundSeconds,
    minHeadroomPct: bounds.capPct === null ? 0 : 100 - bounds.capPct,
  });

  const loopPath = defaultLedgerPath(REPO_ROOT, "serve-loop");
  const seatPath = defaultLedgerPath(REPO_ROOT, "serve-seat");
  const spawnPath = defaultLedgerPath(REPO_ROOT, "serve-spawn");
  const runPath = defaultLedgerPath(REPO_ROOT, "serve-run");

  console.log(`SERVE records=${recordsDir}`);
  console.log(`SERVE addr=${addr} cap=${cap} pollIntervalMs=${pollIntervalMs} maxTicks=${maxTicks}`);
  console.log(`SERVE seat=${seat} meters=${metersDir} meterPath=${adapter.meterPath}`);
  console.log(`SERVE bounds stalenessBoundSeconds=${bounds.stalenessBoundSeconds} utilizationField=${bounds.utilizationField} capPct=${String(bounds.capPct)}`);
  console.log(`SERVE capacity source=${capacitySource.name} dispatchMaxAgeSeconds=${capacity.policy.dispatchMaxAgeSeconds} minHeadroomPct=${capacity.policy.minHeadroomPct}`);
  console.log(`SERVE live=${live} (dry run by default; the live path needs --live, AX_CONWIP_LIVE_HALOGEN=1 and a seat on [${DEFAULT_LIVE_SPAWN_SEATS.join(", ")}])`);
  console.log(`LEDGER loop:  ${loopPath}`);
  console.log(`LEDGER seat:  ${seatPath}`);
  console.log(`LEDGER run:   ${runPath}`);
  if (live) console.log(`LEDGER spawn: ${spawnPath}`);

  const client = AxClient.connect(addr);

  // Fail fast when the server is unreachable. `Restart = no` in the unit means
  // a dead process is a fact to read in the journal rather than a thing to
  // paper over, and a reconnect loop is a decision with a Tom-shaped question
  // behind it: how long may a scheduler hold slots while its server is gone.
  try {
    await Promise.race([
      client.listTasks(1, 0),
      new Promise((_r, reject) =>
        setTimeout(() => reject(new Error(`no answer within ${STARTUP_PROBE_MS}ms`)), STARTUP_PROBE_MS),
      ),
    ]);
    console.log(`PROBE ax server at ${addr} answered ListTasks`);
  } catch (e) {
    console.error(`refusing to serve: ax server at ${addr} is unreachable: ${(e as Error).message}`);
    client.close();
    process.exit(4);
  }

  const outcomeOf = live
    ? makeHalogenOutcomeOf({
        adapter,
        stalenessBoundSeconds,
        spawnTimeoutMs: SUGGESTED_CHILD_TIMEOUT_MS,
        nowMs: () => Date.now(),
        print: (l) => console.log(l),
        seatSink: new JsonlSink<SeatLedgerEntry>(seatPath, [...SEAT_LEDGER_KEYS]),
        spawnSink: new JsonlSink<SpawnLedgerEntry>(spawnPath, [...SPAWN_LEDGER_KEYS]),
      })
    : undefined;

  const serve = new Serve({
    recordsDir,
    client,
    adapter,
    bounds,
    capacity,
    // A slot seat takes the same machine-wide holds conwip-run does (r5).
    ...(taskRouteForSeat(seat).harness === "pi" ? { machineSlots: new MachineSlots(process.env["AX_CONWIP_SLOT_DIR"] || undefined) } : {}),
    cap,
    outcomeOf,
    loopSink: new JsonlSink<LedgerEntry>(loopPath, [...LEDGER_KEYS]),
    seatSink: new JsonlSink<SeatLedgerEntry>(seatPath, [...SEAT_LEDGER_KEYS]),
    runSink: new JsonlSink<ServeLedgerEntry>(runPath, [...SERVE_LEDGER_KEYS]),
  });
  serve.start(`addr ${addr}, seat ${seat}, cap ${cap}, pollIntervalMs ${pollIntervalMs}, live ${String(live)}`);

  let timer: ReturnType<typeof setTimeout> | undefined;
  let inFlight: Promise<void> | undefined;
  let stopping = false;
  let stopped = false;

  /**
   * The stop path. It runs to completion rather than calling `process.exit`
   * from inside an async gap: the timer is cleared, a tick already in flight is
   * awaited, the client is closed, the `stop` line is appended and only then is
   * the process exited. `JsonlSink` flushes on every append, so nothing was
   * buffered, but the handler still has to finish for the stop line to exist.
   *
   * EXIT 0 on a deliberate stop. A signal-shaped 143 from a clean stop is the
   * bug dotfiles#413's halogen-switch fix already fought once on this fleet.
   */
  const stop = async (reason: string): Promise<void> => {
    if (stopped) {
      // A SECOND signal exits immediately, still 0: the first stop is already
      // committed and its ledger lines are already flushed.
      console.log(`SERVE second signal (${reason}), exiting immediately`);
      process.exit(0);
    }
    stopped = true;
    stopping = true;
    if (timer !== undefined) clearTimeout(timer);
    if (inFlight !== undefined) {
      try { await inFlight; } catch (e) { console.error(`SERVE tick in flight failed: ${(e as Error).message}`); }
    }
    // A-18: drain what is still admitted before the stop line, bounded.
    try {
      const abandoned = await serve.drain();
      if (abandoned > 0) console.log(`SERVE drain abandoned=${abandoned} (see the loop ledger's abandon lines)`);
    } catch (e) {
      console.error(`SERVE drain failed: ${(e as Error).message}`);
    }
    try { client.close(); } catch { /* closing a closed client is not a failure */ }
    serve.stop(reason);
    const code = stopExitCode(reason);
    console.log(
      `SERVE stop reason=${reason} ticks=${serve.ticks} filesDerived=${serve.filesDerived}` +
        ` admitted=${serve.admitted} released=${serve.released} refused=${serve.refused}` +
        ` slotsInUse=${serve.slotsInUse} exit=${code}`,
    );
    process.exit(code);
  };

  const runTick = async (): Promise<void> => {
    if (stopping) return;
    inFlight = serve.tick();
    try {
      await inFlight;
    } catch (e) {
      console.error(`SERVE tick failed: ${(e as Error).message}`);
      inFlight = undefined;
      await stop(TICK_FAILED_REASON);
      return;
    }
    inFlight = undefined;
    if (maxTicks > 0 && serve.ticks >= maxTicks) {
      await stop(`max-ticks ${maxTicks} reached`);
      return;
    }
    if (!stopping) timer = setTimeout(() => void runTick(), pollIntervalMs);
  };

  process.on("SIGTERM", () => { void stop("SIGTERM"); });
  process.on("SIGINT", () => { void stop("SIGINT"); });

  await runTick();
}

/**
 * Run `main` only when this file IS the entry point. Under vitest
 * `process.argv[1]` is the test runner, so importing this module for the engine
 * parses no argv and exits nothing.
 */
const entry = process.argv[1];
if (entry !== undefined && resolve(entry) === fileURLToPath(import.meta.url)) {
  await main();
}
