/**
 * `cards/bands.tsv` and `cards/selection-<pass>.tsv`, read as data.
 *
 * `selection.ts` is the type; this is the reader for the two documents another
 * repository authors, so the selector's numbers can be edited by
 * `bin/register bands` and `bin/register next` in `/home/tom/research-methods`
 * and picked up here without anything being retyped into a constant. The idiom
 * is `levelsDocument.ts` reading `docs/levels.md`, and every rule below is that
 * module's rule.
 *
 * IT PARSES BY SHAPE AND NEVER BY LAYOUT. A `#` line is a comment, the first
 * non-comment line is the header, and a column is found by name. Column order
 * may move, comments may be added, and the reader does not notice. The two
 * header facts a selection file carries in prose — `# pass:` and `# arm:` — are
 * read by their key and not by their line number.
 *
 * IT REFUSES RATHER THAN GUESSES (H-16). A missing column, a row whose width is
 * not the header's, a duplicate cell, a `score` column on a band table, a
 * band-sourced row whose band is absent, a stated `shrinkage_weight` that is not
 * `n / (n + 4)`, a stated `yield_rate` that is not the band's mean, and a
 * pass-2 admitted row with no recorded draw are each a named refusal carrying
 * the document's path. A default here would be this package inventing a belief
 * about a cell, which is the one thing §2.8 says it must never do.
 *
 * IT DERIVES THE TWO NUMBERS IT USES AND CHECKS THE RECORD AGAINST THEM. The
 * `shrinkage_weight` a file states is printed to six decimals; the weight this
 * package hands to the release evaluator is `n / (n + 4)` computed here, and
 * the stated column is checked against it within one part in a million. Reading
 * the column and trusting it would make a mutated `n` invisible — which is
 * exactly this unit's negative control.
 *
 * NOTHING HERE SORTS. `rank`, `precedence` and `thompson_draw` are decoded and
 * carried; no comparator in this package reads them. The selector chooses; the
 * lake reads (spec §4.4 rule 5).
 */
import { Schema } from "effect";
import { Band, SelectionRow, SELECTOR_PSEUDO_COUNT } from "./selection.ts";
import type { SelectionTable } from "./selection.ts";

const decodeBand = Schema.decodeUnknownSync(Band);
const decodeSelectionRow = Schema.decodeUnknownSync(SelectionRow);

/** Raised by every refusal here; carries the document it was reading. */
export class SelectionDocumentError extends Error {
  readonly path: string;
  constructor(message: string, path: string) {
    super(message);
    this.name = "SelectionDocumentError";
    this.path = path;
  }
}

/**
 * How far a printed number may sit from the number it stands for.
 *
 * The register prints six decimals, so a value rounded there differs from the
 * exact quotient by at most `5e-7`. One part in a million admits that rounding
 * and nothing else: `7/11` prints `0.636364` and passes, while a row whose `n`
 * moved from 7 to 6 states `0.636364` against a derived `0.6` and fails by four
 * orders of magnitude.
 */
const PRINTED_TOLERANCE = 1e-6;

/** The word the register writes where a cell has no value. */
const NULL_CELL = "-";

/** `n / (n + 4)`: the weight the lake computes and the register agrees with. */
export const shrinkageFromObservations = (observations: number): number =>
  observations / (observations + SELECTOR_PSEUDO_COUNT);

/** One document's rows, keyed by the header's column names. */
interface Rows {
  readonly header: ReadonlyArray<string>;
  readonly rows: ReadonlyArray<{
    readonly line: number;
    readonly cells: Record<string, string>;
  }>;
}

/**
 * A comment-tolerant TSV whose every physical row carries the header's width.
 *
 * The width rule is the register's own (`read_strict_tsv`): a row with a cell
 * too few is a row whose columns have all shifted by one, and a reader that
 * accepts it reads the wrong number out of the right-hand columns forever.
 */
