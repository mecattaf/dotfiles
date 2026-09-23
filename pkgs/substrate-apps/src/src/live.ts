/**
 * The live dispatch path, and nothing else in this repository reaches it.
 *
 * This module holds the pieces `src/e2e-live.ts` assembles. It is a separate
 * file so that a test can import and exercise them WITHOUT importing an entry
 * point whose top level parses argv and exits; `src/e2e-live.ts` itself stays a
 * thin main that runs only when it is run.
 *
 * `src/cli.ts` does not import this module and must not. The ordinary command
 * line cannot dispatch anything, so a typo there cannot become a live spawn.
 */
import {
  runSeatDryRun,
  type LedgerSink,
  type SeatDeclaration,
  type SeatLedgerEntry,
  type SpawnLedgerEntry,
} from "./dispatch.ts";
import type { WorkItem } from "./schema.ts";
import type { SeatAdapter, SpawnFn } from "./seats.ts";

/**
 * The gate. A checkout on another machine dispatches nothing by running its
 * tests or its entry points, because nothing here runs without this set to
 * exactly "1". Item 26 chose the variable; this item keeps it and adds no
 * second way in.
 */
export const LIVE_ENV_VAR = "AX_CONWIP_LIVE_HALOGEN";

export class LiveDisabledError extends Error {}

/** Throw unless the live gate is explicitly open. Pure in its input. */
export function assertLiveEnabled(env: Readonly<Record<string, string | undefined>>): void {
  if (env[LIVE_ENV_VAR] !== "1") {
    throw new LiveDisabledError(
      `refusing to run the live path: ${LIVE_ENV_VAR} is ${JSON.stringify(env[LIVE_ENV_VAR] ?? null)}, not "1"`,
    );
  }
}

/**
 * Suggested bounds. They are exported as named defaults so a receipt can quote
 * them, but every one of them is PASSED at the call site in `src/e2e-live.ts`
 * and is overridable there on the command line. Nothing in this module reads
 * them itself, so striking a bound is never an edit to this file.
 *
 * 300 seconds is item 26's staleness bound, chosen because `gpu-worker.json` is
 * rewritten about once a minute. It is not loosened after seeing a refusal.
 */
export const SUGGESTED_STALENESS_BOUND_SECONDS = 300;
/** The wrapper's own `--timeout`, so it exits cleanly with its own message. */
export const SUGGESTED_WRAPPER_TIMEOUT_SECONDS = 240;
/** The child timeout outside it, so a wrapper that hangs is still bounded. */
export const SUGGESTED_CHILD_TIMEOUT_MS = 270_000;

export interface LiveOutcomeOptions {
  /** The seat. Which seats may actually spawn is NOT decided here. */
  readonly adapter: SeatAdapter;
  readonly stalenessBoundSeconds: number;
  readonly spawnTimeoutMs: number;
  /** The instant the age is derived against. Injected, never read here. */
  readonly nowMs: () => number;
  readonly seatSink?: LedgerSink<SeatLedgerEntry>;
  readonly spawnSink?: LedgerSink<SpawnLedgerEntry>;
  readonly print?: (line: string) => void;
  /** Injected reader, so a test supplies a fabricated row without a fixture tree. */
  readonly readFile?: (p: string) => string;
  /** Injected spawner, so a test drives the path without touching a seat. */
  readonly spawn?: SpawnFn;
}

export interface LiveOutcome {
  readonly phase: "Completed" | "Failed";
  readonly reason: string;
}

/**
 * Build the `LoopOptions.outcomeOf` hook that dispatches one admitted item on a
 * seat and reports what came back.
 *
 * There is deliberately NO `allowSpawnSeats` member on `LiveOutcomeOptions`.
 * The live path cannot express a widened allow list, so
 * `DEFAULT_LIVE_SPAWN_SEATS`, which is `["halogen"]`, always applies and `cc`
 * and `codex` are refused by the allow list rather than by convention. Widening
 * it would be an edit to `src/seats.ts`, in the open, and not a call-site flag.
 *
 * All three of item 26's gates are in force: `mode: "spawn"`, `allowSpawn:
 * true`, and the default allow list. Admission is still metered: the seat's own
 * row goes through `evaluateMeter` inside `runSeatDryRun` before anything is
 * executed, and a refusal there throws rather than degrading into a dispatch.
 *
 * The scheduler still originates no command line: the adapter carries the argv,
 * the item carries the prompt, and the prompt travels on stdin.
 */
export function makeHalogenOutcomeOf(
  opts: LiveOutcomeOptions,
): (item: WorkItem) => Promise<LiveOutcome> {
  const decl: SeatDeclaration = {
    adapter: opts.adapter,
    slots: 1,
    bounds: {
      stalenessBoundSeconds: opts.stalenessBoundSeconds,
      // halogen is a slot row of capacity one with NO budget row. A missing
      // budget figure is not a refusal for it, and that is a property of this
      // declaration rather than an exception inside the rule.
      utilizationField: "none",
      capPct: null,
    },
  };

  return async (item: WorkItem): Promise<LiveOutcome> => {
    const r = runSeatDryRun([item], [decl], {
      cap: 1,
      mode: "spawn",
      allowSpawn: true,
      // allowSpawnSeats is NOT passed, here or anywhere on this path.
      spawnTimeoutMs: opts.spawnTimeoutMs,
      deriveAgeFromObservedAtMs: opts.nowMs(),
      print: opts.print,
      readFile: opts.readFile,
      spawn: opts.spawn,
      seatSink: opts.seatSink,
      spawnSink: opts.spawnSink,
    });

    // The meter refused, or there was nothing to dispatch. Either way no child
    // ran, and that refusal is the measurement. It is not turned into a phase.
    if (r.spawned !== 1) {
      const refusal = r.ledger.entries.filter((e) => e.event === "refuse").at(-1);
      throw new Error(
        `no dispatch happened on seat ${opts.adapter.seatId}: ` +
          `${refusal?.reason ?? "unknown"}: ${refusal?.detail ?? "no refusal line"}`,
      );
    }

    const e = r.spawnLedger.entries[0]!;
    // A non-zero exit, a timeout and an empty reply are all `Failed`. The
    // CONWIP releases on `Failed`, and a held slot is worse than a recorded
    // failure. An empty reply is indistinguishable from a failed dispatch, so
    // it is not called a success.
    const ok = e.exitCode === 0 && !e.timedOut && e.reply.length > 0;
    return {
      phase: ok ? "Completed" : "Failed",
      reason: ok
        ? `seat ${e.seat} exit 0, reply ${e.reply.length} chars`
        : `seat ${e.seat} produced no usable reply: exit ${String(e.exitCode)}, timedOut ${e.timedOut}, reply ${e.reply.length} chars: ${e.reason}`,
    };
  };
}
