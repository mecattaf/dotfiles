/**
 * Seat declarations, and the dry-run dispatch pass that gates them on their
 * own meter row.
 *
 * The shape here is deliberate and is the whole point of item 12:
 *
 *   adapter  (seats.ts)  knows the command line and nothing about budgets.
 *   bounds   (meter.ts)  are data: the staleness bound, which utilization
 *                        figure this seat is capped on, and the cap itself.
 *   rule     (meter.ts)  is pure, and sees only the parsed row and the bounds.
 *
 * So a seat is declared, not special-cased. An empty meters directory is not
 * an open door: a seat that declares no row simply defers the items that need
 * it, and there is no exception table anywhere in this file.
 */
import { AppendOnlyLog } from "./ledger.ts";
import {
  evaluateMeter,
  readMeterRow,
  type MeterBounds,
  type MeterRead,
  type MeterRefusalReason,
  type NormalizeOptions,
} from "./meter.ts";
import type { WorkItem } from "./schema.ts";
import {
  executeDispatch,
  renderArgv,
  SPAWN_CAPTURE_CHARS,
  type SeatAdapter,
  type SeatMode,
  type SpawnFn,
} from "./seats.ts";

/** One declared seat: what it runs, and what it is allowed to run under. */
export interface SeatDeclaration {
  readonly adapter: SeatAdapter;
  readonly bounds: MeterBounds;
  /**
   * How many items this seat may hold at once. `halogen` declares one, because
   * the model is resident on a single worker and a second concurrent request
   * contends for the same GPU.
   */
  readonly slots: number;
}

export type SeatLedgerEvent = "meter" | "admit" | "dryrun" | "refuse";

/**
 * The seat log's own shape. It is a second log rather than extra columns on
 * the item 11 ledger, whose key order and pinned bytes are a format contract
 * that item 12 has no business breaking.
 */
export interface SeatLedgerEntry {
  readonly seq: number;
  readonly event: SeatLedgerEvent;
  readonly seat: string;
  readonly runId: string;
  readonly label: string;
  readonly cap: number;
  readonly seatsInUse: number;
  readonly reason: string;
  readonly detail: string;
  readonly argv: string;
}

export const SEAT_LEDGER_KEYS = [
  "seq",
  "event",
  "seat",
  "runId",
  "label",
  "cap",
  "seatsInUse",
  "reason",
  "detail",
  "argv",
] as const;

export class SeatLedger extends AppendOnlyLog<SeatLedgerEntry> {
  constructor() {
    super(SEAT_LEDGER_KEYS);
  }
}

/**
 * The spawn log: a THIRD representation, for the same reason item 12 added a
 * second one. The item 11 ledger's key order and pinned sha256 are a format
 * contract, and the seat log of item 12 is now one too. A child's exit code,
 * signal, timeout state and reply have no column in either, so item 26
 * declares its own list rather than widening theirs. No existing key order
 * changes and no existing pinned byte moves.
 *
 * `reply` is the seat's own reading of its stdout. It is truncated, like the
 * stdout and stderr excerpts, because a ledger line is a record and not a
 * transcript. The ledger is not a secret store: see the note on the spawner.
 */
export interface SpawnLedgerEntry {
  readonly seq: number;
  readonly event: "spawn";
  readonly seat: string;
  readonly runId: string;
  readonly label: string;
  readonly argv: string;
  readonly exitCode: number | null;
  readonly signal: string | null;
  readonly timedOut: boolean;
  readonly timeoutMs: number;
  readonly stdoutChars: number;
  readonly stderrChars: number;
  readonly reply: string;
  readonly stderrExcerpt: string;
  readonly reason: string;
}

export const SPAWN_LEDGER_KEYS = [
  "seq",
  "event",
  "seat",
  "runId",
  "label",
  "argv",
  "exitCode",
  "signal",
  "timedOut",
  "timeoutMs",
  "stdoutChars",
  "stderrChars",
  "reply",
  "stderrExcerpt",
  "reason",
] as const;

export class SpawnLedger extends AppendOnlyLog<SpawnLedgerEntry> {
  constructor() {
    super(SPAWN_LEDGER_KEYS);
  }
}

/** Anything that can take one ledger line. `JsonlSink` is the durable one. */
export interface LedgerSink<E> {
  append(entry: E): void;
}

/** Refused for a reason that is not the meter's: the cap, or nothing to do. */
export type DispatchRefusalReason = MeterRefusalReason | "cap-reached" | "no-item";

