/**
 * U-A13 LAKE-PROJECTION — the suite.
 *
 * The unit's DOMINANT oracle runs against the register on this disk, which is a
 * corpus that belongs to other lanes and moves while they bank into it. This
 * suite is the part that does not: hermetic fixtures, no path opened, one
 * assertion per sentence of §2.2e.
 *
 * What it asserts, in the order §2.2e says it:
 *
 *   the banked corpus is read as it is, not as a schema wishes it were
 *   the mirror is what the Factory object accepted, and nothing else
 *   the diff sees a dropped receipt — the unit's own mutation_hint
 *   the diff sees a card that contradicts the projection, and is silent about
 *     one that is merely unwritten
 *   `--write` fills the nine cells and never `status` or `outcome_ruled`
 *   re-applying the same projection changes nothing
 */
import { Effect, Option } from "effect";
import { describe, expect, it } from "vitest";
import {
  applyCells,
  bankedRowOf,
  cardCellsOf,
  diffProjections,
  fencedLines,
  loadBankedIntoFactory,
  makeFactory,
  NEVER_WRITTEN,
  planningStoreInMemoryLayer,
  priorGapOf,
  projectionRowOf,
  PROJECTION_CELLS,
  statOf,
  type BankedRow,
  type CardView,
  type ProjectionRow
} from "../src/index.ts";
import { armedPlan, item, reading, releaseState } from "../../planning/test/fixtures.ts";

/**
 * One banked receipt in the shape the corpus actually has.
 *
 * MEASURED 2026-09-06 over `receipts/FACTORY-2026-09-06/*​/receipt.json`: every
 * one of the 52 files carries `unit`, `disposition`, `verdict`, `oracle_rc`,
 * `seconds` and a six-cell `tokens`; 27 also carry `outcome_for_calibration`,
 * `prior_gap` and `mutation_rc`; 0 of 52 decode under the strict §2.3 `Receipt`.
 */
const receipt = (overrides: Record<string, unknown> = {}) => ({
  id: "U-X1-2026-09-06-r0",
  unit: "U-X1",
  kind: "build",
  disposition: "KEEP",
  verdict: "PASS",
  seconds: 1200,
  oracle_rc: 0,
  oracle_output_sha256: "a".repeat(64),
  mutation_rc: 1,
  outcome_for_calibration: "pass",
  prior_gap: { tokens_out: 4200, p_pass_vs_outcome: "0.7 vs 1" },
  tokens: {
    in_uncached: 1,
    cache_read: 2,
    cache_write: 0,
    out: 3,
    reasoning: 4,
    total: 10
  },
  ...overrides
});

const rowOf = (unit: string, overrides: Record<string, unknown> = {}): BankedRow => {
  const read = bankedRowOf(
    unit,
    `receipts/FACTORY-2026-09-06/${unit}/receipt.json`,
    unit.padEnd(64, "0"),
    receipt({ unit, ...overrides })
  );
  if (!read.ok) throw new Error(`the fixture receipt did not read: ${read.why}`);
  return read.row;
};

const chainLink = (index: number) => ({
  seq: index + 1,
  hash: String(index + 1).padStart(64, "0"),
  prevHash: String(index).padStart(64, "0")
});

const load = async (rows: ReadonlyArray<BankedRow>) => {
  const items = rows.map((row, index) => item({ taskId: row.unit, rank: index }));
  const factory = await Effect.runPromise(
    makeFactory(
      releaseState(items, { plans: [{ ...armedPlan, attemptCap: Option.some(1) }] })
    ).pipe(Effect.provide(planningStoreInMemoryLayer))
  );
  return Effect.runPromise(
    loadBankedIntoFactory(factory, rows, chainLink, (pass) => reading({ seq: pass + 1 }))
  );
};

const registerSide = (rows: ReadonlyArray<BankedRow>): ReadonlyArray<ProjectionRow> =>
  rows
    .map((row) =>
      projectionRowOf(row, {
        id: row.unit,
        oracle_rc: row.oracle_rc,
        oracle_output_sha256: row.oracle_output_sha256,
        verdict_hash: ""
      })
    )
    .sort((a, b) => a.unit.localeCompare(b.unit));

const card = (id: string, overrides: Partial<CardView> = {}): CardView => ({
  id,
  repo: "mecattaf/substrate",
  cells: new Map(),
  ...overrides
});

