import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  makeFactoryHttpHandler,
  makeTableArtifactHasher
} from "../src/index.ts";
import { BacklogItem } from "@substrate/planning/schema/backlog.ts";
import { CapacityReading } from "@substrate/planning/schema/capacity.ts";
import {
  armRequest,
  artifactBytes,
  artifactDigest,
  emptyFactory,
  factoryFor,
  item,
  reading,
  report,
  run,
  verdict
} from "./fixtures.ts";

const RECEIPT = fileURLToPath(
  new URL("../../schema/test/fixtures/receipt-strict-full.json", import.meta.url)
);
const receipt = (): Record<string, unknown> => JSON.parse(readFileSync(RECEIPT, "utf8"));
const encodeReading = Schema.encodeSync(CapacityReading);
const encodeItem = Schema.encodeSync(BacklogItem);

const request = (
  path: string,
  method: "GET" | "POST",
  body?: unknown,
  authenticated = true
) =>
  new Request(`https://factory.invalid${path}`, {
    method,
    headers: {
      ...(authenticated ? { authorization: "Bearer test-token" } : {}),
      ...(body === undefined ? {} : { "content-type": "application/json" })
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });

describe("the host-neutral HTTP surface", () => {
  it("requires bearer authorization on every write", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]])
    });
    const result = await handler(
      request("/capacity", "POST", encodeReading(reading({})), false)
    );
    expect(result.status).toBe(401);
  });

  it("requires bearer authorization before a proposal pull can release work", async () => {
    const factory = await factoryFor([item({ taskId: "A" })]);
    await run(factory.observeCapacity(reading({})));
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([])
    });

    const refused = await handler(
      request("/proposals?executor=coordinator", "GET", undefined, false)
    );
    expect(refused.status).toBe(401);
    expect((await run(factory.releaseState)).backlog[0]?.state).toBe("unclaimed");

    const accepted = await handler(
      request("/proposals?executor=coordinator", "GET")
    );
    expect(accepted.status).toBe(200);
    expect((await run(factory.releaseState)).backlog[0]?.state).toBe("released");
  });

  it("serves plans, capacity, proposals, outcomes and state without a Worker entry", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]])
    });
    const a = item({ taskId: "A", rank: 0 });
    expect(
      (
        await handler(
          request("/plans", "POST", {
            arm: armRequest,
            artifact: {
              planId: a.planId,
              bytes: [...artifactBytes],
              items: [encodeItem(a)]
            }
          })
        )
      ).status
    ).toBe(200);
    expect(
      (
        await handler(
          request("/capacity", "POST", encodeReading(reading({})))
        )
      ).status
    ).toBe(200);

    const proposals = await handler(request("/proposals?executor=coordinator", "GET"));
    expect(proposals.status).toBe(200);
    expect(
      (await proposals.json()) as {
        proposals: Array<{ taskId: string }>;
        next_wake_at: string | null;
      }
    ).toMatchObject({ proposals: [{ taskId: "A" }], next_wake_at: null });
    expect((await handler(request("/outcomes", "POST", report("A", "Accepted")))).status).toBe(
      200
    );
    const state = await handler(request("/state", "GET", undefined, false));
    expect(state.status).toBe(200);
    expect((await state.json()) as { backlog: Array<{ state: string }> }).toMatchObject({
      backlog: [{ state: "inflight" }]
    });
  });

  it("returns next_wake_at when every row is STOP and no proposal is admissible", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([[artifactBytes, artifactDigest]])
    });
    const a = item({ taskId: "A", rank: 0 });
    expect(
      (
        await handler(
          request("/plans", "POST", {
            arm: armRequest,
            artifact: {
              planId: a.planId,
              bytes: [...artifactBytes],
              items: [encodeItem(a)]
            }
          })
        )
      ).status
    ).toBe(200);

    const nextWakeAt = "2026-09-06T18:00:00Z";
    const encoded = encodeReading(reading({ signal: "STOP", nextWindowAt: nextWakeAt }));
    const allStopped = {
      ...encoded,
      rows: encoded.rows.map((row) => ({ ...row, signal: "STOP" as const }))
    };
    expect((await handler(request("/capacity", "POST", allStopped))).status).toBe(200);

    const response = await handler(request("/proposals?executor=coordinator", "GET"));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ proposals: [], next_wake_at: nextWakeAt });
  });

  it("returns 409 when a strict receipt has no matching mirrored verdict", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([])
    });
    const result = await handler(
      request("/receipts", "POST", {
        receipt: receipt(),
        verdict_hash: "1".repeat(64)
      })
    );
    expect(result.status).toBe(409);
  });

  it("accepts a receipt only when all three evidence cells match", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([])
    });
    const line = receipt();
    const mirrored = verdict("receipt-evaluator", "pass", 1, {
      unit_id: line["id"],
      oracle_rc: line["oracle_rc"],
      mutation_rc: (line["mutation"] as { rc: number }).rc,
      oracle_output_sha256: line["oracle_output_sha256"]
    });
    expect((await handler(request("/verdicts", "POST", mirrored))).status).toBe(200);
    expect(
      (
        await handler(
          request("/receipts", "POST", {
            receipt: line,
            verdict_hash: mirrored.hash
          })
        )
      ).status
    ).toBe(200);

    const changed = { ...line, oracle_rc: 7 };
    expect(
      (
        await handler(
          request("/receipts", "POST", {
            receipt: changed,
            verdict_hash: mirrored.hash
          })
        )
      ).status
    ).toBe(409);
    expect((await run(factory.stateView)).receipts).toHaveLength(1);
  });

  it("strictly rejects a receipt with a null measured cell", async () => {
    const factory = await emptyFactory();
    const handler = makeFactoryHttpHandler({
      factory,
      token: "test-token",
      artifactHasher: makeTableArtifactHasher([])
    });
    const invalid = { ...receipt(), tokens: null };
    expect(
      (
        await handler(
          request("/receipts", "POST", {
            receipt: invalid,
            verdict_hash: "1".repeat(64)
          })
        )
      ).status
    ).toBe(400);
  });
});
