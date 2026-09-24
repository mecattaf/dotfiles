/**
 * projection.ts — U-A13 LAKE-PROJECTION, the part that touches nothing.
 *
 * §2.2e names one tool, `tools/ladder-projection.mjs`, and one thing it fills:
 * "`--write` fills only `actuals`, `result.grade`, `result.observed`,
 * `result.receipt_sha256`, `prior_gap`, `outcome_for_calibration` on cards (the
 * operator's fields); `status` and `outcome_ruled` never."
 *
 * This module is the operator's fields as a value. It reads no path, opens no
 * socket and writes no byte: the tool reads the register and hands what it read
 * in here as data, and the tool writes back what comes out. Everything that can
 * be decided without the disk is decided here so the suite can decide it too.
 *
 * THE THREE THINGS IT KNOWS
 *
 *   1. `bankedRowOf` — what one banked receipt says, normalised. The banked
 *      corpus is heterogeneous: MEASURED 2026-09-06 over
 *      `receipts/FACTORY-2026-09-06/*​/receipt.json`, 52 files carry `unit`,
 *      `disposition`, `verdict`, `oracle_rc`, `tokens{6 cells}` and `seconds`;
 *      27 also carry `outcome_for_calibration`, `prior_gap` and `mutation_rc`;
 *      47 carry `oracle_output_sha256`; and 0 of 52 decode under the strict
 *      §2.3 `Receipt` (U-A16) — they are the factory run's own receipts, written
 *      before that type existed. A projection that refused them would project
 *      nothing, so this reader takes the cells that are there, names the ones
 *      that are not, and never invents one.
 *
 *   2. `projectionRowOf` — the operator's fields for one unit, built from the
 *      banked cells AND from what the Factory object handed back. The evidence
 *      cells (`result.observed`, `result.grade`) come from the mirror, not from
 *      the file: a row exists only for a unit the object accepted, which is what
 *      makes `--negative-control drop-one-receipt` visible at all.
 *
 *   3. `diffProjections` — one line per disagreement, in a fixed order. Empty
 *      output is the green; every line names the unit and the cell.
 *
 * WHAT IS NOT HERE. `status` and `outcome_ruled` are absent from
 * `PROJECTION_CELLS`, from `cardCellsOf` and from every writer path — not
 * guarded against, absent. A field the writer has no name for cannot be written
 * by a mistake in the writer.
 */

/** The one release cycle this projection covers. */
export const RELEASE_CYCLE = "FACTORY-2026-09-06";

/**
 * The card cells `--write` may fill, spelled as §2.2e spells them.
 *
 * `status` and `outcome_ruled` are not here and never are. The tool's writer
 * takes its whole vocabulary from this list.
 */
export const PROJECTION_CELLS: ReadonlyArray<string> = [
  "actuals.tokens",
  "actuals.seconds",
  "actuals.outcome",
  "actuals.receipt_sha256",
  "actuals.prior_gap",
  "result.grade",
  "result.observed",
  "result.receipt_sha256",
  "outcome_for_calibration"
];

/** The cells no projection may ever write, named so the suite can assert it. */
export const NEVER_WRITTEN: ReadonlyArray<string> = ["status", "outcome_ruled"];

/** The string D-B22 gives an inapplicable field: never a null, never a guess. */
export const NONE = "none";

/** One banked receipt, normalised to the cells the projection uses. */
export interface BankedRow {
  /** The card id the receipt is banked under — the directory name. */
  readonly unit: string;
  /** The receipt path, relative to the register root. */
  readonly receipt_path: string;
  /** sha256 over the receipt's bytes, computed by the caller. */
  readonly receipt_sha256: string;
  /** `oracle_rc`, the gate metric of every card in this cycle. */
  readonly oracle_rc: number;
  /** `oracle_output_sha256`, or `"none"` where the receipt carries none. */
  readonly oracle_output_sha256: string;
  /** `mutation_rc` where the receipt carries one. */
  readonly mutation_rc: number | null;
  /** `verdict`, normalised to the mirror's vocabulary. */
  readonly outcome: "pass" | "fail";
  /** `disposition`, verbatim. */
  readonly disposition: string;
  /** `seconds`, measured. */
  readonly seconds: number;
  /** `tokens.total`, the cell the ladder's `actuals.tokens` carries. */
  readonly tokens: number;
  /** `tokens.out`, the declared cell (D-B19). */
  readonly tokens_out: number;
  /** `outcome_for_calibration` where the receipt carries one. */
  readonly outcome_for_calibration: string | null;
  /** The declared-cell prior gap, where it can be read or derived. */
  readonly prior_gap: number | null;
  /** Which cells the receipt did not carry. Reported, never filled. */
  readonly absent: ReadonlyArray<string>;
}