const CARD_TEXT = [
  "---",
  'id: "U-X1"',
  "status: DRAFT          # DRAFT -> ARMED -> RUNNING -> KEEP | DISCARD",
  'repo: "mecattaf/substrate"',
  "prior:",
  "  p_pass: 0.55",
  "  predicted_tokens_cell: out   # DECISIONS.md D-B19",
  'grade: "CLAIMED"',
  "actuals:                       # written after the run",
  "  tokens: null",
  "  seconds: null",
  "  outcome: null",
  "  receipt_sha256: null",
  "  prior_gap: null",
  "---",
  "",
  "# U-X1 — the body, which the writer never touches",
  ""
].join("\n");

describe("reading the banked corpus", () => {
  it("takes the cells the receipt carries and names the ones it does not", () => {
    const read = bankedRowOf("U-X1", "p", "s", receipt({ mutation_rc: undefined }));
    expect(read.ok).toBe(true);
    if (!read.ok) return;
    expect(read.row.absent).toContain("mutation_rc");
    expect(read.row.mutation_rc).toBeNull();
    expect(read.row.tokens).toBe(10);
    expect(read.row.outcome).toBe("pass");
  });

  it("refuses a receipt missing a cell it cannot do without, by name", () => {
    const read = bankedRowOf("U-X1", "p", "s", receipt({ seconds: undefined, tokens: {} }));
    expect(read.ok).toBe(false);
    if (read.ok) return;
    expect(read.why).toContain("seconds");
    expect(read.why).toContain("tokens.total");
  });

  it("carries `none` rather than a null where §2.3 has no digest (D-B22)", () => {
    const row = rowOf("U-X1", { oracle_output_sha256: undefined });
    expect(row.oracle_output_sha256).toBe("none");
  });

  it("reads both spellings of prior_gap as the one declared cell", () => {
    expect(priorGapOf({ tokens_out: 7, p_pass_vs_outcome: "0.5 vs 1" })).toBe(7);
    expect(priorGapOf({ tokens_by_cell: { out: -9, "in_uncached+out": 1, total: 2 } })).toBe(-9);
    expect(priorGapOf(undefined)).toBeNull();
  });

  it("reads a FAIL verdict as the mirror's `fail`, not as an absence", () => {
    expect(rowOf("U-X1", { verdict: "FAIL" }).outcome).toBe("fail");
  });
});

describe("loading the corpus into the Factory object", () => {
  it("walks every receipt through the state machine and mirrors it back", async () => {
    const rows = [rowOf("U-X1"), rowOf("U-X2"), rowOf("U-X3")];
    const result = await load(rows);
    expect(result.refused).toEqual([]);
    expect(result.unreleased).toEqual([]);
    expect(result.rows.map((row) => row.unit)).toEqual(["U-X1", "U-X2", "U-X3"]);
    expect(result.rows[0]?.result.observed).toBe(0);
    expect(result.rows[0]?.result.grade).toBe("MEASURED");
  });

  it("agrees with the same rows read straight off the register", async () => {
    const rows = [rowOf("U-X1"), rowOf("U-X2")];
    const result = await load(rows);
    expect(diffProjections(result.rows, registerSide(rows), [])).toEqual([]);
  });

  it("names the unit when one banked receipt is dropped from the load", async () => {
    // The unit's mutation_hint: "drop one banked receipt → --diff non-empty".
    const rows = [rowOf("U-X1"), rowOf("U-X2"), rowOf("U-X3")];
    const result = await load(rows.filter((row) => row.unit !== "U-X2"));
    const lines = diffProjections(result.rows, registerSide(rows), []);
    expect(lines).toEqual(["missing U-X2 receipts/FACTORY-2026-09-06/U-X2/receipt.json"]);
  });

  it("names a mirrored row the register does not bank", async () => {
    const rows = [rowOf("U-X1"), rowOf("U-X2")];
    const result = await load(rows);
    const lines = diffProjections(result.rows, registerSide([rows[0]!]), []);
    expect(lines).toEqual(["extra U-X2"]);
  });

  it("projects no row for a receipt whose evidence the object refuses", async () => {
    // A verdict that skips the chain is a ContinuityGap; the object refuses it,
    // the receipt then has no verdict to match, and the mirror holds neither.
    const rows = [rowOf("U-X1"), rowOf("U-X2")];
    const items = rows.map((row, index) => item({ taskId: row.unit, rank: index }));
    const factory = await Effect.runPromise(
      makeFactory(
        releaseState(items, { plans: [{ ...armedPlan, attemptCap: Option.some(1) }] })
      ).pipe(Effect.provide(planningStoreInMemoryLayer))
    );
    const skipping = (index: number) => ({
      seq: (index + 1) * 7,
      hash: String(index + 1).padStart(64, "0"),
      prevHash: String(index).padStart(64, "0")
    });
    const result = await Effect.runPromise(
      loadBankedIntoFactory(factory, rows, skipping, (pass) => reading({ seq: pass + 1 }))
    );
    expect(result.rows).toEqual([]);
    expect(result.refused.map((entry) => entry.reason)).toContain("ContinuityGap");
  });
});

