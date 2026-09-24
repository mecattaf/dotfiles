/**
 * projectionLoad.ts — U-A13 LAKE-PROJECTION, the load.
 *
 * `ACTION-PLAN.md` U-A13, verbatim: "loads the banked corpus into the Factory
 * object under the in-memory storage Layer and projects the mirror back". This
 * is that sentence, and it is the reason the projection is not a `cat` of the
 * register into a different file.
 *
 * THE CORPUS GOES THROUGH THE STATE MACHINE, NOT AROUND IT. Every banked
 * receipt is walked through the same four states an item walks in production —
 * `unclaimed → released → inflight → closed` — by the same calls the uplink
 * makes:
 *
 *   observeCapacity(reading)   a reading is what makes anything admissible
 *   handOut(executor)          the release evaluator picks; this module does not
 *   observeOutcome(Accepted)   the kernel's answer, which is what makes it inflight
 *   observeVerdict(verdict)    the mirrored witness record, chained
 *   observeReceipt(evidence)   §2.2b's exact chain match
 *
 * The object refuses a receipt whose three evidence cells do not equal a
 * mirrored verdict's (`Factory.observeReceipt`, reason `ReceiptMismatch`) and
 * refuses a verdict that breaks its executor's chain (`ContinuityGap`). So a
 * unit reaches the mirror only if its evidence survived both, and the mirror is
 * the thing the projection reads. A receipt dropped from the load is a unit the
 * object never accepted, no row is projected for it, and `--diff` names it:
 * that is the whole of `mutation_hint`, "drop one banked receipt → --diff
 * non-empty", implemented rather than asserted.
 *
 * THIS MODULE AUTHORS NOTHING. It constructs no verdict of its own: the outcome,
 * the rc, the mutation rc and the output digest all come from the banked bytes,
 * and the hash chain is supplied by the caller. The lake is a mirror and never a
 * ledger; what it mirrors here is a corpus that was banked by someone else.
 *
 * IN-MEMORY ONLY. The caller provides the object; the tool provides it under
 * `planningStoreInMemoryLayer`. Nothing is persisted anywhere.
 */
import { Effect, Schema } from "effect";
import type { CapacityReading } from "@substrate/planning/schema/capacity.ts";
import type { ExecutorId } from "@substrate/planning/schema/ids.ts";
import { Verdict } from "@substrate/planning/schema/records.ts";
import { AdmitOutcomeReport } from "@substrate/planning/schema/admit.ts";
import type { FactoryError } from "@substrate/planning/schema/errors.ts";
import type { IFactory } from "@substrate/planning/objects/factory.ts";
import {
  projectionRowOf,
  type BankedRow,
  type MirroredEvidence,
  type ProjectionRow
} from "./projection.ts";

const decodeVerdict = Schema.decodeUnknownSync(Verdict);
const decodeOutcome = Schema.decodeUnknownSync(AdmitOutcomeReport);

/** One link of the witness chain the caller supplies. */
interface ChainLink {
  readonly seq: number;
  readonly hash: string;
  readonly prevHash: string;
}

/** What one load produced. */
interface LoadResult {
  /** One row per unit the object accepted, sorted by unit id. */
  readonly rows: ReadonlyArray<ProjectionRow>;
  /** Units armed but never proposed before the loop stopped making progress. */
  readonly unreleased: ReadonlyArray<string>;
  /** Units the object refused, with the reason it gave. */
  readonly refused: ReadonlyArray<{ readonly unit: string; readonly reason: string }>;
  /** Passes of the release loop the corpus needed. */
  readonly passes: number;
}

/**
 * Walk the banked corpus through one Factory object and read the mirror back.
 *
 * @param factory - The object, already built over the in-memory store.
 * @param rows - The banked receipts, normalised. Order is the arming order.
 * @param link - The witness chain link for the nth verdict, supplied by the
 *   caller so this module computes no hash and therefore mints no proof.
 * @param readingFor - A capacity reading for pass `n`. One per pass, because a
 *   reading is a complete fixture and re-observing the same `seq` is a no-op.
 * @param maxPasses - A bound on the release loop, so a corpus the evaluator will
 *   not drain stops rather than spins.
 * @returns The mirror's rows plus everything that did not reach it, named.
 */
