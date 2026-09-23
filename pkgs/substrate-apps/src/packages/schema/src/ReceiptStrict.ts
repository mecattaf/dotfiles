/**
 * ReceiptStrict.ts — U-A16 LAKE-RECEIPT-STRICT. The §2.3 `Receipt`.
 *
 * `Receipt.ts` carries the shapes the estate has ALREADY banked: `BankedReceipt`
 * (RAWA-FLOW.md §5's line as the 19 lines on disk write it, `tokens` nullable),
 * P12's `DetectorReceipt`, and the box's `AttemptReceipt`. This file carries the
 * one the lake INGESTS from now on, and it is a different type on purpose.
 *
 * TALLY-SPEC-2026-09-06.md §2.3, verbatim, is the field list:
 *
 *   "Every field below is required unless marked `?`; a required field that
 *    cannot be stamped makes the line `disposition: CRASH` with a named
 *    `crash_reason`, never a null"
 *
 * and, for `tokens` in particular (TL-7 / DECISIONS.md D-B7):
 *
 *   "`tokens` may not be `null` (TL-7)."
 *
 * So there is no `S.NullOr` anywhere below. That is not a style: it is the
 * unit's whole claim, and it is measured rather than asserted by
 * `tools/decode-estate.mjs --negative-control tokens-null`, which decodes the
 * 19 banked lines that DO carry `tokens: null` against this type and exits
 * non-zero because every one of them is refused, each named.
 *
 * The nine ciru fields of DECISIONS.md D-B22 (`control_receipt_id`, `baseline`,
 * `disposition_class`, `not_evidence_for`, `confirmation_of`, `setup_seconds`,
 * `post_conditions`, `population`, `supersedes`/`superseded_by`, `shape`) are
 * required too, and an inapplicable one carries the STRING `"none"` — never a
 * null, never an omission. `orNone` below is that convention, in one place.
 *
 * What is deliberately NOT closed here, and why:
 *
 *   `harness`, `model`, `arm.harness`, `arm.model`, `seat`, `row`,
 *   `tokens_source.kind`               — §2.2a: "`tokens_source.kind` is
 *                                        `Schema.String` in `packages/schema`;
 *                                        the literal union of harness parsers
 *                                        lives in `apps/evaluator` only, so
 *                                        `tools/no-harness-names.mjs packages`
 *                                        stays at 0 hits" (D14).
 *   `oracle_output_normalization`      — §2.2d names three rule ids and they are
 *                                        the evaluator's vocabulary, not the
 *                                        schema's; same reason as above.
 *   `disposition_class`                — the ciru vocabulary is not enumerated
 *                                        in any source this unit takes as
 *                                        authority. A closed list would be a
 *                                        ruling, and rulings are Tom's
 *                                        (R-2026-09-05-03).
 *
 * `seconds`, `setup_seconds`, `started_at`, `finished_at`, `load_seconds` and
 * `gpu_seconds` are measurements of a run that happened. R-2026-09-05-16 strikes
 * PREDICTED wall clock and keeps measured seconds; `assertNoWallclockField`
 * below is run over this struct's own field names so the two cannot be confused
 * by a later edit.
 */
import * as S from "effect/Schema"
import { assertNoWallclockField, Disposition, Iso8601, Probability, Sha256Ref, Tokens } from "./Common.ts"

// --- the "none" convention (D-B22) -------------------------------------------

/** The one string an inapplicable cell carries. Never `null`, never absent. */
export const NONE = "none" as const

/**
 * `A | "none"`. D-B22: "An inapplicable field carries the string `"none"`,
 * never null"; handoff rule 4, "no null field".
 */
const orNone = <A, I>(schema: S.Codec<A, I>) => S.Union([schema, S.Literal(NONE)])

/** A string that says something. An empty string is not a measurement. */
const NonEmpty = S.String.check(S.isMinLength(1))

/** A count. */
const Count = S.Int.check(S.isGreaterThanOrEqualTo(0))

/** A measured duration in seconds. An outcome, not a prediction (R-2026-09-05-16). */
const Seconds = S.Number.check(S.isGreaterThanOrEqualTo(0))

