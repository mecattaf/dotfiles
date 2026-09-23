/**
 * Common.ts — U-A8 LAKE-SCHEMA. The vocabularies the register shares.
 *
 * Two grades run through this file, and every literal union below says which it
 * is:
 *
 *   SOURCED  the vocabulary is written in a source this unit takes as its
 *            authority: /home/tom/research-methods/README.md §5, the header of
 *            /home/tom/research-methods/PROMPTS.md, or
 *            /home/tom/research-methods/RAWA-FLOW.md §5.
 *   MEASURED the vocabulary is not in those sources; it is what the corpus on
 *            disk carries, counted on 2026-09-06 by this unit.
 *
 * A vocabulary that no source enumerates and that the corpus does not close is
 * left as `String`. Inventing a closed list would be ruling, and states are
 * Tom's (R-2026-09-05-03).
 *
 * Enumerating a status word is not writing one. No file in this repository sets
 * a card's status, and this unit changed none (CONTRIBUTING.md §2 rule 3).
 */
import * as S from "effect/Schema"

// --- R-16, in the type -------------------------------------------------------

/**
 * The field names R-2026-09-05-16 removes. Tom, 2026-09-05 evening, verbatim:
 *
 *   "one thing to make clear: No WALL CLOCK EXTIMATES WHATSOEVER. the
 *    implementation time in not the purpose of this doc. we are simply listing
 *    all the worb that must be done"
 *
 * The ruling's operator reading strikes `predicted_wallclock` from the rung
 * fields (PROMPTS.md's header already carries the shorter list; the field
 * survives only in the superseded intake draft,
 * /home/tom/research-methods/intake/plan-B-product-first.md:7). This unit takes
 * it out of the TYPE and not only the prose: every struct below is decoded with
 * `onExcessProperty: "error"`, so a card carrying one of these names does not
 * decode. Measured seconds on a receipt are outcomes and stay — `seconds` and
 * `finished_at` are receipt fields, not predictions.
 */
export const WALLCLOCK_FIELDS: ReadonlyArray<string> = [
  "predicted_wallclock",
  "predicted_wall_clock",
  "predicted_wallclock_seconds",
  "wallclock",
  "wall_clock",
  "expected_wallclock",
  "estimated_wallclock",
  "eta"
]

/**
 * Assert at module load that a declared field set carries no wall-clock field.
 * Called once per struct below, so the guard cannot drift away from the types
 * it guards: adding such a field to a schema throws on import, before any
 * corpus is read.
 */
export const assertNoWallclockField = (where: string, fields: ReadonlyArray<string>): void => {
  for (const f of fields) {
    if (WALLCLOCK_FIELDS.includes(f)) {
      throw new Error(`${where}: field '${f}' is struck by R-2026-09-05-16 and may not appear in the type`)
    }
  }
}

/** The declared keys of a struct schema, for `assertNoWallclockField`. */
export const fieldsOf = (struct: { readonly fields: Record<string, unknown> }): ReadonlyArray<string> =>
  Object.keys(struct.fields)

// --- scalars -----------------------------------------------------------------

/** A non-empty identifier, e.g. `T-LAKE`, `SH-01`, `drv-workerd`. */
export const Id = S.String.check(S.isMinLength(1))

/** `YYYY-MM-DD`. README §5's `created` is written this way in 170 of 170 cards. */
export const CalendarDate = S.String.check(S.isPattern(/^\d{4}-\d{2}-\d{2}$/))

/** 64 lowercase hex characters. */
export const Sha256 = S.String.check(S.isPattern(/^[0-9a-f]{64}$/))

/** A sha256 with or without the `sha256:` prefix the ledgers use. */
export const Sha256Ref = S.String.check(S.isPattern(/^(?:sha256:)?[0-9a-f]{64}$/))

/** ISO-8601 with an offset or `Z`. The serializer's clock format (P17 signal line). */
export const Iso8601 = S.String.check(
  S.isPattern(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})$/)
)

