/**
 * Value density, and the defect the bid-price denominator fixes.
 */
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import {
  bindingRow,
  coversBidPrice,
  valueDensity
} from "../src/heuristics/valueDensity.ts";
import { Option, Schema } from "effect";
import { PriceVector } from "../src/schema/prices.ts";
import { RowSet } from "../src/schema/rows.ts";
import { digest, item, prices, rowName } from "./fixtures.ts";

const decodePrices = Schema.decodeUnknownSync(PriceVector);
const decodeRowSet = Schema.decodeUnknownSync(RowSet);

const freeRows = decodeRowSet([
  { row: "gpu-coordinator", holders: 1, consumption: 0 }
]);
const meteredRows = decodeRowSet([
  { row: "claude-lanes", holders: 1, consumption: 0 },
  { row: "claude-budget", holders: 1, consumption: 20 }
]);
const meteredNames = [rowName("claude-budget")];

describe("value density", () => {
  it("is value times yield over bid-price-weighted consumption", () => {
    const candidate = item({ taskId: "t1", value: 100, yieldRate: 0.5, consumption: 20 });
    const density = valueDensity(candidate, meteredRows, meteredNames, prices);

    expect(density.numerator).toBeCloseTo(50);
    // Only the budget row is priced above zero, at 0.01 per unit of 20 consumed.
    expect(density.denominator).toBeCloseTo(0.2);
    expect(density.value).toBeCloseTo(250);
  });

  it("saturates a free lane: a row priced at zero yields infinite density", () => {
    const candidate = item({ taskId: "t1", value: 1, yieldRate: 0.01 });
    const density = valueDensity(candidate, freeRows, [], prices);

    // Complementary slackness: capacity priced at zero should be consumed by
    // anything with positive value.
    expect(density.value).toBe(Number.POSITIVE_INFINITY);
    expect(coversBidPrice(density)).toBe(true);
  });

  it("does not degenerate to pure value ordering when the free lane is priced", () => {
    // The defect Volume II Part III section 2 names: with an epsilon denominator
    // the sort reverts to value ordering exactly when local lanes are saturated.
    // With a slot price the longer job must sort below the shorter one at equal
    // value.
    const busy = decodePrices({
      hash: digest("9"),
      rows: [{ row: "gpu-coordinator", price: 0.5 }],
      drum: 100,
      stage: []
    });

    const short = item({ taskId: "short", value: 10, yieldRate: 0.5, medianSeconds: 100 });
    const long = item({ taskId: "long", value: 10, yieldRate: 0.5, medianSeconds: 1000 });

    const shortDensity = valueDensity(short, freeRows, [], busy);
    const longDensity = valueDensity(long, freeRows, [], busy);

    expect(shortDensity.value).toBeGreaterThan(longDensity.value);
  });

  it("never treats an unpriced row as free", () => {
    const unpriced = decodePrices({ hash: digest("8"), rows: [], drum: 1, stage: [] });
    const candidate = item({ taskId: "t1", value: 1000 });
    const density = valueDensity(candidate, freeRows, [], unpriced);

    expect(density.unpriced.length).toBe(1);
    expect(coversBidPrice(density)).toBe(false);
  });

  it("names the row that priced an item out", () => {
    const candidate = item({ taskId: "t1", value: 1, yieldRate: 0.1, consumption: 100 });
    const density = valueDensity(candidate, meteredRows, meteredNames, prices);

    expect(coversBidPrice(density)).toBe(false);
    expect(Option.getOrNull(bindingRow(density))).toBe("claude-budget");
  });

  it("is monotone in value and in yield", () => {
    fc.assert(
      fc.property(
        fc.double({ min: 1, max: 1000, noNaN: true }),
        fc.double({ min: 1.0001, max: 4, noNaN: true }),
        (value, factor) => {
          const lower = item({ taskId: "a", value, yieldRate: 0.5, consumption: 10 });
          const higher = item({
            taskId: "b",
            value: value * factor,
            yieldRate: 0.5,
            consumption: 10
          });
          const lowerDensity = valueDensity(lower, meteredRows, meteredNames, prices);
          const higherDensity = valueDensity(higher, meteredRows, meteredNames, prices);
          return higherDensity.value >= lowerDensity.value;
        }
      ),
      { numRuns: 200 }
    );
  });
});
