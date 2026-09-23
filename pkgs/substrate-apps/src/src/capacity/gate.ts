/**
 * The capacity gate: one question per dispatch, "may this seat take a job for
 * this model now", answered fail-closed from a `CapacitySource` by the ported,
 * pure `admitSeat`.
 *
 * On top of `admitSeat` (which admits a reading up to 1200 s old, the planning
 * bound), the gate applies the DISPATCH bound SCOUT.md 5.4 names for this
 * scheduler (360 s: the active cadence plus one tick), requires BOTH the
 * five-hour and the weekly window on a Claude seat (OI-2), and maps a model id
 * onto the family a model-scoped row names (OI-3). A model id it cannot map is
 * refused rather than let through: `best` resolves to Fable (OI-6), and a
 * scoped Fable row at 100 percent must not be sidestepped by an alias.
 */
import { admitSeat, type AdmissionDecision } from "@substrate/planning";
import type { CapacitySource, SeatCapacityRead } from "./source.ts";

export interface CapacityPolicy {
  /** A reading older than this (seconds) is refused for dispatch. */
  readonly dispatchMaxAgeSeconds: number;
  /** Every checked window must leave more than this share free. cap 95 is 5. */
  readonly minHeadroomPct: number;
}

/** SCOUT.md 5.4: active cadence 300 s plus one 60 s tick. */
export const DISPATCH_MAX_AGE_SECONDS = 360;

export const DEFAULT_CAPACITY_POLICY: CapacityPolicy = {
  dispatchMaxAgeSeconds: DISPATCH_MAX_AGE_SECONDS,
  minHeadroomPct: 5,
};

export type GateDecision =
  | { readonly kind: "ADMIT"; readonly detail: string; readonly until: string }
  | {
      readonly kind: "REFUSE";
      readonly reason: string;
      readonly detail: string;
      /** A fresh provider reading would help: the caller may raise demand. */
      readonly raiseDemand: boolean;
    };

/** The model families the providers' scoped rows name. */
const FAMILIES = ["fable", "opus", "sonnet", "haiku"] as const;

/**
 * Map a model id onto a scoped row's family name (`claude-opus-5-5` is `Opus`).
 * Undefined when the id names no known family or names two.
 */
export function modelFamily(model: string): string | undefined {
  const m = model.toLowerCase();
  const hits = FAMILIES.filter((f) => new RegExp(`(^|[^a-z])${f}([^a-z]|$)`).test(m));
  if (hits.length !== 1) return undefined;
  const f = hits[0]!;
  return f[0]!.toUpperCase() + f.slice(1);
}

/**
 * What the CONWIP knows about one call besides its model: the harness that
 * will run it, and how many calls it has already sent to this seat that are
 * still running (the reading's `holders` cannot see them yet).
 */
export interface GateContext {
  readonly harness?: string;
  readonly inflight?: number;
  /** The model allowlist's ceilings for the model that runs (runners models.ts), in percent used. */
  readonly ceilings?: { readonly five_hour?: number; readonly seven_day?: number; readonly model_scoped?: number };
}

/**
 * The seat provider each harness spends (successor review r3: a claude or
 * codex call routed to a halogen seat was admitted on "slot free" while the
 * mounted cc credential paid). `ax` runs claude. codex spends a `codex`
 * seat, whose owner field still decides whether it is dispatchable.
 */
export const HARNESS_PROVIDER: Readonly<Record<string, string | null>> = { claude: "claude", ax: "claude", pi: "halogen", codex: "codex" };

