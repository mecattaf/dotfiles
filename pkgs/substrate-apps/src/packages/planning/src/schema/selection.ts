/**
 * The selector's two tables, as types the lake decodes and never authors.
 *
 * `register bands` (U-E6) writes `cards/bands.tsv`: one Beta posterior per
 * `(use_case_class x arm)` cell, `Beta(2 + passes, 2 + fails)`. `register next`
 * writes `cards/selection-<pass>.tsv`: one row per rung of the E1 sample, each
 * carrying the band it was priced against, the pass's Thompson draw from pass 2,
 * and the rank the selector put it in.
 *
 * The lake reads both and chooses nothing (spec §4.4 rule 5, §2.8). That is the
 * unit's non-goal stated as a type: there is no comparator here, no sort, no
 * draw and no random source. `rank` and `thompsonDraw` are carried through as
 * data and are read by no rule in this package; the ordering that ranks a
 * release is the release evaluator's own lexicographic hierarchy and value
 * density, over estimates the selector supplied.
 *
 * The pseudo-count is four and not two, and that is a joint decision with the
 * register rather than a coincidence: `register`'s `BANDS_PSEUDO_COUNT` is
 * `2 + 2` precisely so that
 *
 *   (2 + s) / (n + 4) = n/(n+4) * (s/n) + 4/(n+4) * 1/2
 *
 * is the shrinkage the estimate table's `shrinkageWeight` column carries with
 * `priorStrength = 4`. A Jeffreys or uniform prior on the register's side
 * would make the band's mean and the lake's weight disagree (D-U-E6-1).
 */
import { Schema } from "effect";
import { ClassName, UnitInterval, Weight } from "./ids.ts";

/**
 * The equal-trust observation count the register and the lake share.
 *
 * `shrinkageWeight = n / (n + 4)`. It is exported because it is a contract with
 * another repository and not an internal constant: if the register repins its
 * prior, this number moves with it or the two disagree silently.
 */
export const SELECTOR_PSEUDO_COUNT = 4;

/**
 * The prior a band-sourced row was priced against, by name.
 *
 * `band` means the `(class x arm)` cell had a posterior of its own. `prior`
 * means it did not and the register's `Beta(2,2)` stood in — the case the
 * selection file marks by name rather than by an indistinguishable 0.5.
 */
const PriorSource = Schema.Literals(["band", "prior"]);
/** Whether a row's prior came from a band or from the standing `Beta(2,2)`. */
type PriorSource = typeof PriorSource.Type;

/**
 * The Thompson draw's parameters, as the selection file records them.
 *
 * The seed is a **decimal string** and not a number. `register`'s seed is the
 * first eight bytes of `sha256("<pass>\t<class>\t<arm>\t<rung>")` read as a
 * big-endian unsigned integer, so it ranges over the full 64 bits and the
 * measured fixture carries `17696085320377123006` — larger than
 * `Number.MAX_SAFE_INTEGER`. Decoded as a number it would round, and a seed that
 * rounds is not a seed: the draw would not be reproducible from the receipt
 * (D-U-A24-1).
 *
 * `alpha` and `beta` are the posterior the draw was taken from, so the draw is
 * re-derivable from the three fields together. The realised value is on the
 * selection row and is deliberately not part of the stamp: a receipt that
 * carried the number without its parameters could not be checked (§6.2 B11).
 */
const ThompsonDraw = Schema.Struct({
  /** The per-draw seed, as decimal digits; never a JavaScript number. */
  seed: Schema.String.pipe(Schema.check(Schema.isPattern(/^[0-9]+$/))),
  /** The posterior's alpha, `2 + passes`. */
  alpha: Schema.Finite,
  /** The posterior's beta, `2 + fails`. */
  beta: Schema.Finite
});
/** The Thompson draw's parameters, `{seed, alpha, beta}`. */
type ThompsonDraw = typeof ThompsonDraw.Type;

/**
 * What a release stamps about the prior it was released under.
 *
 * The field names are the spec's and the register's, in snake case, because they
 * cross to a receipt and a receipt's key order is a wire fact: `prior_source`
 * and `thompson` are read back by the evaluator's ingestion (§2.2d) and by
 * `register calibrate`, which scores Brier per `(prior_source x arm)`. Renaming
 * them here to match the package's camel case would break that join at the one
 * place B11 says it must hold.
 */
