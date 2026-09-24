/**
 * The selector's two tables, joined onto the backlog and onto the release.
 *
 * Spec §2.8, U-A24: *"the lake reads `cards/selection-<pass>.tsv` and
 * `bands.tsv` into `BacklogItem.estimate {yieldRate, p80Consumption,
 * shrinkageWeight}` and stamps `prior{prior_source: band, thompson{seed, alpha,
 * beta}}` on the release — the selector as data; the lake never chooses."*
 *
 * Two verbs and no third. **Decode**, in `schema/selectionDocument.ts`: the
 * files become values, and every disagreement between what a row states and what
 * its own numbers say is a refusal. **Join**, here: a decoded row becomes an
 * `Estimate` on the backlog item whose task id is the rung, and a `PriorStamp`
 * the release evaluator copies onto the admit.
 *
 * THE UNIT'S NON-GOAL IS "NO SELECTION LOGIC IN THE LAKE", AND THIS IS WHERE IT
 * WOULD HAVE GONE. There is no comparator in this file. `rank`, `precedence` and
 * `thompsonDraw` are on the decoded rows and are read by nothing: the release
 * evaluator orders by the lexicographic hierarchy and value density, exactly as
 * it did before this unit, over estimates that now come from measurement instead
 * of from a fixture. The one thing the selector's ordering does here is get
 * carried to the receipt, so that what was released can be scored against the
 * prior it was released under (§6.2 B11).
 *
 * WHAT THE JOIN DOES NOT SUPPLY. The selection file carries no service times, so
 * `medianSeconds`, `p80Seconds` and `p99Seconds` come from the estimate table's
 * main effects unchanged. The register measures out-tokens and outcomes; it does
 * not measure wall-clock, and inventing a median here would be this package
 * estimating from its own history, which the estimate table's own
 * `shrinkageWeight` column exists to prevent.
 */
import { Option, Schema } from "effect";
import type { BacklogItem } from "../schema/backlog.ts";
import { Estimate } from "../schema/estimate.ts";
import { TaskId } from "../schema/ids.ts";
import type { Band, PriorStamp, SelectionRow, SelectionTable } from "../schema/selection.ts";
import { readBandsDocument, readSelectionDocument } from "../schema/selectionDocument.ts";

const decodeEstimate = Schema.decodeUnknownSync(Estimate);
const decodeTaskId = Schema.decodeUnknownSync(TaskId);

/**
 * One selection row as an estimate.
 *
 * @param row - A decoded selection row.
 * @param mainEffect - The estimate table's main effects, which supply the three
 *   service-time quantiles the selector does not measure.
 * @returns The estimate to put on the item, carrying the selector's yield rate,
 *   its p80 consumption and the shrinkage weight derived from `n`.
 */
const estimateFromSelection = (
  row: SelectionRow,
  mainEffect: Estimate
): Estimate =>
  decodeEstimate({
    medianSeconds: mainEffect.medianSeconds,
    p80Seconds: mainEffect.p80Seconds,
    p99Seconds: mainEffect.p99Seconds,
    // The class's measured p80 out-token consumption. A row whose class has no
    // measured cost keeps the main effects' number rather than a zero, because
    // zero is "this lane is free" and would make the envelope test vacuous.
    p80Consumption: Option.getOrElse(row.p80Consumption, () => mainEffect.p80Consumption),
    // The band's mean, verbatim. `selectionDocument.ts` has already refused the
    // row if it disagrees with the band it names.
    yieldRate: row.yieldRate,
    observations: row.n,
    // `n / (n + 4)`, derived at decode and never read off the column.
    shrinkageWeight: row.shrinkageWeight
  });

/**
 * One selection row as the prior stamp its release carries.
 *
 * @param row - A decoded selection row.
 * @returns `{prior_source}` on a pass that drew nothing, and
 *   `{prior_source, thompson{seed, alpha, beta}}` where a draw was recorded.
 */
const priorStampOf = (row: SelectionRow): PriorStamp =>
  Option.isSome(row.thompson)
    ? { prior_source: row.priorSource, thompson: row.thompson.value }
    : { prior_source: row.priorSource };

/** Both documents, decoded and joined, ready for a backlog and a release. */
export interface SelectorReading {
  /** The decoded selection table, in file order. */
  readonly table: SelectionTable;
  /** The decoded band table. */
  readonly bands: ReadonlyArray<Band>;
  /** The estimate per task id, for the items the selection names. */
  readonly estimates: ReadonlyMap<TaskId, Estimate>;
  /** The prior stamp per task id, for the release to carry. */
  readonly priors: ReadonlyMap<TaskId, PriorStamp>;
}

/** The bytes of one document and where they came from. */
interface SelectorSource {
  /** The document's contents. */
  readonly text: string;
  /** Its path, for a diagnostic that names it. This package opens no file. */
  readonly path: string;
}

/**
 * Reads both documents and joins them.
 *
 * Only **admitted** rows produce an estimate and a stamp. A row contamination
 * held back stays in the decoded table by name — that is the register's whole
 * reason for keeping it — but it is not a release candidate, and priming the
 * backlog from it would put a held rung's numbers on an item that must not run.
 *
 * @param selection - `cards/selection-<pass>.tsv`.
 * @param bands - `cards/bands.tsv`.
 * @param mainEffect - The main effects the service-time quantiles come from.
 * @returns The joined reading.
 * @throws SelectionDocumentError - On any refusal either document raises.
 */
export const readSelector = (
  selection: SelectorSource,
  bands: SelectorSource,
  mainEffect: Estimate
): SelectorReading => {
  const bandRows = readBandsDocument(bands.text, bands.path);
  const table = readSelectionDocument(selection.text, selection.path, bandRows);
  const estimates = new Map<TaskId, Estimate>();
  const priors = new Map<TaskId, PriorStamp>();
  for (const row of table.rows) {
    if (!row.admitted) continue;
    const id = decodeTaskId(row.rung);
    estimates.set(id, estimateFromSelection(row, mainEffect));
    priors.set(id, priorStampOf(row));
  }
  return { table, bands: bandRows, estimates, priors };
};

/**
 * Puts the selector's estimates on the backlog items they name.
 *
 * Order is preserved and membership is unchanged: an item the selection does not
 * name keeps the estimate it had, and no item is added, dropped or moved. This
 * function is a `map`, and it is written as one on purpose — a `sort` here would
 * be the lake choosing.
 *
 * @param items - The backlog.
 * @param reading - The joined selector reading.
 * @returns The backlog, in the same order, with estimates replaced where the
 *   selection has one.
 */
export const applySelectorEstimates = (
  items: ReadonlyArray<BacklogItem>,
  reading: SelectorReading
): ReadonlyArray<BacklogItem> =>
  items.map((item) => {
    const estimate = reading.estimates.get(item.taskId);
    return estimate === undefined ? item : { ...item, estimate };
  });
