/**
 * U-A24 LAKE-SELECTOR-READ — the unit's DOMINANT oracle.
 *
 * *"fixture tsv → `estimate.yieldRate` equals the band mean, `shrinkageWeight` =
 * n/(n+4), the release carries `prior_source: band` and `thompson{seed, alpha,
 * beta}`"*.
 *
 * The fixtures are not written by hand. `packages/planning/test-selector/fixtures/`
 * holds a `bands.tsv` and two `selection-<pass>.tsv` files produced by
 * `/home/tom/research-methods/bin/register` itself, on a scratch copy of the
 * register, at the argvs recorded in `docs/selector-read.md`. A hand-written
 * fixture would only prove that this reader agrees with whoever wrote the
 * fixture; these prove it agrees with U-E6.
 *
 * This suite sits in `test-selector/` and not in `test/` for the reason
 * `test-policy/` exists: `test/` is U-A7's port, nine files copied byte-identical
 * from the sketch and named one by one in `docs/port-manifest.tsv`, and the
 * package's `tsconfig.json` compiles `src/**` and `test/**` with `types: []` —
 * no Node types, because the engine imports no Node API. This file reads two
 * fixture documents off the disk, so it belongs beside the port and not inside
 * it.
 *
 * `SELECTOR_FIXTURE_DIR` moves the fixture root. `tools/check-selector-read.sh`
 * uses it to run this same suite against a mutated copy under `mktemp -d`,
 * which is how the card's `mutation_hint` — *"mutate a row's n → the shrinkage
 * assertion RED"* — is applied without editing the tree.
 */
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { Option, Schema } from "effect";
import { evaluateRelease } from "../src/release/evaluator.ts";
import {
  applySelectorEstimates,
  readSelector,
  type SelectorReading
} from "../src/release/selectorRead.ts";
import {
  bandFor,
  readBandsDocument,
  SelectionDocumentError,
  shrinkageFromObservations
} from "../src/schema/selectionDocument.ts";
import { Admit } from "../src/schema/admit.ts";
import { SELECTOR_PSEUDO_COUNT } from "../src/schema/selection.ts";
import { estimates, item, reading, releaseState, taskId } from "../test/fixtures.ts";

const FIXTURES =
  process.env["SELECTOR_FIXTURE_DIR"] ?? new URL("./fixtures/", import.meta.url).pathname;

const read = (name: string): { readonly text: string; readonly path: string } => {
  const path = `${FIXTURES.replace(/\/$/, "")}/${name}`;
  return { text: readFileSync(path, "utf8"), path };
};

const bandsSource = read("bands.tsv");
const mainEffect = estimates.mainEffect;

const selector = (pass: 1 | 2): SelectorReading =>
  readSelector(read(`selection-${pass}.tsv`), bandsSource, mainEffect);

const rowOf = (loaded: SelectorReading, rung: string) => {
  const row = loaded.table.rows.find((candidate) => candidate.rung === rung);
  if (row === undefined) throw new Error(`fixture has no row ${rung}`);
  return row;
};

const decodeAdmit = Schema.decodeUnknownSync(Admit);