const readStrictTsv = (text: string, path: string): Rows => {
  const numbered = text
    .split("\n")
    .map((line, index) => ({ line: index + 1, text: line }))
    .filter((entry) => entry.text.trim() !== "" && !entry.text.trimStart().startsWith("#"));
  if (numbered.length === 0) {
    throw new SelectionDocumentError("empty TSV: no header line", path);
  }
  const header = numbered[0]!.text.split("\t").map((cell) => cell.trim());
  if (new Set(header).size !== header.length) {
    throw new SelectionDocumentError("duplicate column name in the header", path);
  }
  const rows = numbered.slice(1).map((entry) => {
    const values = entry.text.split("\t");
    if (values.length !== header.length) {
      throw new SelectionDocumentError(
        `line ${entry.line} has ${values.length} cells, want ${header.length}`,
        path
      );
    }
    const cells: Record<string, string> = {};
    header.forEach((name, index) => {
      cells[name] = values[index]!.trim();
    });
    return { line: entry.line, cells };
  });
  return { header, rows };
};

/** Every `# key: value` line of a document, by key, first occurrence winning. */
const commentFields = (text: string): ReadonlyMap<string, string> => {
  const fields = new Map<string, string>();
  for (const line of text.split("\n")) {
    const trimmed = line.trimStart();
    if (!trimmed.startsWith("#")) continue;
    const body = trimmed.slice(1).trim();
    const colon = body.indexOf(":");
    if (colon <= 0) continue;
    const key = body.slice(0, colon).trim();
    if (!fields.has(key)) fields.set(key, body.slice(colon + 1).trim());
  }
  return fields;
};

/** Refuses unless every named column is on the header. */
const requireColumns = (rows: Rows, columns: ReadonlyArray<string>, path: string): void => {
  const missing = columns.filter((column) => !rows.header.includes(column));
  if (missing.length > 0) {
    throw new SelectionDocumentError(`columns missing: ${missing.join(", ")}`, path);
  }
};

const numeric = (
  cells: Record<string, string>,
  column: string,
  line: number,
  path: string
): number => {
  const raw = cells[column] ?? "";
  const value = Number(raw);
  if (raw === "" || !Number.isFinite(value)) {
    throw new SelectionDocumentError(
      `line ${line}: ${column} is ${JSON.stringify(raw)}, want a finite number`,
      path
    );
  }
  return value;
};

const optionalNumeric = (
  cells: Record<string, string>,
  column: string,
  line: number,
  path: string
): number | null =>
  (cells[column] ?? "") === NULL_CELL ? null : numeric(cells, column, line, path);

const close = (left: number, right: number): boolean =>
  Math.abs(left - right) <= PRINTED_TOLERANCE;

/**
 * Reads `cards/bands.tsv`.
 *
 * @param text - The document's bytes.
 * @param path - Where they came from, for a diagnostic that names it.
 * @returns One `Band` per row, in file order.
 * @throws SelectionDocumentError - On any refusal above.
 */
export const readBandsDocument = (text: string, path: string): ReadonlyArray<Band> => {
  const table = readStrictTsv(text, path);
  // The register repeats this guard at every reader, and so does this one: a
  // band is a belief about a cell and never a ranking, so a `score` column
  // reaching the lake would be a selector smuggled in through the back door.
  const score = table.header.find((column) => column.toLowerCase() === "score");
  if (score !== undefined) {
    throw new SelectionDocumentError(
      `a ${JSON.stringify(score)} column is present; bands never carry a score`,
      path
    );
  }
  requireColumns(
    table,
    ["class", "arm", "n", "m", "passes", "fails", "alpha", "beta", "mean", "p05", "p95",
      "shrinkage_weight"],
    path
  );

  const seen = new Set<string>();
  return table.rows.map(({ line, cells }) => {
    const key = `${cells["class"]}\t${cells["arm"]}`;
    if (seen.has(key)) {
      throw new SelectionDocumentError(
        `line ${line}: duplicate cell (${cells["class"]} x ${cells["arm"]})`,
        path
      );
    }
    seen.add(key);

    const n = numeric(cells, "n", line, path);
    const alpha = numeric(cells, "alpha", line, path);
    const beta = numeric(cells, "beta", line, path);
    const mean = numeric(cells, "mean", line, path);
    const stated = numeric(cells, "shrinkage_weight", line, path);

    // The shrinkage clause, on the band's own row. Mutating `n` here moves the
    // derived weight and leaves the printed column where it was.
    const derived = shrinkageFromObservations(n);
    if (!close(stated, derived)) {
      throw new SelectionDocumentError(
        `line ${line}: (${cells["class"]} x ${cells["arm"]}) states ` +
          `shrinkage_weight ${stated}, but n = ${n} gives n/(n+${SELECTOR_PSEUDO_COUNT}) ` +
          `= ${derived}`,
        path
      );
    }
    if (!close(mean, alpha / (alpha + beta))) {
      throw new SelectionDocumentError(
        `line ${line}: (${cells["class"]} x ${cells["arm"]}) states mean ${mean}, ` +
          `but alpha/(alpha+beta) = ${alpha / (alpha + beta)}`,
        path
      );
    }

    return decodeBand({
      useCaseClass: cells["class"],
      arm: cells["arm"],
      n,
      m: numeric(cells, "m", line, path),
      passes: numeric(cells, "passes", line, path),
      fails: numeric(cells, "fails", line, path),
      alpha,
      beta,
      mean,
      p05: numeric(cells, "p05", line, path),
      p95: numeric(cells, "p95", line, path),
      shrinkageWeight: derived
    });
  });
};

