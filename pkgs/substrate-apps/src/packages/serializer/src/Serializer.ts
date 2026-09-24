/**
 * Serializer.ts — U-A12 LAKE-SERIALIZER. The deterministic serializer.
 *
 * §2.2e names four properties and this file is all four:
 *
 *   1. STABLE KEY ORDER — sorted, not insertion. Every object's keys are
 *      emitted in ascending UTF-16 code-unit order, recursively. Arrays keep
 *      their order, because in an array the order IS the data.
 *   2. LF — the only newline this file can emit is the `\n` between rows.
 *      JSON escapes every control character inside a string, so a CR in the
 *      data is written `\r` and never reaches the byte stream raw.
 *   3. TRAILING NEWLINE — a non-empty output ends with exactly one `\n`.
 *   4. ISO-8601 UTC — every string that is a zoned ISO-8601 date-time is
 *      re-emitted in UTC (`Iso8601.ts` carries that rule in full).
 *
 * Why "sorted, not insertion" is a real property and not a taste:
 *
 *   JSON.parse('{"10":1,"2":1}') enumerates as ["2","10"], because integer-like
 *   keys are read out in ascending numeric order ahead of every other key. The
 *   parsed object's key order is therefore already NOT the source order, and it
 *   depends on what the keys happen to spell. A serializer that follows
 *   insertion order is a serializer whose output depends on an accident of the
 *   input's spelling. Sorting removes the accident, and that is exactly what
 *   the unit's `mutation_hint` breaks: with the sort removed, this repository's
 *   own fixture tool produces two different files from two byte-equal corpora
 *   that differ only in the order their keys were written.
 *
 * WHY EVERY UNSUPPORTED VALUE THROWS. `JSON.stringify` drops `undefined`, a
 * function and a symbol from an object silently, renders them as `null` inside
 * an array, and calls `toJSON` on a `Date`. Each of those is a place where the
 * output stops being a function of the input in a way nobody sees. This file
 * refuses all of them by name and by path (`$.a.b[3]`), so a wrong value is a
 * loud failure at the row that carries it and never a quiet difference in the
 * fixture.
 *
 * The function is pure: it reads no clock, no locale, no environment and no
 * ambient time zone, and it mutates nothing it is given.
 */
import { carriesNonUtcZone, normaliseTimestamps } from "./Iso8601.ts"

/** Thrown when a value cannot be serialized. Carries the path that carried it. */
export class SerializeError extends Error {
  readonly path: string
  constructor(path: string, why: string) {
    super(`${path}: ${why}`)
    this.name = "SerializeError"
    this.path = path
  }
}

/** Ascending UTF-16 code-unit order. Explicit, so no locale can reach it. */
export const compareKeys = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0)

const isPlainObject = (v: object): boolean => {
  const proto = Object.getPrototypeOf(v)
  return proto === Object.prototype || proto === null
}

const describe = (v: unknown): string => {
  if (v === undefined) return "undefined"
  if (typeof v === "function") return "a function"
  if (typeof v === "symbol") return "a symbol"
  if (typeof v === "bigint") return "a bigint"
  if (typeof v === "number") return Number.isNaN(v) ? "NaN" : `${v}`
  if (v instanceof Date) return "a Date (pass an ISO-8601 string instead)"
  if (Array.isArray(v)) return "an array"
  if (v !== null && typeof v === "object") {
    const name = v.constructor?.name
    return name !== undefined && name !== "Object" ? `a ${name}` : "an object"
  }
  return typeof v
}

/**
 * How keys are ordered when a record is serialized. `sorted` is the contract;
 * `insertion` exists so the negative control can be *run* rather than asserted
 * — CONTRIBUTING.md §2 rule 5, "a green that cannot go red is vacuous". No
 * caller in this repository passes `insertion` outside a control.
 */
type KeyOrder = "sorted" | "insertion"

interface SerializeOptions {
  /** Default `"sorted"`. See `KeyOrder`. */
  readonly keyOrder?: KeyOrder
  /** Default `true`. `false` is a negative control: it disables property 4. */
  readonly normaliseTimestamps?: boolean
}

const orderedKeys = (o: Record<string, unknown>, order: KeyOrder): Array<string> => {
  const keys = Object.keys(o)
  return order === "sorted" ? keys.sort(compareKeys) : keys
}

/**
 * Serialize one decoded record to its canonical single-line form. No trailing
 * newline: `serializeLine` adds it, `serializeRecords` adds one per row.
 *
 * @throws SerializeError on any value JSON cannot carry, on a non-finite
 * number, and on a cycle — each naming the path.
 */
