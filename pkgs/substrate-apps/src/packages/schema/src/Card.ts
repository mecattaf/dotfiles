/**
 * Card.ts — U-A8 LAKE-SCHEMA. The `card` of {receipt, rung, card}.
 *
 * Source of the field set, in order of authority:
 *
 *   1. /home/tom/research-methods/README.md §5, "Draft card front matter
 *      (proposal, not built; Tom to strike or amend)" — the block of YAML that
 *      names id, title, status, class, created, armed_at, armed_commit,
 *      depends_on, data_already_collected, problem, theory, hypotheses, signal,
 *      decision_rule, prior, arm, result, posterior, supervisory.
 *   2. The header of /home/tom/research-methods/PROMPTS.md, line 6:
 *      "cards at /home/tom/research-methods/cards/<ID>.md in the README §5
 *      front matter plus difficulty, predicted_tokens, use_case_class, arm".
 *   3. MEASURED on disk 2026-09-06: `seat` (4 cards) and `vacuous_risk`
 *      (7 cards) are carried by the register and named by neither source; they
 *      are optional here and marked MEASURED in docs/schema.md.
 *
 * NOT in the field set: `predicted_wallclock`. R-2026-09-05-16 strikes it, and
 * the struct is closed — decoding runs with `onExcessProperty: "error"` — so a
 * card that carries it is REJECTED rather than quietly stripped. That is the
 * unit's negative control, and it is the type that enforces it, not a grep.
 *
 * The three fields of cards/UTIL-01.md that no source names — `definition`,
 * `row_schema`, `reference_job` — are deliberately absent: that card is a
 * specification written into front matter, and admitting its shape would make
 * the type a description of one file. It is a named gap instead.
 */
import * as S from "effect/Schema"
import { PredictedTokensCell, PriorSource } from "./ReceiptStrict.ts"
import { Actuals, Oracle } from "./Rung.ts"
import {
  assertNoWallclockField,
  Basis,
  CalendarDate,
  CardClass,
  Difficulty,
  fieldsOf,
  Grade,
  Hypothesis,
  Id,
  Probability,
  Status,
  Tokens
} from "./Common.ts"

/** README §5 `signal`: metric, instrument, sample_target, receipt. */
export const Signal = S.Struct({
  metric: S.String,
  instrument: S.String,
  sample_target: S.Union([S.Number, S.String]),
  receipt: S.String,
  // MEASURED extensions: the hash and posture fields P01 and P05 added so an
  // instrument cannot be swapped after arming.
  instrument_sha256: S.optionalKey(S.Union([S.String, S.Record(S.String, S.String)])),
  spec_sha256: S.optionalKey(S.String),
  spec_version: S.optionalKey(S.Number),
  schema_sha256: S.optionalKey(S.String),
  read_only: S.optionalKey(S.Boolean),
  network: S.optionalKey(S.String)
})
assertNoWallclockField("Card.Signal", fieldsOf(Signal))

/** README §5 `decision_rule`, frozen by arming. */
export const DecisionRule = S.Struct({
  comparator: S.String,
  if_pass: S.String,
  if_fail: S.String,
  abort_on: S.Array(S.String),
  threshold: S.optionalKey(S.Union([S.Number, S.String, S.Array(S.String)])),
  // MEASURED: cards/EXP-000.md splits the threshold into what the prompt wrote
  // and what the session proposes, because the written one is not meetable.
  threshold_as_written: S.optionalKey(S.Array(S.String)),
  threshold_proposed: S.optionalKey(S.Array(S.String)),
  tonight: S.optionalKey(S.String)
})
assertNoWallclockField("Card.DecisionRule", fieldsOf(DecisionRule))

/**
 * README §5 `prior`: {p_pass, basis}. The rest is MEASURED — the reasoning
 * fields P04's charter requires, and the two `p_pass_*` variants one card
 * carries for a single night.
 *
 * `predicted_opus_tokens` is here and `predicted_wallclock` is not: tokens are
 * a usage quantity and stay, wall-clock predictions go (R-2026-09-05-16).
 */