describe("U-A24 the selector's tables, decoded", () => {
  it("decodes every band of the register's own bands.tsv", () => {
    const bands = readBandsDocument(bandsSource.text, bandsSource.path);
    expect(bands.length).toBe(24);

    const cell = bandFor(bands, "typescript-on-workers", "claude/claude-opus-5");
    expect(cell).toBeDefined();
    expect(cell?.n).toBe(7);
    expect(cell?.m).toBe(7);
    expect(cell?.alpha).toBe(9);
    expect(cell?.beta).toBe(2);
    // The mean is the file's, printed to six decimals, and is not re-derived:
    // 9/11 is 0.8181818..., and the number the register and the lake agree on is
    // the one the register wrote down.
    expect(cell?.mean).toBe(0.818182);
  });

  it("reads the pass and the arm off the document's own header", () => {
    const loaded = selector(2);
    expect(loaded.table.pass).toBe(2);
    expect(loaded.table.arm).toBe("claude/claude-opus-5");
    expect(loaded.table.rows.length).toBe(39);
  });

  // --- the oracle, clause 1 ------------------------------------------------
  it("estimate.yieldRate equals the band mean, for every band-sourced row", () => {
    const loaded = selector(2);
    const bands = loaded.bands;
    let checked = 0;

    for (const row of loaded.table.rows) {
      if (!row.admitted || row.priorSource !== "band") continue;
      const cell = bandFor(bands, Option.getOrThrow(row.useCaseClass), row.arm);
      const estimate = loaded.estimates.get(taskId(row.rung));
      expect(cell).toBeDefined();
      expect(estimate).toBeDefined();
      expect(estimate?.yieldRate).toBe(cell?.mean);
      checked += 1;
    }

    // A loop that checked nothing would pass. This is the fixture's measured
    // count of admitted band-sourced rows.
    expect(checked).toBe(21);
    expect(loaded.estimates.get(taskId("U-A5"))?.yieldRate).toBe(0.818182);
    expect(loaded.estimates.get(taskId("U-B1"))?.yieldRate).toBe(0.714286);
  });

  it("a row with no band carries the standing Beta(2,2) and says so", () => {
    const loaded = selector(2);
    const row = rowOf(loaded, "U-A7");
    expect(row.priorSource).toBe("prior");
    expect(row.alpha).toBe(2);
    expect(row.beta).toBe(2);
    expect(loaded.estimates.get(taskId("U-A7"))?.yieldRate).toBe(0.5);
    expect(loaded.priors.get(taskId("U-A7"))?.prior_source).toBe("prior");
  });

  // --- the oracle, clause 2 ------------------------------------------------
  it("shrinkageWeight is n/(n+4) on every decoded row, derived and not read", () => {
    const loaded = selector(2);
    expect(SELECTOR_PSEUDO_COUNT).toBe(4);

    for (const row of loaded.table.rows) {
      expect(row.shrinkageWeight).toBe(row.n / (row.n + 4));
      if (!row.admitted) continue;
      expect(loaded.estimates.get(taskId(row.rung))?.shrinkageWeight).toBe(
        shrinkageFromObservations(row.n)
      );
      expect(loaded.estimates.get(taskId(row.rung))?.observations).toBe(row.n);
    }

    // The four measured cells of this fixture, written out. `7/11` and not
    // `0.636364`: the weight is the quotient, and the file's six decimals are a
    // rounding of it that the reader checks and then discards.
    expect(loaded.estimates.get(taskId("U-A5"))?.shrinkageWeight).toBe(7 / 11);
    expect(loaded.estimates.get(taskId("U-B1"))?.shrinkageWeight).toBe(3 / 7);
    expect(loaded.estimates.get(taskId("U-C5"))?.shrinkageWeight).toBe(4 / 8);
    expect(loaded.estimates.get(taskId("U-A7"))?.shrinkageWeight).toBe(0);
  });

  it("carries the class's measured p80 consumption, and falls back where none was measured", () => {
    const loaded = selector(2);
    expect(loaded.estimates.get(taskId("U-A5"))?.p80Consumption).toBe(86444.6);
    expect(loaded.estimates.get(taskId("U-B1"))?.p80Consumption).toBe(106542.2);
    // U-A7 has no class, so no class cost distribution and no p80. The main
    // effects stand in; a zero would say "this lane is free".
    expect(loaded.estimates.get(taskId("U-A7"))?.p80Consumption).toBe(
      mainEffect.p80Consumption
    );
  });

  it("keeps the service-time quantiles the selector does not measure", () => {
    const estimate = selector(2).estimates.get(taskId("U-A5"));
    expect(estimate?.medianSeconds).toBe(mainEffect.medianSeconds);
    expect(estimate?.p80Seconds).toBe(mainEffect.p80Seconds);
    expect(estimate?.p99Seconds).toBe(mainEffect.p99Seconds);
  });

  it("holds back the rows contamination held back", () => {
    const loaded = selector(2);
    // The fifteen rawa-app rungs are in the table by name and out of the join.
    expect(loaded.table.rows.filter((row) => !row.admitted).length).toBe(15);
    expect(loaded.estimates.has(taskId("RW-00"))).toBe(false);
    expect(loaded.priors.has(taskId("RW-00"))).toBe(false);
  });
});