/** The band for one `(class, arm)` cell, or `undefined` when there is none. */
export const bandFor = (
  bands: ReadonlyArray<Band>,
  useCaseClass: string,
  arm: string
): Band | undefined =>
  bands.find((band) => band.useCaseClass === useCaseClass && band.arm === arm);

/**
 * Reads `cards/selection-<pass>.tsv` against the bands it was priced from.
 *
 * @param text - The document's bytes.
 * @param path - Where they came from, for a diagnostic that names it.
 * @param bands - The band table `readBandsDocument` returned. A band-sourced row
 *   whose cell is absent from it is a refusal: the file says the number came
 *   from a posterior, and the posterior has to be there to be checked.
 * @returns The decoded table, in file order.
 * @throws SelectionDocumentError - On any refusal above.
 */
export const readSelectionDocument = (
  text: string,
  path: string,
  bands: ReadonlyArray<Band>
): SelectionTable => {
  const table = readStrictTsv(text, path);
  requireColumns(
    table,
    ["rank", "rung", "repo", "class", "arm", "attempt", "admitted", "precedence",
      "cost_frontier_out", "yield_rate", "p80_consumption", "shrinkage_weight", "n", "m",
      "alpha", "beta", "prior_source", "thompson_seed", "thompson_draw", "reason",
      "selection_note"],
    path
  );

  const fields = commentFields(text);
  const declaredPass = fields.get("pass");
  const declaredArm = fields.get("arm");
  if (declaredPass === undefined || !/^\d+$/.test(declaredPass)) {
    throw new SelectionDocumentError(
      "no `# pass: <n>` line; a selection with no pass number cannot be joined to a draw",
      path
    );
  }
  if (declaredArm === undefined || declaredArm === "") {
    throw new SelectionDocumentError("no `# arm: <arm>` line", path);
  }
  const pass = Number(declaredPass);

  const seen = new Set<string>();
  const rows = table.rows.map(({ line, cells }) => {
    const rung = cells["rung"] ?? "";
    if (rung === "") {
      throw new SelectionDocumentError(`line ${line}: rung is empty`, path);
    }
    if (seen.has(rung)) {
      throw new SelectionDocumentError(`line ${line}: duplicate rung ${rung}`, path);
    }
    seen.add(rung);

    const admittedCell = cells["admitted"];
    if (admittedCell !== "Y" && admittedCell !== "N") {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} has admitted ${JSON.stringify(admittedCell)}, want Y or N`,
        path
      );
    }
    const admitted = admittedCell === "Y";

    const priorSource = cells["prior_source"];
    if (priorSource !== "band" && priorSource !== "prior") {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} has prior_source ${JSON.stringify(priorSource)}, ` +
          "want band or prior",
        path
      );
    }

    const n = numeric(cells, "n", line, path);
    const alpha = numeric(cells, "alpha", line, path);
    const beta = numeric(cells, "beta", line, path);
    const yieldRate = numeric(cells, "yield_rate", line, path);
    const statedWeight = numeric(cells, "shrinkage_weight", line, path);

    // The shrinkage clause, on the selection's own row, checked before anything
    // is asked of the band: the mutation of record is a row's `n`, and this is
    // the assertion it must turn red.
    const derivedWeight = shrinkageFromObservations(n);
    if (!close(statedWeight, derivedWeight)) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} states shrinkage_weight ${statedWeight}, but n = ${n} ` +
          `gives n/(n+${SELECTOR_PSEUDO_COUNT}) = ${derivedWeight}`,
        path
      );
    }

    const useCaseClass = (cells["class"] ?? "") === NULL_CELL ? null : cells["class"]!;
    if (priorSource === "band") {
      if (useCaseClass === null) {
        throw new SelectionDocumentError(
          `line ${line}: ${rung} is band-sourced with no class`,
          path
        );
      }
      const band = bandFor(bands, useCaseClass, cells["arm"] ?? "");
      if (band === undefined) {
        throw new SelectionDocumentError(
          `line ${line}: ${rung} is band-sourced but (${useCaseClass} x ` +
            `${cells["arm"]}) is absent from the band table`,
          path
        );
      }
      if (band.n !== n || band.m !== numeric(cells, "m", line, path)) {
        throw new SelectionDocumentError(
          `line ${line}: ${rung} states n=${n}, m=${cells["m"]}; the band states ` +
            `n=${band.n}, m=${band.m}`,
          path
        );
      }
      if (band.alpha !== alpha || band.beta !== beta) {
        throw new SelectionDocumentError(
          `line ${line}: ${rung} states Beta(${alpha}, ${beta}); the band states ` +
            `Beta(${band.alpha}, ${band.beta})`,
          path
        );
      }
      // The oracle's first clause: the yield rate a band-sourced row carries is
      // the band's mean and is never re-derived here.
      if (yieldRate !== band.mean) {
        throw new SelectionDocumentError(
          `line ${line}: ${rung} states yield_rate ${yieldRate}; the band's mean is ` +
            `${band.mean}`,
          path
        );
      }
    } else if (!close(yieldRate, alpha / (alpha + beta))) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} states yield_rate ${yieldRate} against Beta(${alpha}, ` +
          `${beta})`,
        path
      );
    }

    const seed = cells["thompson_seed"] ?? NULL_CELL;
    const draw = optionalNumeric(cells, "thompson_draw", line, path);
    const drew = seed !== NULL_CELL;
    if (drew !== (draw !== null)) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} records ${drew ? "a seed with no draw" : "a draw with no seed"}`,
        path
      );
    }
    // Pass 1 orders by measured cost and draws nothing; from pass 2 every
    // admitted row draws. A release stamped from a drawn pass with no draw on
    // the row would be a prior scored that was not the prior used (§6.2 B11).
    if (pass >= 2 && admitted && !drew) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} is admitted on pass ${pass} with no Thompson draw recorded`,
        path
      );
    }
    if (pass < 2 && drew) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} records a Thompson draw on pass ${pass}; the draw ` +
          "begins at pass 2",
        path
      );
    }
    if (drew && !/^[0-9]+$/.test(seed)) {
      throw new SelectionDocumentError(
        `line ${line}: ${rung} has thompson_seed ${JSON.stringify(seed)}, want decimal digits`,
        path
      );
    }

    return decodeSelectionRow({
      rank: (cells["rank"] ?? NULL_CELL) === NULL_CELL
        ? null
        : numeric(cells, "rank", line, path),
      rung,
      repo: cells["repo"] ?? "",
      useCaseClass,
      arm: cells["arm"] ?? "",
      attempt: numeric(cells, "attempt", line, path),
      admitted,
      precedence: numeric(cells, "precedence", line, path),
      costFrontierOut: optionalNumeric(cells, "cost_frontier_out", line, path),
      yieldRate,
      p80Consumption: optionalNumeric(cells, "p80_consumption", line, path),
      shrinkageWeight: derivedWeight,
      n,
      m: numeric(cells, "m", line, path),
      alpha,
      beta,
      priorSource,
      thompson: drew ? { seed, alpha, beta } : null,
      thompsonDraw: draw,
      reason: cells["reason"] ?? "",
      selectionNote: cells["selection_note"] ?? ""
    });
  });

  // The rows are already values: `decodeSelectionRow` ran on each as it was
  // read, so decoding the table again here would hand an `Option` to a decoder
  // that wants the `null` it came from.
  return { pass, arm: declaredArm, rows };
};
