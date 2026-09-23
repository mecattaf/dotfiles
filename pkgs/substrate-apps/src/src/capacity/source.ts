/**
 * Where a seat's capacity comes from: the seam that keeps admission off any one
 * producer's file layout.
 *
 * The gate (`gate.ts`) asks a `CapacitySource` for one `seat-capacity/2`
 * reading and judges it with the pure `admitSeat`. Two sources exist:
 *
 *  - `snapshotFileSource`: a `seat-capacity/2` snapshot file. This is the
 *    long-term contract (SCOUT.md 5.2): any publisher can write it, and nothing
 *    here knows who did.
 *  - `floorCapacitySource` (`floor.ts`): the ported floor's `GET /capacity`
 *    and `GET /capacity/admit`, cached per seat by an async `prepare` so that
 *    `read` stays synchronous. Both the floor's verdict and this gate's must
 *    admit.
 *  - `tallyMeterSource` (`tally-meters.ts`): an ADAPTER over today's
 *    `seat-meter/1` rows and the usage cache the dotfiles feeder writes. It is
 *    the only module under `src/capacity/` allowed to know that layout, so that
 *    removing tally from the dotfiles removes one file here and nothing else
 *    (fence: `test/conwip-fixes-capacity.test.ts`).
 */
import { readFileSync } from "node:fs";
import { decodeSeatCapacitySnapshot, type SeatCapacity } from "@substrate/planning";

/**
 * A refusal the source itself already holds for this job (the floor's own
 * `/capacity/admit` answer). The gate refuses on it before its own checks; it
 * never turns a refusal of the gate's into an admission.
 */
export interface UpstreamRefusal {
  readonly reason: string;
  readonly detail: string;
  readonly raiseDemand: boolean;
}

/** One read: a reading, or why there is none. Never both. */
export type SeatCapacityRead =
  | { readonly ok: true; readonly seat: SeatCapacity; readonly from: string; readonly upstream?: UpstreamRefusal }
  | { readonly ok: false; readonly error: string; readonly from: string };

/** The job a read or a prepare is for. `model` null means "no model named". */
export interface CapacityJob {
  readonly model: string | null;
}

/** What `prepare` needs besides the job: the instant and the gate's headroom floor. */
export interface CapacityPrepare extends CapacityJob {
  readonly asOfMs: number;
  readonly minHeadroomPct: number;
}

export interface CapacitySource {
  /** A short name for ledger lines: which source answered. */
  readonly name: string;
  /**
   * Read the current capacity of one seat. Must not throw: an error is a value.
   * `job` is given when the read is for one job; a source that holds per-job
   * verdicts (the floor) fails closed when it holds none for that job.
   */
  read(seatId: string, job?: CapacityJob): SeatCapacityRead;
  /**
   * Optional: fetch what `read` will answer from (a remote source). Absent on
   * a local source. A prepare that fails must leave `read` failing closed; it
   * never leaves an older answer readable in its place.
   */
  prepare?(seatId: string, job: CapacityPrepare): Promise<void>;
}

/**
 * A `seat-capacity/2` snapshot file. `seatIds` maps this scheduler's seat ids
 * onto the snapshot's (`halogen` is `gpu-worker` there).
 */
export function snapshotFileSource(
  path: string,
  opts: { readonly seatIds?: Readonly<Record<string, string>>; readonly readFile?: (p: string) => string } = {},
): CapacitySource {
  const read = opts.readFile ?? ((p: string) => readFileSync(p, "utf8"));
  return {
    name: `snapshot:${path}`,
    read(seatId) {
      const wanted = opts.seatIds?.[seatId] ?? seatId;
      let raw: unknown;
      try {
        raw = JSON.parse(read(path));
      } catch (e) {
        return { ok: false, error: `snapshot unreadable: ${(e as Error).message}`, from: path };
      }
      let snap: ReturnType<typeof decodeSeatCapacitySnapshot>;
      try {
        snap = decodeSeatCapacitySnapshot(raw);
      } catch (e) {
        return { ok: false, error: `snapshot does not decode as seat-capacity/2: ${(e as Error).message.slice(0, 300)}`, from: path };
      }
      const seat = snap.seats.find((s) => s.seat === wanted);
      if (seat === undefined) return { ok: false, error: `snapshot names no seat ${JSON.stringify(wanted)}`, from: path };
      return { ok: true, seat, from: path };
    },
  };
}

/** A fixed set of readings, for tests and for a caller that already holds them. */
export function staticSource(seats: Readonly<Record<string, SeatCapacity>>): CapacitySource {
  return {
    name: "static",
    read(seatId) {
      const seat = seats[seatId];
      return seat === undefined
        ? { ok: false, error: `no reading for seat ${JSON.stringify(seatId)}`, from: "static" }
        : { ok: true, seat, from: "static" };
    },
  };
}