export const CardPrior = S.Struct({
  basis: Basis,
  p_pass: S.optionalKey(Probability),
  // MEASURED: on a CARD this field carries the REASONING for p_pass in prose
  // (8 of 8 uses are block scalars). The vocabulary word README §5 names lives
  // in `basis` beside it. On a RUNG the two are split the other way round —
  // `p_pass_basis` is the word, `p_pass_reason` the prose — so only the rung's
  // is checked against the vocabulary. See docs/schema.md.
  p_pass_basis: S.optionalKey(S.String),
  p_pass_tonight: S.optionalKey(Probability),
  p_pass_first_night: S.optionalKey(Probability),
  difficulty: S.optionalKey(Difficulty),
  difficulty_basis: S.optionalKey(S.String),
  predicted_opus_tokens: S.optionalKey(Tokens),
  token_basis: S.optionalKey(S.String),
  // U-A17: the four cells §2.3's receipt `prior{…}` needs that README §5 does
  // not name, so that a receipt's prior is COPIED from the card that was locked
  // before the run and never re-derived after it (§3, "pull 0"; R-09 / H-14
  // "locked by a commit before the run"). Each is optional here because the 173
  // cards on disk predate them; the evaluator refuses by name when a card it is
  // asked to evaluate omits one, rather than inventing a default.
  //   difficulty_scale       D-B9: the scale is 1-5 and "the scoping node states
  //                          `difficulty_scale`" — so it is stated, not assumed.
  //   predicted_tokens_cell  D-B19: "`predicted_tokens_cell: out` on every prior
  //                          written from now"; the 89 card-text priors stay
  //                          `unruled`, which is why the word is in the union.
  //   prior_source           §2.3's `prior_source ∈ {card-text, scoping-node, band}`.
  //   prior_executor         §2.3's cell: the arm the prior was written FOR.
  difficulty_scale: S.optionalKey(S.String.check(S.isMinLength(1))),
  predicted_tokens_cell: S.optionalKey(PredictedTokensCell),
  prior_source: S.optionalKey(PriorSource),
  prior_executor: S.optionalKey(S.String.check(S.isMinLength(1)))
})
assertNoWallclockField("Card.CardPrior", fieldsOf(CardPrior))

/** README §5 `result`. `grade` is README's three words; prose there is a gap. */
export const CardResult = S.Struct({
  observed: S.NullOr(S.Union([S.String, S.Number])),
  sample_actual: S.NullOr(S.Union([S.String, S.Number])),
  receipt_path: S.NullOr(S.String),
  receipt_sha256: S.NullOr(S.String),
  grade: S.NullOr(Grade),
  outcome: S.NullOr(S.String),
  action_taken: S.NullOr(S.String),
  // MEASURED: per-card hashes a session banked beside the four README fields.
  oracle_report: S.optionalKey(S.String),
  index_sha256: S.optionalKey(S.String),
  cards_sha256: S.optionalKey(S.String),
  receipt_round1_sha256: S.optionalKey(S.String),
  actuals_tokens: S.optionalKey(Tokens)
})
assertNoWallclockField("Card.CardResult", fieldsOf(CardResult))

/** README §5 `posterior`, BARG order in the body. */
export const Posterior = S.Struct({
  p_pass: S.NullOr(Probability),
  learning: S.NullOr(S.String),
  spec_shrunk: S.NullOr(S.String),
  next: S.NullOr(S.String)
})
assertNoWallclockField("Card.Posterior", fieldsOf(Posterior))

/** README §5 `supervisory`. */
export const Supervisory = S.Struct({
  wip_max: S.Number,
  interventions: S.Array(S.Unknown)
})
assertNoWallclockField("Card.Supervisory", fieldsOf(Supervisory))

/**
 * README §5 `arm`, whose comment reads
 * `# {model, quant, ctx, harness, density, patch} for bench cards`.
 * MEASURED extensions: seat, executors, workflow, wip.
 *
 * The struct is closed, and that is what catches cards/REPORT-KIT.md:14 — an
 * unquoted plain scalar with a comma inside a flow mapping, which YAML splits
 * into a key that was meant to be prose.
 */
export const Arm = S.Struct({
  model: S.optionalKey(S.String),
  quant: S.optionalKey(S.String),
  ctx: S.optionalKey(S.String),
  harness: S.optionalKey(S.String),
  density: S.optionalKey(S.String),
  patch: S.optionalKey(S.String),
  seat: S.optionalKey(S.String),
  executors: S.optionalKey(S.Union([S.String, S.Number])),
  workflow: S.optionalKey(S.String),
  wip: S.optionalKey(S.Number)
})
assertNoWallclockField("Card.Arm", fieldsOf(Arm))

