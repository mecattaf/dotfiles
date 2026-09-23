/**
 * A `CapacitySource` backed by the ported floor (`packages/factory`'s HTTP
 * handler, served by `apps/floor`): `GET /capacity?asOf=` for the seat's
 * projected `seat-capacity/2` reading, and `GET /capacity/admit` for the
 * floor's own admission verdict on this job.
 *
 * The gate is synchronous, so the network happens in `prepare` (the gate's
 * `refresh`) and `read` answers from what the last prepare fetched. It is
 * fail-closed at every step:
 *
 *  - never prepared for this seat, or for this job's model: refused;
 *  - a request in flight: the previous answer is read, within its age bound;
 *  - the floor unreachable, timed out, non-200, or an answer that does not
 *    decode: that failure is what `read` returns until the next prepare, and
 *    an older good answer is never read in its place;
 *  - an answer older than `maxAnswerAgeMs` (by this process's clock): refused;
 *  - the floor refused the job: carried as `upstream`, and the gate refuses;
 *  - the floor admitted it: the gate still applies its own checks, including
 *    the dispatch staleness bound on the reading's `observed_at`.
 *
 * The deployed Worker closes every route behind the operator bearer, so the
 * source sends one when it is given (`token`, read by the caller from a file;
 * never logged). A test floor that serves GETs openly ignores it.
 */
import { decodeSeatCapacity, type SeatCapacity } from "@substrate/planning";
import type { CapacityJob, CapacityPrepare, CapacitySource, SeatCapacityRead, UpstreamRefusal } from "./source.ts";

/**
 * This scheduler's seat ids onto the floor's. Identity: the gentle pusher
 * (apps/pusher, seat-capacity/1 -> /2) publishes the runs-on seat names, so the
 * worker's Halogen row is `halogen` on the floor. A floor fed by the legacy
 * meters pusher names it `gpu-worker`; pass `seatIds: { halogen: "gpu-worker" }` there.
 */
export const FLOOR_SEAT_IDS: Readonly<Record<string, string>> = {};

/** How long a fetched answer may be read before it must be fetched again. */
export const FLOOR_MAX_ANSWER_AGE_MS = 30_000;

/** How long one floor request may take. */
export const FLOOR_TIMEOUT_MS = 5_000;

export interface FloorSourceOptions {
  readonly seatIds?: Readonly<Record<string, string>>;
  readonly fetch?: (url: string, init: { readonly signal: AbortSignal; readonly headers?: Record<string, string> }) => Promise<Response>;
  /** This process's clock, for the answer's age. */
  readonly nowMs?: () => number;
  readonly maxAnswerAgeMs?: number;
  readonly timeoutMs?: number;
  /** The floor's operator bearer; sent as Authorization, never logged. */
  readonly token?: string;
}

type Fetched<T> = { readonly atMs: number } & ({ readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: string });

interface SeatEntry {
  seq: number;
  applied: number;
  view?: Fetched<SeatCapacity>;
  readonly admits: Map<string, Fetched<UpstreamRefusal | null>>;
}

const obj = (v: unknown): Record<string, unknown> | undefined =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;

const modelKey = (model: string | null): string => (model === null ? "\u0000none" : model);

/** Pure: the named seat's reading out of a `GET /capacity` body. */
export function seatFromFloorView(body: unknown, wanted: string): { ok: true; seat: SeatCapacity } | { ok: false; error: string } {
  const seats = obj(body)?.["seats"];
  if (!Array.isArray(seats)) return { ok: false, error: "GET /capacity answered no seats array" };
  const entry = seats.map(obj).find((s) => obj(s?.["reading"])?.["seat"] === wanted);
  if (entry === undefined) return { ok: false, error: `the floor holds no reading for seat ${JSON.stringify(wanted)}` };
  try {
    return { ok: true, seat: decodeSeatCapacity(entry["reading"]) };
  } catch (e) {
    return { ok: false, error: `the floor's reading does not decode as seat-capacity/2: ${(e as Error).message.slice(0, 300)}` };
  }
}

/** Pure: a `GET /capacity/admit` body as null (admitted) or the floor's refusal. */
export function verdictFromFloorAdmit(body: unknown): { ok: true; value: UpstreamRefusal | null } | { ok: false; error: string } {
  const b = obj(body);
  if (b === undefined || typeof b["admit"] !== "boolean") return { ok: false, error: "GET /capacity/admit answered no admit boolean" };
  if (b["admit"] === true) return { ok: true, value: null };
  const reason = typeof b["reason"] === "string" && b["reason"].length > 0 ? b["reason"] : "floor-refused";
  const detail = typeof b["detail"] === "string" ? b["detail"] : "";
  return { ok: true, value: { reason, detail: `floor refused: ${detail}`, raiseDemand: b["raise_demand"] === true } };
}

