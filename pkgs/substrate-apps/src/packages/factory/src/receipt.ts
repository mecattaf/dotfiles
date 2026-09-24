/** Strict receipt decoding followed by the Factory's exact verdict match. */
import { Effect } from "effect";
import { decodeReceipt } from "@substrate/schema";
import {
  type IFactory,
  type ReceiptEvidence,
  type ReceiptObservation
} from "@substrate/planning/objects/factory.ts";
import { FactoryError } from "@substrate/planning/schema/errors.ts";

const possibleId = (input: unknown): string => {
  if (input === null || typeof input !== "object") return "receipt";
  const id = (input as Record<string, unknown>)["id"];
  return typeof id === "string" ? id : "receipt";
};

/**
 * Decodes the complete §2.3 receipt. Only then are its three evidence cells
 * compared with a mirrored kernel verdict carrying `verdictHash`.
 */
export const postReceipt = (
  factory: IFactory,
  incoming: unknown,
  verdictHash: string
): Effect.Effect<ReceiptObservation, FactoryError> => {
  const decoded = decodeReceipt(incoming);
  if (!decoded.ok) {
    return Effect.fail(
      new FactoryError({
        reason: "ReceiptInvalid",
        operation: "Factory.observeReceipt",
        subject: possibleId(incoming)
      })
    );
  }
  const receipt = decoded.value;
  const base = {
    id: receipt.id,
    oracle_rc: receipt.oracle_rc,
    oracle_output_sha256: receipt.oracle_output_sha256,
    verdict_hash: verdictHash
  };
  const evidence: ReceiptEvidence =
    receipt.mutation.kind === "hint"
      ? { ...base, mutation_rc: receipt.mutation.rc }
      : base;
  return factory.observeReceipt(evidence);
};
