import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Effect } from "effect";
import { describe, expect, it } from "vitest";
import {
  makeFactoryHttpHandler,
  makeInMemoryPlanningStore,
  makeFactory,
  mirrorProjectionRows,
  NEVER_WRITTEN,
  PlanningStore,
  retainedReceiptOf,
  type IFactory,
  type IPlanningStore
} from "../src/index.ts";
import { checkLineDiscipline } from "@substrate/serializer";
import { releaseState, run, verdict } from "./fixtures.ts";

const RECEIPT = fileURLToPath(
  new URL("../../schema/test/fixtures/receipt-strict-full.json", import.meta.url)
);
const receipt = (): Record<string, unknown> => JSON.parse(readFileSync(RECEIPT, "utf8"));

/**
 * A hasher that answers for any bytes.
 *
 * The table hasher refuses bytes it has not been told about, which is right for
 * an ARMING — an unknown artifact has no authority. A receipt digest is not an
 * authority, it is a label on a row, so the fake here answers by length. It is
 * still not sha-256 and still does not pretend to be: the digest's value is
 * never asserted below, only its presence and its stability.
 */
const lengthHasher = {
  hash: (bytes: Uint8Array) =>
    Effect.succeed(String(bytes.length).padStart(64, "0") as never)
};

const openHandler = async (): Promise<{
  readonly factory: IFactory;
  readonly store: IPlanningStore;
  readonly handler: (request: Request) => Promise<Response>;
}> => {
  const store = await run(makeInMemoryPlanningStore);
  const factory = await run(
    makeFactory(releaseState([], { plans: [] })).pipe(
      Effect.provideService(PlanningStore, store)
    )
  );
  return {
    factory,
    store,
    handler: makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: lengthHasher,
      store
    })
  };
};