export function floorCapacitySource(baseUrl: string, opts: FloorSourceOptions = {}): CapacitySource {
  const base = baseUrl.replace(/\/+$/, "");
  const seatIds = opts.seatIds ?? FLOOR_SEAT_IDS;
  const doFetch = opts.fetch ?? ((url: string, init: { readonly signal: AbortSignal; readonly headers?: Record<string, string> }) => fetch(url, init));
  const nowMs = opts.nowMs ?? (() => Date.now());
  const maxAge = opts.maxAnswerAgeMs ?? FLOOR_MAX_ANSWER_AGE_MS;
  const timeoutMs = opts.timeoutMs ?? FLOOR_TIMEOUT_MS;
  const held = new Map<string, SeatEntry>();
  const name = `floor:${base}`;

  const getJson = async (path: string): Promise<{ ok: true; body: unknown } | { ok: false; error: string }> => {
    try {
      const res = await doFetch(`${base}${path}`, {
        signal: AbortSignal.timeout(timeoutMs),
        ...(opts.token === undefined || opts.token === "" ? {} : { headers: { authorization: `Bearer ${opts.token}` } }),
      });
      if (res.status !== 200) {
        await res.arrayBuffer().catch(() => undefined);
        return { ok: false, error: `GET ${path.split("?")[0]} answered ${res.status}` };
      }
      try {
        return { ok: true, body: await res.json() };
      } catch (e) {
        return { ok: false, error: `GET ${path.split("?")[0]} answered no JSON: ${(e as Error).message}` };
      }
    } catch (e) {
      return { ok: false, error: `the floor is unreachable (GET ${path.split("?")[0]}): ${(e as Error).message}` };
    }
  };

  const aged = (f: Fetched<unknown>, what: string): string | undefined => {
    const age = nowMs() - f.atMs;
    return age > maxAge ? `the floor's ${what} answer is ${Math.round(age / 1000)} s old, bound ${Math.round(maxAge / 1000)} s` : undefined;
  };

  return {
    name,
    async prepare(seatId: string, job: CapacityPrepare): Promise<void> {
      const wanted = seatIds[seatId] ?? seatId;
      const entry: SeatEntry = held.get(seatId) ?? { seq: 0, applied: 0, admits: new Map() };
      held.set(seatId, entry);
      const key = modelKey(job.model);
      // A previous answer stays readable while this one is in flight (other
      // calls read it concurrently) and only until its age bound; whatever
      // this request answers, failure included, replaces it. A request that
      // lands after a newer one was sent is dropped.
      const mine = ++entry.seq;
      const asOf = encodeURIComponent(new Date(job.asOfMs).toISOString());
      const q = new URLSearchParams({ seat: wanted, min_headroom_pct: String(job.minHeadroomPct) });
      if (job.model !== null) q.set("model", job.model);
      const [view, admit] = await Promise.all([getJson(`/capacity?asOf=${asOf}`), getJson(`/capacity/admit?${q.toString()}&asOf=${asOf}`)]);
      if (mine < entry.applied) return;
      entry.applied = mine;
      const at = nowMs();
      if (!view.ok) entry.view = { atMs: at, ok: false, error: view.error };
      else {
        const s = seatFromFloorView(view.body, wanted);
        entry.view = s.ok ? { atMs: at, ok: true, value: s.seat } : { atMs: at, ok: false, error: s.error };
      }
      if (!admit.ok) entry.admits.set(key, { atMs: at, ok: false, error: admit.error });
      else {
        const v = verdictFromFloorAdmit(admit.body);
        entry.admits.set(key, v.ok ? { atMs: at, ok: true, value: v.value } : { atMs: at, ok: false, error: v.error });
      }
    },
    read(seatId: string, job?: CapacityJob): SeatCapacityRead {
      const entry = held.get(seatId);
      if (entry?.view === undefined) return { ok: false, error: `the floor was not consulted for seat ${JSON.stringify(seatId)}`, from: name };
      const view = entry.view;
      if (!view.ok) return { ok: false, error: view.error, from: name };
      const viewAge = aged(view, "capacity");
      if (viewAge !== undefined) return { ok: false, error: viewAge, from: name };
      if (job === undefined) return { ok: true, seat: view.value, from: name };
      const admit = entry.admits.get(modelKey(job.model));
      if (admit === undefined) {
        return { ok: false, error: `the floor was not asked to admit model ${JSON.stringify(job.model)} on seat ${JSON.stringify(seatId)}`, from: name };
      }
      if (!admit.ok) return { ok: false, error: admit.error, from: name };
      const admitAge = aged(admit, "admit");
      if (admitAge !== undefined) return { ok: false, error: admitAge, from: name };
      return admit.value === null
        ? { ok: true, seat: view.value, from: name }
        : { ok: true, seat: view.value, from: name, upstream: admit.value };
    },
  };
}