export const PriorStamp = Schema.Struct({
  /** Where this item's prior came from. */
  prior_source: PriorSource,
  /**
   * The draw's parameters, present exactly when the selection pass drew.
   *
   * Absent on a pass-1 row: pass 1 orders by measured cost and draws nothing,
   * so a `thompson` block there would be a fabrication.
   */
  thompson: Schema.optionalKey(ThompsonDraw)
});
/** The prior stamp a release carries, `{prior_source, thompson{seed, alpha, beta}}`. */
export type PriorStamp = typeof PriorStamp.Type;

/** One `(use_case_class x arm)` cell of `cards/bands.tsv`. */
export const Band = Schema.Struct({
  /** The use-case class axis. */
  useCaseClass: ClassName,
  /** The joined arm, `<seat>/<harness>/<model>`, as U-E5 writes it. */
  arm: Schema.String,
  /** Attempts behind the cell. */
  n: Schema.Int,
  /** Distinct rungs behind those attempts (spec §4.1). */
  m: Schema.Int,
  /** Attempts that closed `pass`. */
  passes: Schema.Int,
  /** Attempts that closed `fail`. */
  fails: Schema.Int,
  /** The posterior's alpha, `2 + passes`. */
  alpha: Schema.Finite,
  /** The posterior's beta, `2 + fails`. */
  beta: Schema.Finite,
  /** The posterior mean, `alpha / (alpha + beta)`. This is the yield rate. */
  mean: UnitInterval,
  /** The band's 5th percentile over the register's 20000 draws. */
  p05: UnitInterval,
  /** The band's 95th percentile. */
  p95: UnitInterval,
  /** `n / (n + 4)`, recomputed by the lake and checked against this column. */
  shrinkageWeight: UnitInterval
});
/** One `(use_case_class x arm)` cell of the register's band table. */
export type Band = typeof Band.Type;

/** One row of `cards/selection-<pass>.tsv`. */
export const SelectionRow = Schema.Struct({
  /**
   * The selector's rank, or `None` for a row contamination held back.
   *
   * Carried and never read. Nothing in this package sorts on it.
   */
  rank: Schema.OptionFromNullOr(Schema.Int),
  /** The rung id, which is the task id the acceptor armed. */
  rung: Schema.String,
  /** The repository the rung's commit lives in. */
  repo: Schema.String,
  /** The use-case class, or `None` when the register found no class to invent. */
  useCaseClass: Schema.OptionFromNullOr(ClassName),
  /** The arm this selection pass is for. */
  arm: Schema.String,
  /** Which attempt this would be, counting from zero. */
  attempt: Schema.Int,
  /** Whether contamination admits the rung; a held row stays in the table by name. */
  admitted: Schema.Boolean,
  /** The sample's own order of record. */
  precedence: Schema.Int,
  /** The measured frontier out-token cost, `None` where none was measured. */
  costFrontierOut: Schema.OptionFromNullOr(Schema.Finite),
  /** The row's yield rate: the band's mean, or the standing prior's 0.5. */
  yieldRate: UnitInterval,
  /** The class's p80 measured consumption, `None` where the class has no costs. */
  p80Consumption: Schema.OptionFromNullOr(Weight),
  /** The row's stated `n / (n + 4)`; the lake recomputes and compares. */
  shrinkageWeight: UnitInterval,
  /** Attempts behind the row's cell. */
  n: Schema.Int,
  /** Distinct rungs behind them. */
  m: Schema.Int,
  /** The posterior's alpha. */
  alpha: Schema.Finite,
  /** The posterior's beta. */
  beta: Schema.Finite,
  /** Where the prior came from. */
  priorSource: PriorSource,
  /** The draw's parameters, absent on pass 1 and on a held row. */
  thompson: Schema.OptionFromNullOr(ThompsonDraw),
  /**
   * The realised draw, `None` where none was taken.
   *
   * Carried and never read. This is the number a selector would sort on, and
   * the fence that keeps selection out of the lake is that no rule here does.
   */
  thompsonDraw: Schema.OptionFromNullOr(UnitInterval),
  /** Why the rung is admitted or held, in the register's words. */
  reason: Schema.String,
  /** The register's note about the cell, in the register's words. */
  selectionNote: Schema.String
});
/** One row of the register's selection table. */
export type SelectionRow = typeof SelectionRow.Type;

/** A decoded `cards/selection-<pass>.tsv`, with the header facts it declares. */
export const SelectionTable = Schema.Struct({
  /** The pass number, from the file's own `# pass:` line. */
  pass: Schema.Int,
  /** The arm the pass is for, from the file's own `# arm:` line. */
  arm: Schema.String,
  /** The rows, in file order. File order is not an ordering this package uses. */
  rows: Schema.Array(SelectionRow)
});
/** A decoded selection table. */
export type SelectionTable = typeof SelectionTable.Type;
