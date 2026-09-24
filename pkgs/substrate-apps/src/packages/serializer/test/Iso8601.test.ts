/**
 * Iso8601.test.ts — U-A12. Property 4: every timestamp normalised to ISO-8601 UTC.
 *
 * The three shapes asserted against the corpus are the three MEASURED on the two
 * input trees on 2026-09-06 (`src/Iso8601.ts` header): `…Z` with milliseconds,
 * `+HH:MM` with no fraction, and `+HH:MM` with microseconds.
 */
import fc from "fast-check"
import { describe, expect, it } from "vitest"
import { canonicalFraction, carriesNonUtcZone, normaliseIso8601, normaliseTimestamps } from "../src/index.ts"

describe("normaliseIso8601 — the three shapes the corpus carries", () => {
  it("leaves an already-UTC millisecond timestamp alone", () => {
    const r = normaliseIso8601("2026-08-29T07:09:49.888Z")
    expect(r.declined).toBe(null)
    expect(r.value).toBe("2026-08-29T07:09:49.888Z")
  })

  it("moves a positive offset back to UTC and gains .000", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00+02:00")).toBe("2026-09-01T10:00:00.000Z")
  })

  it("moves a negative offset forward to UTC", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00-05:00")).toBe("2026-09-01T17:00:00.000Z")
  })

  it("keeps microsecond precision while moving the zone", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00.123456+02:00")).toBe("2026-09-01T10:00:00.123456Z")
  })

  it("keeps nanosecond precision — the corpus carries fifteen of them", () => {
    // MEASURED 2026-09-06: 15 strings of the shape
    // NNNN-NN-NNTNN:NN:NN.NNNNNNNNN+NN:NN. Rounding to milliseconds here would
    // drop six digits of a recorded instant on a mirror.
    expect(normaliseTimestamps("2026-09-01T12:00:00.123456789+02:00")).toBe("2026-09-01T10:00:00.123456789Z")
  })

  it("gives a fraction-less UTC timestamp the canonical .000", () => {
    // MEASURED 2026-09-06: 4 strings of the shape NNNN-NN-NNTNN:NN:NNZ.
    expect(normaliseTimestamps("2026-09-01T12:00:00Z")).toBe("2026-09-01T12:00:00.000Z")
  })

  it("accepts the basic-format offset ±HHMM as well as ±HH:MM", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00+0200")).toBe("2026-09-01T10:00:00.000Z")
  })

  it("accepts a lower-case z", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00.500z")).toBe("2026-09-01T12:00:00.500Z")
  })
})

describe("normaliseIso8601 — the arithmetic crosses the boundaries it must", () => {
  it("crosses midnight backwards over a month end", () => {
    expect(normaliseTimestamps("2026-09-01T01:00:00+02:00")).toBe("2026-08-31T23:00:00.000Z")
  })

  it("crosses midnight forwards over a year end", () => {
    expect(normaliseTimestamps("2026-12-31T23:30:00-01:00")).toBe("2027-01-01T00:30:00.000Z")
  })

  it("handles the 29th of February in a leap year", () => {
    expect(normaliseTimestamps("2024-02-29T23:00:00+02:00")).toBe("2024-02-29T21:00:00.000Z")
  })

  it("handles a half-hour offset", () => {
    expect(normaliseTimestamps("2026-09-01T12:00:00+05:30")).toBe("2026-09-01T06:30:00.000Z")
  })

  it("does not fall into the two-digit-year trap of Date.UTC", () => {
    expect(normaliseTimestamps("0050-01-01T00:00:00Z")).toBe("0050-01-01T00:00:00.000Z")
  })
})

describe("normaliseIso8601 — what it declines, and why", () => {
  it("declines a string that merely contains a timestamp", () => {
    const prose = 'witnessed at 2026-08-29T07:09:49.888Z during the run'
    const r = normaliseIso8601(prose)
    expect(r.declined).toBe("not-a-date-time")
    expect(r.value).toBe(prose)
  })

  it("declines a zone-less date-time rather than reading it as UTC", () => {
    const r = normaliseIso8601("2026-09-01T12:00:00")
    expect(r.declined).toBe("no-zone")
    expect(r.value).toBe("2026-09-01T12:00:00")
  })

  it("declines the 31st of February rather than rolling it into March", () => {
    const r = normaliseIso8601("2026-02-31T12:00:00Z")
    expect(r.declined).toBe("not-a-calendar-date")
    expect(r.value).toBe("2026-02-31T12:00:00Z")
  })

  it("declines the 29th of February in a common year", () => {
    expect(normaliseIso8601("2026-02-29T12:00:00Z").declined).toBe("not-a-calendar-date")
  })

  it("declines a leap second and an end-of-day 24:00:00", () => {
    expect(normaliseIso8601("2026-06-30T23:59:60Z").declined).toBe("not-a-calendar-date")
    expect(normaliseIso8601("2026-06-30T24:00:00Z").declined).toBe("not-a-calendar-date")
  })

  it("declines a month or an offset out of range", () => {
    expect(normaliseIso8601("2026-13-01T12:00:00Z").declined).toBe("not-a-calendar-date")
    expect(normaliseIso8601("2026-09-01T12:00:00+24:00").declined).toBe("not-a-calendar-date")
  })

  it("leaves an ordinary string exactly as it is", () => {
    for (const s of ["", "sha256:abc", "2026-09-01", "T", "null"]) {
      expect(normaliseTimestamps(s)).toBe(s)
    }
  })
})