/** A probability. */
export const Probability = S.Number.check(S.isBetween({ minimum: 0, maximum: 1 }))

/** A count of tokens. Predicted tokens are a usage quantity and stay (R-16). */
export const Tokens = S.Int.check(S.isGreaterThanOrEqualTo(0))

/**
 * SOURCED (PROMPTS.md header, "difficulty"; PATH.md and plan-B write the range
 * as 1–5) with one MEASURED exception: cards/L6-EFFECT.md carries `low`. No
 * other word appears, so no other word is admitted.
 */
export const Difficulty = S.Union([S.Int.check(S.isBetween({ minimum: 1, maximum: 5 })), S.Literal("low")])

/**
 * SOURCED, README §5 verbatim:
 *   `status: DRAFT  # DRAFT → ARMED → RUNNING → KEEP | DISCARD | VACUOUS | CRASH | PARKED`
 * MEASURED on disk: DRAFT 157, ARMED 9, VACUOUS 2, RUNNING 1, PARKED 1.
 */
export const Status = S.Literals(["DRAFT", "ARMED", "RUNNING", "KEEP", "DISCARD", "VACUOUS", "CRASH", "PARKED"])

/**
 * SOURCED, README §5 verbatim: `grade: null  # MEASURED | CLAIMED | UNKNOWN`.
 * MEASURED on disk: MEASURED 129, CLAIMED 35, null 2, plus one card whose
 * grade field carries prose instead of a word — that one is a gap, by design.
 */
export const Grade = S.Literals(["MEASURED", "CLAIMED", "UNKNOWN"])

/**
 * SOURCED, README §5 verbatim: `basis: flat  # flat | history | text`.
 */
export const Basis = S.Literals(["flat", "history", "text"])

/**
 * P04's rung fields write the basis as the word followed by its reasoning
 * ("text — the blanket sweep is the nixpkgs-default idiom …"). The word is
 * SOURCED; the trailing prose is MEASURED. The check keeps the vocabulary
 * binding without throwing the reasoning away.
 */
export const BasisLine = S.String.check(
  S.makeFilter((s: string) =>
    /^(flat|history|text)\b/.test(s) ? undefined : "must open with one of README §5's three bases: flat, history, text"
  )
)

/**
 * SOURCED, RAWA-FLOW.md §5 verbatim: `disposition KEEP|DISCARD|CRASH`.
 * A receipt's disposition is a record of what a run did; it is not a card
 * state, and nothing here writes one (R-2026-09-05-03).
 */
export const Disposition = S.Literals(["KEEP", "DISCARD", "CRASH"])

/**
 * SOURCED, README §5 verbatim:
 *   `class:  # controllability | calibration | seam | feasibility | saturation | ladder | routing | filler | product`
 * MEASURED extensions the register has since grown, with counts taken
 * 2026-09-06: `shenanigan` 70 (cards/SH/), `literature-synthesis` 3,
 * `benchmark-harness` 1.
 */
export const CardClass = S.Literals([
  // README §5, in its own order
  "controllability",
  "calibration",
  "seam",
  "feasibility",
  "saturation",
  "ladder",
  "routing",
  "filler",
  "product",
  // MEASURED on disk, not in README §5
  "shenanigan",
  "literature-synthesis",
  "benchmark-harness"
])

/**
 * A `{path, locator}` row. MEASURED shape: every `sources` entry of every rung
 * and shenanigan card, 156 of 156.
 */
export const SourceRef = S.Struct({
  path: S.String,
  locator: S.optionalKey(S.String)
})

/** A `{id, statement}` row. README §5's `hypotheses` list. */
export const Hypothesis = S.Struct({
  id: S.String,
  statement: S.String
})

/** A `{line, how}` row of a rung's `rul01_consulted` list. MEASURED, P04's field. */
export const Rul01Ref = S.Struct({
  line: S.String,
  how: S.String
})
