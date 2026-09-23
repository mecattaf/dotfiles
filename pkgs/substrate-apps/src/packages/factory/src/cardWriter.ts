/**
 * cardWriter.ts — U-A13 LAKE-PROJECTION, the writer.
 *
 * §2.2e: "`--write` fills only `actuals`, `result.grade`, `result.observed`,
 * `result.receipt_sha256`, `prior_gap`, `outcome_for_calibration` on cards (the
 * operator's fields); `status` and `outcome_ruled` never."
 *
 * LINE-ORIENTED, NOT A YAML EMITTER. A card is a file a human wrote: it carries
 * trailing comments (`status: DRAFT          # DRAFT -> ARMED -> …`), block
 * scalars, and a field order someone chose. Re-emitting its front matter from a
 * parsed value would rewrite every one of those and the diff would be a diff of
 * this tool's formatting opinions. So the writer finds the ONE line a cell lives
 * on and replaces the text after the colon, keeping the trailing comment byte
 * for byte; a cell with no line yet is appended to its block.
 *
 * THE FENCE IS THE VOCABULARY. `applyCells` writes the keys it is handed and has
 * no path that constructs a key of its own. `status` and `outcome_ruled` are
 * never in `PROJECTION_CELLS`, so no value the tool computes can name them —
 * and `fencedLines` lets the caller re-read the result and refuse anyway,
 * because a fence that is only an argument about scope is not a fence.
 *
 * IDEMPOTENT BY CONSTRUCTION. Values render through one function, and a cell
 * already carrying its rendered form is replaced by the same bytes. Applying the
 * same card twice is a no-op, which is the issue's "Re-applying the same card
 * reports zero changes" read at the level of the file.
 */
import { Frontmatter } from "@substrate/schema";
import { NEVER_WRITTEN } from "./projection.ts";