describe("U-A24 the Thompson draw, stamped on the release", () => {
  // --- the oracle, clause 3 ------------------------------------------------
  it("the release carries prior_source: band and thompson{seed, alpha, beta}", () => {
    const loaded = selector(2);
    const backlog = applySelectorEstimates(
      [item({ taskId: "U-A5" }), item({ taskId: "U-A7", rank: 1 })],
      loaded
    );
    const decision = evaluateRelease(
      releaseState(backlog, { priors: loaded.priors }),
      reading({})
    );

    const admit = decision.admits.find((candidate) => candidate.taskId === "U-A5");
    expect(admit).toBeDefined();
    expect(admit?.prior).toEqual({
      prior_source: "band",
      thompson: { seed: "2444832024327446672", alpha: 9, beta: 2 }
    });

    // The stamp is the row's, not a reconstruction: the band it names carries
    // the same posterior the draw was taken from.
    const cell = bandFor(loaded.bands, "typescript-on-workers", "claude/claude-opus-5");
    expect(admit?.prior?.thompson?.alpha).toBe(cell?.alpha);
    expect(admit?.prior?.thompson?.beta).toBe(cell?.beta);

    // And the estimate that was released with it is the band's.
    expect(
      decision.admits.length > 0 &&
        backlog.find((candidate) => candidate.taskId === "U-A5")?.estimate.yieldRate
    ).toBe(0.818182);
  });

  it("a prior-sourced item is stamped `prior` and still records its draw", () => {
    const loaded = selector(2);
    const backlog = applySelectorEstimates([item({ taskId: "U-A7" })], loaded);
    const decision = evaluateRelease(
      releaseState(backlog, { priors: loaded.priors }),
      reading({})
    );

    expect(decision.admits[0]?.prior).toEqual({
      prior_source: "prior",
      thompson: { seed: "3062309841186505877", alpha: 2, beta: 2 }
    });
  });

  it("the seed survives as digits; read as a number it would round", () => {
    const loaded = selector(2);
    const seed = Option.getOrThrow(rowOf(loaded, "U-A2").thompson).seed;
    expect(seed).toBe("17696085320377123006");
    // The measured reason the field is a string: this seed is past
    // Number.MAX_SAFE_INTEGER and a number would not round-trip.
    expect(Number.isSafeInteger(Number(seed))).toBe(false);
    expect(String(Number(seed))).not.toBe(seed);
  });

  it("a pass that drew nothing stamps no thompson block", () => {
    const loaded = selector(1);
    expect(loaded.table.pass).toBe(1);
    const stamp = loaded.priors.get(taskId("U-A5"));
    // Pass 1 orders by measured cost. The band is still the source of the
    // yield rate; the draw is absent because no draw was taken.
    expect(stamp).toEqual({ prior_source: "band" });
    expect(stamp && "thompson" in stamp).toBe(false);
    expect(loaded.estimates.get(taskId("U-A5"))?.yieldRate).toBe(0.818182);
  });

  it("an item with no selection behind it carries no prior key at all", () => {
    const decision = evaluateRelease(releaseState([item({ taskId: "t1" })]), reading({}));
    expect(decision.admits.length).toBe(1);
    expect(Object.keys(decision.admits[0] ?? {})).not.toContain("prior");
  });

  it("the stamped admit decodes through the wire type", () => {
    const loaded = selector(2);
    const backlog = applySelectorEstimates([item({ taskId: "U-A5" })], loaded);
    const decision = evaluateRelease(
      releaseState(backlog, { priors: loaded.priors }),
      reading({})
    );
    // Round-trips as JSON: the stamp crosses the uplink to a receipt, so a
    // value the schema would reject must fail here and not there.
    const wire = JSON.parse(JSON.stringify(decision.admits[0]));
    expect(decodeAdmit(wire).prior?.prior_source).toBe("band");
  });
});

describe("U-A24 the non-goal: no selection logic in the lake", () => {
  it("applying the selector's estimates changes no order and no membership", () => {
    const loaded = selector(2);
    // In the selection's own ranking U-A5 is first and U-B1 is fifth. The
    // backlog is handed over in the opposite order and comes back in it.
    const before = [item({ taskId: "U-B1" }), item({ taskId: "U-A5" })];
    const after = applySelectorEstimates(before, loaded);

    expect(after.map((entry) => entry.taskId)).toEqual(["U-B1", "U-A5"]);
    expect(after.length).toBe(before.length);
    expect(after[0]?.estimate.yieldRate).toBe(0.714286);
  });

  it("an item the selection does not name keeps the estimate it had", () => {
    const loaded = selector(2);
    const before = item({ taskId: "t1", yieldRate: 0.25 });
    const after = applySelectorEstimates([before], loaded)[0];
    expect(after).toBe(before);
  });

  it("no rule reads the rank or the realised draw", () => {
    const loaded = selector(2);
    // Both are decoded and available — and the admit type has no field for
    // either, which is where a selector would have leaked into the lake.
    expect(Option.getOrThrow(rowOf(loaded, "U-A5").rank)).toBe(1);
    expect(Option.isSome(rowOf(loaded, "U-A5").thompsonDraw)).toBe(true);
    const decision = evaluateRelease(
      releaseState(applySelectorEstimates([item({ taskId: "U-A5" })], loaded), {
        priors: loaded.priors
      }),
      reading({})
    );
    const keys = Object.keys(decision.admits[0]?.prior ?? {});
    expect(keys).toEqual(["prior_source", "thompson"]);
    expect(Object.keys(decision.admits[0] ?? {})).not.toContain("rank");
  });
});

