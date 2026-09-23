/**
 * The Factory HTTP surface as a library handler.
 *
 * U-A11 built every route but one and left the Worker entry to U-A14, which
 * added `GET /projection` — §2.2b's last unbuilt line — and the store the route
 * reads. The handler still instantiates no Worker and names no binding.
 */
import { Effect, Schema } from "effect";
import {
  ArtifactHasher,
  type IArtifactHasher
} from "@substrate/planning/objects/hasher.ts";
import type { IFactory } from "@substrate/planning/objects/factory.ts";
import { parseAdmitOutcomeReport } from "@substrate/planning/schema/admit.ts";
import { parseBacklog } from "@substrate/planning/schema/backlog.ts";
import { parseCapacityReading } from "@substrate/planning/schema/capacity.ts";
import {
  Instant,
  parseSeatCapacitySnapshot,
  SeatJob
} from "@substrate/planning/schema/seatCapacity.ts";
import { FactoryError } from "@substrate/planning/schema/errors.ts";
import { ExecutorId, PlanId } from "@substrate/planning/schema/ids.ts";
import { parsePlanArm } from "@substrate/planning/schema/plan.ts";
import { parseVerdict } from "@substrate/planning/schema/records.ts";
import { Heartbeat } from "@substrate/planning/schema/uplink.ts";
import type { IPlanningStore } from "@substrate/planning/objects/storage.ts";
import { serializeValue } from "@substrate/serializer";
import { NONE } from "./projection.ts";
import {
  mirrorProjectionRows,
  projectionBody,
  retainedReceiptOf,
  retainedReceipts,
  retainReceipt
} from "./projectionMirror.ts";
import { postReceipt } from "./receipt.ts";

const parseExecutor = Schema.decodeUnknownEffect(ExecutorId);
const parsePlanId = Schema.decodeUnknownEffect(PlanId);
const parseHeartbeat = Schema.decodeUnknownEffect(Heartbeat);
const parseInstant = Schema.decodeUnknownEffect(Instant);
const parseSeatJob = Schema.decodeUnknownEffect(SeatJob);

interface FactoryHttpOptions {
  readonly factory: IFactory;
  readonly token: string;
  readonly artifactHasher: IArtifactHasher;
  /**
   * The same store the object was built over, for `GET /projection` (U-A14).
   *
   * Optional because the route is the only thing that needs it and a host that
   * does not serve the projection should not have to name a store. Without it,
   * an accepted receipt's measured cells are not retained and the projection is
   * empty — which is an honest answer and not a silent one: an empty projection
   * says "this object mirrors no receipt", which is exactly true of a handler
   * that was given nowhere to keep one.
   */
  readonly store?: IPlanningStore;
  /**
   * The host's clock, as an RFC 3339 instant.
   *
   * The object never reads a clock; the host hands one in. It is the default
   * `asOf` for `GET /capacity`, the receipt time for pushed seats (a reading
   * dated beyond the skew tolerance ahead of it is refused) and the floor under
   * every alarm a `POST /capacity` computes. Without it, `POST /capacity/seats`
   * and a `POST /capacity` that carries `seats` are refused (501 NoClock)
   * rather than accepted against no clock (the publisher's own `published_at`
   * is never the receiving clock), and `GET /capacity` requires `asOf`.
   */
  readonly now?: () => string;
}

type FactoryHttpHandler = (request: Request) => Promise<Response>;

const response = (status: number, body: unknown): Response =>
  new Response(`${JSON.stringify(body)}\n`, {
    status,
    headers: { "content-type": "application/json; charset=utf-8" }
  });

/**
 * The projection's own response.
 *
 * Its body is JSON Lines produced by U-A12's serializer and is served verbatim:
 * re-encoding it through `response` above would put `JSON.stringify`'s
 * insertion order back on the wire and undo the one property the route exists
 * to have.
 */
const ndjson = (body: string): Response =>
  new Response(body, {
    status: 200,
    headers: { "content-type": "application/x-ndjson; charset=utf-8" }
  });

const asRecord = (value: unknown): Record<string, unknown> => {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("request body must be a JSON object");
  }
  return value as Record<string, unknown>;
};

const decodeBase64 = (value: unknown, field: string): Uint8Array => {
  if (typeof value !== "string") throw new TypeError(`${field} must be base64 text`);
  try {
    const binary = atob(value);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw new TypeError(`${field} must be valid base64`);
  }
};

