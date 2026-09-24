/**
 * @substrate/schema — U-A8 LAKE-SCHEMA.
 *
 * Effect Schema for {receipt, rung, card}, and the decoders that run it over
 * the estate's own corpora. See docs/schema.md for the field-by-field source
 * table and docs/schema-known-gaps.tsv for what does not decode and why.
 *
 * Every decoder here is built with ONE set of parse options and no way to pass
 * others:
 *
 *   onExcessProperty: "error"   an unknown key is a failure, not a strip
 *   errors: "all"               every issue is reported, not just the first
 *
 * The first is where R-2026-09-05-16 lives. `predicted_wallclock` is in no
 * struct, so a card or rung carrying it does not decode — the ruling is
 * enforced by the type and not by a grep over the prose. Making the option
 * optional would make the ruling optional, so it is not a parameter.
 */
import * as S from "effect/Schema"
import * as Result from "effect/Result"
import type { Value } from "./Frontmatter.ts"

export * as Frontmatter from "./Frontmatter.ts"
export * from "./Common.ts"
export {
  Arm,
  Card,
  CardPrior,
  CardResult,
  DecisionRule,
  MutationHint,
  MutationHintSpec,
  Posterior,
  Signal,
  Supervisory,
  VacuousRisk
} from "./Card.ts"
export {
  Deliverable,
  EVALUATION_FIELDS,
  EVALUATOR_BLOCK_FIELDS,
  Evaluation,
  EvaluationKind,
  EvaluationMutation,
  EvaluationMutationHint,
  EvaluationMutationRef,
  EvaluatorBlock as EvaluationEvaluatorBlock,
  Identity,
  OracleOutputNormalization
} from "./Evaluation.ts"
export { Actuals, Detector, Oracle, Rung, RungPrior, Shenanigan } from "./Rung.ts"
export {
  AttemptReceipt,
  BankedReceipt,
  Diagnosis,
  DetectorReceipt,
  Escalation,
  EstateReceipt,
  Pardon,
  Retry,
  WorkerOutcome
} from "./Receipt.ts"
export {
  Arm as ReceiptArm,
  Baseline,
  CIRU_FIELDS,
  CostAtRelease,
  CrashReason,
  EvaluatorBlock,
  Mutation,
  MutationNone,
  NONE,
  OutcomeForCalibration,
  Population,
  PostCondition,
  PredictedTokensCell,
  PriorGap,
  PriorSource,
  Receipt,
  RECEIPT_FIELDS,
  RECEIPT_OPTIONAL_FIELDS,
  ReceiptKind,
  ReceiptPrior,
  Sampling,
  Thompson,
  TokenCells,
  TokensByCell,
  TokensSource,
  TokPerS,
  WindowId
} from "./ReceiptStrict.ts"

import { Card } from "./Card.ts"
import { Evaluation } from "./Evaluation.ts"
import { Rung, Shenanigan } from "./Rung.ts"
import { AttemptReceipt, BankedReceipt, DetectorReceipt, EstateReceipt } from "./Receipt.ts"
import { Receipt } from "./ReceiptStrict.ts"

/**
 * The one parse posture this package decodes under. Not a parameter: see the
 * module header.
 */
export const PARSE_OPTIONS = {
  onExcessProperty: "error",
  errors: "all"
} as const

/** A decode that succeeded, or the reason it did not, as one printable line. */
export type Decoded<A> = { readonly ok: true; readonly value: A } | { readonly ok: false; readonly why: string }

const decoderFor = <A, I>(schema: S.Codec<A, I>) => {
  const run = S.decodeUnknownResult(schema)
  return (input: unknown): Decoded<A> => {
    const r = run(input, PARSE_OPTIONS)
    return Result.isSuccess(r)
      ? { ok: true, value: r.success }
      : { ok: false, why: r.failure.message.replace(/\s*\n\s*/g, " ") }
  }
}

export const decodeCard = decoderFor(Card)
export const decodeRung = decoderFor(Rung)
export const decodeShenanigan = decoderFor(Shenanigan)
/**
 * §2.3's receipt line, strict (U-A16). This is the decoder `POST /receipts` and
 * the evaluator run: `tokens` may not be null, every measured cell is required,
 * and D-B22's nine ciru fields are present with `"none"` where inapplicable.
 */
export const decodeReceipt = decoderFor(Receipt)

/**
 * RAWA-FLOW §5's line as the estate has already banked it (U-A8). Reads the
 * corpus; does not govern ingestion. See `ReceiptStrict.ts`'s header.
 */
/**
 * §2.2d's `Evaluation` (U-A17). The evaluator's return: what the kernel derives
 * a `verdict` from under the lock, beside the `Receipt` line the lake ingests.
 */
export const decodeEvaluation = decoderFor(Evaluation)

export const decodeBankedReceipt = decoderFor(BankedReceipt)
export const decodeDetectorReceipt = decoderFor(DetectorReceipt)
export const decodeEstateReceipt = decoderFor(EstateReceipt)
export const decodeAttemptReceipt = decoderFor(AttemptReceipt)

/**
 * Route a card path to its schema by the register layout PROMPTS.md's header
 * declares (line 6): cards at `cards/<ID>.md`, rungs at `cards/ladder/<id>.md`,
 * shenanigans at `cards/SH/SH-nn.md`. The directory is the declaration; a file
 * is never re-routed by reading its own `class`, because then a mislabelled
 * file would grade itself.
 */
export type CardKind = "card" | "rung" | "shenanigan"

export const kindOf = (relativePath: string): CardKind => {
  const parts = relativePath.split("/").filter((s) => s !== "" && s !== ".")
  if (parts.length >= 2 && parts[parts.length - 2] === "ladder") return "rung"
  if (parts.length >= 2 && parts[parts.length - 2] === "SH") return "shenanigan"
  return "card"
}

export const decodeByKind = (kind: CardKind, input: Value): Decoded<unknown> =>
  kind === "rung" ? decodeRung(input) : kind === "shenanigan" ? decodeShenanigan(input) : decodeCard(input)

export {
  Credential,
  decodeRunRecord,
  Egress,
  FORBIDDEN_EGRESS,
  Placement,
  RUN_RECORD_FIELDS,
  RunRecord,
  Runtime,
  RuntimeClass,
  Slug
} from "./RunRecord.ts"
