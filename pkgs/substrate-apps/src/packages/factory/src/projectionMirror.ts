/**
 * projectionMirror.ts — U-A14. `GET /projection`, served from the object's own
 * mirror.
 *
 * §2.2b's route table has one line for it — `GET /projection` → §2.2e — and
 * §2.2e says what a projection is: the operator's fields over U-A12's
 * deterministic serializer (stable key order, LF, trailing newline, ISO-8601
 * UTC). U-A13 built that projection for the TOOL, which reads a banked corpus
 * off the disk. This module builds the same rows for the WORKER, which has no
 * disk and no register: what it has is the receipts it accepted.
 *
 * THE ROW IS THE SAME ROW. `projectionRowOf` is U-A13's and is not copied here.
 * The two halves it joins are the two halves it always joins:
 *
 *   the banked cells      `actuals.*`, `outcome_for_calibration`, `receipt_path`
 *                         — retained below from the receipt's own bytes
 *   the evidence cells    `result.observed`, `result.grade`
 *                         — read off `stateView.receipts`, the mirror
 *
 * so a unit has a row only if the object accepted its evidence against a
 * mirrored kernel verdict (§2.2b's exact three-cell match). A receipt the object
 * refused is a unit with no row, on the Worker for the same reason as in the
 * tool.
 *
 * WHY THE CELLS ARE RETAINED AT ALL. `Factory.observeReceipt` keeps
 * `ReceiptEvidence` — five cells, the ones the chain match is about — and
 * deliberately not the receipt. But `actuals.seconds`, `actuals.tokens` and
 * `actuals.outcome` are measurements that live nowhere else, and a projection
 * that filled them with zeros would be inventing them. So the HTTP layer writes
 * the receipt's own measured cells into the `PlanningStore` beside the object's
 * state, under this module's prefix, and reads them back here. Durable Object
 * SQLite is what makes that survive an eviction; the in-memory Layer makes it
 * survive a test.
 *
 * NOTHING IS AUTHORED. Every cell below comes from the receipt's bytes or from
 * the mirror. `status` and `outcome_ruled` are not reachable from here — they
 * are not in `PROJECTION_CELLS`, not in `ProjectionRow`, and not named in this
 * file.
 */
import { Effect, Option, Schema } from "effect";
import { serializeRecords } from "@substrate/serializer";
import {
  StorageKey,
  type IPlanningStore
} from "@substrate/planning/objects/storage.ts";
import type { ReceiptEvidence } from "@substrate/planning/objects/factory.ts";
import {
  NONE,
  projectionRowOf,
  type ProjectionRow
} from "./projection.ts";

/** Where a retained receipt's measured cells live in the store. */
const MIRROR_RECEIPT_PREFIX = "factory/projection/";

/** The key one unit's retained cells are written under. */
const mirrorReceiptKey = (unit: string): StorageKey =>
  StorageKey(`${MIRROR_RECEIPT_PREFIX}${unit}`);

/**
 * The measured cells kept from an accepted receipt.
 *
 * Exactly the banked half of a projection row and not one field more. It is a
 * schema rather than an interface because storage is a boundary: what comes back
 * out of SQLite is parsed before any row is built from it, by the same rule the
 * `PlanningStore` header states.
 */
const RetainedReceipt = Schema.Struct({
  unit: Schema.String,
  receipt_path: Schema.String,
  receipt_sha256: Schema.String,
  disposition: Schema.String,
  seconds: Schema.Number,
  tokens: Schema.Number,
  outcome_for_calibration: Schema.NullOr(Schema.String),
  prior_gap: Schema.NullOr(Schema.Number)
});

/** The measured cells kept from an accepted receipt. */
type RetainedReceipt = typeof RetainedReceipt.Type;

const parseRetained = Schema.decodeUnknownEffect(RetainedReceipt);
const encodeRetained = Schema.encodeUnknownSync(RetainedReceipt);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const numberAt = (source: Record<string, unknown>, key: string): number | null => {
  const value = source[key];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
};

const stringAt = (source: Record<string, unknown>, key: string): string | null => {
  const value = source[key];
  return typeof value === "string" && value !== "" ? value : null;
};

/**
 * The declared-cell prior gap of a §2.3 receipt.
 *
 * The strict type spells it `prior_gap{tokens_by_cell{out, …}}`; `out` is the
 * cell every prior in this cycle declares (D-B19), which is the same reading
 * `projection.ts` takes over the banked corpus.
 */
const priorGapOf = (value: unknown): number | null => {
  if (!isRecord(value)) return null;
  const byCell = value["tokens_by_cell"];
  if (isRecord(byCell)) return numberAt(byCell, "out");
  return null;
};

