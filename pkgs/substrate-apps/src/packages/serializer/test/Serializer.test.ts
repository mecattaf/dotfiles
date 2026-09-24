/**
 * Serializer.test.ts — U-A12. Properties 1, 2 and 3, and the refusals.
 */
import fc from "fast-check"
import { describe, expect, it } from "vitest"
import {
  checkLineDiscipline,
  checkRow,
  compareKeys,
  keyOrderOf,
  SerializeError,
  serializeLine,
  serializeRecords,
  serializeValue,
  stringsOf,
  withReversedKeyOrder
} from "../src/index.ts"

describe("property 1 — stable key order, sorted and not insertion", () => {
  it("sorts the keys of a flat object", () => {
    expect(serializeValue({ b: 1, a: 2, C: 3 })).toBe('{"C":3,"a":2,"b":1}')
  })

  it("sorts recursively, and leaves array order alone", () => {
    const v = { z: { y: 1, x: 2 }, a: [{ q: 1, p: 2 }, 3] }
    expect(serializeValue(v)).toBe('{"a":[{"p":2,"q":1},3],"z":{"x":2,"y":1}}')
  })

  it("sorts by UTF-16 code unit, so upper case precedes lower and digits precede both", () => {
    expect(serializeValue({ a: 0, A: 0, "1": 0, _: 0 })).toBe('{"1":0,"A":0,"_":0,"a":0}')
  })

  it("is blind to the order the keys were written in", () => {
    expect(serializeValue({ a: 1, b: 2 })).toBe(serializeValue({ b: 2, a: 1 }))
  })

  it("is blind to the reversal, which is the assertion the fixture tool makes", () => {
    const record = { seat: "x", id: "y", nested: { b: 1, a: 2 } }
    expect(serializeValue(withReversedKeyOrder(record))).toBe(serializeValue(record))
  })

  it("the reversal really reverses — the control is not vacuous", () => {
    // If `withReversedKeyOrder` were the identity, the assertion above would
    // hold for an insertion-order serializer too, and would prove nothing.
    const record = { a: 1, b: 2, c: 3 }
    expect(keyOrderOf(record)).toEqual(["a", "b", "c"])
    expect(keyOrderOf(withReversedKeyOrder(record))).toEqual(["c", "b", "a"])
    expect(serializeValue(withReversedKeyOrder(record), { keyOrder: "insertion" })).toBe('{"c":3,"b":2,"a":1}')
    expect(serializeValue(record, { keyOrder: "insertion" })).toBe('{"a":1,"b":2,"c":3}')
  })

  it("the permutation is descending order, so it is idempotent and not an involution", () => {
    // It puts the keys in the exact reverse of the contract's order, whatever
    // order they arrived in — which is what makes it the strongest single
    // permutation available and what makes the assertion above reproducible
    // from any input.
    const record = { b: 2, a: 1, c: 3 }
    expect(keyOrderOf(withReversedKeyOrder(record))).toEqual(["c", "b", "a"])
    expect(keyOrderOf(withReversedKeyOrder(withReversedKeyOrder(record)))).toEqual(["c", "b", "a"])
  })

  it("the host already reorders integer-like keys, which is why insertion order is not a contract", () => {
    const parsed = JSON.parse('{"10":1,"2":2,"b":3,"a":4}') as Record<string, unknown>
    expect(keyOrderOf(parsed)).toEqual(["2", "10", "b", "a"])
    expect(serializeValue(parsed)).toBe('{"10":1,"2":2,"a":4,"b":3}')
  })

  it("compareKeys is a total order and reads no locale", () => {
    expect(compareKeys("a", "b")).toBe(-1)
    expect(compareKeys("b", "a")).toBe(1)
    expect(compareKeys("a", "a")).toBe(0)
    // In many locales "ä" collates next to "a"; by code unit it does not.
    expect(compareKeys("z", "ä")).toBe(-1)
  })
})

describe("property 2 — LF, and only LF", () => {
  it("escapes a newline and a carriage return inside a string", () => {
    const line = serializeLine({ s: "a\r\nb" })
    expect(line).toBe('{"s":"a\\r\\nb"}\n')
    expect(line.indexOf("\r")).toBe(-1)
    expect(line.split("\n")).toHaveLength(2)
  })

  it("emits one LF per record and nothing else", () => {
    const text = serializeRecords([{ a: 1 }, { b: 2 }, { c: "x\ny" }])
    expect(text.split("\n").filter((l) => l !== "")).toHaveLength(3)
    expect(checkLineDiscipline(text)).toEqual([])
  })

  it("checkLineDiscipline reports a raw CR", () => {
    const problems = checkLineDiscipline('{"a":1}\r\n')
    expect(problems.map((p) => p.property)).toContain("LF")
  })
})