export const loadBankedIntoFactory = (
  factory: IFactory,
  rows: ReadonlyArray<BankedRow>,
  link: (index: number) => ChainLink,
  readingFor: (pass: number) => CapacityReading,
  maxPasses = 512
): Effect.Effect<LoadResult, FactoryError> =>
  Effect.gen(function* () {
    const pending = new Map(rows.map((row) => [row.unit, row]));
    const witnessed = new Set<string>();
    const refused: Array<{ unit: string; reason: string }> = [];
    let written = 0;
    let pass = 0;

    while (witnessed.size + refused.length < rows.length && pass < maxPasses) {
      const reading = readingFor(pass);
      pass += 1;
      yield* factory.observeCapacity(reading);
      const proposals = yield* factory.handOut(reading.executor as ExecutorId);
      const fresh = proposals.filter(
        (proposal) => pending.has(proposal.taskId) && !witnessed.has(proposal.taskId)
      );
      if (fresh.length === 0) break;

      for (const proposal of fresh) {
        const banked = pending.get(proposal.taskId);
        if (banked === undefined) continue;
        yield* factory.observeOutcome(
          decodeOutcome({
            taskId: proposal.taskId,
            dedupKey: proposal.dedupKey,
            outcome: "Accepted",
            row: proposal.rows[0]?.row ?? "build"
          })
        );
        const chain = link(written);
        written += 1;
        const record = decodeVerdict({
          _tag: "Verdict",
          taskId: banked.unit,
          executor: reading.executor,
          seq: chain.seq,
          hash: chain.hash,
          prevHash: chain.prevHash,
          outcome: banked.outcome,
          serviceSeconds: banked.seconds,
          unit_id: banked.unit,
          oracle_rc: banked.oracle_rc,
          oracle_output_sha256: banked.oracle_output_sha256,
          ...(banked.mutation_rc === null ? {} : { mutation_rc: banked.mutation_rc })
        });
        const observed = yield* factory.observeVerdict(record).pipe(
          Effect.map(() => null),
          Effect.catch((error: FactoryError) => Effect.succeed(error.reason))
        );
        if (observed !== null) {
          refused.push({ unit: banked.unit, reason: observed });
          witnessed.add(banked.unit);
          continue;
        }
        const accepted = yield* factory
          .observeReceipt({
            id: banked.unit,
            oracle_rc: banked.oracle_rc,
            oracle_output_sha256: banked.oracle_output_sha256,
            verdict_hash: chain.hash,
            ...(banked.mutation_rc === null ? {} : { mutation_rc: banked.mutation_rc })
          })
          .pipe(
            Effect.map(() => null),
            Effect.catch((error: FactoryError) => Effect.succeed(error.reason))
          );
        if (accepted !== null) refused.push({ unit: banked.unit, reason: accepted });
        witnessed.add(banked.unit);
      }
    }

    const view = yield* factory.stateView;
    const evidence = new Map<string, MirroredEvidence>();
    for (const receipt of view.receipts) evidence.set(receipt.id, receipt);

    const projected: Array<ProjectionRow> = [];
    for (const row of rows) {
      const mirrored = evidence.get(row.unit);
      if (mirrored === undefined) continue;
      projected.push(projectionRowOf(row, mirrored));
    }
    projected.sort((a, b) => a.unit.localeCompare(b.unit));

    const unreleased = rows
      .filter((row) => !witnessed.has(row.unit))
      .map((row) => row.unit)
      .sort((a, b) => a.localeCompare(b));

    return {
      rows: projected,
      unreleased,
      refused: refused.sort((a, b) => a.unit.localeCompare(b.unit)),
      passes: pass
    };
  });