/** A git object name, abbreviated or full, as the banked receipts write it. */
const CommitSha = S.String.check(S.isPattern(/^[0-9a-f]{7,40}$/))

// --- the blocks --------------------------------------------------------------

/**
 * §2.3: "`tokens{in_uncached, cache_read, cache_write, out, reasoning, total}`
 * (every cell an integer)". Six cells, all required, all `Tokens` = a
 * non-negative integer. No cell is nullable and no cell is optional: this struct
 * is what TL-7 means by "measured at the source".
 */
export const TokenCells = S.Struct({
  in_uncached: Tokens,
  cache_read: Tokens,
  cache_write: Tokens,
  out: Tokens,
  reasoning: Tokens,
  total: Tokens
})
export type TokenCells = typeof TokenCells.Type

/**
 * §2.3: "`tokens_source{kind, path, first_event, last_event}`". `kind` is a
 * plain string here by §2.2a (D14); the parser-id union is `apps/evaluator`'s.
 * The two event cells are whatever the source names an event by — an ISO stamp
 * on one harness, an ordinal on another — so both forms decode and neither is
 * invented.
 */
export const TokensSource = S.Struct({
  kind: NonEmpty,
  path: NonEmpty,
  first_event: S.Union([NonEmpty, S.Int]),
  last_event: S.Union([NonEmpty, S.Int])
})

/** §2.3: "`arm{harness, model, seat}`". Strings, for the reason in the header. */
export const Arm = S.Struct({
  harness: NonEmpty,
  model: NonEmpty,
  seat: NonEmpty
})

/** §2.3: "`tok_per_s{prefill, decode}?` (local arms only, from print_timing …)". */
export const TokPerS = S.Struct({
  prefill: S.Number.check(S.isGreaterThanOrEqualTo(0)),
  decode: S.Number.check(S.isGreaterThanOrEqualTo(0))
})

/** §2.3: "`sampling{temperature, seed}?`". */
export const Sampling = S.Struct({
  temperature: S.Number,
  seed: S.Int
})

/**
 * §2.3: "`mutation{kind: hint|ref, rc | ref}`". A tagged union, so a `hint`
 * mutation must carry the rc it measured and a `ref` mutation must carry the
 * frontier receipt it points at — and neither can carry the other's cell.
 * §2.2d: validation in the lake asserts `mutation.rc != 0` on a build, or
 * `mutation.kind == ref` on a replay.
 */
const MutationHint = S.Struct({ kind: S.Literal("hint"), rc: S.Int })
const MutationRef = S.Struct({ kind: S.Literal("ref"), ref: Sha256Ref })
/** B5's honest representation when no mutation ran; no rc is fabricated. */
export const MutationNone = S.Struct({ kind: S.Literal("none"), reason: S.Literal("no-mutation-hint") })
export const Mutation = S.Union([MutationHint, MutationRef, MutationNone])

/** §2.3: "`evaluator{argv_sha256, lock, tokens{…}, seconds, execution_id}`". */
export const EvaluatorBlock = S.Struct({
  argv_sha256: Sha256Ref,
  lock: Sha256Ref,
  tokens: TokenCells,
  seconds: Seconds,
  execution_id: NonEmpty
}).check(
  S.makeFilter((block: Record<string, unknown>) => {
    const tokens = block["tokens"] as Record<string, number> | undefined
    if (tokens === undefined) return undefined
    const nonZero = Object.entries(tokens).filter(([, value]) => value !== 0).map(([name]) => name)
    return nonZero.length === 0
      ? undefined
      : `evaluator token cells must all be zero (§2.2d / D6); non-zero: ${nonZero.join(", ")}`
  })
)

/**
 * §2.3: "`cost_at_release{row, price_hash, unit, value}` … stated in the row's
 * price unit … never in raw token counts".
 */
export const CostAtRelease = S.Struct({
  row: NonEmpty,
  price_hash: Sha256Ref,
  unit: NonEmpty,
  value: S.Number
})