/** Pure: judge one read for one job at one instant. */
export function decideCapacity(
  seatId: string,
  read: SeatCapacityRead,
  model: string | null,
  asOfMs: number,
  policy: CapacityPolicy = DEFAULT_CAPACITY_POLICY,
  ctx: GateContext = {},
): GateDecision {
  if (!read.ok) {
    return { kind: "REFUSE", reason: "capacity-unreadable", detail: `${read.from}: ${read.error}`, raiseDemand: true };
  }
  let seat = read.seat;
  if (ctx.harness !== undefined) {
    const want = Object.hasOwn(HARNESS_PROVIDER, ctx.harness) ? HARNESS_PROVIDER[ctx.harness] : undefined;
    if (want === null || want === undefined || seat.provider !== want) {
      return {
        kind: "REFUSE",
        reason: "seat-provider-mismatch",
        detail:
          want === null
            ? `harness ${ctx.harness} runs on a third party's login and is never admitted`
            : want === undefined
              ? `harness ${ctx.harness} is bound to no seat provider`
              : `harness ${ctx.harness} spends a ${want} seat, but seat ${seatId} is a ${seat.provider} reading`,
        raiseDemand: false,
      };
    }
  }
  // The source's own verdict (the floor's /capacity/admit) binds after the
  // harness check; the gate's own checks below still apply to whatever it admits.
  if (read.upstream !== undefined) {
    return { kind: "REFUSE", reason: read.upstream.reason, detail: `${read.from}: ${read.upstream.detail}`, raiseDemand: read.upstream.raiseDemand };
  }
  // Calls this CONWIP already sent to a slot seat hold slots the reading may
  // not show yet (successor review r3: three pi calls held Halogen's one slot).
  const inflight = ctx.inflight ?? 0;
  if (inflight > 0 && seat.slots !== null && seat.slots !== undefined) {
    seat = { ...seat, slots: { ...seat.slots, holders: seat.slots.holders + inflight } };
  }
  let family: string | null = null;
  if (seat.provider === "claude" && model !== null) {
    const f = modelFamily(model);
    if (f === undefined) {
      return {
        kind: "REFUSE",
        reason: "model-unrecognized",
        detail: `model ${JSON.stringify(model)} names no single family (fable, opus, sonnet, haiku); an alias is never admitted past a scoped limit`,
        raiseDemand: false,
      };
    }
    family = f;
  }
  const asOf = new Date(asOfMs).toISOString();
  const d: AdmissionDecision = admitSeat(seatId, seat, { model: family, min_headroom_pct: policy.minHeadroomPct }, asOf);
  if (!d.admit) {
    return { kind: "REFUSE", reason: d.reason, detail: d.detail, raiseDemand: d.raise_demand };
  }
  const ageS = (asOfMs - Date.parse(seat.observed_at)) / 1000;
  if (ageS > policy.dispatchMaxAgeSeconds) {
    return {
      kind: "REFUSE",
      reason: "stale-for-dispatch",
      detail: `the reading is ${Math.round(ageS)} s old, dispatch bound ${policy.dispatchMaxAgeSeconds} s`,
      raiseDemand: true,
    };
  }
  if (seat.provider === "claude") {
    for (const kind of ["five_hour", "seven_day"] as const) {
      if (!d.checked.some((c) => c.kind === kind)) {
        return {
          kind: "REFUSE",
          reason: "window-missing",
          detail: `a Claude seat must publish its ${kind} window before it takes work`,
          raiseDemand: true,
        };
      }
    }
  }
  // Per-model ceilings (the model allowlist): a window at or above the
  // model's ceiling refuses this model while the seat still takes others.
  if (ctx.ceilings !== undefined) {
    for (const w of seat.windows) {
      const ceiling =
        w.kind === "five_hour" ? ctx.ceilings.five_hour
          : w.kind === "seven_day" ? ctx.ceilings.seven_day
            : w.kind === "model_scoped" && family !== null && w.model !== null && w.model.toLowerCase() === family.toLowerCase() ? ctx.ceilings.model_scoped
              : undefined;
      if (ceiling !== undefined && w.utilization_pct !== null && w.utilization_pct >= ceiling) {
        return {
          kind: "REFUSE",
          reason: "model-ceiling",
          detail: `${w.kind}${w.model !== null ? `(${w.model})` : ""} at ${w.utilization_pct}% meets the model ceiling ${ceiling}% for ${JSON.stringify(model)}`,
          raiseDemand: false,
        };
      }
    }
  }
  const checked = d.checked.map((c) => (c.model === null ? c.kind : `${c.kind}(${c.model})`)).join(", ");
  return {
    kind: "ADMIT",
    detail: `${read.from}: headroom ${String(d.headroom_pct)}%, checked [${checked}], age ${Math.round(ageS)} s, until ${d.until}`,
    until: d.until,
  };
}

/** The gate a scheduler holds: a source, a seat, a policy. */
export class CapacityGate {
  constructor(
    readonly source: CapacitySource,
    readonly seatId: string,
    readonly policy: CapacityPolicy = DEFAULT_CAPACITY_POLICY,
  ) {}

  /**
   * `seatId` overrides the gate's own seat: the CONWIP gates each call on the
   * seat of the harness that will run it (successor review 2026-09-23).
   */
  /** The seat's slot capacity when its reading is a slot row (Halogen), else undefined. */
  /**
   * Three answers, never two (successor review r5): a slot seat and its count,
   * a seat that is not a slot seat, or a read that failed. slotCapacity folded
   * the last into the second, so a floor that went unreachable between the
   * admit and the slot read dispatched with no machine-wide hold.
   */
  slotStatus(seatId: string = this.seatId): { readonly kind: "slots"; readonly capacity: number } | { readonly kind: "none" } | { readonly kind: "unreadable"; readonly reason: string } {
    try {
      const read = this.source.read(seatId);
      if (!read.ok) return { kind: "unreadable", reason: (read as { reason?: string }).reason ?? "source read failed" };
      return read.seat.slots !== null && read.seat.slots !== undefined ? { kind: "slots", capacity: read.seat.slots.capacity } : { kind: "none" };
    } catch (e) {
      return { kind: "unreadable", reason: (e as Error).message };
    }
  }

  slotCapacity(seatId: string = this.seatId): number | undefined {
    try {
      const read = this.source.read(seatId);
      return read.ok && read.seat.slots !== null && read.seat.slots !== undefined ? read.seat.slots.capacity : undefined;
    } catch {
      return undefined;
    }
  }

  /**
   * Let a remote source fetch what the next `decide` for this job reads. A
   * no-op for a local source. Never throws: a failed fetch leaves the source
   * failing closed, which `decide` then refuses.
   */
  async refresh(model: string | null, asOfMs: number, seatId: string = this.seatId): Promise<void> {
    if (this.source.prepare === undefined) return;
    try {
      await this.source.prepare(seatId, { model, asOfMs, minHeadroomPct: this.policy.minHeadroomPct });
    } catch {
      // The source's contract: a failed prepare leaves read failing closed.
    }
  }

  decide(model: string | null, asOfMs: number, seatId: string = this.seatId, ctx: GateContext = {}): GateDecision {
    let read: SeatCapacityRead;
    try {
      read = this.source.read(seatId, { model });
    } catch (e) {
      read = { ok: false, error: `source threw: ${(e as Error).message}`, from: this.source.name };
    }
    return decideCapacity(seatId, read, model, asOfMs, this.policy, ctx);
  }
}
