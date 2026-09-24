/**
 * The levels document, read.
 *
 * The reader is what makes `docs/levels.md` load-bearing rather than decoration,
 * so what is asserted here is the grammar and every refusal in it: the whole
 * value of a parsed document is that a mistake in it is named rather than
 * silently defaulted (H-16). The SHIPPED document is asserted where it is
 * actually used — `tools/batch-replay.mjs` clause B1 reads `docs/levels.md`
 * itself and requires D-B10's numbers off it — because this package carries no
 * platform types and must not learn to read a file to be tested.
 */
import { describe, expect, it } from "vitest";
import {
  documentFillers,
  LevelsDocumentError,
  parseLevelsDocument
} from "../src/schema/levelsDocument.ts";
import { orderedLevels } from "../src/schema/levels.ts";
import { digest } from "./fixtures.ts";

const MINIMAL = [
  "| level | ordinal | families | wip_cap |",
  "|---|---|---|---|",
  "| `approved` | 0 | `build` | 2 |",
  "| `filler` | 1 | `e1-replay`, `academic-drain` | 1 |",
  "",
  "| lane | value |",
  "|---|---|",
  "| level | `filler` |",
  "| row | `gpu-coordinator` |",
  "| promote_after | 10 |",
  "| promote_to | `approved` |",
  "| abort_on.consecutive_crash | 2 |"
].join("\n");

const parse = (text: string) => parseLevelsDocument(text, "fixture.md", digest("b"));

describe("the hierarchy it yields", () => {
  it("orders the filler level last, so nothing is beneath it", () => {
    expect(orderedLevels(parse(MINIMAL).levels).at(-1)?.name).toBe("filler");
  });

  it("carries D-B10's numbers through unchanged", () => {
    const lane = parse(MINIMAL).filler;
    expect(lane?.level).toBe("filler");
    expect(lane?.row).toBe("gpu-coordinator");
    expect(lane?.promoteAfter).toBe(10);
    expect(lane?.promoteTo).toBe("approved");
    expect(lane?.abortOnConsecutiveCrash).toBe(2);
  });

  it("declares the two fillers, in the order they alternate", () => {
    expect(documentFillers(parse(MINIMAL))).toEqual(["e1-replay", "academic-drain"]);
  });

  it("names no filler when the document declares no lane", () => {
    const noLane = MINIMAL.split("\n").slice(0, 4).join("\n");
    expect(documentFillers(parse(noLane))).toEqual([]);
  });
});

describe("the reader", () => {
  it("reads a document that carries only the two tables", () => {
    const document = parse(MINIMAL);
    expect(document.levels.levels).toHaveLength(2);
    expect(document.filler?.promoteAfter).toBe(10);
  });

  it("reads the tables by shape, wherever they sit in the prose", () => {
    const shuffled = ["# heading", "", "some prose", "", MINIMAL, "", "more prose"].join("\n");
    expect(parse(shuffled).filler?.row).toBe("gpu-coordinator");
  });

  it("declares no lane when the document declares none", () => {
    const noLane = MINIMAL.split("\n").slice(0, 4).join("\n");
    expect(parse(noLane).filler).toBeNull();
  });

  it("refuses a document with no level table, and names it", () => {
    expect(() => parse("# nothing here\n")).toThrow(LevelsDocumentError);
    expect(() => parse("# nothing here\n")).toThrow(/fixture\.md/);
  });

  it("refuses a level declared twice", () => {
    const twice = MINIMAL.replace("| `filler` | 1 |", "| `approved` | 1 |");
    expect(() => parse(twice)).toThrow(/declared twice/);
  });

  it("refuses a level with no whole-number ordinal", () => {
    const vague = MINIMAL.replace("| `filler` | 1 |", "| `filler` | last |");
    expect(() => parse(vague)).toThrow(/ordinal/);
  });

  it("refuses a level that declares no goal family", () => {
    const empty = MINIMAL.replace("| `build` | 2 |", "|  | 2 |");
    expect(() => parse(empty)).toThrow(/goal family/);
  });

  it("refuses a lane naming a level the table does not declare", () => {
    const stray = MINIMAL.replace("| level | `filler` |", "| level | `scavenger` |");
    expect(() => parse(stray)).toThrow(/does not declare/);
  });

  it("refuses a lane with no promotion number", () => {
    const none = MINIMAL.replace("| promote_after | 10 |", "| promote_after |  |");
    expect(() => parse(none)).toThrow(/missing promote_after/);
  });

  it("refuses a lane with no abort number, because D-B10 names one", () => {
    const none = MINIMAL.replace("| abort_on.consecutive_crash | 2 |", "");
    expect(() => parse(none)).toThrow(/abort_on\.consecutive_crash/);
  });
});