/** The operator's fields for one unit, as one canonical record. */
export interface ProjectionRow {
  readonly actuals: {
    readonly outcome: string;
    readonly prior_gap: number | null;
    readonly receipt_sha256: string;
    readonly seconds: number;
    readonly tokens: number;
  };
  readonly outcome_for_calibration: string | null;
  readonly receipt_path: string;
  readonly result: {
    readonly grade: "MEASURED" | "CLAIMED";
    readonly observed: number;
    readonly receipt_sha256: string;
  };
  readonly unit: string;
}

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
 * The declared-cell prior gap.
 *
 * The corpus MEASURED two spellings of `prior_gap`: the strict §2.3 block
 * `{tokens_by_cell{out, in_uncached+out, total}, ...}` (1 receipt) and the older
 * flat `{tokens_out, p_pass_vs_outcome}` (26). Both name the same cell, `out`,
 * which is the cell every prior in this cycle declares (D-B19), so both read as
 * one number. A receipt carrying neither yields `null` and is named in `absent`
 * — the gap is not derived from a prior the receipt does not carry, because a
 * number computed against an unknown prediction is not a measurement.
 */
export const priorGapOf = (value: unknown): number | null => {
  if (!isRecord(value)) return null;
  const flat = numberAt(value, "tokens_out");
  if (flat !== null) return flat;
  const byCell = value["tokens_by_cell"];
  if (isRecord(byCell)) {
    const out = numberAt(byCell, "out");
    if (out !== null) return out;
  }
  return null;
};

/** The verdict vocabulary of the banked corpus, mapped onto the mirror's. */
const outcomeOf = (verdict: unknown): "pass" | "fail" =>
  typeof verdict === "string" && verdict.trim().toUpperCase() === "PASS" ? "pass" : "fail";

/**
 * Normalise one banked receipt.
 *
 * @param unit - The card id the receipt is banked under.
 * @param receiptPath - The path, relative to the register root.
 * @param receiptSha256 - sha256 over the file's bytes.
 * @param parsed - The receipt's JSON, already parsed.
 * @returns The row, or the reason it is not one. A receipt missing a cell the
 *   projection cannot do without (`oracle_rc`, `seconds`, `tokens.total`,
 *   `disposition`, `verdict`) is refused by name rather than filled with a zero.
 */
export const bankedRowOf = (
  unit: string,
  receiptPath: string,
  receiptSha256: string,
  parsed: unknown
): { readonly ok: true; readonly row: BankedRow } | { readonly ok: false; readonly why: string } => {
  if (!isRecord(parsed)) return { ok: false, why: "the receipt is not a JSON object" };
  const missing: Array<string> = [];
  const absent: Array<string> = [];

  const oracleRc = numberAt(parsed, "oracle_rc");
  if (oracleRc === null) missing.push("oracle_rc");
  const seconds = numberAt(parsed, "seconds");
  if (seconds === null) missing.push("seconds");
  const disposition = stringAt(parsed, "disposition");
  if (disposition === null) missing.push("disposition");
  const verdict = stringAt(parsed, "verdict");
  if (verdict === null) missing.push("verdict");

  const tokensBlock = parsed["tokens"];
  const tokens = isRecord(tokensBlock) ? numberAt(tokensBlock, "total") : null;
  const tokensOut = isRecord(tokensBlock) ? numberAt(tokensBlock, "out") : null;
  if (tokens === null) missing.push("tokens.total");
  if (tokensOut === null) missing.push("tokens.out");

  if (missing.length > 0) {
    return { ok: false, why: `carries no ${missing.join(", ")}` };
  }

  const outputSha = stringAt(parsed, "oracle_output_sha256");
  if (outputSha === null) absent.push("oracle_output_sha256");
  const mutationRc = numberAt(parsed, "mutation_rc");
  if (mutationRc === null) absent.push("mutation_rc");
  const forCalibration = stringAt(parsed, "outcome_for_calibration");
  if (forCalibration === null) absent.push("outcome_for_calibration");
  const gap = priorGapOf(parsed["prior_gap"]);
  if (gap === null) absent.push("prior_gap");

  return {
    ok: true,
    row: {
      unit,
      receipt_path: receiptPath,
      receipt_sha256: receiptSha256,
      oracle_rc: oracleRc as number,
      oracle_output_sha256: outputSha ?? NONE,
      mutation_rc: mutationRc,
      outcome: outcomeOf(verdict),
      disposition: disposition as string,
      seconds: seconds as number,
      tokens: tokens as number,
      tokens_out: tokensOut as number,
      outcome_for_calibration: forCalibration,
      prior_gap: gap,
      absent
    }
  };
};