/** One cell value, rendered as the front matter spells it. */
const renderValue = (value: string | number | boolean | null): string => {
  if (value === null) return "null";
  if (typeof value === "number") return String(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  return JSON.stringify(value);
};

/**
 * The trailing `# …` comment of a front-matter line, with the whitespace that
 * separated it from the value, or the empty string.
 *
 * The padding comes along because it is part of what the human wrote: a card
 * that reads `status: DRAFT          # DRAFT -> ARMED -> …` keeps its column
 * when a value beside it changes, and a line with no comment gains no trailing
 * space.
 */
const trailingComment = (line: string): string => {
  const stripped = Frontmatter.stripComment(line);
  const comment = line.slice(stripped.length);
  if (comment === "") return "";
  return stripped.slice(stripped.trimEnd().length) + comment;
};

const indentOf = (line: string): number => line.length - line.replace(/^ +/, "").length;

/** The half-open line range of the block opened at `head`, by indentation. */
const blockRange = (
  lines: ReadonlyArray<string>,
  head: number
): { readonly start: number; readonly end: number; readonly indent: number } => {
  const indent = indentOf(lines[head] ?? "");
  let end = head + 1;
  while (end < lines.length) {
    const line = lines[end] ?? "";
    if (line.trim() === "" || line.trimStart().startsWith("#")) {
      end += 1;
      continue;
    }
    if (indentOf(line) <= indent) break;
    end += 1;
  }
  // A trailing run of blank or comment lines belongs to whatever comes next,
  // not to this block: appending after them would move a comment's subject.
  while (end > head + 1) {
    const line = lines[end - 1] ?? "";
    if (line.trim() === "" || line.trimStart().startsWith("#")) end -= 1;
    else break;
  }
  return { start: head + 1, end, indent: indent + 2 };
};

/** The index of the line opening `key` at indent 0, or -1. */
const headOf = (lines: ReadonlyArray<string>, key: string): number =>
  lines.findIndex((line) => line === `${key}:` || line.startsWith(`${key}: `) || line.startsWith(`${key}:#`));

/** Set `key` inside `[start, end)`, or insert it at `end`. Returns the new end. */
const setInBlock = (
  lines: Array<string>,
  start: number,
  end: number,
  indent: number,
  key: string,
  value: string | number | boolean | null
): number => {
  const prefix = `${" ".repeat(indent)}${key}:`;
  for (let i = start; i < end; i++) {
    const line = lines[i] ?? "";
    if (!line.startsWith(prefix)) continue;
    const rest = line.slice(prefix.length);
    if (rest !== "" && !rest.startsWith(" ") && !rest.startsWith("\t") && !rest.startsWith("#")) continue;
    lines[i] = `${prefix} ${renderValue(value)}${trailingComment(line)}`;
    return end;
  }
  lines.splice(end, 0, `${" ".repeat(indent)}${key}: ${renderValue(value)}`);
  return end + 1;
};

/**
 * Put the operator's cells on one card's front matter.
 *
 * @param text - The card, whole.
 * @param cells - The cells to set, keyed as `PROJECTION_CELLS` keys them
 *   (`actuals.tokens`, `result.grade`, `outcome_for_calibration`, …).
 * @returns The card with those cells set and nothing else touched.
 */
export const applyCells = (
  text: string,
  cells: ReadonlyMap<string, string | number | boolean | null>
): string => {
  const split = Frontmatter.split(text);
  if (split === null) throw new Error("the card opens with no front-matter fence");
  const lines = split.frontmatter.split("\n");

  const group = (name: string, after: number): number => {
    let head = headOf(lines, name);
    if (head === -1) {
      lines.splice(after, 0, `${name}:`);
      head = after;
    }
    let range = blockRange(lines, head);
    for (const [cell, value] of cells) {
      if (!cell.startsWith(`${name}.`)) continue;
      range = {
        ...range,
        end: setInBlock(lines, range.start, range.end, range.indent, cell.slice(name.length + 1), value)
      };
    }
    return range.end;
  };

  const afterActuals = group("actuals", lines.length);
  group("result", afterActuals);

  for (const [cell, value] of cells) {
    if (cell.includes(".")) continue;
    setInBlock(lines, 0, lines.length, 0, cell, value);
  }

  return `---\n${lines.join("\n")}\n---\n${split.body}`;
};

/** The front-matter lines whose key is one this projection never writes. */
export const fencedLines = (text: string): ReadonlyArray<string> => {
  const split = Frontmatter.split(text);
  if (split === null) return [];
  return split.frontmatter
    .split("\n")
    .filter((line) => NEVER_WRITTEN.some((key) => line.startsWith(`${key}:`)));
};

/**
 * `git diff --stat`'s shape for one file.
 *
 * Computed here because git is not on the wrapped PATH: `scripts/node-env.sh`
 * puts node on it and nothing else, and the evaluator runs the oracle on a bare
 * PATH where the only executables are `/usr/bin/env` and `/bin/sh` (U-A2,
 * MEASURED). The oracle's parenthetical asks for the reading, not for the
 * program that usually prints it.
 */
export const statOf = (
  name: string,
  before: string,
  after: string
): { readonly name: string; readonly added: number; readonly removed: number } => {
  const a = before.split("\n");
  const b = after.split("\n");
  // Longest common subsequence, so an inserted block counts as an insertion and
  // not as a rewrite of every line below it. A card is ~120 lines; the quadratic
  // table is the honest reading and costs nothing at that size.
  const table: Array<Array<number>> = Array.from({ length: a.length + 1 }, () =>
    new Array<number>(b.length + 1).fill(0)
  );
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      table[i]![j] = a[i] === b[j]
        ? (table[i + 1]![j + 1] ?? 0) + 1
        : Math.max(table[i + 1]![j] ?? 0, table[i]![j + 1] ?? 0);
    }
  }
  const common = table[0]![0] ?? 0;
  return { name, added: b.length - common, removed: a.length - common };
};