describe("the diff against the cards", () => {
  it("is silent about a cell the card has not written yet", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const unwritten = card("U-X1", {
      cells: new Map(PROJECTION_CELLS.map((cell) => [cell, null]))
    });
    expect(diffProjections(result.rows, registerSide(rows), [unwritten])).toEqual([]);
  });

  it("names a card that carries a different value in a cell it would fill", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const stale = card("U-X1", { cells: new Map([["actuals.tokens", 999]]) });
    expect(diffProjections(result.rows, registerSide(rows), [stale])).toEqual([
      "contradiction U-X1 actuals.tokens card=999 projection=10"
    ]);
  });

  it("names a card that carries no repo: (§2.2e's unmapped)", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const lines = diffProjections(result.rows, registerSide(rows), [
      card("U-X1"),
      card("U-X9", { repo: null })
    ]);
    expect(lines).toEqual(["unmapped U-X9"]);
  });
});

describe("writing the operator's fields", () => {
  const cellsFor = (row: ProjectionRow) => {
    const cells = new Map<string, string | number | boolean | null>();
    for (const [cell, value] of cardCellsOf(row)) if (value !== null) cells.set(cell, value);
    return cells;
  };

  it("fills exactly the cells §2.2e names and leaves the body alone", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const after = applyCells(CARD_TEXT, cellsFor(result.rows[0]!));
    expect(after).toContain("  tokens: 10");
    expect(after).toContain("  seconds: 1200");
    expect(after).toContain('  outcome: "KEEP"');
    expect(after).toContain("  prior_gap: 4200");
    expect(after).toContain('  grade: "MEASURED"');
    expect(after).toContain("  observed: 0");
    expect(after).toContain('outcome_for_calibration: "pass"');
    expect(after).toContain("# U-X1 — the body, which the writer never touches");
  });

  it("never moves a status: or outcome_ruled: line", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const after = applyCells(CARD_TEXT, cellsFor(result.rows[0]!));
    expect(fencedLines(after)).toEqual(fencedLines(CARD_TEXT));
    expect(after).toContain("status: DRAFT          # DRAFT -> ARMED -> RUNNING -> KEEP | DISCARD");
    for (const key of NEVER_WRITTEN) {
      expect([...cardCellsOf(result.rows[0]!).keys()]).not.toContain(key);
      expect(PROJECTION_CELLS).not.toContain(key);
    }
  });

  it("keeps a trailing comment, and its column, when a value beside it changes", () => {
    const after = applyCells(CARD_TEXT, new Map([["status", "KEEP"]]));
    expect(after).toContain('status: "KEEP"          # DRAFT -> ARMED -> RUNNING -> KEEP | DISCARD');
  });

  it("is idempotent: re-applying the same cells changes no byte", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const once = applyCells(CARD_TEXT, cellsFor(result.rows[0]!));
    const twice = applyCells(once, cellsFor(result.rows[0]!));
    expect(twice).toBe(once);
  });

  it("reads the change as an insertion and not as a rewrite of the file", async () => {
    const rows = [rowOf("U-X1")];
    const result = await load(rows);
    const after = applyCells(CARD_TEXT, cellsFor(result.rows[0]!));
    const stat = statOf("U-X1.md", CARD_TEXT, after);
    // five actuals lines replaced, plus `result:` with its three cells and
    // `outcome_for_calibration:` inserted.
    expect(stat.removed).toBe(5);
    expect(stat.added).toBe(10);
  });
});