describe("property 3 — the trailing newline", () => {
  it("ends a non-empty output with exactly one LF", () => {
    const text = serializeRecords([{ a: 1 }, { b: 2 }])
    expect(text.endsWith("\n")).toBe(true)
    expect(text.endsWith("\n\n")).toBe(false)
  })

  it("serializes an empty sequence to the empty string, not to a bare newline", () => {
    expect(serializeRecords([])).toBe("")
    expect(checkLineDiscipline("")).toEqual([])
  })

  it("checkLineDiscipline reports a missing terminator and a blank last row", () => {
    expect(checkLineDiscipline('{"a":1}').map((p) => p.property)).toContain("trailing-newline")
    expect(checkLineDiscipline('{"a":1}\n\n').map((p) => p.property)).toContain("trailing-newline")
  })
})

describe("scalars", () => {
  it("writes null, booleans and numbers as JSON does", () => {
    expect(serializeValue(null)).toBe("null")
    expect(serializeValue(true)).toBe("true")
    expect(serializeValue(false)).toBe("false")
    expect(serializeValue(0)).toBe("0")
    expect(serializeValue(-1.5)).toBe("-1.5")
    expect(serializeValue(1e21)).toBe("1e+21")
  })

  it("writes -0 as 0, so the two are one JSON number and not two", () => {
    expect(serializeValue(-0)).toBe("0")
    expect(serializeValue({ a: -0 })).toBe(serializeValue({ a: 0 }))
  })

  it("escapes strings as JSON does", () => {
    expect(serializeValue("\u0000\t\"\\")).toBe('"\\u0000\\t\\"\\\\"')
    expect(serializeValue("é😀")).toBe('"é😀"')
  })

  it("carries an own __proto__ key through as data, the way JSON.parse hands it over", () => {
    const parsed = JSON.parse('{"__proto__":{"x":1},"a":2}') as Record<string, unknown>
    expect(Object.keys(parsed)).toEqual(["__proto__", "a"])
    expect(serializeValue(parsed)).toBe('{"__proto__":{"x":1},"a":2}')
    expect(serializeValue(withReversedKeyOrder(parsed))).toBe('{"__proto__":{"x":1},"a":2}')
  })
})

describe("the refusals — every place JSON.stringify would drop or invent a value", () => {
  const refuses = (v: unknown, needle: string) => {
    expect(() => serializeValue(v)).toThrow(SerializeError)
    expect(() => serializeValue(v)).toThrow(needle)
  }

  it("refuses undefined in an object, which JSON.stringify drops silently", () => {
    refuses({ a: 1, b: undefined }, "undefined")
    expect(JSON.stringify({ a: 1, b: undefined })).toBe('{"a":1}')
  })

  it("refuses undefined in an array, which JSON.stringify writes as null", () => {
    refuses([1, undefined], "cannot be serialized")
    expect(JSON.stringify([1, undefined])).toBe("[1,null]")
  })

  it("refuses a hole in a sparse array", () => {
    const sparse = [1]
    sparse[2] = 3
    refuses(sparse, "a hole in a sparse array")
  })

  it("refuses NaN and the infinities, which JSON.stringify writes as null", () => {
    refuses(Number.NaN, "NaN is not a JSON number")
    refuses(Number.POSITIVE_INFINITY, "not a JSON number")
    refuses(Number.NEGATIVE_INFINITY, "not a JSON number")
  })

  it("refuses a Date, and says what to pass instead", () => {
    refuses(new Date(0), "ISO-8601 string")
  })

  it("refuses a function, a symbol, a bigint, a Map and a Set", () => {
    refuses({ f: () => 1 }, "a function")
    refuses({ s: Symbol("s") }, "a symbol")
    refuses({ n: 1n }, "a bigint")
    refuses({ m: new Map() }, "a Map")
    refuses({ s: new Set() }, "a Set")
  })

  it("refuses a cycle and names the path", () => {
    const a: Record<string, unknown> = { name: "a" }
    a.self = a
    expect(() => serializeValue(a)).toThrow("$.self: a cycle")
  })

  it("accepts the same object twice side by side, which is a DAG and not a cycle", () => {
    const shared = { k: 1 }
    expect(serializeValue({ a: shared, b: shared })).toBe('{"a":{"k":1},"b":{"k":1}}')
  })

  it("names the path of the value it refuses", () => {
    expect(() => serializeValue({ a: [{ b: Number.NaN }] })).toThrow("$.a[0].b")
  })
})

