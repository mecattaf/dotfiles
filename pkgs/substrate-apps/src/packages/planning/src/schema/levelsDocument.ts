/**
 * The levels document, read as data.
 *
 * §2.2c: the level list is *"a hashed, authored document in the Factory object,
 * and re-ordering it is a data edit and never a deploy"*. `levels.ts` is the
 * type; this is the reader for the document that authors it, so the hierarchy
 * can be edited in `docs/levels.md` by a human and picked up by a tool without
 * anything being retyped into a constant.
 *
 * IT PARSES BY SHAPE AND NEVER BY LAYOUT. The idiom is `apps/uplink/src/rows.mjs`
 * reading the kernel's `docs/rows.md`: a table is a header line, a separator
 * line and the run of pipe lines after it; the level table is the one whose
 * header begins `| level | ordinal |` and the lane table is the one whose header
 * begins `| lane | value |`. No heading, no line number and no ordering of the
 * document's sections is depended on, because a document a human edits must be
 * read by its shape.
 *
 * IT REFUSES RATHER THAN GUESSES (H-16). A missing table, a level with a
 * non-integer ordinal, a duplicate level name, a lane naming a level the table
 * does not declare, and a lane whose promotion target is not declared are each a
 * named refusal carrying the path. A default here would be this module having an
 * opinion about Tom's priorities.
 *
 * THE HASH IS OVER THE BYTES IT READ. `LevelList.hash` is there so a release can
 * cite the hierarchy it obeyed; the digest is taken by the caller, because this
 * package imports nothing but `effect` and a digest needs a platform primitive
 * (`objects/hasher.ts` says the same for artifacts).
 */
import { Schema } from "effect";
import { LevelList } from "./levels.ts";
import type { FillerLane } from "../heuristics/fillerLane.ts";
import { FamilyName, LevelName, RowName } from "./ids.ts";

const decodeLevelList = Schema.decodeUnknownSync(LevelList);
const decodeLevelName = Schema.decodeUnknownSync(LevelName);
const decodeRowName = Schema.decodeUnknownSync(RowName);
const decodeFamilyName = Schema.decodeUnknownSync(FamilyName);

/** Raised by every refusal here; carries the document it was reading. */
export class LevelsDocumentError extends Error {
  readonly path: string;
  constructor(message: string, path: string) {
    super(message);
    this.name = "LevelsDocumentError";
    this.path = path;
  }
}

/** One markdown pipe table, as a header and its body rows. */
interface Table {
  readonly header: ReadonlyArray<string>;
  readonly body: ReadonlyArray<ReadonlyArray<string>>;
}

/** Splits one table line into its cells, without the outer pipes. */
const cells = (line: string): ReadonlyArray<string> => {
  const trimmed = line.trim();
  const inner = trimmed.slice(
    trimmed.startsWith("|") ? 1 : 0,
    trimmed.endsWith("|") ? -1 : undefined
  );
  return inner.split("|").map((cell) => cell.trim());
};

/**
 * `` `filler` `` and `**filler**` are the same word written two ways.
 *
 * Backticks and asterisks only. An underscore is a character IN a level name and
 * in a column name (`wip_cap`), never emphasis.
 */