describe("U-A24 the reader refuses rather than guesses", () => {
  const mutate = (name: string, edit: (text: string) => string) => ({
    text: edit(read(name).text),
    path: `${name} (mutated in memory)`
  });

  const load = (
    selection: { readonly text: string; readonly path: string },
    bands = bandsSource
  ): SelectorReading => readSelector(selection, bands, mainEffect);

  it("refuses a selection row whose n does not give its shrinkage weight", () => {
    // The card's mutation_hint, applied to the fixture's first row.
    const mutated = mutate("selection-2.tsv", (text) =>
      text.replace(
        "0.818182\t86444.6\t0.636364\t7\t7\t9\t2\tband\t2444832024327446672",
        "0.818182\t86444.6\t0.636364\t3\t7\t9\t2\tband\t2444832024327446672"
      )
    );
    expect(mutated.text).not.toBe(read("selection-2.tsv").text);
    expect(() => load(mutated)).toThrow(SelectionDocumentError);
    expect(() => load(mutated)).toThrow(/U-A5 states shrinkage_weight 0.636364/);
  });

  it("refuses a band whose n does not give its shrinkage weight", () => {
    const mutatedBands = mutate("bands.tsv", (text) =>
      text.replace(
        "typescript-on-workers\tclaude/claude-opus-5\t7\t7",
        "typescript-on-workers\tclaude/claude-opus-5\t3\t7"
      )
    );
    expect(() => load(read("selection-2.tsv"), mutatedBands)).toThrow(
      /shrinkage_weight 0.636364/
    );
  });

  it("refuses a band table carrying a score", () => {
    const scored = mutate("bands.tsv", (text) =>
      text
        .split("\n")
        .map((line) =>
          line.trim() === "" || line.startsWith("#")
            ? line
            : line.startsWith("class\t")
              ? `${line}\tscore`
              : `${line}\t1`
        )
        .join("\n")
    );
    expect(() => readBandsDocument(scored.text, scored.path)).toThrow(
      /never carry a score/
    );
  });

  it("refuses a band-sourced row whose cell is absent from the band table", () => {
    const withoutCell = mutate("bands.tsv", (text) =>
      text
        .split("\n")
        .filter((line) => !line.startsWith("typescript-on-workers\tclaude/claude-opus-5"))
        .join("\n")
    );
    expect(() => load(read("selection-2.tsv"), withoutCell)).toThrow(
      /absent from the band table/
    );
  });

  it("refuses a row whose width is not the header's", () => {
    const short = mutate("selection-2.tsv", (text) =>
      text.replace("\t2444832024327446672\t0.965976", "\t0.965976")
    );
    expect(() => load(short)).toThrow(/cells, want 24/);
  });

  it("refuses an admitted pass-2 row with no draw recorded", () => {
    const undrawn = mutate("selection-2.tsv", (text) =>
      text.replace("band\t2444832024327446672\t0.965976", "band\t-\t-")
    );
    expect(() => load(undrawn)).toThrow(/no Thompson draw recorded/);
  });

  it("refuses a yield rate that is not the band's mean", () => {
    const drifted = mutate("selection-2.tsv", (text) =>
      text.replace("\t0.818182\t86444.6\t0.636364\t7", "\t0.900000\t86444.6\t0.636364\t7")
    );
    expect(() => load(drifted)).toThrow(/the band's mean is 0.818182/);
  });

  it("names the document in every refusal", () => {
    const empty = { text: "# only comments\n", path: "nowhere/bands.tsv" };
    try {
      readBandsDocument(empty.text, empty.path);
      throw new Error("expected a refusal");
    } catch (error) {
      expect(error).toBeInstanceOf(SelectionDocumentError);
      expect((error as SelectionDocumentError).path).toBe("nowhere/bands.tsv");
    }
  });
});