export const serializeValue = (value: unknown, options: SerializeOptions = {}): string => {
  const keyOrder = options.keyOrder ?? "sorted"
  const doTimestamps = options.normaliseTimestamps ?? true
  // A cycle is detected by the set of ancestors on the current branch, not by
  // every object ever seen: the same object appearing twice side by side is a
  // DAG, which serializes fine, and only a self-reference is a cycle.
  const ancestors = new Set<object>()

  const go = (v: unknown, path: string): string => {
    if (v === null) return "null"

    switch (typeof v) {
      case "boolean":
        return v ? "true" : "false"
      case "number":
        if (!Number.isFinite(v)) throw new SerializeError(path, `${describe(v)} is not a JSON number`)
        // -0 and 0 are the same JSON number; JSON.stringify already writes
        // both as "0". Named here so the equality is a decision, not a
        // coincidence of the host.
        return Object.is(v, -0) ? "0" : JSON.stringify(v)
      case "string":
        return JSON.stringify(doTimestamps ? normaliseTimestamps(v) : v)
      case "object":
        break
      default:
        throw new SerializeError(path, `${describe(v)} cannot be serialized`)
    }

    const o = v as object
    if (ancestors.has(o)) throw new SerializeError(path, "a cycle: this value contains itself")
    ancestors.add(o)
    try {
      if (Array.isArray(o)) {
        const parts = new Array<string>(o.length)
        for (let i = 0; i < o.length; i++) {
          // A hole in a sparse array reads as undefined; JSON.stringify would
          // write it "null". Refuse it: a hole is not data.
          if (!(i in o)) throw new SerializeError(`${path}[${i}]`, "a hole in a sparse array")
          parts[i] = go(o[i], `${path}[${i}]`)
        }
        return `[${parts.join(",")}]`
      }
      if (!isPlainObject(o)) throw new SerializeError(path, `${describe(o)} cannot be serialized`)

      const rec = o as Record<string, unknown>
      const parts: Array<string> = []
      for (const k of orderedKeys(rec, keyOrder)) {
        const kp = `${path}.${k}`
        const child = rec[k]
        if (child === undefined) {
          throw new SerializeError(kp, "undefined: JSON.stringify would drop this key silently")
        }
        // A key is a name, not a value: it is never read as a timestamp.
        parts.push(`${JSON.stringify(k)}:${go(child, kp)}`)
      }
      return `{${parts.join(",")}}`
    } finally {
      ancestors.delete(o)
    }
  }

  return go(value, "$")
}

/** One record, one line, terminated by LF. */
export const serializeLine = (value: unknown, options: SerializeOptions = {}): string =>
  `${serializeValue(value, options)}\n`

/**
 * Many records, one per line, LF-terminated, with the trailing newline that
 * property 3 requires. An empty sequence serializes to the empty string: a
 * file that is one bare newline would claim a row that is not there.
 */
export const serializeRecords = (
  records: Iterable<unknown>,
  options: SerializeOptions = {}
): string => {
  let out = ""
  for (const r of records) out += serializeLine(r, options)
  return out
}

// --- assertions over the OUTPUT ----------------------------------------------
// The four properties, re-measured on the bytes rather than trusted to the code
// above. The fixture tool runs these over its whole output, so the oracle's
// green is a reading and not a claim.

interface OutputProblem {
  readonly property: "LF" | "trailing-newline" | "ISO-8601-UTC" | "round-trip"
  readonly row: number
  readonly detail: string
}

/** Property 2 and 3, over a whole serialized blob. */
export const checkLineDiscipline = (text: string): Array<OutputProblem> => {
  const problems: Array<OutputProblem> = []
  const cr = text.indexOf("\r")
  if (cr !== -1) {
    const row = text.slice(0, cr).split("\n").length
    problems.push({ property: "LF", row, detail: `a raw CR byte at offset ${cr}` })
  }
  if (text.length > 0) {
    if (!text.endsWith("\n")) {
      problems.push({ property: "trailing-newline", row: -1, detail: "the output does not end with LF" })
    } else if (text.endsWith("\n\n")) {
      problems.push({ property: "trailing-newline", row: -1, detail: "the output ends with a blank row" })
    }
  }
  return problems
}

/**
 * Property 1 and 4, over one emitted row: it re-parses, it re-serializes to
 * itself (so the transform is idempotent and the order really is a function of
 * the content), and it carries no timestamp still bearing a non-UTC zone.
 */
export const checkRow = (line: string, row: number): Array<OutputProblem> => {
  const problems: Array<OutputProblem> = []
  let back: unknown
  try {
    back = JSON.parse(line)
  } catch (e) {
    problems.push({ property: "round-trip", row, detail: `does not re-parse: ${(e as Error).message}` })
    return problems
  }
  const again = serializeValue(back)
  if (again !== line) {
    problems.push({ property: "round-trip", row, detail: "re-serializing the row does not reproduce it" })
  }
  for (const s of stringsOf(back)) {
    if (carriesNonUtcZone(s)) {
      problems.push({ property: "ISO-8601-UTC", row, detail: `a timestamp still carries an offset: ${s}` })
    }
  }
  return problems
}

/** Every string value in a decoded record. Keys are names and are not visited. */
export function* stringsOf(value: unknown): Generator<string> {
  if (typeof value === "string") {
    yield value
    return
  }
  if (value === null || typeof value !== "object") return
  if (Array.isArray(value)) {
    for (const v of value) yield* stringsOf(v)
    return
  }
  for (const v of Object.values(value as Record<string, unknown>)) yield* stringsOf(v)
}