const plain = (cell: string): string => cell.replace(/[`*]/g, "").trim();

/** A table's separator line: `|---|:--:|` and nothing else. */
const isSeparator = (line: string): boolean =>
  /^\s*\|?[\s:|-]+\|[\s:|-]*$/.test(line) && line.includes("-");

/** Every pipe table in a document, in the order they appear. */
const tables = (text: string): ReadonlyArray<Table> => {
  const lines = text.split("\n");
  const found: Array<Table> = [];
  for (let index = 0; index + 1 < lines.length; index += 1) {
    if (!lines[index]!.includes("|")) continue;
    if (!isSeparator(lines[index + 1]!)) continue;
    const header = cells(lines[index]!).map((cell) => plain(cell).toLowerCase());
    const body: Array<ReadonlyArray<string>> = [];
    let cursor = index + 2;
    while (
      cursor < lines.length &&
      lines[cursor]!.includes("|") &&
      !isSeparator(lines[cursor]!)
    ) {
      body.push(cells(lines[cursor]!));
      cursor += 1;
    }
    found.push({ header, body });
    index = cursor - 1;
  }
  return found;
};

/** A whole-number cell, or `null` when the document does not give one. */
const integer = (cell: string): number | null => {
  const text = plain(cell).replace(/[,\s]/g, "");
  return /^-?\d+$/.test(text) ? Number(text) : null;
};

/** A comma-separated cell, in the order it is written; empties dropped. */
const list = (cell: string): ReadonlyArray<string> =>
  plain(cell)
    .split(",")
    .map((entry) => plain(entry))
    .filter((entry) => entry !== "");

/** What one levels document carries. */
interface LevelsDocument {
  /** The document's own path, for a diagnostic that names it. */
  readonly path: string;
  /** The authored hierarchy, decoded through the schema that owns it. */
  readonly levels: LevelList;
  /** The filler lane, or `null` when the document declares none. */
  readonly filler: FillerLane | null;
}

/**
 * Reads a levels document.
 *
 * @param text - The document's bytes.
 * @param path - Where they came from; carried on every refusal, and never read.
 * @param hash - The digest of those bytes, taken by the caller, which the level
 *   list carries so a release can cite the hierarchy it obeyed.
 * @returns The hierarchy and the lane.
 */
export const parseLevelsDocument = (
  text: string,
  path: string,
  hash: string
): LevelsDocument => {
  const all = tables(text);

  const levelTable = all.find(
    (table) => table.header[0] === "level" && table.header[1] === "ordinal"
  );
  if (levelTable === undefined) {
    throw new LevelsDocumentError(
      `${path} carries no level table: no table whose header begins | level | ordinal |`,
      path
    );
  }

  const at = (header: ReadonlyArray<string>, name: string): number =>
    header.findIndex((cell) => cell.startsWith(name));
  const familiesAt = at(levelTable.header, "families");
  const capAt = at(levelTable.header, "wip_cap");
  if (familiesAt < 0 || capAt < 0) {
    throw new LevelsDocumentError(
      `${path}: the level table needs a families column and a wip_cap column`,
      path
    );
  }

  const seen = new Set<string>();
  const rows: Array<{
    readonly name: string;
    readonly ordinal: number;
    readonly families: ReadonlyArray<string>;
    readonly wipCap: number;
  }> = [];
  for (const body of levelTable.body) {
    const name = plain(body[0] ?? "");
    if (name === "") continue;
    if (seen.has(name)) {
      throw new LevelsDocumentError(`${path}: level ${name} is declared twice`, path);
    }
    seen.add(name);
    const ordinal = integer(body[1] ?? "");
    const wipCap = integer(body[capAt] ?? "");
    if (ordinal === null) {
      throw new LevelsDocumentError(
        `${path}: level ${name} has no whole-number ordinal`,
        path
      );
    }
    if (wipCap === null) {
      throw new LevelsDocumentError(
        `${path}: level ${name} has no whole-number wip_cap`,
        path
      );
    }
    const families = list(body[familiesAt] ?? "");
    if (families.length === 0) {
      throw new LevelsDocumentError(
        `${path}: level ${name} declares no goal family`,
        path
      );
    }
    rows.push({ name, ordinal, families, wipCap });
  }
  if (rows.length === 0) {
    throw new LevelsDocumentError(`${path}: the level table has no rows`, path);
  }

  const levels = decodeLevelList({ hash, levels: rows });

  return { path, levels, filler: parseLane(all, rows, path) };
};

/** The lane table, when the document declares one. */
const parseLane = (
  all: ReadonlyArray<Table>,
  rows: ReadonlyArray<{ readonly name: string }>,
  path: string
): FillerLane | null => {
  const laneTable = all.find(
    (table) => table.header[0] === "lane" && table.header[1] === "value"
  );
  if (laneTable === undefined) return null;

  const value = new Map<string, string>();
  for (const body of laneTable.body) {
    const key = plain(body[0] ?? "");
    if (key === "") continue;
    value.set(key, plain(body[1] ?? ""));
  }

  const required = ["level", "row", "promote_after", "promote_to"];
  const missing = required.filter((key) => (value.get(key) ?? "") === "");
  if (missing.length > 0) {
    throw new LevelsDocumentError(
      `${path}: the lane table is missing ${missing.join(", ")}`,
      path
    );
  }

  const declared = new Set(rows.map((row) => row.name));
  for (const key of ["level", "promote_to"]) {
    const name = value.get(key)!;
    if (!declared.has(name)) {
      throw new LevelsDocumentError(
        `${path}: the lane's ${key} names ${name}, which the level table does not declare`,
        path
      );
    }
  }

  const promoteAfter = integer(value.get("promote_after")!);
  if (promoteAfter === null || promoteAfter < 1) {
    throw new LevelsDocumentError(
      `${path}: the lane's promote_after must be a whole number of passes above zero`,
      path
    );
  }
  const abort = integer(value.get("abort_on.consecutive_crash") ?? "");
  if (abort === null) {
    throw new LevelsDocumentError(
      `${path}: the lane declares no whole-number abort_on.consecutive_crash (D-B10)`,
      path
    );
  }

  return {
    level: decodeLevelName(value.get("level")!),
    row: decodeRowName(value.get("row")!),
    promoteAfter,
    promoteTo: decodeLevelName(value.get("promote_to")!),
    abortOnConsecutiveCrash: abort
  };
};

/**
 * The fillers the document's lane declares, in the order they alternate.
 *
 * Convenience over `fillerSources`, parsed into the brand so a caller that
 * compares a family name against one of these compares two branded values.
 */
export const documentFillers = (
  document: LevelsDocument
): ReadonlyArray<FamilyName> => {
  if (document.filler === null) return [];
  const level = document.levels.levels.find(
    (entry) => entry.name === document.filler!.level
  );
  return (level?.families ?? []).map((family) => decodeFamilyName(family));
};