/**
 * The banked cells one projection row is built from.
 *
 * A `BankedRow` is one of these and more: the extra cells (`oracle_rc`,
 * `oracle_output_sha256`, `mutation_rc`, `outcome`) are the evidence cells, and
 * the row below never reads them from the file — it reads them from the mirror,
 * which is the whole mechanism of `--negative-control drop-one-receipt`. Naming
 * the smaller shape lets the Worker serve `GET /projection` from the receipts it
 * has itself accepted (U-A14) through this one definition of the operator's
 * fields, rather than a second copy of it.
 */
type ProjectionCells = Pick<
  BankedRow,
  | "unit"
  | "receipt_path"
  | "receipt_sha256"
  | "disposition"
  | "seconds"
  | "tokens"
  | "outcome_for_calibration"
  | "prior_gap"
>;

/** What the Factory object handed back for one unit. */
export interface MirroredEvidence {
  readonly id: string;
  readonly oracle_rc: number;
  readonly oracle_output_sha256: string;
  readonly mutation_rc?: number;
  readonly verdict_hash: string;
}

/**
 * The operator's fields for one unit.
 *
 * `result.observed` and `result.grade` are read off the MIRROR — the evidence
 * the object accepted — and not off the file the tool read. That is the whole
 * mechanism of the negative control: a receipt dropped from the load is a unit
 * the object never accepted, so no row exists for it, so `--diff` names it.
 *
 * `result.grade` is `MEASURED` when the object holds the receipt's evidence and
 * the receipt carries a measured token total; `CLAIMED` otherwise. Nothing here
 * decides `KEEP` — that is Tom's, and `outcome_ruled` is never written.
 */
export const projectionRowOf = (
  banked: ProjectionCells,
  mirrored: MirroredEvidence
): ProjectionRow => ({
  actuals: {
    outcome: banked.disposition,
    prior_gap: banked.prior_gap,
    receipt_sha256: banked.receipt_sha256,
    seconds: banked.seconds,
    tokens: banked.tokens
  },
  outcome_for_calibration: banked.outcome_for_calibration,
  receipt_path: banked.receipt_path,
  result: {
    grade: banked.tokens > 0 ? "MEASURED" : "CLAIMED",
    observed: mirrored.oracle_rc,
    receipt_sha256: banked.receipt_sha256
  },
  unit: banked.unit
});

/** The cells `--write` sets on one card, keyed by their §2.2e spelling. */
export const cardCellsOf = (row: ProjectionRow): ReadonlyMap<string, string | number | null> =>
  new Map<string, string | number | null>([
    ["actuals.tokens", row.actuals.tokens],
    ["actuals.seconds", row.actuals.seconds],
    ["actuals.outcome", row.actuals.outcome],
    ["actuals.receipt_sha256", row.actuals.receipt_sha256],
    ["actuals.prior_gap", row.actuals.prior_gap],
    ["result.grade", row.result.grade],
    ["result.observed", row.result.observed],
    ["result.receipt_sha256", row.result.receipt_sha256],
    ["outcome_for_calibration", row.outcome_for_calibration]
  ]);

/** One card as the diff needs to see it: its id, whether it maps, its cells. */
export interface CardView {
  readonly id: string;
  /** `repo:` on the card, or null. §2.2e's `unmapped`. */
  readonly repo: string | null;
  /** The card's current value for each cell of `PROJECTION_CELLS`. */
  readonly cells: ReadonlyMap<string, string | number | boolean | null>;
}