export interface SeatDryRunOptions {
  /** The work-in-progress cap across all seats. Data, passed in. */
  readonly cap: number;
  /**
   * Dry run is the default. The only caller that passes "spawn" is
   * `makeHalogenOutcomeOf` in `src/live.ts`; no test passes it against a real
   * seat, and the two that exercise the spawn path inject a spawner.
   */
  readonly mode?: SeatMode;
  /** Where dry-run lines go. Injected so tests capture them. */
  readonly print?: (line: string) => void;
  /**
   * Injected file reader, so a test can supply fabricated rows without a
   * fixture tree. Unset means the real filesystem, read-only.
   */
  readonly readFile?: (p: string) => string;
  /**
   * Passed through to normalization. Unset, as it is by default, a file with
   * no `reading_age_seconds` is refused `meter-stale` exactly as the rule says.
   */
  readonly deriveAgeFromObservedAtMs?: number | undefined;
  /**
   * Gate two, passed straight through to `executeDispatch`. Absent, as it is
   * everywhere but the one live test and the live path of `src/live.ts`,
   * `mode: "spawn"` is refused.
   */
  readonly allowSpawn?: boolean;
  /** Gate three. Defaults to ["halogen"] inside `executeDispatch`. */
  readonly allowSpawnSeats?: readonly string[];
  /** The child timeout, as data at the call site rather than a constant. */
  readonly spawnTimeoutMs?: number;
  /** Injected spawner, so the spawn path is testable without a seat. */
  readonly spawn?: SpawnFn;
  /** Durable sink for the seat log. One line per seat-ledger event. */
  readonly seatSink?: LedgerSink<SeatLedgerEntry>;
  /** Durable sink for the spawn log. One line per spawned child. */
  readonly spawnSink?: LedgerSink<SpawnLedgerEntry>;
}

export interface SeatDryRunResult {
  readonly ledger: SeatLedger;
  /** Empty unless a live spawn actually happened. */
  readonly spawnLedger: SpawnLedger;
  readonly admitted: number;
  readonly refused: number;
  readonly spawned: number;
  readonly reads: readonly MeterRead[];
}

/**
 * One dispatch pass: pair each declared seat, in declaration order, with the
 * next item that has a resolved prompt, and let the meter decide.
 *
 * Nothing is executed in the default mode. `executeDispatch` in dry-run mode
 * prints the argv and the first 200 characters of stdin and returns
 * `spawned: false`; the spawn path is not reachable from here without
 * `mode: "spawn"`, which exactly one caller in this repository passes:
 * `makeHalogenOutcomeOf` in `src/live.ts`, reachable only from
 * `src/e2e-live.ts` and only with AX_CONWIP_LIVE_HALOGEN=1. `src/cli.ts` does
 * not import that module and cannot dispatch anything.
 */
/**
 * Slice a captured string to the ledger's capture bound WITHOUT leaving a lone
 * surrogate at the end.
 *
 * A-13 of the 2026-09-23 review. `.slice(0, SPAWN_CAPTURE_CHARS)` cuts on a
 * UTF-16 code unit, so an excerpt whose cut lands between the two halves of an
 * astral character recorded a high surrogate with no low surrogate after it.
 * The line stays valid JSON; the character is broken. This costs one code unit
 * and only in the case that is already wrong.
 */
export function sliceCapture(text: string, chars: number = SPAWN_CAPTURE_CHARS): string {
  const cut = text.slice(0, chars);
  const last = cut.charCodeAt(cut.length - 1);
  const isHighSurrogate = last >= 0xd800 && last <= 0xdbff;
  return isHighSurrogate && text.length > cut.length ? cut.slice(0, -1) : cut;
}

