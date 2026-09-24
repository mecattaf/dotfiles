/**
 * The mechanical evaluator result from TALLY-SPEC §2.2d.
 *
 * Parser names deliberately do not live in this package. Harness, model and
 * token-source identity are opaque strings at the lake boundary; the closed
 * parser vocabulary belongs to `apps/evaluator` (C10 / D14).
 */
import * as S from "effect/Schema"
import { assertNoWallclockField, Iso8601, Sha256Ref } from "./Common.ts"
import { CrashReason, TokenCells, TokensSource } from "./ReceiptStrict.ts"

const NonEmpty = S.String.check(S.isMinLength(1))
const Count = S.Int.check(S.isGreaterThanOrEqualTo(0))
const Seconds = S.Number.check(S.isGreaterThanOrEqualTo(0))
const CommitSha = S.String.check(S.isPattern(/^[0-9a-f]{7,40}$/))

/** U-A17's deliberately closed evaluation kinds. `merge` is not an evaluator run. */
export const EvaluationKind = S.Literals(["build", "replay"])

/** B15's three normalization rules. */
export const OracleOutputNormalization = S.Literals(["cargo-test-v1", "vitest-json-v1", "shell-v1"])

/** Exactly one immutable deliverable identity is required. */
export const Deliverable = S.Struct({
  repo: NonEmpty,
  branch: NonEmpty,
  commit_sha: S.optionalKey(CommitSha),
  tree_sha256: S.optionalKey(Sha256Ref)
}).check(
  S.makeFilter((deliverable: Record<string, unknown>) => {
    const names = Number(typeof deliverable["commit_sha"] === "string") +
      Number(typeof deliverable["tree_sha256"] === "string")
    return names === 1 ? undefined : "deliverable must carry exactly one of commit_sha or tree_sha256"
  })
)

export const EvaluationMutationHint = S.Struct({
  kind: S.Literal("hint"),
  description: NonEmpty,
  rc: S.Int
})

export const EvaluationMutationRef = S.Struct({
  kind: S.Literal("ref"),
  ref: Sha256Ref
})

export const EvaluationMutation = S.Union([EvaluationMutationHint, EvaluationMutationRef])

export const Identity = S.Struct({
  harness: NonEmpty,
  model: NonEmpty,
  seat: NonEmpty,
  row: NonEmpty,
  thread_id: S.optionalKey(NonEmpty),
  session_id: S.optionalKey(NonEmpty),
  window_id: S.Union([Iso8601, S.Literal("none"), S.Literal("unknown")])
}).check(
  S.makeFilter((identity: Record<string, unknown>) =>
    typeof identity["thread_id"] === "string" || typeof identity["session_id"] === "string"
      ? undefined
      : "identity requires a non-empty thread_id or session_id"
  )
)

const evaluatorBlockFields = {
  argv_sha256: Sha256Ref,
  lock: Sha256Ref,
  tokens: TokenCells,
  seconds: Seconds,
  execution_id: NonEmpty
} as const

export const EVALUATOR_BLOCK_FIELDS: ReadonlyArray<string> = Object.keys(evaluatorBlockFields)

/** D6 is enforced in the type: a mechanical evaluator spends zero model tokens. */
export const EvaluatorBlock = S.Struct(evaluatorBlockFields).check(
  S.makeFilter((block: Record<string, unknown>) => {
    const tokens = block["tokens"] as Record<string, number> | undefined
    if (tokens === undefined) return undefined
    const nonZero = Object.entries(tokens).filter(([, value]) => value !== 0).map(([name]) => name)
    return nonZero.length === 0 ? undefined : `evaluator token cells must all be zero; non-zero: ${nonZero.join(", ")}`
  })
)

const evaluationFields = {
  unit_id: NonEmpty,
  kind: EvaluationKind,
  card_sha256: Sha256Ref,
  deliverable: Deliverable,
  oracle_argv: S.Union([S.Array(S.String), S.Array(S.Array(S.String))]),
  oracle_sha256: Sha256Ref,
  worktree_path: NonEmpty,
  oracle_rc: S.Int,
  oracle_output_sha256: Sha256Ref,
  oracle_output_normalization: OracleOutputNormalization,
  mutation: EvaluationMutation,
  identity: Identity,
  tokens: TokenCells,
  tokens_source: TokensSource,
  seconds: Seconds,
  context_window: Count,
  max_context_used: Count,
  load_seconds: S.optionalKey(Seconds),
  concurrent_requests: S.optionalKey(Count),
  crash_reason: S.optionalKey(CrashReason),
  artifact_sha256: S.Union([Sha256Ref, S.Literal("none")]),
  pins_sha256: S.Union([Sha256Ref, S.Literal("none")]),
  evaluator: EvaluatorBlock,
  verdict: S.Literals(["PASS", "FAIL"]),
  disposition_proposed: S.Literals(["KEEP", "DISCARD", "CRASH"])
} as const

export const EVALUATION_FIELDS: ReadonlyArray<string> = Object.keys(evaluationFields)

export const Evaluation = S.Struct(evaluationFields).check(
  S.makeFilter((evaluation: Record<string, unknown>) => {
    const mutation = evaluation["mutation"] as Record<string, unknown> | undefined
    if (evaluation["kind"] === "build" && mutation?.["kind"] !== "hint") {
      return "kind build requires mutation.kind hint"
    }
    if (evaluation["kind"] === "replay" && mutation?.["kind"] !== "ref") {
      return "kind replay requires mutation.kind ref"
    }
    return undefined
  }),
  S.makeFilter((evaluation: Record<string, unknown>) => {
    if (evaluation["verdict"] !== "PASS") return undefined
    if (evaluation["oracle_rc"] !== 0) return "verdict PASS requires oracle_rc 0"
    const mutation = evaluation["mutation"] as Record<string, unknown> | undefined
    if (mutation?.["kind"] === "ref" || (mutation?.["kind"] === "hint" && mutation["rc"] !== 0)) return undefined
    return "verdict PASS requires a non-zero build mutation rc or a replay mutation ref"
  }),
  S.makeFilter((evaluation: Record<string, unknown>) =>
    evaluation["disposition_proposed"] !== "CRASH" || typeof evaluation["crash_reason"] === "string"
      ? undefined
      : "disposition_proposed CRASH requires crash_reason"
  )
)

assertNoWallclockField("Evaluation", EVALUATION_FIELDS)
assertNoWallclockField("Evaluation.EvaluatorBlock", EVALUATOR_BLOCK_FIELDS)

export type Evaluation = typeof Evaluation.Type
