/**
 * Iso8601.ts — U-A12 LAKE-SERIALIZER. Timestamp normalisation to ISO-8601 UTC.
 *
 * One of the serializer's four properties (§2.2e: "stable key order, LF,
 * trailing newline, ISO-8601 UTC"). It is the only one that changes the *value*
 * of a field rather than the shape of the output, so it is written here on its
 * own, with the rule stated before the code.
 *
 * THE RULE, in full:
 *
 *   A string is normalised **only** when the whole string is an ISO-8601
 *   calendar date-time that carries an explicit zone — `Z` or `±HH:MM` /
 *   `±HHMM`. Nothing else is touched, byte for byte:
 *
 *     - a string that merely *contains* a timestamp (the corpus's `diagnosis`
 *       fields are prose with embedded JSON) is prose, and prose is data;
 *     - a date-time with **no zone** is not an instant. Reading it as UTC would
 *       invent a fact about a clock nobody recorded, so it is left as written
 *       (docs/serializer.md records this as a default, unruled);
 *     - a string that has the shape but not the calendar — `2026-13-45T…`,
 *       `…T25:00:00Z`, a `:60` leap second — is not a date either, and is left
 *       as written rather than silently repaired.
 *
 *   A normalised timestamp is emitted as
 *
 *     YYYY-MM-DDTHH:MM:SS.fffZ
 *
 *   with the wall-clock shifted by the written offset so the zone is always
 *   `Z`, and `fff` the original fractional digits with trailing zeros removed
 *   but never below three. Nothing is rounded away: `.888` stays `.888`,
 *   `.123456` stays `.123456`, `.5` becomes `.500`, `.8880` becomes `.888`, and
 *   a timestamp with no fraction gains `.000`. Truncating to milliseconds would
 *   drop digits the corpus actually carries, and the lake is a mirror.
 *
 * The rule is total (every string maps to exactly one string), pure (no clock,
 * no locale, no ambient time zone is read) and **idempotent** — normalising a
 * normalised timestamp returns it unchanged. Idempotence is what lets the
 * projection be re-run over its own output, and it is asserted by the suite.
 *
 * MEASURED over both input trees, 2026-09-06, by this unit, at the reading where
 * they together held 127 .jsonl files and 37,276 rows (the register grows, so
 * this is a reading at a moment and not a pin; docs/serializer.md §4):
 *
 *   59132  "NNNN-NN-NNTNN:NN:NN.NNNZ"             already UTC, millisecond
 *    7472  "NNNN-NN-NNTNN:NN:NN+NN:NN"            an offset, no fraction
 *     114  "NNNN-NN-NNTNN:NN:NN.NNNNNN+NN:NN"     an offset, microsecond
 *      15  "NNNN-NN-NNTNN:NN:NN.NNNNNNNNN+NN:NN"  an offset, NANOSECOND
 *       4  "NNNN-NN-NNTNN:NN:NNZ"                 already UTC, no fraction
 *       0  zone-less
 *
 * so 7601 of 66737 timestamps are moved by this file. The normalisation is not
 * decoration on this corpus — and those fifteen nanosecond timestamps are why
 * the fraction rule truncates nothing: rounding them to milliseconds would drop
 * six digits of a recorded instant.
 */

/**
 * The shape. Anchored at both ends: a partial match is prose, not a timestamp.
 * The zone group is optional here so that a zone-less date-time can be
 * recognised and then *declined* with a named reason, rather than falling
 * through as "did not look like a date".
 */
const ISO_8601 =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|z|[+-]\d{2}:?\d{2})?$/

/** Days in each month of a non-leap year, indexed 1..12. */
const MONTH_DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

const isLeapYear = (y: number): boolean => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0

const daysInMonth = (y: number, m: number): number =>
  m === 2 && isLeapYear(y) ? 29 : (MONTH_DAYS[m] ?? 0)

/** Two digits, zero padded. */
const p2 = (n: number): string => (n < 10 ? `0${n}` : `${n}`)

/** Four digits, zero padded. Years outside 0000..9999 cannot occur here: the
 * pattern admits exactly four digits. */