/**
 * §2.3's `predicted_tokens_cell` vocabulary, and D-B19: "`predicted_tokens_cell:
 * out` on every prior written from now"; the 89 card-text priors stay
 * `unruled`. A prior with no cell does not decode, which is the
 * `prior-without-cell` control.
 */
export const PredictedTokensCell = S.Literals(["out", "in_uncached+out", "total", "unruled"])

/** §2.3: "`prior_source ∈ {card-text, scoping-node, band}`". */
export const PriorSource = S.Literals(["card-text", "scoping-node", "band"])

/** §2.3: "`thompson{seed, alpha, beta}?`". */
export const Thompson = S.Struct({
  seed: S.Int,
  alpha: S.Number.check(S.isGreaterThan(0)),
  beta: S.Number.check(S.isGreaterThan(0))
})

/**
 * §2.3's `prior{…}`. `difficulty_scale` is a string because D-B9 sets the scale
 * ("1–5") and the scoping node states it per card; writing the range as a
 * literal here would freeze one card's statement into the type.
 */
export const ReceiptPrior = S.Struct({
  difficulty: S.Int.check(S.isBetween({ minimum: 1, maximum: 5 })),
  difficulty_scale: NonEmpty,
  p_pass: Probability,
  predicted_tokens: Tokens,
  predicted_tokens_cell: PredictedTokensCell,
  basis: NonEmpty,
  p_pass_basis: NonEmpty,
  difficulty_basis: NonEmpty,
  prior_source: PriorSource,
  prior_executor: NonEmpty,
  thompson: S.optionalKey(Thompson)
})

/**
 * §2.3's `prior_gap{tokens_by_cell{out, in_uncached+out, total},
 * tokens_in_declared_cell?, p_pass_vs_outcome}`. The gap is printed in every
 * cell (D-B19) precisely because the 89 card-text priors declare none, so the
 * three cells are required and the declared-cell reading is the optional one.
 */
export const TokensByCell = S.Struct({
  "out": S.Int,
  "in_uncached+out": S.Int,
  "total": S.Int
})

export const PriorGap = S.Struct({
  tokens_by_cell: TokensByCell,
  tokens_in_declared_cell: S.optionalKey(S.Int),
  p_pass_vs_outcome: S.Number
})

// --- the ciru blocks (D-B22, §7 amendment 4) ---------------------------------

/**
 * D-B20: "`build`: `baseline = {metric: oracle_rc, value: <rc of the same oracle
 * on the parent commit>, receipt_id: <that run>}`, `control_receipt_id` = that
 * control run; `replay`: the frontier receipt; `merge`: the wave's receipt".
 */
export const Baseline = S.Struct({
  metric: NonEmpty,
  value: S.Union([S.Number, S.String]),
  receipt_id: NonEmpty
})

/** D-B22: "`post_conditions[]{name, rc}`". */
export const PostCondition = S.Struct({
  name: NonEmpty,
  rc: S.Int
})

/** D-B22: "`population{cards, schema_valid, tests_passing}`". */
export const Population = S.Struct({
  cards: Count,
  schema_valid: Count,
  tests_passing: Count
})

/**
 * The nine receipt-side ciru fields, in D-B22's own order. Split out so the
 * decision they come from can be read as one block, and so a later unit can see
 * at a glance that all nine are required and none is nullable.
 */
const ciruFields = {
  control_receipt_id: orNone(NonEmpty),
  baseline: orNone(Baseline),
  disposition_class: orNone(NonEmpty),
  not_evidence_for: orNone(S.Array(NonEmpty).check(S.isMinLength(1))),
  confirmation_of: orNone(NonEmpty),
  setup_seconds: orNone(Seconds),
  post_conditions: orNone(S.Array(PostCondition).check(S.isMinLength(1))),
  population: orNone(Population),
  supersedes: orNone(NonEmpty),
  superseded_by: orNone(NonEmpty),
  shape: orNone(S.Record(S.String, S.Unknown))
} as const

/** The names D-B22 lists, for the docs, the tests and the tool. */
export const CIRU_FIELDS: ReadonlyArray<string> = Object.keys(ciruFields)