const concatenate = (...parts: ReadonlyArray<Uint8Array>): Uint8Array => {
  const joined = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return joined;
};

const statusFor = (error: unknown): number => {
  if (error instanceof FactoryError) {
    if (error.reason === "ReceiptMismatch" || error.reason === "ContinuityGap") return 409;
    if (error.reason === "InvalidTransition" || error.reason === "DedupMismatch") return 409;
    if (error.reason === "ReceiptInvalid") return 400;
    if (error.reason === "UnknownTask" || error.reason === "PlanNotArmed") return 404;
  }
  return 400;
};

const errorBody = (error: unknown): Record<string, string> => {
  if (error instanceof FactoryError) {
    return { error: error.reason, operation: error.operation, subject: error.subject };
  }
  if (
    error !== null &&
    typeof error === "object" &&
    "_tag" in error &&
    typeof (error as { readonly _tag?: unknown })._tag === "string"
  ) {
    return { error: String((error as { readonly _tag: string })._tag) };
  }
  return { error: error instanceof Error ? error.message : "invalid request" };
};

/**
 * Builds the route handler without creating a Worker entry or selecting a
 * persistence binding. Every state-changing request checks the supplied bearer
 * token, including the proposal pull that releases backlog items.
 */
export const makeFactoryHttpHandler = (options: FactoryHttpOptions): FactoryHttpHandler => {
  const run = <A, E>(effect: Effect.Effect<A, E, ArtifactHasher>): Promise<A> =>
    Effect.runPromise(
      effect.pipe(
        Effect.provideService(
          ArtifactHasher,
          ArtifactHasher.of(options.artifactHasher)
        )
      )
    );

  /** `?asOf=` when given (validated), else the host's clock, else nothing. */
  const asOfFrom = async (url: URL): Promise<string | undefined> => {
    const raw = url.searchParams.get("asOf");
    if (raw !== null) return Effect.runPromise(parseInstant(raw));
    return options.now?.();
  };

  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    const changesState =
      (request.method !== "GET" && request.method !== "HEAD") ||
      (request.method === "GET" && url.pathname === "/proposals");
    if (
      changesState &&
      request.headers.get("authorization") !== `Bearer ${options.token}`
    ) {
      // Drain before refusing. The refusal itself needs nothing from the body,
      // but a Worker that answers while the request stream is still open makes
      // workerd log `Can't read from request stream after response has been
      // sent` — an uncaught TypeError in the dev log of an otherwise green
      // smoke, which is exactly the kind of noise a reader learns to ignore.
      await request.arrayBuffer().catch(() => undefined);
      return response(401, { error: "Unauthorized" });
    }

    try {
      if (request.method === "GET" && url.pathname === "/projection") {
        if (options.store === undefined) return ndjson("");
        const retained = await Effect.runPromise(retainedReceipts(options.store));
        const state = await run(options.factory.stateView);
        return ndjson(projectionBody(mirrorProjectionRows(retained, state.receipts)));
      }

      if (request.method === "GET" && url.pathname === "/state") {
        return response(200, await run(options.factory.stateView));
      }

      if (request.method === "GET" && url.pathname === "/proposals") {
        const raw = url.searchParams.get("executor");
        if (raw === null) return response(400, { error: "executor is required" });
        const executor = await Effect.runPromise(parseExecutor(raw));
        const proposals = await run(options.factory.handOut(executor));
        const state = await run(options.factory.stateView);
        return response(200, {
          proposals,
          next_wake_at: state.alarm_at
        });
      }

      if (request.method === "POST" && url.pathname === "/capacity") {
        const body = await request.json();
        const record = asRecord(body);
        const { seats, ...reading } = await Effect.runPromise(
          parseCapacityReading(record["reading"] ?? body)
        );
        const asOf = options.now?.();
        // Seats need a receiving clock, the same as on POST /capacity/seats.
        // Refused whole, before anything is folded in, so the two doors agree.
        if (seats !== undefined && asOf === undefined) {
          return response(501, { error: "NoClock", subject: "/capacity" });
        }
        // The seats are the ledger's: folded in on their own monotonic rule,
        // whatever becomes of the reading's seq.
        const seatReport =
          seats === undefined || asOf === undefined
            ? undefined
            : await run(options.factory.observeSeats(seats, asOf));
        const accepted = await run(options.factory.observeCapacity(reading, asOf));
        return response(200, seatReport === undefined ? { accepted } : { accepted, seats: seatReport });
      }

      if (request.method === "POST" && url.pathname === "/capacity/seats") {
        const receivedAt = options.now?.();
        if (receivedAt === undefined) {
          await request.arrayBuffer().catch(() => undefined);
          return response(501, { error: "NoClock", subject: "/capacity/seats" });
        }
        const body = asRecord(await request.json());
        const snapshot = await Effect.runPromise(
          parseSeatCapacitySnapshot(body["snapshot"] ?? body)
        );
        return response(200, await run(options.factory.observeSeats(snapshot, receivedAt)));
      }

      if (request.method === "GET" && url.pathname === "/capacity") {
        const asOf = await asOfFrom(url);
        if (asOf === undefined) return response(400, { error: "asOf is required" });
        return response(200, await run(options.factory.capacityAt(asOf)));
      }

      if (request.method === "GET" && url.pathname === "/capacity/admit") {
        const seat = url.searchParams.get("seat");
        if (seat === null) return response(400, { error: "seat is required" });
        const asOf = await asOfFrom(url);
        if (asOf === undefined) return response(400, { error: "asOf is required" });
        const minimum = url.searchParams.get("min_headroom_pct");
        const job = await Effect.runPromise(
          parseSeatJob({
            model: url.searchParams.get("model"),
            min_headroom_pct: minimum === null ? 0 : Number(minimum)
          })
        );
        return response(200, await run(options.factory.admitSeat(seat, job, asOf)));
      }

      if (request.method === "POST" && url.pathname === "/outcomes") {
        const report = await Effect.runPromise(
          parseAdmitOutcomeReport(await request.json())
        );
        return response(200, await run(options.factory.observeOutcome(report)));
      }

      if (request.method === "POST" && url.pathname === "/verdicts") {
        const verdict = await Effect.runPromise(parseVerdict(await request.json()));
        return response(200, await run(options.factory.observeVerdict(verdict)));
      }

      if (request.method === "POST" && url.pathname === "/receipts") {
        const body = asRecord(await request.json());
        const verdictHash = body["verdict_hash"];
        if (typeof verdictHash !== "string") {
          return response(400, { error: "verdict_hash is required" });
        }
        let receipt: unknown = body["receipt"];
        if (receipt === undefined) {
          const inline = { ...body };
          delete inline["verdict_hash"];
          receipt = inline;
        }
        const observation = await run(postReceipt(options.factory, receipt, verdictHash));

        // Accepted. The three evidence cells are now in the mirror; the
        // measured cells (`seconds`, `tokens`, `disposition`) live only in
        // these bytes, so they are retained beside the object's state for
        // `GET /projection`. The digest is taken over the receipt's CANONICAL
        // bytes — U-A12's serializer — so the same receipt yields the same
        // `receipt_sha256` whichever order its keys arrived in.
        if (options.store !== undefined) {
          const path = body["receipt_path"];
          const canonical = serializeValue(receipt);
          const digest = await Effect.runPromise(
            options.artifactHasher.hash(
              new TextEncoder().encode(canonical),
              "receipt"
            )
          );
          const retained = retainedReceiptOf(
            receipt,
            typeof path === "string" ? path : NONE,
            digest
          );
          if (retained.ok) {
            await Effect.runPromise(retainReceipt(options.store, retained.retained));
          }
        }
        return response(200, observation);
      }

      if (request.method === "POST" && url.pathname === "/heartbeats") {
        const body = asRecord(await request.json());
        const heartbeat = await Effect.runPromise(parseHeartbeat(body["heartbeat"] ?? body));
        const lane = typeof body["lane"] === "string" ? body["lane"] : undefined;
        const observedAt =
          typeof body["observed_at"] === "string" ? body["observed_at"] : undefined;
        await run(options.factory.observeHeartbeat(heartbeat, lane, observedAt));
        return response(200, { accepted: true });
      }

      if (request.method === "POST" && url.pathname === "/plans") {
        const body = asRecord(await request.json());

        // The acceptor owns this producer shape. Its planHash is over the
        // concatenated script and args bytes, and its plan items are enriched
        // here with the release-state fields that are Factory concerns.
        if (body["plan"] !== undefined) {
          const plan = asRecord(body["plan"]);
          const meta = plan["meta"] === undefined ? {} : asRecord(plan["meta"]);
          const arm = await Effect.runPromise(
            parsePlanArm({
              label:
                typeof meta["name"] === "string" && meta["name"] !== "none"
                  ? meta["name"]
                  : "conwip plan arm",
              kind: "workflow",
              level: plan["level"],
              namespace: plan["namespace"],
              planHash: body["planHash"],
              author:
                typeof plan["acceptor"] === "string"
                  ? plan["acceptor"]
                  : "conwip plan arm"
            })
          );
          const planId = await Effect.runPromise(parsePlanId(arm.planHash));
          if (plan["planHash"] !== arm.planHash) {
            throw new FactoryError({
              reason: "PlanHashMismatch",
              operation: "FactoryHttp.POST /plans",
              subject: planId
            });
          }

          const rawItems = plan["items"];
          if (!Array.isArray(rawItems)) throw new TypeError("plan.items must be an array");
          const current = await run(options.factory.releaseState);
          const itemRecords = rawItems.map((value) => asRecord(value));
          const decodedItems = await Effect.runPromise(
            parseBacklog(
              itemRecords.map((item) => {
                if (item["planHash"] !== arm.planHash) {
                  throw new FactoryError({
                    reason: "PlanHashMismatch",
                    operation: "FactoryHttp.POST /plans",
                    subject: planId
                  });
                }
                const namespace = item["namespace"] ?? arm.namespace;
                const namespaceValue = current.namespaces.namespaces.find(
                  (entry) => entry.name === namespace
                )?.value;
                const mutationHint = item["mutation_hint"];
                const argvRef = item["argv_ref"];
                return {
                  taskId: item["taskId"],
                  planId,
                  namespace,
                  family: item["family"] ?? "build",
                  level: item["level"] ?? arm.level,
                  rank: item["rank"],
                  needs: item["needs"],
                  dependsOn: item["dependsOn"] ?? [],
                  evidence: item["evidence"] ?? [],
                  briefHash: item["briefHash"],
                  planHash: item["planHash"],
                  dedupKey: item["dedupKey"],
                  state: item["state"],
                  deferrals: item["deferrals"] ?? 0,
                  attempt: item["attempt"] ?? 1,
                  outcome: item["outcome"] ?? null,
                  value: item["value"] ?? namespaceValue ?? 1,
                  estimate: item["estimate"] ?? current.estimates.mainEffect,
                  gate: item["gate"],
                  subassembly: item["subassembly"] ?? null,
                  dueBy: item["dueBy"] ?? null,
                  float: item["float"] ?? null,
                  envelopeParent: item["envelopeParent"] ?? null,
                  ...(typeof mutationHint === "string" && mutationHint !== "none"
                    ? { mutation_hint: mutationHint }
                    : {}),
                  ...(typeof argvRef === "string" ? { argv_ref: argvRef } : {})
                };
              })
            )
          );
          const bytes = concatenate(
            decodeBase64(body["script_bytes_base64"], "script_bytes_base64"),
            decodeBase64(body["args_bytes_base64"], "args_bytes_base64")
          );
          const row = await run(
            options.factory.armPlan(arm, { planId, bytes, items: decodedItems })
          );
          return response(200, row);
        }

        const artifactBody = asRecord(body["artifact"]);
        const arm = await Effect.runPromise(parsePlanArm(body["arm"]));
        const planId = await Effect.runPromise(parsePlanId(artifactBody["planId"]));
        const items = await Effect.runPromise(parseBacklog(artifactBody["items"]));
        const bytes = artifactBody["bytes"];
        if (
          !Array.isArray(bytes) ||
          !bytes.every((entry) => Number.isInteger(entry) && entry >= 0 && entry <= 255)
        ) {
          return response(400, { error: "artifact.bytes must be byte values" });
        }
        const row = await run(
          options.factory.armPlan(arm, {
            planId,
            bytes: Uint8Array.from(bytes as ReadonlyArray<number>),
            items
          })
        );
        return response(200, row);
      }

      return response(404, { error: "NotFound" });
    } catch (error) {
      return response(statusFor(error), errorBody(error));
    }
  };
};
