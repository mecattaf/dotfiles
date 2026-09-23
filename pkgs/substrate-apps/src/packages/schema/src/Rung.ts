/**
 * Rung.ts — U-A8 LAKE-SCHEMA. The `rung` of {receipt, rung, card}.
 *
 * Source of the field set:
 *
 *   1. The header of /home/tom/research-methods/PROMPTS.md, line 6 — "rungs at
 *      /home/tom/research-methods/cards/ladder/<id>.md; shenanigans at
 *      /home/tom/research-methods/cards/SH/SH-nn.md" — read with line 2, "every
 *      build unit is a rung with a prior before and actuals after", and the
 *      card fields of line 6 ("difficulty, predicted_tokens, use_case_class,
 *      arm"), which sit inside `prior` on a rung.
 *   2. README.md §5 for everything a rung shares with a card: id, title,
 *      status, class, created, armed_at, armed_commit, depends_on, grade.
 *   3. MEASURED on disk 2026-09-06: the shape is exact and uniform — 86 of 86
 *      rungs under cards/ladder/ carry the same 22 keys plus at most three of
 *      {seat, sh_cards_met, requirements_met}, and 70 of 70 shenanigans under
 *      cards/SH/ carry the same 16.
 *
 * NOT in the field set: `predicted_wallclock`. The intake draft
 * intake/plan-B-product-first.md:7 put it in the rung's front matter next to
 * `predicted_tokens`; R-2026-09-05-16 struck it, PROMPTS.md's header carries
 * the shortened list, and this type carries the shortened list too. Decoding is
 * closed, so a rung that carries it is REJECTED.
 *
 * `actuals.seconds` stays: "Measured seconds on a receipt are outcomes and
 * stay" (R-2026-09-05-16, operator reading). A prediction goes; a measurement
 * does not.
 */
import * as S from "effect/Schema"
import {
  assertNoWallclockField,
  Basis,
  BasisLine,
  CalendarDate,
  CardClass,
  Difficulty,
  fieldsOf,
  Grade,
  Id,
  Probability,
  Rul01Ref,
  SourceRef,
  Status,
  Tokens
} from "./Common.ts"

/**
 * The prior R-09 requires before a rung runs. MEASURED: all seven keys on
 * 86 of 86 rungs.
 */
export const RungPrior = S.Struct({
  difficulty: Difficulty,
  difficulty_basis: S.String,
  p_pass: Probability,
  p_pass_basis: Basis,
  p_pass_reason: S.String,
  predicted_tokens: Tokens,
  tokens_basis: S.String
})
assertNoWallclockField("Rung.RungPrior", fieldsOf(RungPrior))

/**
 * The oracle. `marker` is the dispatch lock: `NO-ORACLE` bars dispatch by
 * construction (card T-LAKE carries it today). The four marker words are
 * MEASURED — the in-file comment names three and the corpus carries a fourth,
 * `NEEDS-BENCH`, 11 times.
 */
export const Oracle = S.Struct({
  marker: S.Literals(["mechanical", "NO-ORACLE", "HUMAN-ATTENDED", "NEEDS-BENCH"]),
  kind: S.String,
  argv: S.String,
  proposed: S.Boolean,
  source: S.String,
  dispatch: S.String,
  reopen_condition: S.optionalKey(S.String)
})
assertNoWallclockField("Rung.Oracle", fieldsOf(Oracle))

/**
 * What the run actually cost and did. Written after the run; null before it.
 * `seconds` is a measurement, not a prediction (R-2026-09-05-16).
 */
export const Actuals = S.Struct({
  tokens: S.NullOr(Tokens),
  seconds: S.NullOr(S.Number),
  outcome: S.NullOr(S.String),
  receipt_sha256: S.NullOr(S.String),
  prior_gap: S.NullOr(S.Union([S.String, S.Number]))
})
assertNoWallclockField("Rung.Actuals", fieldsOf(Actuals))

/** A ladder rung. */
export const Rung = S.Struct({
  id: Id,
  title: S.String,
  status: Status,
  class: CardClass,
  use_case_class: S.String,
  tenant: S.String,
  t_type: S.String,
  created: CalendarDate,
  drafted_by: S.String,
  armed_at: S.NullOr(S.String),
  armed_commit: S.NullOr(S.String),
  depends_on: S.Array(S.String),
  executor: S.String,
  prior: RungPrior,
  oracle: Oracle,
  replicable: S.Literals(["yes", "no", "partly"]),
  receipt: S.String,
  rul01_consulted: S.Array(Rul01Ref),
  default_unruled: S.Array(S.String),
  grade: S.NullOr(Grade),
  sources: S.Array(SourceRef),
  actuals: Actuals,
  // MEASURED: carried by some rungs and not others.
  seat: S.optionalKey(S.String),
  sh_cards_met: S.optionalKey(S.Array(S.String)),
  requirements_met: S.optionalKey(S.Array(S.String))
})
assertNoWallclockField("Rung", fieldsOf(Rung))

export type Rung = typeof Rung.Type

/**
 * The detector that makes a shenanigan a rung rather than prose — P04's
 * charter, quoted from cards/SH/SH-01.md:5:
 * "a cloudflare-os trap as a rung with a detector, not prose (P04 charter)".
 */
export const Detector = S.Struct({
  marker: S.Literals(["mechanical", "NO-ORACLE", "HUMAN-ATTENDED", "NEEDS-BENCH"]),
  argv: S.String,
  runs_against: S.String,
  proposed: S.Boolean
})
assertNoWallclockField("Rung.Detector", fieldsOf(Detector))

/**
 * A shenanigan: a rung whose prior is a re-run probability and whose oracle is
 * a detector. MEASURED: 70 of 70 files under cards/SH/ carry exactly these
 * sixteen keys.
 */
export const Shenanigan = S.Struct({
  id: Id,
  title: S.String,
  status: Status,
  class: CardClass,
  created: CalendarDate,
  drafted_by: S.String,
  discovered_in: S.Array(S.String),
  detector: Detector,
  tenants_affected: S.Array(S.String),
  first_unit: S.String,
  rerun_prior: Probability,
  rerun_prior_basis: BasisLine,
  grade: S.NullOr(Grade),
  sources: S.Array(SourceRef),
  receipt: S.String,
  met_by: S.Array(S.String)
})
assertNoWallclockField("Rung.Shenanigan", fieldsOf(Shenanigan))

export type Shenanigan = typeof Shenanigan.Type