// --- the receipt -------------------------------------------------------------

/**
 * §2.3: "`kind: build|replay`". D-B20 defines the matched control for a third,
 * `merge` ("the wave's receipt"), so `merge` decodes too; see DECISIONS.md
 * D-A16-1 in this repository.
 */
export const ReceiptKind = S.Literals(["build", "replay", "merge"])

/** §2.3: "`window_id` (the row's `resets_at` | `"none"` | `"unknown"`)". */
export const WindowId = S.Union([Iso8601, S.Literal("none"), S.Literal("unknown")])

/** §2.3: "`crash_reason? ∈ {serve, oom, context_overflow, runtime_cap, measurement, no-mutation-hint}`". */
export const CrashReason = S.Literals([
  "serve",
  "oom",
  "context_overflow",
  "runtime_cap",
  "measurement",
  "no-mutation-hint"
])

/** §2.3: "`outcome_for_calibration ∈ {pass, fail, excluded}`". Computed, never typed. */
export const OutcomeForCalibration = S.Literals(["pass", "fail", "excluded"])

/**
 * §2.3's own mapping from `crash_reason` to `outcome_for_calibration`:
 *
 *   "DISCARD·FAIL, `runtime_cap`, `context_overflow` → `fail` (they update
 *    belief about the arm); `serve`, `oom`, `measurement`, `no-mutation-hint`,
 *    `cancelled`, `preempted` → `excluded` (CRASH, `program.md` 'updates no
 *    belief')".
 *
 * The two `fail` reasons and the four `excluded` ones are determinate from the
 * crash reason alone, so the type carries them. KEEP·PASS → `pass` needs the
 * disposition AND the oracle rc AND Tom's ruling, so the type does not compute
 * it — that is the evaluator's (U-A17).
 */
const CRASH_REASON_OUTCOME: Record<string, "fail" | "excluded"> = {
  runtime_cap: "fail",
  context_overflow: "fail",
  serve: "excluded",
  oom: "excluded",
  measurement: "excluded",
  "no-mutation-hint": "excluded"
}

const receiptFields = {
  // identity
  id: NonEmpty,
  kind: ReceiptKind,
  attempt: S.Int.check(S.isGreaterThanOrEqualTo(1)),
  card_sha256: Sha256Ref,
  prior_lock_commit: CommitSha,
  repo: NonEmpty,
  seat: NonEmpty,
  row: NonEmpty,
  harness: NonEmpty,
  model: NonEmpty,
  arm: Arm,
  // §2.3: "thread_id|session_id (non-empty)" — one cell under two names.
  thread_id: S.optionalKey(NonEmpty),
  session_id: S.optionalKey(NonEmpty),
  window_id: WindowId,
  // measurement
  started_at: Iso8601,
  finished_at: Iso8601,
  // §2.2d's determinism clause names this receipt timestamp explicitly.
  observed_at: Iso8601,
  seconds: Seconds,
  tokens: TokenCells,
  tokens_source: TokensSource,
  context_window: Count,
  max_context_used: Count,
  tok_per_s: S.optionalKey(TokPerS),
  load_seconds: S.optionalKey(Seconds),
  concurrent_requests: S.optionalKey(Count),
  gpu_seconds: S.optionalKey(Seconds),
  sampling: S.optionalKey(Sampling),
  // the run
  commit_sha: CommitSha,
  branch: NonEmpty,
  oracle_argv: S.Union([S.Array(S.String), S.Array(S.Array(S.String))]),
  oracle_sha256: Sha256Ref,
  oracle_rc: S.Int,
  oracle_output_sha256: Sha256Ref,
  oracle_output_normalization: NonEmpty,
  mutation: Mutation,
  artifact_sha256: orNone(Sha256Ref),
  pins_sha256: orNone(Sha256Ref),
  evaluator: EvaluatorBlock,
  cost_at_release: CostAtRelease,
  runtime_cap_seconds: Count,
  // the verdict's record
  disposition: Disposition,
  crash_reason: S.optionalKey(CrashReason),
  outcome_for_calibration: OutcomeForCalibration,
  outcome_ruled: S.optionalKey(S.Literals(["KEEP", "DISCARD"])),
  // the prior and its gap
  prior: ReceiptPrior,
  difficulty_scoped: S.optionalKey(S.Int.check(S.isBetween({ minimum: 1, maximum: 5 }))),
  prior_gap: PriorGap,
  notes: S.String,
  // D-B22
  ...ciruFields
} as const