const p4 = (n: number): string => `${n}`.padStart(4, "0")

/**
 * The fractional part, canonicalised: trailing zeros removed, then padded back
 * to at least three digits. Total, and idempotent by construction.
 */
export const canonicalFraction = (digits: string | undefined): string => {
  if (digits === undefined || digits === "") return "000"
  let end = digits.length
  while (end > 3 && digits[end - 1] === "0") end--
  const kept = digits.slice(0, end)
  return kept.length >= 3 ? kept : kept.padEnd(3, "0")
}

/**
 * Why a string was not normalised, or `null` when it was. Returned alongside
 * the result so the tool can report a declined string by reason instead of
 * silently passing it through — a silent pass-through is how a normalisation
 * step stops being one.
 */
type Decline =
  | "not-a-date-time"
  | "no-zone"
  | "not-a-calendar-date"

interface Normalised {
  readonly value: string
  readonly declined: Decline | null
}

/**
 * Normalise one string. See the rule at the head of this file.
 *
 * The arithmetic runs through `Date.UTC` and the `getUTC*` readers only, which
 * are defined in terms of the UTC calendar and read no ambient zone. The
 * two-digit-year trap of `Date.UTC` (`Date.UTC(50, 0)` means 1950) is closed by
 * setting the year explicitly afterwards.
 */
export const normaliseIso8601 = (s: string): Normalised => {
  const m = ISO_8601.exec(s)
  if (m === null) return { value: s, declined: "not-a-date-time" }

  const [, ys, mos, ds, hs, mis, ses, frac, zone] = m
  if (zone === undefined) return { value: s, declined: "no-zone" }

  const y = Number(ys)
  const mo = Number(mos)
  const d = Number(ds)
  const h = Number(hs)
  const mi = Number(mis)
  const se = Number(ses)

  if (mo < 1 || mo > 12) return { value: s, declined: "not-a-calendar-date" }
  if (d < 1 || d > daysInMonth(y, mo)) return { value: s, declined: "not-a-calendar-date" }
  // 24:00:00 is a legal ISO-8601 end-of-day, and :60 is a legal leap second.
  // Neither appears in this estate and neither round-trips through Date.UTC
  // without inventing a repair, so both are declined by name.
  if (h > 23 || mi > 59 || se > 59) return { value: s, declined: "not-a-calendar-date" }

  let offsetMinutes = 0
  if (zone !== "Z" && zone !== "z") {
    const sign = zone[0] === "-" ? -1 : 1
    const body = zone.slice(1).replace(":", "")
    const oh = Number(body.slice(0, 2))
    const om = Number(body.slice(2, 4))
    if (oh > 23 || om > 59) return { value: s, declined: "not-a-calendar-date" }
    offsetMinutes = sign * (oh * 60 + om)
  }

  const at = new Date(Date.UTC(2000, mo - 1, d, h, mi, se))
  at.setUTCFullYear(y)
  at.setUTCMinutes(at.getUTCMinutes() - offsetMinutes)

  const value =
    `${p4(at.getUTCFullYear())}-${p2(at.getUTCMonth() + 1)}-${p2(at.getUTCDate())}` +
    `T${p2(at.getUTCHours())}:${p2(at.getUTCMinutes())}:${p2(at.getUTCSeconds())}` +
    `.${canonicalFraction(frac)}Z`

  return { value, declined: null }
}

/** The rule as a plain string→string function. */
export const normaliseTimestamps = (s: string): string => normaliseIso8601(s).value

/**
 * True when a string is an ISO-8601 date-time carrying a zone that is NOT `Z` —
 * i.e. a timestamp the normalisation is supposed to have moved. The fixture
 * tool asserts this is false of every string it emits, so "normalised to UTC"
 * is a measurement over the output and not a claim about the code.
 */
export const carriesNonUtcZone = (s: string): boolean => {
  const m = ISO_8601.exec(s)
  if (m === null) return false
  const zone = m[8]
  return zone !== undefined && zone !== "Z" && zone !== "z"
}