export function runSeatDryRun(
  items: readonly WorkItem[],
  declarations: readonly SeatDeclaration[],
  opts: SeatDryRunOptions,
): SeatDryRunResult {
  const ledger = new SeatLedger();
  const spawnLedger = new SpawnLedger();
  /** Append to the in-memory log and, when one is configured, to disk. */
  const rec = (e: Omit<SeatLedgerEntry, "seq">): void => {
    const entry = ledger.append(e);
    opts.seatSink?.append(entry);
  };
  const mode: SeatMode = opts.mode ?? "dry-run";
  const queue = items.filter((i) => i.promptResolved);
  const reads: MeterRead[] = [];
  let seatsInUse = 0;
  let spawned = 0;
  let next = 0;

  for (const decl of declarations) {
    const seat = decl.adapter.seatId;
    const item = queue[next];

    const normalize: NormalizeOptions & { readonly readFile?: (p: string) => string } = {
      deriveAgeFromObservedAtMs: opts.deriveAgeFromObservedAtMs,
      readFile: opts.readFile,
    };
    const read = readMeterRow(decl.adapter.meterPath, normalize);
    reads.push(read);
    rec({
      event: "meter",
      seat,
      runId: item?.runId ?? "-",
      label: item?.label ?? "-",
      cap: opts.cap,
      seatsInUse,
      reason: read.row === null ? "no-row" : "row",
      detail: read.row === null ? `${decl.adapter.meterPath}: ${read.error ?? "absent"}` : decl.adapter.meterPath,
      argv: "",
    });

    // The pure rule. It sees the parsed row and the bounds, and nothing else.
    const decision = evaluateMeter(read.row, decl.bounds);
    if (decision.kind === "REFUSE") {
      rec({
        event: "refuse",
        seat,
        runId: item?.runId ?? "-",
        label: item?.label ?? "-",
        cap: opts.cap,
        seatsInUse,
        reason: decision.reason,
        detail: decision.detail,
        argv: "",
      });
      continue;
    }

    if (item === undefined) {
      rec({
        event: "refuse", seat, runId: "-", label: "-", cap: opts.cap, seatsInUse,
        reason: "no-item", detail: "no item with a resolved prompt remains", argv: "",
      });
      continue;
    }

    if (seatsInUse + decl.slots > opts.cap) {
      rec({
        event: "refuse", seat, runId: item.runId, label: item.label, cap: opts.cap, seatsInUse,
        reason: "cap-reached",
        detail: `${seatsInUse} in use plus ${decl.slots} would exceed cap ${opts.cap}`,
        argv: "",
      });
      continue;
    }

    const d = decl.adapter.render(item);
    seatsInUse += decl.slots;
    next++;
    rec({
      event: "admit", seat, runId: item.runId, label: item.label, cap: opts.cap, seatsInUse,
      reason: "meter-admit", detail: decision.detail, argv: renderArgv(d),
    });

    const result = executeDispatch(decl.adapter, d, {
      mode,
      print: opts.print,
      allowSpawn: opts.allowSpawn,
      allowSpawnSeats: opts.allowSpawnSeats,
      timeoutMs: opts.spawnTimeoutMs,
      spawn: opts.spawn,
    });
    if (result.spawned) spawned++;
    rec({
      event: "dryrun", seat, runId: item.runId, label: item.label, cap: opts.cap, seatsInUse,
      reason: result.spawned ? "spawned" : "printed-only",
      detail: `stdin ${d.stdin.length} chars, first ${Math.min(200, d.stdin.length)} shown`,
      argv: renderArgv(d),
    });

    // A spawned child gets its own line, in the spawn log's own key order.
    if (result.spawned && result.outcome !== undefined) {
      const o = result.outcome;
      const entry = spawnLedger.append({
        event: "spawn",
        seat,
        runId: item.runId,
        label: item.label,
        argv: renderArgv(d),
        exitCode: o.exitCode,
        signal: o.signal,
        timedOut: o.timedOut,
        timeoutMs: o.timeoutMs,
        stdoutChars: o.stdout.length,
        stderrChars: o.stderr.length,
        reply: sliceCapture(result.reply ?? ""),
        stderrExcerpt: sliceCapture(o.stderr),
        // A-19 of the 2026-09-23 review. A signal death has NO exit code, and
        // the old expression wrote `exit null` into this column, claiming one
        // that never existed. The three outcomes were already distinguishable
        // by the exitCode/signal/timedOut columns; this makes the human-
        // readable column agree with them.
        reason: o.timedOut
          ? `killed at the ${o.timeoutMs}ms timeout; what was captured before the kill is kept`
          : o.error !== undefined
            ? `child did not start: ${o.error}`
            : o.signal !== null && o.signal !== undefined
              ? `killed by signal ${String(o.signal)}`
              : o.exitCode === 0
                ? (result.replyError ?? "exit 0")
                : `exit ${String(o.exitCode)}`,
      });
      opts.spawnSink?.append(entry);
    }
  }

  return {
    ledger,
    spawnLedger,
    admitted: ledger.count("admit"),
    refused: ledger.count("refuse"),
    spawned,
    reads,
  };
}