/** The optional keys of `Receipt`, by name. §2.3's `?` marks, and nothing else. */
export const RECEIPT_OPTIONAL_FIELDS: ReadonlyArray<string> = [
  "thread_id",
  "session_id",
  "tok_per_s",
  "load_seconds",
  "concurrent_requests",
  "gpu_seconds",
  "sampling",
  "crash_reason",
  "outcome_ruled",
  "difficulty_scoped"
]

/** Every declared key of `Receipt`, in declaration order. */
export const RECEIPT_FIELDS: ReadonlyArray<string> = Object.keys(receiptFields)

/**
 * The §2.3 receipt line, strict. Four rules ride on the struct rather than on a
 * field, because each is about two cells at once. Every message names the cells
 * it is about, so a refusal is legible without reading this file.
 */
export const Receipt = S.Struct(receiptFields).check(
  // "thread_id|session_id (non-empty)" — the identity of the run in the harness's
  // own record, without which no usage row can be joined to it (GROUND-bayes §0.1).
  S.makeFilter((r: Record<string, unknown>) =>
    typeof r["thread_id"] === "string" || typeof r["session_id"] === "string"
      ? undefined
      : "a receipt must carry a non-empty thread_id or session_id: the harness's own identity for the run"
  ),
  // "a required field that cannot be stamped makes the line `disposition: CRASH`
  // with a named `crash_reason`, never a null". The converse is not asserted: a
  // CRASH is the only disposition that REQUIRES a reason.
  S.makeFilter((r: Record<string, unknown>) =>
    r["disposition"] !== "CRASH" || typeof r["crash_reason"] === "string"
      ? undefined
      : "disposition CRASH requires a named crash_reason (§2.3): a stamp that failed is named, never nulled"
  ),
  // §2.3's own computation of `outcome_for_calibration` from `crash_reason`.
  S.makeFilter((r: Record<string, unknown>) => {
    const reason = r["crash_reason"]
    if (typeof reason !== "string") return undefined
    const want = CRASH_REASON_OUTCOME[reason]
    if (want === undefined || r["outcome_for_calibration"] === want) return undefined
    return `crash_reason '${reason}' fixes outcome_for_calibration at '${want}' (§2.3), not '${
      String(r["outcome_for_calibration"])
    }'`
  }),
  // "refuse to stamp `tok_per_s` when `concurrent_requests > 0`" (§2.2d, §2.3).
  S.makeFilter((r: Record<string, unknown>) =>
    typeof r["concurrent_requests"] === "number" && r["concurrent_requests"] > 0 && r["tok_per_s"] !== undefined
      ? "tok_per_s may not be stamped when concurrent_requests > 0 (§2.3): the rate is not the arm's"
      : undefined
  ),
  S.makeFilter((r: Record<string, unknown>) => {
    const mutation = r["mutation"] as Record<string, unknown> | undefined
    const noHint = mutation?.["kind"] === "none"
    const named = r["crash_reason"] === "no-mutation-hint"
    if (noHint && (!named || r["disposition"] !== "CRASH")) {
      return "mutation.kind none requires disposition CRASH and crash_reason no-mutation-hint"
    }
    if (!noHint && named) return "crash_reason no-mutation-hint requires mutation.kind none"
    return undefined
  })
)

assertNoWallclockField("ReceiptStrict.Receipt", RECEIPT_FIELDS)
assertNoWallclockField("ReceiptStrict.ReceiptPrior", Object.keys(ReceiptPrior.fields))
assertNoWallclockField("ReceiptStrict.EvaluatorBlock", Object.keys(EvaluatorBlock.fields))

export type Receipt = typeof Receipt.Type