const request = (path: string, method: "GET" | "POST", body?: unknown) =>
  new Request(`https://factory.invalid${path}`, {
    method,
    headers: {
      authorization: "Bearer test-token",
      ...(body === undefined ? {} : { "content-type": "application/json" })
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });

/** Posts one mirrored verdict and the receipt whose evidence matches it. */
const ingest = async (
  handler: (request: Request) => Promise<Response>,
  line: Record<string, unknown>,
  sequence = 1
): Promise<string> => {
  const mirrored = verdict("receipt-evaluator", "pass", sequence, {
    unit_id: line["id"],
    oracle_rc: line["oracle_rc"],
    mutation_rc: (line["mutation"] as { readonly rc: number }).rc,
    oracle_output_sha256: line["oracle_output_sha256"]
  });
  expect((await handler(request("/verdicts", "POST", mirrored))).status).toBe(200);
  const posted = await handler(
    request("/receipts", "POST", {
      receipt: line,
      verdict_hash: mirrored.hash,
      receipt_path: `receipts/${String(line["id"])}/receipt.json`
    })
  );
  expect(posted.status).toBe(200);
  return mirrored.hash;
};

describe("the measured cells retained from an accepted receipt", () => {
  it("reads exactly the banked half of a projection row", () => {
    const read = retainedReceiptOf(receipt(), "receipts/U-A16/receipt.json", "a".repeat(64));
    expect(read.ok).toBe(true);
    if (!read.ok) return;
    expect(read.retained).toEqual({
      unit: "U-A16-FIXTURE-0",
      receipt_path: "receipts/U-A16/receipt.json",
      receipt_sha256: "a".repeat(64),
      disposition: "CRASH",
      seconds: 265,
      tokens: 34206,
      outcome_for_calibration: "fail",
      prior_gap: -134694
    });
  });

  it("names the cell it cannot do without rather than filling it with a zero", () => {
    const withoutSeconds = { ...receipt() };
    delete withoutSeconds["seconds"];
    const read = retainedReceiptOf(withoutSeconds, "none", "a".repeat(64));
    expect(read.ok).toBe(false);
    if (read.ok) return;
    expect(read.why).toContain("seconds");
  });

  it("carries an absent optional cell as null and never as a guess", () => {
    const without = { ...receipt() };
    delete without["outcome_for_calibration"];
    delete without["prior_gap"];
    const read = retainedReceiptOf(without, "none", "a".repeat(64));
    expect(read.ok).toBe(true);
    if (!read.ok) return;
    expect(read.retained.outcome_for_calibration).toBeNull();
    expect(read.retained.prior_gap).toBeNull();
  });
});

describe("the projection the object serves from its own mirror", () => {
  it("yields a row only where the retained cells and the mirror agree on a unit", () => {
    const cells = {
      unit: "U-1",
      receipt_path: "none",
      receipt_sha256: "a".repeat(64),
      disposition: "CRASH",
      seconds: 1,
      tokens: 2,
      outcome_for_calibration: null,
      prior_gap: null
    };
    const evidence = {
      id: "U-1",
      oracle_rc: 0,
      oracle_output_sha256: "sha256:x",
      verdict_hash: "h"
    };
    expect(mirrorProjectionRows([cells], [evidence])).toHaveLength(1);
    expect(mirrorProjectionRows([cells], [])).toHaveLength(0);
    expect(mirrorProjectionRows([], [evidence])).toHaveLength(0);
  });

  it("sorts by unit, so two objects holding the same receipts serve the same bytes", () => {
    const cellsFor = (unit: string) => ({
      unit,
      receipt_path: "none",
      receipt_sha256: "a".repeat(64),
      disposition: "CRASH",
      seconds: 1,
      tokens: 2,
      outcome_for_calibration: null,
      prior_gap: null
    });
    const evidenceFor = (id: string) => ({
      id,
      oracle_rc: 0,
      oracle_output_sha256: "sha256:x",
      verdict_hash: "h"
    });
    const rows = mirrorProjectionRows(
      [cellsFor("U-B"), cellsFor("U-A")],
      [evidenceFor("U-A"), evidenceFor("U-B")]
    );
    expect(rows.map((row) => row.unit)).toEqual(["U-A", "U-B"]);
  });

  it("serves an accepted receipt as one canonical line, twice identically", async () => {
    const { handler } = await openHandler();
    await ingest(handler, receipt());

    const first = await handler(request("/projection", "GET"));
    expect(first.status).toBe(200);
    const body = await first.text();
    expect(checkLineDiscipline(body)).toEqual([]);
    expect(body.split("\n").filter((line) => line !== "")).toHaveLength(1);
    expect(JSON.parse(body)).toMatchObject({
      unit: "U-A16-FIXTURE-0",
      actuals: { seconds: 265, tokens: 34206, outcome: "CRASH" },
      result: { grade: "MEASURED", observed: 0 }
    });

    const second = await handler(request("/projection", "GET"));
    expect(await second.text()).toBe(body);
  });

  it("never serves a cell the operator does not own", async () => {
    const { handler } = await openHandler();
    // The fixture receipt carries `outcome_ruled: DISCARD`. It is Tom's field,
    // and the projection has no name for it: §2.2e's `--write` fills only the
    // operator's cells, and `status` and `outcome_ruled` never.
    expect(receipt()["outcome_ruled"]).toBe("DISCARD");
    await ingest(handler, receipt());
    const body = await (await handler(request("/projection", "GET"))).text();
    for (const forbidden of NEVER_WRITTEN) {
      expect(body).not.toContain(`"${forbidden}"`);
    }
  });

  it("keeps the retained cells across a recreation over the same store", async () => {
    const { handler, store } = await openHandler();
    await ingest(handler, receipt());
    const before = await (await handler(request("/projection", "GET"))).text();

    const recreated = await run(
      makeFactory(releaseState([], { plans: [], wip: [] })).pipe(
        Effect.provideService(PlanningStore, store)
      )
    );
    const second = makeFactoryHttpHandler({
      factory: recreated,
      token: "test-token",
      artifactHasher: lengthHasher,
      store
    });
    expect(await (await second(request("/projection", "GET"))).text()).toBe(before);
  });

  it("serves an empty body, not an error, when the host named no store", async () => {
    const store = await run(makeInMemoryPlanningStore);
    const factory = await run(
      makeFactory(releaseState([], { plans: [] })).pipe(
        Effect.provideService(PlanningStore, store)
      )
    );
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: lengthHasher
    });
    const served = await handler(request("/projection", "GET"));
    expect(served.status).toBe(200);
    expect(await served.text()).toBe("");
  });
});