describe("canonicalFraction", () => {
  it("pads to three and never truncates", () => {
    expect(canonicalFraction(undefined)).toBe("000")
    expect(canonicalFraction("")).toBe("000")
    expect(canonicalFraction("5")).toBe("500")
    expect(canonicalFraction("888")).toBe("888")
    expect(canonicalFraction("123456")).toBe("123456")
  })

  it("removes trailing zeros but not below three digits", () => {
    expect(canonicalFraction("8880")).toBe("888")
    expect(canonicalFraction("1000")).toBe("100")
    expect(canonicalFraction("000")).toBe("000")
    expect(canonicalFraction("0000000")).toBe("000")
    expect(canonicalFraction("1234560")).toBe("123456")
  })

  it("is idempotent", () => {
    for (const d of ["", "5", "50", "888", "8880", "0000", "123456", "1234560"]) {
      expect(canonicalFraction(canonicalFraction(d))).toBe(canonicalFraction(d))
    }
  })
})

describe("carriesNonUtcZone — the reading the fixture tool takes over its output", () => {
  it("is true of an offset timestamp and false of a UTC one", () => {
    expect(carriesNonUtcZone("2026-09-01T12:00:00+02:00")).toBe(true)
    expect(carriesNonUtcZone("2026-09-01T12:00:00.000Z")).toBe(false)
  })

  it("is false of prose and of a zone-less date-time", () => {
    expect(carriesNonUtcZone("ran at 2026-09-01T12:00:00+02:00")).toBe(false)
    expect(carriesNonUtcZone("2026-09-01T12:00:00")).toBe(false)
  })

  it("is false of everything normaliseTimestamps returns", () => {
    fc.assert(
      fc.property(arbitraryTimestamp(), (s) => {
        expect(carriesNonUtcZone(normaliseTimestamps(s))).toBe(false)
      }),
      { numRuns: 500 }
    )
  })
})

/** An arbitrary zoned ISO-8601 date-time, over the whole calendar. */
const arbitraryTimestamp = (): fc.Arbitrary<string> =>
  fc
    .record({
      y: fc.integer({ min: 1, max: 9999 }),
      mo: fc.integer({ min: 1, max: 12 }),
      d: fc.integer({ min: 1, max: 28 }),
      h: fc.integer({ min: 0, max: 23 }),
      mi: fc.integer({ min: 0, max: 59 }),
      s: fc.integer({ min: 0, max: 59 }),
      frac: fc.option(fc.stringMatching(/^[0-9]{1,9}$/), { nil: undefined }),
      zone: fc.oneof(
        fc.constant("Z"),
        fc.constant("z"),
        fc.record({
          sign: fc.constantFrom("+", "-"),
          oh: fc.integer({ min: 0, max: 23 }),
          om: fc.constantFrom(0, 15, 30, 45)
        }).map(({ oh, om, sign }) => `${sign}${pad(oh)}:${pad(om)}`)
      )
    })
    .map(({ d, frac, h, mi, mo, s, y, zone }) => {
      const f = frac === undefined ? "" : `.${frac}`
      return `${`${y}`.padStart(4, "0")}-${pad(mo)}-${pad(d)}T${pad(h)}:${pad(mi)}:${pad(s)}${f}${zone}`
    })

const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`)

describe("normaliseIso8601 — the properties, over the whole calendar", () => {
  it("is idempotent", () => {
    fc.assert(
      fc.property(arbitraryTimestamp(), (s) => {
        const once = normaliseTimestamps(s)
        expect(normaliseTimestamps(once)).toBe(once)
      }),
      { numRuns: 1000 }
    )
  })

  it("always produces the canonical shape, and never declines a zoned date-time", () => {
    fc.assert(
      fc.property(arbitraryTimestamp(), (s) => {
        const r = normaliseIso8601(s)
        expect(r.declined).toBe(null)
        expect(r.value).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,}Z$/)
      }),
      { numRuns: 1000 }
    )
  })

  it("preserves the instant: the normalised form parses to the same epoch millisecond", () => {
    fc.assert(
      fc.property(arbitraryTimestamp(), (s) => {
        expect(Date.parse(normaliseTimestamps(s))).toBe(Date.parse(s))
      }),
      { numRuns: 1000 }
    )
  })

  it("agrees with the host's own UTC renderer on every millisecond timestamp", () => {
    // `Date.prototype.toISOString` is defined in UTC and reads no ambient zone,
    // so agreeing with it on the whole generated calendar is a cross-check of
    // this file's arithmetic against an implementation it does not share code
    // with — and, because neither side can see the box's TZ, a reading that
    // the normalisation is pure.
    fc.assert(
      fc.property(arbitraryTimestamp(), (s) => {
        const ours = normaliseTimestamps(s)
        // The host's parser is strict about the case of the zone designator;
        // this file is not, so the lower-case `z` is spelled up for it.
        const theirs = new Date(s.replace(/z$/, "Z")).toISOString()
        // toISOString always writes exactly three fractional digits; ours keeps
        // every digit the input carried, so the two agree on the first 23
        // characters and ours may carry more.
        expect(ours.slice(0, 23)).toBe(theirs.slice(0, 23))
        expect(ours.endsWith("Z")).toBe(true)
      }),
      { numRuns: 1000 }
    )
  })
})