describe("property 4 in place — timestamps inside a record", () => {
  it("normalises a value and never a key", () => {
    expect(serializeValue({ "2026-09-01T12:00:00+02:00": "2026-09-01T12:00:00+02:00" })).toBe(
      '{"2026-09-01T12:00:00+02:00":"2026-09-01T10:00:00.000Z"}'
    )
  })

  it("normalises inside arrays and nested objects", () => {
    expect(serializeValue({ a: ["2026-09-01T12:00:00+02:00"], b: { c: "2026-09-01T12:00:00+02:00" } })).toBe(
      '{"a":["2026-09-01T10:00:00.000Z"],"b":{"c":"2026-09-01T10:00:00.000Z"}}'
    )
  })

  it("can be switched off, which is the negative control the fixture tool runs", () => {
    expect(serializeValue({ t: "2026-09-01T12:00:00+02:00" }, { normaliseTimestamps: false })).toBe(
      '{"t":"2026-09-01T12:00:00+02:00"}'
    )
  })
})

describe("checkRow — the reading the fixture tool takes over each emitted row", () => {
  it("passes a canonical row", () => {
    expect(checkRow(serializeValue({ b: 1, a: "2026-09-01T12:00:00+02:00" }), 1)).toEqual([])
  })

  it("fails a row that does not re-parse", () => {
    expect(checkRow("{not json", 1).map((p) => p.property)).toEqual(["round-trip"])
  })

  it("fails a row whose keys are not sorted", () => {
    const line = serializeValue({ b: 1, a: 2 }, { keyOrder: "insertion" })
    expect(line).toBe('{"b":1,"a":2}')
    expect(checkRow(line, 1).map((p) => p.property)).toEqual(["round-trip"])
  })

  it("fails a row that still carries an offset timestamp", () => {
    const line = serializeValue({ t: "2026-09-01T12:00:00+02:00" }, { normaliseTimestamps: false })
    expect(checkRow(line, 7).map((p) => p.property)).toContain("ISO-8601-UTC")
  })
})

describe("stringsOf", () => {
  it("yields every string value and no key", () => {
    expect([...stringsOf({ k: "v", n: 1, a: ["x", { j: "y" }] })]).toEqual(["v", "x", "y"])
  })
})

// --- the properties, over generated records ----------------------------------

/**
 * An arbitrary decoded record: exactly the values JSON.parse can produce.
 *
 * The keys are drawn from a small alphabet that includes digits, so the
 * host's integer-like-key reordering is exercised, and includes upper and
 * lower case, so a code-unit order and a locale order disagree. `__proto__` is
 * covered by its own test above rather than here: an object *literal* cannot
 * carry it as an own property, so a generator cannot produce the shape
 * `JSON.parse` produces.
 */
const jsonKey = fc.stringMatching(/^[0-9A-Za-z_]{0,4}$/)

const jsonValue = fc.letrec<{ v: unknown }>((tie) => ({
  v: fc.oneof(
    { maxDepth: 4 },
    fc.constant(null),
    fc.boolean(),
    fc.double({ noNaN: true, noDefaultInfinity: true }),
    fc.integer(),
    fc.string(),
    fc.array(tie("v"), { maxLength: 5 }),
    fc.dictionary(jsonKey, tie("v"), { maxKeys: 6 })
  )
})).v

describe("the properties, over generated records", () => {
  it("is deterministic: the same record serializes to the same bytes", () => {
    fc.assert(
      fc.property(jsonValue, (v) => {
        expect(serializeValue(v)).toBe(serializeValue(v))
      }),
      { numRuns: 500 }
    )
  })

  it("is blind to key order: a record and its reversal serialize alike", () => {
    fc.assert(
      fc.property(jsonValue, (v) => {
        expect(serializeValue(withReversedKeyOrder(v))).toBe(serializeValue(v))
      }),
      { numRuns: 1000 }
    )
  })

  it("is idempotent: re-parsing the output and serializing it again reproduces it", () => {
    fc.assert(
      fc.property(jsonValue, (v) => {
        const once = serializeValue(v)
        expect(serializeValue(JSON.parse(once))).toBe(once)
      }),
      { numRuns: 1000 }
    )
  })

  it("emits valid JSON that decodes to the same value JSON.parse would give", () => {
    fc.assert(
      fc.property(jsonValue, (v) => {
        expect(JSON.parse(serializeValue(v))).toStrictEqual(JSON.parse(JSON.stringify(v)))
      }),
      { numRuns: 1000 }
    )
  })

  it("every emitted row passes checkRow, and a corpus of them passes checkLineDiscipline", () => {
    fc.assert(
      fc.property(fc.array(jsonValue, { maxLength: 12 }), (vs) => {
        const text = serializeRecords(vs)
        expect(checkLineDiscipline(text)).toEqual([])
        const lines = text === "" ? [] : text.slice(0, -1).split("\n")
        expect(lines).toHaveLength(vs.length)
        lines.forEach((l, i) => expect(checkRow(l, i + 1)).toEqual([]))
      }),
      { numRuns: 300 }
    )
  })
})