/**
 * Reads the measured cells off one receipt.
 *
 * The receipt has already been decoded strictly by `postReceipt` when this is
 * called, so the required cells are there by construction; the reader is written
 * defensively anyway, because "already validated upstream" is a claim about a
 * caller and not about a value.
 *
 * @param receipt - The receipt as it arrived, parsed.
 * @param receiptPath - Where the poster banked it, or `"none"` (D-B22).
 * @param receiptSha256 - sha256 over the receipt's canonical bytes.
 * @returns The retained cells, or the reason they are not a row.
 */
export const retainedReceiptOf = (
  receipt: unknown,
  receiptPath: string,
  receiptSha256: string
):
  | { readonly ok: true; readonly retained: RetainedReceipt }
  | { readonly ok: false; readonly why: string } => {
  if (!isRecord(receipt)) return { ok: false, why: "the receipt is not a JSON object" };
  const missing: Array<string> = [];
  const unit = stringAt(receipt, "id");
  if (unit === null) missing.push("id");
  const seconds = numberAt(receipt, "seconds");
  if (seconds === null) missing.push("seconds");
  const disposition = stringAt(receipt, "disposition");
  if (disposition === null) missing.push("disposition");
  const tokensBlock = receipt["tokens"];
  const tokens = isRecord(tokensBlock) ? numberAt(tokensBlock, "total") : null;
  if (tokens === null) missing.push("tokens.total");
  if (missing.length > 0) return { ok: false, why: `carries no ${missing.join(", ")}` };

  return {
    ok: true,
    retained: {
      unit: unit as string,
      receipt_path: receiptPath === "" ? NONE : receiptPath,
      receipt_sha256: receiptSha256,
      disposition: disposition as string,
      seconds: seconds as number,
      tokens: tokens as number,
      outcome_for_calibration: stringAt(receipt, "outcome_for_calibration"),
      prior_gap: priorGapOf(receipt["prior_gap"])
    }
  };
};

/** Writes one unit's retained cells into the store. */
export const retainReceipt = (
  store: IPlanningStore,
  retained: RetainedReceipt
): Effect.Effect<void, never> =>
  store
    .put(mirrorReceiptKey(retained.unit), encodeRetained(retained))
    .pipe(Effect.catch(() => Effect.void));

/**
 * Joins the retained cells with the mirror, in unit order.
 *
 * A retained receipt with no matching evidence yields no row: the object holds
 * the cells only because it accepted the evidence, so the two disagreeing means
 * the store is ahead of the mirror and the row would be a claim the object
 * cannot back. Evidence with no retained cells yields no row either, and for the
 * mirror image of the same reason.
 */
export const mirrorProjectionRows = (
  retained: ReadonlyArray<RetainedReceipt>,
  evidence: ReadonlyArray<ReceiptEvidence>
): ReadonlyArray<ProjectionRow> => {
  const byUnit = new Map(evidence.map((entry) => [entry.id, entry] as const));
  const rows: Array<ProjectionRow> = [];
  for (const cells of retained) {
    const mirrored = byUnit.get(cells.unit);
    if (mirrored === undefined) continue;
    rows.push(projectionRowOf(cells, mirrored));
  }
  return rows.sort((left, right) => (left.unit < right.unit ? -1 : left.unit > right.unit ? 1 : 0));
};

/**
 * Reads every retained receipt back out of the store, in key order.
 *
 * A record that does not parse is skipped rather than thrown on: the projection
 * is a mirror, and a mirror that refuses to show anything because one record is
 * malformed shows less truth, not more. It cannot be written by this repository
 * in the first place — the only writer is `retainReceipt` above.
 */
export const retainedReceipts = (
  store: IPlanningStore
): Effect.Effect<ReadonlyArray<RetainedReceipt>, never> =>
  Effect.gen(function* () {
    const keys = yield* store
      .list(MIRROR_RECEIPT_PREFIX)
      .pipe(Effect.catch(() => Effect.succeed<ReadonlyArray<StorageKey>>([])));
    const found: Array<RetainedReceipt> = [];
    for (const key of keys) {
      const stored = yield* store
        .get(key)
        .pipe(Effect.catch(() => Effect.succeed(Option.none<unknown>())));
      if (Option.isNone(stored)) continue;
      const parsed = yield* parseRetained(stored.value).pipe(Effect.option);
      if (Option.isSome(parsed)) found.push(parsed.value);
    }
    return found;
  });

/**
 * The projection body, byte for byte.
 *
 * `serializeRecords` is U-A12's: sorted keys, LF, one record per line, a
 * trailing newline. That is what makes `cmp` against a banked fixture a
 * statement about the projection rather than about `JSON.stringify`'s insertion
 * order, and it is why the smoke's `cmp` step is worth running at all.
 */
export const projectionBody = (rows: ReadonlyArray<ProjectionRow>): string =>
  serializeRecords(rows as ReadonlyArray<unknown>);