/** MEASURED, 7 cards: how the card could pass by nothing, and what stops it. */
export const VacuousRisk = S.Struct({
  how_it_could_pass_by_nothing: S.String,
  preventing_assertion: S.String
})
assertNoWallclockField("Card.VacuousRisk", fieldsOf(VacuousRisk))

/**
 * §2.2a's `mutation_hint`, in the two runnable forms §2.2d fixes:
 *
 *   "then the mutation step by `kind`: for `kind: build`, apply the card's
 *    **required** `mutation_hint` (an argv or a `git apply` patch), run, record
 *    rc (must be non-zero), revert"
 *
 * `kind: argv` carries a command that changes the fresh worktree before the
 * oracle is re-run; `kind: patch` carries the `git apply` bytes directly. The
 * evaluator captures and reverses the resulting diff after the RED run.
 *
 * A bare string also decodes, because that is what the 89 rungs on disk carry
 * and what `UNITS-2026-09-06.json` writes ("skip the mutation step → the
 * receipt's mutation.rc is 0 → non-zero"). Prose is a hint for a human and is
 * not runnable: the evaluator refuses it BY NAME as `no-mutation-hint` rather
 * than choosing a mutation for it (§6.3 D6). The type admits the sentence; the
 * evaluator does not admit it as a mutation.
 */
const NonEmpty = S.String.check(S.isMinLength(1))

export const MutationHintSpec = S.Union([
  S.Struct({ kind: S.Literal("argv"), description: NonEmpty, argv: NonEmpty }),
  S.Struct({ kind: S.Literal("patch"), description: NonEmpty, patch: NonEmpty })
])

export const MutationHint = S.Union([S.String, MutationHintSpec])

/** The card. */
export const Card = S.Struct({
  // README §5, in README's own order
  id: Id,
  title: S.String,
  status: Status,
  class: CardClass,
  created: CalendarDate,
  armed_at: S.NullOr(S.String),
  armed_commit: S.NullOr(S.String),
  depends_on: S.Array(S.String),
  data_already_collected: S.Union([S.Boolean, S.Literal("partial")]),
  problem: S.String,
  theory: S.String,
  hypotheses: S.Array(Hypothesis),
  signal: Signal,
  decision_rule: DecisionRule,
  prior: CardPrior,
  arm: S.NullOr(Arm),
  result: CardResult,
  posterior: Posterior,
  supervisory: Supervisory,
  // PROMPTS.md header, line 6: "plus difficulty, predicted_tokens,
  // use_case_class, arm". `arm` is already README's.
  difficulty: S.optionalKey(Difficulty),
  predicted_tokens: S.optionalKey(Tokens),
  use_case_class: S.String,
  // MEASURED on disk; named by neither source
  seat: S.optionalKey(S.String),
  vacuous_risk: S.optionalKey(VacuousRisk),
  // §2.2a's ladder fields, added by U-A17 LAKE-EVALUATOR. §2.2a, verbatim:
  // "`Card` (README §5 front matter: … + ladder fields `use_case_class,
  // executor, oracle, actuals, repo, mutation_hint, prior_lock_commit` minus
  // `predicted_wallclock`)". U-A8 shipped `use_case_class` (the corpus carries
  // it) and left the other six for the unit that needs them; the evaluator is
  // that unit — it reads the card's `oracle.argv`, its `mutation_hint` and its
  // `prior_lock_commit` and can invent none of the three.
  //
  // Every one is `optionalKey`, so the 173 front matters already on disk decode
  // exactly as before (`tools/decode-estate.mjs` over cards/, unchanged), and so
  // that a card which omits one is REFUSED BY NAME by the evaluator rather than
  // quietly defaulted. `oracle` and `actuals` are the rung's own structs: a card
  // and a rung state an oracle in one grammar or the register has two.
  repo: S.optionalKey(S.String.check(S.isMinLength(1))),
  executor: S.optionalKey(S.String.check(S.isMinLength(1))),
  oracle: S.optionalKey(Oracle),
  actuals: S.optionalKey(Actuals),
  mutation_hint: S.optionalKey(MutationHint),
  prior_lock_commit: S.optionalKey(S.String.check(S.isPattern(/^[0-9a-f]{7,40}$/)))
})
assertNoWallclockField("Card", fieldsOf(Card))

export type Card = typeof Card.Type