const cellText = (value: string | number | boolean | null): string =>
  value === null ? "null" : String(value);

/**
 * Whether a card cell is unwritten.
 *
 * A card minted by U-E8 carries `actuals: {tokens: null, ...}` and no `result:`
 * block at all: the operator's fields exist and are empty, which is what "not
 * yet run" looks like. An unwritten cell is not a disagreement — it is what
 * `--write` is for — so the diff is silent about it and loud about a cell that
 * carries a DIFFERENT value.
 */
const unwritten = (value: string | number | boolean | null | undefined): boolean =>
  value === undefined || value === null || value === "" || value === NONE;

/**
 * Every disagreement between the mirror and the register, one line each.
 *
 * The line vocabulary, in the order the lines are emitted:
 *
 *   `missing <unit> <path>`      the register banks a receipt the mirror has no
 *                                row for — the object never accepted it. This is
 *                                what `drop-one-receipt` produces.
 *   `extra <unit>`               the mirror holds a row the register does not
 *                                bank. The lake is a mirror and never a ledger;
 *                                a row without a banked receipt is the lake
 *                                having authored something.
 *   `cell <unit> <cell> mirror=<a> register=<b>`
 *                                two projections of the same receipt disagree.
 *   `contradiction <unit> <cell> card=<a> projection=<b>`
 *                                the card already carries a DIFFERENT value in
 *                                a cell `--write` would fill. `--write` refuses
 *                                to overwrite it; the operator settles it.
 *   `unmapped <id>`              a card carries no `repo:` (§2.2e: expected to
 *                                name 89 against the main checkout until
 *                                TL-12's merge; 0 against the named worktree).
 *
 * @param mirror - Rows read back out of the Factory object.
 * @param register - Rows computed straight off the register's banked receipts.
 * @param cards - The register's ladder cards.
 * @returns The lines, sorted within each kind by unit id. Empty is the green.
 */
export const diffProjections = (
  mirror: ReadonlyArray<ProjectionRow>,
  register: ReadonlyArray<ProjectionRow>,
  cards: ReadonlyArray<CardView>
): ReadonlyArray<string> => {
  const lines: Array<string> = [];
  const byUnit = new Map(mirror.map((row) => [row.unit, row]));
  const registerByUnit = new Map(register.map((row) => [row.unit, row]));

  for (const row of [...register].sort((a, b) => a.unit.localeCompare(b.unit))) {
    if (!byUnit.has(row.unit)) lines.push(`missing ${row.unit} ${row.receipt_path}`);
  }
  for (const row of [...mirror].sort((a, b) => a.unit.localeCompare(b.unit))) {
    if (!registerByUnit.has(row.unit)) lines.push(`extra ${row.unit}`);
  }
  for (const row of [...mirror].sort((a, b) => a.unit.localeCompare(b.unit))) {
    const other = registerByUnit.get(row.unit);
    if (other === undefined) continue;
    const here = cardCellsOf(row);
    const there = cardCellsOf(other);
    for (const cell of PROJECTION_CELLS) {
      const a = here.get(cell) ?? null;
      const b = there.get(cell) ?? null;
      if (cellText(a) !== cellText(b)) {
        lines.push(`cell ${row.unit} ${cell} mirror=${cellText(a)} register=${cellText(b)}`);
      }
    }
  }

  const cardById = new Map(cards.map((card) => [card.id, card]));
  for (const row of [...mirror].sort((a, b) => a.unit.localeCompare(b.unit))) {
    const card = cardById.get(row.unit);
    if (card === undefined) continue;
    for (const [cell, projected] of cardCellsOf(row)) {
      const current = card.cells.get(cell);
      if (unwritten(current)) continue;
      if (projected === null) continue;
      if (cellText(current ?? null) !== cellText(projected)) {
        lines.push(
          `contradiction ${row.unit} ${cell} card=${cellText(current ?? null)} projection=${cellText(projected)}`
        );
      }
    }
  }

  for (const card of [...cards].sort((a, b) => a.id.localeCompare(b.id))) {
    if (card.repo === null || card.repo === "") lines.push(`unmapped ${card.id}`);
  }

  return lines;
};
