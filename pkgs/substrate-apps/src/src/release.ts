/**
 * The release rule. One pure function of (state, reading): no clock read, no
 * randomness, no service, no input and no output. That property is the single
 * most valuable thing carried over from tally-ts-sdk, because it makes a
 * fabricated reading a complete test fixture.
 *
 * Wall-clock time enters only as data. The caller reads the clock once, outside
 * this module, and puts the result in `state.asOf`.
 */

/**
 * The phase strings ax actually writes. `TaskStatus.phase` is a proto3 `string`,
 * NOT an enum: `ax.proto` declares no enum at all. These six are every literal
 * assigned to `Status.Phase` anywhere in ax v0.3.0. See DESIGN.md for the file
 * and line of each.
 */
export const AX_PHASES = [
  "Pending",
  "Running",
  "Suspended",
  "Failed",
  "Completed",
  "Terminating",
] as const;

export type AxPhase = (typeof AX_PHASES)[number];

/**
 * The set ax itself calls terminal, and on which it closes the WatchTask
 * stream: internal/server/server.go:233 and cmd/ax/main.go:818.
 */
export const AX_WATCH_TERMINAL = ["Running", "Completed", "Failed"] as const;

/**
 * The set on which the CONWIP gives a slot back. "Running" is deliberately NOT
 * here: a running Task still occupies work-in-progress. The consequence is that
 * the end of the WatchTask stream is a signal to read again, not a release.
 */
export const CONWIP_RELEASING_PHASES = ["Completed", "Failed", "Terminating"] as const;

export interface Reading {
  /** The ax Task this reading is about. */
  readonly taskName: string;
  /** `Task.status.phase` exactly as the server returned it. */
  readonly phase: string;
  /** When the reading was taken, ISO-8601 UTC, supplied by the caller. */
  readonly observedAt: string;
  /** The WatchTask `action`, or "GET" for a unary read. */
  readonly action: string;
}

export interface SlotState {
  readonly runId: string;
  readonly label: string;
  readonly taskName: string;
  /** The caller's own clock reading, taken outside this rule. */
  readonly asOf: string;
  /** A reading older than this is refused rather than acted on. */
  readonly maxReadingAgeMs: number;
}

export type ReleaseDecision =
  | { readonly kind: "RELEASE"; readonly phase: string; readonly reason: string }
  | { readonly kind: "HOLD"; readonly reason: string }
  | { readonly kind: "REFUSE"; readonly reason: string };

/** Parse an ISO-8601 instant to epoch milliseconds. Returns undefined if it is not one. */
export function instantMs(iso: string): number | undefined {
  if (typeof iso !== "string" || iso.length === 0) return undefined;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? undefined : ms;
}

/**
 * Decide whether the slot held by `state` is given back, held, or whether the
 * reading is refused. Pure.
 */
export function evaluateRelease(state: SlotState, reading: Reading | null | undefined): ReleaseDecision {
  if (reading === null || reading === undefined) {
    return { kind: "REFUSE", reason: "missing reading" };
  }
  if (reading.taskName !== state.taskName) {
    return {
      kind: "REFUSE",
      reason: `reading is for task ${JSON.stringify(reading.taskName)}, slot holds ${JSON.stringify(state.taskName)}`,
    };
  }
  const observed = instantMs(reading.observedAt);
  const asOf = instantMs(state.asOf);
  if (observed === undefined) {
    return { kind: "REFUSE", reason: `reading observedAt is not ISO-8601: ${JSON.stringify(reading.observedAt)}` };
  }
  if (asOf === undefined) {
    return { kind: "REFUSE", reason: `state asOf is not ISO-8601: ${JSON.stringify(state.asOf)}` };
  }
  const ageMs = asOf - observed;
  if (ageMs > state.maxReadingAgeMs) {
    return { kind: "REFUSE", reason: `reading is stale by ${ageMs - state.maxReadingAgeMs} ms` };
  }
  if (ageMs < 0) {
    return { kind: "REFUSE", reason: `reading is ${-ageMs} ms in the future of asOf` };
  }
  if (!(AX_PHASES as readonly string[]).includes(reading.phase)) {
    return { kind: "REFUSE", reason: `unknown ax phase ${JSON.stringify(reading.phase)}` };
  }
  if ((CONWIP_RELEASING_PHASES as readonly string[]).includes(reading.phase)) {
    return { kind: "RELEASE", phase: reading.phase, reason: `phase ${reading.phase}` };
  }
  return { kind: "HOLD", reason: `phase ${reading.phase} is not terminal for the CONWIP` };
}
